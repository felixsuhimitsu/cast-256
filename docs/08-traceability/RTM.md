# RTM — Requirements Traceability Matrix

**Artifact #11 / 11** · Cập nhật: 2026-09-09 · Trạng thái: 🚧 Khung đã lập, chờ WP thực thi

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
| REQ-F-01 | AES-256 14 vòng FIPS 197 | WP-04 | MOD-AES-ROUND, MOD-AES-CIPHER | TC-101 | TBD | ⬜ |
| REQ-F-02 | Chế độ CTR SP 800-38A | WP-04 | MOD-AES-IP | TC-104 | TBD | ⬜ |
| REQ-F-03 | Counter 128-bit, wrap đúng | WP-04 | MOD-AES-IP | TC-105 | TBD | ⬜ |
| REQ-F-04 | S-Box composite field | WP-04 | MOD-AES-SBOX | TC-100 | TBD | ⬜ |
| REQ-F-05 | Key schedule 15 khóa vòng | WP-04 | MOD-AES-KEYSCHED | TC-102 | TBD | ⬜ |
| REQ-F-06 | Dùng chung cipher cho cả hai chiều | WP-04 | MOD-AES-CIPHER | TC-106 | TBD | ⬜ |
| REQ-F-07 | Bỏ qua `start` khi busy | WP-04 | MOD-AES-IP | TC-107 | TBD | ⬜ |

### 3.2 IP SHA-256

| REQ | Mô tả ngắn | WP | Module | Test | Bằng chứng | TT |
|---|---|---|---|---|---|---|
| REQ-F-10 | SHA-256 64 vòng FIPS 180-4 | WP-03 | MOD-SHA-COMPRESS, MOD-SHA-K | TC-200, TC-202 | TBD | ⬜ |
| REQ-F-11 | Tự đệm theo chuẩn | WP-03 | MOD-SHA-PAD | TC-201, TC-203 | TBD | ⬜ |
| REQ-F-12 | Thông điệp nhiều khối | WP-03 | MOD-SHA-PAD, MOD-SHA-IP | TC-204 | TBD | ⬜ |
| REQ-F-13 | Cửa sổ trượt 16 word | WP-03 | MOD-SHA-SCHED | TC-208 + báo cáo DFF | TBD | ⬜ |
| REQ-F-14 | Xung `digest_valid` 1 chu kỳ | WP-03 | MOD-SHA-IP | TC-206 | TBD | ⬜ |

### 3.3 Giao thức

| REQ | Mô tả ngắn | WP | Module | Test | Bằng chứng | TT |
|---|---|---|---|---|---|---|
| REQ-F-20 | Đồng bộ bằng quét preamble | WP-06 | MOD-PROTO-RX, MOD-PROTO-TX | TC-500, TC-501, TC-508, TC-605 | TBD | ⬜ |
| REQ-F-21 | LEN trong [1,512] | WP-06 | MOD-PROTO-RX, MOD-PROTO-BUF | TC-504, TC-505 | TBD | ⬜ |
| REQ-F-22 | Chỉ phát khi digest khớp | WP-06 | MOD-PROTO-DGST, MOD-PROTO-FSM | TC-502, TC-503, TC-603 | TBD | ⬜ |
| REQ-F-23 | So sánh digest hằng thời | WP-06 | MOD-PROTO-DGST | TC-507 | TBD | ⬜ |
| REQ-F-24 | Watchdog 2²⁴ chu kỳ | WP-06 | MOD-PROTO-FSM | TC-506, TC-604 | TBD | ⬜ |
| REQ-F-25 | AES và SHA loại trừ tương hỗ | WP-05 | MOD-FAB-ARB | TC-400, TC-401 | TBD | ⬜ |
| REQ-F-30 | LED0 đang nhận | WP-07 | MOD-IO-LED | TC-606 | TBD | ⬜ |
| REQ-F-31 | LED1 engine bận | WP-07 | MOD-IO-LED | TC-606 | TBD | ⬜ |
| REQ-F-32 | LED2 chớp khi loại khung | WP-07 | MOD-IO-LED | TC-606 | TBD | ⬜ |

### 3.4 Giao diện

