#!/usr/bin/env python3
"""
scripts/hw_test.py — Bộ kiểm chứng trên phần cứng thật (mức L3)
================================================================
REQ: REQ-P-01..04, REQ-V-03, REQ-V-04 · TEST_PLAN: TC-600..606
Ngày: 2026-09-10

CHẠY BẰNG /usr/bin/python3, KHÔNG dùng `python3`
   Sau khi `source ~/tools/oss-cad-suite/environment`, `python3` bị thay bằng
   bản 3.11 riêng của toolchain, không có pyserial.

CỔNG: /dev/ttyUSB1
   FT2232 có hai kênh. ttyUSB0 là JTAG (dùng để nạp bitstream), ttyUSB1 mới là
   UART. Đọc nhầm kênh sẽ ra dữ liệu rác trông y hệt lỗi giao thức.

NGUYÊN TẮC REQ-V-04 — MỌI TEST "TỪ CHỐI" ĐỀU CHẠY HAI PHA
   Pha A — kích thích tiêu cực, kỳ vọng im lặng
   Pha B — khung hợp lệ ngay sau đó, kỳ vọng phản hồi ĐÚNG   ← bằng chứng sống
   Test chỉ có pha A là KHÔNG HỢP LỆ: nó vẫn PASS khi FPGA đã chết hoàn toàn.
   Đây là lỗi thật đã gặp ở thiết kế trước.
"""

import argparse
import hashlib
import os
import statistics
import sys
import time

try:
    import serial
except ImportError:
    sys.exit("[ERROR] can pyserial:  /usr/bin/pip3 install --user pyserial\n"
             "        (chay bang /usr/bin/python3, khong phai python3 cua oss-cad-suite)")

try:
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
except ImportError:
    sys.exit("[ERROR] can thu vien `cryptography` de tinh gia tri ky vong")


# ─────────────────────── giao thức ───────────────────────
PREAMBLE = b"\xA5\x5A"

# PHẢI khớp rtl/config/keys.vh. Khóa ví dụ công khai từ NIST SP 800-38A F.5.5 —
# xem SRS §10.1 về giới hạn "khóa nạp cứng".
KEY = bytes.fromhex(
    "603deb1015ca71be2b73aef0857d7781" "1f352c073b6108d72d9810a30914dff4")


