# SCOPE — Làm rõ phạm vi

**Artifact #1 / 11** · Chủ sở hữu: Đội Hủ Tiếu · Cập nhật: 2026-09-09 · Trạng thái: Baseline v1.0

---

## 1. Vấn đề

Các hệ nhúng nhỏ (cảm biến công nghiệp, thiết bị đo từ xa, module IoT) thường truyền dữ
liệu qua liên kết nối tiếp thô — UART, RS-485. Liên kết này **không có bảo mật ở tầng
vật lý**: bất kỳ ai chạm được vào đường dây đều đọc được toàn bộ nội dung và sửa được
từng byte mà bên nhận không biết.

Giải pháp phần mềm (chạy mã hóa trên MCU) thì tốn chu kỳ CPU và làm khóa nằm trong bộ nhớ
chương trình — dễ trích xuất. Giải pháp phần cứng thương mại (IP core có bản quyền) thì
đắt và là hộp đen, không kiểm chứng được.

## 2. Mục tiêu

Thiết kế **hai IP core mật mã độc lập, tự viết, có hợp đồng giao diện chuẩn hóa**, và
chứng minh chúng **tích hợp được** vào một giao thức truyền/nhận dữ liệu thực chạy trên
FPGA giá rẻ.

| ID | Mục tiêu | Tiêu chí đạt (đo được) | Kết quả 2026-09-10 |
|---|---|---|---|
| G1 | IP AES-256 | Vượt 100% vector NIST SP 800-38A cho AES-256-CTR; interface theo `IP_INTERFACE_CONTRACT.md` | ✅ 17/17, 2528 LUT4 |
| G2 | IP SHA-256 | Vượt 100% vector FIPS 180-4 (bao gồm ca biên độ dài 55/56/64 byte); cùng interface | ✅ 17/17, 1661 LUT4 |
| G3 | Tích hợp | Khung dữ liệu đi qua UART, được mã hóa + băm, trả về đúng nguyên bản, 0% mất gói trên 100 khung liên tiếp | ✅ 0/100 mất, 19/19 độ dài |
| G4 | Vừa thiết bị | Tổng hợp và P&R thành công trên GW1NR-LV9QN88PC6/I5 (8640 LUT4), timing PASS ở 27 MHz | ✅ 6664 LUT4 (77%), 46,85 MHz |
| G5 | Tài liệu sống | RTM phủ 100% requirement → module → test; không có requirement mồ côi | 🚧 36/39 (92%) |

## 3. Trong phạm vi (In scope)

- IP AES-256 chế độ CTR, khóa 256-bit, 14 vòng, kiến trúc lặp (iterative).
- IP SHA-256 đầy đủ, kèm khối đệm (padding) theo FIPS 180-4.
- Hợp đồng giao diện dòng chảy (streaming) dùng chung cho cả hai IP.
- Lớp giao thức: đóng/mở khung, kiểm tra toàn vẹn, quản lý phiên.
- Lớp vật lý: UART 8-N-1, 115200 baud.
- Bộ testbench mô phỏng cho từng IP và cho toàn hệ.
- Script kiểm chứng trên phần cứng thật (Python ↔ FPGA).
- Toàn bộ artifact chain 11 bước trong `docs/`.

## 4. Ngoài phạm vi (Out of scope) — và vì sao

| Không làm | Lý do |
|---|---|
| Trao đổi khóa (ECDH/RSA) | Cần số học trường lớn, vượt xa 8640 LUT4. Khóa nạp cứng lúc tổng hợp, ghi rõ là giới hạn. |
| HMAC-SHA-256 | Đã đo trên thiết kế trước: 85–107% LUT4, **không vừa thiết bị**. Xem `ADR-0004`. |
| Chống tấn công kênh kề (DPA, timing) | Cần masking + logic ngẫu nhiên, nhân đôi diện tích. Ghi vào phần hạn chế. |
| Ethernet / USB / SPI | UART đủ để chứng minh tích hợp; thêm PHY khác chỉ tăng chi phí, không tăng giá trị chứng minh. |
| AES-128 / AES-192 | Đề tài đã chốt AES-256. Key schedule khác nhau, không tái dùng miễn phí. |
| Ống dẫn (pipeline) AES nhiều tầng | Đánh đổi diện tích lấy throughput mà UART 115200 baud không tận dụng được. Xem `ADR-0002`. |

## 5. Bên liên quan

| Vai trò | Ai | Quan tâm gì |
|---|---|---|
| Người dùng cuối | Kỹ sư nhúng tích hợp IP | Interface rõ ràng, tài liệu đủ để dùng lại IP mà không đọc RTL |
| Ban giám khảo | Hội đồng VMBMATTT 2026 | Tính đúng đắn mật mã, mức độ tự làm, bằng chứng chạy thật |
| Đội phát triển | Hủ Tiếu | Làm được trong thời gian có, giải thích được từng dòng |

## 6. Ràng buộc đã biết

| ID | Ràng buộc | Nguồn |
|---|---|---|
| REQ-C-01 | Thiết bị: Sipeed Tang Nano 9K, GW1NR-LV9QN88PC6/I5 — 8640 LUT4, 6480 DFF, 26 BSRAM | Phần cứng có sẵn |
| REQ-C-02 | Toolchain mã nguồn mở: Yosys + nextpnr-himbaechel + Project Apicula | Không có license Gowin EDA |
| REQ-C-03 | Một miền xung nhịp duy nhất 27.0 MHz | Bộ dao động trên board |
| REQ-C-04 | Verilog IEEE 1364-2001 (không SystemVerilog) | Giới hạn `synth_gowin` |
| REQ-C-05 | Không dùng IP core của bên thứ ba cho phần mật mã | Yêu cầu cuộc thi: phải tự thiết kế |

## 7. Giả định (phải kiểm chứng, không được tin sẵn)

| Giả định | Cách kiểm chứng | Nếu sai thì sao |
|---|---|---|
| AES-256 lặp + SHA-256 cùng vừa trong 8640 LUT4 | Tổng hợp thử sớm ở WP-02 trước khi viết lớp giao thức | Chuyển SHA sang chia sẻ đường dữ liệu hoặc bỏ G2 khỏi cùng bitstream |
| UART 115200 chịu được luồng byte liên tục không nghỉ | Test luồng 256 byte back-to-back ngay ở WP-01 | Thêm điều khiển luồng hoặc hạ baud |
| 27 MHz đủ cho đường tổ hợp dài nhất của AES | Đọc báo cáo timing nextpnr sau mỗi P&R | Chèn thanh ghi cắt đường, tăng số chu kỳ mỗi vòng |

> Giả định thứ hai đã từng làm hỏng thiết kế trước (mất bit sync sau ~96 byte liên tiếp).
> Vì vậy nó được đưa lên WP-01, kiểm chứng trước mọi thứ khác. Xem `ADR-0005`.

## 8. Định nghĩa "xong" cho toàn dự án

Dự án xong khi **đồng thời**:

1. Cả 5 mục tiêu G1–G5 đạt tiêu chí đo được ở §2.
2. Có log thật từ phần cứng (không phải mô phỏng) chứng minh G3.
3. RTM không có ô trống.
4. Mọi hạn chế đã biết được ghi trung thực trong báo cáo, không giấu.
