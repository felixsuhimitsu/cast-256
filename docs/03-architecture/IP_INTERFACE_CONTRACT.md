# HỢP ĐỒNG GIAO DIỆN IP — "CSI" (Crypto Stream Interface) v1.0

**Artifact #4b / 11** · Cập nhật: 2026-09-09 · Trạng thái: Baseline v1.0
**Hiện thực:** REQ-I-01, REQ-I-02 · **Ràng buộc bởi:** REQ-C-04 (Verilog-2001)

> Đây là tài liệu quan trọng nhất của đề tài. Nó là **ranh giới không được tự ý phá vỡ**.
> Thay đổi bất kỳ điều gì ở đây là thay đổi phá vỡ tương thích (breaking change) và bắt
> buộc phải có ADR.

---

## 1. Vì sao cần hợp đồng chung

Đề tài không chỉ là "viết AES" và "viết SHA". Giá trị nằm ở chỗ hai IP có **cùng một
hình dạng cổng**, nên tầng `fabric/` có thể đối xử với chúng như nhau, và một IP thứ ba
(ví dụ ChaCha20) có thể cắm vào sau này mà không sửa lớp giao thức.

Hệ quả kiểm chứng được: đổi chỗ hai IP trong sơ đồ khối không cần sửa một dòng nào của
`stream_mux.v`.

## 2. Sơ đồ cổng

Mọi IP tuân theo CSI PHẢI có đúng tập cổng sau. Tên cổng cố định.

```verilog
module <ip_name> #(
    parameter CSI_DATA_W = 8,     // độ rộng dòng dữ liệu, cố định 8 cho dự án này
    parameter CSI_RES_W  = 256    // độ rộng thanh ghi kết quả
) (
    // ── Nhịp & reset ────────────────────────────────────────────────
    input  wire                    clk,
    input  wire                    rst_n,        // reset bất đồng bộ, tích cực mức thấp

    // ── Điều khiển ──────────────────────────────────────────────────
    input  wire                    csi_start,    // xung 1 chu kỳ, bắt đầu thao tác mới
    input  wire [7:0]              csi_mode,     // ý nghĩa do từng IP định nghĩa (§6)
    output wire                    csi_busy,     // 1 = đang xử lý, csi_start bị bỏ qua
    output wire                    csi_done,     // xung 1 chu kỳ, kết quả đã sẵn sàng
    output wire                    csi_err,      // mức, giữ tới csi_start kế tiếp

    // ── Dòng dữ liệu vào ────────────────────────────────────────────
    input  wire [CSI_DATA_W-1:0]   sin_data,
    input  wire                    sin_valid,
    input  wire                    sin_last,     // 1 ở byte cuối của thông điệp
    output wire                    sin_ready,

    // ── Dòng dữ liệu ra ─────────────────────────────────────────────
    output wire [CSI_DATA_W-1:0]   sout_data,
    output wire                    sout_valid,
    output wire                    sout_last,
    input  wire                    sout_ready,

    // ── Kết quả dạng thanh ghi (dùng cho digest, tag…) ──────────────
    output wire [CSI_RES_W-1:0]    csi_result,
    output wire                    csi_result_valid
);
```

IP nào không dùng một nhóm cổng thì buộc dây cố định, **không được xóa cổng**:
- SHA-256 không sinh dòng ra → `sout_valid = 1'b0`, `sout_data = 0`, `sout_last = 1'b0`.
- AES-CTR không sinh kết quả thanh ghi → `csi_result = 0`, `csi_result_valid = 1'b0`.

## 3. Quy tắc bắt tay valid/ready

Giống AXI-Stream ở phần cốt lõi, đơn giản hóa cho Verilog-2001.

| # | Quy tắc |
|---|---|
| H1 | Một byte được chuyển khi và chỉ khi `valid && ready` cùng bằng 1 tại sườn lên của `clk`. |
| H2 | Khi bên phát đã đặt `valid = 1`, nó **PHẢI** giữ nguyên `valid`, `data`, `last` cho tới khi thấy `ready = 1`. Không được rút lại. |
| H3 | Bên nhận **ĐƯỢC PHÉP** đặt `ready = 1` khi `valid` chưa lên (ready không phụ thuộc valid). |
| H4 | Bên phát **KHÔNG ĐƯỢC** để `valid` phụ thuộc tổ hợp vào `ready` (tránh vòng lặp tổ hợp). |
| H5 | `last` chỉ có nghĩa khi `valid = 1`. |

Quy tắc H2 và H4 là hai chỗ dễ sai nhất. Testbench dùng chung
`sim/lib/csi_assert.vh` kiểm cả hai một cách tự động ở mọi instance.

## 4. Trình tự thao tác

