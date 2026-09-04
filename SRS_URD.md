# Software/System Requirements Specification & User Requirements Document (SRS/URD)

**Project:** Secure Half-Duplex Data Transceiver with Integrated AES-256 & SHA-256 IP Cores  
**Vietnamese Title:** Thiết kế và tích hợp IP mã hóa AES-256 và SHA-256 cho giao thức truyền và nhận dữ liệu  
**Target Platform:** Sipeed Tang Nano 9K (Gowin GW1NR-LV9QN88PC6/I5)  
**Standard Compliance:** NIST FIPS 197 (AES), NIST FIPS 180-4 (SHA-256), IEEE 1364-2001 Verilog  

---

## 1. System Overview & Architecture

The system implements a standalone hardware cryptographic transceiver core operating in a **half-duplex master/slave packet architecture** with strict hardware arbitration. The design integrates an iterative AES-256 engine operating in Counter (CTR) mode and a deterministic SHA-256 cryptographic digest engine operating in an **Encrypt-then-MAC** topology.

To prevent unauthenticated plaintext leakage and guarantee physical routability on the Gowin GW1NR-9 FPGA:
1. **Gated Post-Auth Decryption:** Inbound ciphertext is held in an isolated Quarantine BSRAM partition. Decryption is strictly gated until the entire incoming frame's SHA-256 MAC is validated. Forged or corrupted packets are purged without exposing plaintext.
2. **Minimal-Area S-Box Architecture:** AES `SubBytes` uses composite Galois Field $GF(((2^2)^2)^2)$ isomorphic mapping (Canright architecture) with time-multiplexed folding to constrain logic slice utilization well under 1,600 LUT4s.
3. **Hardware Arbiter & Mutual Exclusion:** A dedicated hardware arbiter grants mutually exclusive access to the shared AES and SHA execution pipelines, prioritizing inbound RX packet reception over outbound TX packet assembly.
4. **BSRAM-Backed Deterministic SHA-256 Padding:** Full frames are ingested into a dedicated Framing BSRAM prior to dispatching autonomous padding words (`1'b1`, zero-fill, and 64-bit length injection) to the 64-round compression core.

```
       +-----------------------------------------------------------------------------------------------+
       |                                   Gowin GW1NR-9 FPGA                                          |
       |                                                                                               |
       |       +-------------------------------------------------------------------------------+       |
       |       |                     Hardware Arbiter & Pipeline Mutex                         |       |
       |       +-------------------------------------------------------------------------------+       |
       |               ^                                                               |               |
       |    RX Preamble| (Locks Pipeline to RX)                     Grants Shared      |               |
       |    Detected   |                                            AES/SHA Execution  v               |
       |               |                                            +-------------------------------+  |
       |               |                                            | Shared AES-256 CTR Engine     |  |
       |               |                                            | (Canright GF(((2^2)^2)^2)     |  |
       |               |                                            +-------------------------------+  |
       |               |                                            +-------------------------------+  |
       |               |                                            | Shared SHA-256 Digest Core    |  |
       |               |                                            | (Iterative 64-Round Engine)   |  |
       |               |                                            +-------------------------------+  |
       |               |                                                                               |
RX Pin |  +------------+----+      +-------------------------+            +-------------------------+  |
(18)   |  | UART RX         | ===> | Quarantine BSRAM Buffer | ===[Gate]==> AES-256 Post-Auth Decrypt  |
       |  | (3-Sample Vote) |      | (Ciphertext + IV + LEN) |      |     | (Executes ONLY on MAC OK) |
       |  +-----------------+      +------------+------------+      |     +------------+------------+  |
       |                                        |                   |                  |               |
       |                                        v                   v                  v               |
       |                           +-------------------------+   MAC Match?   +------------------+     |
       |                           | Framing BSRAM & Padder  | ===[Verify]==> | Plaintext Buffer |     |
       |                           | (Feeds SHA-256 Engine)  |                | / Application RX |     |
       |                           +-------------------------+                +------------------+     |
       |                                                                                               |
TX Pin |  +-----------------+      +-------------------------+                +------------------+     |
(17)   |  | UART TX         | <=== | TX Serialization Buffer | <============= | AES-256 Encrypt  |     |
       |  | (115200 bps)    |      | (Preamble..MAC..Post)   |                | & SHA-256 Digest |     |
       |  +-----------------+      +-------------------------+                +------------------+     |
       |                                                                                               |
       |  Pins 10, 11, 13: Status & Integrity LEDs (TX Active, RX Auth Pass, MAC Corrupt Alert)        |
       +-----------------------------------------------------------------------------------------------+
```

