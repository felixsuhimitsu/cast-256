# RTM — Requirements Traceability Matrix

**Artifact #11 / 11** · Cập nhật: 2026-09-10 · Trạng thái: 36/39 REQ đã đóng có bằng chứng

---

## 1. Mục đích

Nối chuỗi **requirement → work package → module → test case → bằng chứng** để cả người và
AI kiểm được ảnh hưởng của một thay đổi mà không phải đọc lại toàn bộ RTL.

Bảng này là **gate cuối** của dự án (WP-10). Điều kiện đóng:

- Mọi REQ-ID có ≥ 1 module **và** ≥ 1 test case → không có **requirement mồ côi**.
- Mọi module có ≥ 1 REQ-ID → không có **module mồ côi**.
- Không còn ô `TBD` ở cột Bằng chứng.

## 2. Trạng thái

| Ký hiệu | Nghĩa |
|---|---|
| ⬜ | Chưa bắt đầu |
| 🚧 | Đang làm |
| ✅ | Đạt, có bằng chứng |
| ❌ | Không đạt |
| ⛔ | Đã chấp nhận không làm, có ADR |

## 3. Ma trận truy vết

### 3.1 IP AES-256

| REQ | Mô tả ngắn | WP | Module | Test | Bằng chứng | TT |
|---|---|---|---|---|---|---|
| REQ-F-01 | AES-256 14 vòng FIPS 197 | WP-04 | MOD-AES-ROUND, MOD-AES-CIPHER | TC-101 | `make sim-aes` — FIPS 197 C.3 khớp | ✅ |
| REQ-F-02 | Chế độ CTR SP 800-38A | WP-04 | MOD-AES-IP | TC-104 | 4/4 khối F.5.5 khớp | ✅ |
| REQ-F-03 | Counter 128-bit, wrap đúng | WP-04 | MOD-AES-IP | TC-105 | all-ones → 0, cả hai khối khớp | ✅ |
| REQ-F-04 | S-Box composite field | WP-04 | MOD-AES-SBOX | TC-100 | `sim/unit/tb_sbox.v` 256/256 PASS | ✅ |
| REQ-F-05 | Key schedule 15 khóa vòng | WP-04 | MOD-AES-KEYSCHED | **TC-102** | `make sim-keysched` — 60/60 word khớp FIPS 197 A.3, kiểm với **hai** khóa khác nhau | ✅ |
| REQ-F-06 | Dùng chung cipher cho cả hai chiều | WP-04 | MOD-AES-CIPHER | TC-106 | mã→giải 48 byte về đúng bản rõ | ✅ |
| REQ-F-07 | Bỏ qua `start` khi busy | WP-04 | MOD-AES-IP | TC-107 | start giữa chừng bị bỏ, kết quả không hỏng | ✅ |

### 3.2 IP SHA-256

| REQ | Mô tả ngắn | WP | Module | Test | Bằng chứng | TT |
|---|---|---|---|---|---|---|
| REQ-F-10 | SHA-256 64 vòng FIPS 180-4 | WP-03 | MOD-SHA-COMPRESS, MOD-SHA-K | TC-202 | `make sim-sha` — SHA("abc") khớp | ✅ |
| REQ-F-11 | Tự đệm theo chuẩn | WP-03 | MOD-SHA-PAD | TC-203 | 1/55/56/63/64/119/120 byte đều khớp | ✅ |
| REQ-F-12 | Thông điệp nhiều khối | WP-03 | MOD-SHA-PAD, MOD-SHA-IP | TC-203, **TC-204** | 119/120 byte (2–3 khối) và **1000 byte (16 khối)** đều khớp | ✅ |
| REQ-F-13 | Cửa sổ trượt 16 word | WP-03 | MOD-SHA-SCHED | TC-208 + đo DFF | 512 DFF (thay vì 2048) | ✅ |
| REQ-F-14 | Xung `digest_valid` 1 chu kỳ | WP-03 | MOD-SHA-IP | TC-206 | độ rộng đo được = 1 | ✅ |

### 3.3 Giao thức

