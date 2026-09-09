# SRS — Đặc tả yêu cầu phần mềm/phần cứng

**Artifact #2 / 11** · Cập nhật: 2026-09-09 · Trạng thái: Baseline v1.0
**Tham chiếu ngược:** [`../00-scope/SCOPE.md`](../00-scope/SCOPE.md)

---

## 1. Cách đọc tài liệu này

Mỗi yêu cầu có một ID bất biến. ID đó xuất hiện lại ở:
- `../02-module-map/MODULE_MAP.md` — module nào hiện thực nó,
- `../07-test/TEST_PLAN.md` — test case nào chứng minh nó,
- `../08-traceability/RTM.md` — bảng nối đầy đủ.

Từ khóa **PHẢI / NÊN / CÓ THỂ** dùng theo nghĩa RFC 2119.

---

## 2. Yêu cầu chức năng — IP AES-256

| ID | Yêu cầu | Tiêu chí chấp nhận |
|---|---|---|
| REQ-F-01 | IP PHẢI hiện thực AES-256 chuẩn FIPS 197: khối 128 bit, khóa 256 bit, 14 vòng. | Khớp bit-chính-xác vector phụ lục C.3 của FIPS 197. |
| REQ-F-02 | IP PHẢI hiện thực chế độ CTR theo NIST SP 800-38A §6.5. | Khớp toàn bộ 4 khối của vector F.5.5 (CTR-AES256.Encrypt). |
| REQ-F-03 | Bộ đếm CTR PHẢI là 128 bit, tăng theo big-endian, tràn quấn vòng (wrap) mà không lỗi. | TC kiểm ca counter = all-ones → 0. |
| REQ-F-04 | S-Box PHẢI hiện thực bằng số học trường composite GF(((2²)²)²), không dùng bảng tra 256×8. | Xem `ADR-0001`. Đối chiếu toàn bộ 256 giá trị với `sim/vectors/sbox_ref.hex`. |
| REQ-F-05 | Key schedule PHẢI sinh đủ 15 khóa vòng từ khóa 256 bit, dùng Rcon đúng chuẩn. | Khớp toàn bộ 60 word W[0..59] của vector FIPS 197 A.3. |
| REQ-F-06 | Mã hóa và giải mã CTR PHẢI dùng chung một khối cipher (CTR không cần hàm nghịch). | Không tồn tại module InvSubBytes/InvMixColumns trong `rtl/`. |
| REQ-F-07 | IP PHẢI báo lỗi (không âm thầm sinh rác) nếu nhận `start` khi đang bận. | Chân `busy` = 1 và `start` bị bỏ qua; TC kiểm chứng. |

## 3. Yêu cầu chức năng — IP SHA-256

| ID | Yêu cầu | Tiêu chí chấp nhận |
|---|---|---|
| REQ-F-10 | IP PHẢI hiện thực SHA-256 chuẩn FIPS 180-4: 64 vòng, 8 biến trạng thái, hằng K đúng. | Khớp `abc` → `ba7816bf…f20015ad`. |
| REQ-F-11 | IP PHẢI tự thực hiện đệm (padding): bit 1, các bit 0, độ dài 64 bit big-endian. | TC cho các độ dài 0, 1, 55, 56, 63, 64, 119, 120 byte. |
| REQ-F-12 | IP PHẢI xử lý được thông điệp nhiều khối (>64 byte) bằng cách nối trạng thái. | TC chuỗi 1.000.000 ký tự 'a' cho `cdc76e5c…2f92a0` (chạy trong mô phỏng, không trên board). |
| REQ-F-13 | Bộ lập lịch thông điệp (message schedule) PHẢI dùng cửa sổ trượt 16 word, không lưu cả 64 word. | Xem `ADR-0003`. Kiểm bằng đếm DFF sau tổng hợp. |
| REQ-F-14 | IP PHẢI xuất digest 256 bit kèm một xung `digest_valid` rộng đúng 1 chu kỳ. | TC kiểm độ rộng xung. |

## 4. Yêu cầu chức năng — Giao thức truyền/nhận

### 4.1 Định dạng khung

Khung đi vào (host → FPGA):

