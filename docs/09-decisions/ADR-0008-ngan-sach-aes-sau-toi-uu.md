# ADR-0008: Chốt ngân sách IP AES ở 2600 LUT4 sau khi đã áp dụng biện pháp dự phòng

**Trạng thái:** Accepted · **Ngày:** 2026-09-09
**Liên quan:** REQ-R-03, REQ-P-05, WP-04 · **Tiếp nối:** ADR-0002, ADR-0007

## Bối cảnh

IP AES-256-CTR viết xong ở WP-04 vượt qua **17/17** vector FIPS 197 và NIST SP 800-38A,
nhưng đo được **2961 LUT4**, vượt ngưỡng REQ-R-03 (2400) tới 23%.

Đây là lần thứ hai một ngân sách IP bị vượt. Lần đầu (ADR-0007) chỉ nới số. Lần này
**phải thử tối ưu thật trước đã** — nếu cứ vượt là nới thì gate không còn nghĩa gì.

## Đã đo trước khi sửa

| Thành phần | LUT4 |
|---|---|
| 16 × `aes256_sbox` | 1296 |
| `aes256_round` | 382 |
| `aes256_keysched` | 619 |
| bộ nhớ khóa vòng + FSM `aes256_cipher` | ~326 |
| `aes256_ctr_ip` (bộ đếm, CSI) | 338 |
| **Tổng** | **2961** |

S-Box chiếm 44%. Đó là chỗ đáng cắt, không phải chỗ khác.

## Các phương án đã cân nhắc

| # | Phương án | Kết quả đo |
|---|---|---|
| A | Đưa bộ nhớ khóa vòng vào BSRAM | Không khả thi: yosys không ánh xạ được mảng 15×128 sang BSRAM Gowin (bề rộng cổng tối đa 32 bit), rơi về logic phân tán |
| B | **Giảm 16 → 8 S-Box, 2 chu kỳ/vòng** (biện pháp dự phòng #3 của ESTIMATION §4) | **2961 → 2526, giảm 435** |
| C | Bỏ tầng thanh ghi cổng ra của key schedule | DFF 1490 → 1357, **LUT4 2526 → 2528 — KHÔNG giảm** |
| D | Giảm tiếp xuống 4 S-Box | Ước tính giảm thêm ~330 nhưng thành 4 chu kỳ/vòng và phải viết lại đường dữ liệu lần nữa |

### Ghi nhận một dự đoán sai của tôi

Phương án C được thực hiện với dự đoán "tiết kiệm khoảng 130 LUT4". Số đo cho thấy **LUT4
không giảm** — các thanh ghi đó ánh xạ thẳng vào ô DFF, không tiêu LUT nào để mà bỏ đi.
Thay đổi vẫn được giữ (133 DFF rẻ hơn thì vẫn tốt hơn), nhưng lý do giữ là số đo chứ không
phải lý do ban đầu.

Đây là lần thứ tư trong hai dự án một phép "tối ưu" dựa trên suy đoán không cho kết quả như
dự đoán. Xem DEVELOPMENT_BOOK §4.

## Quyết định

1. **Giữ phương án B** (8 S-Box, 2 chu kỳ mỗi vòng). Đã kiểm chứng: 17/17 vector vẫn PASS.
2. **REQ-R-03: 2400 → 2600 LUT4.** Số đo cuối là 2528, dùng 97% ngân sách mới.
3. **REQ-P-05: ≤ 20 → ≤ 32 chu kỳ mỗi khối.** Số đo: 30 chu kỳ (1 chờ bộ nhớ + 1
   AddRoundKey + 14 vòng × 2).
4. **Không** áp dụng phương án D. Giữ nó làm dự phòng nếu tầng `protocol/` ở WP-06 làm
   tổng vượt trần.

## Vì sao chấp nhận nới ngân sách lần thứ hai

Ngân sách từng IP là **ước lượng đặt ra trước khi đo bất cứ thứ gì**; chúng đã hoàn thành
việc của mình là buộc phải dừng lại và tối ưu thật. Ràng buộc **thực sự cứng** là
REQ-R-01 (tổng ≤ 7776 LUT4) và nó chưa hề bị đụng tới:

| Khối | LUT4 | Nguồn |
|---|---|---|
| `aes256_ctr_ip` | 2528 | **đo** |
| `sha256_ip` | 1661 | **đo** |
| `io/` (UART, đã nạp board) | 331 | **đo** |
| `protocol/` + `fabric/` + top | ~1360 | ước lượng, đo ở WP-06/WP-07 |
| **Tổng dự phóng** | **≈ 5880 / 8640 (68%)** | dự phòng 24% so với trần REQ-R-01 |

## Hệ quả

**Được:** một IP AES đúng chuẩn, đo được, còn dư 24% chỗ cho tầng giao thức.

**Mất:** thông lượng AES giảm từ 28,8 MB/s xuống 14,4 MB/s. Không ảnh hưởng gì: UART
115200 chỉ cho 11,5 kB/s, tức là engine vẫn nhanh hơn đường truyền hơn 1000 lần.

**Phải theo dõi:** nếu WP-06 làm tổng vượt 7000 LUT4, áp dụng phương án D (4 S-Box).