---

## 2. Hardware Interfaces & Pin Allocation

| Port Name | Direction | Pin | Standard | Description |
|---|---|---|---|---|
| `clk_27m` | Input | 52 | 3.3V LVCMOS | 27.0 MHz Master Onboard Crystal |
| `rst_n` | Input | 3 | 3.3V LVCMOS | Active-Low Asynchronous Reset (Button S1, 2-stage synchronized) |
| `uart_rx` | Input | 18 | 3.3V LVCMOS | Serial Data In (from onboard BL702 USB-JTAG/UART bridge) |
| `uart_tx` | Output | 17 | 3.3V LVCMOS | Serial Data Out (to onboard BL702 USB-JTAG/UART bridge) |
| `led_tx_active` | Output | 10 | 3.3V LVCMOS | Active-Low LED: ON during active packet serialization and TX burst |
| `led_rx_pass` | Output | 11 | 3.3V LVCMOS | Active-Low LED: Latched ON when packet SHA-256 MAC validates successfully |
| `led_mac_err` | Output | 13 | 3.3V LVCMOS | Active-Low LED: Latched ON upon MAC mismatch, framing fault, or timeout |

---

## 3. Communication Protocol & Timing Specifications

### 3.1 UART Physical Layer Parameters

* **Master Frequency ($F_{clk}$):** $27{,}000{,}000\text{ Hz}$ ($T_{clk} \approx 37.037\text{ ns}$).
* **Target Baud Rate ($B$):** $115{,}200\text{ bps}$.
* **Baud Clock Divisor:**
  $$D_{uart} = \left\lfloor \frac{27{,}000{,}000}{115{,}200} + 0.5 \right\rfloor = \left\lfloor 234.375 \right\rfloor = 234$$
* **Actual Baud Rate:**
  $$B_{actual} = \frac{27{,}000{,}000}{234} \approx 115{,}384.62\text{ bps}$$
* **Timing Deviation:**
  $$\text{Error} = \frac{115{,}384.62 - 115{,}200}{115{,}200} \times 100\% = +0.1603\%$$
  *(Physical UART tolerance: $\pm 2.0\%$; margin is well within specification).*
* **Bit Period:**
  $$T_{bit} = 234 \times T_{clk} = 8.667\,\mu\text{s}$$
* **Byte Transmission Duration (10 bits: 1 Start, 8 Data, 1 Stop):**
  $$T_{byte} = 10 \times T_{bit} = 2{,}340\text{ clock cycles} \approx 86.667\,\mu\text{s}$$
* **Oversampling & Majority Voting:** Mid-bit sample window at cycles 116, 117, and 118 with 3-sample majority voting for noise rejection.

### 3.2 Packet Serialization Framing

```
+---------------+---------------+--------------------+--------------------------+---------------------+---------------+
| PREAMBLE (2B) |  LEN (2B, BE) |   IV / NONCE (16B) | CIPHERTEXT (N * 16B)     |   SHA-256 MAC (32B) | POSTAMBLE (2B)|
|   0xAA 0x55   | [LEN_H, LEN_L]|   IV[127:0]        | C_0, C_1, ..., C_{N-1}   |   Digest[255:0]     |   0x0D 0x0A   |
+---------------+---------------+--------------------+--------------------------+---------------------+---------------+
```

* **PREAMBLE (2 Bytes):** Frame sync word `0xAA 0x55`.
* **LEN (2 Bytes, Big-Endian):** Ciphertext payload length $L = N \times 16$ bytes. Supported dynamic payload range: $16 \le L \le 448$ bytes.
* **IV / NONCE (16 Bytes):** Initial 128-bit counter block for AES-CTR mode.
* **CIPHERTEXT ($N \times 16$ Bytes):** Encrypted payload blocks ($N \in [1, 28]$).
* **SHA-256 MAC (32 Bytes):** Authentication tag covering all preceding authenticated data:
  $$\text{MAC} = \text{SHA-256}(\text{LEN}[15:0] \mathbin{\Vert} \text{IV}[127:0] \mathbin{\Vert} \text{CIPHERTEXT}[8L-1:0])$$
