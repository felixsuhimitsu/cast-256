# RISK & DELEGATION — Rủi ro và ranh giới tự chủ

**Artifact #7 / 11** · Cập nhật: 2026-09-09 · Trạng thái: Baseline v1.0

---

## 1. Sổ rủi ro

Điểm = Khả năng (1-5) × Ảnh hưởng (1-5). Ưu tiên xử lý theo điểm giảm dần.

| ID | Rủi ro | KN | AH | Điểm | Biện pháp giảm thiểu | Kích hoạt ở |
|---|---|---|---|---|---|---|
| RSK-01 | AES + SHA không vừa 8640 LUT4 | 4 | 5 | **20** | Đo diện tích ở WP-02 trước khi viết logic; 5 biện pháp dự phòng định lượng sẵn (ESTIMATION §4) | WP-02 |
| RSK-02 | UART mất byte khi luồng liên tục | 3 | 5 | **15** | WP-01 test 512 byte back-to-back; RX nhả về IDLE ngay sau bit stop (REQ-I-05) | WP-01 |
| RSK-03 | S-Box composite sai âm thầm | 3 | 4 | **12** | Đối chiếu **cả 256 giá trị** ở mức module con, trước khi ghép vòng | WP-04 |
| RSK-04 | Test cho PASS giả trong khi FPGA đã chết | 3 | 4 | **12** | REQ-V-04: mọi test "từ chối" phải kèm bằng chứng liveness | WP-09 |
| RSK-05 | Timing không đạt 27 MHz | 2 | 4 | **8** | Ngân sách timing tính trước (ARCHITECTURE §6); biện pháp chèn thanh ghi đã định sẵn | WP-07 |
| RSK-06 | Board không enumerate / cáp hỏng | 3 | 2 | **6** | Kiểm cáp bằng thiết bị khác trước khi kết luận; ghi rõ ttyUSB1 là kênh UART, ttyUSB0 là JTAG | WP-01 |
| RSK-07 | Tài liệu lệch khỏi code | 4 | 3 | **12** | Quy tắc cập nhật ngược trong cùng commit (docs/README §3); RTM kiểm ở WP-10 | mọi WP |
| RSK-08 | Vector test tự sinh che giấu lỗi | 2 | 5 | **10** | REQ-V-02: chỉ dùng vector chính thức NIST/FIPS làm nguồn sự thật | WP-03, WP-04 |
| RSK-09 | Hết thời gian trước hạn nộp | 3 | 5 | **15** | WBS chia lát dọc: sau WP-07 đã có sản phẩm demo được, WP-08/09 là gia tăng | WP-07 |
| RSK-10 | Vi phạm ràng buộc phụ thuộc tầng | 3 | 3 | **9** | Script kiểm: grep instantiate chéo tầng, chạy trong `make lint` | WP-05 |

## 2. Ba rủi ro đứng đầu — kế hoạch cụ thể

### RSK-01 (20 điểm) — Diện tích

*Vì sao cao nhất:* ngân sách chỉ dự phòng 11%, và đây là lỗi **phát hiện muộn** — nếu chỉ
biết lúc P&R cuối dự án thì không còn thời gian sửa.

*Cảnh báo sớm:* WP-02 đo số thật của khung IP rỗng. Nếu khung rỗng đã chiếm > 30% ngân
sách của IP đó, coi như tín hiệu đỏ.

*Nếu xảy ra:* áp dụng ESTIMATION §4 theo thứ tự 1→5. Mỗi bước phải **đo lại và ghi số
thật**, không được suy đoán. Bài học: ở lần trước, hai lần "tối ưu" dựa trên suy đoán
đều làm diện tích **tăng** (7359 → 7724 → 9248).

### RSK-02 (15 điểm) — UART

*Vì sao cao:* đã từng xảy ra thật, và **mô phỏng không bắt được** — testbench chèn khoảng
nghỉ giữa các byte nên bug chỉ lộ trên phần cứng sau ~96 byte liên tiếp.

*Cảnh báo sớm:* WP-01, test bắt buộc 512 byte không nghỉ.

*Nếu xảy ra:* (a) nhả RX về IDLE ngay sau mẫu bit stop; (b) nếu vẫn mất, dùng bộ chia
baud phân số thay vì divisor nguyên 234 (giá trị đúng là 234.375).

### RSK-09 (15 điểm) — Thời gian

