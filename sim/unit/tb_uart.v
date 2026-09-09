//=============================================================================
// File   : sim/unit/tb_uart.v
// Mục đích: TC-300..302 — kiểm bộ thu/phát UART ở mức mô phỏng.
// REQ    : REQ-I-03, REQ-I-04
// Tác giả : Đội Hủ Tiếu · Ngày: 2026-09-09
//=============================================================================
// GIỚI HẠN CỦA TESTBENCH NÀY — đọc trước khi tin vào kết quả PASS.
//
// Testbench dùng nhịp bit LÝ TƯỞNG (234.375 chu kỳ, làm tròn trong mô phỏng),
// còn phần cứng thật thì host có sai số thạch anh riêng và gửi không nghỉ.
// Vì vậy TC-300..302 KHÔNG chứng minh được REQ-I-05. REQ-I-05 chỉ được chứng
// minh bởi TC-600 chạy trên board thật (REQ-V-03).
//
// Ở thiết kế trước, đúng bộ test kiểu này PASS 100% trong khi phần cứng mất
// 159/256 byte. Ghi rõ ở đây để không ai lặp lại nhầm lẫn đó.
//=============================================================================

`timescale 1ns / 1ps
`include "tb_util.vh"

module tb_uart;

    `TB_DECL

    localparam CLK_HZ  = 27_000_000;
    localparam BAUD    = 115_200;
    localparam CLK_P   = 37.037;              // ns, 27 MHz
    localparam real BIT_NS = 1.0e9 / BAUD;    // 8680.6 ns — nhịp bit THẬT

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #(CLK_P/2.0) clk = ~clk;

    // ---- bộ thu đang kiểm ----
    reg        line = 1'b1;
    wire [7:0] rx_data;
    wire       rx_valid, rx_frame_err;

    uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) dut_rx (
        .clk(clk), .rst_n(rst_n), .rx(line),
        .rx_data(rx_data), .rx_valid(rx_valid), .rx_frame_err(rx_frame_err)
    );

    // ---- bộ phát đang kiểm, nối vòng về bộ thu thứ hai ----
    reg  [7:0] tx_data = 8'd0;
    reg        tx_valid = 1'b0;
    wire       tx_ready, tx_line;

    uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) dut_tx (
        .clk(clk), .rst_n(rst_n),
        .tx_data(tx_data), .tx_valid(tx_valid), .tx_ready(tx_ready), .tx(tx_line)
    );

    wire [7:0] lb_data;
    wire       lb_valid;
    uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) dut_lb (
        .clk(clk), .rst_n(rst_n), .rx(tx_line),
        .rx_data(lb_data), .rx_valid(lb_valid), .rx_frame_err()
    );

    // ---- bộ nhận kết quả ----
    reg [7:0]  got;
    reg        got_flag;
    reg [7:0]  lb_got;
    reg        lb_flag;
    integer    err_count;

    always @(posedge clk) begin
        if (rx_valid) begin got <= rx_data; got_flag <= 1'b1; end
        if (rx_frame_err) err_count <= err_count + 1;
        if (lb_valid) begin lb_got <= lb_data; lb_flag <= 1'b1; end
    end

    // Gửi một byte vào `line` với nhịp bit thật (không làm tròn về 234 chu kỳ)
    task send_byte;
        input [7:0] b;
        integer i;
        begin
            line = 1'b0;  #(BIT_NS);              // start
            for (i = 0; i < 8; i = i + 1) begin
                line = b[i]; #(BIT_NS);           // LSB first
            end
            line = 1'b1;  #(BIT_NS);              // stop
        end
    endtask

    // Gửi byte kèm một xung nhiễu 1 chu kỳ nhịp ở giữa bit thứ `glitch_bit`
    task send_byte_glitched;
        input [7:0] b;
        input integer glitch_bit;
        integer i;
        begin
            line = 1'b0;  #(BIT_NS);
            for (i = 0; i < 8; i = i + 1) begin
                if (i == glitch_bit) begin
                    line = b[i];
                    #(BIT_NS/2.0 - CLK_P);
                    line = ~b[i];  #(CLK_P);      // nhiễu 1 chu kỳ nhịp
                    line = b[i];
                    #(BIT_NS/2.0);
                end else begin
                    line = b[i]; #(BIT_NS);
                end
            end
            line = 1'b1;  #(BIT_NS);
        end
    endtask

    task send_byte_badstop;
        input [7:0] b;
        integer i;
        begin
            line = 1'b0;  #(BIT_NS);
            for (i = 0; i < 8; i = i + 1) begin
                line = b[i]; #(BIT_NS);
            end
            line = 1'b0;  #(BIT_NS);              // stop SAI (phải là 1)
            line = 1'b1;  #(BIT_NS * 2);
        end
    endtask

    integer n;

    initial begin
        got_flag  = 1'b0;
        lb_flag   = 1'b0;
        err_count = 0;

        `TB_BEGIN("TC-300..302: lop vat ly UART")

        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (10) @(posedge clk);

        //---------------------------------------------------------------
        // TC-300a: thu mot byte
        //---------------------------------------------------------------
        got_flag = 1'b0;
        send_byte(8'hA5);
        #(BIT_NS);
        `CHECK_TRUE(got_flag, "TC-300a: nhan duoc byte")
        `CHECK_EQ(got, 8'hA5, "TC-300a: gia tri byte thu")

        got_flag = 1'b0;
        send_byte(8'h00);
        #(BIT_NS);
        `CHECK_EQ(got, 8'h00, "TC-300a: byte 0x00 (toan bit 0)")

        got_flag = 1'b0;
        send_byte(8'hFF);
        #(BIT_NS);
        `CHECK_EQ(got, 8'hFF, "TC-300a: byte 0xFF (toan bit 1)")

        //---------------------------------------------------------------
        // TC-300b: 32 byte lien tiep KHONG NGHI qua bo thu
        // Day la phep kiem gan nhat voi TC-600, nhung van khong thay the
        // duoc no: nhip bit o day la ly tuong.
        //---------------------------------------------------------------
        begin : burst
            integer ok;
            ok = 0;
            for (n = 0; n < 32; n = n + 1) begin
                got_flag = 1'b0;
                send_byte(n[7:0] ^ 8'h5A);
                // khong cho them chu ky nao — byte ke tiep di ngay
                if (got_flag && (got == (n[7:0] ^ 8'h5A))) ok = ok + 1;
            end
            `CHECK_EQ(ok, 32, "TC-300b: 32 byte lien tiep khong nghi")
        end

        //---------------------------------------------------------------
        // TC-301: bieu quyet 3 diem chong nhieu xung don
        //---------------------------------------------------------------
        begin : glitch
            integer ok, gb;
            ok = 0;
            for (gb = 0; gb < 8; gb = gb + 1) begin
                got_flag = 1'b0;
                send_byte_glitched(8'h96, gb);
                #(BIT_NS);
                if (got_flag && (got == 8'h96)) ok = ok + 1;
            end
            `CHECK_EQ(ok, 8, "TC-301: nhieu 1 chu ky o moi bit deu bi loai")
        end

        //---------------------------------------------------------------
        // TC-302: bit stop sai -> co loi khung, byte bi bo
        //---------------------------------------------------------------
        got_flag  = 1'b0;
        err_count = 0;
        send_byte_badstop(8'h3C);
        #(BIT_NS);
        `CHECK_TRUE(err_count > 0, "TC-302: bat duoc loi khung")
        `CHECK_TRUE(!got_flag,     "TC-302: byte hong khong duoc bao la hop le")

        // Sau loi khung, bo thu phai con dung duoc
        got_flag = 1'b0;
        send_byte(8'h7E);
        #(BIT_NS);
        `CHECK_EQ(got, 8'h7E, "TC-302: van thu duoc byte hop le sau loi khung")

        //---------------------------------------------------------------
        // TC-300c: bo phat -> bo thu (loopback)
        //---------------------------------------------------------------
        begin : loopback
            integer ok;
            ok = 0;
            for (n = 0; n < 8; n = n + 1) begin
                lb_flag = 1'b0;
                @(posedge clk);
                while (!tx_ready) @(posedge clk);
                tx_data  <= n[7:0] ^ 8'hC3;
                tx_valid <= 1'b1;
                @(posedge clk);
                tx_valid <= 1'b0;
                // cho het khung: 10 bit + du
                #(BIT_NS * 11);
                if (lb_flag && (lb_got == (n[7:0] ^ 8'hC3))) ok = ok + 1;
            end
            `CHECK_EQ(ok, 8, "TC-300c: phat roi thu lai dung 8/8 byte")
        end

        `TB_END
    end

    // Chặn treo vô hạn
    initial begin
        #50_000_000;
        $display("  [FAIL] TIMEOUT");
        $fatal(1, "timeout");
    end

endmodule
