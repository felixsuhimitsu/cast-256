# ADR-0007: Điều chỉnh ngân sách diện tích từng IP sau khi đo thật

**Trạng thái:** Accepted · **Ngày:** 2026-09-09
**Liên quan:** REQ-R-01, REQ-R-02, REQ-R-03, REQ-R-04, WP-02
**Sửa đổi:** ngân sách trong `../02-module-map/MODULE_MAP.md` §2 và SRS §7

## Bối cảnh

WP-02 tồn tại để kiểm chính các con số ngân sách trong `MODULE_MAP.md` §2 — vốn là **ước
lượng chưa đo**, và đã được đánh dấu là chỗ đáng ngờ nhất trong
`DEVELOPMENT_BOOK.md` §5 mục 1.

Thay vì đo "khung rỗng" (yosys sẽ tối ưu mất, cho số vô nghĩa), đã viết và đo **hai khối
thật sự tốn diện tích nhất**: S-Box composite field và hàm nén SHA-256.

## Số đo thật

Tổng hợp riêng lẻ, `synth_gowin -no-rw-check -nowidelut`. Trên Gowin mọi LUT1/2/3/4 đều
chiếm một slot LUT4, nên cột "LUT4" dưới đây là tổng cả bốn loại.

| Module | LUT4 thật | ALU | DFF | Ngân sách cũ | Chênh |
|---|---|---|---|---|---|
| `aes256_sbox` | **81** | 0 | 0 | 70 | +16% |
| `sha256_sched` | **242** | 32 | 512 | 420 | −42% |
| `sha256_k` | **286** | 0 | 0 | 180 | +59% |
| `sha256_compress` | **892** | 352 | 512 | 780 | +14% |

### Một phát hiện trong lúc đo

`sha256_compress` ban đầu đo được **1132 LUT4**. Nguyên nhân: 8 thanh ghi trạng thái
`a..h` được gán ở cả ba nhánh `init` / `step` / `finalize`, làm mỗi bit trong 256 bit cần
một **mux 3 chiều** — đúng cái bẫy đã ghi ở `ADR-0004` với thanh ghi dịch.

Sửa: bỏ việc nạp lại `a..h` trong nhánh `finalize`; cho khối kế tiếp, FSM phát `init` với
`h_in = h_out`. `a..h` còn 2 nguồn → mux 2 chiều.

**1132 → 892 LUT4, giảm 240 (21%)**, không đổi chức năng. Ghi lại ở đây vì đây là lần đầu
một phép "tối ưu" trong dự án này thực sự giảm diện tích — ba lần trước ở ADR-0004 đều làm
tăng, và khác biệt nằm ở chỗ lần này **đo trước rồi mới sửa**.

## Dự phóng tổng

| Khối | LUT4 | Cơ sở |
|---|---|---|
| 16 × `aes256_sbox` | 1296 | **đo** |
| `aes256_round` (ShiftRows + MixColumns + AddRoundKey) | ~240 | ước lượng, xác nhận ở WP-04 |
| `aes256_keysched` (điều khiển, khóa vòng tính sẵn) | ~150 | ước lượng |
| `aes256_cipher` (FSM 14 vòng) | ~180 | ước lượng |
| `aes256_ctr_ip` (bộ đếm + CSI) | ~340 | ước lượng |
| **Cộng AES** | **~2206** | |
| `sha256_sched` + `sha256_k` + `sha256_compress` | 1420 | **đo** |
| `sha256_pad` + `sha256_ip` | ~420 | ước lượng |
| **Cộng SHA** | **~1840** | |
| `protocol/` + `fabric/` + `io/` + top | ~1690 | ước lượng |
| **TỔNG DỰ PHÓNG** | **~5740 / 8640 (66%)** | |

## Các phương án đã cân nhắc

| # | Phương án | Kết quả |
|---|---|---|
| A | Giữ nguyên ngân sách, ép AES/SHA vừa 2200/1800 | Phải hy sinh chức năng dù **tổng vẫn thừa chỗ** — tối ưu sai chỗ |
| B | Bỏ luôn ngân sách từng IP, chỉ giữ ngân sách tổng | Mất cảnh báo sớm; lỗi tràn diện tích lại chỉ lộ ra ở P&R cuối dự án |
| C | Nới ngân sách từng IP theo số đo, giữ nguyên ngân sách tổng | Giữ được cảnh báo sớm, phản ánh thực tế |
| D | Đưa `sha256_k` vào BSRAM để cứu 286 LUT4 | Cứu được LUT4 nhưng ăn vào BSRAM dành cho bộ đệm khung; chưa cần |

## Quyết định

Chọn **C**.

| Requirement | Cũ | **Mới** |
|---|---|---|
| REQ-R-03 (AES) | ≤ 2200 LUT4 | **≤ 2400 LUT4** |
| REQ-R-04 (SHA) | ≤ 1800 LUT4 | **≤ 2000 LUT4** |
| REQ-R-01 (tổng) | ≤ 7776 LUT4 | **không đổi** |
| REQ-R-02 (DFF) | ≤ 5184 | **không đổi** |

Kèm hai quyết định kiến trúc phát sinh từ số đo:

1. **AES dùng 16 S-Box, không phải 20.** Khóa vòng được tính sẵn một lần lúc nạp khóa,
   dùng lại chính 16 S-Box của đường dữ liệu theo thời gian, và lưu 15×128 = 1920 DFF.
   Tiết kiệm 4 × 81 = 324 LUT4, đổi lấy 1920 DFF — mà DFF đang thừa (dự phóng ~57%).
2. **`sha256_k` giữ ở dạng logic tổ hợp**, không đưa vào BSRAM. 286 LUT4 chấp nhận được;
   BSRAM để dành cho bộ đệm khung theo `ARCHITECTURE.md` §4.2.

## Hệ quả

**Được:** kế hoạch phản ánh số đo thật thay vì ước lượng; vẫn còn 34% dự phòng tổng.

**Mất:** ngân sách từng IP nới ra nên cảnh báo sớm kém nhạy hơn một chút.

**Phải theo dõi:** các con số còn là *ước lượng* trong bảng dự phóng — `aes256_round`,
`aes256_cipher`, `aes256_ctr_ip`, `sha256_pad`, `sha256_ip`, và toàn bộ tầng `protocol/`.
Chúng phải được đo và ghi vào `DEVELOPMENT_BOOK.md` §3.1 khi WP tương ứng hoàn thành.
Nếu tổng vượt 7000 LUT4 ở bất kỳ thời điểm nào, áp dụng `ESTIMATION.md` §4 biện pháp 3
(giảm còn 4 S-Box) — đã định lượng sẵn, vẫn nhanh hơn UART 6,7 lần.
