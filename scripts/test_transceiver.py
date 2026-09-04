#!/usr/bin/env python3
"""
Host-side Verification & Diagnostic CLI for FPGA Cryptographic Transceiver.
Communicates with Sipeed Tang Nano 9K over physical/virtual UART at 115,200 baud (8-N-1).

Protocol Specification:
  [ PREAMBLE (2B: 0xAA 0x55) | LEN (2B Big-Endian) | IV (16B) | CIPHERTEXT (L bytes) | MAC (32B SHA-256) | POSTAMBLE (2B: 0x0D 0x0A) ]
  - MAC calculation: SHA-256( LEN || IV || CIPHERTEXT )
  - Encryption: AES-256 CTR mode with standard 128-bit big-endian counter increment
"""

import sys
import time
import argparse
import hashlib
from typing import Tuple, Optional

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

# Default Transceiver Parameters (matches SRS_URD.md & RTL)
DEFAULT_ROOT_KEY = bytes.fromhex("603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4")
DEFAULT_BASE_IV  = bytes.fromhex("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff")
PREAMBLE         = bytes([0xAA, 0x55])
POSTAMBLE        = bytes([0x0D, 0x0A])


def build_frame(plaintext: bytes, key: bytes = DEFAULT_ROOT_KEY, iv: bytes = DEFAULT_BASE_IV) -> Tuple[bytes, bytes, bytes]:
    """Encrypts plaintext with AES-256 CTR, computes SHA-256 MAC, and frames packet."""
    # Ensure plaintext is a multiple of 16 bytes (pad with PKCS#7 or zero-pad up to block boundary)
    pad_len = (16 - (len(plaintext) % 16)) % 16
    padded_pt = plaintext + (b"\x00" * pad_len if pad_len != 0 else b"")
    if len(padded_pt) == 0:
        padded_pt = b"\x00" * 16

    # AES-256 CTR Encryption
    cipher = Cipher(algorithms.AES(key), modes.CTR(iv))
    encryptor = cipher.encryptor()
    ciphertext = encryptor.update(padded_pt) + encryptor.finalize()

    # Length: 2 bytes big-endian
    len_bytes = len(ciphertext).to_bytes(2, byteorder="big")

    # MAC: SHA-256( LEN || IV || CIPHERTEXT )
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

    # Verify SHA-256 MAC
    auth_data = raw[2:20 + ct_len]
    expected_mac = hashlib.sha256(auth_data).digest()
    if received_mac != expected_mac:
        return False, None, f"MAC verification failed! Recv: {received_mac.hex()} != Calc: {expected_mac.hex()}"

    # Decrypt AES-256 CTR
    cipher = Cipher(algorithms.AES(key), modes.CTR(iv))
    decryptor = cipher.decryptor()
    plaintext = decryptor.update(ciphertext) + decryptor.finalize()

    return True, plaintext, "OK"


def run_echo_test(ser: serial.Serial, payload: bytes) -> bool:
    """Executes normal round-trip echo verification test."""
    print(f"\n--- [TEST: SECURE ECHO LOOPBACK] ---")
    print(f"Payload ({len(payload)} bytes): {payload.hex()} ({payload})")

    frame, expected_ct, expected_mac = build_frame(payload)
    print(f"Transmitting Frame ({len(frame)} bytes): {frame.hex()}")

    ser.reset_input_buffer()
    t0 = time.perf_counter()
    ser.write(frame)
    ser.flush()

    # Expected response length matches request length
    resp = ser.read(len(frame))
    t1 = time.perf_counter()

    if len(resp) == 0:
        print(f"[FAIL] Transceiver timed out. No response bytes received.")
        return False

    print(f"Received Response ({len(resp)} bytes in {(t1 - t0)*1000:.2f} ms): {resp.hex()}")

    valid, decrypted_pt, msg = parse_and_verify_frame(resp)
    if not valid:
        print(f"[FAIL] Frame validation failed: {msg}")
        return False

    # Check payload match
    trimmed_pt = decrypted_pt[:len(payload)]
    if trimmed_pt != payload:
        print(f"[FAIL] Payload mismatch! Decrypted: {trimmed_pt.hex()} != Sent: {payload.hex()}")
        return False

    print(f"[PASS] Echoed packet authentic, decrypted, and matches payload exactly!")
    return True


