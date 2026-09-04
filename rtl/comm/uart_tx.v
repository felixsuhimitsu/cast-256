`timescale 1ns/1ps

// 115,200 Baud UART Transmitter for 27.0 MHz Clock Domain (8-N-1)
// Clock Divisor: 27.0 MHz / 115,200 = 234 (cycles 0 to 233)
module uart_tx (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] tx_data,
    input  wire       tx_start,
    output reg        tx_pin,
    output wire       tx_busy
);

    localparam CLKS_PER_BIT = 234;

    localparam STATE_IDLE = 1'b0;
    localparam STATE_SEND = 1'b1;

    reg state;
    reg [7:0] clk_cnt;
    reg [3:0] bit_idx;
    reg [9:0] tx_shift;

    assign tx_busy = (state != STATE_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= STATE_IDLE;
            tx_pin   <= 1'b1;
            clk_cnt  <= 8'd0;
            bit_idx  <= 4'd0;
            tx_shift <= 10'h3ff;
        end else begin
            case (state)
                STATE_IDLE: begin
                    tx_pin  <= 1'b1;
                    clk_cnt <= 8'd0;
                    bit_idx <= 4'd0;
                    if (tx_start) begin
                        // Frame: Stop bit (1) | Data bits (MSB..LSB) | Start bit (0)
                        tx_shift <= {1'b1, tx_data, 1'b0};
                        tx_pin   <= 1'b0; // Start bit driven immediately
                        state    <= STATE_SEND;
                    end
                end

                STATE_SEND: begin
                    tx_pin <= tx_shift[bit_idx];
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 8'd0;
                        if (bit_idx == 4'd9) begin
                            state <= STATE_IDLE;
                        end else begin
                            bit_idx <= bit_idx + 4'd1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 8'd1;
                    end
                end

                default: begin
                    state <= STATE_IDLE;
                end
            endcase
        end
    end

endmodule
