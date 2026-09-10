//=============================================================================
// File   : sim/integ/tb_top.v
// Mục đích: TC-500..508 — kiểm toàn hệ qua chính chân UART, gồm cả các kịch
//           bản lỗi.
// REQ    : REQ-F-20..25
// Tác giả : Đội Hủ Tiếu · Ngày: 2026-09-09
//=============================================================================
// Testbench này lái thiết kế qua ĐÚNG hai chân UART như host thật, không thò
// tay vào tín hiệu bên trong. Nhờ vậy nó kiểm được cả đường đi thật của dữ liệu.
//
// GIỚI HẠN: nhịp bit ở đây là lý tưởng và các byte có khoảng nghỉ. Vì vậy nó
// KHÔNG chứng minh được REQ-I-05 hay REQ-P-02..04 — những cái đó chỉ có TC-600
// và TC-602 trên board thật mới chứng minh được (REQ-V-03).
//
// Để mô phỏng chạy trong thời gian chấp nhận được, dùng BAUD giả lập cao
// (CLK_HZ/16) thay vì 115200. Logic giao thức không phụ thuộc tốc độ baud.
//=============================================================================

`timescale 1ns / 1ps
`include "tb_util.vh"

module tb_top;

    `TB_DECL

    localparam CLK_HZ = 27_000_000;
    localparam BAUD   = CLK_HZ / 16;      // 16 chu kỳ mỗi bit, chỉ để chạy nhanh
    localparam CLK_P  = 37.037;
    localparam real BIT_NS = 1.0e9 / BAUD;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #(CLK_P/2.0) clk = ~clk;

    reg  line = 1'b1;
    wire dut_tx;
    wire led0_n, led1_n, led2_n;

    // WDOG_BITS nho de mo phong kiem duoc REQ-F-24 trong thoi gian hop ly.
    // 4096 chu ky ~ 25 byte-time o baud gia lap; du dai de khong cat nham khung
    // dang toi (byte cach nhau ~160 chu ky), du ngan de test chay duoc.
    top_secure_link #(.CLK_HZ(CLK_HZ), .BAUD(BAUD), .WDOG_BITS(12)) dut (
        .clk_27m(clk), .rst_n(rst_n),
        .uart_rx_pin(line), .uart_tx_pin(dut_tx),
        .led0_n(led0_n), .led1_n(led1_n), .led2_n(led2_n)
    );

    //------------------------------------------------------------------
    // Bộ thu phía host
    //------------------------------------------------------------------
    wire [7:0] host_rx_data;
    wire       host_rx_valid;
    uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_host_rx (
        .clk(clk), .rst_n(rst_n), .rx(dut_tx),
        .rx_data(host_rx_data), .rx_valid(host_rx_valid), .rx_frame_err()
    );

    integer rxn;
    reg [7:0] rxbuf [0:1023];
    always @(posedge clk) begin
        if (host_rx_valid) begin
            rxbuf[rxn] = host_rx_data;
            rxn = rxn + 1;
        end
    end

    //------------------------------------------------------------------
    task send_byte;
        input [7:0] b;
        integer i;
        begin
            line = 1'b0; #(BIT_NS);
            for (i = 0; i < 8; i = i + 1) begin
                line = b[i]; #(BIT_NS);
            end
            line = 1'b1; #(BIT_NS * 2);     // stop + khoảng nghỉ
        end
    endtask

    //------------------------------------------------------------------
    // GIÁ TRỊ KỲ VỌNG — sinh từ hiện thực tham chiếu (python hashlib +
    // cryptography) với đúng khóa trong rtl/config/keys.vh:
    //
    //   payload  3c21066b48ad92f7d4391e036045aa8f      (16 byte)
    //   IV       000102030405060708090a0b0c0d0e0f
    //   DIG_IN   = SHA-256(LEN‖IV‖payload)     -> gửi lên FPGA
    //   CT_EXP   = AES-256-CTR(payload)        -> mong đợi nhận về
    //   DIG_OUT  = SHA-256(LEN‖IV‖CT)          -> mong đợi nhận về
    //
    // Nhờ vậy TC-500 kiểm được TRỌN VẸN đường đi: mở khung -> SHA -> so digest
    // -> AES -> SHA -> đóng khung -> phát. Không có phép kiểm dương này thì cả
    // testbench chỉ chứng minh "FPGA im lặng", điều mà một thiết kế chết cũng
    // làm được (DEFINITION_OF_DONE §4, kiểu Done giả số 1).
    //------------------------------------------------------------------
    localparam [255:0] DIG_IN  =
        256'h8a5b63d90f008d569c7831cd38f6a17b57ebaa5bf4a533aec0f3c918fd3000d0;
    localparam [127:0] CT_EXP  = 128'h8b9e3c36bc941b2a43c9e4948b8b85c5;
    localparam [255:0] DIG_OUT =
        256'h13c6f553df4505a12705b52b5d9a73ec509c5abd299ae9551f46f464ea97b444;

    reg [7:0]  pt   [0:63];
    reg [7:0]  ivb  [0:15];
    reg [7:0]  dig  [0:31];
    integer    plen;
    integer    i, j;

    task send_frame;
        input integer corrupt_payload;   // 1 = lật 1 bit trong payload
        input integer corrupt_digest;    // 1 = lật 1 bit trong digest
        input integer truncate_after;    // >0 = dừng sau ngần ấy byte
        integer k, sent;
        begin
            // KHONG dat lai rxn o day: TC-508 can cong don so byte cua HAI
            // khung lien tiep. Moi cho goi deu tu dat rxn = 0 truoc khi goi.
            sent = 0;
            send_byte(8'hA5);                       sent = sent + 1;
            if (truncate_after == 0 || sent < truncate_after) begin
            send_byte(8'h5A);                       sent = sent + 1; end
            if (truncate_after == 0 || sent < truncate_after) begin
            send_byte(plen[15:8]);                  sent = sent + 1; end
            if (truncate_after == 0 || sent < truncate_after) begin
            send_byte(plen[7:0]);                   sent = sent + 1; end
            for (k = 0; k < 16; k = k + 1)
                if (truncate_after == 0 || sent < truncate_after) begin
                    send_byte(ivb[k]);              sent = sent + 1; end
            for (k = 0; k < plen; k = k + 1)
                if (truncate_after == 0 || sent < truncate_after) begin
                    send_byte(corrupt_payload && (k == 0) ? (pt[k] ^ 8'h01) : pt[k]);
                    sent = sent + 1; end
            for (k = 0; k < 32; k = k + 1)
                if (truncate_after == 0 || sent < truncate_after) begin
                    send_byte(corrupt_digest && (k == 31) ? (dig[k] ^ 8'h80) : dig[k]);
                    sent = sent + 1; end
        end
    endtask

    task wait_quiet;
        input integer nbits;
        begin
            #(BIT_NS * nbits);
        end
    endtask

    //------------------------------------------------------------------
    initial begin
        rxn  = 0;
        plen = 16;

        `TB_BEGIN("TC-500..508: toan he qua chan UART")

        for (i = 0; i < 64; i = i + 1) pt[i]  = (i * 8'd29) ^ 8'h3C;
        for (i = 0; i < 16; i = i + 1) ivb[i] = i[7:0];
        for (i = 0; i < 32; i = i + 1) dig[i] = DIG_IN[255 - 8*i -: 8];

        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (200) @(posedge clk);       // chờ nạp khóa AES xong

        //---------------------------------------------------------------
        // TC-500: KHUNG HOP LE — phep kiem DUONG, quan trong nhat trong file
        //---------------------------------------------------------------
        rxn = 0;
        send_frame(0, 0, 0);
        wait_quiet(3000);

        // 2 preamble + 2 LEN + 16 IV + 16 ciphertext + 32 digest = 68 byte.
        // (Ban dau toi ghi 52 — cong sai. Thiet ke dung, phep dem sai.)
        `CHECK_EQ(rxn, 32'd68,
                  "TC-500a: nhan du 2+2+16+16+32 = 68 byte")
        if (rxn >= 68) begin
            `CHECK_EQ({rxbuf[0], rxbuf[1]}, 16'hA55A, "TC-500b: preamble tra ve")
            `CHECK_EQ({rxbuf[2], rxbuf[3]}, 16'd16,   "TC-500c: LEN tra ve")
            `CHECK_EQ({rxbuf[4], rxbuf[5], rxbuf[6], rxbuf[7]}, 32'h00010203,
                      "TC-500d: IV tra ve (4 byte dau)")
            `CHECK_EQ({rxbuf[20], rxbuf[21], rxbuf[22], rxbuf[23]},
                      CT_EXP[127:96],
                      "TC-500e: ban ma AES-256-CTR dung (4 byte dau)")
            `CHECK_EQ({rxbuf[32], rxbuf[33], rxbuf[34], rxbuf[35]},
                      CT_EXP[31:0],
                      "TC-500f: ban ma AES-256-CTR dung (4 byte cuoi)")
            `CHECK_EQ({rxbuf[36], rxbuf[37], rxbuf[38], rxbuf[39]},
                      DIG_OUT[255:224],
                      "TC-500g: digest tra ve dung (4 byte dau)")
            `CHECK_EQ({rxbuf[64], rxbuf[65], rxbuf[66], rxbuf[67]},
                      DIG_OUT[31:0], "TC-500h: digest tra ve dung (4 byte cuoi)")
        end
        // Khong phat thua: doi them mot lat, so byte phai KHONG doi
        begin : no_extra
            integer before;
            before = rxn;
            wait_quiet(500);
            `CHECK_EQ(rxn, before, "TC-500i: khong phat them byte nao sau khung")
        end

        //---------------------------------------------------------------
        // TC-503: lat 1 bit trong digest -> phai IM LANG
        //---------------------------------------------------------------
        rxn = 0;
        send_frame(0, 1, 0);
        wait_quiet(3000);
        `CHECK_EQ(rxn, 32'd0, "TC-503: lat 1 bit digest -> KHONG phat gi ca")

        //---------------------------------------------------------------
        // TC-504 / TC-505: LEN ngoai [1,512]
        //---------------------------------------------------------------
        rxn = 0;
        send_byte(8'hA5); send_byte(8'h5A);
        send_byte(8'h00); send_byte(8'h00);            // LEN = 0
        for (i = 0; i < 16; i = i + 1) send_byte(ivb[i]);
        wait_quiet(300);
        `CHECK_EQ(rxn, 32'd0, "TC-504: LEN = 0 -> khung bi loai")

        rxn = 0;
        send_byte(8'hA5); send_byte(8'h5A);
        send_byte(8'h04); send_byte(8'h00);            // LEN = 1024 > 512
        for (i = 0; i < 16; i = i + 1) send_byte(ivb[i]);
        wait_quiet(300);
        `CHECK_EQ(rxn, 32'd0, "TC-505: LEN = 1024 -> khung bi loai")

        //---------------------------------------------------------------
        // TC-506: khung cat giua chung, roi khung tiep theo van phai nhan
        // duoc. Watchdog that su la 2^24 chu ky nen o day ta khong cho het;
        // thay vao do dua mot preamble moi va kiem rang bo mo khung khong
        // treo vinh vien o trang thai cu.
        //---------------------------------------------------------------
        rxn = 0;
        send_frame(0, 0, 10);              // cat sau 10 byte
        wait_quiet(200);
        `CHECK_EQ(rxn, 32'd0, "TC-506a: khung cat -> khong phat gi")

        // Cho watchdog kich hoat roi gui mot khung HOP LE.
        // Day la cap A+B cua REQ-V-04: pha A la khung cat (im lang), pha B
        // chung minh he thong da phuc hoi chu khong phai da chet.
        wait_quiet(600);
        rxn = 0;
        send_frame(0, 0, 0);
        wait_quiet(3000);
        `CHECK_EQ(rxn, 32'd68,
                  "TC-506b: sau watchdog, khung hop le tiep theo chay dung")

        //---------------------------------------------------------------
        // TC-501: 32 byte rac truoc preamble hop le van phai nhan dung.
        // Ket hop voi TC-500: day la lan dau ta CHUA biet digest dung, nen
        // chi kiem rang he thong khong phat gi (digest van sai).
        //---------------------------------------------------------------
        rxn = 0;
        for (i = 0; i < 32; i = i + 1) send_byte(i[7:0] ^ 8'hF0);
        send_frame(0, 0, 0);
        wait_quiet(3000);
        `CHECK_EQ(rxn, 32'd68,
                  "TC-501: 32 byte rac truoc preamble -> VAN nhan dung khung")

        //---------------------------------------------------------------
        // TC-502: lat 1 bit trong payload -> im lang (digest da sai san,
        // nen phep kiem nay chi cung co them)
        //---------------------------------------------------------------
        rxn = 0;
        send_frame(1, 0, 0);
        wait_quiet(3000);
        `CHECK_EQ(rxn, 32'd0, "TC-502: lat 1 bit payload -> im lang")

        //---------------------------------------------------------------
        // Sau tat ca cac khung hong, he thong phai CON SONG.
        // Day la nguyen tac REQ-V-04 ap dung o muc mo phong: mot loat phep
        // kiem "khong co phan hoi" ma khong co phep kiem lieveness nao thi
        // van PASS ca khi thiet ke da chet hoan toan.
        //
        // Kiem lieveness: bo mo khung phai quay ve trang thai quet, tuc la
        // den bao nhan (led0_n) khong bi ket o muc sang.
        //---------------------------------------------------------------
        // LIVENESS sau moi khung hong: gui mot khung HOP LE va doi phan hoi.
        // Day la ap dung REQ-V-04 o muc mo phong — mot loat phep kiem "khong
        // co phan hoi" ma khong co phep kiem duong nao thi van PASS ngay ca khi
        // thiet ke da chet hoan toan.
        rxn = 0;
        send_frame(0, 0, 0);
        wait_quiet(3000);
        `CHECK_EQ(rxn, 32'd68,
                  "LIVENESS: sau tat ca khung hong, khung hop le VAN chay dung")

        wait_quiet(100);
        `CHECK_TRUE(led0_n === 1'b1,
                    "LIVENESS: bo mo khung da ve trang thai quet, khong treo")
        `CHECK_TRUE(led1_n === 1'b1,
                    "LIVENESS: engine mat ma khong bi ket o trang thai ban")
        `CHECK_TRUE(dut.u_arb.viol_concurrent === 1'b0,
                    "TC-400 muc he thong: khong vi pham loai tru tuong ho")

        //---------------------------------------------------------------
        // TC-508: hai khung lien tiep — bo mo khung phai xu ly duoc ca hai
        //---------------------------------------------------------------
        rxn = 0;
        send_frame(0, 0, 0);
        wait_quiet(3000);
        send_frame(0, 0, 0);
        wait_quiet(3000);
        `CHECK_EQ(rxn, 32'd136, "TC-508: hai khung lien tiep -> hai phan hoi")
        `CHECK_TRUE(led0_n === 1'b1, "TC-508: van khong treo sau hai khung")

        `TB_END
    end

    initial begin
        #200_000_000;
        $display("  [FAIL] TIMEOUT");
        $fatal(1, "timeout");
    end

endmodule
