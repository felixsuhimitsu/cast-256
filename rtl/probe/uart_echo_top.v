//=============================================================================
// File   : rtl/probe/uart_echo_top.v
// Mục đích: Bitstream thăm dò của WP-01 — vọng lại (echo) mọi byte nhận được,
//           để kiểm REQ-I-05 trên phần cứng thật với luồng byte liên tục.
// REQ    : REQ-I-03, REQ-I-04, REQ-I-05
// ADR    : ADR-0005
// Tác giả : Đội Hủ Tiếu · Ngày: 2026-09-09
//=============================================================================
// ĐÂY KHÔNG PHẢI THIẾT KẾ NỘP. Nó chỉ tồn tại để trả lời một câu hỏi duy nhất:
// bộ thu UART có giữ được đồng bộ khi host gửi 512 byte không nghỉ hay không.
//
// Vì sao cần bitstream riêng thay vì tin vào mô phỏng: testbench luôn chèn
// khoảng nghỉ giữa các byte, nên lỗi mất đồng bộ tích lũy KHÔNG BAO GIỜ lộ ra
// trong mô phỏng. Ở thiết kế trước, mô phỏng PASS 100% trong khi phần cứng mất
// 159/256 byte. Xem DEVELOPMENT_BOOK §4.1.
//
// FIFO 16 byte: bộ phát dùng bộ chia 234 (2340 chu kỳ/byte) trong khi host gửi
// ở nhịp thật 2343.75 chu kỳ/byte, nên phía phát rút nhanh hơn phía thu nạp —
// FIFO không thể tràn. Nó chỉ để hấp thụ độ lệch pha lúc khởi động.
//=============================================================================

`timescale 1ns / 1ps

module uart_echo_top (
    input  wire clk_27m,
    input  wire rst_n,
    input  wire uart_rx_pin,
    output wire uart_tx_pin,
    output wire led_activity
);

    //------------------------------------------------------------------
    // Đồng bộ nhả reset: assert bất đồng bộ, de-assert đồng bộ
    // (ARCHITECTURE §5)
    //------------------------------------------------------------------
    reg rst_meta, rst_sync;
    always @(posedge clk_27m or negedge rst_n) begin
        if (!rst_n) begin
            rst_meta <= 1'b0;
            rst_sync <= 1'b0;
        end else begin
            rst_meta <= 1'b1;
            rst_sync <= rst_meta;
        end
    end
    wire rstn = rst_sync;

    //------------------------------------------------------------------
    wire [7:0] rx_data;
    wire       rx_valid;
    wire       rx_frame_err;

    uart_rx u_rx (
        .clk          (clk_27m),
        .rst_n        (rstn),
        .rx           (uart_rx_pin),
        .rx_data      (rx_data),
        .rx_valid     (rx_valid),
        .rx_frame_err (rx_frame_err)
    );

    //------------------------------------------------------------------
    // FIFO vòng 16 byte
    //------------------------------------------------------------------
    reg [7:0] fifo [0:15];
    reg [4:0] wptr, rptr;
    wire      fifo_empty = (wptr == rptr);
    wire      fifo_full  = (wptr[3:0] == rptr[3:0]) && (wptr[4] != rptr[4]);

    wire       tx_ready;
    wire       tx_take = !fifo_empty && tx_ready;

    always @(posedge clk_27m or negedge rstn) begin
        if (!rstn) begin
            wptr <= 5'd0;
            rptr <= 5'd0;
        end else begin
            if (rx_valid && !fifo_full) begin
                fifo[wptr[3:0]] <= rx_data;
                wptr <= wptr + 1'b1;
            end
            if (tx_take)
                rptr <= rptr + 1'b1;
        end
    end

    uart_tx u_tx (
        .clk      (clk_27m),
        .rst_n    (rstn),
        .tx_data  (fifo[rptr[3:0]]),
        .tx_valid (!fifo_empty),
        .tx_ready (tx_ready),
        .tx       (uart_tx_pin)
    );

    //------------------------------------------------------------------
    // Đèn: sáng khi FIFO không rỗng hoặc vừa có lỗi khung.
    // Kéo dài để mắt thấy được (~50 ms).
    //------------------------------------------------------------------
    reg [20:0] blink;
    always @(posedge clk_27m or negedge rstn) begin
        if (!rstn)
            blink <= 21'd0;
        else if (rx_valid || rx_frame_err)
            blink <= 21'h1FFFFF;
        else if (blink != 21'd0)
            blink <= blink - 1'b1;
    end

    // LED trên Tang Nano 9K sáng ở mức thấp
    assign led_activity = ~(blink != 21'd0);

endmodule
