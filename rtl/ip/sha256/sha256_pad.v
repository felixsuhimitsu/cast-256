//=============================================================================
// File   : rtl/ip/sha256/sha256_pad.v
// Mục đích: Đệm thông điệp theo FIPS 180-4 §5.1.1. Nhận dòng byte thông điệp,
//           phát ra dòng byte ĐÃ ĐỆM, độ dài luôn là bội số của 64 byte.
// REQ    : REQ-F-11, REQ-F-12
// Tác giả : Đội Hủ Tiếu · Ngày: 2026-09-09
//=============================================================================
// Quy tắc đệm: M ‖ 0x80 ‖ 0x00 * k ‖ len64_be
//   với k nhỏ nhất sao cho tổng độ dài ≡ 0 (mod 64), và len64 là ĐỘ DÀI BIT
//   của thông điệp gốc, big-endian.
//
// Hai độ dài dễ sai nhất là 55 và 56 byte:
//   55 byte -> 0x80 ở vị trí 55, còn đúng chỗ cho 8 byte độ dài -> 1 khối
//   56 byte -> 0x80 ở vị trí 56, KHÔNG còn chỗ -> phải tràn sang khối thứ hai
// TC-203 kiểm cả hai ca này cùng 63, 64, 119, 120.
//
// TUÂN QUY TẮC H2 CỦA HỢP ĐỒNG CSI: không bao giờ đặt `pb_valid` lên rồi rút
// lại. Vì vậy trạng thái kế tiếp được quyết định tại thời điểm byte được nhận,
// chứ không phải bằng cách nhìn vị trí rồi mới hạ valid.
//=============================================================================

`timescale 1ns / 1ps

module sha256_pad (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        start,        // xung: bắt đầu thông điệp mới

    // dòng byte thông điệp vào
    input  wire [7:0]  sin_data,
    input  wire        sin_valid,
    input  wire        sin_last,
    output wire        sin_ready,

    // dòng byte đã đệm ra
    output reg  [7:0]  pb_data,
    output reg         pb_valid,
    output wire        pb_last,      // byte cuối cùng của dòng đã đệm
    input  wire        pb_ready
);

    localparam [2:0] ST_IDLE  = 3'd0,
                     ST_PASS  = 3'd1,
                     ST_P80   = 3'd2,
                     ST_ZERO  = 3'd3,
                     ST_LEN   = 3'd4,
                     ST_DONE  = 3'd5;

    reg [2:0]  state;
    reg [5:0]  pos;          // vị trí byte trong khối 64, 0..63
    reg [63:0] bitlen;       // độ dài thông điệp tính bằng bit
    reg [2:0]  len_idx;      // 0..7, byte thứ mấy của trường độ dài

    wire accept = pb_valid && pb_ready;

    assign sin_ready = (state == ST_PASS) && pb_ready;
    assign pb_last   = (state == ST_LEN) && (len_idx == 3'd7);

    // Vị trí sau khi nhận byte hiện tại
    wire [5:0] pos_next = pos + 6'd1;

    always @(*) begin
        case (state)
            ST_PASS: begin pb_valid = sin_valid;  pb_data = sin_data;      end
            ST_P80:  begin pb_valid = 1'b1;       pb_data = 8'h80;         end
            ST_ZERO: begin pb_valid = 1'b1;       pb_data = 8'h00;         end
            ST_LEN:  begin
                pb_valid = 1'b1;
                case (len_idx)
                    3'd0: pb_data = bitlen[63:56];
                    3'd1: pb_data = bitlen[55:48];
                    3'd2: pb_data = bitlen[47:40];
                    3'd3: pb_data = bitlen[39:32];
                    3'd4: pb_data = bitlen[31:24];
                    3'd5: pb_data = bitlen[23:16];
                    3'd6: pb_data = bitlen[15:8];
                    3'd7: pb_data = bitlen[7:0];
                endcase
            end
            default: begin pb_valid = 1'b0;       pb_data = 8'h00;         end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= ST_IDLE;
            pos     <= 6'd0;
            bitlen  <= 64'd0;
            len_idx <= 3'd0;
        end else begin
            case (state)

                ST_IDLE: begin
                    if (start) begin
                        state   <= ST_PASS;
                        pos     <= 6'd0;
                        bitlen  <= 64'd0;
                        len_idx <= 3'd0;
                    end
                end

                //--------------------------------------------------------
                ST_PASS: begin
                    if (accept) begin
                        pos    <= pos_next;
                        bitlen <= bitlen + 64'd8;
                        if (sin_last) begin
                            // Quyết định NGAY tại đây để không phải hạ pb_valid
                            // ở chu kỳ sau (quy tắc H2).
                            state <= ST_P80;
                        end
                    end
                end

                //--------------------------------------------------------
                ST_P80: begin
                    if (accept) begin
                        pos <= pos_next;
                        // Nếu 0x80 vừa lấp đến vị trí 56 thì đi thẳng sang
                        // trường độ dài, không chèn byte 0 nào.
                        state <= (pos_next == 6'd56) ? ST_LEN : ST_ZERO;
                    end
                end

                //--------------------------------------------------------
                ST_ZERO: begin
                    if (accept) begin
                        pos <= pos_next;
                        // pos_next quấn vòng qua 0 khi hết khối — biểu thức
                        // dưới đây tự động xử lý ca độ dài 56 byte (phải tràn
                        // sang khối thứ hai) vì pos_next sẽ đi 57..63,0,1,...56.
                        if (pos_next == 6'd56)
                            state <= ST_LEN;
                    end
                end

                //--------------------------------------------------------
                ST_LEN: begin
                    if (accept) begin
                        pos <= pos_next;
                        if (len_idx == 3'd7)
                            state <= ST_DONE;
                        else
                            len_idx <= len_idx + 3'd1;
                    end
                end

                //--------------------------------------------------------
                ST_DONE: begin
                    if (start) begin
                        state   <= ST_PASS;
                        pos     <= 6'd0;
                        bitlen  <= 64'd0;
                        len_idx <= 3'd0;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