| REQ | Mô tả ngắn | WP | Module | Test | Bằng chứng | TT |
|---|---|---|---|---|---|---|
| REQ-F-20 | Đồng bộ bằng quét preamble | WP-06, WP-07 | MOD-PROTO-RX, MOD-PROTO-TX | TC-500, TC-501, TC-508, TC-605 | mô phỏng + **board thật: 19/19 độ dài đúng, rác trước preamble vẫn nhận đúng** | ✅ |
| REQ-F-21 | LEN trong [1,512] | WP-06, WP-07 | MOD-PROTO-RX, MOD-PROTO-BUF | TC-504, TC-505, TC-601s | LEN=0 và 1024 bị loại (cả mô phỏng lẫn board); LEN=512 đúng sau khi sửa lỗi cắt bit | ✅ |
| REQ-F-22 | Chỉ phát khi digest khớp | WP-06, WP-09 | MOD-PROTO-DGST, MOD-PROTO-FSM | TC-502, TC-503, TC-603 | mô phỏng + **board thật (TC-603 đủ 2 pha)** | ✅ |
| REQ-F-23 | So sánh digest hằng thời | WP-06 | MOD-PROTO-DGST | **TC-507** | đo tự động: byte digest sai ở vị trí đầu và vị trí cuối đều cho **đúng 208 chu kỳ** | ✅ |
| REQ-F-24 | Watchdog 2²⁴ chu kỳ | WP-06, WP-09 | MOD-PROTO-RX | TC-506, TC-604 | mô phỏng + **board thật: sau 0,62 s watchdog, khung tiếp theo chạy đúng** | ✅ |
| REQ-F-25 | AES và SHA loại trừ tương hỗ | WP-05 | MOD-FAB-ARB, MOD-FAB-MUX | TC-400, TC-401 | assertion mọi chu kỳ: 0 lần hai IP cùng bận; grant luôn one-hot | ✅ |
| REQ-F-30 | LED0 đang nhận | WP-07 | MOD-IO-LED | TC-606 | TC-606 mô phỏng (15/15) **+** người phụ trách xác nhận trực quan trên board 2026-09-15 | ✅ |
| REQ-F-31 | LED1 engine bận | WP-07 | MOD-IO-LED | TC-606 | TC-606 mô phỏng (15/15) **+** người phụ trách xác nhận trực quan trên board 2026-09-15 | ✅ |
| REQ-F-32 | LED2 chớp khi loại khung | WP-07 | MOD-IO-LED | TC-606 | TC-606 mô phỏng (15/15) **+** người phụ trách xác nhận trực quan trên board 2026-09-15; độ dài chớp đo được 27001 chu kỳ đúng danh định | ✅ |

### 3.4 Giao diện

| REQ | Mô tả ngắn | WP | Module | Test | Bằng chứng | TT |
|---|---|---|---|---|---|---|
| REQ-I-01 | Hai IP cùng hợp đồng CSI | WP-04, WP-05 | MOD-AES-IP, MOD-SHA-IP, MOD-FAB-MUX | TC-108, TC-207, TC-402, TC-403 | `csi_checker` 0 vi phạm ở cả hai IP; TC-402 đổi chỗ hai IP không sửa mux | ✅ |
| REQ-I-02 | Bắt tay valid/ready đúng H1–H5 | WP-04 | tất cả IP | TC-108, TC-207 | H2/H5 kiểm mọi chu kỳ, 0 vi phạm | ✅ |
| REQ-I-03 | UART 8-N-1 115200 | WP-01 | MOD-IO-URX, MOD-IO-UTX, MOD-IO-BAUD | TC-300 | `make sim-uart` 10/10 PASS | ✅ |
| REQ-I-04 | Biểu quyết 3 điểm | WP-01 | MOD-IO-URX | TC-301, TC-302 | TC-301 8/8 sau khi sửa lỗi vote | ✅ |
| REQ-I-05 | Nhả IDLE sau bit stop | WP-01 | MOD-IO-URX | **TC-600** | board thật: 4096/4096, 0 mất — `evidence/hw/20260909-2230-*.log` | ✅ |

### 3.5 Hiệu năng — chỉ phủ được bằng phần cứng

| REQ | Ngưỡng | WP | Test | Bằng chứng | TT |
|---|---|---|---|---|---|
| REQ-P-01 | F_max ≥ 27 MHz | WP-07 | báo cáo nextpnr | **46,85 MHz** — `evidence/synth/20260910-0957-*.log` | ✅ |
| REQ-P-02 | 0% mất khung / 100 khung | WP-08 | TC-602 | **0/100 (0,00%)** — `evidence/hw/*-TC-602-bench.log` | ✅ |
| REQ-P-03 | Độ trễ ≤ 40 ms | WP-08 | TC-602 | **max 32,55 ms**, avg 32,42, σ 0,03 | ✅ |
| REQ-P-04 | Thông lượng ≥ 8000 B/s | WP-08 | TC-602 | **10 778 B/s** (86,2 kbps) | ✅ |
| REQ-P-05 | AES ≤ 32 chu kỳ/khối (ADR-0008) | WP-04 | **TC-103** (đếm tự động) | **32 chu kỳ** đo được | ✅ |
| REQ-P-06 | SHA ≤ 70 chu kỳ/khối | WP-03 | **TC-205** (đếm tự động) | **66 chu kỳ** nén đo được | ✅ |

### 3.6 Tài nguyên

| REQ | Ngưỡng | WP | Cách đo | Số đo thật | TT |
|---|---|---|---|---|---|
| REQ-R-01 | LUT4 ≤ 7776 | WP-07 | nextpnr | **6664 / 8640 (77%)** | ✅ |
| REQ-R-02 | DFF ≤ 5184 | WP-07 | nextpnr | **3568 / 6480 (55%)** | ✅ |
| REQ-R-03 | AES ≤ 2600 LUT4 (ADR-0008) | WP-04 | `make synth-aes` | **2528 LUT4 (97% ngân sách)** | ✅ |
| REQ-R-04 | SHA ≤ 2000 LUT4 (ADR-0007) | WP-03 | `make synth-sha` | **1661 LUT4 (83% ngân sách)** | ✅ |

