//=============================================================================
// File   : rtl/protocol/frame_rx.v
// Mục đích: Mở khung nhận được: quét preamble, tách LEN / IV / payload / digest.
// REQ    : REQ-F-20, REQ-F-21, REQ-F-24
// Tác giả : Đội Hủ Tiếu · Ngày: 2026-09-09
//=============================================================================
// Định dạng khung (SRS §4.1):
//   A5 5A | LEN(2, big-endian) | IV(16) | PAYLOAD(LEN) | DIGEST(32)
//
// ĐỒNG BỘ LẠI BẰNG QUÉT LIÊN TỤC (REQ-F-20): bộ mở khung không giả định biên
// khung. Nó quét từng byte tìm cặp A5 5A, nên rác đứng trước khung hợp lệ không
// làm hỏng việc nhận. Đây là điều kiện để hệ thống tự phục hồi sau nhiễu.
//
// LOẠI KHUNG SỚM (REQ-F-21): LEN được kiểm ngay khi đọc xong, TRƯỚC khi cấp
// phát bộ đệm hay nhận thêm byte nào. LEN = 0 hoặc LEN > 512 thì quay thẳng về
// quét, không tiêu tốn gì.
//
// WATCHDOG (REQ-F-24): nếu một khung không hoàn tất trong 2^24 chu kỳ (~0,62 s
// ở 27 MHz), FSM tự quay về quét. Không có watchdog thì một khung bị cắt giữa
// chừng sẽ treo bộ thu vĩnh viễn và mọi khung sau đều mất.
//=============================================================================

`timescale 1ns / 1ps

module frame_rx #(
    parameter MAX_LEN   = 512,
    parameter AW        = 9,
    // Số bit của bộ đếm watchdog. 24 bit ở 27 MHz = 0,62 s — dài hơn thời gian
    // truyền một khung 512 byte ở 115200 baud (46 ms) hơn 13 lần, nên không bao
    // giờ cắt nhầm một khung đang tới.
    //
    // Tham số hóa để MÔ PHỎNG kiểm được watchdog. Với giá trị 24 cố định, một
    // khung bị cắt sẽ khóa bộ mở khung suốt 0,62 s thời gian mô phỏng — dài tới
    // mức mọi testbench thực tế đều bỏ qua, và REQ-F-24 sẽ không bao giờ thực
    // sự được kiểm. Một requirement không kiểm được thì coi như không có.
    parameter WDOG_BITS = 24
) (
    input  wire         clk,
    input  wire         rst_n,

    // dòng byte từ uart_rx
    input  wire [7:0]   rx_data,
    input  wire         rx_valid,

    // ghi payload vào bộ đệm
    output reg          buf_we,
    output reg [AW-1:0] buf_waddr,
    output reg [7:0]    buf_wdata,

    // kết quả một khung
    output reg [15:0]   len,
    output reg [127:0]  iv,
    output reg [255:0]  digest_rx,
    output reg          frame_ready,     // xung 1 chu kỳ
    output reg          frame_drop,      // xung 1 chu kỳ: LEN sai hoặc watchdog
    output wire         busy
);

    localparam [2:0] ST_SCAN0 = 3'd0,   // chờ 0xA5
                     ST_SCAN1 = 3'd1,   // chờ 0x5A
                     ST_LEN   = 3'd2,
                     ST_IV    = 3'd3,
                     ST_PAY   = 3'd4,
                     ST_DIG   = 3'd5;

    reg [2:0]    state;
    reg [5:0]    cnt;          // đếm byte trong trường hiện tại (tối đa 32)
    reg [AW:0]   paycnt;
    reg [WDOG_BITS-1:0] wdog;

    assign busy = (state != ST_SCAN0) && (state != ST_SCAN1);

    // LEN ghép từ byte cao đã nhận (đang nằm ở len[7:0]) và byte thấp vừa tới
    wire [15:0] rx_len_next = {len[7:0], rx_data};
    wire        len_ok      = (rx_len_next >= 16'd1) &&
                              (rx_len_next <= MAX_LEN[15:0]);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= ST_SCAN0;
            cnt         <= 6'd0;
            paycnt      <= {(AW+1){1'b0}};
            wdog        <= {WDOG_BITS{1'b0}};
            len         <= 16'd0;
            iv          <= 128'd0;
            digest_rx   <= 256'd0;
            frame_ready <= 1'b0;
            frame_drop  <= 1'b0;
            buf_we      <= 1'b0;
            buf_waddr   <= {AW{1'b0}};
            buf_wdata   <= 8'd0;
        end else begin
            frame_ready <= 1'b0;
            frame_drop  <= 1'b0;
            buf_we      <= 1'b0;

            //----------------------------------------------------------
            // Watchdog: chỉ chạy khi đang giữa chừng một khung
            //----------------------------------------------------------
            if (busy) begin
                if (wdog == {WDOG_BITS{1'b1}}) begin
                    state      <= ST_SCAN0;
                    wdog       <= {WDOG_BITS{1'b0}};
                    frame_drop <= 1'b1;
                end else if (rx_valid) begin
                    wdog <= {WDOG_BITS{1'b0}};   // có byte mới thì gia hạn
                end else begin
                    wdog <= wdog + 1'b1;
                end
            end else begin
                wdog <= {WDOG_BITS{1'b0}};
            end

            //----------------------------------------------------------
            if (rx_valid) begin
                case (state)

                    // Quét liên tục, không giả định biên khung
                    ST_SCAN0: begin
                        if (rx_data == 8'hA5)
                            state <= ST_SCAN1;
                    end

                    ST_SCAN1: begin
                        if (rx_data == 8'h5A) begin
                            state <= ST_LEN;
                            cnt   <= 6'd0;
                        end else if (rx_data == 8'hA5) begin
                            // A5 A5 ... : giữ nguyên, byte này có thể là
                            // preamble mới. Không quay về SCAN0.
                            state <= ST_SCAN1;
                        end else begin
                            state <= ST_SCAN0;
                        end
                    end

                    ST_LEN: begin
                        if (cnt == 6'd0) begin
                            len <= {8'd0, rx_data};    // byte cao
                            cnt <= 6'd1;
                        end else begin
                            // REQ-F-21: kiểm NGAY, trước khi nhận thêm gì
                            if (len_ok) begin
                                len    <= rx_len_next;
                                state  <= ST_IV;
                                cnt    <= 6'd0;
                            end else begin
                                state      <= ST_SCAN0;
                                frame_drop <= 1'b1;
                            end
                        end
                    end

                    ST_IV: begin
                        iv <= {iv[119:0], rx_data};
                        if (cnt == 6'd15) begin
                            state  <= ST_PAY;
                            cnt    <= 6'd0;
                            paycnt <= {(AW+1){1'b0}};
                        end else begin
                            cnt <= cnt + 6'd1;
                        end
                    end

                    ST_PAY: begin
                        buf_we    <= 1'b1;
                        buf_waddr <= paycnt[AW-1:0];
                        buf_wdata <= rx_data;
                        if (paycnt == (len - 16'd1)) begin
                            state <= ST_DIG;
                            cnt   <= 6'd0;
                        end else begin
                            paycnt <= paycnt + 1'b1;
                        end
                    end

                    ST_DIG: begin
                        digest_rx <= {digest_rx[247:0], rx_data};
                        if (cnt == 6'd31) begin
                            state       <= ST_SCAN0;
                            frame_ready <= 1'b1;
                        end else begin
                            cnt <= cnt + 6'd1;
                        end
                    end

                    default: state <= ST_SCAN0;
                endcase
            end
        end
    end

endmodule
