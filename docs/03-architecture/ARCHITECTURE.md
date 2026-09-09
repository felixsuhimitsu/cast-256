# ARCHITECTURE — Các phần liên hệ với nhau thế nào

**Artifact #4 / 11** · Cập nhật: 2026-09-09 · Trạng thái: Baseline v1.0
**Đi kèm:** [`IP_INTERFACE_CONTRACT.md`](IP_INTERFACE_CONTRACT.md)

---

## 1. Sơ đồ khối tổng thể

```
 HOST (PC, Python)                    FPGA Tang Nano 9K — 27.0 MHz, một miền xung nhịp
 ─────────────────       │
                         │
  ┌───────────┐   UART   │   ┌──────────┐    ┌─────────────┐    ┌──────────────┐
  │ hw_test.py│═════════▶│──▶│MOD-IO-URX│───▶│MOD-PROTO-RX │───▶│MOD-PROTO-BUF │
  │           │ 115200   │   │ baud_gen │    │ quét preamble│   │  BSRAM 512B  │
  │  đóng gói │          │   └──────────┘    │ tách LEN/IV  │   └──────┬───────┘
  │  khung    │          │                   └──────┬───────┘          │
  └───────────┘          │                          │                  │
        ▲                │                          ▼                  ▼
        ║                │                   ┌─────────────────────────────────┐
        ║                │                   │      MOD-PROTO-FSM              │
        ║                │                   │  điều phối phiên + watchdog     │
        ║                │                   └────────────┬────────────────────┘
        ║                │                                │ yêu cầu cấp IP
        ║                │                   ┌────────────▼────────────────────┐
        ║                │                   │  fabric/                        │
        ║                │                   │  ┌───────────┐  ┌────────────┐  │
        ║                │                   │  │ip_arbiter │─▶│ stream_mux │  │
        ║                │                   │  │ loại trừ  │  │  định tuyến│  │
        ║                │                   │  │ tương hỗ  │  │  CSI       │  │
        ║                │                   │  └───────────┘  └──┬──────┬──┘  │
        ║                │                   └────────────────────┼──────┼─────┘
        ║                │                             CSI ┌──────┘      └──────┐ CSI
        ║                │                                 ▼                    ▼
        ║                │                        ┌─────────────────┐  ┌─────────────────┐
        ║                │                        │  MOD-AES-IP     │  │  MOD-SHA-IP     │
        ║                │                        │  AES-256-CTR    │  │  SHA-256        │
        ║                │                        │  ~2200 LUT4     │  │  ~1800 LUT4     │
        ║                │                        └─────────────────┘  └────────┬────────┘
        ║                │                                                      │ digest
        ║                │                   ┌──────────────┐   ┌───────────────▼──────┐
        ║                │   ┌──────────┐    │ MOD-PROTO-TX │◀──│  MOD-PROTO-DGST      │
        ╚════════════════│◀──│MOD-IO-UTX│◀───│  đóng khung  │   │  so sánh hằng thời   │
                         │   └──────────┘    └──────────────┘   └──────────────────────┘
                         │                                          │ khớp / không khớp
                         │                                          ▼
                         │                                   ┌──────────────┐
                         │                                   │ MOD-IO-LED   │
                         │                                   │  3 đèn       │
                         │                                   └──────────────┘
```

## 2. Bốn tầng và lý do tách

| Tầng | Trách nhiệm | Vì sao tách riêng |
|---|---|---|
| `io/` | Chuyển đổi bit nối tiếp ↔ byte | Đổi UART sang SPI/RS-485 chỉ cần thay tầng này |
| `protocol/` | Ý nghĩa của khung: đâu là LEN, IV, payload, digest | Đổi định dạng khung không đụng tới mật mã |
| `fabric/` | Ai được dùng IP nào, lúc nào | Thêm IP thứ ba chỉ đụng tầng này |
| `ip/` | Toán học mật mã thuần túy | Tái sử dụng được nguyên vẹn ở dự án khác |

Ràng buộc phụ thuộc một chiều đã ghi ở `../02-module-map/MODULE_MAP.md` §4.

## 3. Luồng dữ liệu một khung — từng bước

Giả sử host gửi khung 128 byte payload.

| Bước | Ai làm | Hành động | IP được cấp |
|---|---|---|---|
| 1 | MOD-IO-URX | Thu byte, biểu quyết 3 điểm, xuất `rx_data`/`rx_valid` | — |
| 2 | MOD-PROTO-RX | Quét `A5 5A`, đọc LEN (2B), IV (16B) | — |
| 3 | MOD-PROTO-RX → BUF | Ghi 128 byte payload vào BSRAM | — |
| 4 | MOD-PROTO-RX | Đọc 32 byte DIGEST vào thanh ghi so sánh | — |
| 5 | MOD-PROTO-FSM | Yêu cầu trọng tài cấp SHA | SHA |
| 6 | MOD-SHA-IP | Băm `LEN‖IV‖payload` từ BSRAM, xuất `csi_result` | SHA |
| 7 | MOD-PROTO-DGST | So sánh đủ 32 byte, thời gian hằng định | — |
| 8a | — | **Không khớp** → chớp LED2, xóa BSRAM, về IDLE. **Không phát gì.** | — |
| 8b | MOD-PROTO-FSM | **Khớp** → nhả SHA, xin cấp AES | AES |
| 9 | MOD-AES-IP | Nạp IV, mã hóa 128 byte từ BSRAM, ghi đè bản mã vào BSRAM | AES |
| 10 | MOD-PROTO-FSM | Nhả AES, xin cấp SHA lần hai | SHA |
| 11 | MOD-SHA-IP | Băm lại `LEN‖IV‖ciphertext` để host kiểm được khung trả về | SHA |
| 12 | MOD-PROTO-TX | Đóng khung: `A5 5A ‖ LEN ‖ IV ‖ CT ‖ DIGEST'` | — |
| 13 | MOD-IO-UTX | Phát nối tiếp | — |

