//=============================================================================
// File   : rtl/ip/sha256/sha256_compress.v
// Mục đích: Hàm nén SHA-256 — 8 biến trạng thái a..h, 64 vòng, cộng dồn
//           trạng thái khối theo FIPS 180-4 §6.2.2.
// REQ    : REQ-F-10, REQ-P-06, REQ-R-04
// Tác giả : Đội Hủ Tiếu · Ngày: 2026-09-09
//=============================================================================
// Mỗi vòng:
//   T1 = h + Σ1(e) + Ch(e,f,g) + K[t] + W[t]
//   T2 = Σ0(a) + Maj(a,b,c)
//   h=g, g=f, f=e, e=d+T1, d=c, c=b, b=a, a=T1+T2
//
// Sau 64 vòng: H[i] += {a..h}[i]
//
// Đường tổ hợp dài nhất là chuỗi cộng của T1 (5 toán hạng 32 bit). Ước lượng
// ~18 ns, nằm trong ngân sách 37.0 ns của 27 MHz — xem ARCHITECTURE §6. Nếu
// F_max thực tế trượt, đây là chỗ chèn thanh ghi đầu tiên phía SHA.
//=============================================================================

`timescale 1ns / 1ps

module sha256_compress (
    input  wire         clk,
    input  wire         rst_n,

    input  wire         init,        // nạp trạng thái ban đầu H (IV hoặc trạng thái nối tiếp)
    input  wire [255:0] h_in,        // {H0,H1,...,H7}
    input  wire         step,        // chạy một vòng
    input  wire         finalize,    // cộng dồn a..h vào H

    input  wire [31:0]  w_t,         // W[t] từ sha256_sched
    input  wire [31:0]  k_t,         // K[t] từ sha256_k

    output wire [255:0] h_out
);

    reg [31:0] a, b, c, d, e, f, g, h;
    reg [31:0] h0, h1, h2, h3, h4, h5, h6, h7;

    //--------------------------------------------------------------------
    // Các hàm logic của chuẩn — thuần tổ hợp
    //--------------------------------------------------------------------
    function [31:0] bsig0;   // Σ0(x) = ROTR2 ^ ROTR13 ^ ROTR22
        input [31:0] x;
        begin
            bsig0 = {x[1:0],  x[31:2]}
                  ^ {x[12:0], x[31:13]}
                  ^ {x[21:0], x[31:22]};
        end
    endfunction

    function [31:0] bsig1;   // Σ1(x) = ROTR6 ^ ROTR11 ^ ROTR25
        input [31:0] x;
        begin
            bsig1 = {x[5:0],  x[31:6]}
                  ^ {x[10:0], x[31:11]}
                  ^ {x[24:0], x[31:25]};
        end
    endfunction

    function [31:0] ch;      // Ch(e,f,g) = (e & f) ^ (~e & g)
        input [31:0] x, y, z;
        begin
            ch = (x & y) ^ ((~x) & z);
        end
    endfunction

    function [31:0] maj;     // Maj(a,b,c) = (a&b) ^ (a&c) ^ (b&c)
        input [31:0] x, y, z;
        begin
            maj = (x & y) ^ (x & z) ^ (y & z);
        end
    endfunction

    wire [31:0] t1 = h + bsig1(e) + ch(e, f, g) + k_t + w_t;
    wire [31:0] t2 = bsig0(a) + maj(a, b, c);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            {a, b, c, d, e, f, g, h} <= 256'd0;
            {h0, h1, h2, h3, h4, h5, h6, h7} <= 256'd0;
        end else if (init) begin
            {h0, h1, h2, h3, h4, h5, h6, h7} <= h_in;
            {a, b, c, d, e, f, g, h}         <= h_in;
        end else if (step) begin
            h <= g;
            g <= f;
            f <= e;
            e <= d + t1;
            d <= c;
            c <= b;
            b <= a;
            a <= t1 + t2;
        end else if (finalize) begin
            h0 <= h0 + a;  h1 <= h1 + b;  h2 <= h2 + c;  h3 <= h3 + d;
            h4 <= h4 + e;  h5 <= h5 + f;  h6 <= h6 + g;  h7 <= h7 + h;
            // KHÔNG nạp lại a..h ở đây. Cho khối kế tiếp (REQ-F-12), FSM phát
            // `init` với h_in = h_out. Lý do: nếu cập nhật a..h ở cả ba nhánh
            // init/step/finalize thì mỗi bit trong 256 bit trạng thái cần một
            // mux 3 chiều — đo được 844 LUT3, đúng cái bẫy đã ghi ở ADR-0004.
            // Giữ a..h chỉ có 2 nguồn làm nó thành mux 2 chiều.
        end
    end

    assign h_out = {h0, h1, h2, h3, h4, h5, h6, h7};

endmodule
