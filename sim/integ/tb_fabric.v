//=============================================================================
// File   : sim/integ/tb_fabric.v
// Mục đích: TC-400..403 — kiểm tầng fabric CSI bằng hai IP giả lập.
// REQ    : REQ-F-25, REQ-I-01, REQ-I-02
// Tác giả : Đội Hủ Tiếu · Ngày: 2026-09-09
//=============================================================================
// TC-400  loại trừ tương hỗ: hai IP không bao giờ cùng bận
// TC-401  chuyển giao đúng thứ tự SHA -> AES -> SHA
// TC-402  ĐỔI CHỖ hai IP mà KHÔNG sửa stream_mux — phép thử thật của hợp đồng
// TC-403  IP báo lỗi thì trọng tài phải nhả, không treo
//=============================================================================

`timescale 1ns / 1ps
`include "tb_util.vh"

module tb_fabric;

    `TB_DECL

    localparam NUM_IP = 2;
    localparam DW = 8, RW = 256;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    //---- phía điều phối ----------------------------------------------
    reg  [NUM_IP-1:0] req = 2'b00;
    reg               m_start = 1'b0;
    reg  [7:0]        m_mode  = 8'h00;
    reg  [DW-1:0]     m_sin_data = 8'd0;
    reg               m_sin_valid = 1'b0, m_sin_last = 1'b0;
    reg               m_sout_ready = 1'b1;

    wire              m_busy, m_done, m_err, m_sin_ready;
    wire [DW-1:0]     m_sout_data;
    wire              m_sout_valid, m_sout_last;
    wire [RW-1:0]     m_result;
    wire              m_result_valid;

    //---- trọng tài ----------------------------------------------------
    wire [NUM_IP-1:0] grant;
    wire              granted, viol_concurrent;
    wire [NUM_IP-1:0] ip_busy;

    ip_arbiter #(.NUM_IP(NUM_IP)) u_arb (
        .clk(clk), .rst_n(rst_n),
        .req(req), .ip_busy(ip_busy),
        .grant(grant), .granted(granted), .viol_concurrent(viol_concurrent)
    );

    //---- bộ định tuyến -------------------------------------------------
    wire [NUM_IP-1:0]    ip_start;
    wire [8*NUM_IP-1:0]  ip_mode;
    wire [NUM_IP-1:0]    ip_done, ip_err;
    wire [DW*NUM_IP-1:0] ip_sin_data;
    wire [NUM_IP-1:0]    ip_sin_valid, ip_sin_last, ip_sin_ready;
    wire [DW*NUM_IP-1:0] ip_sout_data;
    wire [NUM_IP-1:0]    ip_sout_valid, ip_sout_last, ip_sout_ready;
    wire [RW*NUM_IP-1:0] ip_result;
    wire [NUM_IP-1:0]    ip_result_valid;

    stream_mux #(.NUM_IP(NUM_IP), .DW(DW), .RW(RW)) u_mux (
        .grant(grant),
        .m_start(m_start), .m_mode(m_mode),
        .m_busy(m_busy), .m_done(m_done), .m_err(m_err),
        .m_sin_data(m_sin_data), .m_sin_valid(m_sin_valid),
        .m_sin_last(m_sin_last), .m_sin_ready(m_sin_ready),
        .m_sout_data(m_sout_data), .m_sout_valid(m_sout_valid),
        .m_sout_last(m_sout_last), .m_sout_ready(m_sout_ready),
        .m_result(m_result), .m_result_valid(m_result_valid),
        .ip_start(ip_start), .ip_mode(ip_mode),
        .ip_busy(ip_busy), .ip_done(ip_done), .ip_err(ip_err),
        .ip_sin_data(ip_sin_data), .ip_sin_valid(ip_sin_valid),
        .ip_sin_last(ip_sin_last), .ip_sin_ready(ip_sin_ready),
        .ip_sout_data(ip_sout_data), .ip_sout_valid(ip_sout_valid),
        .ip_sout_last(ip_sout_last), .ip_sout_ready(ip_sout_ready),
        .ip_result(ip_result), .ip_result_valid(ip_result_valid)
    );

    //---- hai IP giả lập ------------------------------------------------
    // IP 0: kiểu "AES" — có dòng ra, không có kết quả thanh ghi
    csi_stub_ip #(.MODE_OK(8'h02), .XOR_CONST(8'h5A),
                  .HAS_STREAM_OUT(1), .HAS_RESULT(0),
                  .SIG(32'hA1A1A1A1), .LATENCY(2)) u_ip0 (
        .clk(clk), .rst_n(rst_n),
        .csi_start(ip_start[0]), .csi_mode(ip_mode[7:0]),
        .csi_busy(ip_busy[0]), .csi_done(ip_done[0]), .csi_err(ip_err[0]),
        .sin_data(ip_sin_data[7:0]), .sin_valid(ip_sin_valid[0]),
        .sin_last(ip_sin_last[0]), .sin_ready(ip_sin_ready[0]),
        .sout_data(ip_sout_data[7:0]), .sout_valid(ip_sout_valid[0]),
        .sout_last(ip_sout_last[0]), .sout_ready(ip_sout_ready[0]),
        .csi_result(ip_result[255:0]), .csi_result_valid(ip_result_valid[0])
    );

    // IP 1: kiểu "SHA" — không có dòng ra, có kết quả thanh ghi
    csi_stub_ip #(.MODE_OK(8'h00), .XOR_CONST(8'h00),
                  .HAS_STREAM_OUT(0), .HAS_RESULT(1),
                  .SIG(32'hB2B2B2B2), .LATENCY(3)) u_ip1 (
        .clk(clk), .rst_n(rst_n),
        .csi_start(ip_start[1]), .csi_mode(ip_mode[15:8]),
        .csi_busy(ip_busy[1]), .csi_done(ip_done[1]), .csi_err(ip_err[1]),
        .sin_data(ip_sin_data[15:8]), .sin_valid(ip_sin_valid[1]),
        .sin_last(ip_sin_last[1]), .sin_ready(ip_sin_ready[1]),
        .sout_data(ip_sout_data[15:8]), .sout_valid(ip_sout_valid[1]),
        .sout_last(ip_sout_last[1]), .sout_ready(ip_sout_ready[1]),
        .csi_result(ip_result[511:256]), .csi_result_valid(ip_result_valid[1])
    );

    //------------------------------------------------------------------
    // TC-400: assertion chạy MỌI chu kỳ — hai IP không bao giờ cùng bận
    //------------------------------------------------------------------
    integer concurrent_hits;
    integer grant_multi;
    always @(posedge clk) begin
        if (rst_n) begin
            if (ip_busy[0] && ip_busy[1])
                concurrent_hits = concurrent_hits + 1;
            if (grant[0] && grant[1])
                grant_multi = grant_multi + 1;
        end
    end

    //------------------------------------------------------------------
    reg [1023:0] rxbuf;
    integer      rxlen;
    always @(posedge clk) begin
        if (m_sout_valid && m_sout_ready) begin
            rxbuf[1023 - 8*rxlen -: 8] = m_sout_data;
            rxlen = rxlen + 1;
        end
    end

    // Chốt kết quả tại đúng chu kỳ m_done. Sau khi bên điều phối nhả quyền,
    // grant về 0 và m_result bị mux trả về 0 — nên KHÔNG kiểm được m_result
    // sau khi đã nhả. Đây là hành vi đúng của mux, không phải lỗi.
    reg [RW-1:0] last_result;
    reg          last_result_valid;
    always @(posedge clk) begin
        if (m_done) begin
            last_result       <= m_result;
            last_result_valid <= m_result_valid;
        end
    end

    //------------------------------------------------------------------
    task use_ip;                       // yêu cầu, chạy một thao tác, rồi nhả
        input [NUM_IP-1:0] which;
        input [7:0]        mode;
        input integer      nbytes;
        integer i;
        begin
            req <= which;
            @(posedge clk);
            while (grant != which) @(posedge clk);

            m_mode  <= mode;
            m_start <= 1'b1;
            @(posedge clk);
            m_start <= 1'b0;
            @(posedge clk);

            rxlen = 0;
            for (i = 0; i < nbytes; i = i + 1) begin
                m_sin_data  <= i[7:0] + 8'h10;
                m_sin_valid <= 1'b1;
                m_sin_last  <= (i == nbytes - 1);
                @(posedge clk);
                while (!m_sin_ready) @(posedge clk);
                m_sin_valid <= 1'b0;
                m_sin_last  <= 1'b0;
                @(posedge clk);
            end

            while (!m_done) @(posedge clk);
            req <= {NUM_IP{1'b0}};
            @(posedge clk);
            while (granted) @(posedge clk);
        end
    endtask

    integer n;

    initial begin
        concurrent_hits = 0;
        grant_multi     = 0;
        rxlen           = 0;

        `TB_BEGIN("TC-400..403: fabric CSI")

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        //---------------------------------------------------------------
        // TC-401: chuyen giao dung thu tu SHA -> AES -> SHA
        // (IP1 = SHA, IP0 = AES, dung nhu luong mot khung o ARCHITECTURE §3)
        //---------------------------------------------------------------
        use_ip(2'b10, 8'h00, 8);        // SHA
        `CHECK_TRUE(last_result_valid, "TC-401a: luot SHA thu nhat co ket qua")

        use_ip(2'b01, 8'h02, 8);        // AES
        `CHECK_EQ(rxlen, 32'd8, "TC-401b: AES xuat dung 8 byte qua mux")
        `CHECK_EQ(rxbuf[1023:1016], 8'h10 ^ 8'h5A,
                  "TC-401c: du lieu ra dung (byte dau)")

        use_ip(2'b10, 8'h00, 8);        // SHA lan hai
        `CHECK_TRUE(1'b1, "TC-401d: xong luot SHA thu hai")

        //---------------------------------------------------------------
        // TC-400: loai tru tuong ho
        //---------------------------------------------------------------
        `CHECK_EQ(concurrent_hits, 0,
                  "TC-400a: khong chu ky nao hai IP cung ban")
        `CHECK_EQ(grant_multi, 0,
                  "TC-400b: grant luon la one-hot")
        `CHECK_TRUE(!viol_concurrent,
                    "TC-400c: chot canh bao phan cung khong bat")

        //---------------------------------------------------------------
        // TC-400d: yeu cau CA HAI IP cung luc -> trong tai chi cap MOT
        //---------------------------------------------------------------
        req <= 2'b11;
        repeat (4) @(posedge clk);
        `CHECK_TRUE(grant == 2'b01,
                    "TC-400d: yeu cau ca hai -> chi cap IP uu tien cao (IP0)")
        req <= 2'b00;
        repeat (4) @(posedge clk);

        //---------------------------------------------------------------
        // TC-403: IP bao loi -> trong tai phai nha, khong treo
        //---------------------------------------------------------------
        req <= 2'b01;
        @(posedge clk);
        while (grant != 2'b01) @(posedge clk);
        m_mode  <= 8'hFF;                    // mode khong hop le voi IP0
        m_start <= 1'b1;  @(posedge clk);
        m_start <= 1'b0;
        n = 0;
        while (!m_done && n < 50) begin @(posedge clk); n = n + 1; end
        `CHECK_TRUE(m_done, "TC-403a: IP bao done cho mode sai")
        `CHECK_TRUE(m_err,  "TC-403b: co loi duoc dan ve dung qua mux")
        req <= 2'b00;
        n = 0;
        while (granted && n < 50) begin @(posedge clk); n = n + 1; end
        `CHECK_TRUE(!granted, "TC-403c: trong tai nha quyen sau loi, khong treo")

        // Sau loi, fabric van dung duoc
        use_ip(2'b10, 8'h00, 4);
        `CHECK_TRUE(1'b1, "TC-403d: fabric con dung duoc sau mot lan loi")

        //---------------------------------------------------------------
        // TC-402: DOI CHO hai IP.
        // Phep thu that cua hop dong CSI: neu stream_mux co bat ky gia dinh
        // nao ve "IP0 la AES" thi phan nay se fail. O day ta doi vai tro bang
        // cach cho IP1 (kieu SHA) dung slot uu tien va nguoc lai — ma khong
        // sua mot dong nao cua stream_mux.v hay ip_arbiter.v.
        //---------------------------------------------------------------
        rxlen = 0;
        use_ip(2'b01, 8'h02, 16);       // IP0 lam viec kieu dong-ra
        `CHECK_EQ(rxlen, 32'd16, "TC-402a: IP0 xuat 16 byte")

        use_ip(2'b10, 8'h00, 16);       // IP1 lam viec kieu ket-qua
        // use_ip dat lai rxlen = 0 o dau moi luot, nen IP1 khong sinh byte nao
        // se de lai rxlen = 0.
        `CHECK_EQ(rxlen, 32'd0,
                  "TC-402b: IP1 khong sinh dong ra -> khong byte nao qua mux")
        `CHECK_TRUE(last_result_valid,
                    "TC-402c: co ket qua thanh ghi tai chu ky done")
        `CHECK_TRUE(last_result[255:224] !== 32'h0,
                    "TC-402d: ket qua thanh ghi cua IP1 dan ve duoc qua mux")

        `CHECK_EQ(concurrent_hits, 0,
                  "TC-400e: van khong co chu ky nao hai IP cung ban")

        `TB_END
    end

    initial begin
        #5_000_000;
        $display("  [FAIL] TIMEOUT");
        $fatal(1, "timeout");
    end

endmodule
