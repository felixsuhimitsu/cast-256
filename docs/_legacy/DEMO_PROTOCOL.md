# DEMO_PROTOCOL.md — Live Jury Demonstration Runbook

> **Competition**: KMA 2026 — Hardware Security IP Design Contest
> **Project**: Thiết kế và tích hợp IP mã hóa AES-256 và SHA-256 cho giao thức truyền và nhận dữ liệu
> **Board**: Sipeed Tang Nano 9K (Gowin GW1NR-LV9QN88PC6/I5)

---

## 1. Hardware Apparatus Setup

### 1.1 Physical Connections

| Item | Detail |
|------|--------|
| FPGA Board | Sipeed Tang Nano 9K |
| Connection | USB-C to host laptop (onboard BL702 USB-UART bridge) |
| Serial Port | `/dev/ttyUSB0` or `/dev/ttyUSB1` (auto-detected) |
| Baud Rate | 115,200 bps, 8-N-1 |
| System Clock | 27.0 MHz (onboard crystal oscillator) |

### 1.2 LED Status Indicators

| LED | Pin | Color | Function |
|-----|-----|-------|----------|
| D1 | 10 | Orange | **TX Active** — 150 ms pulse on every outbound frame transmission |
| D2 | 11 | Green | **RX Auth Pass** — 150 ms pulse when inbound frame passes SHA-256 MAC verification |
| D3 | 13 | Blue | **MAC Tamper Alert** — 150 ms pulse when MAC verification fails or watchdog timeout triggers |

### 1.3 Pre-Demo Checklist

```bash
# 1. Flash bitstream to FPGA SRAM (volatile — resets on power cycle)
bash scripts/flash_openfpgaloader.sh --sram

# 2. Verify serial port enumeration
ls -la /dev/ttyUSB*

# 3. Verify Python dependencies
python3 -c "import serial; from cryptography.hazmat.primitives.ciphers import Cipher; print('OK')"
```

---

## 2. Demonstration Scenarios

### Scenario A: Authenticated Transceiver Round-Trip

**Purpose**: Prove full cryptographic pipeline integrity — AES-256 CTR encryption, SHA-256 MAC computation, secure echo loopback, and post-auth gated decryption.

**Command**:
```bash
python3 scripts/test_transceiver.py --port /dev/ttyUSB0 --mode echo
```

**Expected Outcome**:
- NIST SP 800-38A F.5.5 KAT plaintext (64 bytes, 4 AES blocks) is encrypted, framed, and transmitted.
- FPGA receives frame → quarantines ciphertext → computes SHA-256 MAC → **verifies match** → releases plaintext from quarantine → re-encrypts → transmits echo frame.
- Host verifies echoed frame: MAC integrity ✓, decrypted payload matches original ✓.
- **LED D2 (Green)** pulses for 150 ms confirming hardware-level auth pass.
- **LED D1 (Orange)** pulses for 150 ms confirming outbound TX.
- Terminal prints `[PASS]` with round-trip latency measurement.

**Key Talking Points for Judges**:
1. Plaintext is **never** exposed until MAC is verified — gated post-auth decryption.
2. IV is transmitted in-band (16 bytes) per protocol frame for CTR nonce management.
3. MAC covers `LEN || IV || CIPHERTEXT` — length extension and IV substitution attacks are mitigated.

---

### Scenario B: Physical Layer Tamper Detection

**Purpose**: Prove the Encrypt-then-MAC security invariant — corrupted frames are quarantined and **zero** unauthenticated plaintext is released.

**Command**:
```bash
python3 scripts/test_transceiver.py --port /dev/ttyUSB0 --mode tamper
```

**Expected Outcome**:
- A valid frame is constructed, then **1 bit is flipped** in the SHA-256 MAC tag before transmission.
- FPGA receives frame → quarantines ciphertext → computes SHA-256 → **MAC mismatch detected**.
- **Quarantine BSRAM is flushed**. AES-256 CTR decryption engine is **never invoked**.
- **Zero bytes** emitted on UART TX.
- **LED D3 (Blue)** pulses for 150 ms confirming hardware-level tamper alert.
- Terminal prints `[PASS]` confirming 0 response bytes.

**Key Talking Points for Judges**:
1. Ciphertext stays in quarantine BSRAM — **never** reaches AES decryption input.
2. This prevents padding oracle, chosen-ciphertext, and side-channel amplification attacks.
3. Single-bit sensitivity: even 1 corrupted bit in the 256-bit MAC tag triggers full rejection.

---

### Scenario C: Protocol Resilience & Timeout Recovery

**Purpose**: Prove the hardware arbiter cannot be permanently locked by truncated or malformed frames (DoS resilience).

**Command**:
```bash
python3 scripts/test_transceiver.py --port /dev/ttyUSB0 --mode timeout
```

**Expected Outcome**:
- Host sends preamble `0xAA 0x55` + partial length/IV bytes, then **goes silent**.
- After **2.5 ms** (67,500 clock cycles at 27.0 MHz), the hardware watchdog timer fires.
- Arbiter lock is released. RX deframer returns to `ST_IDLE`.
- **LED D3 (Blue)** pulses confirming error condition.
- Host then sends a **fresh valid frame** — FPGA processes it normally.
- Terminal prints `[PASS]` confirming successful recovery.

**Key Talking Points for Judges**:
1. Deterministic 2.5 ms timeout — no software involvement, pure hardware counter.
2. Arbiter mutual-exclusion lock is **always** released on timeout — prevents deadlock.
3. Immediate recovery: next valid frame is processed without reset or reboot.

---

### Scenario D: Throughput Benchmark (Optional)

**Command**:
```bash
python3 scripts/test_transceiver.py --port /dev/ttyUSB0 --mode benchmark --frames 100
```

**Expected Outcome**:
- 100 consecutive frames streamed through the full encrypt→MAC→TX→RX→verify→decrypt→re-encrypt→TX pipeline.
- Reports per-frame latency (min/avg/max), throughput (bytes/sec, kbps), and packet loss rate.
- 0% packet loss expected under clean channel conditions.

---

## 3. Failure Recovery Procedures

| Symptom | Cause | Recovery |
|---------|-------|----------|
| No serial port detected | USB-C cable or BL702 bridge issue | Reconnect USB-C, check `dmesg \| tail` |
| All LEDs stay off after flash | Bitstream not loaded | Re-run `bash scripts/flash_openfpgaloader.sh --sram` |
| Echo test timeout | Wrong serial port | Try `--port /dev/ttyUSB1` |
| Intermittent failures | USB hub signal integrity | Use direct USB-C connection, no hub |

---

## 4. Silicon Resource Summary (for Judges)

| Resource | Used | Available | Utilization |
|----------|------|-----------|-------------|
| DFF (Flip-Flops) | 3,499 | 6,480 | 54.0% |
| BSRAM Blocks | 5 | 26 | 19.2% |
| F_max | 59.21 MHz | 27.0 MHz target | **2.19× margin** |
| WNS (Worst Negative Slack) | +66.4 ns | ≥ 0 ns | **PASS** |
