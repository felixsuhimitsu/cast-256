//=============================================================================
// File   : sim/unit/tb_keysched.v
// Mục đích: TC-102 — đối chiếu TRỰC TIẾP toàn bộ 60 word khóa vòng W[0..59]
//           với vector FIPS 197 phụ lục A.3.
// REQ    : REQ-F-05, REQ-V-02
// Tác giả : Đội Hủ Tiếu · Ngày: 2026-09-15
//=============================================================================
// VÌ SAO TESTBENCH NÀY TỒN TẠI
//
// Trước đây REQ-F-05 chỉ được phủ GIÁN TIẾP: nếu key schedule sai thì TC-101 và
// TC-104 không thể PASS. Lập luận đó đúng nhưng chưa đủ — nó không phân biệt
// được "key schedule đúng" với "key schedule sai theo cách bù trừ với một lỗi
// khác". RTM §4b từng ghi rõ đây là chỗ phủ chưa đầy đủ.
//
// Lý do khi đó là `aes256_keysched` không có cổng quan sát ở mức IP, và thêm
// cổng sẽ vi phạm §7 hợp đồng CSI. Nhưng hợp đồng CSI chỉ ràng buộc ĐỈNH IP;
// module con hoàn toàn kiểm riêng được. Đây là cách đúng, và nó không đòi hỏi
// thay đổi RTL nào cả.
//
// Kiểm hai khóa khác nhau để loại trừ khả năng trùng hợp ngẫu nhiên:
//   khóa 1: 000102…1f          — FIPS 197 phụ lục A.3 / C.3
//   khóa 2: 603deb10…0914dff4  — NIST SP 800-38A §F.5.5
//=============================================================================

`timescale 1ns / 1ps
`include "tb_util.vh"

