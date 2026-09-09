# DEVELOPMENT BOOK — Đã thử gì, sai ở đâu, vì sao chọn hướng này

**Artifact xuyên suốt** · Cập nhật: 2026-09-09

---

## 1. Tài liệu này khác ADR ở chỗ nào

- **ADR** ghi *quyết định*: chọn gì, vì sao, hệ quả. Bất biến sau khi Accepted.
- **Development Book** ghi *quá trình*: đã thử gì, cái gì không chạy, số đo thật, người
  sửa AI ở đâu. Ghi thêm liên tục, không xóa.

Một điều sai đã thử mà không được ghi lại sẽ bị thử lại. Đó là lý do phần §4 tồn tại.

---

## 2. Nhật ký theo work package

### WP-00 — Khung dự án · TT: ✅ Done (2026-09-09)

**Đã làm:**
- Xóa `rtl/` và `sim/` cũ (giữ nguyên trong lịch sử git trên nhánh `main`), dựng cây mới
  theo `MODULE_MAP.md` §1: `config/`, `ip/aes256/`, `ip/sha256/`, `protocol/`, `fabric/`, `io/`.
- `sim/lib/tb_util.vh`: macro `CHECK_EQ` / `CHECK_TRUE` / `CHECK_LE` / `TB_END` / `TB_TIMEOUT`.
  `TB_END` dùng `$fatal(1,...)` để iverilog trả **mã thoát khác 0** khi FAIL — điều kiện
  của REQ-V-01. Nếu chỉ `$finish` thì testbench FAIL vẫn trả 0 và CI sẽ báo xanh sai.
- `sim/lib/csi_checker.v`: module kiểm tự động INV-1..6 và quy tắc bắt tay H2, H5 của hợp
  đồng CSI. Instantiate song song với IP, đếm vi phạm ra cổng `viol_count`.
- `scripts/check_headers.sh` (REQ-N-02), `scripts/check_layering.sh` (MODULE_MAP §4).
- `Makefile`: target `lint / sim-* / synth-aes / synth-sha / synth / flash / test / bench`.

**Ba chỗ đưa bài học cũ thẳng vào công cụ, không để trong đầu:**
1. `synth` dùng `2>&1 | tee` cho nextpnr — công cụ ghi toàn bộ ra stderr, thiếu `2>&1`
   thì log luôn 0 byte (§4.1 mục 8).
2. `YOSYS_FLAGS` cố định `-nowidelut` kèm bình luận giải thích, để không ai bỏ đi lần nữa
   (§4.1 mục 3).
3. Target `test`/`bench` gọi `/usr/bin/python3` tường minh, không dùng `python3` (§4.1 mục 9).
   `PORT` mặc định `/dev/ttyUSB1`, có ghi chú `ttyUSB0` là JTAG (§4.1 mục 5).

**Tự kiểm gate (quan trọng):** `make lint` chạy sạch trên cây rỗng — nhưng "sạch" khi
không có gì để kiểm là vô nghĩa, đúng kiểu Done giả số 1 trong `DEFINITION_OF_DONE.md` §4.
Vì vậy đã dựng vi phạm cố ý để kiểm chính cái gate:

| Vi phạm dựng lên | Gate | Kết quả |
|---|---|---|
| File trong `ip/aes256/` không có header | `check_headers.sh` | FAIL, exit=1 ✅ |
| Module trong `ip/` instantiate module của `io/` | `check_layering.sh` | FAIL, exit=1 ✅ |
| (sau khi dọn) | cả hai | PASS, exit=0 ✅ |

Gate được chứng minh là bắt được vi phạm thật, không phải luôn xanh.

**Còn nợ (đã xử lý một phần ở WP-01):** `constraints/tangnano9k.cst` kế thừa có hai vấn
đề — 3 LED khai `LVCMOS18` trong khi `rst_n` cùng IO bank là `LVCMOS33` (làm `gowin_pack`
dừng, không sinh bitstream), và gán chân UART bị ngược. `constraints/uart_echo.cst` của
WP-01 đã dùng gán chân đúng và LVCMOS33 toàn bộ, đã kiểm chứng trên board. File
`tangnano9k.cst` sẽ được viết lại ở WP-07 dựa trên bản đã kiểm chứng này.

### WP-01 — Đường ống UART trần · TT: ✅ Done (2026-09-09) — **GATE CỨNG ĐÃ QUA**

