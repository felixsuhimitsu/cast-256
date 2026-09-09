# MODULE MAP — Chức năng nằm ở đâu

**Artifact #3 / 11** · Cập nhật: 2026-09-09 · Trạng thái: Baseline v1.0

Tài liệu này trả lời một câu hỏi duy nhất: *"muốn sửa hành vi X thì mở file nào?"*

---

## 1. Cây thư mục RTL

```
rtl/
├── config/
│   └── keys.vh                  MOD-CFG-KEYS      khóa AES nạp cứng (giới hạn thiết kế)
├── ip/
│   ├── aes256/
│   │   ├── aes256_sbox.v        MOD-AES-SBOX      S-Box composite field
│   │   ├── aes256_keysched.v    MOD-AES-KEYSCHED  sinh 15 khóa vòng
│   │   ├── aes256_round.v       MOD-AES-ROUND     một vòng: SubBytes→ShiftRows→MixCol→AddRK
│   │   ├── aes256_cipher.v      MOD-AES-CIPHER    FSM 14 vòng, khối 128 bit
│   │   └── aes256_ctr_ip.v      MOD-AES-IP        ★ đỉnh IP, theo hợp đồng interface
│   └── sha256/
│       ├── sha256_k.v           MOD-SHA-K         64 hằng số K
│       ├── sha256_sched.v       MOD-SHA-SCHED     cửa sổ trượt 16 word
│       ├── sha256_compress.v    MOD-SHA-COMPRESS  vòng nén, 8 biến a..h
│       ├── sha256_pad.v         MOD-SHA-PAD       đệm FIPS 180-4
│       └── sha256_ip.v          MOD-SHA-IP        ★ đỉnh IP, theo hợp đồng interface
├── protocol/
│   ├── frame_rx.v               MOD-PROTO-RX      mở khung, quét preamble
│   ├── frame_tx.v               MOD-PROTO-TX      đóng khung phát đi
│   ├── digest_check.v           MOD-PROTO-DGST    so sánh 32 byte thời gian hằng
│   ├── frame_buffer.v           MOD-PROTO-BUF     BSRAM đệm payload
│   └── session_fsm.v            MOD-PROTO-FSM     điều phối phiên + watchdog
├── fabric/
│   ├── ip_arbiter.v             MOD-FAB-ARB       trọng tài AES ↔ SHA, loại trừ tương hỗ
│   └── stream_mux.v             MOD-FAB-MUX       định tuyến dòng dữ liệu tới IP đang được cấp
├── io/
│   ├── baud_gen.v               MOD-IO-BAUD       chia nhịp 27 MHz → 115200
│   ├── uart_rx.v                MOD-IO-URX        thu, biểu quyết 3 điểm
│   ├── uart_tx.v                MOD-IO-UTX        phát
│   └── led_status.v             MOD-IO-LED        3 đèn chỉ thị
└── top_secure_link.v            MOD-TOP           đỉnh thiết kế, nối tất cả
```

★ = điểm tích hợp. Ai muốn dùng lại IP trong dự án khác chỉ cần đọc hai file này và
`../03-architecture/IP_INTERFACE_CONTRACT.md`.

## 2. Bảng module ↔ requirement

