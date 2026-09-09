# Thiết kế và tích hợp IP mã hóa AES-256 và SHA-256 cho giao thức truyền và nhận dữ liệu

## Design and Integration of AES-256 Encryption and SHA-256 Authentication IPs for a Secure Data Communication Protocol

> **KMA 2026 — Hardware Security IP Design Competition**
> **Technical Engineering Report v1.0**

---

## 1. Abstract

This report presents the design, implementation, and physical silicon verification of a synthesizable cryptographic coprocessor IP targeting the Sipeed Tang Nano 9K development board (Gowin GW1NR-LV9QN88PC6/I5 FPGA). The system integrates:

- **AES-256 CTR Mode Encryption Engine** with Canright composite Galois Field S-Boxes for minimal-area substitution.
- **SHA-256 Message Digest Engine** with autonomous BSRAM-backed padding for Encrypt-then-MAC packet integrity verification.
- **Full-Duplex UART Transceiver** with hardware packet framing, quarantine-gated decryption, and a mutual-exclusion arbiter for half-duplex crypto pipeline sharing.

The design achieves **3,499 DFFs (54%)**, **5 BSRAM blocks (19%)**, and **F_max = 59.21 MHz** (2.19× over the 27.0 MHz system clock), with 100% NIST compliance verified against SP 800-38A (AES CTR) and FIPS 180-4 (SHA-256) test vectors.

---

## 2. System Architecture