* **POSTAMBLE (2 Bytes):** Frame terminator `0x0D 0x0A` (`\r\n`).
* **Frame Overhead:** $2 + 2 + 16 + 32 + 2 = 54\text{ Bytes}$.
* **Frame Size Limits:**
  * Minimum packet ($N=1, L=16\text{B}$): $54 + 16 = 70\text{ Bytes}$ ($T_{rx/tx} = 6.067\text{ ms}$).
  * Maximum packet ($N=28, L=448\text{B}$): $54 + 448 = 502\text{ Bytes}$ ($T_{rx/tx} = 43.507\text{ ms}$).

---

## 4. Hardware Arbitration & Concurrency Model

### 4.1 Half-Duplex Mutual Exclusion Policy

The device operates strictly in **Half-Duplex Master/Slave Mode** to enable sharing of single-instance AES-256 and SHA-256 hardware cores:
1. **RX Precedence:** Reception of an incoming preamble byte pair (`0xAA 0x55`) on UART RX triggers an immediate lock of the cryptographic datapath (`arb_rx_lock = 1'b1`).
2. **TX Hold:** If an application TX request arrives while `arb_rx_lock` is active, the TX FSM enters `TX_WAIT_BUSY`, latching `tx_pending = 1'b1`. Outbound transmission is deferred until the RX transaction completes (either through verified post-auth decryption, MAC error flush, or timeout abort).
3. **Pipeline Ownership:** AES-256 and SHA-256 core control lines are multiplexed by the arbiter:
   * When `arb_rx_lock = 1'b1`: Control assigned exclusively to `rx_frame_fsm` and `sha_pad_rx`.
   * When `arb_tx_lock = 1'b1`: Control assigned exclusively to `tx_frame_fsm` and `sha_pad_tx`.

```
 +--------------------------------------------------------------------------+
 |                         ARBITER STATE MACHINE                            |
 +--------------------------------------------------------------------------+
                                    |
                                    v
                             +-------------+
                             |  ARB_IDLE   |
                             +------+------+
                                    |
            +-----------------------+-----------------------+
            | Preamble Match                                | TX Request &
            v                                               v Not RX Active
     +--------------+                                +--------------+
     | ARB_RX_LOCKED|                                | ARB_TX_LOCKED|
     +-------+------+                                +-------+------+
             |                                               |
             | RX Complete (MAC OK + Decrypt                 | TX Frame Finished
             | OR MAC Error / Timeout Abort)                 | (Postamble Sent)
             v                                               v
     +--------------+                                        |
     | Release Lock | ---------------------------------------+
     +--------------+
```

---

## 5. Cryptographic Engines & Silicon Resource Optimization

### 5.1 AES-256 CTR Engine with Canright S-Box Architecture

#### 5.1.1 Silicon Budget Bottleneck Resolution
* **Problem:** A conventional logic lookup table implementation for AES S-Box requires $\approx 220\text{ LUT4s}$ per byte. 16 unrolled S-Boxes consume $16 \times 220 = 3{,}520\text{ LUT4s}$, which alone consumes $>78\%$ of the entire 4,500 LUT4 project budget.
* **Resolution:** SubBytes datapath utilizes **Composite Galois Field $GF(((2^2)^2)^2)$ Isomorphic Mapping** (Canright minimal-area S-Box):
  * Maps elements of $GF(2^8)$ to towers of subfields:
    $$GF(2) \longrightarrow GF(2^2) \longrightarrow GF((2^2)^2) \longrightarrow GF(((2^2)^2)^2)$$
  * Inversion in composite subfields converts the 8-bit non-linear inversion into compact XOR trees, reducing area to $\approx 65\text{ LUT4s}$ per S-Box instance.
  * **Folded Datapath Option:** 4 Canright S-Boxes time-multiplexed over 4 clock cycles ($4 \times 65 \approx 260\text{ LUT4s}$ for SubBytes) or 16 parallel Canright S-Boxes ($16 \times 65 \approx 1{,}040\text{ LUT4s}$).
  * We implement the **16-parallel Canright architecture** (~1,040 LUT4s for SubBytes) to complete 1 round per cycle (14 cycles total per 128-bit block). Total AES-256 core area is bounded at $\le 1{,}450\text{ LUT4s}$.

#### 5.1.2 AES Latency vs. UART Throughput
* Round latency: $14\text{ rounds} \times 1\text{ cycle} + 2\text{ overhead cycles} = 16\text{ clock cycles}$ ($592.6\text{ ns}$ at $27\text{ MHz}$).
* 16-byte UART ingestion window: $16 \times 2{,}340 = 37{,}440\text{ clock cycles}$.
* Execution speed margin: The AES core operates $2{,}340\times$ faster than serial line throughput.

