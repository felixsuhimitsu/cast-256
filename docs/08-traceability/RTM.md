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
| REQ-F-01 | AES-256 14 vòng FIPS 197 | WP-04 | MOD-AES-ROUND, MOD-AES-CIPHER | TC-101 | `make sim-aes` — FIPS 197 C.3 khớp | ✅ |
| REQ-F-02 | Chế độ CTR SP 800-38A | WP-04 | MOD-AES-IP | TC-104 | 4/4 khối F.5.5 khớp | ✅ |
| REQ-F-03 | Counter 128-bit, wrap đúng | WP-04 | MOD-AES-IP | TC-105 | all-ones → 0, cả hai khối khớp | ✅ |
| REQ-F-04 | S-Box composite field | WP-04 | MOD-AES-SBOX | TC-100 | `sim/unit/tb_sbox.v` 256/256 PASS | ✅ |
| REQ-F-05 | Key schedule 15 khóa vòng | WP-04 | MOD-AES-KEYSCHED | TC-101, TC-104 (gián tiếp) | 15/15 khóa vòng khớp FIPS 197 A.3 khi dump; **không có test trực tiếp** — xem §5 | 🚧 |
| REQ-F-06 | Dùng chung cipher cho cả hai chiều | WP-04 | MOD-AES-CIPHER | TC-106 | mã→giải 48 byte về đúng bản rõ | ✅ |
| REQ-F-07 | Bỏ qua `start` khi busy | WP-04 | MOD-AES-IP | TC-107 | start giữa chừng bị bỏ, kết quả không hỏng | ✅ |

### 3.2 IP SHA-256

| REQ | Mô tả ngắn | WP | Module | Test | Bằng chứng | TT |
|---|---|---|---|---|---|---|
| REQ-F-10 | SHA-256 64 vòng FIPS 180-4 | WP-03 | MOD-SHA-COMPRESS, MOD-SHA-K | TC-202 | `make sim-sha` — SHA("abc") khớp | ✅ |
| REQ-F-11 | Tự đệm theo chuẩn | WP-03 | MOD-SHA-PAD | TC-203 | 1/55/56/63/64/119/120 byte đều khớp | ✅ |
| REQ-F-12 | Thông điệp nhiều khối | WP-03 | MOD-SHA-PAD, MOD-SHA-IP | TC-203 (119, 120 byte = 2–3 khối) | khớp | ✅ |
| REQ-F-13 | Cửa sổ trượt 16 word | WP-03 | MOD-SHA-SCHED | TC-208 + đo DFF | 512 DFF (thay vì 2048) | ✅ |
| REQ-F-14 | Xung `digest_valid` 1 chu kỳ | WP-03 | MOD-SHA-IP | TC-206 | độ rộng đo được = 1 | ✅ |

### 3.3 Giao thức

