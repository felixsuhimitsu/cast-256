# ADR-0003: SHA-256 message schedule dùng cửa sổ trượt 16 word

**Trạng thái:** Accepted · **Ngày:** 2026-09-09
**Liên quan:** REQ-F-13, REQ-R-02, REQ-R-04, MOD-SHA-SCHED

## Bối cảnh

SHA-256 cần W[0..63], mỗi word 32 bit. Cách viết trực tiếp theo chuẩn là lưu cả 64 word.

## Các phương án đã cân nhắc

| Phương án | DFF | Ghi chú |
|---|---|---|
| Lưu đủ 64 word | 2048 | Chiếm 32% toàn bộ DFF của thiết bị |
| Cửa sổ trượt 16 word | **512** | W[t] chỉ phụ thuộc W[t-2], W[t-7], W[t-15], W[t-16] |
| Lưu trong BSRAM | ~64 | Thêm độ trễ đọc, FSM phức tạp hơn, tốn BSRAM |

## Quyết định

**Cửa sổ trượt 16 word.** Mỗi chu kỳ đẩy một word mới vào, word cũ nhất rơi ra.

## Hệ quả

**Được:** 1536 DFF so với phương án trực tiếp — đủ để cả AES và SHA cùng nằm dưới ngân
sách DFF 5184 (REQ-R-02).

**Mất:** message schedule và vòng nén bị **buộc chặt về thời gian** — không thể tính
trước toàn bộ W rồi mới nén. FSM phải đồng bộ chính xác hai phần. Đây là chỗ dễ sai
off-by-one nhất trong WP-03.

**Không chọn BSRAM** vì tiết kiệm thêm chỉ ~450 DFF (đã dư DFF) nhưng đổi lấy độ phức
tạp FSM ở đúng chỗ đã khó nhất.
