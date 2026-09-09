# ESTIMATION — Ước lượng công sức và tài nguyên

**Artifact #6 / 11** · Cập nhật: 2026-09-09 · Trạng thái: Baseline v1.0

---

## 1. Cách ước lượng

Dùng ba điểm (lạc quan / khả dĩ / bi quan), kỳ vọng PERT:

```
E = (O + 4M + P) / 6        σ = (P − O) / 6
```

Đơn vị: **phiên làm việc** (≈ 2 giờ tập trung), vì đây là dự án cuộc thi làm ngoài giờ,
không phải sprint toàn thời gian.

## 2. Bảng ước lượng

| WP | Tên | O | M | P | **E** | σ | Ghi chú độ tin cậy |
|---|---|---|---|---|---|---|---|
| WP-00 | Khung dự án | 1 | 2 | 4 | **2.2** | 0.5 | Cao — việc quen |
| WP-01 | UART trần | 2 | 3 | 8 | **3.7** | 1.0 | **Thấp** — lỗi timing khó đoán |
| WP-02 | Thăm dò diện tích | 1 | 2 | 5 | **2.3** | 0.7 | Trung bình |
| WP-03 | IP SHA-256 | 4 | 6 | 11 | **6.5** | 1.2 | Cao — thuật toán rõ ràng |
| WP-04 | IP AES-256 | 6 | 9 | 16 | **9.7** | 1.7 | **Thấp** — S-Box composite khó |
| WP-05 | Fabric CSI | 3 | 4 | 8 | **4.5** | 0.8 | Trung bình |
| WP-06 | Lớp giao thức | 5 | 8 | 14 | **8.5** | 1.5 | Trung bình |
| WP-07 | Tích hợp phần cứng | 2 | 5 | 14 | **6.0** | 2.0 | **Rất thấp** — phần cứng luôn bất ngờ |
| WP-08 | Đo hiệu năng | 1 | 2 | 4 | **2.2** | 0.5 | Cao |
| WP-09 | Test đối kháng | 2 | 3 | 5 | **3.2** | 0.5 | Cao |
| WP-10 | RTM & báo cáo | 3 | 5 | 9 | **5.3** | 1.0 | Trung bình |
| | **Tổng** | 30 | 49 | 98 | **54.1** | — | |

Độ lệch chuẩn tổng (căn tổng bình phương): σ_total ≈ **3.7 phiên**.

Khoảng tin cậy ~95% (E ± 2σ): **46.7 – 61.5 phiên** ≈ 93 – 123 giờ.

## 3. Đọc bảng này thế nào

- **WP-04 (AES) là gói lớn nhất** (9.7 phiên, 18% tổng). S-Box composite field là chỗ dễ
  sai nhất: đúng về mặt toán nhưng sai một phép biến đổi cơ sở thì vector vẫn fail mà
  không có manh mối. Biện pháp: đối chiếu **cả 256 giá trị** ngay từ module con, trước khi
  ghép vào vòng.
- **WP-07 có σ lớn nhất** (2.0). Đây là chỗ ước lượng đáng ngờ nhất. Lịch sử: ở lần làm
  trước, riêng việc board không enumerate đã tốn nhiều thời gian hơn cả việc viết AES.
- Ba WP có độ tin cậy thấp (WP-01, WP-04, WP-07) chiếm **19.4 / 54.1 = 36%** tổng công
  sức nhưng đóng góp phần lớn phương sai.

## 4. Ngân sách tài nguyên FPGA

Đây là "estimation" quan trọng hơn cả thời gian, vì nó là ràng buộc cứng.

| Hạng mục | Ngân sách | Trần thiết bị | Ghi chú |
|---|---|---|---|
| LUT4 | 7690 | 8640 | Dự phòng chỉ **11%** — rất sát |
| DFF | ~4200 | 6480 | Dự phòng 35% — thoải mái |
| BSRAM | 5 | 26 | Thoải mái |
| IOB | 7 | 276 | Thoải mái |

### Phân rã LUT4 (từ MODULE_MAP §2)

```
AES-256   ████████████████████████        2200   (29%)
SHA-256   ███████████████████             1800   (23%)
protocol  ███████████                     1080   (14%)
fabric    ██▌                              240   ( 3%)
io        ███                              290   ( 4%)
top       ▊                                 80   ( 1%)
─────────────────────────────────────────────────────
dùng                                      5690
                    ...cộng ~2000 dự phòng tổng hợp = 7690 / 8640
```

### Kế hoạch dự phòng nếu vượt trần

Theo thứ tự áp dụng, mỗi bước ghi lại số đo thật vào Development Book:

| # | Biện pháp | Tiết kiệm ước tính | Chi phí |
|---|---|---|---|
| 1 | Giảm LEN tối đa từ 512 → 256 byte | ~40 LUT4 | Ít |
| 2 | Chia sẻ 1 S-Box cho key schedule thay vì 4 | ~210 LUT4 | +4 chu kỳ/khóa vòng |
| 3 | Giảm từ 16 S-Box xuống 4, xử lý 4 byte/chu kỳ | ~840 LUT4 | AES 14 → 56 chu kỳ/khối |
| 4 | Bỏ đường SHA thứ hai (bước 11 §3 Architecture) | ~0 LUT4, đơn giản FSM | Host không tự kiểm được khung về |
| 5 | Tách thành hai bitstream riêng (AES / SHA) | — | **Mất G3**, chỉ là phương án cuối |

Biện pháp 3 là đòn bẩy lớn nhất và **vẫn an toàn về throughput**: 56 chu kỳ/khối ở 27 MHz
= 77 kB/s, vẫn nhanh hơn UART 115200 (11.5 kB/s) **6.7 lần**.

> Có sẵn kế hoạch dự phòng định lượng **trước khi** viết code là điều đã thiếu ở lần làm
> trước — khi đó HMAC được thêm vào rồi mới phát hiện không vừa, và ba lần "tối ưu" đều
> làm tệ hơn (7359 → 7724 → 9248 LUT4). Xem `ADR-0004`.

## 5. Điều kiện phải ước lượng lại

Bảng này hết hiệu lực nếu bất kỳ điều nào sau đây xảy ra:

1. WP-02 đo thấy AES hoặc SHA vượt ngân sách > 15%.
2. WP-01 phát hiện UART cần điều khiển luồng (kéo theo thay đổi giao thức).
3. F_max sau P&R < 30 MHz (phải chèn tầng thanh ghi, sửa nhiều FSM).
4. Thay đổi bất kỳ điều gì trong `IP_INTERFACE_CONTRACT.md`.
