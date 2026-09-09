# DEFINITION OF DONE — Điều kiện được coi là xong

**Artifact #8b / 11** · Cập nhật: 2026-09-09 · Trạng thái: Baseline v1.0

---

## 1. Nguyên tắc

> "Chạy được rồi" **không phải** Done.
> "AI viết xong rồi" **không phải** Done.
> "Test PASS" một mình cũng **không phải** Done.

Done = code đúng **và** bằng chứng tồn tại **và** tài liệu đã đồng bộ **và** người phụ
trách hiểu nó.

## 2. Checklist chung cho mọi WP

- [ ] **D1** — Mọi tiêu chí chấp nhận ở `WBS.md` §3 của WP này đều đạt, có bằng chứng.
- [ ] **D2** — `make lint` sạch: không cảnh báo latch, không cảnh báo width mismatch.
- [ ] **D3** — Mọi testbench liên quan PASS, và **trả mã thoát 0**; FAIL phải trả khác 0.
- [ ] **D4** — Mọi REQ-ID của WP đã có dòng trong `08-traceability/RTM.md`, không "TBD".
- [ ] **D5** — Tài liệu bị ảnh hưởng đã cập nhật **trong cùng commit** (docs/README §3).
- [ ] **D6** — Mỗi file RTL mới có header ghi mục đích + REQ-ID (REQ-N-02).
- [ ] **D7** — Nếu có quyết định đánh đổi: đã có ADR trong `09-decisions/`.
- [ ] **D8** — Development Book có mục ghi: đã thử gì, sai ở đâu, vì sao chọn hướng này.
- [ ] **D9** — **Human correction log** có ít nhất một mục cho WP này (RISK §4).
- [ ] **D10** — Số đo thật (LUT4/DFF/F_max nếu có) đã ghi vào Development Book §Số đo.

## 3. Checklist riêng

### IP core (WP-03, WP-04)

- [ ] Vượt **100%** vector chính thức, không phải "phần lớn".
- [ ] Bất biến INV-1..6 của hợp đồng CSI được assertion kiểm, không phải kiểm bằng mắt.
- [ ] Tổng hợp riêng lẻ được, số LUT4 thật ≤ ngân sách trong `MODULE_MAP.md`.
- [ ] Không có cổng nào ngoài danh sách `IP_INTERFACE_CONTRACT.md` §2.
- [ ] Không có phụ thuộc vào `protocol/`, `io/`, `fabric/`.

### Lớp tích hợp (WP-05, WP-06)

- [ ] Assertion chứng minh `aes_busy & sha_busy` không bao giờ = 1.
- [ ] Cả 4 kịch bản lỗi ở `ARCHITECTURE.md` §7 đều có test và đều đúng.
- [ ] Script kiểm ràng buộc phụ thuộc tầng chạy sạch.

### Phần cứng (WP-07, WP-08, WP-09)

- [ ] Có **log thật từ board**, lưu trong `10-devbook/evidence/`, có timestamp.
- [ ] Kết quả mô phỏng **không** được dùng thay cho log phần cứng (REQ-V-03).
- [ ] Mọi test "từ chối" đều kèm bằng chứng liveness ngay sau đó (REQ-V-04).
- [ ] Báo cáo timing của nextpnr được lưu lại, không chỉ đọc rồi bỏ.

### Toàn dự án (WP-10)

- [ ] RTM: mọi REQ có ≥1 module **và** ≥1 test case.
- [ ] RTM: mọi module có ≥1 REQ (không có module mồ côi).
- [ ] Mọi con số trong báo cáo nộp truy được về một file log cụ thể.
- [ ] Mọi hạn chế đã biết được ghi trung thực, không giấu (SRS §10).

## 4. Bốn cách thường gặp để "Done giả"

Ghi ra đây vì đã gặp thật, để nhận diện sớm:

| Kiểu Done giả | Dấu hiệu | Cách chặn |
|---|---|---|
| **Test kiểm sai thứ** | Test tamper PASS trong khi bitstream hỏng hoàn toàn — vì nó chỉ kiểm "0 byte trả về" | REQ-V-04, mục D3 + liveness |
| **Mô phỏng thay phần cứng** | "Testbench PASS nên chắc chạy được" — nhưng testbench chèn khoảng nghỉ giữa byte, phần cứng thì không | REQ-V-03, mục D3 phân biệt sim/hw |
| **Tối ưu theo suy đoán** | "Đổi cách này chắc nhỏ hơn" rồi commit mà không đo | D10 bắt buộc số đo thật |
| **Tài liệu trôi** | Code sửa, tài liệu giữ nguyên, sau 5 commit thì tài liệu mô tả một hệ thống đã chết | D5 cùng-commit, D4 RTM |

## 5. Ai xác nhận Done

Người phụ trách WP, có đối chiếu với bằng chứng. Với WP thuộc **vùng Đỏ** ở
`RISK_DELEGATION.md` §3, bắt buộc người thứ hai xác nhận và ghi tên vào Development Book.
