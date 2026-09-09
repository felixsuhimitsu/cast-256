//=============================================================================
// File   : rtl/ip/aes256/aes256_round.v
// Mục đích: Một vòng AES sau SubBytes — ShiftRows, MixColumns, AddRoundKey.
//           Thuần tổ hợp, không thanh ghi.
// REQ    : REQ-F-01
// Tác giả : Đội Hủ Tiếu · Ngày: 2026-09-09
//=============================================================================
// SubBytes KHÔNG nằm trong module này. 16 khối aes256_sbox do aes256_cipher sở
// hữu, vì chúng còn được key schedule mượn dùng (ADR-0007) — gom S-Box vào đây
// sẽ làm việc chia sẻ đó không thực hiện được.
//
// Quy ước sắp byte theo FIPS 197 §3.4: state[r][c] = b[r + 4c], với b[0] là
// byte đầu tiên của khối, tức là 8 bit CAO NHẤT của vector 128 bit.
//
// ShiftRows: hàng r dịch trái r vị trí.
// MixColumns: nhân ma trận trong GF(2^8) với modulus x^8+x^4+x^3+x+1.
// Vòng cuối (round 14) KHÔNG có MixColumns — cờ `last`.
//=============================================================================

`timescale 1ns / 1ps

module aes256_round (
    input  wire [127:0] sb,      // state SAU SubBytes
    input  wire [127:0] rk,      // khóa vòng
    input  wire         last,    // 1 = vòng cuối, bỏ MixColumns
    output wire [127:0] out
);

    // Truy cập byte thứ i (i = 0..15), b[0] ở bit cao nhất
    function [7:0] bsel;
        input [127:0] v;
        input integer i;
        begin
            bsel = v[127 - 8*i -: 8];
        end
    endfunction

    // xtime: nhân với 2 trong GF(2^8)
    function [7:0] xt;
        input [7:0] x;
        begin
            xt = {x[6:0], 1'b0} ^ (x[7] ? 8'h1B : 8'h00);
        end
    endfunction

    //------------------------------------------------------------------
    // ShiftRows
    //------------------------------------------------------------------
    wire [7:0] sr [0:15];

    // hàng 0: không dịch
    assign sr[0]  = bsel(sb, 0);
    assign sr[4]  = bsel(sb, 4);
    assign sr[8]  = bsel(sb, 8);
    assign sr[12] = bsel(sb, 12);
    // hàng 1: dịch trái 1
    assign sr[1]  = bsel(sb, 5);
    assign sr[5]  = bsel(sb, 9);
    assign sr[9]  = bsel(sb, 13);
    assign sr[13] = bsel(sb, 1);
    // hàng 2: dịch trái 2
    assign sr[2]  = bsel(sb, 10);
    assign sr[6]  = bsel(sb, 14);
    assign sr[10] = bsel(sb, 2);
    assign sr[14] = bsel(sb, 6);
    // hàng 3: dịch trái 3
    assign sr[3]  = bsel(sb, 15);
    assign sr[7]  = bsel(sb, 3);
    assign sr[11] = bsel(sb, 7);
    assign sr[15] = bsel(sb, 11);

    //------------------------------------------------------------------
    // MixColumns — 4 cột độc lập
    //------------------------------------------------------------------
    wire [7:0] mc [0:15];
    genvar c;
    generate
        for (c = 0; c < 4; c = c + 1) begin : gen_mixcol
            wire [7:0] a0 = sr[4*c + 0];
            wire [7:0] a1 = sr[4*c + 1];
            wire [7:0] a2 = sr[4*c + 2];
            wire [7:0] a3 = sr[4*c + 3];

            // 3*x = xtime(x) ^ x
            assign mc[4*c + 0] = xt(a0) ^ (xt(a1) ^ a1) ^ a2        ^ a3;
            assign mc[4*c + 1] = a0     ^ xt(a1)         ^ (xt(a2) ^ a2) ^ a3;
            assign mc[4*c + 2] = a0     ^ a1             ^ xt(a2)   ^ (xt(a3) ^ a3);
            assign mc[4*c + 3] = (xt(a0) ^ a0) ^ a1      ^ a2       ^ xt(a3);
        end
    endgenerate

    //------------------------------------------------------------------
    // Chọn có MixColumns hay không, rồi AddRoundKey
    //------------------------------------------------------------------
    wire [127:0] mixed = {
        mc[0],  mc[1],  mc[2],  mc[3],  mc[4],  mc[5],  mc[6],  mc[7],
        mc[8],  mc[9],  mc[10], mc[11], mc[12], mc[13], mc[14], mc[15]
    };

    wire [127:0] shifted = {
        sr[0],  sr[1],  sr[2],  sr[3],  sr[4],  sr[5],  sr[6],  sr[7],
        sr[8],  sr[9],  sr[10], sr[11], sr[12], sr[13], sr[14], sr[15]
    };

    assign out = (last ? shifted : mixed) ^ rk;

endmodule