---

### 5.2 Deterministic SHA-256 Framing & Hardware Message Scheduler

#### 5.2.1 BSRAM-Backed Framing & Zero-Deadlock Padding
Dynamic frames ($16 \le L \le 448$ bytes) authenticate $M = 18 + L$ bytes ($2\text{B LEN} + 16\text{B IV} + L\text{B CIPHERTEXT}$).

1. **Storage in Framing BSRAM:** As serial bytes arrive, they are written to consecutive byte addresses $0 \dots (M-1)$ in a 512-byte partition of a Gowin BSRAM.
2. **Padding Injection Sequence:** Upon receiving the final ciphertext byte:
   * **Pad Byte:** The padder writes byte `0x80` at address $M$.
   * **Zero Filling:** Addresses $(M + 1)$ through $(Block\_End - 9)$ are filled with `0x00`.
   * **Bit Length:** The 64-bit big-endian representation of total bit length $\lambda = M \times 8$ is written to the last 8 bytes of the final 512-bit (64-byte) block:
     $$Block\_Count = \begin{cases} 
     1 & \text{if } M \le 55 \text{ bytes (payload } L \le 37\text{B}) \\
     2 & \text{if } 56 \le M \le 119 \text{ bytes (payload } L \le 101\text{B}) \\
     k & \text{where } k = \lfloor \frac{M + 9 + 63}{64} \rfloor \le 8 \text{ blocks}
     \end{cases}$$
3. **Block Scheduler Dispatch:** The scheduler sequentially streams 64-byte blocks from BSRAM into the 64-round iterative SHA-256 compression core.
4. **Iterative Compression Timing:** $64\text{ rounds} + 1\text{ accumulation} = 65\text{ clock cycles}$ per 512-bit block. For maximum packet size (8 blocks), total hash computation requires $8 \times 65 = 520\text{ clock cycles}$ ($19.26\,\mu\text{s}$), completely negligible compared to UART byte delivery.

---

## 6. Detailed State Machines & Gated Post-Auth Decryption

### 6.1 Inbound RX Deframing, Validation & Gated Decryption Flow

```
                      +-------------------+
                      |      RX_IDLE      | <-----------------------------------------+
                      +---------+---------+                                           |
                                | Byte == 0xAA                                        |
                                v                                                     |
                      +-------------------+                                           |
                      |      RX_PRE1      |                                           |
                      +---------+---------+                                           |
                                | Byte == 0x55 (Assert arb_rx_lock)                   |
                                v                                                     |
                      +-------------------+                                           |
                      |      RX_LEN       | (Capture 2B LEN -> store Framing BSRAM)   |
                      +---------+---------+                                           |
                                |                                                     |
                                v                                                     |
                      +-------------------+                                           |
                      |       RX_IV       | (Capture 16B IV -> store Framing BSRAM    |
                      |                   |  and Quarantine BSRAM)                    |
                      +---------+---------+                                           |
                                |                                                     |
                                v                                                     |
                      +-------------------+                                           |
                      |     RX_CIPHER     | (Collect L Bytes -> store Framing BSRAM   |
                      |                   |  and Quarantine BSRAM. NO DECRYPT!)       |
                      +---------+---------+                                           |
                                |                                                     |
                                v                                                     |
                      +-------------------+                                           |
                      |      RX_MAC       | (Collect 32B MAC Tag into temp register)  |
                      +---------+---------+                                           |
                                |                                                     |
                                v                                                     |
                      +-------------------+                                           |
                      |  RX_POST1 & POST2 | (Verify 0x0D, 0x0A)                       |
                      +---------+---------+                                           |
                                | Postamble Valid                                     |
                                v                                                     |
                      +-------------------+                                           |
                      |    RX_SHA_PAD     | (Execute autonomous hardware padding)     |
                      +---------+---------+                                           |
                                |                                                     |
                                v                                                     |
                      +-------------------+                                           |
                      |   RX_SHA_DIGEST   | (Iterative compression: 65 cyc/block)     |
                      +---------+---------+                                           |
                                |                                                     |
                                v                                                     |
                      +-------------------+                                           |
                      |     RX_VERIFY     |                                           |
                      +---------+---------+                                           |
                                |                                                     |
          +---------------------+---------------------+                               |
          | MAC == Computed Digest?                   | MAC != Computed Digest        |
          v                                           v (Forged / Corrupted)          |
+-------------------+                       +-------------------+                     |
|    RX_DECRYPT     |                       |   RX_AUTH_FAIL    |                     |
| (Trigger AES-CTR  |                       | - Flush Quarantine|                     |
|  on Quarantine    |                       |   BSRAM pointers  |                     |
|  BSRAM blocks)    |                       | - Zero plaintext  |                     |
+---------+---------+                       | - Assert          |                     |
          | Decrypt Done                    |   `led_mac_err`   |                     |
          v                                 +---------+---------+                     |
+-------------------+                                 |                               |
|   RX_AUTH_PASS    |                                 v                               |
| - Commit Plaintext|                       +-------------------+                     |
|   to Buffer       |                       |   Release Locks   | --------------------+
| - Assert          |                       +-------------------+
|   `led_rx_pass`   |
+---------+---------+
          |
          v
+-------------------+
|   Release Locks   | ----------------------------------------------------------------+
+-------------------+
```

