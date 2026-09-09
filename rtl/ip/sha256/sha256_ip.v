//=============================================================================
// File   : rtl/ip/sha256/sha256_ip.v
// Mục đích: Đỉnh IP SHA-256 — theo hợp đồng giao diện CSI v1.0.
// REQ    : REQ-F-10, REQ-F-11, REQ-F-12, REQ-F-14, REQ-I-01, REQ-I-02
// ADR    : ADR-0003, ADR-0006
// Tác giả : Đội Hủ Tiếu · Ngày: 2026-09-09
//=============================================================================
// ĐÂY LÀ MỘT TRONG HAI ĐIỂM TÍCH HỢP của đề tài. Ai muốn dùng lại IP này ở dự
// án khác chỉ cần đọc file này và docs/03-architecture/IP_INTERFACE_CONTRACT.md.
// IP không biết gì về UART, về khung dữ liệu, hay về AES.
//
// csi_mode:
//   8'h00 SHA_HASH      — băm thông điệp mới, bắt đầu từ IV chuẩn
//   8'h01 SHA_HASH_CONT — băm tiếp, giữ trạng thái H từ lần trước
//   khác  — csi_err = 1 cùng lúc với csi_done
//
// Không có dòng dữ liệu ra: sout_* buộc dây 0 theo §2 của hợp đồng.
//
// ĐIỀU KHIỂN DÙNG TÍN HIỆU TỔ HỢP, KHÔNG PHẢI THANH GHI.
// Bản đầu tiên dùng tín hiệu điều khiển có thanh ghi và bị lệch pha một chu kỳ:
// `round` tăng trước khi vòng nén tương ứng thực sự chạy, nên K[t] ghép với
// W[t-1]. Với điều khiển tổ hợp, trong mỗi chu kỳ ST_COMPRESS thì `round`,
// `w_t`, `k_t` và tín hiệu `step` đều thuộc CÙNG một vòng — dễ đọc và dễ đúng.
//
// Thời gian mỗi khối 64 byte: 16 chu kỳ gom word (chồng lấn với thời gian byte
// đi vào) + 1 nạp trạng thái + 64 vòng + 1 cộng dồn = 66 chu kỳ ngoài phần gom.
// Phần nén thuần 65 chu kỳ, dưới ngưỡng 70 của REQ-P-06.
//=============================================================================

