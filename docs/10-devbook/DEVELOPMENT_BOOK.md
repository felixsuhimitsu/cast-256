# DEVELOPMENT BOOK — Đã thử gì, sai ở đâu, vì sao chọn hướng này

**Artifact xuyên suốt** · Cập nhật: 2026-09-09

---

## 1. Tài liệu này khác ADR ở chỗ nào

- **ADR** ghi *quyết định*: chọn gì, vì sao, hệ quả. Bất biến sau khi Accepted.
- **Development Book** ghi *quá trình*: đã thử gì, cái gì không chạy, số đo thật, người
  sửa AI ở đâu. Ghi thêm liên tục, không xóa.

Một điều sai đã thử mà không được ghi lại sẽ bị thử lại. Đó là lý do phần §4 tồn tại.

---

## 2. Nhật ký theo work package

### WP-00 — Khung dự án · TT: ✅ Done (2026-09-09)

**Đã làm:**
- Xóa `rtl/` và `sim/` cũ (giữ nguyên trong lịch sử git trên nhánh `main`), dựng cây mới
  theo `MODULE_MAP.md` §1: `config/`, `ip/aes256/`, `ip/sha256/`, `protocol/`, `fabric/`, `io/`.
- `sim/lib/tb_util.vh`: macro `CHECK_EQ` / `CHECK_TRUE` / `CHECK_LE` / `TB_END` / `TB_TIMEOUT`.
  `TB_END` dùng `$fatal(1,...)` để iverilog trả **mã thoát khác 0** khi FAIL — điều kiện
  của REQ-V-01. Nếu chỉ `$finish` thì testbench FAIL vẫn trả 0 và CI sẽ báo xanh sai.
- `sim/lib/csi_checker.v`: module kiểm tự động INV-1..6 và quy tắc bắt tay H2, H5 của hợp
  đồng CSI. Instantiate song song với IP, đếm vi phạm ra cổng `viol_count`.
- `scripts/check_headers.sh` (REQ-N-02), `scripts/check_layering.sh` (MODULE_MAP §4).
- `Makefile`: target `lint / sim-* / synth-aes / synth-sha / synth / flash / test / bench`.

**Ba chỗ đưa bài học cũ thẳng vào công cụ, không để trong đầu:**
1. `synth` dùng `2>&1 | tee` cho nextpnr — công cụ ghi toàn bộ ra stderr, thiếu `2>&1`
   thì log luôn 0 byte (§4.1 mục 8).
2. `YOSYS_FLAGS` cố định `-nowidelut` kèm bình luận giải thích, để không ai bỏ đi lần nữa
   (§4.1 mục 3).
3. Target `test`/`bench` gọi `/usr/bin/python3` tường minh, không dùng `python3` (§4.1 mục 9).
   `PORT` mặc định `/dev/ttyUSB1`, có ghi chú `ttyUSB0` là JTAG (§4.1 mục 5).

**Tự kiểm gate (quan trọng):** `make lint` chạy sạch trên cây rỗng — nhưng "sạch" khi
không có gì để kiểm là vô nghĩa, đúng kiểu Done giả số 1 trong `DEFINITION_OF_DONE.md` §4.
Vì vậy đã dựng vi phạm cố ý để kiểm chính cái gate:

| Vi phạm dựng lên | Gate | Kết quả |
|---|---|---|
| File trong `ip/aes256/` không có header | `check_headers.sh` | FAIL, exit=1 ✅ |
| Module trong `ip/` instantiate module của `io/` | `check_layering.sh` | FAIL, exit=1 ✅ |
| (sau khi dọn) | cả hai | PASS, exit=0 ✅ |

Gate được chứng minh là bắt được vi phạm thật, không phải luôn xanh.

**Còn nợ:** `constraints/tangnano9k.cst` trên nhánh này vẫn để 3 LED ở `LVCMOS18` trong
khi `rst_n` (chân 3) là `LVCMOS33`. Hai mức điện áp trong cùng IO bank làm `gowin_pack`
dừng và **không sinh ra bitstream nào cả**. Đây là thay đổi thuộc **vùng ĐỎ** (mức điện
áp chân), sẽ xử lý ở WP-01 và phải được người xác nhận trước khi commit.

### WP-01 — Đường ống UART trần · TT: ⬜
*(chưa có mục)*

### WP-02 — Thăm dò diện tích · TT: ⬜
*(chưa có mục)*

### WP-03 — IP SHA-256 · TT: ⬜
*(chưa có mục)*

### WP-04 — IP AES-256 · TT: ⬜
*(chưa có mục)*

### WP-05 — Fabric CSI · TT: ⬜
*(chưa có mục)*

### WP-06 — Lớp giao thức · TT: ⬜
*(chưa có mục)*

### WP-07 — Tích hợp phần cứng · TT: ⬜
*(chưa có mục)*

### WP-08 — Đo hiệu năng · TT: ⬜
*(chưa có mục)*

### WP-09 — Test đối kháng · TT: ⬜
*(chưa có mục)*

### WP-10 — RTM & báo cáo · TT: ⬜
*(chưa có mục)*

---

## 3. Số đo thật

Chỉ ghi số **đọc từ log công cụ**, không ghi số ước lượng. Mỗi dòng phải trỏ được về một
file trong `evidence/`.

### 3.1 Tài nguyên theo module (tổng hợp riêng lẻ)

| Ngày | Module | LUT4 | DFF | Ngân sách | Đạt? | Log |
|---|---|---|---|---|---|---|
| — | — | — | — | — | — | — |

