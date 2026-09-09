# TEST PLAN — Thế nào là đúng

**Artifact #10 / 11** · Cập nhật: 2026-09-09 · Trạng thái: Baseline v1.0

---

## 1. Ba mức kiểm chứng

| Mức | Công cụ | Chứng minh được gì | **Không** chứng minh được gì |
|---|---|---|---|
| L1 — Đơn vị (mô phỏng) | Icarus Verilog | Thuật toán đúng chuẩn | Có chạy trên silicon không |
| L2 — Tích hợp (mô phỏng) | Icarus Verilog | FSM, bắt tay, xử lý lỗi | Timing thật, hành vi luồng liên tục |
| L3 — Phần cứng | `scripts/hw_test.py` + board | Hệ thống thật hoạt động | Tính đúng đắn mật mã (quá ít vector) |

**Quy tắc:** L1 và L3 **bù cho nhau, không thay thế nhau**. Một kết quả L1 PASS không bao
giờ được dùng làm bằng chứng cho REQ-P-02..04 (REQ-V-03). Bug UART ở `ADR-0005` là ví dụ:
L1 PASS hoàn toàn trong khi phần cứng hỏng.

## 2. Nguồn vector — bắt buộc

| Vector | Nguồn chính thức | Dùng ở |
|---|---|---|
| AES-256 khối đơn | FIPS 197, Phụ lục C.3 | TC-101 |
| AES-256 key schedule W[0..59] | FIPS 197, Phụ lục A.3 | TC-102 |
| AES-256-CTR 4 khối | NIST SP 800-38A, F.5.5 | TC-104 |
| S-Box 256 giá trị | FIPS 197, Hình 7 | TC-100 |
| SHA-256 ngắn/dài | FIPS 180-4, Phụ lục B | TC-201..203 |
| SHA-256 1M×'a' | FIPS 180-4, B.3 | TC-204 |

REQ-V-02: **không** dùng vector tự sinh làm nguồn sự thật. Vector tự sinh chỉ dùng cho
kiểm tra hồi quy sau khi vector chính thức đã PASS.

## 3. Danh mục test case

### L1 — IP AES-256 (`make sim-aes`)

| TC | Mục tiêu | REQ | Tiêu chí PASS |
|---|---|---|---|
| TC-100 | S-Box đối chiếu toàn bộ | REQ-F-04 | 256/256 giá trị khớp |
| TC-101 | Mã hóa khối đơn | REQ-F-01 | Khớp bit FIPS 197 C.3 |
| TC-102 | Key schedule | REQ-F-05 | 60/60 word khớp |
| TC-103 | Số chu kỳ mỗi khối | REQ-P-05 | ≤ 20 chu kỳ |
| TC-104 | CTR 4 khối liên tiếp | REQ-F-02 | Khớp SP 800-38A F.5.5 |
| TC-105 | Counter tràn all-ones → 0 | REQ-F-03 | Khối kế tiếp đúng |
| TC-106 | Mã rồi giải, vòng tròn | REQ-F-06 | PT == D(E(PT)), 100 khối ngẫu nhiên |
| TC-107 | `csi_start` khi đang bận | REQ-F-07 | Bị bỏ qua, kết quả không hỏng |
| TC-108 | Bất biến CSI INV-1..6 | REQ-I-01, REQ-I-02 | Không assertion nào bắn |
| TC-109 | `csi_mode` không hợp lệ | REQ-I-01 | `csi_err`=1 cùng `csi_done` |

### L1 — IP SHA-256 (`make sim-sha`)

| TC | Mục tiêu | REQ | Tiêu chí PASS |
|---|---|---|---|
| TC-200 | Hằng số K | REQ-F-10 | 64/64 khớp |
| TC-201 | `""` (rỗng) | REQ-F-11 | `e3b0c442…7852b855` |
| TC-202 | `"abc"` | REQ-F-10 | `ba7816bf…f20015ad` |
| TC-203 | Biên đệm: 55, 56, 63, 64, 119, 120 byte | REQ-F-11 | 6/6 khớp |
| TC-204 | 1.000.000 × `'a'` | REQ-F-12 | `cdc76e5c…2f92a0` |
| TC-205 | Số chu kỳ mỗi khối | REQ-P-06 | ≤ 70 chu kỳ |
| TC-206 | Độ rộng xung `digest_valid` | REQ-F-14 | Đúng 1 chu kỳ |
| TC-207 | Bất biến CSI INV-1..6 | REQ-I-01 | Không assertion nào bắn |
| TC-208 | Cửa sổ trượt không rò word cũ | REQ-F-13 | Hai lần băm liên tiếp cho kết quả độc lập |

> TC-203 là test quan trọng nhất của SHA. Độ dài 55 và 56 byte nằm hai bên ranh giới nơi
> phần đệm phải tràn sang khối thứ hai — chỗ sai phổ biến nhất.

### L1 — Lớp vật lý (`make sim-uart`)

| TC | Mục tiêu | REQ | Tiêu chí PASS |
|---|---|---|---|
| TC-300 | Thu/phát một byte | REQ-I-03 | Khớp |
| TC-301 | Biểu quyết 3 điểm với xung nhiễu 1 chu kỳ | REQ-I-04 | Vẫn đúng |
| TC-302 | Bit stop sai | REQ-I-04 | Cờ lỗi khung bật, byte bị bỏ |

### L2 — Fabric (`make sim-fabric`)

| TC | Mục tiêu | REQ | Tiêu chí PASS |
|---|---|---|---|
| TC-400 | Loại trừ tương hỗ | REQ-F-25 | `aes_busy & sha_busy` luôn = 0 (assertion mọi chu kỳ) |
| TC-401 | Thứ tự cấp SHA→AES→SHA | REQ-F-25 | Đúng thứ tự |
| TC-402 | Đổi chỗ hai IP giả lập | REQ-I-01 | Không sửa `stream_mux.v` mà vẫn chạy |
| TC-403 | Nhả IP khi `csi_err` | REQ-I-01 | Trọng tài không treo |

