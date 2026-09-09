//=============================================================================
// File   : rtl/io/uart_tx.v
// Mục đích: Bộ phát UART 8-N-1, bắt tay valid/ready.
// REQ    : REQ-I-03, REQ-I-02
// Tác giả : Đội Hủ Tiếu · Ngày: 2026-09-09
//=============================================================================
// Khung: START(0) - D0..D7 (LSB first) - STOP(1).
// `tx_ready` lên khi bộ phát rảnh; một byte được nhận khi tx_valid & tx_ready.
// Tuân quy tắc H3 của hợp đồng CSI: ready không phụ thuộc tổ hợp vào valid.
//=============================================================================

`timescale 1ns / 1ps

module uart_tx #(
    parameter CLK_HZ = 27_000_000,
    parameter BAUD   = 115_200
) (
    input  wire       clk,
    input  wire       rst_n,

    input  wire [7:0] tx_data,
    input  wire       tx_valid,
    output wire       tx_ready,

    output reg        tx            // chân vật lý
);

    localparam [1:0] ST_IDLE = 2'd0,
                     ST_SEND = 2'd1;

    reg        state;
    reg  [3:0] bit_idx;     // 0 = start, 1..8 = dữ liệu, 9 = stop
    reg  [7:0] shreg;
    reg        run;

    wire tick;

    baud_gen #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_baud (
        .clk    (clk),
        .rst_n  (rst_n),
        .enable (run),      // giữ bộ đếm ở 0 khi rảnh -> căn pha ngay khi bắt đầu
        .tick   (tick)
    );

    // H3: ready chỉ phụ thuộc trạng thái nội bộ, không nhìn tx_valid.
    assign tx_ready = (state == ST_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= ST_IDLE;
            bit_idx <= 4'd0;
            shreg   <= 8'd0;
            run     <= 1'b0;
            tx      <= 1'b1;        // đường nghỉ ở mức cao
        end else begin
            case (state)

                ST_IDLE: begin
                    tx  <= 1'b1;
                    run <= 1'b0;
                    if (tx_valid) begin
                        shreg   <= tx_data;
                        bit_idx <= 4'd0;
                        tx      <= 1'b0;    // start bit ngay lập tức
                        run     <= 1'b1;
                        state   <= ST_SEND;
                    end
                end

                ST_SEND: begin
                    if (tick) begin
                        if (bit_idx == 4'd8) begin
                            tx      <= 1'b1;            // stop bit
                            bit_idx <= bit_idx + 1'b1;
                        end else if (bit_idx == 4'd9) begin
                            // stop bit đã phát đủ một chu kỳ bit -> rảnh
                            state <= ST_IDLE;
                            run   <= 1'b0;
                            tx    <= 1'b1;
                        end else begin
                            tx      <= shreg[0];
                            shreg   <= {1'b0, shreg[7:1]};
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
