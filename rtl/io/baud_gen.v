//=============================================================================
// File   : rtl/io/baud_gen.v
// Mục đích: Sinh xung nhịp bit cho bộ phát UART. 27.0 MHz -> 115200 baud.
// REQ    : REQ-I-03
// Tác giả : Đội Hủ Tiếu · Ngày: 2026-09-09
//=============================================================================
// 27_000_000 / 115_200 = 234.375  ->  bộ chia nguyên dùng 234, sai số −0.16%.
//
// Module này CHỈ dùng cho bộ phát (uart_tx). Bộ thu (uart_rx) tự đếm riêng vì
// nó phải căn pha lại theo từng sườn start bit — dùng chung một bộ đếm tự do
// sẽ làm điểm lấy mẫu trôi khỏi giữa bit. Đây là lý do baud_gen không có cổng
// nào nối sang uart_rx.
//
// Sai số −0.16% tích lũy trong một khung 10 bit là ~3.75 chu kỳ, nằm xa dưới
// nửa bit (117 chu kỳ) nên không ảnh hưởng phía phát. Phía thu thì sai số này
// từng gây mất đồng bộ — cách xử lý ở ADR-0005 và trong uart_rx.v.
//=============================================================================

`timescale 1ns / 1ps

module baud_gen #(
    parameter CLK_HZ = 27_000_000,
    parameter BAUD   = 115_200
) (
    input  wire clk,
    input  wire rst_n,
    input  wire enable,      // 0 = giữ bộ đếm ở 0, để căn pha khi bắt đầu phát
    output wire tick         // 1 chu kỳ, mỗi DIV chu kỳ một lần
);

    localparam integer DIV = CLK_HZ / BAUD;      // = 234
    localparam integer CW  = 9;                  // đủ chứa 233

    reg [CW-1:0] cnt;

    assign tick = enable && (cnt == DIV[CW-1:0] - 1'b1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cnt <= {CW{1'b0}};
        else if (!enable)
            cnt <= {CW{1'b0}};
        else if (cnt == DIV[CW-1:0] - 1'b1)
            cnt <= {CW{1'b0}};
        else
            cnt <= cnt + 1'b1;
    end

endmodule
