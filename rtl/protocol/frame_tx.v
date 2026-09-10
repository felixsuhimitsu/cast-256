//=============================================================================
// File   : rtl/protocol/frame_tx.v
// Mục đích: Đóng khung trả lời và đẩy từng byte sang uart_tx.
// REQ    : REQ-F-20
// Tác giả : Đội Hủ Tiếu · Ngày: 2026-09-09
//=============================================================================
// Khung phát ra có cùng cấu trúc với khung nhận:
//   A5 5A | LEN(2) | IV(16) | CIPHERTEXT(LEN) | DIGEST(32)
// trong đó DIGEST = SHA-256(LEN‖IV‖CIPHERTEXT), để host tự kiểm được khung về.
//
// Module này có cổng đọc bộ đệm RIÊNG. Ở tầng trên, địa chỉ đọc được chọn giữa
// session_fsm và module này — chúng không bao giờ chạy cùng lúc (session_fsm ở
// trạng thái ST_TX trong suốt thời gian phát). Bộ chọn nằm ở top và được ghi rõ
// ở đó, thay vì thêm cổng đọc thứ hai cho bộ đệm (sẽ tốn gấp đôi BSRAM).
//
// Đọc bộ đệm trễ một chu kỳ nên mỗi byte ciphertext đi qua hai trạng thái.
//=============================================================================

`timescale 1ns / 1ps

module frame_tx #(
    parameter AW = 9
) (
    input  wire          clk,
    input  wire          rst_n,

    input  wire          start,
    input  wire [15:0]   len,
    input  wire [127:0]  iv,
    input  wire [255:0]  digest,
    output reg           done,          // xung 1 chu kỳ

    // cổng đọc bộ đệm. Địa chỉ là TỔ HỢP: bộ nhớ đã trễ một chu kỳ, nếu địa
    // chỉ cũng qua thanh ghi thì trạng thái chờ một chu kỳ là không đủ.
    output wire [AW-1:0] buf_raddr,
    input  wire [7:0]    buf_rdata,

    // sang uart_tx
    output reg  [7:0]    tx_data,
    output reg           tx_valid,
    input  wire          tx_ready,

    output wire          active
);

    localparam [2:0] ST_IDLE = 3'd0,
                     ST_HDR  = 3'd1,   // A5 5A LEN_HI LEN_LO IV[0..15]
                     ST_PADR = 3'd2,
                     ST_PDAT = 3'd3,
                     ST_DIG  = 3'd4;

    reg [2:0]   state;
    reg [4:0]   hidx;        // 0..19 : preamble(2) + len(2) + iv(16)
    reg [AW:0]  pidx;
    reg [5:0]   didx;

    assign active    = (state != ST_IDLE);
    assign buf_raddr = pidx[AW-1:0];

    // Byte thứ hidx của phần đầu khung
    reg [7:0] hdr_byte;
    always @(*) begin
        case (hidx)
            5'd0:    hdr_byte = 8'hA5;
            5'd1:    hdr_byte = 8'h5A;
            5'd2:    hdr_byte = len[15:8];
            5'd3:    hdr_byte = len[7:0];
            default: hdr_byte = iv[127 - 8*(hidx - 4) -: 8];
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= ST_IDLE;
            hidx      <= 5'd0;
            pidx      <= {(AW+1){1'b0}};
            didx      <= 6'd0;
            tx_data   <= 8'd0;
            tx_valid  <= 1'b0;
            done      <= 1'b0;
        end else begin
            done <= 1'b0;

            case (state)

                ST_IDLE: begin
                    tx_valid <= 1'b0;
                    if (start) begin
                        hidx  <= 5'd0;
                        pidx  <= {(AW+1){1'b0}};
                        didx  <= 6'd0;
                        state <= ST_HDR;
                    end
                end

                //--------------------------------------------------------
                ST_HDR: begin
                    tx_data  <= hdr_byte;
                    tx_valid <= 1'b1;
                    if (tx_ready && tx_valid) begin
                        tx_valid <= 1'b0;
                        if (hidx == 5'd19)
                            state <= ST_PADR;
                        else
                            hidx <= hidx + 5'd1;
                    end
                end

                //--------------------------------------------------------
                // Một chu kỳ chờ bộ nhớ trả dữ liệu về
                ST_PADR: state <= ST_PDAT;

                ST_PDAT: begin
                    tx_data  <= buf_rdata;
                    tx_valid <= 1'b1;
                    if (tx_ready && tx_valid) begin
                        tx_valid <= 1'b0;
                        if (pidx == len - 1)
                            state <= ST_DIG;
                        else begin
                            pidx  <= pidx + 1;
                            state <= ST_PADR;
                        end
                    end
                end

                //--------------------------------------------------------
                ST_DIG: begin
                    tx_data  <= digest[255 - 8*didx -: 8];
                    tx_valid <= 1'b1;
                    if (tx_ready && tx_valid) begin
                        tx_valid <= 1'b0;
                        if (didx == 6'd31) begin
                            done  <= 1'b1;
                            state <= ST_IDLE;
                        end else begin
                            didx <= didx + 6'd1;
                        end
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
