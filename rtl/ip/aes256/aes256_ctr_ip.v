//=============================================================================
// File   : rtl/ip/aes256/aes256_ctr_ip.v
// Mục đích: Đỉnh IP AES-256-CTR — theo hợp đồng giao diện CSI v1.0.
// REQ    : REQ-F-02, REQ-F-03, REQ-F-06, REQ-F-07, REQ-I-01, REQ-I-02
// ADR    : ADR-0002, ADR-0006
// Tác giả : Đội Hủ Tiếu · Ngày: 2026-09-09
//=============================================================================
// ĐÂY LÀ ĐIỂM TÍCH HỢP THỨ HAI của đề tài. Cùng hình dạng cổng với sha256_ip,
// nên tầng fabric/ đối xử với hai IP như nhau.
//
// csi_mode:
//   8'h00 AES_LOAD_KEY — nạp 32 byte khóa qua sin_*, chạy key schedule
//   8'h01 AES_LOAD_IV  — nạp 16 byte IV làm giá trị đầu của bộ đếm
//   8'h02 AES_CRYPT    — sout = sin XOR keystream, cho cả hai chiều (REQ-F-06)
//   khác  — csi_err = 1
//
// Chế độ CTR (NIST SP 800-38A §6.5):
//   keystream_block[j] = AES-256-Encrypt(counter + j)
//   ciphertext = plaintext XOR keystream
// Vì phép XOR đối xứng nên MỘT chế độ dùng cho cả mã hóa và giải mã, và thiết
// kế không cần hàm AES nghịch.
//
// Bộ đếm 128 bit, tăng theo big-endian, tràn quấn vòng tự nhiên (REQ-F-03).
//
// Không có kết quả dạng thanh ghi: csi_result buộc dây 0 theo §2 hợp đồng.
//=============================================================================

