# ADR-0002: AES dùng kiến trúc lặp, không pipeline

**Trạng thái:** Accepted · **Ngày:** 2026-09-09
**Liên quan:** REQ-P-05, REQ-R-03, MOD-AES-CIPHER

## Bối cảnh

AES-256 có 14 vòng. Có thể trải 14 vòng thành 14 tầng phần cứng (pipeline, 1 khối/chu kỳ)
hoặc dùng một khối vòng và lặp 14 lần.

## Các phương án đã cân nhắc

| Phương án | LUT4 | Thông lượng ở 27 MHz |
|---|---|---|
| Pipeline 14 tầng | ~14 × 1400 ≈ 19600 | 432 MB/s |
| Lặp, 1 vòng/chu kỳ | ~2200 | **216 kB/s** |
| Lặp, 4 byte/chu kỳ (4 S-Box) | ~1360 | 54 kB/s |

## Quyết định

Kiến trúc **lặp, một vòng đầy đủ mỗi chu kỳ** (16 S-Box).

## Hệ quả

Phương án pipeline vượt trần thiết bị **2,3 lần** — loại ngay.

Giữa hai phương án lặp: đường truyền UART 115200 baud cho tối đa **11.5 kB/s**. Phương án
đã chọn nhanh hơn đường truyền **19 lần**; phương án 4 byte/chu kỳ vẫn nhanh hơn **4,7
lần**. Cả hai đều đủ. Chọn phương án 16 S-Box vì còn dư ngân sách, và giữ phương án 4
S-Box làm **dự phòng bậc 3** trong ESTIMATION §4 nếu diện tích vỡ.

**Điều phải theo dõi:** nếu WP-02 đo thấy AES vượt 2200 LUT4, chuyển sang phương án 4
S-Box là bước đã được định lượng sẵn, không cần thiết kế lại.