`timescale 1ns / 1ps

module sha256_ip #(
    parameter CSI_DATA_W = 8,
    parameter CSI_RES_W  = 256
) (
    input  wire                    clk,
    input  wire                    rst_n,

    input  wire                    csi_start,
    input  wire [7:0]              csi_mode,
    output wire                    csi_busy,
    output reg                     csi_done,
    output reg                     csi_err,

    input  wire [CSI_DATA_W-1:0]   sin_data,
    input  wire                    sin_valid,
    input  wire                    sin_last,
    output wire                    sin_ready,

    output wire [CSI_DATA_W-1:0]   sout_data,
    output wire                    sout_valid,
    output wire                    sout_last,
    input  wire                    sout_ready,

    output wire [CSI_RES_W-1:0]    csi_result,
    output wire                    csi_result_valid
);

    localparam [7:0] MODE_HASH = 8'h00,
                     MODE_CONT = 8'h01;

    // IV chuẩn FIPS 180-4 §5.3.3
    localparam [255:0] SHA256_IV = {
        32'h6a09e667, 32'hbb67ae85, 32'h3c6ef372, 32'ha54ff53a,
        32'h510e527f, 32'h9b05688c, 32'h1f83d9ab, 32'h5be0cd19
    };

    localparam [2:0] ST_IDLE     = 3'd0,
                     ST_FILL     = 3'd1,   // gom byte đã đệm thành 16 word
                     ST_CINIT    = 3'd2,   // nạp trạng thái H vào a..h
                     ST_COMPRESS = 3'd3,   // 64 vòng nén
                     ST_ACCUM    = 3'd4,   // cộng dồn a..h vào H
                     ST_FINISH   = 3'd5,
                     // csi_mode không hợp lệ: vẫn phải đi qua một chu kỳ busy.
                     // Bản đầu báo done+err ngay trong ST_IDLE và bị csi_checker
                     // bắt: vi phạm INV-1 (done khi không busy) và INV-4 (busy
                     // không lên trong 2 chu kỳ sau start). Sửa IP cho đúng hợp
                     // đồng, KHÔNG nới hợp đồng.
                     ST_ERR      = 3'd6;

    reg  [2:0]  state;
    reg  [5:0]  round;
    reg  [3:0]  word_idx;
    reg  [1:0]  byte_idx;
    reg  [23:0] wbuf;             // 3 byte đã gom, byte thứ 4 lấy thẳng từ pb_data
    reg         first_block;
    reg         stream_ended;
    reg         result_valid_r;
    reg         pb_ready_r;

    //------------------------------------------------------------------
    // Khối đệm
    //------------------------------------------------------------------
    wire       mode_ok   = (csi_mode == MODE_HASH) || (csi_mode == MODE_CONT);
    wire       pad_start = csi_start && (state == ST_IDLE) && mode_ok;

    wire [7:0] pb_data;
    wire       pb_valid, pb_last;

    sha256_pad u_pad (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (pad_start),
        .sin_data  (sin_data),
        .sin_valid (sin_valid),
        .sin_last  (sin_last),
        .sin_ready (sin_ready),
        .pb_data   (pb_data),
        .pb_valid  (pb_valid),
        .pb_last   (pb_last),
        .pb_ready  (pb_ready_r)
    );

    wire        pb_take   = pb_valid && pb_ready_r;
    wire        word_done = pb_take && (byte_idx == 2'd3);
    wire [31:0] word_now  = {wbuf, pb_data};

    //------------------------------------------------------------------
    // Lập lịch thông điệp + hàm nén — điều khiển TỔ HỢP
    //------------------------------------------------------------------
    wire        sch_load = (state == ST_FILL) && word_done;
    wire        sch_step = (state == ST_COMPRESS);
    wire [31:0] w_t;

    sha256_sched u_sched (
        .clk       (clk),
        .rst_n     (rst_n),
        .load      (sch_load),
        .load_word (word_now),
        .step      (sch_step),
        .w_out     (w_t)
    );

    wire [31:0]  k_t;
    sha256_k u_k (.t(round), .k(k_t));

    wire         cmp_init  = (state == ST_CINIT);
    wire         cmp_step  = (state == ST_COMPRESS);
    wire         cmp_final = (state == ST_ACCUM);
    wire [255:0] h_out;
    wire [255:0] cmp_h_in  = first_block ? SHA256_IV : h_out;

    sha256_compress u_cmp (
        .clk      (clk),
        .rst_n    (rst_n),
        .init     (cmp_init),
        .h_in     (cmp_h_in),
        .step     (cmp_step),
        .finalize (cmp_final),
        .w_t      (w_t),
        .k_t      (k_t),
        .h_out    (h_out)
    );

    //------------------------------------------------------------------
    // Cổng ra theo hợp đồng CSI
    //------------------------------------------------------------------
    assign csi_busy         = (state != ST_IDLE);
    assign sout_data        = {CSI_DATA_W{1'b0}};   // IP này không sinh dòng ra
    assign sout_valid       = 1'b0;
    assign sout_last        = 1'b0;
    assign csi_result       = h_out;
    assign csi_result_valid = result_valid_r && !csi_err;   // INV-5

    //------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_IDLE;
            round          <= 6'd0;
            word_idx       <= 4'd0;
            byte_idx       <= 2'd0;
            wbuf           <= 24'd0;
            first_block    <= 1'b1;
            stream_ended   <= 1'b0;
            result_valid_r <= 1'b0;
            pb_ready_r     <= 1'b0;
            csi_done       <= 1'b0;
            csi_err        <= 1'b0;
        end else begin
            csi_done <= 1'b0;      // INV-2: done rộng đúng 1 chu kỳ

            case (state)

                //--------------------------------------------------------
                ST_IDLE: begin
                    pb_ready_r <= 1'b0;
                    // REQ-F-07 / INV-3: chỉ nhận start khi đang rảnh; khi bận
                    // thì nhánh này không chạy nên start bị bỏ qua tự nhiên.
                    if (csi_start) begin
                        if (mode_ok) begin
                            csi_err        <= 1'b0;
                            result_valid_r <= 1'b0;
                            first_block    <= (csi_mode == MODE_HASH);
                            stream_ended   <= 1'b0;
                            word_idx       <= 4'd0;
                            byte_idx       <= 2'd0;
                            round          <= 6'd0;
                            pb_ready_r     <= 1'b1;
                            state          <= ST_FILL;
                        end else begin
                            result_valid_r <= 1'b0;
                            state          <= ST_ERR;
                        end
                    end
                end

                //--------------------------------------------------------
                ST_FILL: begin
                    if (pb_take) begin
                        wbuf <= {wbuf[15:0], pb_data};
                        if (pb_last)
                            stream_ended <= 1'b1;

                        if (byte_idx == 2'd3) begin
                            byte_idx <= 2'd0;
                            if (word_idx == 4'd15) begin
                                word_idx   <= 4'd0;
                                pb_ready_r <= 1'b0;    // ngừng nhận, đi nén
                                round      <= 6'd0;
                                state      <= ST_CINIT;
                            end else begin
                                word_idx <= word_idx + 4'd1;
                            end
                        end else begin
                            byte_idx <= byte_idx + 2'd1;
                        end
                    end
                end

                //--------------------------------------------------------
                ST_CINIT: begin
                    // cmp_init tổ hợp đang lên; a..h và H nạp ở cuối chu kỳ này
                    state <= ST_COMPRESS;
                end

                //--------------------------------------------------------
                ST_COMPRESS: begin
                    // round, w_t, k_t, step đều thuộc cùng một vòng
                    if (round == 6'd63)
                        state <= ST_ACCUM;
                    else
                        round <= round + 6'd1;
                end

                //--------------------------------------------------------
                ST_ACCUM: begin
                    first_block <= 1'b0;
                    if (stream_ended) begin
                        state <= ST_FINISH;
                    end else begin
                        pb_ready_r <= 1'b1;
                        state      <= ST_FILL;
                    end
                end

                //--------------------------------------------------------
                ST_FINISH: begin
                    // cmp_final đã chạy ở chu kỳ trước -> h_out đã hợp lệ
                    csi_done       <= 1'b1;         // REQ-F-14: xung 1 chu kỳ
                    result_valid_r <= 1'b1;
                    state          <= ST_IDLE;
                end

                //--------------------------------------------------------
                ST_ERR: begin
                    // csi_busy đã lên ở chu kỳ này (state != ST_IDLE), nên
                    // done phát ra ở đây là hợp lệ theo INV-1.
                    csi_err        <= 1'b1;
                    csi_done       <= 1'b1;
                    result_valid_r <= 1'b0;         // INV-5
                    state          <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