| REQ | Mô tả ngắn | WP | Module | Test | Bằng chứng | TT |
|---|---|---|---|---|---|---|
| REQ-I-01 | Hai IP cùng hợp đồng CSI | WP-05 | MOD-AES-IP, MOD-SHA-IP, MOD-FAB-MUX | TC-108, TC-207, TC-402, TC-403, TC-109 | TBD | ⬜ |
| REQ-I-02 | Bắt tay valid/ready đúng H1–H5 | WP-05 | tất cả IP | TC-108, TC-207 | TBD | ⬜ |
| REQ-I-03 | UART 8-N-1 115200 | WP-01 | MOD-IO-URX, MOD-IO-UTX, MOD-IO-BAUD | TC-300 | TBD | ⬜ |
| REQ-I-04 | Biểu quyết 3 điểm | WP-01 | MOD-IO-URX | TC-301, TC-302 | TBD | ⬜ |
| REQ-I-05 | Nhả IDLE sau bit stop | WP-01 | MOD-IO-URX | **TC-600** | TBD | ⬜ |

### 3.5 Hiệu năng — chỉ phủ được bằng phần cứng

| REQ | Ngưỡng | WP | Test | Bằng chứng | TT |
|---|---|---|---|---|---|
| REQ-P-01 | F_max ≥ 27 MHz | WP-07 | báo cáo nextpnr | TBD | ⬜ |
| REQ-P-02 | 0% mất khung / 100 khung | WP-08 | TC-602 | TBD | ⬜ |
| REQ-P-03 | Độ trễ ≤ 40 ms | WP-08 | TC-602 | TBD | ⬜ |
| REQ-P-04 | Thông lượng ≥ 8000 B/s | WP-08 | TC-602 | TBD | ⬜ |
| REQ-P-05 | AES ≤ 20 chu kỳ/khối | WP-04 | TC-103 | TBD | ⬜ |
| REQ-P-06 | SHA ≤ 70 chu kỳ/khối | WP-03 | TC-205 | TBD | ⬜ |

### 3.6 Tài nguyên

| REQ | Ngưỡng | WP | Cách đo | Số đo thật | TT |
|---|---|---|---|---|---|
| REQ-R-01 | LUT4 ≤ 7776 | WP-07 | nextpnr | TBD | ⬜ |
| REQ-R-02 | DFF ≤ 5184 | WP-07 | nextpnr | TBD | ⬜ |
| REQ-R-03 | AES ≤ 2200 LUT4 | WP-02, WP-04 | tổng hợp riêng | TBD | ⬜ |
| REQ-R-04 | SHA ≤ 1800 LUT4 | WP-02, WP-03 | tổng hợp riêng | TBD | ⬜ |

### 3.7 Kiểm chứng & phi chức năng

| REQ | Mô tả | WP | Cách xác nhận | TT |
|---|---|---|---|---|
| REQ-V-01 | Mỗi IP có testbench, mã thoát đúng | WP-03, WP-04 | `make sim-*; echo $?` | ⬜ |
| REQ-V-02 | Chỉ vector chính thức làm nguồn sự thật | WP-03, WP-04 | Review, TEST_PLAN §2 | ⬜ |
| REQ-V-03 | Có test phần cứng thật | WP-08 | Log trong `evidence/` | ⬜ |
| REQ-V-04 | Test từ chối phải kèm liveness | WP-09 | Review mã test: đủ pha A+B | ⬜ |
| REQ-N-01 | Tổng hợp sạch, không latch | mọi WP | `make lint` | ⬜ |
| REQ-N-02 | Header file có REQ-ID | mọi WP | Script kiểm trong `make lint` | ⬜ |
| REQ-N-03 | Khóa tách ra `config/keys.vh` | WP-07 | Review | ⬜ |

## 4. Kiểm tra ngược — module nào chưa có requirement

Cập nhật khi RTL được viết. Module xuất hiện ở đây mà không có REQ là module mồ côi —
phải hoặc gắn REQ, hoặc xóa.

| Module | REQ phủ | TT |
|---|---|---|
| (tất cả module trong MODULE_MAP §2 đã có ≥1 REQ ở giai đoạn thiết kế) | — | ✅ khung |

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
| Traceability coverage | % REQ có đủ module + test + bằng chứng | 100% | 0% (khung) |
| Orphan rate (REQ) | % REQ không có code/test | 0% | 0% |
| Orphan rate (module) | % module không có REQ | 0% | 0% |
| Freshness | % tài liệu khớp commit hiện tại | 100% | 100% |
| Decision coverage | % thay đổi kiến trúc có ADR | 100% | 100% (6/6) |
| Review evidence | % artifact có mục trong human correction log | 100% | **0%** ⚠️ |

> Ô cuối đang là 0% một cách trung thực: toàn bộ artifact hiện tại là bản nháp do AI soạn,
> **chưa** qua bước người phụ trách chỉ ra chỗ sai và sửa. Theo `RISK_DELEGATION.md` §4,
> chúng chưa được coi là hoàn thành. Đây là việc tiếp theo phải làm, không phải chi tiết
> hình thức.
