# WBS — Phân rã công việc

**Artifact #5 / 11** · Cập nhật: 2026-09-09 · Trạng thái: Baseline v1.0

---

## 1. Nguyên tắc phân rã

Chia theo **lát cắt dọc (vertical slice)**, không theo tầng. Mỗi work package kết thúc
bằng một thứ *chạy được và đo được*, không phải bằng "một tầng đã viết xong".

Lý do: nếu chia theo tầng, rủi ro lớn nhất (AES + SHA có vừa thiết bị không?) chỉ lộ ra
ở cuối. Chia dọc thì rủi ro đó lộ ra ở WP-02.

## 2. Bảng work package

| WP | Tên | Đầu ra kiểm chứng được | Phụ thuộc | REQ liên quan |
|---|---|---|---|---|
| **WP-00** | Khung dự án | Makefile, cây thư mục, `csi_assert.vh`, CI lint chạy sạch | — | REQ-N-01, REQ-N-02 |
| **WP-01** | Đường ống UART trần | Bitstream echo byte; **test 512 byte liên tục, 0 mất** | WP-00 | REQ-I-03, REQ-I-04, REQ-I-05 |
| **WP-02** | Thăm dò diện tích | Tổng hợp AES rỗng + SHA rỗng, đọc số LUT4 thật, so ngân sách | WP-00 | REQ-R-01, REQ-R-03, REQ-R-04 |
| **WP-03** | IP SHA-256 | `make sim-sha` PASS toàn vector FIPS 180-4 | WP-00, WP-02 | REQ-F-10..14 |
| **WP-04** | IP AES-256 | `make sim-aes` PASS toàn vector FIPS 197 + SP 800-38A | WP-00, WP-02 | REQ-F-01..07 |
| **WP-05** | Fabric CSI | Testbench giả lập 2 IP, kiểm INV-1..6 và loại trừ tương hỗ | WP-03, WP-04 | REQ-I-01, REQ-I-02, REQ-F-25 |
| **WP-06** | Lớp giao thức | `make sim-top` PASS: khung hợp lệ, khung hỏng, khung dở, LEN sai | WP-05 | REQ-F-20..25 |
| **WP-07** | Tích hợp phần cứng | Bitstream đầy đủ nạp được, LED đúng, echo một khung PASS | WP-01, WP-06 | REQ-F-30..32, REQ-P-01 |
| **WP-08** | Đo hiệu năng | Log thật: 100 khung, tỉ lệ mất, độ trễ, thông lượng | WP-07 | REQ-P-02..04, REQ-V-03 |
| **WP-09** | Test đối kháng | Tamper/timeout/rác phân biệt được "từ chối đúng" vs "chết" | WP-07 | REQ-V-04 |
| **WP-10** | Đóng RTM & báo cáo | RTM không ô trống, Development Book đầy đủ, báo cáo nộp | tất cả | REQ-V-01..04, G5 |

## 3. Chi tiết từng WP

### WP-00 — Khung dự án
- `Makefile` với các target: `lint`, `sim-<x>`, `synth`, `flash`, `test`.
- Header chuẩn cho mọi file RTL (REQ-N-02) — có script kiểm.
- `sim/lib/csi_assert.vh`: assertion dùng chung cho hợp đồng CSI.
- **Gate:** `make lint` chạy sạch trên cây rỗng; `make` tự in danh sách target.

### WP-01 — Đường ống UART trần (rủi ro cao, làm sớm)
- `baud_gen`, `uart_rx`, `uart_tx`, top echo tối giản.
- **Bài test bắt buộc:** gửi 512 byte **không có khoảng nghỉ**, đếm byte nhận lại.
- **Gate:** 0 byte mất. Nếu mất byte, dừng — không đi tiếp WP nào khác.

> WP này đứng thứ hai trong toàn dự án vì đúng lỗi này đã âm thầm giết mọi khung ở thiết
> kế trước, và mô phỏng không bắt được (testbench luôn chèn khoảng nghỉ giữa byte).
> Xem `ADR-0005`.

### WP-02 — Thăm dò diện tích (rủi ro cao, làm sớm)
- Viết **khung rỗng** của AES và SHA: đúng cấu trúc, đúng độ rộng đường dữ liệu, logic
  bên trong tối giản nhưng không bị tối ưu hóa mất.