*Biện pháp cấu trúc:* WBS chia lát dọc nên tại mọi thời điểm sau WP-07 đều có sản phẩm
demo được. Nếu hết giờ ở WP-08, vẫn nộp được với phần hiệu năng đo thủ công.

*Thứ tự hy sinh nếu thiếu giờ:* WP-09 (test đối kháng mở rộng) → WP-08 (bench 100 khung,
giảm còn 20) → **không bao giờ** hy sinh WP-10 (RTM/báo cáo) hay gate của WP-03/04.

## 3. Bảng ủy quyền — AI được làm đến đâu

Đây là ranh giới bắt buộc. Nguyên tắc nền: **càng cho AI làm nhiều bước liên tiếp, gate
càng phải chặt**, nếu không tốc độ chỉ khuếch đại sai lệch.

### Vùng XANH — AI tự chủ, người review sau

| Việc | Điều kiện |
|---|---|
| Viết/sửa module RTL đã có testbench chặn | Testbench phải PASS trước khi commit |
| Viết testbench từ vector chính thức | Vector phải trích từ tài liệu NIST/FIPS, ghi rõ nguồn |
| Sửa script build, Makefile, lint | Không đổi cờ tổng hợp ảnh hưởng kết quả |
| Soạn thảo/định dạng tài liệu | Không tự đổi nội dung requirement |
| Chạy mô phỏng, tổng hợp, đọc log | — |
| Refactor không đổi hành vi | Testbench PASS trước và sau, giống nhau |

### Vùng VÀNG — AI đề xuất, người duyệt trước khi commit

| Việc | Vì sao |
|---|---|
| Thêm/sửa requirement trong SRS | Đổi định nghĩa "đúng" |
| Thay đổi ngân sách LUT4 | Đổi tiêu chí gate |
| Thêm ADR | Là quyết định, không phải thực thi |
| Thay đổi WBS, ước lượng | Đổi kế hoạch |
| Đổi cờ tổng hợp (`-nowidelut`, v.v.) | Ảnh hưởng toàn cục, khó dò ngược |
| Xóa hoặc nới lỏng một test case | Có thể che giấu lỗi |

### Vùng ĐỎ — AI PHẢI DỪNG, người quyết định

| Việc | Vì sao |
|---|---|
| Đổi định dạng khung truyền | Phá vỡ tương thích với host |
| Đổi thuật toán mật mã hoặc tham số của nó | Đây là lõi đề tài |
| Đổi `IP_INTERFACE_CONTRACT.md` | Là ranh giới không được tự ý phá |
| Đổi gán chân / mức điện áp trong `.cst` | Sai mức điện áp có thể **hỏng phần cứng** |
| Kết luận "đã chạy được trên board" | Chỉ được kết luận khi có log thật, người xác nhận |
| Chạy lệnh nạp bitstream ở chế độ nền | Đã từng làm treo thiết bị FTDI, phải rút cắm lại |
| Đưa số liệu vào báo cáo nộp | Mọi con số nộp đi phải có người đối chiếu với log gốc |

## 4. Bằng chứng người can thiệp (human correction evidence)

Quy định của dự án: **AI-generated ≠ done.**

Một artifact chỉ được đánh dấu ✅ trong `docs/README.md` §2 khi người phụ trách:

1. Giải thích được artifact đó bằng lời của mình,
2. Chỉ ra được **ít nhất một chỗ AI sai hoặc thiếu**,
3. Sửa lại chỗ đó,
4. Ghi lại vào `10-devbook/DEVELOPMENT_BOOK.md` §Human correction log.

Nếu một artifact không có mục nào trong correction log, nó **chưa được review**, dù trông
hoàn chỉnh đến đâu. Đây là biện pháp chống "rubber-stamp một chồng tài liệu chuyên nghiệp
mà không ai thực sự hiểu".

## 5. Rủi ro tồn dư được chấp nhận

Ghi rõ ở đây để không ai hiểu nhầm là đã xử lý:

| Rủi ro | Vì sao chấp nhận |
|---|---|
| Khóa nạp cứng có thể trích từ bitstream | Trao đổi khóa vượt xa 8640 LUT4 (SCOPE §4) |
| Digest không có khóa, không chống được tấn công chủ động | HMAC không vừa thiết bị (ADR-0004); công bố trung thực ở SRS §10 |
| Không chống tấn công kênh kề | Cần masking, nhân đôi diện tích (SCOPE §4) |
| Chỉ test trên một board vật lý duy nhất | Chỉ có một board |
