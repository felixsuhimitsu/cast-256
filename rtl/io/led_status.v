//=============================================================================
// File   : rtl/io/led_status.v
// Mục đích: Ba đèn chỉ thị trạng thái.
// REQ    : REQ-F-30, REQ-F-31, REQ-F-32
// Tác giả : Đội Hủ Tiếu · Ngày: 2026-09-09
//=============================================================================
// LED trên Tang Nano 9K sáng ở MỨC THẤP — mọi cổng ra ở đây đều đảo.
//
// LED0  đang nhận khung          (REQ-F-30)
// LED1  engine mật mã đang bận   (REQ-F-31)
// LED2  khung vừa bị loại        (REQ-F-32) — chớp ~200 ms để mắt kịp thấy,
//       và bật VĨNH VIỄN nếu chốt vi phạm loại trừ tương hỗ bật (REQ-F-25).
//
// Việc nối `viol_concurrent` ra đèn là có chủ đích: nó biến một bất biến vốn
// chỉ kiểm được trong mô phỏng thành thứ quan sát được trên phần cứng thật.
//=============================================================================

`timescale 1ns / 1ps

module led_status #(
    parameter CLK_HZ    = 27_000_000,
    parameter BLINK_MS  = 200
) (
    input  wire clk,
    input  wire rst_n,

    input  wire rx_active,
    input  wire engine_busy,
    input  wire drop_pulse,
    input  wire viol_concurrent,

    output wire led0_n,
    output wire led1_n,
    output wire led2_n
);

    localparam integer BLINK_CYCLES = (CLK_HZ / 1000) * BLINK_MS;

    reg [23:0] blink;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            blink <= 24'd0;
        else if (drop_pulse)
            blink <= BLINK_CYCLES[23:0];
        else if (blink != 24'd0)
            blink <= blink - 24'd1;
    end

    assign led0_n = ~rx_active;
    assign led1_n = ~engine_busy;
    assign led2_n = ~((blink != 24'd0) | viol_concurrent);

endmodule
