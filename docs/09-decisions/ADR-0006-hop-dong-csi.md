# ADR-0006: Chuẩn hóa hợp đồng giao diện CSI cho mọi IP mật mã

**Trạng thái:** Accepted · **Ngày:** 2026-09-09
**Liên quan:** REQ-I-01, REQ-I-02, REQ-F-25, MOD-FAB-ARB, MOD-FAB-MUX

## Bối cảnh

Đề tài là "thiết kế **và tích hợp** IP". Nếu AES và SHA mỗi cái có một kiểu cổng riêng,
lớp giao thức phải viết mã đặc thù cho từng cái, và đề tài mất đi phần "tích hợp" — chỉ
còn là hai khối logic được nối tay.

## Các phương án đã cân nhắc

| Phương án | Ưu | Nhược |
|---|---|---|
| Mỗi IP một interface riêng | Đơn giản nhất khi viết từng IP | Lớp giao thức phải biết chi tiết từng IP; thêm IP thứ ba phải sửa `protocol/` |
| AXI4-Stream đầy đủ | Chuẩn công nghiệp, ai cũng biết | Nhiều tín hiệu không dùng (`tkeep`, `tstrb`, `tid`, `tdest`); tốn LUT4 cho logic không bao giờ chạy |
| **CSI** — tập con tối giản kiểu AXI-Stream + điều khiển/kết quả | Đủ dùng, rẻ, vẫn quen thuộc | Không phải chuẩn có tên tuổi; phải tự viết tài liệu và assertion |

## Quyết định

Định nghĩa **CSI (Crypto Stream Interface) v1.0** — xem
`../03-architecture/IP_INTERFACE_CONTRACT.md`. Giữ quy tắc bắt tay `valid`/`ready` giống
AXI-Stream (để người quen AXI đọc được ngay), bỏ các tín hiệu thừa, thêm nhóm
`csi_start/busy/done/err/mode` và một cổng kết quả dạng thanh ghi.

## Hệ quả

**Được:**
- `stream_mux.v` đối xử với mọi IP như nhau; thêm IP thứ ba chỉ tăng tham số `NUM_IP`.
- Assertion viết một lần trong `sim/lib/csi_assert.vh`, dùng cho mọi IP.
- Hai IP dùng lại được ở dự án khác mà không kéo theo gì của dự án này.
- Loại trừ tương hỗ (REQ-F-25) cưỡng chế được ở một chỗ duy nhất (`ip_arbiter.v`).

**Mất:**
- Không tương thích trực tiếp với IP AXI của bên thứ ba — cần một cầu nối nếu sau này ghép.
- Thêm ~240 LUT4 cho tầng `fabric/` mà một thiết kế nối tay không cần.

**Chấp nhận đánh đổi này** vì 240 LUT4 (2.8% thiết bị) chính là thứ biến đề tài từ "hai
khối mật mã" thành "hai IP tích hợp được" — đúng phần được chấm điểm.

**Phải theo dõi:** mọi thay đổi hợp đồng CSI thuộc **vùng ĐỎ** trong bảng ủy quyền.