- Tổng hợp riêng từng IP, ghi số LUT4 thật vào Development Book.
- **Gate:** AES ≤ 2200, SHA ≤ 1800. Vượt ⟹ dừng, mở ADR, đàm phán lại ngân sách hoặc
  scope. **Không được viết tiếp rồi tính sau.**

### WP-03 — IP SHA-256
Thứ tự: `sha256_k` → `sha256_compress` → `sha256_sched` → `sha256_pad` → `sha256_ip`.
- **Gate:** vector `""`, `"abc"`, 55B, 56B, 64B, 119B, 1M×'a' đều đúng; INV-1..6 pass;
  LUT4 thật ≤ 1800.

### WP-04 — IP AES-256
Thứ tự: `aes256_sbox` (đối chiếu 256 giá trị) → `aes256_keysched` (đối chiếu W[0..59])
→ `aes256_round` → `aes256_cipher` → `aes256_ctr_ip`.
- **Gate:** FIPS 197 C.3 đúng; SP 800-38A F.5.5 đúng cả 4 khối; ca counter wrap đúng;
  INV-1..6 pass; LUT4 thật ≤ 2200.

### WP-05 — Fabric CSI
- `ip_arbiter` (ưu tiên cố định, không starvation vì FSM tuần tự), `stream_mux`.
- Testbench dùng **IP giả lập** (behavioral stub) để test fabric độc lập với IP thật.
- **Gate:** assertion `aes_busy & sha_busy` không bao giờ = 1; chuyển giao IP đúng thứ tự
  SHA→AES→SHA.

### WP-06 — Lớp giao thức
- `frame_rx`, `frame_buffer`, `digest_check`, `session_fsm`, `frame_tx`.
- **Gate:** 4 kịch bản mô phỏng đều đúng: khung hợp lệ trả về đúng; khung lật 1 bit → im
  lặng; khung cắt giữa chừng → watchdog rồi khung sau vẫn nhận; LEN=0 và LEN=1024 → loại.

### WP-07 — Tích hợp phần cứng
- Ghép tất cả, tổng hợp thật, nạp thật.
- **Gate:** P&R thành công, F_max ≥ 27 MHz, một khung khứ hồi PASS trên board thật.

### WP-08 — Đo hiệu năng
- `scripts/hw_test.py --mode bench`: 100 khung × 128 byte.
- **Gate:** 0% mất, độ trễ ≤ 40 ms, thông lượng ≥ 8000 B/s. Log lưu vào
  `docs/10-devbook/evidence/`.

### WP-09 — Test đối kháng
- `--mode tamper`: lật bit → **và** ngay sau đó gửi một khung hợp lệ để chứng minh FPGA
  còn sống. Test chỉ kiểm "0 byte trả về" bị coi là không hợp lệ (REQ-V-04).
- `--mode timeout`, `--mode garbage` (32 byte rác trước preamble).
- **Gate:** cả ba kịch bản đúng, **kèm** bằng chứng liveness.

### WP-10 — Đóng RTM & báo cáo
- **Gate:** mọi REQ-ID có ≥ 1 module và ≥ 1 test case; mọi module có ≥ 1 REQ-ID; không
  có mục "TBD" trong RTM.

## 4. Đường găng (critical path)

```
WP-00 → WP-02 → WP-04 → WP-05 → WP-06 → WP-07 → WP-08 → WP-10
```

WP-01 và WP-03 chạy song song được, nhưng WP-01 phải xong trước WP-07.

Hai điểm gate cứng — nếu trượt thì dừng toàn dự án để tái đàm phán scope:
- **WP-01** (UART chịu tải liên tục)
- **WP-02** (diện tích)

## 5. Thứ tự khuyến nghị khi làm

1. WP-00
2. **WP-02** ← đo diện tích trước khi viết bất cứ logic thật nào
3. **WP-01** ← chứng minh đường truyền trước khi tin vào bất cứ kết quả nào từ nó
4. WP-03, WP-04
5. WP-05 → WP-06 → WP-07 → WP-08 → WP-09 → WP-10

Hai bước đầu tiên sau khung dự án đều là **kiểm chứng giả định**, không phải xây tính
năng. Đó là chủ đích.