### L2 — Giao thức (`make sim-top`)

| TC | Mục tiêu | REQ | Tiêu chí PASS |
|---|---|---|---|
| TC-500 | Khung hợp lệ khứ hồi | REQ-F-20 | Bản rõ giải mã khớp |
| TC-501 | 32 byte rác trước preamble | REQ-F-20 | Vẫn nhận đúng |
| TC-502 | Lật 1 bit trong payload | REQ-F-22 | **Không phát gì** |
| TC-503 | Lật 1 bit trong digest | REQ-F-22 | **Không phát gì** |
| TC-504 | LEN = 0 | REQ-F-21 | Loại khung |
| TC-505 | LEN = 1024 | REQ-F-21 | Loại khung |
| TC-506 | Khung cắt giữa chừng | REQ-F-24 | Watchdog về IDLE, khung sau vẫn nhận |
| TC-507 | So sánh digest hằng thời | REQ-F-23 | Số chu kỳ so sánh giống nhau cho mọi đầu vào |
| TC-508 | Hai khung liên tiếp không nghỉ | REQ-F-20 | Cả hai đúng |

### L3 — Phần cứng (`scripts/hw_test.py`)

| TC | Chế độ | REQ | Tiêu chí PASS |
|---|---|---|---|
| TC-600 | `--mode uartloop` (WP-01) | REQ-I-05 | 512 byte back-to-back, **0 mất** |
| TC-601 | `--mode echo` | REQ-F-20, REQ-P-01 | Một khung khứ hồi đúng |
| TC-602 | `--mode bench` | REQ-P-02..04 | 100 khung: 0% mất, ≤40 ms, ≥8000 B/s |
| TC-603 | `--mode tamper` | REQ-F-22, **REQ-V-04** | Khung hỏng bị từ chối **VÀ** khung hợp lệ ngay sau đó thành công |
| TC-604 | `--mode timeout` | REQ-F-24, **REQ-V-04** | Khung cắt bị bỏ **VÀ** khung hợp lệ ngay sau đó thành công |
| TC-605 | `--mode garbage` | REQ-F-20 | 32 byte rác rồi khung hợp lệ → thành công |
| TC-606 | Quan sát LED | REQ-F-30..32 | Đúng như đặc tả, ghi hình lại |

## 4. Quy tắc chống PASS giả

Đây là phần rút ra từ lỗi thật ở thiết kế trước.

> Ở lần làm trước, `--mode tamper` và `--mode timeout` chỉ kiểm **"FPGA trả về 0 byte"**.
> Cả hai vẫn báo PASS trong khi bitstream hỏng hoàn toàn và mọi khung đều bị loại. Test
> đã "đúng" theo nghĩa của nó, nhưng nó kiểm sai thứ.

**Quy tắc bắt buộc (REQ-V-04):** mọi test có tiêu chí dạng "không có phản hồi" PHẢI gồm
hai pha:

```
Pha A — kích thích tiêu cực   → kỳ vọng: im lặng
Pha B — kích thích hợp lệ     → kỳ vọng: phản hồi ĐÚNG   ← bằng chứng liveness
```

Test chỉ có pha A **bị coi là không hợp lệ** và không được tính vào gate Done.

## 5. Ma trận: REQ nào được test nào phủ

Bảng đầy đủ ở `../08-traceability/RTM.md`. Ở đây chỉ tóm tắt vùng phủ:

| Nhóm REQ | Số REQ | Phủ bởi L1 | L2 | L3 |
|---|---|---|---|---|
| REQ-F (chức năng) | 20 | 14 | 9 | 5 |
| REQ-I (giao diện) | 5 | 5 | 2 | 2 |
| REQ-P (hiệu năng) | 6 | 2 | 0 | 4 |
| REQ-R (tài nguyên) | 4 | báo cáo tổng hợp | — | — |
| REQ-V (kiểm chứng) | 4 | meta — kiểm bằng review |

REQ-P-01..04 **chỉ** phủ được bởi L3. Đây là lý do REQ-V-03 tồn tại.

## 6. Cách chạy

```bash
source ~/tools/oss-cad-suite/environment    # nạp toolchain

make lint          # kiểm cú pháp + latch + ràng buộc phụ thuộc tầng
make sim-aes       # L1 AES
make sim-sha       # L1 SHA
make sim-uart      # L1 UART
make sim-fabric    # L2 fabric
make sim-top       # L2 toàn hệ
make sim           # tất cả các mức mô phỏng

make synth         # tổng hợp + P&R, in bảng tài nguyên
make flash         # nạp bitstream (chạy tiền cảnh, KHÔNG chạy nền)

# L3 — chú ý dùng python hệ thống, không dùng python của oss-cad-suite
/usr/bin/python3 scripts/hw_test.py --port /dev/ttyUSB1 --mode echo
/usr/bin/python3 scripts/hw_test.py --port /dev/ttyUSB1 --mode bench
```

**Hai cái bẫy đã gặp thật, ghi lại để không mất thời gian lần nữa:**

1. `/dev/ttyUSB0` là kênh **JTAG**, không phải UART. Kênh UART là **`/dev/ttyUSB1`**.
   Đọc nhầm cổng cho ra dữ liệu rác trông giống lỗi giao thức.
2. `source ~/tools/oss-cad-suite/environment` che mất `python3` của hệ thống bằng bản
   3.11 riêng **không có pyserial**. Luôn gọi `/usr/bin/python3` tường minh cho test L3.
