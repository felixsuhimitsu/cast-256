#!/usr/bin/env python3
"""
scripts/hw_test.py — Bộ kiểm chứng trên phần cứng thật (mức L3)
================================================================
REQ: REQ-V-03, REQ-V-04 · TEST_PLAN: TC-600..606 · Ngày: 2026-09-09

CHẠY BẰNG /usr/bin/python3, KHÔNG dùng `python3`
   Sau khi `source ~/tools/oss-cad-suite/environment`, `python3` bị thay bằng
   bản 3.11 riêng của toolchain, không có pyserial.

CỔNG: /dev/ttyUSB1
   FT2232 có hai kênh. ttyUSB0 là JTAG (dùng để nạp bitstream), ttyUSB1 mới là
   UART. Đọc nhầm kênh sẽ ra dữ liệu rác trông y hệt lỗi giao thức.

NGUYÊN TẮC REQ-V-04
   Mọi chế độ kiểm "FPGA phải từ chối" đều chạy HAI PHA:
     Pha A — kích thích tiêu cực, kỳ vọng im lặng
     Pha B — khung hợp lệ ngay sau đó, kỳ vọng phản hồi đúng  ← liveness
   Test chỉ có pha A là KHÔNG HỢP LỆ: nó vẫn PASS khi FPGA đã chết hoàn toàn.
   Đây là lỗi thật đã gặp ở thiết kế trước.
"""

import argparse
import statistics
import sys
import time

try:
    import serial
except ImportError:
    sys.exit("[ERROR] can pyserial. Cai bang:  /usr/bin/pip3 install --user pyserial\n"
             "        (nho chay bang /usr/bin/python3, khong phai python3 cua oss-cad-suite)")


# ───────────────────────────── tiện ích ─────────────────────────────
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
        return cond

    def finish(self, name):
        print("-" * 58)
        print(f"  {name}:  PASS {self.ok}   FAIL {self.bad}")
        if self.bad:
            print("  KET QUA: FAIL")
            sys.exit(1)
        print("  KET QUA: PASS")
        sys.exit(0)


def open_port(port, baud, timeout):
    try:
        s = serial.Serial(port, baud, timeout=timeout, write_timeout=5)
    except serial.SerialException as e:
        sys.exit(f"[ERROR] khong mo duoc {port}: {e}\n"
                 f"        Kiem tra: board da cam chua, va {port} co phai kenh UART khong "
                 f"(ttyUSB0 la JTAG).")
    s.reset_input_buffer()
    s.reset_output_buffer()
    return s


def read_exact(ser, n, deadline_s):
    """Đọc đúng n byte hoặc tới hết hạn. Trả về những gì đọc được."""
    buf = bytearray()
    end = time.time() + deadline_s
    while len(buf) < n and time.time() < end:
        chunk = ser.read(n - len(buf))
        if chunk:
            buf += chunk
    return bytes(buf)


# ───────────────────── TC-600: đường ống UART trần ─────────────────────
def mode_uartloop(ser, args):
    """
    GATE CỨNG CỦA WP-01.

    Gửi N byte LIÊN TỤC KHÔNG NGHỈ và đếm số byte vọng về. Đây là phép thử duy
    nhất chứng minh được REQ-I-05 — mô phỏng không bao giờ bắt được lỗi này vì
    testbench luôn chèn khoảng nghỉ giữa các byte.
    """
    r = Res()
    n = args.bytes
    payload = bytes((i * 7 + 0x5A) & 0xFF for i in range(n))

    print(f"  Gui {n} byte lien tuc, khong nghi giua cac byte...")
    ser.reset_input_buffer()
    t0 = time.time()
    ser.write(payload)
    ser.flush()
    got = read_exact(ser, n, deadline_s=n * 10.0 / args.baud + 3.0)
    dt = time.time() - t0

    lost = n - len(got)
    print(f"  Nhan lai {len(got)}/{n} byte trong {dt*1000:.1f} ms")

    r.check(lost == 0, f"TC-600a: khong mat byte nao (mat {lost})",
            f"Neu mat byte -> REQ-I-05 KHONG dat. Xem ADR-0005.")

    if got:
        first_bad = next((i for i in range(min(len(got), n)) if got[i] != payload[i]), None)
        r.check(first_bad is None,
                "TC-600b: noi dung vong lai dung tung byte",
                f"byte dau tien sai o vi tri {first_bad}" if first_bad is not None else "")

    # Đối chứng: cùng dữ liệu nhưng có nghỉ 1 ms giữa các byte.
    # Nếu ca này PASS mà ca trên FAIL thì nguyên nhân chắc chắn là mất đồng bộ
    # tích lũy, không phải hỏng đường truyền.
    print("  Doi chung: cung du lieu nhung nghi 1 ms giua cac byte...")
    ser.reset_input_buffer()
    slow_n = min(64, n)
    for b in payload[:slow_n]:
        ser.write(bytes([b]))
        ser.flush()
        time.sleep(0.001)
    got_slow = read_exact(ser, slow_n, deadline_s=3.0)
    print(f"  Nhan lai {len(got_slow)}/{slow_n} byte (che do co nghi)")
    if lost > 0:
        r.check(False,
                "CHAN DOAN: ca co nghi so voi ca lien tuc",
                f"lien tuc mat {lost}/{n}, co nghi mat {slow_n-len(got_slow)}/{slow_n} "
                f"-> dung la mat dong bo tich luy")

    r.finish("TC-600 (WP-01 gate)")


# ───────────────────────── các chế độ khác ─────────────────────────
def mode_notready(ser, args):
    sys.exit("[ERROR] Che do nay can bitstream day du (WP-07), chua co.\n"
             "        Hien tai chi chay duoc: --mode uartloop")


MODES = {
    "uartloop": mode_uartloop,
    "echo":     mode_notready,
    "bench":    mode_notready,
    "tamper":   mode_notready,
    "timeout":  mode_notready,
    "garbage":  mode_notready,
}


def main():
    ap = argparse.ArgumentParser(description="Kiem chung tren phan cung that")
    ap.add_argument("--port", default="/dev/ttyUSB1",
                    help="kenh UART (ttyUSB0 la JTAG, KHONG dung)")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--mode", required=True, choices=sorted(MODES))
    ap.add_argument("--bytes", type=int, default=512, help="so byte cho --mode uartloop")
    ap.add_argument("--frames", type=int, default=100)
    args = ap.parse_args()

    print("=" * 58)
    print(f"  HW TEST  mode={args.mode}  port={args.port}  baud={args.baud}")
    print("=" * 58)

    ser = open_port(args.port, args.baud, timeout=0.3)
    try:
        MODES[args.mode](ser, args)
    finally:
        ser.close()


if __name__ == "__main__":
    main()
