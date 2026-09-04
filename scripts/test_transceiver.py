#!/usr/bin/env python3
"""
Host-side Verification & Diagnostic CLI for FPGA Cryptographic Transceiver.
Communicates with Sipeed Tang Nano 9K over physical UART at 115,200 baud (8-N-1).

Protocol Specification:
  [ PREAMBLE (2B: 0xAA 0x55) | LEN (2B Big-Endian) | IV (16B) | CIPHERTEXT (L bytes) | MAC (32B SHA-256) | POSTAMBLE (2B: 0x0D 0x0A) ]
  - MAC calculation: SHA-256( LEN || IV || CIPHERTEXT )
  - Encryption: AES-256 CTR mode with standard 128-bit big-endian counter increment

Test Modes:
  echo      - Authenticated round-trip loopback verification (NIST KAT payload)
  tamper    - 1-bit fault injection in MAC tag; expects quarantine drop
  timeout   - Incomplete frame; expects watchdog recovery
  benchmark - Stream N frames, report throughput & latency
  all       - Run echo + tamper + timeout sequentially
"""

import sys
import time
import argparse
import hashlib
import statistics
from typing import Tuple, Optional, List

try:
    import serial
except ImportError:
    print("[ERROR] pyserial is required. Install via: pip install pyserial")
    sys.exit(1)

try:
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
except ImportError:
    print("[ERROR] cryptography is required. Install via: pip install cryptography")
    sys.exit(1)

# ── Default Transceiver Parameters (matches SRS_URD.md & RTL) ──
DEFAULT_ROOT_KEY = bytes.fromhex("603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4")
DEFAULT_BASE_IV  = bytes.fromhex("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff")
PREAMBLE         = bytes([0xAA, 0x55])
POSTAMBLE        = bytes([0x0D, 0x0A])

# NIST SP 800-38A F.5.5 CTR-AES256 KAT plaintext (4 blocks = 64 bytes)
NIST_KAT_PLAINTEXT = bytes.fromhex(
    "6bc1bee22e409f96e93d7e117393172a"
    "ae2d8a571e03ac9c9eb76fac45af8e51"
    "30c81c46a35ce411e5fbc1191a0a52ef"
    "f69f2445df4f9b17ad2b417be66c3710"
)


# ═══════════════════════════════════════════════════════════════
#  Frame Builder / Parser
# ═══════════════════════════════════════════════════════════════

def build_frame(plaintext: bytes, key: bytes = DEFAULT_ROOT_KEY, iv: bytes = DEFAULT_BASE_IV) -> Tuple[bytes, bytes, bytes]:
    """Encrypts plaintext with AES-256 CTR, computes SHA-256 MAC, and frames packet."""
    pad_len = (16 - (len(plaintext) % 16)) % 16
    padded_pt = plaintext + (b"\x00" * pad_len if pad_len != 0 else b"")
    if len(padded_pt) == 0:
        padded_pt = b"\x00" * 16

    cipher = Cipher(algorithms.AES(key), modes.CTR(iv))
    encryptor = cipher.encryptor()
    ciphertext = encryptor.update(padded_pt) + encryptor.finalize()

    len_bytes = len(ciphertext).to_bytes(2, byteorder="big")

    auth_data = len_bytes + iv + ciphertext
    mac = hashlib.sha256(auth_data).digest()

    frame = PREAMBLE + len_bytes + iv + ciphertext + mac + POSTAMBLE
    return frame, ciphertext, mac


def parse_and_verify_frame(raw: bytes, key: bytes = DEFAULT_ROOT_KEY) -> Tuple[bool, Optional[bytes], str]:
    """Validates frame structure, checks SHA-256 MAC, and decrypts payload."""
    if len(raw) < 70:
        return False, None, f"Frame too short ({len(raw)} bytes < min 70 bytes)"

    if raw[:2] != PREAMBLE:
        return False, None, f"Invalid preamble: {raw[:2].hex()}"

    if raw[-2:] != POSTAMBLE:
        return False, None, f"Invalid postamble: {raw[-2:].hex()}"

    ct_len = int.from_bytes(raw[2:4], byteorder="big")
    expected_total_len = 2 + 2 + 16 + ct_len + 32 + 2
    if len(raw) != expected_total_len:
        return False, None, f"Length mismatch (header indicates {expected_total_len}B, received {len(raw)}B)"

    iv = raw[4:20]
    ciphertext = raw[20:20 + ct_len]
    received_mac = raw[20 + ct_len: 20 + ct_len + 32]

    auth_data = raw[2:20 + ct_len]
    expected_mac = hashlib.sha256(auth_data).digest()
    if received_mac != expected_mac:
        return False, None, f"MAC verification failed! Recv: {received_mac.hex()} != Calc: {expected_mac.hex()}"

    cipher = Cipher(algorithms.AES(key), modes.CTR(iv))
    decryptor = cipher.decryptor()
    plaintext = decryptor.update(ciphertext) + decryptor.finalize()

    return True, plaintext, "OK"


