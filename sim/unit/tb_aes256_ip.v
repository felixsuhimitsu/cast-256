//=============================================================================
// File   : sim/unit/tb_aes256_ip.v
// Mục đích: TC-100..109 — kiểm IP AES-256-CTR bằng vector FIPS 197 và
//           NIST SP 800-38A, kèm kiểm hợp đồng CSI.
// REQ    : REQ-F-01..07, REQ-P-05, REQ-I-01, REQ-I-02, REQ-V-01, REQ-V-02
// Tác giả : Đội Hủ Tiếu · Ngày: 2026-09-09
//=============================================================================
// NGUỒN VECTOR — mọi giá trị dưới đây đã được đối chiếu với hiện thực tham
// chiếu (python `cryptography`) trước khi đưa vào file này, sau khi WP-03 phát
// hiện 2/6 vector viết từ trí nhớ là SAI. Xem DEVELOPMENT_BOOK §4.2 mục 7.
//
//   FIPS 197 phụ lục C.3      — AES-256 một khối
//   NIST SP 800-38A §F.5.5    — CTR-AES256.Encrypt, 4 khối
//=============================================================================

`timescale 1ns / 1ps
`include "tb_util.vh"

module tb_aes256_ip;

    `TB_DECL

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg         csi_start = 1'b0;
    reg  [7:0]  csi_mode  = 8'h00;
    wire        csi_busy, csi_done, csi_err;

    reg  [7:0]  sin_data  = 8'd0;
    reg         sin_valid = 1'b0;
    reg         sin_last  = 1'b0;
    wire        sin_ready;

    wire [7:0]  sout_data;
    wire        sout_valid, sout_last;
    reg         sout_ready = 1'b1;

    wire [255:0] csi_result;
    wire         csi_result_valid;

    aes256_ctr_ip dut (
        .clk(clk), .rst_n(rst_n),
        .csi_start(csi_start), .csi_mode(csi_mode),
        .csi_busy(csi_busy), .csi_done(csi_done), .csi_err(csi_err),
        .sin_data(sin_data), .sin_valid(sin_valid), .sin_last(sin_last),
        .sin_ready(sin_ready),
        .sout_data(sout_data), .sout_valid(sout_valid), .sout_last(sout_last),
        .sout_ready(sout_ready),
        .csi_result(csi_result), .csi_result_valid(csi_result_valid)
    );

    wire [15:0] viol;
    csi_checker #(.NAME("aes256_ctr_ip")) u_chk (
        .clk(clk), .rst_n(rst_n),
        .csi_start(csi_start), .csi_busy(csi_busy),
        .csi_done(csi_done), .csi_err(csi_err),
        .sin_data(sin_data), .sin_valid(sin_valid), .sin_last(sin_last),
        .sin_ready(sin_ready),
        .sout_data(sout_data), .sout_valid(sout_valid), .sout_last(sout_last),
        .sout_ready(sout_ready),
        .csi_result_valid(csi_result_valid),
        .viol_count(viol)
    );

    //------------------------------------------------------------------
    reg [2047:0] outbuf;      // gom tối đa 256 byte ra
    integer      outlen;
    integer      cyc, enc_cycles;

    always @(posedge clk) begin
        if (sout_valid && sout_ready) begin
            outbuf[2047 - 8*outlen -: 8] = sout_data;
            outlen = outlen + 1;
        end
    end

    //------------------------------------------------------------------
    task csi_op;                 // phát một xung start với mode cho trước
        input [7:0] m;
        begin
            @(posedge clk);
            csi_mode  <= m;
            csi_start <= 1'b1;
            @(posedge clk);
            csi_start <= 1'b0;
            @(posedge clk);
        end
    endtask

    task push_byte;              // đẩy một byte vào sin_*, tuân H2
        input [7:0] b;
        input       lastf;
        begin
            sin_data  <= b;
            sin_valid <= 1'b1;
            sin_last  <= lastf;
            @(posedge clk);
            while (!sin_ready) @(posedge clk);
            sin_valid <= 1'b0;
            sin_last  <= 1'b0;
            @(posedge clk);
        end
    endtask

    task load_key;
        input [255:0] k;
        integer i;
        begin
            csi_op(8'h00);
            for (i = 0; i < 32; i = i + 1)
                push_byte(k[255 - 8*i -: 8], (i == 31));
            while (!csi_done) @(posedge clk);
        end
    endtask

    task load_iv;
        input [127:0] v;
        integer i;
        begin
            csi_op(8'h01);
            for (i = 0; i < 16; i = i + 1)
                push_byte(v[127 - 8*i -: 8], (i == 15));
            while (!csi_done) @(posedge clk);
        end
    endtask

    task crypt;                  // mã hóa n byte lấy từ `src`
        input integer   n;
        input [2047:0]  src;
        integer i;
        begin
            outlen = 0;
            csi_op(8'h02);
            cyc = 0;
            for (i = 0; i < n; i = i + 1)
                push_byte(src[2047 - 8*i -: 8], (i == n - 1));
            while (!csi_done) @(posedge clk);
        end
    endtask

    //------------------------------------------------------------------
    localparam [255:0] K_FIPS = 256'h000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f;
    localparam [255:0] K_CTR  = 256'h603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4;

    integer j;

    initial begin
        outlen = 0;

        `TB_BEGIN("TC-100..109: IP AES-256-CTR vs FIPS 197 / SP 800-38A")

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        //---------------------------------------------------------------
        // TC-101 (qua CTR): FIPS 197 C.3
        // AES(key, 00112233..eeff) = 8ea2b7ca...b496089
        // Kiem gian tiep: dat IV = plaintext, roi ma hoa 16 byte 0x00.
        // Khi do sout = 0 XOR AES(IV) = AES(plaintext) chinh la ciphertext.
        // Cach nay kiem duoc CA khoi cipher LAN duong CTR bang mot vector.
        //---------------------------------------------------------------
        load_key(K_FIPS);
        `CHECK_TRUE(!csi_err, "TC-101a: nap khoa khong loi")

        load_iv(128'h00112233445566778899aabbccddeeff);
        `CHECK_TRUE(!csi_err, "TC-101b: nap IV khong loi")

        crypt(16, {128'h0, 1920'h0});
        `CHECK_EQ(outlen, 32'd16, "TC-101c: xuat dung 16 byte")
        `CHECK_EQ(outbuf[2047:1920],
                  128'h8ea2b7ca516745bfeafc49904b496089,
                  "TC-101: AES-256(FIPS 197 C.3) - kiem ca cipher va key schedule")

        //---------------------------------------------------------------
        // TC-104: NIST SP 800-38A F.5.5, CTR-AES256, 4 khoi lien tiep.
        // Phep kiem quan trong nhat: no chung minh bo dem tang DUNG qua
        // ranh gioi khoi, khong chi mot khoi don le.
        //---------------------------------------------------------------
        load_key(K_CTR);
        load_iv(128'hf0f1f2f3f4f5f6f7f8f9fafbfcfdfeff);

        crypt(64, {512'h6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e5130c81c46a35ce411e5fbc1191a0a52eff69f2445df4f9b17ad2b417be66c3710, 1536'h0});

        `CHECK_EQ(outlen, 32'd64, "TC-104a: xuat dung 64 byte")
        `CHECK_EQ(outbuf[2047:1920], 128'h601ec313775789a5b7a7f504bbf3d228,
                  "TC-104 khoi 1")
        `CHECK_EQ(outbuf[1919:1792], 128'hf443e3ca4d62b59aca84e990cacaf5c5,
                  "TC-104 khoi 2")
        `CHECK_EQ(outbuf[1791:1664], 128'h2b0930daa23de94ce87017ba2d84988d,
                  "TC-104 khoi 3")
        `CHECK_EQ(outbuf[1663:1536], 128'hdfc9c58db67aada613c2dd08457941a6,
                  "TC-104 khoi 4")

        //---------------------------------------------------------------
        // TC-105: bo dem tran all-ones -> 0 (REQ-F-03)
        //---------------------------------------------------------------
        load_key(K_FIPS);
        load_iv(128'hffffffffffffffffffffffffffffffff);
        crypt(32, {256'h0, 1792'h0});
        `CHECK_EQ(outbuf[2047:1920], 128'he999e41d4ca770da5387117b5d8f57ee,
                  "TC-105a: keystream tai ctr = all-ones")
        `CHECK_EQ(outbuf[1919:1792], 128'hf29000b62a499fd0a9f39a6add2e7780,
                  "TC-105b: sau khi tran, ctr quan vong ve 0")

        //---------------------------------------------------------------
        // TC-106: ma roi giai phai ve lai ban ro (REQ-F-06)
        // CTR doi xung: cung mot MODE_CRYPT dung cho ca hai chieu.
        //---------------------------------------------------------------
        begin : roundtrip
            reg [2047:0] pt, ct;
            integer k2;
            for (k2 = 0; k2 < 48; k2 = k2 + 1)
                pt[2047 - 8*k2 -: 8] = (k2 * 8'd37) ^ 8'hA5;

            load_key(K_CTR);
            load_iv(128'h0123456789abcdef0123456789abcdef);
            crypt(48, pt);
            ct = outbuf;
            `CHECK_TRUE(ct[2047:1920] !== pt[2047:1920],
                        "TC-106a: ban ma khac ban ro (khoa that su co tac dung)")

            load_iv(128'h0123456789abcdef0123456789abcdef);   // dat lai bo dem
            crypt(48, ct);
            `CHECK_EQ(outbuf[2047:1664], pt[2047:1664],
                      "TC-106b: giai ma ve dung ban ro (48 byte)")
        end

        //---------------------------------------------------------------
        // TC-107: csi_start khi dang ban phai bi BO QUA (REQ-F-07)
        //---------------------------------------------------------------
        // Phai dung K_CTR: gia tri keystream doi chieu ben duoi la cua khoa
        // nay. Ban dau toi nap K_FIPS ma van doi chieu keystream cua K_CTR —
        // test sai, khong phai IP sai.
        load_key(K_CTR);
        load_iv(128'hf0f1f2f3f4f5f6f7f8f9fafbfcfdfeff);
        outlen = 0;
        csi_op(8'h02);
        // Ban giua chung: ban thang mot start khac
        @(posedge clk);
        csi_mode  <= 8'h00;
        csi_start <= 1'b1;
        @(posedge clk);
        csi_start <= 1'b0;
        for (j = 0; j < 16; j = j + 1)
            push_byte(8'h00, (j == 15));
        while (!csi_done) @(posedge clk);
        `CHECK_EQ(outbuf[2047:1920], 128'h0bdf7df1591716335e9a8b15c860c502,
                  "TC-107: start khi dang ban bi bo qua, ket qua khong hong")

        //---------------------------------------------------------------
        // TC-109: csi_mode khong hop le
        //---------------------------------------------------------------
        csi_op(8'h7F);
        while (!csi_done) @(posedge clk);
        `CHECK_TRUE(csi_err, "TC-109: csi_mode khong hop le -> csi_err")
        `CHECK_TRUE(!csi_result_valid, "INV-5: err thi result_valid = 0")

        //---------------------------------------------------------------
        // TC-102 gian tiep: neu key schedule sai thi TC-101 va TC-104 da
        // fail. Khong co cong ra rieng cho khoa vong nen khong kiem truc
        // tiep W[0..59] duoc — ghi ro gioi han nay o RTM thay vi lam ngo.
        //---------------------------------------------------------------

        //---------------------------------------------------------------
        // TC-108: hop dong CSI trong toan bo mo phong
        //---------------------------------------------------------------
        `CHECK_EQ(viol, 16'd0, "TC-108: khong vi pham hop dong CSI")

        `TB_END
    end

    initial begin
        #50_000_000;
        $display("  [FAIL] TIMEOUT");
        $fatal(1, "timeout");
    end

endmodule