**Đã làm:** `baud_gen.v`, `uart_rx.v`, `uart_tx.v` + bitstream thăm dò
`rtl/probe/uart_echo_top.v` (FIFO 16 byte). Tổng hợp 331 LUT4, F_max 140 MHz.

#### Lỗi 1 — testbench bắt được lỗi thật trong `uart_rx`

TC-301 (biểu quyết 3 điểm chống nhiễu) FAIL 6/8: nhiễu 1 chu kỳ trên các bit có
giá trị 0 vẫn lọt qua ở bit 3 và bit 5.

Nguyên nhân: `vote` được dùng ở **đúng chu kỳ** mà `samples[2]` đang được gán.
Vì gán là nonblocking, `vote` đọc giá trị **cũ** của `samples[2]` — vốn là `1`
từ lần reset. Nên với bit giá trị 0, phép biểu quyết thành `majority(s0, s1, 1)`:
chỉ cần một trong hai mẫu còn lại bị nhiễu là kết quả lật.

Sửa: thêm `SDEC = S2 + 1`, quyết định trễ một chu kỳ sau mẫu cuối. Dự phòng bắt
sườn start còn 234 − 126 = **108 chu kỳ**, vẫn dư xa so với 3.75 chu kỳ của
thiết kế cũ. TC-300..302 sau đó PASS 10/10.

Đây đúng loại lỗi mà chỉ testbench có kịch bản nhiễu mới bắt được — một bộ test
chỉ gửi byte sạch sẽ PASS hoàn toàn.

#### Lỗi 2 — GÁN CHÂN UART CỦA THIẾT KẾ TRƯỚC BỊ NGƯỢC

Nạp lần đầu với `rx=17, tx=18` (chép từ `constraints/tangnano9k.cst` của thiết
kế cũ): **0/512 byte vọng về**, và ca đối chứng có nghỉ 1 ms cũng 0/64.

Chính ca đối chứng là thứ chỉ đúng hướng: nếu là mất đồng bộ tích lũy thì ca có
nghỉ phải chạy được. Cả hai đều bằng 0 nghĩa là **không có đường về**, tức là
vấn đề vật lý chứ không phải logic.

Đảo chân rồi nạp lại:

| Gán chân | 512 byte liên tục | 1024 | 4096 |
|---|---|---|---|
| rx=17, tx=18 (như thiết kế cũ) | **0/512** | — | — |
| **rx=18, tx=17** | **512/512** | **1024/1024** | **4096/4096** |

Kết luận: trên Tang Nano 9K, **chân 18 là FPGA THU, chân 17 là FPGA PHÁT**.
`constraints/tangnano9k.cst` kế thừa từ thiết kế trước ghi ngược, và điều này
phải sửa trước khi dùng ở WP-07.

> Ghi chú về nhận định trước đó: trong phiên làm việc trước, giả thuyết "đảo chân
> UART" từng bị coi là đã bác bỏ. Số đo ở đây cho thấy kết luận đó sai. Bằng
> chứng là 4096/4096 với gán chân đảo so với 0/512 với gán chân cũ, trên cùng
> một board, cùng một bitstream logic.

#### Kết quả gate

| Bài | Kết quả |
|---|---|
| TC-600a: 512 byte liên tục, không nghỉ | **0 byte mất** ✅ |
| TC-600b: nội dung đúng từng byte | ✅ |
| Bổ sung: 1024 byte | 0 mất ✅ |
| Bổ sung: 4096 byte | 0 mất ✅ |
| Thông lượng đo được | 4096 B trong 355.6 ms ≈ 11.5 kB/s (đạt trần lý thuyết) |

REQ-I-05 **đạt**, chứng minh trên phần cứng thật (REQ-V-03). Log gốc:
`evidence/hw/20260909-2230-TC600-uartloop-4096.log`.

### WP-02 — Thăm dò diện tích · TT: ✅ Done (2026-09-09)

**Đổi cách làm so với WBS.** Kế hoạch ban đầu là đo "khung rỗng" của AES và SHA. Nhưng
yosys sẽ tối ưu mất logic rỗng, cho ra số vô nghĩa — đo xong vẫn không biết gì. Thay vào
đó đã viết và đo **hai khối thật sự tốn diện tích nhất**: S-Box composite field và hàm nén
SHA-256. Số đo vì thế là số thật, và code viết ra dùng luôn được cho WP-03/WP-04.