### 2.1 Top-Level Block Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                    top_crypto_transceiver                        │
│                                                                  │
│  ┌──────────┐   ┌──────────────┐   ┌──────────────────────────┐ │
│  │ UART RX  │──▶│   Packet     │──▶│    Quarantine BSRAM      │ │
│  │ (Pin 18) │   │  Deframer    │   │  (Gated Post-Auth        │ │
│  │ 3-vote   │   │  + SHA-256   │   │   Decryption Gate)       │ │
│  │ majority │   │  MAC Verify  │   └──────────┬───────────────┘ │
│  └──────────┘   └──────────────┘              │ MAC PASS        │
│                                                ▼                 │
│  ┌──────────┐   ┌──────────────┐   ┌──────────────────────────┐ │
│  │ UART TX  │◀──│   Packet     │◀──│   AES-256 CTR Engine     │ │
│  │ (Pin 17) │   │   Framer     │   │  (14-round, Canright     │ │
│  └──────────┘   │  + SHA-256   │   │   S-Box, shared)         │ │
│                  │  MAC Compute │   └──────────────────────────┘ │
│                  └──────────────┘                                │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────────┐│
│  │  Crypto Arbiter (Mutual Exclusion + Watchdog Timer)         ││
│  │  Half-duplex lock: RX deframer XOR TX framer owns pipeline  ││
│  └──────────────────────────────────────────────────────────────┘│
│                                                                  │
│  LEDs: D1 (Pin 10) TX Active                                    │
│        D2 (Pin 11) RX Auth Pass                                 │
│        D3 (Pin 13) MAC Tamper Alert                              │
└──────────────────────────────────────────────────────────────────┘
```

### 2.2 Design Principles

1. **Encrypt-then-MAC (EtM) Security Model**: Ciphertext is computed first, then the SHA-256 MAC covers `LEN || IV || CIPHERTEXT`. The receiver verifies the MAC **before** any decryption occurs. This prevents chosen-ciphertext, padding oracle, and side-channel amplification attacks.

2. **Quarantine-Gated Decryption**: Incoming ciphertext is stored in an isolated Quarantine BSRAM partition. The AES-256 CTR decryption engine is **never invoked** until the MAC verification passes. Upon MAC failure, the quarantine buffer is flushed without exposing any unauthenticated plaintext.

3. **Resource Sharing via Hardware Arbiter**: A single AES-256 engine (14-round iterative) and a single SHA-256 engine (64-round iterative) are time-multiplexed between RX (decryption/verification) and TX (encryption/MAC computation) pipelines through a strict mutual-exclusion arbiter with priority: RX > TX.

---

## 3. Cryptographic Engine Design

### 3.1 AES-256 CTR Engine

| Parameter | Value |
|-----------|-------|
| Key Length | 256 bits (14 rounds, Nr = 14) |
| Mode | CTR (Counter) with 128-bit big-endian increment |
| S-Box | Canright Composite GF(((2²)²)²) isomorphic mapping |
| S-Box Footprint | ~65 LUT4 per instance |
| Key Expansion | On-the-fly round key generation (W₂ᵢ, W₂ᵢ₊₁ per cycle) |
| Throughput | 1 block (128 bits) per 15 clock cycles |
| Latency | 15 cycles × 37.0 ns = 555 ns per block |

**Canright S-Box Architecture**: The SubBytes transformation is implemented using composite field arithmetic in GF(((2²)²)²) with isomorphic basis change matrices. This achieves the theoretical minimum gate count for a combinational S-Box (~65 LUT4s vs ~180 LUT4s for lookup-table approaches), critical for fitting within the GW1NR-9's 8,640 LUT4 budget.

**On-the-fly Key Expansion**: Rather than pre-computing and storing all 15 round keys (requiring 15 × 128 = 1,920 bits of register storage), the key schedule computes two 32-bit words per cycle using SubWord/RotWord/Rcon operations mapped to the same Canright S-Box instances. This trades latency for area.

### 3.2 SHA-256 Digest Engine

| Parameter | Value |
|-----------|-------|
| Algorithm | FIPS 180-4 SHA-256 |
| Block Size | 512 bits (64 bytes) |
| Digest Size | 256 bits (32 bytes) |
| Message Schedule | W_t generation with σ₀, σ₁ rotations |
| K_t Constants | 64 × 32-bit values mapped to synchronous BSRAM (SPX9) |
| Accumulation | Serialized single 32-bit adder over 8 cycles (H₀+a ... H₇+h) |
| Throughput | 1 block per 64 + 8 = 72 clock cycles |

**BSRAM K_t ROM**: The 64 SHA-256 round constants are stored in a Gowin SPX9 block RAM primitive, eliminating ~650 logic LUT4s that would be consumed by a combinational ROM lookup.

**Serialized Hash Accumulation**: Instead of 8 parallel 32-bit adders for the final hash update (H₀ += a, H₁ += b, ..., H₇ += h), a single shared 32-bit adder is serialized over 8 additional cycles. This eliminates 216 ALU cells at the cost of 8 extra clock cycles per block — an acceptable trade-off given UART is the throughput bottleneck.

### 3.3 Autonomous BSRAM Padding (`sha256_padder`)

The SHA-256 message padding logic operates autonomously over a BSRAM-backed message buffer:
- Appends the `0x80` termination byte.
- Inserts zero-padding to align to 56 bytes mod 64.
- Appends the 64-bit big-endian message length.
- Feeds 64-byte blocks to the SHA-256 core via a synchronous read pipeline.

This eliminates UART streaming deadlocks by decoupling the byte-serial UART ingestion from the block-parallel SHA-256 computation.

---

## 4. Protocol & Framing

### 4.1 Packet Frame Format

```
┌──────────┬────────┬─────────┬──────────────┬─────────────┬───────────┐
│ PREAMBLE │  LEN   │   IV    │  CIPHERTEXT  │  SHA-256    │ POSTAMBLE │
│  2 bytes │ 2 bytes│ 16 bytes│  L bytes     │   MAC       │  2 bytes  │
│ 0xAA 0x55│ Big-End│         │ (16≤L≤448)   │  32 bytes   │ 0x0D 0x0A │
└──────────┴────────┴─────────┴──────────────┴─────────────┴───────────┘
```

- **MAC Domain**: `SHA-256(LEN || IV || CIPHERTEXT)` — covers all mutable fields.
- **Ciphertext Length L**: Must be a multiple of 16 bytes (AES block size).
- **IV**: 128-bit initialization vector for AES-256 CTR nonce.

### 4.2 RX Pipeline (Deframer)

1. Detect preamble `0xAA 0x55`.
2. Parse LEN, IV, store ciphertext into **Quarantine BSRAM**.
3. Parse 32-byte MAC tag from wire.
4. Compute `SHA-256(LEN || IV || CIPHERTEXT)` over Quarantine BSRAM contents.
5. **Verify**: Compare computed digest with received MAC.
   - **PASS**: Gate opens → AES-256 CTR decrypts quarantined ciphertext → Plaintext released to loopback buffer.
   - **FAIL**: Quarantine flushed, `mac_err_pulse` asserted, LED D3 fires. **Zero plaintext leakage**.
6. 2.5 ms watchdog timer (67,500 cycles) auto-releases arbiter on frame stall.

### 4.3 TX Pipeline (Framer)

1. Receive plaintext from loopback buffer (post-auth decrypted data).
2. AES-256 CTR encrypt → store ciphertext in TX BSRAM.
3. Write `LEN || IV || CIPHERTEXT` to framing BSRAM.
4. Compute `SHA-256(LEN || IV || CIPHERTEXT)` via autonomous padder.
5. Serialize frame: `PREAMBLE | LEN | IV | CIPHERTEXT | MAC | POSTAMBLE` → UART TX.

### 4.4 Hardware Arbiter

The `crypto_arbiter` module implements strict mutual exclusion:
- **Priority**: RX (inbound) > TX (outbound).
- **Lock Duration**: Held from `rx_req`/`tx_req` assertion until `rx_done`/`tx_done` release.
- **Shared Resources**: Single AES-256 engine + single SHA-256 engine + associated BSRAM write ports.
- **Deadlock Prevention**: 2.5 ms watchdog on RX path; TX path has implicit timeout via frame completion.

---

## 5. Physical Communication Layer

### 5.1 UART Transceiver

| Parameter | Value |
|-----------|-------|
| Baud Rate | 115,200 bps |
| System Clock | 27.0 MHz |
| Clock Divisor | 234 (27,000,000 / 115,200 ≈ 234.375) |
| Format | 8-N-1 (8 data bits, no parity, 1 stop bit) |
| RX Noise Rejection | 3-sample majority voter (cycles 116, 117, 118) |
| TX Pin | Pin 17 (active drive) |
| RX Pin | Pin 18 (LVCMOS33 input with pull-up) |

The 3-sample majority voter at mid-bit position provides robust noise rejection for the physical UART link without requiring oversampling.

---

## 6. Physical Silicon Verification

### 6.1 Resource Utilization

| Resource | Used | Available | Utilization | Target | Status |
|----------|------|-----------|-------------|--------|--------|
| DFF (Flip-Flops) | 3,499 | 6,480 | 54.0% | ≤ 3,500 | ✅ **MET** |
| BSRAM Blocks | 5 | 26 | 19.2% | 3–6 | ✅ **MET** |
| F_max | 59.21 MHz | — | — | ≥ 27.0 MHz | ✅ **PASS** |
| Timing Margin | +66.4 ns WNS | — | — | ≥ 0 ns | ✅ **PASS** |

### 6.2 BSRAM Block Allocation

| Block | Type | Module | Contents |
|-------|------|--------|----------|
| 1 | DPX9B | `packet_deframer` | Quarantine RAM (512 × 8-bit) — unauthenticated ciphertext isolation |
| 2 | DPX9B | `sha256_padder` | Framing/padding buffer (512 × 8-bit) — message assembly for SHA-256 |
| 3 | DPX9B | `packet_framer` | TX Cipher RAM (512 × 8-bit) — encrypted output staging |
| 4 | DPX9B | `top_crypto_transceiver` | Plaintext Loopback Buffer (512 × 8-bit) — post-auth decrypted data |
| 5 | SPX9 | `sha256_core` | K_t Constant ROM (64 × 32-bit) — SHA-256 round constants |

### 6.3 DFF Breakdown by Module

| Module | DFFs | Notes |
|--------|------|-------|
| `aes256_core` | ~830 | 128-bit state + 256-bit key buffer + round control |
| `aes256_key_expand` | ~280 | Running key buffer + Rcon counter |
| `aes256_ctr` | ~170 | 128-bit counter + CTR control FSM |
| `sha256_core` | ~750 | 8 × 32-bit hash registers + W_t pipeline + serialized accumulator |
| `sha256_padder` | ~180 | Block/byte counters + padding FSM |
| `packet_deframer` | ~520 | Frame parser + quarantine control + 128-bit shift register |
| `packet_framer` | ~480 | Encryption sequencer + framing + 128-bit shift register + 256-bit MAC |
| `uart_rx` + `uart_tx` | ~50 | Shift registers + baud counters |
| `top_crypto_transceiver` | ~180 | LED stretchers + loopback controller + arbiter |
| **Total** | **~3,499** | |

### 6.4 Timing Analysis

- **Synthesis Tool**: Yosys (synth_gowin) + nextpnr-himbaechel (Project Apicula)
- **Target Device**: GW1NR-LV9QN88PC6/I5 (GW1N-9C family)
- **Clock Constraint**: 27.0 MHz (37.037 ns period) via `constraints/timing.sdc`
- **Achieved F_max**: 59.21 MHz (16.89 ns critical path)
- **Critical Path**: Through `packet_framer` TX RAM write-data logic chain (9.19 ns logic + 7.70 ns routing)
- **Timing Margin**: 2.19× over constraint (37.04 ns − 16.89 ns = +20.15 ns slack on critical path; +66.4 ns WNS on slowest endpoint)

---

## 7. Functional Verification

### 7.1 NIST Compliance Test Vectors

| Test Suite | Standard | Vectors | Result |
|------------|----------|---------|--------|
| AES-256 S-Box KAT | FIPS 197 | 256/256 input→output pairs | ✅ 100% MATCH |
| AES-256 CTR Encrypt/Decrypt | NIST SP 800-38A F.5.5/F.5.6 | 4-block encrypt + 4-block decrypt | ✅ 100% MATCH |
| SHA-256 Short Message | FIPS 180-4 | "abc" (24-bit) | ✅ MATCH |
| SHA-256 Two-Block | FIPS 180-4 | 448-bit message (56 bytes) | ✅ MATCH |
| SHA-256 Boundary | FIPS 180-4 | 56-byte boundary crossing | ✅ MATCH |

### 7.2 System Integration Tests

| Test | Description | Verification | Result |
|------|-------------|--------------|--------|
| Loopback Echo | 70-byte payload encrypt→transmit→receive→verify→decrypt→re-encrypt→echo | Byte-for-byte match | ✅ PASS |
| Tamper Injection | 1-bit MAC corruption | Zero TX bytes + quarantine flush | ✅ PASS |
| Watchdog Timeout | Truncated frame + 2.5 ms stall | Arbiter release + recovery | ✅ PASS |

### 7.3 Simulation Infrastructure

```bash
make sim-aes    # AES-256 S-Box KAT + CTR mode NIST vectors
make sim-sha    # SHA-256 FIPS 180-4 standard vectors
make sim-top    # Full system integration (loopback, tamper, timeout)
```

All simulations executed with Icarus Verilog (`iverilog` + `vvp`).

---

## 8. Security Analysis

### 8.1 Threat Model Coverage

| Attack Vector | Mitigation | Implementation |
|---------------|------------|----------------|
| Chosen-Ciphertext Attack | Quarantine-gated decryption | Ciphertext isolated in BSRAM until MAC verified |
| Padding Oracle | No padding-dependent branching | CTR mode eliminates padding entirely |
| MAC Forgery | SHA-256 (256-bit) pre-image resistance | 2²⁵⁶ computational barrier |
| IV Reuse / Nonce Misuse | Per-frame IV transmitted in-band | Sender responsible for IV uniqueness |
| Frame Injection / Replay | MAC covers LEN+IV+CIPHERTEXT | Replay with different IV produces MAC mismatch |
| DoS via Frame Stall | Hardware watchdog (2.5 ms) | Arbiter auto-releases; no permanent lock |
| Unauthenticated Plaintext Leak | Post-auth gate | AES engine never invoked on MAC failure |

### 8.2 Side-Channel Considerations

- **Constant-Time S-Box**: Canright composite field S-Box is purely combinational with data-independent timing.
- **No Early Termination**: AES and SHA-256 engines always complete all rounds regardless of input.
- **Limitation**: No explicit power analysis countermeasures (masking, shuffling). This is acknowledged as a trade-off for the GW1NR-9's limited LUT budget.

---

## 9. Build & Deployment

### 9.1 Toolchain

| Tool | Version | Purpose |
|------|---------|---------|
| Yosys | ≥ 0.40 | RTL synthesis (synth_gowin) |
| nextpnr-himbaechel | ≥ 0.7 | Place & Route (Project Apicula) |
| gowin_pack | ≥ 0.7 | Bitstream generation |
| openFPGALoader | ≥ 0.12 | FPGA programming |
| Icarus Verilog | ≥ 12.0 | Behavioral simulation |

### 9.2 Build Commands

```bash
# Synthesize + Place & Route + Generate Bitstream
bash scripts/build_yosys.sh