# ═══════════════════════════════════════════════════════════════
#  Test Mode: Echo (Authenticated Round-Trip)
# ═══════════════════════════════════════════════════════════════

def run_echo_test(ser: serial.Serial, payload: bytes, verbose: bool = True) -> bool:
    """Executes normal round-trip echo verification test using NIST KAT payload."""
    if verbose:
        print(f"\n{'='*72}")
        print(f"  [TEST: SECURE ECHO LOOPBACK]")
        print(f"{'='*72}")
        print(f"  Payload ({len(payload)} bytes): {payload[:32].hex()}{'...' if len(payload) > 32 else ''}")

    frame, expected_ct, expected_mac = build_frame(payload)
    if verbose:
        print(f"  TX Frame ({len(frame)} bytes)")

    ser.reset_input_buffer()
    t0 = time.perf_counter()
    ser.write(frame)
    ser.flush()

    resp = ser.read(len(frame))
    t1 = time.perf_counter()
    latency_ms = (t1 - t0) * 1000

    if len(resp) == 0:
        if verbose:
            print(f"  [FAIL] Transceiver timed out. No response bytes received.")
        return False

    if verbose:
        print(f"  RX Response ({len(resp)} bytes in {latency_ms:.2f} ms)")

    valid, decrypted_pt, msg = parse_and_verify_frame(resp)
    if not valid:
        if verbose:
            print(f"  [FAIL] Frame validation failed: {msg}")
        return False

    trimmed_pt = decrypted_pt[:len(payload)]
    if trimmed_pt != payload:
        if verbose:
            print(f"  [FAIL] Payload mismatch! Decrypted: {trimmed_pt.hex()} != Sent: {payload.hex()}")
        return False

    if verbose:
        print(f"  [PASS] Echoed packet authentic, MAC verified, payload matched. ({latency_ms:.2f} ms)")
        print(f"         LED D2 (Pin 11, RX Auth Pass) should pulse Green for 150 ms.")
    return True


# ═══════════════════════════════════════════════════════════════
#  Test Mode: Tamper (1-bit MAC Corruption)
# ═══════════════════════════════════════════════════════════════

def run_tamper_test(ser: serial.Serial, payload: bytes) -> bool:
    """Injects 1-bit corruption in MAC; expects FPGA to drop frame and emit 0 bytes."""
    print(f"\n{'='*72}")
    print(f"  [TEST: TAMPER FAULT INJECTION]")
    print(f"{'='*72}")

    frame, _, _ = build_frame(payload)

    # Corrupt 1 bit in the SHA-256 MAC tag (first byte of MAC)
    mac_offset = 2 + 2 + 16 + len(frame) - 2 - 32 - 2 + 2  # Start of MAC in frame
    # Simpler: MAC starts at 2+2+16+ct_len, ct_len = len(payload) rounded up to 16
    ct_len = int.from_bytes(frame[2:4], byteorder="big")
    mac_start = 2 + 2 + 16 + ct_len
    tampered_frame = bytearray(frame)
    tampered_frame[mac_start] ^= 0x01
    tampered_frame = bytes(tampered_frame)

    print(f"  TX Corrupted Frame (1-bit flipped at MAC byte 0)")

    ser.reset_input_buffer()
    ser.write(tampered_frame)
    ser.flush()

    old_timeout = ser.timeout
    ser.timeout = 0.5
    resp = ser.read(64)
    ser.timeout = old_timeout

    if len(resp) > 0:
        print(f"  [FAIL] Tampered frame leaked {len(resp)} bytes: {resp.hex()}")
        return False

    print(f"  [PASS] Frame quarantined and dropped. 0 bytes emitted on TX.")
    print(f"         LED D3 (Pin 13, MAC Tamper Alert) should pulse Blue for 150 ms.")
    return True