`timescale 1ns / 1ps

module aes256_ctr_ip #(
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
    output reg                     sout_valid,
    output reg                     sout_last,
    input  wire                    sout_ready,

    output wire [CSI_RES_W-1:0]    csi_result,
    output wire                    csi_result_valid
);

    localparam [7:0] MODE_KEY   = 8'h00,
                     MODE_IV    = 8'h01,
                     MODE_CRYPT = 8'h02;

    localparam [3:0] ST_IDLE   = 4'd0,
                     ST_RXKEY  = 4'd1,   // nhận 32 byte khóa
                     ST_KEXP   = 4'd2,   // chạy key schedule
                     ST_RXIV   = 4'd3,   // nhận 16 byte IV
                     ST_GEN    = 4'd4,   // mã hóa bộ đếm -> keystream
                     ST_XOR    = 4'd5,   // XOR dòng byte với keystream
                     ST_EMIT   = 4'd6,   // giữ byte ra cho tới khi sout_ready
                     ST_FINISH = 4'd7,
                     ST_ERR    = 4'd8;

    reg  [3:0]   state;
    reg  [255:0] key_r;
    reg  [127:0] ctr;
    reg  [127:0] ks;             // keystream block hiện tại
    reg  [5:0]   rxcnt;          // đếm byte khi nạp khóa/IV
    reg  [3:0]   ks_idx;         // 0..15, byte thứ mấy trong keystream
    reg  [7:0]   out_byte;
    reg          last_seen;

    //------------------------------------------------------------------
    wire         key_start = (state == ST_RXKEY) && (rxcnt == 6'd31) &&
                             sin_valid && sin_ready;
    wire         key_done_w;
    reg          enc_start;
    wire         enc_done_w;
    wire [127:0] block_out;
    wire         cipher_busy;

    aes256_cipher u_cipher (
        .clk       (clk),
        .rst_n     (rst_n),
        .key_start (key_start),
        .key       ({key_r[247:0], sin_data}),   // byte thứ 32 lấy thẳng từ dòng
        .key_done  (key_done_w),
        .enc_start (enc_start),
        .block_in  (ctr),
        .block_out (block_out),
        .enc_done  (enc_done_w),
        .busy      (cipher_busy)
    );

    //------------------------------------------------------------------
    // Cổng ra theo hợp đồng CSI
    //------------------------------------------------------------------
    assign csi_busy         = (state != ST_IDLE);
    assign sin_ready        = (state == ST_RXKEY) || (state == ST_RXIV) ||
                              (state == ST_XOR);
    assign sout_data        = out_byte;
    assign csi_result       = {CSI_RES_W{1'b0}};   // IP này không có kết quả thanh ghi
    assign csi_result_valid = 1'b0;

    wire mode_ok = (csi_mode == MODE_KEY) || (csi_mode == MODE_IV) ||
                   (csi_mode == MODE_CRYPT);

    //------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= ST_IDLE;
            key_r      <= 256'd0;
            ctr        <= 128'd0;
            ks         <= 128'd0;
            rxcnt      <= 6'd0;
            ks_idx     <= 4'd0;
            out_byte   <= 8'd0;
            last_seen  <= 1'b0;
            csi_done   <= 1'b0;
            csi_err    <= 1'b0;
            sout_valid <= 1'b0;
            sout_last  <= 1'b0;
            enc_start  <= 1'b0;
        end else begin
            csi_done  <= 1'b0;      // INV-2
            enc_start <= 1'b0;

            case (state)

                //--------------------------------------------------------
                ST_IDLE: begin
                    sout_valid <= 1'b0;
                    sout_last  <= 1'b0;
                    if (csi_start) begin
                        csi_err   <= 1'b0;
                        rxcnt     <= 6'd0;
                        last_seen <= 1'b0;
                        case (csi_mode)
                            MODE_KEY:   state <= ST_RXKEY;
                            MODE_IV:    state <= ST_RXIV;
                            MODE_CRYPT: begin
                                ks_idx    <= 4'd0;
                                enc_start <= 1'b1;
                                state     <= ST_GEN;
                            end
                            default:    state <= ST_ERR;
                        endcase
                    end
                end

                //--------------------------------------------------------
                ST_RXKEY: begin
                    if (sin_valid) begin
                        key_r <= {key_r[247:0], sin_data};
                        if (rxcnt == 6'd31) begin
                            // key_start (tổ hợp) đang lên ở chu kỳ này
                            state <= ST_KEXP;
                        end else begin
                            rxcnt <= rxcnt + 6'd1;
                        end
                    end
                end

                ST_KEXP: begin
                    if (key_done_w)
                        state <= ST_FINISH;
                end

                //--------------------------------------------------------
                ST_RXIV: begin
                    if (sin_valid) begin
                        ctr <= {ctr[119:0], sin_data};
                        if (rxcnt == 6'd15)
                            state <= ST_FINISH;
                        else
                            rxcnt <= rxcnt + 6'd1;
                    end
                end

                //--------------------------------------------------------
                // Sinh một khối keystream = AES(ctr)
                //--------------------------------------------------------
                ST_GEN: begin
                    if (enc_done_w) begin
                        ks     <= block_out;
                        ks_idx <= 4'd0;
                        state  <= ST_XOR;
                    end
                end

                //--------------------------------------------------------
                // XOR từng byte. sin_ready lên ở đây; mỗi byte nhận vào sinh
                // đúng một byte ra, giữ ở ST_EMIT cho tới khi sout_ready.
                //--------------------------------------------------------
                ST_XOR: begin
                    if (sin_valid) begin
                        out_byte   <= sin_data ^ ks[127 - 8*ks_idx -: 8];
                        sout_valid <= 1'b1;
                        sout_last  <= sin_last;
                        last_seen  <= sin_last;
                        state      <= ST_EMIT;
                    end
                end

                //--------------------------------------------------------
                // H2: giữ nguyên valid/data/last cho tới khi thấy ready
                //--------------------------------------------------------
                ST_EMIT: begin
                    if (sout_ready) begin
                        sout_valid <= 1'b0;
                        sout_last  <= 1'b0;
                        if (last_seen) begin
                            state <= ST_FINISH;
                        end else if (ks_idx == 4'd15) begin
                            // Hết khối keystream: tăng bộ đếm và sinh khối mới.
                            // REQ-F-03: tràn quấn vòng tự nhiên vì cộng 128 bit.
                            ctr       <= ctr + 128'd1;
                            ks_idx    <= 4'd0;
                            enc_start <= 1'b1;
                            state     <= ST_GEN;
                        end else begin
                            ks_idx <= ks_idx + 4'd1;
                            state  <= ST_XOR;
                        end
                    end
                end

                //--------------------------------------------------------
                ST_FINISH: begin
                    csi_done <= 1'b1;
                    csi_err  <= 1'b0;
                    state    <= ST_IDLE;
                end

                ST_ERR: begin
                    // csi_busy đã lên ở chu kỳ này nên done hợp lệ (INV-1)
                    csi_err  <= 1'b1;
                    csi_done <= 1'b1;
                    state    <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
