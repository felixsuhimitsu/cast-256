//=============================================================================
// File   : rtl/protocol/frame_buffer.v
// Mục đích: Bộ đệm payload 512 byte. Đặt trong BSRAM, không phải thanh ghi.
// REQ    : REQ-F-21
// ADR    : ARCHITECTURE §4.2
// Tác giả : Đội Hủ Tiếu · Ngày: 2026-09-09
//=============================================================================
// 512 byte trong thanh ghi = 4096 DFF, tức 63% toàn bộ DFF của thiết bị. Trong
// BSRAM thì tốn 4 khối trên tổng 26. Đây là khác biệt giữa "vừa thiết bị" và
// "không".
//
// Bộ nhớ hai cổng đơn giản (simple dual port): một cổng ghi, một cổng đọc, đọc
// có thanh ghi nên trễ MỘT chu kỳ. Bên dùng phải tính đến độ trễ này — chính
// loại lỗi đã xảy ra hai lần ở WP-04 với bộ nhớ khóa vòng.
//=============================================================================

`timescale 1ns / 1ps

module frame_buffer #(
    parameter DEPTH = 512,
    parameter AW    = 9
) (
    input  wire          clk,

    input  wire          we,
    input  wire [AW-1:0] waddr,
    input  wire [7:0]    wdata,

    input  wire [AW-1:0] raddr,
    output reg  [7:0]    rdata      // trễ 1 chu kỳ so với raddr
);

    reg [7:0] mem [0:DEPTH-1];

    always @(posedge clk) begin
        if (we)
            mem[waddr] <= wdata;
        rdata <= mem[raddr];
    end

endmodule