# ═══════════════════════════════════════════════════════════════
#  Test Mode: Timeout (Watchdog Recovery)
# ═══════════════════════════════════════════════════════════════

def run_timeout_test(ser: serial.Serial) -> bool:
    """Sends incomplete frame (preamble + partial header) then verifies watchdog recovery."""
    print(f"\n{'='*72}")
    print(f"  [TEST: WATCHDOG TIMEOUT RECOVERY]")
    print(f"{'='*72}")

    # Send preamble + LEN_H + partial IV (truncated after ~10 bytes)
    partial_frame = PREAMBLE + b"\x00\x40" + DEFAULT_BASE_IV[:10]
    print(f"  TX Truncated Frame ({len(partial_frame)} bytes): {partial_frame.hex()}")
    print(f"  Stalling to trigger 2.5 ms hardware watchdog timer...")

    ser.reset_input_buffer()
    ser.write(partial_frame)
    ser.flush()

    # Wait > 2.5 ms for FPGA watchdog to trigger and release arbiter
    time.sleep(0.01)

    # Verify FPGA recovered by sending a valid frame
    print(f"  Verifying arbiter recovery with a fresh valid frame...")
    recovery_payload = b"WatchdogRecover!"
    frame, _, _ = build_frame(recovery_payload)
    ser.write(frame)
    ser.flush()

    resp = ser.read(len(frame))
    if len(resp) == len(frame) and resp[:2] == PREAMBLE:
        valid, pt, msg = parse_and_verify_frame(resp)
        if valid and pt[:len(recovery_payload)] == recovery_payload:
            print(f"  [PASS] Arbiter recovered from stall. Valid echo received post-timeout.")
            return True

    print(f"  [FAIL] Failed to recover. Response ({len(resp)} bytes): {resp.hex() if resp else 'EMPTY'}")
    return False


# ═══════════════════════════════════════════════════════════════
#  Test Mode: Benchmark (Throughput & Latency)
# ═══════════════════════════════════════════════════════════════

def run_benchmark_test(ser: serial.Serial, payload: bytes, num_frames: int = 100) -> bool:
    """Streams N consecutive frames, calculates throughput and per-frame latency."""
    print(f"\n{'='*72}")
    print(f"  [BENCHMARK: {num_frames}-Frame Throughput & Latency Measurement]")
    print(f"{'='*72}")

    frame, _, _ = build_frame(payload)
    frame_size = len(frame)
    latencies: List[float] = []
    failures = 0

    # Warmup: 2 frames
    for _ in range(2):
        ser.reset_input_buffer()
        ser.write(frame)
        ser.flush()
        resp = ser.read(frame_size)
        if len(resp) != frame_size:
            print(f"  [WARN] Warmup frame failed (received {len(resp)} bytes)")

    time.sleep(0.05)  # Settle

    t_total_start = time.perf_counter()

    for i in range(num_frames):
        ser.reset_input_buffer()
        t0 = time.perf_counter()
        ser.write(frame)
        ser.flush()
        resp = ser.read(frame_size)
        t1 = time.perf_counter()

        if len(resp) == frame_size:
            valid, _, _ = parse_and_verify_frame(resp)
            if valid:
                latencies.append((t1 - t0) * 1000)
            else:
                failures += 1
        else:
            failures += 1

        # Progress indicator
        if (i + 1) % 25 == 0:
            print(f"  [{i+1}/{num_frames}] frames processed...")

    t_total_end = time.perf_counter()
    total_time = t_total_end - t_total_start

    print(f"\n  {'─'*60}")
    print(f"  Results:")
    print(f"    Total Frames     : {num_frames}")
    print(f"    Successful       : {len(latencies)}")
    print(f"    Failed           : {failures}")
    print(f"    Frame Size       : {frame_size} bytes")
    print(f"    Payload Size     : {len(payload)} bytes")

    if latencies:
        total_bytes = len(latencies) * frame_size * 2  # TX + RX
        throughput_bps = total_bytes / total_time
        print(f"    Total Time       : {total_time:.3f} s")
        print(f"    Throughput       : {throughput_bps:.0f} bytes/s ({throughput_bps * 8 / 1000:.1f} kbps)")
        print(f"    Latency (min)    : {min(latencies):.2f} ms")
        print(f"    Latency (avg)    : {statistics.mean(latencies):.2f} ms")
        print(f"    Latency (max)    : {max(latencies):.2f} ms")
        print(f"    Latency (stddev) : {statistics.stdev(latencies):.2f} ms" if len(latencies) > 1 else "")
        print(f"    Packet Loss      : {failures / num_frames * 100:.1f}%")

    success = failures == 0
    status = "PASS" if success else "FAIL"
    print(f"\n  [{status}] Benchmark {'completed with 0% loss' if success else f'failed with {failures} errors'}.")
    return success


