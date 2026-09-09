//=============================================================================
// File   : rtl/io/uart_rx.v
// Mục đích: Bộ thu UART 8-N-1, lấy mẫu bằng biểu quyết 3 điểm, nhả về IDLE
//           ngay sau khi lấy mẫu bit stop.
// REQ    : REQ-I-03, REQ-I-04, REQ-I-05
// ADR    : ADR-0005
// Rủi ro : RSK-02 — đây là module đã từng làm hỏng cả thiết kế trước
// Tác giả : Đội Hủ Tiếu · Ngày: 2026-09-09
//=============================================================================
// BÀI TOÁN GỐC
// 27_000_000 / 115_200 = 234.375 chu kỳ/bit. Bộ chia nguyên chỉ dùng được 234.
// Một khung 10 bit dài 2343.75 chu kỳ thật. Nếu bộ thu tiêu tốn trọn 10*234 =
// 2340 chu kỳ rồi mới về IDLE thì chỉ còn 3.75 chu kỳ để bắt sườn start kế
// tiếp. Với luồng byte liên tục, sai số tích lũy và sau ~96 byte thì mất đồng
// bộ — đã đo được: 256 byte gửi liên tục mất 159 byte.
//
// CÁCH XỬ LÝ (ADR-0005)
// Ở trạng thái STOP, ngay sau khi lấy mẫu bit stop tại chu kỳ 125 của bit, FSM
// về IDLE luôn thay vì chờ hết 234 chu kỳ. Dự phòng bắt sườn start tăng từ
// 3.75 lên ~108 chu kỳ.
//
// ĐÁNH ĐỔI: bộ thu "dễ dãi" hơn với khung méo — nếu bit stop sai, nó về IDLE
// sớm và có thể hiểu nhầm bit dữ liệu kế tiếp là start bit. Chấp nhận được vì
// đường truyền là dây ngắn và có digest chặn ở tầng trên.
//
// LẤY MẪU (REQ-I-04)
// Ba mẫu tại chu kỳ 109 / 117 / 125 trong bit (giữa bit = 117), cách nhau ±8
// chu kỳ ≈ ±0.30 µs. Lấy đa số 2/3. Cách này loại được xung nhiễu đơn lẻ mà
// vẫn nằm gọn trong vùng ổn định của bit.
//=============================================================================

`timescale 1ns / 1ps

module uart_rx #(
    parameter CLK_HZ = 27_000_000,
    parameter BAUD   = 115_200
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,           // chân vật lý, BẤT ĐỒNG BỘ

    output reg  [7:0] rx_data,
    output reg        rx_valid,     // xung 1 chu kỳ
    output reg        rx_frame_err  // xung 1 chu kỳ: bit stop sai
);

    localparam integer DIV  = CLK_HZ / BAUD;   // 234
    localparam integer MID  = DIV / 2;         // 117
    localparam integer S0   = MID - 8;         // 109
    localparam integer S1   = MID;             // 117
    localparam integer S2   = MID + 8;         // 125
    // Quyết định TRỄ MỘT CHU KỲ sau mẫu cuối. Nếu dùng `vote` ngay tại S2 thì
    // samples[2] mới đang được gán (nonblocking) và vote sẽ dùng giá trị CŨ —
    // lỗi này đã bị TC-301 bắt được: nhiễu trên bit giá trị 0 lọt qua ở 2/8 bit.
    localparam integer SDEC = S2 + 1;          // 126

    localparam [1:0] ST_IDLE  = 2'd0,
                     ST_START = 2'd1,
                     ST_DATA  = 2'd2,
                     ST_STOP  = 2'd3;

    //------------------------------------------------------------------
    // Đồng bộ hóa đầu vào — CDC DUY NHẤT của toàn thiết kế.
    // Hai tầng DFF trước khi dùng, theo ARCHITECTURE §5.
    //------------------------------------------------------------------
    reg rx_meta, rx_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
        end
    end

    //------------------------------------------------------------------
    // FSM
    //------------------------------------------------------------------
    reg [1:0]  state;
    reg [8:0]  cnt;          // vị trí trong bit hiện tại, 0..233
    reg [2:0]  bit_idx;
    reg [7:0]  shreg;
    reg [2:0]  samples;      // 3 mẫu đã lấy trong bit này

    wire vote = (samples[0] & samples[1]) |
                (samples[0] & samples[2]) |
                (samples[1] & samples[2]);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            cnt          <= 9'd0;
            bit_idx      <= 3'd0;
            shreg        <= 8'd0;
            samples      <= 3'b111;
            rx_data      <= 8'd0;
            rx_valid     <= 1'b0;
            rx_frame_err <= 1'b0;
        end else begin
            // mặc định: các cổng xung chỉ rộng 1 chu kỳ
            rx_valid     <= 1'b0;
            rx_frame_err <= 1'b0;

            // Thu thập 3 mẫu ở mọi trạng thái đang đếm bit
            if (state != ST_IDLE) begin
                if (cnt == S0[8:0]) samples[0] <= rx_sync;
                if (cnt == S1[8:0]) samples[1] <= rx_sync;
                if (cnt == S2[8:0]) samples[2] <= rx_sync;
            end

            case (state)

                //--------------------------------------------------------
                ST_IDLE: begin
                    // Sườn xuống = có thể là start bit
                    if (rx_sync == 1'b0) begin
                        state   <= ST_START;
                        cnt     <= 9'd0;
                        samples <= 3'b111;
                    end
                end

                //--------------------------------------------------------
                ST_START: begin
                    if (cnt == SDEC[8:0]) begin
                        // Xác nhận start bit thật sự là 0. Nếu không, đây là
                        // xung nhiễu — bỏ qua, quay về IDLE ngay để không mất
                        // start bit thật đến sau.
                        if (vote == 1'b1) begin
                            state <= ST_IDLE;
                            cnt   <= 9'd0;
                        end else begin
                            cnt <= cnt + 1'b1;
                        end
                    end else if (cnt == DIV[8:0] - 1'b1) begin
                        state   <= ST_DATA;
                        cnt     <= 9'd0;
                        bit_idx <= 3'd0;
                        samples <= 3'b111;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                //--------------------------------------------------------
                ST_DATA: begin
                    if (cnt == SDEC[8:0]) begin
                        // LSB first: dịch phải, mẫu mới vào bit 7
                        shreg <= {vote, shreg[7:1]};
                        cnt   <= cnt + 1'b1;
                    end else if (cnt == DIV[8:0] - 1'b1) begin
                        cnt     <= 9'd0;
                        samples <= 3'b111;
                        if (bit_idx == 3'd7)
                            state <= ST_STOP;
                        else
                            bit_idx <= bit_idx + 1'b1;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                //--------------------------------------------------------
                ST_STOP: begin
                    if (cnt == SDEC[8:0]) begin
                        if (vote == 1'b1) begin
                            rx_data  <= shreg;
                            rx_valid <= 1'b1;
                        end else begin
                            rx_frame_err <= 1'b1;
                        end
                        // ADR-0005: về IDLE NGAY, không chờ hết chu kỳ bit.
                        // Đây là một dòng code duy nhất, và nó là khác biệt
                        // giữa "mất 159/256 byte" và "mất 0 byte".
                        state <= ST_IDLE;
                        cnt   <= 9'd0;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
