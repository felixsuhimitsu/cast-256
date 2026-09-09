# ADR-0001: S-Box bằng số học composite field thay vì bảng tra

**Trạng thái:** Accepted · **Ngày:** 2026-09-09
**Liên quan:** REQ-F-04, REQ-R-03, MOD-AES-SBOX

## Bối cảnh

AES cần 16 phép SubBytes song song mỗi vòng (cộng 4 nữa cho key schedule). Tang Nano 9K
chỉ có 8640 LUT4 và **26 khối BSRAM** — nhưng BSRAM cần cho bộ đệm khung.

## Các phương án đã cân nhắc

| Phương án | LUT4 / S-Box | Tổng 20 S-Box | Vấn đề |
|---|---|---|---|
| Bảng tra 256×8 trong LUT | ~128 | ~2560 | Vượt ngân sách AES (2200) một mình |
| Bảng tra trong BSRAM | 0 | 0 LUT4, **20 BSRAM** | Chỉ có 26 BSRAM; mỗi BSRAM có 2 cổng nên cần ≥10 khối, cạnh tranh trực tiếp với buffer |
| Composite field GF(((2²)²)²) | ~70 | ~1400 | Đường tổ hợp sâu hơn; toán học phức tạp, dễ sai |

## Quyết định

Dùng **composite field** theo phương pháp Canright: ánh xạ GF(2⁸) sang GF(((2²)²)²), nghịch
đảo trong trường con, ánh xạ ngược, rồi biến đổi affine.

## Hệ quả

**Được:** ~1160 LUT4 so với bảng tra trong LUT; giữ nguyên toàn bộ BSRAM cho buffer;
thời gian chạy hằng định (không phụ thuộc dữ liệu) — có lợi phụ về kênh kề thời gian.

**Mất:** đường tổ hợp sâu nhất trong thiết kế (~14 ns, xem ARCHITECTURE §6). Nếu timing
trượt, đây là chỗ chèn thanh ghi đầu tiên.

**Rủi ro phải theo dõi (RSK-03):** một phép biến đổi cơ sở sai làm S-Box vẫn là song ánh
nhưng sai giá trị — vector AES sẽ fail mà không có manh mối chỉ về S-Box. **Biện pháp bắt
buộc:** đối chiếu cả 256 giá trị ở mức module con, trước khi ghép vào vòng. Đây là điều
kiện Done của WP-04.