def aes_ctr(data: bytes, iv: bytes) -> bytes:
    """AES-256-CTR. Đối xứng: dùng cho cả mã hóa và giải mã."""
    enc = Cipher(algorithms.AES(KEY), modes.ECB()).encryptor()
    n = int.from_bytes(iv, "big")
    out = bytearray()
    for i in range((len(data) + 15) // 16):
        ks = enc.update(((n + i) % (1 << 128)).to_bytes(16, "big"))
        blk = data[16 * i:16 * i + 16]
        out += bytes(a ^ b for a, b in zip(blk, ks))
    return bytes(out)


def build_frame(payload: bytes, iv: bytes) -> bytes:
    hdr = len(payload).to_bytes(2, "big") + iv
    digest = hashlib.sha256(hdr + payload).digest()
    return PREAMBLE + hdr + payload + digest


def expected_reply(payload: bytes, iv: bytes) -> bytes:
    ct = aes_ctr(payload, iv)
    hdr = len(payload).to_bytes(2, "big") + iv
    return PREAMBLE + hdr + ct + hashlib.sha256(hdr + ct).digest()


# ─────────────────────── tiện ích ───────────────────────
class Res:
    def __init__(self):
        self.ok = 0
        self.bad = 0

    def check(self, cond, msg, detail=""):
        if cond:
            self.ok += 1
            print(f"  [ok]   {msg}")
        else:
            self.bad += 1
            print(f"  [FAIL] {msg}" + (f"\n         {detail}" if detail else ""))
        return bool(cond)

    def finish(self, name):
        print("-" * 62)
        print(f"  {name}:  PASS {self.ok}   FAIL {self.bad}")
        if self.bad:
            print("  KET QUA: FAIL")
            sys.exit(1)
        print("  KET QUA: PASS")
        sys.exit(0)


def read_exact(ser, n, deadline_s):
    buf = bytearray()
    end = time.time() + deadline_s
    while len(buf) < n and time.time() < end:
        chunk = ser.read(n - len(buf))
        if chunk:
            buf += chunk
    return bytes(buf)


def drain(ser, seconds=0.25):
    end = time.time() + seconds
    got = bytearray()
    while time.time() < end:
        c = ser.read(4096)
        if c:
            got += c
    return bytes(got)


def exchange(ser, payload, iv, timeout=2.0):
    """Gửi một khung hợp lệ, đọc phản hồi. Trả (bytes, giây)."""
    reply_len = len(expected_reply(payload, iv))
    ser.reset_input_buffer()
    t0 = time.time()
    ser.write(build_frame(payload, iv))
    ser.flush()
    got = read_exact(ser, reply_len, timeout)
    return got, time.time() - t0


def rand_payload(n):
    return os.urandom(n)


# ═════════════════════ TC-600: đường ống UART trần ═════════════════════
def mode_uartloop(ser, args):
    """GATE CỨNG CỦA WP-01 — cần bitstream rtl/probe/uart_echo_top.v."""
    r = Res()
    n = args.bytes
    payload = bytes((i * 7 + 0x5A) & 0xFF for i in range(n))

    print(f"  Gui {n} byte lien tuc, khong nghi giua cac byte...")
    ser.reset_input_buffer()
    t0 = time.time()
    ser.write(payload)
    ser.flush()
    got = read_exact(ser, n, n * 10.0 / args.baud + 3.0)
    dt = time.time() - t0

    lost = n - len(got)
    print(f"  Nhan lai {len(got)}/{n} byte trong {dt*1000:.1f} ms")
    r.check(lost == 0, f"TC-600a: khong mat byte nao (mat {lost})",
            "Neu mat byte -> REQ-I-05 KHONG dat. Xem ADR-0005.")
    if got:
        bad = next((i for i in range(min(len(got), n)) if got[i] != payload[i]), None)
        r.check(bad is None, "TC-600b: noi dung vong lai dung tung byte",
                f"byte dau tien sai o vi tri {bad}" if bad is not None else "")
    r.finish("TC-600 (WP-01 gate)")


# ═════════════════════ TC-601: một khung khứ hồi ═════════════════════
def mode_echo(ser, args):
    r = Res()
    payload = rand_payload(args.len)
    iv = os.urandom(16)
    exp = expected_reply(payload, iv)

    print(f"  Gui mot khung {args.len} byte payload...")
    got, dt = exchange(ser, payload, iv)
    print(f"  Nhan {len(got)}/{len(exp)} byte trong {dt*1000:.2f} ms")

    if not r.check(len(got) == len(exp), "TC-601a: nhan du so byte",
                   f"nhan {len(got)}, mong doi {len(exp)}"):
        r.finish("TC-601")

    r.check(got[:2] == PREAMBLE, "TC-601b: preamble tra ve")
    r.check(got[2:4] == len(payload).to_bytes(2, "big"), "TC-601c: LEN tra ve")
    r.check(got[4:20] == iv, "TC-601d: IV tra ve")

    ct = got[20:20 + len(payload)]
    r.check(ct == aes_ctr(payload, iv), "TC-601e: ban ma AES-256-CTR dung",
            f"nhan {ct.hex()[:32]}...")

    dg = got[20 + len(payload):]
    hdr = len(payload).to_bytes(2, "big") + iv
    r.check(dg == hashlib.sha256(hdr + ct).digest(), "TC-601f: digest tra ve dung")

    # Giải mã lại: CTR đối xứng nên cùng hàm cho ra bản rõ ban đầu
    r.check(aes_ctr(ct, iv) == payload,
            "TC-601g: giai ma ban ma nhan duoc -> dung ban ro goc")

    r.finish("TC-601")


# ═════════════════════ TC-601s: quét độ dài payload ═════════════════════
def mode_sweep(ser, args):
    """
    Quét các độ dài payload, đặc biệt là các giá trị BIÊN.

    Vì sao cần: lỗi cắt bit chỉ lộ ra ở đúng một giá trị. LEN = 512 (bit thứ 9)
    bị `len[AW-1:0]` với AW = 9 cắt mất thành 0, làm khung 512 byte luôn bị loại
    trong khi 128 byte chạy hoàn hảo. Một test chỉ thử một độ dài sẽ không bao
    giờ thấy. Xem DEVELOPMENT_BOOK §WP-07.
    """
    r = Res()
    lengths = [1, 2, 15, 16, 17, 31, 32, 33, 63, 64, 65,
               127, 128, 129, 255, 256, 257, 511, 512]
    bad = []
    for n in lengths:
        payload = rand_payload(n)
        iv = os.urandom(16)
        got, dt = exchange(ser, payload, iv, timeout=3.0)
        exp = expected_reply(payload, iv)
        mark = "ok " if got == exp else "SAI"
        if got != exp:
            bad.append(n)
        print(f"    LEN={n:4d}  {mark}  {len(got):4d}/{len(exp):4d} byte  {dt*1000:7.2f} ms")
    r.check(not bad, f"TC-601s: tat ca {len(lengths)} do dai deu dung",
            f"sai o LEN = {bad}")

    # Bien ngoai pham vi: phai bi loai
    for n, tag in ((0, "LEN = 0"), (1024, "LEN = 1024")):
        ser.reset_input_buffer()
        body = (n.to_bytes(2, "big") + os.urandom(16) + os.urandom(16)
                + hashlib.sha256(b"x").digest())
        ser.write(PREAMBLE + body)
        ser.flush()
        got = drain(ser, 0.8)
        r.check(len(got) == 0, f"TC-601s: {tag} -> bi loai (REQ-F-21)",
                f"nhan {len(got)} byte")

    _phase_b_liveness(ser, r, "TC-601s")
    r.finish("TC-601s (quet do dai)")


# ═════════════════════ TC-602: đo hiệu năng ═════════════════════
def mode_bench(ser, args):
    r = Res()
    n = args.frames
    plen = args.len
    lat, lost, total_bytes = [], 0, 0

    print(f"  Chay {n} khung x {plen} byte payload...")
    t_start = time.time()
    for i in range(n):
        payload = rand_payload(plen)
        iv = os.urandom(16)
        got, dt = exchange(ser, payload, iv)
        exp = expected_reply(payload, iv)
        if got == exp:
            lat.append(dt * 1000.0)
            total_bytes += len(build_frame(payload, iv)) + len(exp)
        else:
            lost += 1
            print(f"    [khung {i}] SAI: nhan {len(got)}/{len(exp)} byte")
    wall = time.time() - t_start

    loss_pct = 100.0 * lost / n
    thr = total_bytes / wall if wall > 0 else 0.0

    print()
    print(f"  Khung gui       : {n}")
    print(f"  Khung hong/mat  : {lost}  ({loss_pct:.2f}%)")
    if lat:
        print(f"  Do tre (ms)     : min {min(lat):.2f}  avg {statistics.mean(lat):.2f}  "
              f"max {max(lat):.2f}  stddev {statistics.pstdev(lat):.2f}")
    print(f"  Thong luong     : {thr:.0f} byte/s ({thr*8/1000:.1f} kbps)")
    print(f"  Tong thoi gian  : {wall:.2f} s")
    print()

    r.check(lost == 0, f"TC-602a / REQ-P-02: ti le mat khung = 0% (do: {loss_pct:.2f}%)")
    if lat:
        r.check(max(lat) <= 40.0,
                f"TC-602b / REQ-P-03: do tre <= 40 ms (max do duoc {max(lat):.2f} ms)")
    r.check(thr >= 8000.0,
            f"TC-602c / REQ-P-04: thong luong >= 8000 B/s (do: {thr:.0f})")
    r.finish("TC-602")


# ═══════ TC-603/604/605: test đối kháng, BẮT BUỘC hai pha (REQ-V-04) ═══════
def _phase_b_liveness(ser, r, tag):
    """Pha B: khung hợp lệ phải chạy đúng — bằng chứng FPGA còn sống."""
    payload = rand_payload(32)
    iv = os.urandom(16)
    got, dt = exchange(ser, payload, iv)
    ok = (got == expected_reply(payload, iv))
    r.check(ok, f"{tag} pha B (LIVENESS): khung hop le ngay sau do chay DUNG",
            f"nhan {len(got)} byte, mong doi {len(expected_reply(payload, iv))}")
    return ok


def mode_tamper(ser, args):
    r = Res()
    payload = rand_payload(args.len)
    iv = os.urandom(16)
    frame = bytearray(build_frame(payload, iv))

    # Lật 1 bit trong payload -> digest không còn khớp
    frame[20] ^= 0x01
    print("  Pha A: gui khung da lat 1 bit trong payload...")
    ser.reset_input_buffer()
    ser.write(bytes(frame))
    ser.flush()
    got = drain(ser, 1.0)
    r.check(len(got) == 0,
            "TC-603 pha A: khung bi sua -> FPGA KHONG phat gi",
            f"nhan {len(got)} byte: {got[:16].hex()}")

    print("  Pha B: gui khung hop le de chung minh FPGA con song...")
    _phase_b_liveness(ser, r, "TC-603")
    r.finish("TC-603 (tamper)")


def mode_timeout(ser, args):
    r = Res()
    payload = rand_payload(args.len)
    iv = os.urandom(16)
    frame = build_frame(payload, iv)

    print("  Pha A: gui khung cat giua chung (10 byte dau)...")
    ser.reset_input_buffer()
    ser.write(frame[:10])
    ser.flush()
    got = drain(ser, 1.0)
    r.check(len(got) == 0,
            "TC-604 pha A: khung cat -> FPGA KHONG phat gi",
            f"nhan {len(got)} byte")

    # Watchdog phần cứng là 2^24 chu ky ~ 0,62 s ở 27 MHz
    print("  Cho watchdog (0,62 s)...")
    time.sleep(1.0)
    drain(ser, 0.2)

    print("  Pha B: gui khung hop le de chung minh watchdog da phuc hoi...")
    _phase_b_liveness(ser, r, "TC-604")
    r.finish("TC-604 (timeout)")


def mode_garbage(ser, args):
    r = Res()
    print("  Pha A: gui 32 byte rac (khong chua preamble)...")
    junk = bytes(b for b in (i ^ 0xF0 for i in range(32)))
    ser.reset_input_buffer()
    ser.write(junk)
    ser.flush()
    got = drain(ser, 0.5)
    r.check(len(got) == 0, "TC-605 pha A: rac -> FPGA KHONG phat gi",
            f"nhan {len(got)} byte")

    print("  Pha B: rac roi khung hop le ngay sau -> phai nhan dung...")
    payload = rand_payload(args.len)
    iv = os.urandom(16)
    ser.reset_input_buffer()
    ser.write(junk + build_frame(payload, iv))
    ser.flush()
    exp = expected_reply(payload, iv)
    got = read_exact(ser, len(exp), 2.0)
    r.check(got == exp,
            "TC-605 pha B: 32 byte rac truoc preamble -> VAN nhan dung khung",
            f"nhan {len(got)}/{len(exp)} byte")
    r.finish("TC-605 (garbage)")


MODES = {
    "uartloop": mode_uartloop,
    "echo":     mode_echo,
    "sweep":    mode_sweep,
    "bench":    mode_bench,
    "tamper":   mode_tamper,
    "timeout":  mode_timeout,
    "garbage":  mode_garbage,
}


def main():
    ap = argparse.ArgumentParser(description="Kiem chung tren phan cung that")
    ap.add_argument("--port", default="/dev/ttyUSB1",
                    help="kenh UART (ttyUSB0 la JTAG, KHONG dung)")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--mode", required=True, choices=sorted(MODES))
    ap.add_argument("--bytes", type=int, default=512, help="cho --mode uartloop")
    ap.add_argument("--len", type=int, default=128, help="so byte payload moi khung")
    ap.add_argument("--frames", type=int, default=100)
    args = ap.parse_args()

    print("=" * 62)
    print(f"  HW TEST  mode={args.mode}  port={args.port}  baud={args.baud}")
    print("=" * 62)

    try:
        ser = serial.Serial(args.port, args.baud, timeout=0.3, write_timeout=5)
    except serial.SerialException as e:
        sys.exit(f"[ERROR] khong mo duoc {args.port}: {e}\n"
                 f"        Board da cam chua? {args.port} co phai kenh UART khong "
                 f"(ttyUSB0 la JTAG).")
    ser.reset_input_buffer()
    ser.reset_output_buffer()
    try:
        MODES[args.mode](ser, args)
    finally:
        ser.close()


if __name__ == "__main__":
    main()