### 3.7 Kiểm chứng & phi chức năng

| REQ | Mô tả | WP | Cách xác nhận | TT |
|---|---|---|---|---|
| REQ-V-01 | Mỗi IP có testbench, mã thoát đúng | WP-03, WP-04 | 6 testbench PASS, `$fatal(1)` khi FAIL | ✅ |
| REQ-V-02 | Chỉ vector chính thức làm nguồn sự thật | WP-03, WP-04 | mọi vector sinh từ hiện thực tham chiếu; 2 vector bịa đã bị bắt và thay | ✅ |
| REQ-V-03 | Có test phần cứng thật | WP-08 | 7 log trong `evidence/hw/`, có timestamp | ✅ |
| REQ-V-04 | Test từ chối phải kèm liveness | WP-09 | TC-603/604/605 đều chạy đủ pha A+B trên board | ✅ |
| REQ-N-01 | Tổng hợp sạch, không latch | mọi WP | `make lint` sạch, 0 cảnh báo | ✅ |
| REQ-N-02 | Header file có REQ-ID | mọi WP | `check_headers.sh`, đã tự kiểm bằng vi phạm cố ý | ✅ |
| REQ-N-03 | Khóa tách ra `config/keys.vh` | WP-07 | `check_layering.sh` cưỡng chế chỉ top được include | ✅ |

## 4. Kiểm tra ngược — module nào chưa có requirement

Cập nhật khi RTL được viết. Module xuất hiện ở đây mà không có REQ là module mồ côi —
phải hoặc gắn REQ, hoặc xóa.

| Module | REQ phủ | TT |
|---|---|---|
| (tất cả module trong MODULE_MAP §2 đã có ≥1 REQ ở giai đoạn thiết kế) | — | ✅ khung |

## 4b. Chỗ phủ từng chưa đầy đủ — nay đã đóng

Ghi lại vì quá trình đóng chúng có giá trị hơn kết quả.

| REQ | Trước đây | Đã làm gì |
|---|---|---|
| REQ-F-05 | Chỉ phủ **gián tiếp**: "nếu key schedule sai thì TC-101/104 không PASS". Lập luận đúng nhưng không phân biệt được "đúng" với "sai theo cách bù trừ với lỗi khác". | Thêm `tb_keysched.v` kiểm **module con** — hợp đồng CSI chỉ ràng buộc đỉnh IP nên không cần thêm cổng quan sát nào. Đối chiếu 60/60 word với **hai** khóa. |
| REQ-F-23 | Đánh dấu đạt bằng **đọc RTL**. | Thêm TC-507 đo số chu kỳ loại khung khi byte digest sai ở vị trí đầu so với vị trí cuối: **208 = 208**. |
| REQ-P-05 / P-06 | Con số suy ra **bằng tay**. | Thêm bộ đếm tự động TC-103 / TC-205. Phát hiện số thật là **32** và **66**, không phải 30 và 65 như đã ghi. |
| REQ-F-12 | Chỉ 2–3 khối. | Thêm TC-204: 1000 byte = 16 khối. |
| REQ-F-30..32 | "Chờ quan sát bằng mắt". | `tb_led_status.v` (15 phép kiểm) **+** người phụ trách xác nhận trên board. |

## 5. Ràng buộc đã chấp nhận không thực hiện

| Mục | ADR | Lý do |
|---|---|---|
| HMAC-SHA-256 | ADR-0004 | Không vừa thiết bị (85–107% LUT4) | ⛔ |
| Trao đổi khóa | SCOPE §4 | Vượt xa ngân sách diện tích | ⛔ |
| Chống kênh kề | SCOPE §4 | Cần masking, nhân đôi diện tích | ⛔ |

## 6. Chỉ số sức khỏe tài liệu

Đo ở WP-10, theo `skills.txt` §C:

| Chỉ số | Định nghĩa | Mục tiêu | Hiện tại |
|---|---|---|---|
| Traceability coverage | % REQ có đủ module + test + bằng chứng | 100% | **39/39 = 100%** |
| Orphan rate (REQ) | % REQ không có code/test | 0% | 0% |
| Orphan rate (module) | % module không có REQ | 0% | 0% |
| Freshness | % tài liệu khớp commit hiện tại | 100% | 100% (quy tắc cùng-commit) |
| Decision coverage | % thay đổi kiến trúc có ADR | 100% | 100% (8/8) |
| Review evidence | % artifact có mục trong human correction log | 100% | **0%** ⚠️ |

> Ô cuối là 0% một cách trung thực: toàn bộ artifact do AI soạn và **chưa** qua bước người
> phụ trách chỉ ra chỗ sai rồi sửa. AI đã tự bắt được 20 lỗi của chính mình (xem
> `DEVELOPMENT_BOOK.md` §4.2), nhưng tự sửa không phải review. Theo `RISK_DELEGATION.md` §4,
> các artifact vì vậy chưa được coi là hoàn thành. Danh sách 5 chỗ đáng soi nhất ở
> `DEVELOPMENT_BOOK.md` §5.
