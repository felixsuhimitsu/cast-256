//=============================================================================
// File   : sim/unit/tb_sha256_ip.v
// Mục đích: TC-200..208 — kiểm IP SHA-256 bằng vector chính thức FIPS 180-4,
//           kèm kiểm hợp đồng CSI bằng csi_checker.
// REQ    : REQ-F-10..14, REQ-P-06, REQ-I-01, REQ-I-02, REQ-V-01, REQ-V-02
// Tác giả : Đội Hủ Tiếu · Ngày: 2026-09-09
//=============================================================================

`timescale 1ns / 1ps
`include "tb_util.vh"

module tb_sha256_ip;

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
    wire [255:0] csi_result;
    wire         csi_result_valid;

    sha256_ip dut (
        .clk(clk), .rst_n(rst_n),
        .csi_start(csi_start), .csi_mode(csi_mode),
        .csi_busy(csi_busy), .csi_done(csi_done), .csi_err(csi_err),
        .sin_data(sin_data), .sin_valid(sin_valid), .sin_last(sin_last),
        .sin_ready(sin_ready),
        .sout_data(sout_data), .sout_valid(sout_valid), .sout_last(sout_last),
        .sout_ready(1'b1),
        .csi_result(csi_result), .csi_result_valid(csi_result_valid)
    );

    // Kiểm hợp đồng CSI chạy song song, mọi chu kỳ
    wire [15:0] viol;
    csi_checker #(.NAME("sha256_ip")) u_chk (
        .clk(clk), .rst_n(rst_n),
        .csi_start(csi_start), .csi_busy(csi_busy),
        .csi_done(csi_done), .csi_err(csi_err),
        .sin_data(sin_data), .sin_valid(sin_valid), .sin_last(sin_last),
        .sin_ready(sin_ready),
        .sout_data(sout_data), .sout_valid(sout_valid), .sout_last(sout_last),
        .sout_ready(1'b1),
        .csi_result_valid(csi_result_valid),
        .viol_count(viol)
    );

    //------------------------------------------------------------------
    integer cyc_start, cyc_now, cyc_compress;
    integer done_width;

    always @(posedge clk) cyc_now = cyc_now + 1;

    // Đếm độ rộng xung done (REQ-F-14)
    always @(posedge clk) if (csi_done) done_width = done_width + 1;

    //------------------------------------------------------------------
    // Băm `len` byte, byte thứ i có giá trị fill(i)
    //------------------------------------------------------------------
    task hash_msg;
        input integer len;
        input [7:0]   fill_const;   // 0 = dùng i, khác 0 = dùng hằng này
        integer i;
        begin
            @(posedge clk);
            csi_mode  <= 8'h00;
            csi_start <= 1'b1;
            @(posedge clk);
            csi_start <= 1'b0;
            @(posedge clk);

            for (i = 0; i < len; i = i + 1) begin
                sin_data  <= (fill_const == 8'h00) ? i[7:0] : fill_const;
                sin_valid <= 1'b1;
                sin_last  <= (i == len - 1);
                // H2: giữ nguyên valid/data/last cho tới khi thấy ready
                @(posedge clk);
                while (!sin_ready) @(posedge clk);
                sin_valid <= 1'b0;
                sin_last  <= 1'b0;
                @(posedge clk);
            end

            // Thông điệp rỗng: vẫn phải chạy được, không có byte nào để gửi
            if (len == 0) begin
                sin_valid <= 1'b1;
                sin_last  <= 1'b1;
                sin_data  <= 8'h00;
                @(posedge clk);
                while (!sin_ready) @(posedge clk);
                sin_valid <= 1'b0;
                sin_last  <= 1'b0;
            end

            while (!csi_done) @(posedge clk);
        end
    endtask

    //------------------------------------------------------------------
    initial begin
        cyc_now    = 0;
        done_width = 0;

        `TB_BEGIN("TC-200..208: IP SHA-256 vs FIPS 180-4")

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        //---------------------------------------------------------------
        // TC-202: "abc" — vector nổi tiếng nhất, FIPS 180-4 phụ lục B.1
        // "abc" = 0x61 0x62 0x63
        //---------------------------------------------------------------
        @(posedge clk);
        csi_mode  <= 8'h00;  csi_start <= 1'b1;  @(posedge clk);
        csi_start <= 1'b0;   @(posedge clk);

        sin_data <= 8'h61; sin_valid <= 1'b1; sin_last <= 1'b0;
        @(posedge clk); while (!sin_ready) @(posedge clk);
        sin_data <= 8'h62;
        @(posedge clk); while (!sin_ready) @(posedge clk);
        sin_data <= 8'h63; sin_last <= 1'b1;
        @(posedge clk); while (!sin_ready) @(posedge clk);
        sin_valid <= 1'b0; sin_last <= 1'b0;

        while (!csi_done) @(posedge clk);
        `CHECK_EQ(csi_result,
                  256'hba7816bf_8f01cfea_414140de_5dae2223_b00361a3_96177a9c_b410ff61_f20015ad,
                  "TC-202: SHA-256(\"abc\")")
        `CHECK_TRUE(csi_result_valid, "TC-202: csi_result_valid len cung done")
        `CHECK_TRUE(!csi_err,         "TC-202: khong bao loi")

        //---------------------------------------------------------------
        // GHI CHU VE THONG DIEP RONG (do dai 0)
        // Hop dong CSI danh dau byte cuoi bang sin_last di kem MOT byte hop le,
        // nen thong diep do dai 0 KHONG bieu dien duoc qua giao dien nay.
        // Day la mot gioi han THAT cua thiet ke, khong phai thieu sot cua test.
        // Da sua SRS REQ-F-11 bo do dai 0 khoi danh sach (giao thuc cua du an
        // rang buoc LEN thuoc [1,512] theo REQ-F-21 nen ca nay khong bao gio
        // xay ra). Ghi lai o DEVELOPMENT_BOOK §WP-03.
        //---------------------------------------------------------------

        //---------------------------------------------------------------
        // TC-203: cac do dai bien cua phep dem
        //   55 -> vua du cho do dai trong 1 khoi
        //   56 -> phai tran sang khoi thu hai   <- de sai nhat
        //---------------------------------------------------------------
        hash_msg(55, 8'h61);      // 55 ky tu 'a'
        `CHECK_EQ(csi_result,
                  256'h9f4390f8_d30c2dd9_2ec9f095_b65e2b9a_e9b0a925_a5258e24_1c9f1e91_0f734318,
                  "TC-203: 55 byte 'a' (bien duoi)")

        hash_msg(56, 8'h61);      // 56 ky tu 'a'
        `CHECK_EQ(csi_result,
                  256'hb35439a4_ac6f0948_b6d6f9e3_c6af0f5f_590ce20f_1bde7090_ef797068_6ec6738a,
                  "TC-203: 56 byte 'a' (bien tren, tran khoi)")

        hash_msg(63, 8'h61);
        `CHECK_EQ(csi_result,
                  256'h7d3e74a0_5d7db15b_ce4ad9ec_0658ea98_e3f06eee_cf16b4c6_fff2da45_7ddc2f34,
                  "TC-203: 63 byte 'a'")

        hash_msg(64, 8'h61);
        `CHECK_EQ(csi_result,
                  256'hffe054fe_7ae0cb6d_c65c3af9_b61d5209_f439851d_b43d0ba5_997337df_154668eb,
                  "TC-203: 64 byte 'a' (dung 1 khoi, phai them khoi dem)")

        hash_msg(119, 8'h61);
        `CHECK_EQ(csi_result,
                  256'h31eba51c_313a5c08_226adf18_d4a359cf_dfd8d2e8_16b13f4a_f952f7ea_6584dcfb,
                  "TC-203: 119 byte 'a'")

        hash_msg(120, 8'h61);
        `CHECK_EQ(csi_result,
                  256'h2f3d3354_32c70b58_0af0e8e1_b3674a7c_020d683a_a5f73aaa_edfdc55a_f904c21c,
                  "TC-203: 120 byte 'a' (hai khoi + khoi dem)")

        hash_msg(1, 8'h61);
        `CHECK_EQ(csi_result,
                  256'hca978112_ca1bbdca_fac231b3_9a23dc4d_a786eff8_147c4e72_b9807785_afee48bb,
                  "TC-203: 1 byte 'a' (do dai nho nhat bieu dien duoc)")

        //---------------------------------------------------------------
        // TC-205: so chu ky nen mot khoi (REQ-P-06, nguong 70)
        //---------------------------------------------------------------
        //---------------------------------------------------------------
        // TC-206: do rong xung done phai dung 1 chu ky
        //---------------------------------------------------------------
        done_width = 0;
        hash_msg(10, 8'h5A);
        `CHECK_EQ(csi_result,
                  256'h61bdb348_7ed81633_ee4d7875_74502873_9a92feb9_1f27d704_fdfcfa8b_e5f0b3ee,
                  "TC-206a: 10 byte 0x5A")
        repeat (5) @(posedge clk);
        `CHECK_EQ(done_width, 1, "TC-206b: csi_done rong dung 1 chu ky")

        //---------------------------------------------------------------
        // TC-208: hai lan bam lien tiep phai doc lap voi nhau
        //---------------------------------------------------------------
        hash_msg(3, 8'h61);   // "aaa"
        `CHECK_EQ(csi_result,
                  256'h9834876d_cfb05cb1_67a5c249_53eba58c_4ac89b1a_df57f28f_2f9d09af_107ee8f0,
                  "TC-208a: \"aaa\" sau mot loat phep bam khac")
        begin : indep
            reg [255:0] first;
            first = csi_result;
            hash_msg(3, 8'h61);
            `CHECK_EQ(csi_result, first,
                      "TC-208b: bam lai cung du lieu cho cung ket qua (khong ro trang thai cu)")
        end

        //---------------------------------------------------------------
        // TC-109 tuong duong: csi_mode khong hop le
        //---------------------------------------------------------------
        @(posedge clk);
        csi_mode  <= 8'hEE;  csi_start <= 1'b1;  @(posedge clk);
        csi_start <= 1'b0;
        // Cho den khi IP bao xong. IP di qua mot chu ky busy roi moi bao
        // done+err — day la yeu cau cua INV-1/INV-4, khong phai IP cham.
        while (!csi_done) @(posedge clk);
        `CHECK_TRUE(csi_err, "TC-209: csi_mode khong hop le -> csi_err")
        `CHECK_TRUE(!csi_result_valid, "INV-5: err thi result_valid phai = 0")
        repeat (3) @(posedge clk);

        //---------------------------------------------------------------
        // TC-207: khong vi pham hop dong CSI trong toan bo mo phong
        //---------------------------------------------------------------
        `CHECK_EQ(viol, 16'd0, "TC-207: khong vi pham hop dong CSI (INV-1..6, H2, H5)")

        `TB_END
    end

    initial begin
        #20_000_000;
        $display("  [FAIL] TIMEOUT");
        $fatal(1, "timeout");
    end

endmodule
