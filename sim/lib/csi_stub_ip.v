//=============================================================================
// File   : sim/lib/csi_stub_ip.v
// Mục đích: IP giả lập tuân hợp đồng CSI, dùng để kiểm tầng fabric ĐỘC LẬP với
//           IP thật. Chỉ dùng trong mô phỏng.
// REQ    : REQ-I-01, REQ-I-02
// Tác giả : Đội Hủ Tiếu · Ngày: 2026-09-09
//=============================================================================
// Vì sao cần IP giả lập thay vì cắm thẳng AES/SHA thật vào testbench fabric:
// nếu dùng IP thật, một lỗi ở fabric và một lỗi ở IP sẽ trộn lẫn, và khi
// testbench fail thì không biết đổ cho bên nào. IP giả lập có hành vi đơn giản
// tới mức chắc chắn đúng, nên mọi lỗi còn lại đều thuộc về fabric.
//
// Hành vi: nhận LATENCY chu kỳ mỗi byte, xuất ra byte đã XOR với XOR_CONST
// (nếu HAS_STREAM_OUT), và trả về csi_result = SIG lặp lại (nếu HAS_RESULT).
// Tham số hóa để một module giả lập được cả kiểu AES (có dòng ra, không kết
// quả) lẫn kiểu SHA (không dòng ra, có kết quả).
//=============================================================================

`timescale 1ns / 1ps

module csi_stub_ip #(
    parameter DW              = 8,
    parameter RW              = 256,
    parameter [7:0] MODE_OK   = 8'h00,   // mode hợp lệ duy nhất
    parameter [7:0] XOR_CONST = 8'h5A,
    parameter HAS_STREAM_OUT  = 1,
    parameter HAS_RESULT      = 0,
    parameter [31:0] SIG      = 32'hDEADBEEF,
    parameter LATENCY         = 2        // chu kỳ xử lý mỗi byte
) (
    input  wire            clk,
    input  wire            rst_n,

    input  wire            csi_start,
    input  wire [7:0]      csi_mode,
    output wire            csi_busy,
    output reg             csi_done,
    output reg             csi_err,

    input  wire [DW-1:0]   sin_data,
    input  wire            sin_valid,
    input  wire            sin_last,
    output wire            sin_ready,

    output reg  [DW-1:0]   sout_data,
    output reg             sout_valid,
    output reg             sout_last,
    input  wire            sout_ready,

    output wire [RW-1:0]   csi_result,
    output reg             csi_result_valid
);

    localparam [2:0] ST_IDLE = 3'd0,
                     ST_RX   = 3'd1,
                     ST_WORK = 3'd2,
                     ST_TX   = 3'd3,
                     ST_FIN  = 3'd4,
                     ST_ERR  = 3'd5;

    reg [2:0]  state;
    reg [7:0]  work;
    reg [DW-1:0] hold;
    reg        hold_last;
    reg [31:0] acc;

    assign csi_busy   = (state != ST_IDLE);
    assign sin_ready  = (state == ST_RX);
    assign csi_result = {8{acc}};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= ST_IDLE;
            work             <= 8'd0;
            hold             <= {DW{1'b0}};
            hold_last        <= 1'b0;
            acc              <= 32'd0;
            csi_done         <= 1'b0;
            csi_err          <= 1'b0;
            sout_data        <= {DW{1'b0}};
            sout_valid       <= 1'b0;
            sout_last        <= 1'b0;
            csi_result_valid <= 1'b0;
        end else begin
            csi_done <= 1'b0;

            case (state)

                ST_IDLE: begin
                    sout_valid <= 1'b0;
                    sout_last  <= 1'b0;
                    if (csi_start) begin
                        csi_err          <= 1'b0;
                        csi_result_valid <= 1'b0;
                        acc              <= SIG;
                        if (csi_mode == MODE_OK)
                            state <= ST_RX;
                        else
                            state <= ST_ERR;
                    end
                end

                ST_RX: begin
                    if (sin_valid) begin
                        hold      <= sin_data;
                        hold_last <= sin_last;
                        acc       <= {acc[23:0], acc[31:24]} ^ {24'd0, sin_data};
                        work      <= LATENCY[7:0];
                        state     <= ST_WORK;
                    end
                end

                ST_WORK: begin
                    if (work == 8'd0) begin
                        if (HAS_STREAM_OUT) begin
                            sout_data  <= hold ^ XOR_CONST[DW-1:0];
                            sout_valid <= 1'b1;
                            sout_last  <= hold_last;
                            state      <= ST_TX;
                        end else begin
                            state <= hold_last ? ST_FIN : ST_RX;
                        end
                    end else begin
                        work <= work - 8'd1;
                    end
                end

                // H2: giữ nguyên valid/data/last cho tới khi thấy ready
                ST_TX: begin
                    if (sout_ready) begin
                        sout_valid <= 1'b0;
                        sout_last  <= 1'b0;
                        state      <= hold_last ? ST_FIN : ST_RX;
                    end
                end

                ST_FIN: begin
                    csi_done         <= 1'b1;
                    csi_result_valid <= HAS_RESULT ? 1'b1 : 1'b0;
                    state            <= ST_IDLE;
                end

                // Đi qua một chu kỳ busy rồi mới báo lỗi (INV-1, INV-4)
                ST_ERR: begin
                    csi_err          <= 1'b1;
                    csi_done         <= 1'b1;
                    csi_result_valid <= 1'b0;
                    state            <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