```
     clk    ▁▔▁▔▁▔▁▔▁▔▁▔▁▔▁▔▁▔▁▔▁▔▁▔▁▔▁▔▁▔▁▔
csi_start   ▁▁▔▔▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁
 csi_busy   ▁▁▁▁▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▁▁▁▁▁
sin_valid   ▁▁▁▁▁▔▔▔▔▔▔▔▔▔▔▔▔▔▁▁▁▁▁▁▁▁▁▁▁▁▁▁
 sin_last   ▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▔▔▔▁▁▁▁▁▁▁▁▁▁▁▁▁▁
 csi_done   ▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▔▔▁▁▁▁
```

1. Wrapper đặt `csi_mode`, phát một xung `csi_start`.
2. IP đặt `csi_busy = 1` ở chu kỳ kế tiếp. Từ đây, mọi `csi_start` mới bị **bỏ qua**
   (REQ-F-07) — không được reset giữa chừng, không được sinh kết quả rác.
3. Wrapper đẩy byte vào qua `sin_*`, đặt `sin_last = 1` ở byte cuối.
4. IP xử lý; nếu có dòng ra, nó đẩy ra qua `sout_*` (có thể xen kẽ với dòng vào).
5. IP phát `csi_done` một chu kỳ, hạ `csi_busy`. Nếu có `csi_result`, nó hợp lệ **cùng
   chu kỳ** với `csi_done` và giữ nguyên tới `csi_start` kế tiếp.
6. Nếu lỗi (ví dụ `sin_last` tới sớm hơn dự kiến), IP đặt `csi_err = 1` **cùng lúc** với
   `csi_done`, và `csi_result` không được coi là hợp lệ.

## 5. Bất biến (invariant) — testbench kiểm tự động

| ID | Bất biến |
|---|---|
| INV-1 | `csi_done` không bao giờ lên khi `csi_busy` đang là 0. |
| INV-2 | `csi_done` rộng đúng 1 chu kỳ. |
| INV-3 | `sin_ready` không bao giờ lên khi `csi_busy` = 0. |
| INV-4 | Sau `csi_start`, `csi_busy` PHẢI lên trong ≤ 2 chu kỳ. |
| INV-5 | `csi_err = 1` ⟹ `csi_result_valid = 0`. |
| INV-6 | Số byte nhận qua `sin_*` với `sin_last=1` đúng một lần mỗi thao tác. |

## 6. Bảng `csi_mode` theo từng IP

### MOD-AES-IP (`aes256_ctr_ip.v`)

| Giá trị | Tên | Ý nghĩa |
|---|---|---|
| `8'h00` | `AES_LOAD_KEY` | Nạp 32 byte khóa qua `sin_*`, chạy key schedule. Không có dòng ra. |
| `8'h01` | `AES_LOAD_IV` | Nạp 16 byte IV/nonce ban đầu cho bộ đếm CTR. |
| `8'h02` | `AES_CRYPT` | Mã hóa/giải mã dòng byte: `sout = sin XOR keystream`. CTR đối xứng nên một mode dùng cho cả hai chiều (REQ-F-06). |
| khác | — | `csi_err = 1` ngay ở `csi_done`. |

### MOD-SHA-IP (`sha256_ip.v`)

| Giá trị | Tên | Ý nghĩa |
|---|---|---|
| `8'h00` | `SHA_HASH` | Băm dòng byte từ `sin_*`, tự đệm, xuất digest ở `csi_result`. |
| `8'h01` | `SHA_HASH_CONT` | Băm tiếp, giữ nguyên trạng thái từ lần trước (cho thông điệp ghép). |
| khác | — | `csi_err = 1`. |

## 7. Chống chỉ định — những gì hợp đồng này CẤM

1. **Cấm** IP đọc/ghi trực tiếp bộ nhớ dùng chung. Mọi dữ liệu đi qua `sin_*`/`sout_*`.
2. **Cấm** IP có cổng ra khỏi danh sách §2 (kể cả cổng debug). Tín hiệu debug phải đi
   qua một module bọc riêng ở tầng `fabric/`, không nằm trong IP.
3. **Cấm** dùng `initial` để khởi tạo thanh ghi thay cho `rst_n` — không tổng hợp tin cậy
   trên Gowin.
4. **Cấm** hai IP cùng có `csi_busy = 1` tại một thời điểm (REQ-F-25, cưỡng chế bởi
   `MOD-FAB-ARB`).

## 8. Cách thêm một IP thứ ba

Đây là bài kiểm tra thật cho thiết kế: nếu quy trình dưới đây cần sửa `protocol/`, hợp
đồng đã thất bại.

1. Viết module theo §2, khai báo bảng `csi_mode` riêng.
2. Thêm một entry vào tham số `NUM_IP` của `fabric/stream_mux.v` và `fabric/ip_arbiter.v`.
3. Thêm testbench dùng `sim/lib/csi_assert.vh`.
4. Cập nhật `MODULE_MAP.md` và `RTM.md`.

Không đụng tới `protocol/`, không đụng tới `io/`.