### 3.2 Tài nguyên toàn thiết kế

| Ngày | Commit | LUT4 | % | DFF | % | BSRAM | F_max | Log |
|---|---|---|---|---|---|---|---|---|
| — | — | — | — | — | — | — | — | — |

### 3.3 Hiệu năng phần cứng

| Ngày | Chế độ | Số khung | Mất | Thông lượng | Độ trễ avg | Log |
|---|---|---|---|---|---|---|
| — | — | — | — | — | — | — |

---

## 4. Những thứ đã thử và KHÔNG chạy

Phần này quý hơn phần "đã chạy". Ghi lại để không ai (kể cả AI trong phiên sau) thử lại.

### 4.1 Từ thiết kế trước — đã kiểm chứng, không lặp lại

| # | Đã thử | Kết quả | Vì sao sai |
|---|---|---|---|
| 1 | Thêm HMAC-SHA-256 vào bitstream | 7359/8640 LUT4 (85%), P&R **FAIL** | Hai instance SHA không vừa. Xem ADR-0004 |
| 2 | "Tối ưu" HMAC bằng thanh ghi dịch | 7724 LUT4 (89%) — **tệ hơn** | Mỗi bit cần mux 3 chiều nạp/dịch/giữ, đắt hơn thanh ghi thường |
| 3 | Bỏ cờ `-nowidelut` để dùng LUT rộng | 9248 LUT4 (107%) — **tệ hơn nhiều** | Trên Gowin, MUX2_LUT5..8 được dựng **từ chính LUT4**. Không hề tiết kiệm, còn thêm chi phí định tuyến |
| 4 | Đổ lỗi cáp sạc khi board không enumerate | Sai — đổi cáp thứ hai vẫn không lên | Nguyên nhân thật ở đầu cắm phía chip. Bài học: chẩn đoán một-nguyên-nhân quá sớm |
| 5 | Đọc `/dev/ttyUSB0` để lấy dữ liệu UART | Ra dữ liệu rác, tưởng lỗi giao thức | `ttyUSB0` là kênh **JTAG** của FT2232. Kênh UART là `ttyUSB1` |
| 6 | Giả thuyết đảo chân UART 17/18 | Sai — bitstream thăm dò chứng minh chân đúng | Mất thời gian vì đoán thay vì đo |
| 7 | Chạy lệnh nạp bitstream ở chế độ nền | Tiến trình treo giữ thiết bị FTDI, phải rút cắm lại | Lệnh chạm phần cứng phải chạy tiền cảnh |
| 8 | `\| tee nextpnr.log` để lưu log P&R | File luôn 0 byte | nextpnr ghi ra **stderr**. Phải `2>&1 \| tee` |
| 9 | Dùng `python3` sau khi `source oss-cad-suite/environment` | `pyserial is required` | Toolchain che `python3` hệ thống bằng bản riêng. Gọi `/usr/bin/python3` |
| 10 | Đọc bản báo cáo telemetry **đầu tiên** sau khi gửi | Số liệu vô nghĩa | Khung mất 10.2 ms, báo cáo mỗi 300 ms → mẫu rơi giữa khung. Phải đọc bản **cuối** |

### 4.2 Trong dự án này

*(chưa có mục)*

---

## 5. Human correction log — bằng chứng người can thiệp

Theo `../05-risk/RISK_DELEGATION.md` §4: một artifact chỉ được đánh ✅ khi người phụ trách
đã chỉ ra ít nhất một chỗ AI sai hoặc thiếu, và sửa lại.

| Ngày | Artifact | AI sai/thiếu chỗ nào | Người sửa thành | Ai |
|---|---|---|---|---|
| — | — | — | — | — |

> **Bảng này đang rỗng.** Nghĩa là chưa artifact nào được review thật sự, dù chúng trông
> hoàn chỉnh. Đây là trạng thái trung thực, không phải thiếu sót về hình thức — và nó là
> việc tiếp theo phải làm trước khi đánh dấu bất kỳ artifact nào là Done.

Gợi ý những chỗ đáng soi kỹ nhất, vì đó là chỗ AI dễ sai nhất:

1. **Ngân sách LUT4 trong `MODULE_MAP.md` §2** — các con số này là *ước lượng của AI*,
   chưa đo. Tổng 7690 chỉ dư 11%. Nếu ước lượng lệch 15% thì kế hoạch vỡ. WP-02 tồn tại
   để kiểm chính chỗ này.
2. **Ngân sách timing trong `ARCHITECTURE.md` §6** — các số ns là ước đoán, chưa chạy
   phân tích tĩnh nào.
3. **Ước lượng PERT trong `ESTIMATION.md`** — dựa trên cảm tính, không có dữ liệu lịch sử
   của chính đội này.
4. **Danh mục test case** — kiểm xem có test nào "kiểm sai thứ" giống bug ở §4.1 mục 1
   của TEST_PLAN không.
5. **Số chu kỳ REQ-P-05/06** (≤20 và ≤70) — kiểm lại bằng tay xem có khả thi với kiến
   trúc đã chọn không, hay là con số đặt cho đẹp.

---

## 6. Thư mục bằng chứng

`evidence/` chứa log gốc, không chỉnh sửa:

```
evidence/
├── synth/       báo cáo nextpnr theo ngày, đặt tên <ngày>-<commit ngắn>.log
├── sim/         đầu ra testbench
└── hw/          log chạy trên board, có timestamp
```

Quy tắc: **mọi con số xuất hiện trong báo cáo nộp phải truy được về một file ở đây.**