```
+----------+--------+------------+---------------+----------+
| PREAMBLE | LEN    | IV         | PAYLOAD       | DIGEST   |
| 2 byte   | 2 byte | 16 byte    | LEN byte      | 32 byte  |
| 0xA5 0x5A| big-end|  nonce CTR | dữ liệu thô   | SHA-256  |
+----------+--------+------------+---------------+----------+
```

`DIGEST = SHA-256( LEN || IV || PAYLOAD )` — tính trên **bản rõ** trước khi mã hóa.

Khung đi ra (FPGA → host) có cùng cấu trúc, `PAYLOAD` là bản mã CTR, `DIGEST` được tính
lại bởi FPGA trên bản rõ đã nhận.

| ID | Yêu cầu | Tiêu chí chấp nhận |
|---|---|---|
| REQ-F-20 | Bộ mở khung PHẢI đồng bộ lại bằng cách quét liên tục cặp byte PREAMBLE, không giả định biên khung. | Gửi 32 byte rác trước khung hợp lệ → vẫn nhận đúng. |
| REQ-F-21 | `LEN` PHẢI nằm trong [1, 512]; ngoài khoảng đó khung bị loại. | TC gửi LEN=0 và LEN=1024 → không có phản hồi, cờ lỗi bật. |
| REQ-F-22 | Hệ thống PHẢI so sánh DIGEST nhận được với DIGEST tự tính, và chỉ phát khung trả lời khi khớp. | TC lật 1 bit trong PAYLOAD → không có phản hồi. |
| REQ-F-23 | So sánh DIGEST PHẢI là so sánh thời gian hằng định (quét đủ 32 byte, không thoát sớm). | Kiểm bằng đọc RTL: không có `break`/thoát sớm trong FSM so sánh. |
| REQ-F-24 | Hệ thống PHẢI có watchdog: nếu một khung không hoàn tất trong 2^24 chu kỳ (~0.62 s), FSM quay về IDLE. | TC ngắt giữa chừng khung → khung kế tiếp vẫn nhận được. |
| REQ-F-25 | Bộ trọng tài PHẢI đảm bảo AES và SHA không bao giờ cùng chiếm đường dữ liệu tại một thời điểm. | Kiểm bằng assertion trong testbench: `aes_active & sha_active` luôn = 0. |

### 4.2 Chỉ thị trạng thái

| ID | Yêu cầu | Tiêu chí chấp nhận |
|---|---|---|
| REQ-F-30 | LED0 PHẢI sáng khi đang nhận khung. | Quan sát bằng mắt + xác nhận trong video demo. |
| REQ-F-31 | LED1 PHẢI sáng khi engine mật mã đang bận. | như trên |
| REQ-F-32 | LED2 PHẢI chớp 200 ms khi một khung bị loại (sai digest hoặc watchdog). | như trên |

## 5. Yêu cầu giao diện

| ID | Yêu cầu | Tiêu chí chấp nhận |
|---|---|---|
| REQ-I-01 | Cả hai IP PHẢI tuân theo cùng một hợp đồng giao diện, định nghĩa ở `../03-architecture/IP_INTERFACE_CONTRACT.md`. | Đổi chỗ hai IP trong sơ đồ khối không cần sửa wrapper. |
| REQ-I-02 | Bắt tay dữ liệu PHẢI theo quy tắc `valid`/`ready`: bên phát giữ nguyên dữ liệu và `valid` cho tới khi thấy `ready`. | Assertion trong testbench kiểm bất biến này. |
| REQ-I-03 | Lớp vật lý PHẢI là UART 8-N-1, 115200 baud, không điều khiển luồng phần cứng. | Đo bằng phân tích logic hoặc host Python. |
| REQ-I-04 | Bộ thu UART PHẢI lấy mẫu bằng biểu quyết 3 điểm quanh giữa bit. | Kiểm bằng đọc RTL + TC nhiễu. |
| REQ-I-05 | Bộ thu UART PHẢI trở về IDLE ngay sau khi lấy mẫu bit stop, không chờ hết chu kỳ bit. | TC luồng 512 byte liên tục, 0 byte mất. Xem `ADR-0005`. |

## 6. Yêu cầu hiệu năng

