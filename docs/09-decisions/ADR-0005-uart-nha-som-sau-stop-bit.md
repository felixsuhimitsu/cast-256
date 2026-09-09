# ADR-0005: UART RX nhả về IDLE ngay sau khi lấy mẫu bit stop

**Trạng thái:** Accepted · **Ngày:** 2026-09-09
**Liên quan:** REQ-I-05, RSK-02, MOD-IO-URX

## Bối cảnh

27.000.000 Hz / 115200 baud = **234.375** chu kỳ mỗi bit. Bộ chia nguyên chỉ dùng được
234 — sai số **−0.16%** mỗi bit.

Một khung UART 8-N-1 dài 10 bit = 2343.75 chu kỳ thật. Nếu bộ thu tiêu tốn trọn 10 × 234
= 2340 chu kỳ rồi mới về IDLE, nó chỉ còn **3.75 chu kỳ** dự phòng để bắt sườn start bit
kế tiếp.

Với luồng byte liên tục không nghỉ, sai số này **tích lũy**. Sau khoảng 96 byte, bộ thu
bỏ lỡ một sườn start và mất đồng bộ.

## Bằng chứng đo được (thiết kế trước)

| Bài test | Byte gửi | Byte mất |
|---|---|---|
| Liên tục, không nghỉ | 118 | 22 |
| Liên tục, không nghỉ | 256 | 159 |
| Cùng dữ liệu, nghỉ 1 ms giữa byte | 256 | **0** |

Hệ quả dây chuyền: bộ mở khung không bao giờ nhận đủ 32 byte digest → treo ở trạng thái
chờ → watchdog kích hoạt → **mọi khung hợp lệ đều bị loại âm thầm**.

Mô phỏng **không** bắt được lỗi này vì testbench chèn khoảng nghỉ giữa các byte.

## Các phương án đã cân nhắc

| Phương án | Chi phí | Hiệu quả |
|---|---|---|
| Nhả về IDLE ngay sau mẫu bit stop | ~0 LUT4 | Trả lại ~117 chu kỳ dự phòng mỗi byte |
| Bộ chia baud phân số (tích lũy 375/1000) | ~30 LUT4 | Loại bỏ sai số gốc |
| Hạ baud xuống 57600 | 0 | Giảm một nửa thông lượng |
| Thêm điều khiển luồng RTS/CTS | +2 chân, sửa giao thức host | Phức tạp, không cần thiết |

## Quyết định

**Nhả về IDLE ngay sau khi lấy mẫu bit stop.** Không chờ hết chu kỳ bit.

## Hệ quả

**Được:** dự phòng bắt start bit tăng từ 3.75 lên ~117 chu kỳ. Không tốn tài nguyên.

**Mất:** bộ thu trở nên "dễ dãi" hơn với khung bị méo — nếu bit stop bị sai, nó về IDLE
sớm và có thể hiểu nhầm bit dữ liệu kế tiếp là start bit. Chấp nhận được vì đường truyền
là dây ngắn trên bàn, và có digest chặn ở tầng trên.

**Giữ lại phương án chia baud phân số** làm bước tiếp theo nếu WP-01 vẫn thấy mất byte.

## Điều kiện kiểm chứng bắt buộc

WP-01 phải test **512 byte back-to-back, 0 byte mất**, trên phần cứng thật. Đây là gate
cứng: trượt thì dừng toàn dự án.
