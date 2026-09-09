//=============================================================================
// File   : rtl/ip/sha256/sha256_sched.v
// Mục đích: Bộ lập lịch thông điệp SHA-256 dùng cửa sổ trượt 16 word thay vì
//           lưu đủ 64 word — tiết kiệm 1536 DFF.
// REQ    : REQ-F-13, REQ-R-02, REQ-R-04
// ADR    : ADR-0003
// Tác giả : Đội Hủ Tiếu · Ngày: 2026-09-09
//=============================================================================
// W[t] = σ1(W[t-2]) + W[t-7] + σ0(W[t-15]) + W[t-16]
//   σ0(x) = ROTR7(x)  ^ ROTR18(x) ^ SHR3(x)
//   σ1(x) = ROTR17(x) ^ ROTR19(x) ^ SHR10(x)
//
// Vì mọi phụ thuộc đều nằm trong 16 word gần nhất, chỉ cần giữ w[0..15]:
//   w[15] = W[t-1] ... w[0] = W[t-16]
// Mỗi chu kỳ đẩy một word mới vào w[15], word cũ nhất rơi ra khỏi w[0].
//
// ĐÁNH ĐỔI (ADR-0003): message schedule bị buộc chặt về thời gian với vòng nén
// — không thể tính trước toàn bộ W rồi mới nén. FSM phải đồng bộ chính xác.
// Đây là chỗ dễ sai off-by-one nhất trong IP này.
//=============================================================================

`timescale 1ns / 1ps

module sha256_sched (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        load,        // nạp word thứ i của khối (i = 0..15)
    input  wire [31:0] load_word,
    input  wire        step,        // trượt cửa sổ, sinh W[t] cho t >= 16

    output wire [31:0] w_out        // W[t] dùng cho vòng nén ở chu kỳ này
);

    reg [31:0] w [0:15];
    integer    k;

    // σ0 và σ1 — thuần tổ hợp, không tốn thanh ghi
    function [31:0] sig0;
        input [31:0] x;
        begin
            sig0 = {x[6:0],  x[31:7]}       // ROTR7
                 ^ {x[17:0], x[31:18]}      // ROTR18
                 ^ {3'b000,  x[31:3]};      // SHR3
        end
    endfunction

    function [31:0] sig1;
        input [31:0] x;
        begin
            sig1 = {x[16:0], x[31:17]}      // ROTR17
                 ^ {x[18:0], x[31:19]}      // ROTR19
                 ^ {10'd0,   x[31:10]};     // SHR10
        end
    endfunction

    // W[t] mới. w[14] = W[t-2], w[9] = W[t-7], w[1] = W[t-15], w[0] = W[t-16]
    wire [31:0] w_next = sig1(w[14]) + w[9] + sig0(w[1]) + w[0];

    // 16 word đầu là dữ liệu thông điệp; từ word 17 trở đi là word tự sinh.
    assign w_out = load ? load_word : w[0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (k = 0; k < 16; k = k + 1)
                w[k] <= 32'd0;
        end else if (load) begin
            // Nạp: đẩy word thông điệp vào đầu cửa sổ
            for (k = 0; k < 15; k = k + 1)
                w[k] <= w[k+1];
            w[15] <= load_word;
        end else if (step) begin
            // Trượt: đẩy word tự sinh vào
            for (k = 0; k < 15; k = k + 1)
                w[k] <= w[k+1];
            w[15] <= w_next;
        end
    end

endmodule