| ID | Yêu cầu | Ngưỡng | Cách đo |
|---|---|---|---|
| REQ-P-01 | Tần số tối đa sau P&R | ≥ 27.0 MHz | Báo cáo timing của nextpnr |
| REQ-P-02 | Tỉ lệ mất khung, 100 khung 128 byte liên tiếp | 0% | `scripts/hw_test.py --mode bench` |
| REQ-P-03 | Độ trễ khứ hồi một khung 128 byte | ≤ 40 ms | như trên, thống kê min/avg/max/stddev |
| REQ-P-04 | Thông lượng ứng dụng | ≥ 8000 byte/s | như trên |
| REQ-P-05 | Số chu kỳ mã hóa một khối AES | ≤ 20 chu kỳ | Đếm trong mô phỏng |
| REQ-P-06 | Số chu kỳ băm một khối SHA-256 | ≤ 70 chu kỳ | Đếm trong mô phỏng |

## 7. Yêu cầu tài nguyên

| ID | Yêu cầu | Ngưỡng | Cách đo |
|---|---|---|---|
| REQ-R-01 | Tổng LUT4 | ≤ 90% của 8640 (7776) | Báo cáo nextpnr |
| REQ-R-02 | Tổng DFF | ≤ 80% của 6480 (5184) | như trên |
| REQ-R-03 | IP AES-256 đứng riêng | ≤ 2200 LUT4 | Tổng hợp riêng module |
| REQ-R-04 | IP SHA-256 đứng riêng | ≤ 1800 LUT4 | như trên |

> Các ngưỡng REQ-R-03/04 là **ngân sách**, chốt trước khi viết code, để phát hiện sớm việc
> vượt diện tích thay vì phát hiện lúc P&R thất bại ở cuối dự án.

## 8. Yêu cầu kiểm chứng

| ID | Yêu cầu |
|---|---|
| REQ-V-01 | Mỗi IP PHẢI có testbench độc lập chạy được bằng `make sim-<tên>`, tự in PASS/FAIL và trả mã thoát khác 0 khi FAIL. |
| REQ-V-02 | Testbench PHẢI dùng vector chính thức từ NIST/FIPS, không dùng vector tự sinh làm nguồn sự thật. |
| REQ-V-03 | PHẢI có ít nhất một test chạy trên phần cứng thật; kết quả mô phỏng KHÔNG được coi là bằng chứng cho REQ-P-02..04. |
| REQ-V-04 | Test chế độ "tamper" và "timeout" PHẢI phân biệt được "FPGA từ chối đúng" với "FPGA chết"; test chỉ kiểm "0 byte trả về" là **không hợp lệ**. |

> REQ-V-04 sinh ra từ một lỗi thật ở thiết kế trước: test tamper/timeout vẫn PASS trong khi
> bitstream hỏng hoàn toàn. Xem `10-devbook/DEVELOPMENT_BOOK.md`.

## 9. Yêu cầu phi chức năng khác

| ID | Yêu cầu |
|---|---|
| REQ-N-01 | Toàn bộ RTL PHẢI tổng hợp được bằng toolchain mã nguồn mở, không cảnh báo `latch inferred`. |
| REQ-N-02 | Mỗi file RTL PHẢI có header ghi: mục đích, các REQ-ID nó hiện thực, tác giả, ngày. |
| REQ-N-03 | Khóa AES nạp cứng PHẢI được đặt ở một file riêng `rtl/config/keys.vh`, có ghi chú rõ đây là giới hạn thiết kế. |

## 10. Hạn chế đã biết, công bố trung thực

1. **Khóa nạp cứng.** Không có trao đổi khóa. Ai đọc được bitstream sẽ lấy được khóa. Đây
   là hệ quả trực tiếp của REQ-C-01 (diện tích) chứ không phải sơ suất.
2. **DIGEST không có khóa.** `SHA-256(LEN||IV||PT)` là *checksum toàn vẹn*, không phải MAC.
   Nó phát hiện được nhiễu đường truyền và sửa đổi ngẫu nhiên, nhưng **không** chống được
   kẻ tấn công chủ động biết thuật toán. HMAC-SHA-256 đã được hiện thực và vượt mô phỏng
   100%, nhưng không vừa thiết bị. Xem `ADR-0004`.
3. **Không chống kênh kề.** Thời gian chạy AES là hằng định (kiến trúc lặp, không phụ
   thuộc dữ liệu), nhưng không có biện pháp chống phân tích công suất.