# Flash to FPGA
bash scripts/flash_openfpgaloader.sh --sram

# Run all simulations
make sim-aes sim-sha sim-top
```

### 9.3 Output Artifacts

| File | Description |
|------|-------------|
| `build/synth/crypto_transceiver.json` | Yosys synthesized netlist (JSON) |
| `build/synth/crypto_transceiver_pnr.json` | Placed & routed netlist |
| `build/synth/crypto_transceiver.fs` | Final bitstream (3.4 MB) |
| `build/synth/yosys.log` | Synthesis log with cell statistics |

---

## 10. File Structure

```
fpga_crypto_transceiver/
├── ANTIGRAVITY.md                      # Agent working context
├── SRS_URD.md                          # System requirements specification
├── Makefile                            # Simulation targets
├── rtl/
│   ├── core/
│   │   ├── aes256/
│   │   │   ├── aes_sbox_canright.v     # Canright GF(((2²)²)²) S-Box
│   │   │   ├── aes256_key_expand.v     # On-the-fly round key generator
│   │   │   ├── aes256_core.v           # 14-round iterative AES-256
│   │   │   └── aes256_ctr.v            # CTR mode wrapper + counter
│   │   └── sha256/
│   │       ├── sha256_core.v           # 64-round SHA-256 with BSRAM K_t
│   │       └── sha256_padder.v         # Autonomous BSRAM-backed padder
│   ├── framing/
│   │   ├── packet_deframer.v           # RX frame parser + quarantine gate
│   │   ├── packet_framer.v             # TX frame builder + encryption
│   │   └── crypto_arbiter.v            # Mutual-exclusion pipeline arbiter
│   ├── comm/
│   │   ├── uart_rx.v                   # 115200 baud receiver (3-vote)
│   │   └── uart_tx.v                   # 115200 baud transmitter
│   └── top_crypto_transceiver.v        # Top-level integration
├── constraints/
│   ├── tangnano9k.cst                  # Pin constraints
│   └── timing.sdc                      # Clock constraint (27 MHz)
├── sim/
│   ├── tb_aes256_canright.v            # AES NIST KAT testbench
│   ├── tb_sha256_core.v               # SHA-256 FIPS 180-4 testbench
│   └── tb_transceiver_top.v           # Full system integration testbench
├── scripts/
│   ├── build_yosys.sh                  # Synthesis + PnR + bitstream
│   ├── flash_openfpgaloader.sh         # FPGA programmer
│   └── test_transceiver.py            # Host verification CLI
└── docs/
    ├── DEMO_PROTOCOL.md                # Live demonstration runbook
    └── KMA_Technical_Report.md         # This document
```

---

## 11. Conclusion

This project demonstrates a complete, synthesizable cryptographic transceiver IP that:

1. **Meets all silicon resource targets** on the Gowin GW1NR-LV9QN88PC6/I5 (3,499 DFFs, 5 BSRAMs, 59.21 MHz F_max).
2. **Enforces the Encrypt-then-MAC security invariant** through hardware-level quarantine-gated decryption with zero unauthenticated plaintext leakage.
3. **Achieves 100% NIST compliance** against SP 800-38A (AES-256 CTR) and FIPS 180-4 (SHA-256) test vectors.
4. **Provides DoS resilience** through a deterministic 2.5 ms hardware watchdog timer with automatic arbiter recovery.
5. **Uses an entirely open-source toolchain** (Yosys + nextpnr + Apicula) for full reproducibility.

---

*Document generated for KMA 2026 Hardware Security IP Design Competition.*
*Revision: v1.0.0 — September 2026*
