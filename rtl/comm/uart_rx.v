`timescale 1ns/1ps

// 115,200 Baud UART Receiver for 27.0 MHz Clock Domain
// Clock Divisor: 27.0 MHz / 115,200 = 234 (cycles 0 to 233)
// 3-Sample Majority Voting at mid-bit period (cycles 116, 117, 118)
module uart_rx (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx_pin,
    output reg  [7:0] rx_data,
    output reg        rx_valid,
    output reg        rx_frame_err
);

    localparam CLKS_PER_BIT = 234;

    localparam STATE_IDLE  = 2'd0;
    localparam STATE_START = 2'd1;
    localparam STATE_DATA  = 2'd2;
    localparam STATE_STOP  = 2'd3;

    reg [1:0] state;
    reg [7:0] clk_cnt;
    reg [2:0] bit_idx;
    reg [7:0] rx_shift;

    // 2-Stage Metastability Synchronizer
    reg rx_sync0, rx_sync1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync0 <= 1'b1;
            rx_sync1 <= 1'b1;
        end else begin
            rx_sync0 <= rx_pin;
            rx_sync1 <= rx_sync0;
        end
    end

    // Mid-bit 3-sample storage
    reg s0, s1, s2;
    wire vote = (s0 & s1) | (s0 & s2) | (s1 & s2);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= STATE_IDLE;
            clk_cnt      <= 8'd0;
            bit_idx      <= 3'd0;
            rx_shift     <= 8'd0;
            rx_data      <= 8'd0;
            rx_valid     <= 1'b0;
            rx_frame_err <= 1'b0;
            s0           <= 1'b1;
            s1           <= 1'b1;
            s2           <= 1'b1;
        end else begin
            rx_valid     <= 1'b0;
            rx_frame_err <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    clk_cnt <= 8'd0;
                    bit_idx <= 3'd0;
                    if (!rx_sync1) begin // Falling edge detection on Start Bit
                        state <= STATE_START;
                    end
                end

                STATE_START: begin
                    if (clk_cnt == 8'd116) s0 <= rx_sync1;
                    if (clk_cnt == 8'd117) s1 <= rx_sync1;
                    if (clk_cnt == 8'd118) s2 <= rx_sync1;

                    if (clk_cnt == 8'd119) begin
                        if (vote != 1'b0) begin
                            // False start bit / noise spike
                            state <= STATE_IDLE;
                        end
                    end

                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 8'd0;
                        state   <= STATE_DATA;
                    end else begin
                        clk_cnt <= clk_cnt + 8'd1;
                    end
                end

                STATE_DATA: begin
                    if (clk_cnt == 8'd116) s0 <= rx_sync1;
                    if (clk_cnt == 8'd117) s1 <= rx_sync1;
                    if (clk_cnt == 8'd118) s2 <= rx_sync1;

                    if (clk_cnt == 8'd119) begin
                        rx_shift[bit_idx] <= vote;
                    end

                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 8'd0;
                        if (bit_idx == 3'd7) begin
                            bit_idx <= 3'd0;
                            state   <= STATE_STOP;
                        end else begin
                            bit_idx <= bit_idx + 3'd1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 8'd1;
                    end
                end

                STATE_STOP: begin
                    if (clk_cnt == 8'd116) s0 <= rx_sync1;
                    if (clk_cnt == 8'd117) s1 <= rx_sync1;
                    if (clk_cnt == 8'd118) s2 <= rx_sync1;

                    if (clk_cnt == 8'd119) begin
                        if (vote == 1'b1) begin
                            rx_data  <= rx_shift;
                            rx_valid <= 1'b1;
                        end else begin
                            rx_frame_err <= 1'b1;
                        end
                    end

                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 8'd0;
                        state   <= STATE_IDLE;
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