# ═══════════════════════════════════════════════════════════════
#  Main CLI Entry Point
# ═══════════════════════════════════════════════════════════════

def main():
    parser = argparse.ArgumentParser(
        description="FPGA AES-256 CTR & SHA-256 Transceiver Host Verification Suite",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""\
Test Modes:
  echo       Authenticated round-trip loopback (NIST KAT payload)
  tamper     1-bit MAC corruption fault injection
  timeout    Incomplete frame watchdog recovery
  benchmark  Stream 100 frames, report throughput & latency
  all        Run echo + tamper + timeout sequentially

LED Reference:
  D1 (Pin 10, Orange) = TX Active
  D2 (Pin 11, Green)  = RX Auth Pass
  D3 (Pin 13, Blue)   = MAC Tamper Alert
"""
    )
    parser.add_argument("--port", default="/dev/ttyUSB0",
                        help="Serial port device (default: /dev/ttyUSB0)")
    parser.add_argument("--baud", type=int, default=115200,
                        help="Baud rate (default: 115200)")
    parser.add_argument("--mode", choices=["echo", "tamper", "timeout", "benchmark", "all"],
                        default="all", help="Test mode to execute (default: all)")
    parser.add_argument("--payload", default=None,
                        help="ASCII or hex (0x...) plaintext payload (default: NIST KAT 64B)")
    parser.add_argument("--frames", type=int, default=100,
                        help="Number of frames for benchmark mode (default: 100)")
    args = parser.parse_args()

    # Parse payload: default to NIST KAT vector
    if args.payload is None:
        payload = NIST_KAT_PLAINTEXT
    elif args.payload.startswith("0x"):
        payload = bytes.fromhex(args.payload[2:])
    else:
        payload = args.payload.encode("utf-8")

    print("=" * 72)
    print("  FPGA SECURE TRANSCEIVER — HOST VERIFICATION SUITE")
    print(f"  Target : {args.port} @ {args.baud} 8-N-1")
    print(f"  Mode   : {args.mode}")
    print(f"  Payload: {len(payload)} bytes {'(NIST SP 800-38A KAT)' if args.payload is None else ''}")
    print("=" * 72)

    try:
        ser = serial.Serial(port=args.port, baudrate=args.baud, timeout=2.0,
                            bytesize=serial.EIGHTBITS, parity=serial.PARITY_NONE,
                            stopbits=serial.STOPBITS_ONE)
    except Exception as e:
        print(f"[ERROR] Could not open serial port {args.port}: {e}")
        print("Note: If hardware is not connected, use simulator (make sim-top) for verification.")
        sys.exit(1)

    time.sleep(0.1)  # Allow UART to settle after open
    ser.reset_input_buffer()
    ser.reset_output_buffer()

    passes = 0
    total = 0
    results = []

    if args.mode in ["echo", "all"]:
        total += 1
        ok = run_echo_test(ser, payload)
        if ok: passes += 1
        results.append(("Echo Loopback", ok))

    if args.mode in ["tamper", "all"]:
        total += 1
        time.sleep(0.05)  # Inter-test settle
        ok = run_tamper_test(ser, payload)
        if ok: passes += 1
        results.append(("Tamper Injection", ok))

    if args.mode in ["timeout", "all"]:
        total += 1
        time.sleep(0.05)
        ok = run_timeout_test(ser)
        if ok: passes += 1
        results.append(("Watchdog Timeout", ok))

    if args.mode == "benchmark":
        total += 1
        ok = run_benchmark_test(ser, payload, args.frames)
        if ok: passes += 1
        results.append(("Benchmark", ok))

    ser.close()

    print(f"\n{'='*72}")
    print(f"  FINAL SUMMARY")
    print(f"{'─'*72}")
    for name, ok in results:
        status = "\033[32mPASS\033[0m" if ok else "\033[31mFAIL\033[0m"
        print(f"    {name:.<40s} [{status}]")
    print(f"{'─'*72}")
    print(f"    Total: {passes}/{total}")
    print(f"{'='*72}")
    sys.exit(0 if passes == total else 1)


if __name__ == "__main__":
    main()