**S-Box: sinh hằng số bằng Python trước, viết Verilog sau.**
`scripts/gen_sbox_basis.py` tìm phép đẳng cấu GF(2^8)→GF(((2²)²)²) bằng cách quét
(PHI, LAM, nghiệm t), rồi **kiểm đủ 256/256 giá trị so với S-Box FIPS 197 ngay trong
Python**. Chỉ khi Python báo PASS mới chép hằng số sang Verilog. Kết quả:
`PHI=2, LAM=8, t=0x41`. Đây là biện pháp trực tiếp cho RSK-03 — nếu để Verilog tự "đúng
hay sai thì chạy testbench mới biết" thì lỗi lộ ra dưới dạng "vector AES fail" không manh mối.

**Tự kiểm TC-100 bằng lỗi cố ý.** Đổi một hằng số ma trận từ `8'h6C` thành `8'h6D`:

| Phép kiểm | Với S-Box hỏng |
|---|---|
| Đối chiếu 256 giá trị | **FAIL** — 128 giá trị sai, exit=1 ✅ |
| Kiểm song ánh | **vẫn PASS** ⚠️ |

Đúng như RSK-03 dự đoán: S-Box sai vẫn có thể là song ánh. Nếu chỉ kiểm song ánh hoặc chỉ
thử vài giá trị thì lỗi lọt qua. Đây là lý do REQ-F-04 ghi rõ "đối chiếu **toàn bộ** 256".

**Một tối ưu có đo, và nó thực sự có tác dụng.** `sha256_compress` đo lần đầu 1132 LUT4,
trong đó 844 là LUT3 — mux 3 chiều trên 256 bit trạng thái `a..h` (ba nhánh
`init`/`step`/`finalize`). Bỏ việc nạp lại `a..h` ở nhánh `finalize` (khối kế tiếp dùng
`init` với `h_in = h_out`) → còn 2 nguồn → **892 LUT4, giảm 240 (21%)**.

Khác biệt so với ba lần "tối ưu" thất bại ở §4.1: lần này **đo trước, thấy chỗ tốn, rồi
mới sửa** — không phải đoán rồi sửa.

**Kết luận gate:** cả hai IP dự phóng vượt ngân sách *riêng* ban đầu, nhưng tổng toàn
thiết kế chỉ ~5740/8640 (66%), còn xa trần REQ-R-01. Theo đúng thủ tục gate: dừng lại, mở
[`ADR-0007`](../09-decisions/ADR-0007-dieu-chinh-ngan-sach-dien-tich.md), nới REQ-R-03
(2200→2400) và REQ-R-04 (1800→2000), giữ nguyên ngân sách tổng. Kèm hai quyết định kiến
trúc: AES dùng 16 S-Box (không phải 20, khóa vòng tính sẵn), `sha256_k` giữ dạng logic.

### WP-03 — IP SHA-256 · TT: ✅ Done (2026-09-09)

**Đã làm:** `sha256_pad.v` (đệm FIPS 180-4) + `sha256_ip.v` (đỉnh IP theo hợp đồng CSI),
ghép với `sha256_k/sched/compress` đã viết ở WP-02. Testbench `tb_sha256_ip.v` **PASS 17/17**.
Diện tích **1661 LUT4 / 1146 DFF / 464 ALU** — dưới ngưỡng REQ-R-04 (2000), dùng 83% ngân sách.

#### Lỗi 1 — điều khiển có thanh ghi làm lệch pha K[t] với W[t]

Bản đầu dùng tín hiệu điều khiển được ghi vào thanh ghi (`cmp_step <= 1'b1`). Hệ quả:
`round` tăng ở chu kỳ trước khi vòng nén tương ứng thực sự chạy, nên `K[1]` bị ghép với
`W[0]`. Đã phát hiện khi phân tích dạng sóng bằng tay trước cả khi chạy testbench.

Sửa: chuyển toàn bộ tín hiệu điều khiển sang **tổ hợp** dẫn xuất trực tiếp từ `state`.
Khi đó trong mỗi chu kỳ `ST_COMPRESS`, các đại lượng `round`, `w_t`, `k_t` và `step` đều
thuộc cùng một vòng. Thêm một trạng thái `ST_CINIT` một chu kỳ để nạp trạng thái H.

#### Lỗi 2 — tớ tự bịa vector kiểm chứng

Bản testbench đầu tiên có sáu giá trị digest cho các độ dài 55/56/63/64/119 byte được
viết ra từ trí nhớ, không tra nguồn. Khi đối chiếu lại bằng `hashlib`:

| Độ dài | Giá trị đã viết | Đúng? |
|---|---|---|
| 55 byte | `9f4390f8…0f734318` | đúng |
| **56 byte** | `…ef797686_86b6b6f3` | **SAI** (đúng là `…ef797068_6ec6738a`) |
| 63, 64 byte | — | đúng |
| **119 byte** | `1c8bfa4a…5d4f0b56` | **SAI hoàn toàn** |

Nếu để nguyên, hai vector sai này sẽ làm testbench FAIL trên một IP **đúng**, và nhiều
khả năng phản ứng tiếp theo là đi sửa RTL cho khớp vector sai. Đây chính là điều REQ-V-02
cấm: **không dùng vector tự sinh làm nguồn sự thật**.

Đã thay toàn bộ bằng giá trị sinh từ `hashlib` (hiện thực tham chiếu của FIPS 180-4) và
ghi rõ nguồn trong testbench.

#### Lỗi 3 — vi phạm hợp đồng CSI ở nhánh lỗi

`csi_checker` bắt được 2 vi phạm khi `csi_mode` không hợp lệ: IP báo `csi_done` ngay
trong `ST_IDLE`, tức là `done` lên khi chưa từng `busy` (INV-1), và `busy` không bao giờ
lên sau `start` (INV-4).

Có hai cách sửa: nới hợp đồng, hoặc sửa IP. **Chọn sửa IP** — thêm trạng thái `ST_ERR`
một chu kỳ. Hợp đồng là ranh giới của đề tài; nới nó ra để code dễ hơn là làm hỏng đúng
thứ đang được chấm điểm.

#### Lỗi 4 — đo diện tích bằng grep cho số GẤP ĐÔI

Lần đo đầu báo **3322 LUT4**, tức là vượt ngưỡng 2000 rất xa và suýt nữa dẫn tới một
đợt "tối ưu" không cần thiết. Nguyên nhân: yosys in bảng thống kê **hai lần** (một cho
module, một cho `design hierarchy`), và lệnh `grep | awk` cộng cả hai. Số thật là **1661**.

Đã viết `scripts/area.py` chỉ lấy khối đầu tiên, và thay `grep|awk` trong Makefile bằng
script này. Một gate cho số sai còn tệ hơn không có gate.

#### Giới hạn thật, đã ghi vào SRS §10.4

Hợp đồng CSI đánh dấu byte cuối bằng `sin_last` **đi kèm một byte hợp lệ**, nên **thông
điệp độ dài 0 không biểu diễn được**. Đã bỏ độ dài 0 khỏi tiêu chí REQ-F-11 thay vì giả
vờ test nó. Không ảnh hưởng hệ thống (REQ-F-21 buộc `LEN ∈ [1,512]`), nhưng ai dùng lại
IP ở dự án khác cần biết.

### WP-04 — IP AES-256 · TT: ⬜
*(chưa có mục)*

### WP-05 — Fabric CSI · TT: ⬜
*(chưa có mục)*

### WP-06 — Lớp giao thức · TT: ⬜
*(chưa có mục)*

### WP-07 — Tích hợp phần cứng · TT: ⬜
*(chưa có mục)*

### WP-08 — Đo hiệu năng · TT: ⬜
*(chưa có mục)*

### WP-09 — Test đối kháng · TT: ⬜
*(chưa có mục)*

### WP-10 — RTM & báo cáo · TT: ⬜
*(chưa có mục)*

---

## 3. Số đo thật

Chỉ ghi số **đọc từ log công cụ**, không ghi số ước lượng. Mỗi dòng phải trỏ được về một
file trong `evidence/`.

### 3.1 Tài nguyên theo module (tổng hợp riêng lẻ)

| Ngày | Module | LUT4 | ALU | DFF | Ngân sách | Đạt? | Ghi chú |
|---|---|---|---|---|---|---|---|
| 2026-09-09 | `aes256_sbox` | **81** | 0 | 0 | 70 | ⚠️ +16% | ×16 = 1296 trong AES |
| 2026-09-09 | `sha256_sched` | **242** | 32 | 512 | 420 | ✅ −42% | cửa sổ trượt hiệu quả hơn dự kiến |
| 2026-09-09 | `sha256_k` | **286** | 0 | 0 | 180 | ⚠️ +59% | ROM 64×32 dạng logic |
| 2026-09-09 | `sha256_compress` | 1132 | 352 | 512 | 780 | ❌ +45% | trước khi sửa mux 3 chiều |
| 2026-09-09 | `sha256_compress` | **892** | 352 | 512 | 780 | ⚠️ +14% | sau khi sửa, −240 LUT4 |
| 2026-09-09 | **`sha256_ip` (cả IP)** | **1661** | 464 | 1146 | 2000 (REQ-R-04) | ✅ 83% | `make synth-sha`, log ở `evidence/synth/` |