module tb_keysched;

    `TB_DECL

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg          start = 1'b0;
    reg  [255:0] key   = 256'd0;
    wire         done;

    wire [31:0]  sw_in, sw_out;
    wire         rk_we;
    wire [3:0]   rk_addr;
    wire [127:0] rk_data;

    aes256_keysched dut (
        .clk(clk), .rst_n(rst_n),
        .start(start), .key(key), .done(done),
        .sw_in(sw_in), .sw_out(sw_out),
        .rk_we(rk_we), .rk_addr(rk_addr), .rk_data(rk_data)
    );

    // Bốn khối S-Box phục vụ cổng "mượn" của key schedule. Trong thiết kế thật
    // chúng thuộc aes256_cipher; ở đây testbench cấp cho module con.
    genvar g;
    generate
        for (g = 0; g < 4; g = g + 1) begin : gen_sbox
            aes256_sbox u_sb (.a(sw_in[31 - 8*g -: 8]),
                              .s(sw_out[31 - 8*g -: 8]));
        end
    endgenerate

    // Thu toàn bộ khóa vòng do DUT ghi ra
    reg [127:0] got [0:14];
    reg [14:0]  seen;
    integer     k;

    always @(posedge clk) begin
        if (rst_n && rk_we) begin
            got[rk_addr]  <= rk_data;
            seen[rk_addr] <= 1'b1;
        end
    end

    reg [127:0] exp [0:14];
    integer     bad;

    task run_key;
        input [255:0] kv;
        begin
            seen = 15'd0;
            for (k = 0; k < 15; k = k + 1) got[k] = 128'hx;
            @(posedge clk);
            key   <= kv;
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;
            while (!done) @(posedge clk);
            repeat (3) @(posedge clk);
        end
    endtask

    task compare;
        input [127:0] label_unused;
        begin
            bad = 0;
            for (k = 0; k < 15; k = k + 1) begin
                if (!seen[k]) begin
                    bad = bad + 1;
                    $display("  [FAIL] khoa vong %0d KHONG duoc ghi ra", k);
                end else if (got[k] !== exp[k]) begin
                    bad = bad + 1;
                    $display("  [FAIL] rk[%0d]: mong doi %032h, thuc te %032h",
                             k, exp[k], got[k]);
                end
            end
        end
    endtask

    initial begin
        `TB_BEGIN("TC-102: key schedule AES-256 vs FIPS 197 A.3")

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        //---------------------------------------------------------------
        // Khoa 1 — FIPS 197 phu luc A.3
        //---------------------------------------------------------------
        exp[0]  = 128'h000102030405060708090a0b0c0d0e0f;
        exp[1]  = 128'h101112131415161718191a1b1c1d1e1f;
        exp[2]  = 128'ha573c29fa176c498a97fce93a572c09c;
        exp[3]  = 128'h1651a8cd0244beda1a5da4c10640bade;
        exp[4]  = 128'hae87dff00ff11b68a68ed5fb03fc1567;
        exp[5]  = 128'h6de1f1486fa54f9275f8eb5373b8518d;
        exp[6]  = 128'hc656827fc9a799176f294cec6cd5598b;
        exp[7]  = 128'h3de23a75524775e727bf9eb45407cf39;
        exp[8]  = 128'h0bdc905fc27b0948ad5245a4c1871c2f;
        exp[9]  = 128'h45f5a66017b2d387300d4d33640a820a;
        exp[10] = 128'h7ccff71cbeb4fe5413e6bbf0d261a7df;
        exp[11] = 128'hf01afafee7a82979d7a5644ab3afe640;
        exp[12] = 128'h2541fe719bf500258813bbd55a721c0a;
        exp[13] = 128'h4e5a6699a9f24fe07e572baacdf8cdea;
        exp[14] = 128'h24fc79ccbf0979e9371ac23c6d68de36;

        run_key(256'h000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f);
        compare(0);
        `CHECK_EQ(bad, 0, "TC-102a: 15/15 khoa vong (60 word) khop FIPS 197 A.3")

        //---------------------------------------------------------------
        // Khoa 2 — NIST SP 800-38A F.5.5, de loai tru trung hop ngau nhien
        //---------------------------------------------------------------
        exp[0]  = 128'h603deb1015ca71be2b73aef0857d7781;
        exp[1]  = 128'h1f352c073b6108d72d9810a30914dff4;
        exp[2]  = 128'h9ba354118e6925afa51a8b5f2067fcde;
        exp[3]  = 128'ha8b09c1a93d194cdbe49846eb75d5b9a;
        exp[4]  = 128'hd59aecb85bf3c917fee94248de8ebe96;
        exp[5]  = 128'hb5a9328a2678a647983122292f6c79b3;
        exp[6]  = 128'h812c81addadf48ba24360af2fab8b464;
        exp[7]  = 128'h98c5bfc9bebd198e268c3ba709e04214;
        exp[8]  = 128'h68007bacb2df331696e939e46c518d80;
        exp[9]  = 128'hc814e20476a9fb8a5025c02d59c58239;
        exp[10] = 128'hde1369676ccc5a71fa2563959674ee15;
        exp[11] = 128'h5886ca5d2e2f31d77e0af1fa27cf73c3;
        exp[12] = 128'h749c47ab18501ddae2757e4f7401905a;
        exp[13] = 128'hcafaaae3e4d59b349adf6acebd10190d;
        exp[14] = 128'hfe4890d1e6188d0b046df344706c631e;

        run_key(256'h603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4);
        compare(0);
        `CHECK_EQ(bad, 0, "TC-102b: 15/15 khoa vong khop voi khoa thu hai")

        //---------------------------------------------------------------
        // Hai khoa khac nhau phai cho lich trinh khac nhau — chan kha nang
        // module tra ve hang so
        //---------------------------------------------------------------
        `CHECK_TRUE(got[14] !== 128'h24fc79ccbf0979e9371ac23c6d68de36,
                    "TC-102c: khoa khac cho lich trinh khac (khong tra hang so)")

        //---------------------------------------------------------------
        // Chay lai khoa 1: phai cho dung ket qua cu (khong ro trang thai)
        //---------------------------------------------------------------
        exp[0]  = 128'h000102030405060708090a0b0c0d0e0f;
        exp[14] = 128'h24fc79ccbf0979e9371ac23c6d68de36;
        run_key(256'h000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f);
        `CHECK_EQ(got[0],  exp[0],  "TC-102d: nap lai khoa 1 -> rk[0] dung")
        `CHECK_EQ(got[14], exp[14], "TC-102d: nap lai khoa 1 -> rk[14] dung")

        `TB_END
    end

    initial begin
        #2_000_000;
        $display("  [FAIL] TIMEOUT");
        $fatal(1, "timeout");
    end

endmodule