Điểm cần chú ý ở bước 8a: **không phát gì cả** khi digest sai. Đây là hành vi có chủ đích
(REQ-F-22) — im lặng là câu trả lời an toàn, và nó cũng làm cho `--mode tamper` ở phía host
kiểm được đúng thứ cần kiểm.

## 4. Ba quyết định kiến trúc lớn

### 4.1 Một engine, nhiều lượt — không song song

AES và SHA **không** chạy đồng thời (REQ-F-25). Một khung đi qua SHA → AES → SHA tuần tự.

*Đánh đổi:* mất thông lượng lý thuyết. *Được lại:* ~1500 LUT4 (không cần nhân đôi đường
dữ liệu và bộ đệm), và loại bỏ hoàn toàn một lớp lỗi khó gỡ (tranh chấp tài nguyên).

*Vì sao chấp nhận được:* UART 115200 baud cho tối đa ~11.5 kB/s. AES cần ~20 chu kỳ/khối
ở 27 MHz = ~216 kB/s. Engine nhanh hơn đường truyền **19 lần**. Song song hóa chỉ làm
engine rảnh nhiều hơn. Chi tiết ở `ADR-0002`.

### 4.2 Đệm ở BSRAM, không ở thanh ghi

512 byte payload chứa trong BSRAM (4 khối), không phải 4096 DFF.

*Đánh đổi:* thêm 1 chu kỳ độ trễ đọc, FSM phức tạp hơn. *Được lại:* ~4000 DFF, tức là
sự khác biệt giữa "vừa thiết bị" và "không".

### 4.3 Trọng tài tách khỏi định tuyến

`ip_arbiter.v` chỉ quyết định *ai được cấp*; `stream_mux.v` chỉ *nối dây*. Hai việc khác
nhau, hai module khác nhau.

*Vì sao:* khi thêm IP thứ ba, chính sách cấp phát (arbiter) thay đổi nhưng cơ chế nối dây
(mux) chỉ tăng số cổng. Trộn hai việc này là nguyên nhân phổ biến của lỗi khó tìm.

## 5. Miền xung nhịp và reset

- **Một miền duy nhất**, 27.0 MHz từ bộ dao động on-board. Không có CDC, không có
  synchronizer, không có FIFO bất đồng bộ. Đây là lựa chọn có ý thức để loại bỏ cả một
  họ lỗi metastability.
- **Reset**: `rst_n` bất đồng bộ (nút bấm, chân 3), nhưng được **đồng bộ nhả** bằng hai
  tầng DFF trong `top_secure_link.v` trước khi phân phối. Assert bất đồng bộ, de-assert
  đồng bộ — mẫu chuẩn.
- **Đầu vào UART RX** là tín hiệu bất đồng bộ từ ngoài, PHẢI qua 2 tầng DFF trong
  `uart_rx.v` trước khi dùng. Đây là **CDC duy nhất** trong thiết kế.

## 6. Ngân sách timing

| Đường tổ hợp | Ước lượng | Ngân sách 27 MHz = 37.0 ns |
|---|---|---|
| S-Box composite (sâu nhất trong AES) | ~14 ns | OK |
| MixColumns sau S-Box | ~6 ns | cộng dồn ~20 ns, OK |
| Cộng dồn vòng nén SHA (a..h) | ~18 ns | OK |
| So sánh 32 byte digest | ~4 ns (song song hoàn toàn) | OK |

Đường nguy hiểm nhất: `S-Box → MixColumns → AddRoundKey` trong `aes256_round.v`. Nếu
báo cáo nextpnr cho F_max < 30 MHz, biện pháp đầu tiên là chèn một tầng thanh ghi giữa
S-Box và MixColumns (tăng AES từ 14 lên 28 chu kỳ/khối — vẫn thừa xa so với §4.1).

## 7. Chiến lược an toàn khi lỗi

| Tình huống | Hành vi |
|---|---|
| Digest không khớp | Im lặng, chớp LED2, xóa buffer |
| LEN ngoài [1,512] | Loại khung ngay lúc đọc, không cấp phát buffer |
| Khung dở dang > 2^24 chu kỳ | Watchdog đưa FSM về IDLE, xóa buffer |
| IP báo `csi_err` | FSM coi như digest sai: im lặng, chớp LED2 |
| Lỗi khung UART (bit stop sai) | Bỏ byte đó, không làm hỏng đồng bộ preamble |

Nguyên tắc chung: **fail closed** — khi nghi ngờ thì không phát gì. Không bao giờ phát
dữ liệu chưa được xác thực toàn vẹn.
