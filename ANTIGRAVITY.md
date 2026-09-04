# ANTIGRAVITY.md - Agent Working Context & Design Guidelines

## 1. Mission & Core Objective

Design, verify, and synthesize a high-throughput, resource-efficient hardware cryptographic coprocessor IP on the Sipeed Tang Nano 9K development board:
**"Thiết kế và tích hợp IP mã hóa AES-256 và SHA-256 cho giao thức truyền và nhận dữ liệu"**
(Integrated AES-256 Cipher & SHA-256 Message Authentication IP for Secure Half-Duplex Data Transceiver Protocol).

---

## 2. Target Silicon & Board Specifications

* FPGA Device: Gowin LittleBee GW1NR-LV9QN88PC6/I5.
* Logic Capacity: 8,640 4-input LUTs (LUT4), 6,480 Flip-Flops.
* Memory: 26 Block SRAMs (BSRAMs, 18 Kbit each, 468 Kbit total).
* DSP Slices: 2x MULT18X18 (not used for symmetric crypto).
* Master Oscillator: 27.0 MHz crystal directly mapped to Pin 52.
* Onboard Physical Interfaces:
  * `clk_27m`: Pin 52, 3.3V LVCMOS
  * `rst_n`: Pin 3, Button S1, active-low
  * `uart_tx`: Pin 17, 3.3V LVCMOS, to onboard BL702 bridge
  * `uart_rx`: Pin 18, 3.3V LVCMOS, from onboard BL702 bridge
  * `led_tx_active`: Pin 10, 1.8V LVCMOS (Active-Low)
  * `led_rx_pass`: Pin 11, 1.8V LVCMOS (Active-Low)
  * `led_mac_err`: Pin 13, 1.8V LVCMOS (Active-Low)

---

## 3. Cryptographic Architecture Constraints

### A. Resource Budgeting (Strict Silicon Limits)

The total design must consume fewer than 4,500 LUT4s (<55% capacity) to guarantee clean place-and-route closure on nextpnr-himbaechel:

1. **AES-256 Datapath & Canright S-Box:**
   * Mode: Counter Mode (CTR). Forward cipher datapath only.
   * Iterative 14-Round Datapath: Single shared round datapath executed sequentially over 14 clock cycles. Do NOT unroll rounds in parallel.
   * Minimal-Area S-Box: Implement SubBytes using Composite Galois Field $GF(((2^2)^2)^2)$ isomorphic mapping (Canright minimal-area S-Box architecture) consuming ~65 LUT4s per byte to prevent exceeding logic budget. Total AES core area $\le 1{,}450$ LUT4s.
   * Key Expansion: On-the-fly expansion or compact registered round key buffer.

2. **SHA-256 Engine & Deterministic Padding:**
   * NIST FIPS 180-4 compliant 64-round iterative compression core (1 round per clock cycle, 65 cycles per 512-bit block).
   * BSRAM-backed autonomous hardware padder: Ingest frames into Framing BSRAM and append `0x80`, variable zero-fill, and 64-bit length injection before block dispatch.

3. **Concurrency & Security Policies:**
   * Operational Model: Half-duplex master/slave transceiver with hardware mutual exclusion arbiter.
   * RX Precedence: UART RX preamble (`0xAA 0x55`) locks the crypto pipeline to RX mode, holding pending TX transfers.
   * Gated Post-Auth Decryption: Ciphertext is stored in an isolated Quarantine BSRAM partition. AES-256 decryption executes strictly AFTER SHA-256 MAC verification passes. Zero unauthenticated plaintext is ever leaked.

---

## 4. Communication Protocol & Framing Structure

### A. Packet Serialization Format

All transactions across the UART physical medium follow this deterministic packet framing:

`[PREAMBLE (2B): 0xAA 0x55] [LEN (2B, Big Endian)] [IV / NONCE (16 Bytes)] [CIPHERTEXT (N * 16 Bytes)] [SHA-256 MAC (32 Bytes)] [POSTAMBLE (2B): 0x0D 0x0A]`

### B. UART Parameters

* Baud Rate: 115,200 bps.
* Clock Divisor: 234 (derived from 27.0 MHz / 115,200 = 234.375, +0.16% error).
* Frame Spec: 8 Data Bits, 1 Stop Bit, No Parity (8-N-1).
* Noise Rejection: UART RX pin sampling uses 3-sample majority voting at mid-bit period.

---

## 5. Coding & Synthesis Rules

1. **Verilog Dialect:** Strictly IEEE 1364-2001 synthesizable Verilog.
2. **Clock Domains:** Single synchronous 27.0 MHz clock domain. No clock dividers generating derived clock nets; use clock-enable pulses (`en_tick`).
3. **Reset Synchronization:** Active-low reset (`rst_n`) must pass through a 2-stage synchronizer before routing to any state machine or data register.
4. **Synchronous Memory Latency:** Pipeline all BSRAM read-enable signals by exactly 1 clock cycle to match synchronous output latency.
5. **No Undefined States:** All state machine case statements must explicitly handle `default` with recovery into an `IDLE` or `ERROR` state.
6. **Toolchain Target:**
   * Synthesis: Yosys (`synth_gowin`).
   * Place & Route: `nextpnr-himbaechel --device GW1NR-LV9QN88PC6/I5 --vopt family=GW1N-9C`.
   * Pack: Project Apicula (`gowin_pack`).
   * Simulation: Icarus Verilog (`iverilog`) + `vvp` + `GTKWave`.
