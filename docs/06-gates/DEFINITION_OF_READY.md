# DEFINITION OF READY — Điều kiện được phép bắt đầu

**Artifact #8a / 11** · Cập nhật: 2026-09-09 · Trạng thái: Baseline v1.0

---

## 1. Mục đích

Ngăn việc bắt đầu một work package khi chưa đủ thông tin — dẫn tới viết code dựa trên giả
định, rồi phải bỏ đi.

Một WP **chưa Ready** thì không được bắt đầu, kể cả khi "thấy sốt ruột".

## 2. Checklist chung cho mọi WP

Đánh dấu đủ 7 mục mới được bắt đầu:

- [ ] **R1** — WP có ít nhất một REQ-ID gắn với nó trong `WBS.md`.
- [ ] **R2** — Tiêu chí chấp nhận của WP là **đo được**, không phải "chạy tốt", "ổn định".
- [ ] **R3** — Mọi WP phụ thuộc đã qua gate Done của nó.
- [ ] **R4** — Đã biết sẽ dùng **vector/dữ liệu test nào**, và nguồn của nó.
- [ ] **R5** — Đã biết WP này nằm ở vùng ủy quyền nào (Xanh/Vàng/Đỏ) trong `RISK_DELEGATION.md` §3.
- [ ] **R6** — Đã biết nếu WP này thất bại thì làm gì (có ghi ở sổ rủi ro hoặc ADR).
- [ ] **R7** — Ngân sách tài nguyên của WP đã có số cụ thể (nếu WP tạo ra RTL).

## 3. Checklist riêng theo loại WP

### WP tạo IP core (WP-03, WP-04)

- [ ] Đã có bản in vector chính thức từ tài liệu NIST/FIPS, ghi rõ số mục lục.
- [ ] Đã đọc và hiểu `IP_INTERFACE_CONTRACT.md` §2–§6.
- [ ] Đã có ngân sách LUT4 riêng cho IP đó.
- [ ] Đã quyết định trước cách chia module con (ghi vào `MODULE_MAP.md`).

### WP tạo lớp tích hợp (WP-05, WP-06)

- [ ] Sơ đồ luồng dữ liệu từng bước đã có trong `ARCHITECTURE.md` §3.
- [ ] Đã có IP giả lập (stub) để test độc lập với IP thật.
- [ ] Đã liệt kê đủ các trạng thái lỗi và hành vi tương ứng (`ARCHITECTURE.md` §7).

### WP chạm phần cứng (WP-01, WP-07, WP-08, WP-09)

- [ ] Board đã cắm và `dmesg` xác nhận enumerate.
- [ ] Biết chắc cổng nào là UART (`ttyUSB1`), cổng nào là JTAG (`ttyUSB0`).
- [ ] Không có tiến trình `openFPGALoader` cũ đang giữ thiết bị.
- [ ] Đã có kế hoạch phân biệt "FPGA từ chối đúng" với "FPGA chết" (REQ-V-04).
- [ ] Lệnh nạp bitstream chạy **ở tiền cảnh**, không chạy nền.

### WP tài liệu (WP-10)

- [ ] Mọi WP kỹ thuật đã Done.
- [ ] Mọi con số định đưa vào báo cáo đều có file log gốc trong `10-devbook/evidence/`.

## 4. Ai xác nhận Ready

Người phụ trách WP tự đánh dấu, nhưng với các WP nằm ở **vùng Vàng hoặc Đỏ** thì phải có
xác nhận thứ hai. Ghi lại ở `10-devbook/DEVELOPMENT_BOOK.md`.