def run_tamper_test(ser: serial.Serial, payload: bytes) -> bool:
    """Injects 1-bit corruption in MAC; expects FPGA to drop frame and emit 0 bytes."""
    print(f"\n--- [TEST: TAMPER FAULT INJECTION] ---")
    frame, _, _ = build_frame(payload)

    # Invert 1 bit in the MAC tag (byte offset 36)
    tampered_frame = bytearray(frame)
    tampered_frame[36] ^= 0x01
    tampered_frame = bytes(tampered_frame)

    print(f"Transmitting Corrupted Frame (1-bit flipped in MAC): {tampered_frame.hex()}")

    ser.reset_input_buffer()
    ser.write(tampered_frame)
    ser.flush()

    # Short timeout to confirm zero bytes emitted
    old_timeout = ser.timeout
    ser.timeout = 0.5
    resp = ser.read(64)
    ser.timeout = old_timeout

    if len(resp) > 0:
        print(f"[FAIL] Tampered frame leaked bytes ({len(resp)} bytes): {resp.hex()}")
        return False

    print(f"[PASS] Transceiver quarantined and dropped tampered frame. 0 bytes emitted.")
    return True


def run_timeout_test(ser: serial.Serial) -> bool:
    """Sends incomplete frame (preamble only) followed by silence; verifies watchdog recovery."""
    print(f"\n--- [TEST: WATCHDOG TIMEOUT RECOVERY] ---")
    print("Transmitting preamble 0xAA 0x55 then stalling...")

    ser.reset_input_buffer()
    ser.write(PREAMBLE)
    ser.flush()

    # Wait > 2.5 ms for FPGA watchdog to trigger and release arbiter
    time.sleep(0.01)

    # Now verify FPGA can still accept a valid frame immediately
    print("Verifying arbiter reset by transmitting a fresh valid frame...")
    frame, _, _ = build_frame(b"RecoveryTest1234")
    ser.write(frame)
    ser.flush()

    resp = ser.read(len(frame))
    if len(resp) == len(frame) and resp[:2] == PREAMBLE:
        print(f"[PASS] Transceiver successfully recovered from stall after watchdog timeout.")
        return True
    else:
        print(f"[FAIL] Failed to recover. Response: {resp.hex()}")
        return False


def main():
    parser = argparse.ArgumentParser(description="FPGA AES-256 CTR & SHA-256 Transceiver Host Test Suite")
    parser.add_argument("--port", default="/dev/ttyUSB1", help="Serial port device (default: /dev/ttyUSB1)")
    parser.add_argument("--baud", type=int, default=115200, help="Baud rate (default: 115200)")
    parser.add_argument("--test", choices=["echo", "tamper", "timeout", "all"], default="all", help="Test to execute")
    parser.add_argument("--payload", default="KMA_Contest_2026", help="ASCII or hex plaintext payload")
    args = parser.parse_args()

    # Parse payload
    if args.payload.startswith("0x"):
        payload = bytes.fromhex(args.payload[2:])
    else:
        payload = args.payload.encode("utf-8")

    print("================================================================================")
    print("   FPGA SECURE TRANSCEIVER HOST VERIFICATION SUITE")
    print(f"   Target Port: {args.port} @ {args.baud} 8-N-1")
    print("================================================================================")

    try:
        ser = serial.Serial(port=args.port, baudrate=args.baud, timeout=2.0)
    except Exception as e:
        print(f"[ERROR] Could not open serial port {args.port}: {e}")
        print("Note: If hardware is not connected, use simulator (make sim-top) for verification.")
        sys.exit(1)

    passes = 0
    total = 0

    if args.test in ["echo", "all"]:
        total += 1
        if run_echo_test(ser, payload):
            passes += 1

    if args.test in ["tamper", "all"]:
        total += 1
        if run_tamper_test(ser, payload):
            passes += 1

    if args.test in ["timeout", "all"]:
        total += 1
        if run_timeout_test(ser):
            passes += 1

    ser.close()

    print("\n================================================================================")
    print(f"   SUMMARY: {passes}/{total} TESTS PASSED")
    print("================================================================================")
    sys.exit(0 if passes == total else 1)


if __name__ == "__main__":
    main()
