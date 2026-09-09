//=============================================================================
// File   : rtl/ip/aes256/aes256_sbox.v
// Mục đích: S-Box AES bằng số học trường composite GF(((2^2)^2)^2) thay cho
//           bảng tra 256x8. Tổ hợp thuần, không thanh ghi, thời gian hằng định.
// REQ    : REQ-F-04, REQ-R-03
// ADR    : ADR-0001
// Tác giả : Đội Hủ Tiếu · Ngày: 2026-09-09
//=============================================================================
// Cấu trúc trường tháp:
//     GF(2^2) = GF(2)[w]/(w^2 + w + 1)
//     GF(2^4) = GF(2^2)[z]/(z^2 + z + PHI)      PHI = 2
//     GF(2^8) = GF(2^4)[y]/(y^2 + y + LAM)      LAM = 8
//
// Các hằng số MAP_FWD / MAP_INV_AFF dưới đây KHÔNG phải chép tay. Chúng do
// scripts/gen_sbox_basis.py tìm ra và đã được kiểm đủ 256/256 giá trị so với
// S-Box chuẩn FIPS 197 *trước khi* file Verilog này được viết. Muốn đổi hằng
// số thì chạy lại script, đừng sửa tay — xem RSK-03.
//
// Luồng:  a --[MAP_FWD]--> trường tháp --[nghịch đảo]--> --[MAP_INV_AFF]--> ^0x63
//=============================================================================

`timescale 1ns / 1ps

module aes256_sbox (
    input  wire [7:0] a,
    output wire [7:0] s
);

    localparam [1:0] PHI = 2'd2;
    localparam [3:0] LAM = 4'd8;

    //------------------------------------------------------------------
    // GF(2^2): phần tử = a1*w + a0
    //------------------------------------------------------------------
    function [1:0] g2_mul;
        input [1:0] x, y;
        reg xh, xl, yh, yl;
        begin
            xh = x[1]; xl = x[0];
            yh = y[1]; yl = y[0];
            g2_mul[1] = (xh & yh) ^ (xh & yl) ^ (xl & yh);
            g2_mul[0] = (xh & yh) ^ (xl & yl);
        end
    endfunction

    function [1:0] g2_sq;
        input [1:0] x;
        begin
            g2_sq[1] = x[1];
            g2_sq[0] = x[1] ^ x[0];
        end
    endfunction

    // Trong GF(4): x^3 = 1, nên x^(-1) = x^2. Không cần mạch chia riêng.
    function [1:0] g2_inv;
        input [1:0] x;
        begin
            g2_inv = g2_sq(x);
        end
    endfunction

    //------------------------------------------------------------------
    // GF(2^4): phần tử = a1*z + a0, với a1,a0 thuộc GF(2^2)
    //------------------------------------------------------------------
    function [3:0] g4_mul;
        input [3:0] x, y;
        reg [1:0] xh, xl, yh, yl, hh;
        begin
            xh = x[3:2]; xl = x[1:0];
            yh = y[3:2]; yl = y[1:0];
            hh = g2_mul(xh, yh);
            g4_mul[3:2] = hh ^ g2_mul(xh, yl) ^ g2_mul(xl, yh);
            g4_mul[1:0] = g2_mul(PHI, hh) ^ g2_mul(xl, yl);
        end
    endfunction

    function [3:0] g4_sq;
        input [3:0] x;
        reg [1:0] s1;
        begin
            s1 = g2_sq(x[3:2]);
            g4_sq[3:2] = s1;
            g4_sq[1:0] = g2_mul(PHI, s1) ^ g2_sq(x[1:0]);
        end
    endfunction

    function [3:0] g4_inv;
        input [3:0] x;
        reg [1:0] x1, x0, d, di;
        begin
            x1 = x[3:2];
            x0 = x[1:0];
            // chuẩn (norm) rơi xuống GF(2^2)
            d  = g2_mul(PHI, g2_sq(x1)) ^ g2_mul(x0, x1 ^ x0);
            di = g2_inv(d);
            g4_inv[3:2] = g2_mul(x1, di);
            g4_inv[1:0] = g2_mul(x1 ^ x0, di);
        end
    endfunction

    //------------------------------------------------------------------
    // GF(2^8): phần tử = a1*y + a0, với a1,a0 thuộc GF(2^4)
    //------------------------------------------------------------------
    function [7:0] g8_inv;
        input [7:0] x;
        reg [3:0] x1, x0, d, di;
        begin
            x1 = x[7:4];
            x0 = x[3:0];
            d  = g4_mul(LAM, g4_sq(x1)) ^ g4_mul(x0, x1 ^ x0);
            di = g4_inv(d);
            g8_inv[7:4] = g4_mul(x1, di);
            g8_inv[3:0] = g4_mul(x1 ^ x0, di);
        end
    endfunction

    //------------------------------------------------------------------
    // Đổi cơ sở — ma trận 8x8 trên GF(2), hiện thực bằng XOR các cột
    //------------------------------------------------------------------
    // AES -> trường tháp
    function [7:0] map_fwd;
        input [7:0] x;
        begin
            map_fwd = (x[0] ? 8'h01 : 8'h00)
                    ^ (x[1] ? 8'h41 : 8'h00)
                    ^ (x[2] ? 8'h66 : 8'h00)
                    ^ (x[3] ? 8'h6C : 8'h00)
                    ^ (x[4] ? 8'h56 : 8'h00)
                    ^ (x[5] ? 8'h9A : 8'h00)
                    ^ (x[6] ? 8'h58 : 8'h00)
                    ^ (x[7] ? 8'hC4 : 8'h00);
        end
    endfunction

    // Trường tháp -> AES, ĐÃ GỘP phần tuyến tính của biến đổi affine.
    // Gộp như vậy tiết kiệm cả một khối XOR-rotate riêng.
    function [7:0] map_inv_aff;
        input [7:0] x;
        begin
            map_inv_aff = (x[0] ? 8'h1F : 8'h00)
                        ^ (x[1] ? 8'h19 : 8'h00)
                        ^ (x[2] ? 8'hB2 : 8'h00)
                        ^ (x[3] ? 8'h9D : 8'h00)
                        ^ (x[4] ? 8'h7B : 8'h00)
                        ^ (x[5] ? 8'hF6 : 8'h00)
                        ^ (x[6] ? 8'h21 : 8'h00)
                        ^ (x[7] ? 8'h1C : 8'h00);
        end
    endfunction

    //------------------------------------------------------------------
    // Ghép lại
    //------------------------------------------------------------------
    wire [7:0] t_in  = map_fwd(a);
    wire [7:0] t_inv = g8_inv(t_in);

    assign s = map_inv_aff(t_inv) ^ 8'h63;

endmodule