Cách đo: `yosys -p "read_verilog <file>; synth_gowin -no-rw-check -nowidelut -top <mod>"`.
Cột LUT4 là tổng LUT1+LUT2+LUT3+LUT4 — trên Gowin mọi loại đều chiếm một slot LUT4.
Ngân sách đã điều chỉnh theo ADR-0007 sau đợt đo này.

### 3.2 Tài nguyên toàn thiết kế

| Ngày | Commit | LUT4 | % | DFF | % | BSRAM | F_max | Log |
|---|---|---|---|---|---|---|---|---|
| — | — | — | — | — | — | — | — | — |

### 3.3 Hiệu năng phần cứng

| Ngày | Chế độ | Số byte/khung | Mất | Thông lượng | Ghi chú | Log |
|---|---|---|---|---|---|---|
| 2026-09-09 | uartloop (TC-600) | 512 byte | **0** | — | gate WP-01 | `evidence/hw/` |
| 2026-09-09 | uartloop | 1024 byte | **0** | 11.5 kB/s | — | `evidence/hw/` |
| 2026-09-09 | uartloop | 4096 byte | **0** | 11.5 kB/s | 355.6 ms | `evidence/hw/20260909-2230-TC600-uartloop-4096.log` |

---

## 4. Những thứ đã thử và KHÔNG chạy

Phần này quý hơn phần "đã chạy". Ghi lại để không ai (kể cả AI trong phiên sau) thử lại.

### 4.1 Từ thiết kế trước — đã kiểm chứng, không lặp lại

| # | Đã thử | Kết quả | Vì sao sai |
|---|---|---|---|
| 1 | Thêm HMAC-SHA-256 vào bitstream | 7359/8640 LUT4 (85%), P&R **FAIL** | Hai instance SHA không vừa. Xem ADR-0004 |
| 2 | "Tối ưu" HMAC bằng thanh ghi dịch | 7724 LUT4 (89%) — **tệ hơn** | Mỗi bit cần mux 3 chiều nạp/dịch/giữ, đắt hơn thanh ghi thường |
| 3 | Bỏ cờ `-nowidelut` để dùng LUT rộng | 9248 LUT4 (107%) — **tệ hơn nhiều** | Trên Gowin, MUX2_LUT5..8 được dựng **từ chính LUT4**. Không hề tiết kiệm, còn thêm chi phí định tuyến |
| 4 | Đổ lỗi cáp sạc khi board không enumerate | Sai — đổi cáp thứ hai vẫn không lên | Nguyên nhân thật ở đầu cắm phía chip. Bài học: chẩn đoán một-nguyên-nhân quá sớm |
| 5 | Đọc `/dev/ttyUSB0` để lấy dữ liệu UART | Ra dữ liệu rác, tưởng lỗi giao thức | `ttyUSB0` là kênh **JTAG** của FT2232. Kênh UART là `ttyUSB1` |
| 6 | Giả thuyết đảo chân UART 17/18 | Sai — bitstream thăm dò chứng minh chân đúng | Mất thời gian vì đoán thay vì đo |
| 7 | Chạy lệnh nạp bitstream ở chế độ nền | Tiến trình treo giữ thiết bị FTDI, phải rút cắm lại | Lệnh chạm phần cứng phải chạy tiền cảnh |
| 8 | `\| tee nextpnr.log` để lưu log P&R | File luôn 0 byte | nextpnr ghi ra **stderr**. Phải `2>&1 \| tee` |
| 9 | Dùng `python3` sau khi `source oss-cad-suite/environment` | `pyserial is required` | Toolchain che `python3` hệ thống bằng bản riêng. Gọi `/usr/bin/python3` |
| 10 | Đọc bản báo cáo telemetry **đầu tiên** sau khi gửi | Số liệu vô nghĩa | Khung mất 10.2 ms, báo cáo mỗi 300 ms → mẫu rơi giữa khung. Phải đọc bản **cuối** |

### 4.2 Trong dự án này