### 6.2 Outbound TX Assembly & Serialization Flow

```
[TX_IDLE]
   | Application triggers tx_start_req & arb_rx_lock == 0
   v (Assert arb_tx_lock)
[TX_LOAD_PLAIN]       --> Store plaintext in Framing BSRAM
   v
[TX_AES_ENCRYPT]      --> Run AES-CTR, write ciphertext back to Framing BSRAM
   v
[TX_SHA_PAD_COMPUTE]  --> Pad LEN||IV||CIPHERTEXT, compute 32-byte SHA-256 MAC
   v
[TX_SERIALIZE_STREAM] --> UART TX streams: [0xAA55] + [LEN] + [IV] + [CIPHER] + [MAC] + [0x0D0A]
   v
[TX_COMPLETE]         --> Assert `led_tx_active` pulse, release `arb_tx_lock`, return to [TX_IDLE]
```

---

## 7. Revised Silicon Resource Budget & P&R Targets

| Subsystem / Functional Block | Target Gowin Primitive | Estimated LUT4 | Estimated Flip-Flops | Dedicated BSRAM (18Kbit) |
|---|---|---|---|---|
| UART Physical Transceiver (TX/RX + 3-Sample Voter) | Logic Slice LUT4 + FF | 180 | 140 | 0 |
| Frame Controller & Hardware Mutual Exclusion Arbiter | Logic Slice LUT4 + FF | 380 | 290 | 0 |
| AES-256 CTR Engine (Iterative 14-R, Canright GF S-Boxes) | Logic Slice LUT4 + FF | 1,450 | 820 | 0 |
| SHA-256 Compression Engine & Message Padder | Logic Slice LUT4 + FF | 1,350 | 890 | 0 |
| Inbound Quarantine Buffer & Framing BSRAM | Gowin Dual-Port BSRAM | 60 | 40 | 2 (18 Kbit blocks) |
| Plaintext Output / Application Buffer | Gowin Dual-Port BSRAM | 40 | 30 | 1 (18 Kbit block) |
| Status Monitor & LED Registers | Logic Slice LUT4 + FF | 40 | 30 | 0 |
| **Total Project Footprint** | **GW1NR-9 FPGA** | **~3,500 (<41%)** | **~2,240 (<35%)** | **3 / 26 (11.5%)** |
| **Silicon Ceiling Limit** | | **4,500 (<55%)** | **3,500 (<54%)** | **10 / 26** |

---

## 8. Verification & Toolchain Acceptance Gates

1. **Gate 1 - Simulation Verification (Icarus Verilog + VVP):**
   * Canright S-Box composite Galois field equivalence test against standard AES lookup tables.
   * NIST SP 800-38A Known Answer Tests (KAT) for AES-256 CTR mode.
   * NIST FIPS 180-4 standard vectors for SHA-256 with multi-block padding.
   * Anti-tamper verification: Injected 1-bit MAC mismatch guarantees zero byte write to plaintext application buffer and asserts `led_mac_err`.
   * Arbiter testbench: Simultaneous UART RX burst and TX request confirms RX precedence without deadlock.
2. **Gate 2 - Synthesis & P&R Closure:**
   * Synthesis: Yosys (`synth_gowin -top top_crypto_transceiver`).
   * P&R: `nextpnr-himbaechel --device GW1NR-LV9QN88PC6/I5 --vopt family=GW1N-9C`.
   * Constraints: Zero unrouted nets, worst negative slack (WNS) $\ge 0\text{ ns}$ at $27.0\text{ MHz}$.
3. **Gate 3 - Bitstream Generation:**
   * Bitstream packaging via Project Apicula (`gowin_pack`).
