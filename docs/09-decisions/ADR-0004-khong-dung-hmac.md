# ADR-0004: Không đưa HMAC-SHA-256 vào bitstream nộp

**Trạng thái:** Accepted · **Ngày:** 2026-09-09
**Liên quan:** REQ-F-22, REQ-C-01, SRS §10

## Bối cảnh

Trường DIGEST hiện tại là `SHA-256(LEN‖IV‖PT)` — **không có khóa**. Về mặt mật mã đây là
checksum toàn vẹn, **không phải MAC**: kẻ tấn công chủ động biết thuật toán có thể sửa
payload rồi tính lại digest, bên nhận không phát hiện được.

Cách đúng là HMAC-SHA-256 (RFC 2104) với khóa riêng, hoặc encrypt-then-MAC.

## Các phương án đã cân nhắc

| Phương án | LUT4 đo được | Kết quả P&R |
|---|---|---|
| Digest không khóa (hiện tại) | 6697 / 8640 (77%) | **PASS**, F_max 58.4 MHz |
| + HMAC-SHA-256 | 7359 / 8640 (85%) | FAIL — không đặt được cell |
| + HMAC, "tối ưu" bằng thanh ghi dịch | 7724 / 8640 (89%) | FAIL |
| + HMAC, bỏ cờ `-nowidelut` | 9248 / 8640 (107%) | FAIL |

## Quyết định

**Không** đưa HMAC vào bitstream nộp. Giữ digest không khóa, và **công bố rõ hạn chế này**
trong SRS §10 và trong báo cáo.

## Hệ quả

**Mất:** hệ thống không chống được kẻ tấn công chủ động. Nó chỉ phát hiện nhiễu đường
truyền và sửa đổi ngẫu nhiên. Đây là hạn chế thật, phải nói thẳng, không được mô tả
digest này là "MAC" hay "xác thực" trong bất kỳ tài liệu nào.

**Được:** một bitstream chạy được thật, đo được thật, thay vì một thiết kế đúng về lý
thuyết nhưng không nạp được lên board.

## Bài học ghi lại

Hai lần "tối ưu" ở bảng trên đều dựa trên suy đoán và đều làm **tăng** diện tích:
- Thanh ghi dịch: mỗi bit cần thêm mux 3 chiều (nạp/dịch/giữ) — đắt hơn thanh ghi thường.
- Bỏ `-nowidelut`: trên Gowin, MUX2_LUT5..8 được **dựng từ chính LUT4**, nên "dùng LUT
  rộng" không hề giảm số LUT4, mà còn thêm chi phí định tuyến.

Vì vậy DoD mục D10 bắt buộc **đo trước, kết luận sau**.

## Cần làm gì để gỡ hạn chế này

Cần một thiết bị lớn hơn (GW1NR-9C đã hết chỗ), hoặc chia sẻ đường dữ liệu SHA giữa hai
lần gọi HMAC bằng máy trạng thái thay vì hai instance. Phương án sau chưa được thử và là
hướng phát triển tiếp theo được nêu trong báo cáo.