| Module ID | File | Hiện thực REQ | Ngân sách LUT4 |
|---|---|---|---|
| MOD-AES-SBOX | `ip/aes256/aes256_sbox.v` | REQ-F-04 | 16 × 70 = 1120 |
| MOD-AES-KEYSCHED | `ip/aes256/aes256_keysched.v` | REQ-F-05 | 320 |
| MOD-AES-ROUND | `ip/aes256/aes256_round.v` | REQ-F-01 | 240 |
| MOD-AES-CIPHER | `ip/aes256/aes256_cipher.v` | REQ-F-01, REQ-F-06, REQ-P-05 | 180 |
| MOD-AES-IP | `ip/aes256/aes256_ctr_ip.v` | REQ-F-02, REQ-F-03, REQ-F-07, REQ-I-01 | 340 |
| | | **Cộng AES** | **2200** (= REQ-R-03) |
| MOD-SHA-K | `ip/sha256/sha256_k.v` | REQ-F-10 | 180 |
| MOD-SHA-SCHED | `ip/sha256/sha256_sched.v` | REQ-F-13 | 420 |
| MOD-SHA-COMPRESS | `ip/sha256/sha256_compress.v` | REQ-F-10, REQ-P-06 | 780 |
| MOD-SHA-PAD | `ip/sha256/sha256_pad.v` | REQ-F-11, REQ-F-12 | 260 |
| MOD-SHA-IP | `ip/sha256/sha256_ip.v` | REQ-F-14, REQ-I-01 | 160 |
| | | **Cộng SHA** | **1800** (= REQ-R-04) |
| MOD-PROTO-RX | `protocol/frame_rx.v` | REQ-F-20, REQ-F-21 | 300 |
| MOD-PROTO-TX | `protocol/frame_tx.v` | REQ-F-20 | 220 |
| MOD-PROTO-DGST | `protocol/digest_check.v` | REQ-F-22, REQ-F-23 | 120 |
| MOD-PROTO-BUF | `protocol/frame_buffer.v` | REQ-F-21 | 60 + 4 BSRAM |
| MOD-PROTO-FSM | `protocol/session_fsm.v` | REQ-F-24, REQ-F-22 | 380 |
| MOD-FAB-ARB | `fabric/ip_arbiter.v` | REQ-F-25 | 90 |
| MOD-FAB-MUX | `fabric/stream_mux.v` | REQ-I-01 | 150 |
| MOD-IO-BAUD | `io/baud_gen.v` | REQ-I-03 | 40 |
| MOD-IO-URX | `io/uart_rx.v` | REQ-I-03, REQ-I-04, REQ-I-05 | 110 |
| MOD-IO-UTX | `io/uart_tx.v` | REQ-I-03 | 80 |
| MOD-IO-LED | `io/led_status.v` | REQ-F-30..32 | 60 |
| MOD-TOP | `top_secure_link.v` | REQ-N-01 | 80 |
| | | **Tổng ngân sách** | **≈ 7690 / 8640 (89%)** |

> Ngân sách này sát trần REQ-R-01 (7776). Đây là cảnh báo có chủ đích: nếu WP-02 đo thấy
> AES hoặc SHA vượt ngân sách riêng, PHẢI dừng và mở ADR, không được "cứ viết tiếp rồi
> tính sau". Bài học từ thiết kế trước.

## 3. Bảng "muốn sửa X thì mở file nào"

| Muốn thay đổi… | Mở file |
|---|---|
| Tốc độ baud | `io/baud_gen.v` + `docs/01-spec/SRS.md` REQ-I-03 |
| Byte preamble | `protocol/frame_rx.v`, `protocol/frame_tx.v` + SRS §4.1 |
| Độ dài payload tối đa | `protocol/frame_buffer.v`, `session_fsm.v` + SRS REQ-F-21 |
| Khóa AES | `config/keys.vh` |
| Thời gian watchdog | `protocol/session_fsm.v` + SRS REQ-F-24 |
| Ưu tiên giữa AES và SHA | `fabric/ip_arbiter.v` + ADR-0006 |
| Cách chớp đèn | `io/led_status.v` |
| Gán chân, mức điện áp | `constraints/tangnano9k.cst` |
| Thêm một IP mật mã thứ ba | `fabric/stream_mux.v` + `ip_arbiter.v`; IP mới phải theo hợp đồng interface |

## 4. Phụ thuộc giữa module

```
                    top_secure_link
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
   io/ (uart)      protocol/ (khung)     fabric/ (định tuyến)
        │                  │                  │
        │                  │            ┌─────┴─────┐
        │                  │      ip/aes256    ip/sha256
        └──────────────────┴──────────────┘
```

Quy tắc phụ thuộc — **không được vi phạm**:

1. `ip/` KHÔNG được biết gì về `protocol/`, `io/`, hay `fabric/`. Hai IP phải dùng lại
   được nguyên vẹn trong dự án khác.
2. `protocol/` KHÔNG được instantiate trực tiếp module trong `ip/`; phải đi qua `fabric/`.
3. `io/` không phụ thuộc bất kỳ tầng nào khác.
4. Chỉ `top_secure_link.v` được phép tham chiếu `config/keys.vh`.

Quy tắc 1 và 2 chính là thứ biến "hai khối mật mã" thành "hai IP core tích hợp được" —
đúng tên đề tài. Nếu vi phạm, đề tài mất giá trị cốt lõi.