| # | Đã thử | Kết quả | Vì sao |
|---|---|---|---|
| 1 | Đo "khung rỗng" của IP để thăm dò diện tích (theo WBS ban đầu) | Bỏ, không làm | yosys tối ưu mất logic rỗng → số vô nghĩa. Đổi sang đo hai khối tốn nhất và viết thật |
| 2 | Gán `a..h` ở cả ba nhánh init/step/finalize trong `sha256_compress` | 1132 LUT4, trong đó 844 LUT3 | Mỗi bit trong 256 bit cần mux 3 chiều. Bỏ nhánh `finalize` → 892 LUT4 |
| 3 | Dùng `vote` ngay tại chu kỳ lấy mẫu thứ ba trong `uart_rx` | TC-301 FAIL 6/8 | Gán nonblocking: `samples[2]` chưa cập nhật, vote đọc giá trị cũ. Phải quyết định ở `S2+1` |
| 6 | Tín hiệu điều khiển SHA đặt trong thanh ghi | K[t] lệch pha với W[t] | `round` tăng trước khi vòng nén chạy. Chuyển sang điều khiển tổ hợp dẫn xuất từ `state` |
| 7 | Viết vector digest từ trí nhớ thay vì tra nguồn | 2/6 vector SAI | Vector sai làm testbench FAIL trên IP đúng → dễ dẫn tới sửa RTL cho khớp vector sai. Luôn sinh vector từ hiện thực tham chiếu (REQ-V-02) |
| 8 | Đo diện tích bằng `grep 'LUT' \| awk sum` | 3322 thay vì 1661 — **gấp đôi** | yosys in bảng thống kê hai lần. Dùng `scripts/area.py` |
| 4 | Chép gán chân UART từ `constraints/tangnano9k.cst` cũ (rx=17, tx=18) | 0/512 byte vọng về | Ngược chân. Đúng là **rx=18, tx=17** — đã đo trên board |
| 5 | Tin rằng giả thuyết "đảo chân UART" đã bị bác bỏ ở phiên trước | Sai | Kết luận cũ không có số đo đi kèm. Bài học: một giả thuyết chỉ được coi là bác bỏ khi có phép đo, không phải khi có lập luận |

---

## 5. Human correction log — bằng chứng người can thiệp

Theo `../05-risk/RISK_DELEGATION.md` §4: một artifact chỉ được đánh ✅ khi người phụ trách
đã chỉ ra ít nhất một chỗ AI sai hoặc thiếu, và sửa lại.

| Ngày | Artifact | AI sai/thiếu chỗ nào | Người sửa thành | Ai |
|---|---|---|---|---|
| — | — | — | — | — |

> **Bảng này đang rỗng.** Nghĩa là chưa artifact nào được review thật sự, dù chúng trông
> hoàn chỉnh. Đây là trạng thái trung thực, không phải thiếu sót về hình thức — và nó là
> việc tiếp theo phải làm trước khi đánh dấu bất kỳ artifact nào là Done.

Gợi ý những chỗ đáng soi kỹ nhất, vì đó là chỗ AI dễ sai nhất:

1. **Ngân sách LUT4 trong `MODULE_MAP.md` §2** — các con số này là *ước lượng của AI*,
   chưa đo. Tổng 7690 chỉ dư 11%. Nếu ước lượng lệch 15% thì kế hoạch vỡ. WP-02 tồn tại
   để kiểm chính chỗ này.
2. **Ngân sách timing trong `ARCHITECTURE.md` §6** — các số ns là ước đoán, chưa chạy
   phân tích tĩnh nào.
3. **Ước lượng PERT trong `ESTIMATION.md`** — dựa trên cảm tính, không có dữ liệu lịch sử
   của chính đội này.
4. **Danh mục test case** — kiểm xem có test nào "kiểm sai thứ" giống bug ở §4.1 mục 1
   của TEST_PLAN không.
5. **Số chu kỳ REQ-P-05/06** (≤20 và ≤70) — kiểm lại bằng tay xem có khả thi với kiến
   trúc đã chọn không, hay là con số đặt cho đẹp.

---

## 6. Thư mục bằng chứng

`evidence/` chứa log gốc, không chỉnh sửa:

```
evidence/
├── synth/       báo cáo nextpnr theo ngày, đặt tên <ngày>-<commit ngắn>.log
├── sim/         đầu ra testbench
└── hw/          log chạy trên board, có timestamp
```

Quy tắc: **mọi con số xuất hiện trong báo cáo nộp phải truy được về một file ở đây.**
