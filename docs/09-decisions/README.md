# Architecture Decision Records

Mỗi quyết định kiến trúc hoặc đánh đổi quan trọng là một file `ADR-nnnn-<slug>.md`.

Quy tắc: ADR **không bao giờ bị sửa nội dung sau khi Accepted**. Nếu quyết định thay đổi,
viết ADR mới với trạng thái `Supersedes ADR-xxxx`, và đánh dấu ADR cũ là `Superseded by`.
Lịch sử quyết định phải đọc được, kể cả những quyết định đã sai.

| ID | Tiêu đề | Trạng thái | Ngày |
|---|---|---|---|
| [ADR-0001](ADR-0001-sbox-composite-field.md) | S-Box bằng composite field thay vì bảng tra | Accepted | 2026-09-09 |
| [ADR-0002](ADR-0002-kien-truc-lap-khong-pipeline.md) | AES kiến trúc lặp, không pipeline | Accepted | 2026-09-09 |
| [ADR-0003](ADR-0003-sha-cua-so-truot.md) | SHA message schedule dùng cửa sổ trượt 16 word | Accepted | 2026-09-09 |
| [ADR-0004](ADR-0004-khong-dung-hmac.md) | Không dùng HMAC-SHA-256 trong bitstream nộp | Accepted | 2026-09-09 |
| [ADR-0005](ADR-0005-uart-nha-som-sau-stop-bit.md) | UART RX nhả về IDLE ngay sau mẫu bit stop | Accepted | 2026-09-09 |
| [ADR-0006](ADR-0006-hop-dong-csi.md) | Chuẩn hóa hợp đồng giao diện CSI cho mọi IP | Accepted | 2026-09-09 |

## Mẫu ADR

```markdown
# ADR-nnnn: <tiêu đề>
**Trạng thái:** Proposed | Accepted | Superseded by ADR-xxxx
**Ngày:** yyyy-mm-dd · **Liên quan:** REQ-…, MOD-…

## Bối cảnh
Vấn đề là gì, ràng buộc nào đang ép.

## Các phương án đã cân nhắc
Ít nhất hai, kèm số liệu nếu có.

## Quyết định
Chọn gì.

## Hệ quả
Được gì, mất gì, ai bị ảnh hưởng, phải theo dõi chỉ số nào.
```