| REQ | Mô tả ngắn | WP | Module | Test | Bằng chứng | TT |
|---|---|---|---|---|---|---|
| REQ-F-20 | Đồng bộ bằng quét preamble | WP-06 | MOD-PROTO-RX, MOD-PROTO-TX | TC-500, TC-501, TC-508 | `make sim-top` — khung khứ hồi đúng bản mã và digest; 32 byte rác trước preamble vẫn nhận đúng | ✅ (còn TC-605 trên board) |
| REQ-F-21 | LEN trong [1,512] | WP-06 | MOD-PROTO-RX, MOD-PROTO-BUF | TC-504, TC-505 | LEN=0 và LEN=1024 đều bị loại | ✅ |
| REQ-F-22 | Chỉ phát khi digest khớp | WP-06 | MOD-PROTO-DGST, MOD-PROTO-FSM | TC-502, TC-503 | lật 1 bit payload và 1 bit digest → im lặng; khung hợp lệ sau đó vẫn chạy | ✅ (còn TC-603 trên board) |
| REQ-F-23 | So sánh digest hằng thời | WP-06 | MOD-PROTO-DGST | đọc RTL | XOR 256 bit + OR-reduce, 1 chu kỳ, không nhánh phụ thuộc dữ liệu | ✅ |
| REQ-F-24 | Watchdog 2²⁴ chu kỳ | WP-06 | MOD-PROTO-RX | TC-506 | khung cắt → im lặng, **và** khung hợp lệ sau đó chạy đúng (đủ hai pha REQ-V-04) | ✅ (còn TC-604 trên board) |
| REQ-F-25 | AES và SHA loại trừ tương hỗ | WP-05 | MOD-FAB-ARB, MOD-FAB-MUX | TC-400, TC-401 | assertion mọi chu kỳ: 0 lần hai IP cùng bận; grant luôn one-hot | ✅ |
| REQ-F-30 | LED0 đang nhận | WP-07 | MOD-IO-LED | TC-606 | TBD | ⬜ |
| REQ-F-31 | LED1 engine bận | WP-07 | MOD-IO-LED | TC-606 | TBD | ⬜ |
| REQ-F-32 | LED2 chớp khi loại khung | WP-07 | MOD-IO-LED | TC-606 | TBD | ⬜ |

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
| REQ-P-01 | F_max ≥ 27 MHz | WP-07 | báo cáo nextpnr | TBD | ⬜ |
| REQ-P-02 | 0% mất khung / 100 khung | WP-08 | TC-602 | TBD | ⬜ |
| REQ-P-03 | Độ trễ ≤ 40 ms | WP-08 | TC-602 | TBD | ⬜ |
| REQ-P-04 | Thông lượng ≥ 8000 B/s | WP-08 | TC-602 | TBD | ⬜ |
| REQ-P-05 | AES ≤ 32 chu kỳ/khối (ADR-0008) | WP-04 | đếm trong mô phỏng | 30 chu kỳ | ✅ |
| REQ-P-06 | SHA ≤ 70 chu kỳ/khối | WP-03 | TC-205 | 65 chu kỳ nén (1 init + 64 vòng) | ✅ |

### 3.6 Tài nguyên

| REQ | Ngưỡng | WP | Cách đo | Số đo thật | TT |
|---|---|---|---|---|---|
| REQ-R-01 | LUT4 ≤ 7776 | WP-07 | nextpnr | TBD | ⬜ |
| REQ-R-02 | DFF ≤ 5184 | WP-07 | nextpnr | TBD | ⬜ |
| REQ-R-03 | AES ≤ 2600 LUT4 (ADR-0008) | WP-04 | `make synth-aes` | **2528 LUT4 (97% ngân sách)** | ✅ |
| REQ-R-04 | SHA ≤ 2000 LUT4 (ADR-0007) | WP-03 | `make synth-sha` | **1661 LUT4 (83% ngân sách)** | ✅ |

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

## 4b. Chỗ phủ chưa đầy đủ — ghi rõ thay vì làm ngơ

| REQ | Thiếu gì | Vì sao chấp nhận tạm |
|---|---|---|
| REQ-F-05 | Không có test **trực tiếp** đối chiếu W[0..59] với FIPS 197 A.3 | `aes256_keysched` không có cổng ra khóa vòng ở mức IP, nên testbench cấp IP không quan sát được. 15/15 khóa vòng ĐÃ được đối chiếu thủ công bằng testbench gỡ lỗi ở WP-04 và khớp hoàn toàn; ngoài ra nếu key schedule sai thì TC-101/TC-104 không thể PASS. Muốn phủ trực tiếp thì phải thêm cổng quan sát — vi phạm §7 hợp đồng CSI (cấm cổng ngoài danh sách). |

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
| Traceability coverage | % REQ có đủ module + test + bằng chứng | 100% | 26/39 = 67% |
| Orphan rate (REQ) | % REQ không có code/test | 0% | 0% |
| Orphan rate (module) | % module không có REQ | 0% | 0% |
| Freshness | % tài liệu khớp commit hiện tại | 100% | 100% |
| Decision coverage | % thay đổi kiến trúc có ADR | 100% | 100% (8/8) |
| Review evidence | % artifact có mục trong human correction log | 100% | **0%** ⚠️ |

> Ô cuối đang là 0% một cách trung thực: toàn bộ artifact hiện tại là bản nháp do AI soạn,
> **chưa** qua bước người phụ trách chỉ ra chỗ sai và sửa. Theo `RISK_DELEGATION.md` §4,
> chúng chưa được coi là hoàn thành. Đây là việc tiếp theo phải làm, không phải chi tiết
> hình thức.
