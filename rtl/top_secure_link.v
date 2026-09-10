//=============================================================================
// File   : rtl/top_secure_link.v
// Mục đích: Đỉnh thiết kế. Nối bốn tầng io / protocol / fabric / ip lại với nhau.
// REQ    : REQ-N-01, REQ-N-03, REQ-C-03
// Tác giả : Đội Hủ Tiếu · Ngày: 2026-09-09
//=============================================================================
// Đây là module DUY NHẤT được phép tham chiếu rtl/config/keys.vh
// (MODULE_MAP §4 quy tắc 4, `make lint` cưỡng chế).
//
// MỘT MIỀN XUNG NHỊP DUY NHẤT 27.0 MHz. Không CDC, không FIFO bất đồng bộ.
// CDC duy nhất trong thiết kế nằm bên trong uart_rx (đồng bộ chân RX).
//
// Reset: assert bất đồng bộ từ nút bấm, de-assert ĐỒNG BỘ qua hai tầng DFF.
//=============================================================================

`timescale 1ns / 1ps

`include "config/keys.vh"

module top_secure_link #(
    parameter CLK_HZ = 27_000_000,
    parameter BAUD   = 115_200,
    parameter AW     = 9,
    parameter NUM_IP = 2,
    parameter WDOG_BITS = 24
) (
    input  wire clk_27m,
    input  wire rst_n,
    input  wire uart_rx_pin,
    output wire uart_tx_pin,
    output wire led0_n,
    output wire led1_n,
    output wire led2_n
);

    localparam IP_AES = 0;
    localparam IP_SHA = 1;

    //------------------------------------------------------------------
    // Đồng bộ nhả reset
    //------------------------------------------------------------------
    reg rst_meta, rst_sync;
    always @(posedge clk_27m or negedge rst_n) begin
        if (!rst_n) begin
            rst_meta <= 1'b0;
            rst_sync <= 1'b0;
        end else begin
            rst_meta <= 1'b1;
            rst_sync <= rst_meta;
        end
    end
    wire rstn = rst_sync;

    //------------------------------------------------------------------
    // Tầng io/
    //------------------------------------------------------------------
    wire [7:0] rx_data;
    wire       rx_valid_raw;
    wire       rx_frame_err;

    uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_urx (
        .clk(clk_27m), .rst_n(rstn), .rx(uart_rx_pin),
        .rx_data(rx_data), .rx_valid(rx_valid_raw), .rx_frame_err(rx_frame_err)
    );

    wire [7:0] tx_data;
    wire       tx_valid, tx_ready;

    uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_utx (
        .clk(clk_27m), .rst_n(rstn),
        .tx_data(tx_data), .tx_valid(tx_valid), .tx_ready(tx_ready),
        .tx(uart_tx_pin)
    );

    //------------------------------------------------------------------
    // Tầng protocol/
    //------------------------------------------------------------------
    wire        engine_busy;

    // Bỏ qua byte đến trong lúc đang xử lý khung trước. Bộ đệm chỉ có một bản
    // sao, nên nhận khung mới khi khung cũ chưa xử lý xong sẽ ghi đè dữ liệu
    // đang dùng. Giao thức là hỏi–đáp nên trường hợp này không xảy ra trong sử
    // dụng bình thường; khung đến sớm bị bỏ và host sẽ gửi lại.
    wire rx_valid = rx_valid_raw && !engine_busy;

    wire          rxf_we;
    wire [AW-1:0] rxf_waddr;
    wire [7:0]    rxf_wdata;
    wire [15:0]   len;
    wire [127:0]  iv;
    wire [255:0]  digest_rx;
    wire          frame_ready, frame_drop, rx_busy;

    frame_rx #(.MAX_LEN(512), .AW(AW), .WDOG_BITS(WDOG_BITS)) u_frx (
        .clk(clk_27m), .rst_n(rstn),
        .rx_data(rx_data), .rx_valid(rx_valid),
        .buf_we(rxf_we), .buf_waddr(rxf_waddr), .buf_wdata(rxf_wdata),
        .len(len), .iv(iv), .digest_rx(digest_rx),
        .frame_ready(frame_ready), .frame_drop(frame_drop), .busy(rx_busy)
    );

    //------------------------------------------------------------------
    // Bộ đệm khung — một cổng ghi, một cổng đọc.
    // Ghi: frame_rx khi đang nhận, session_fsm khi ghi đè bản mã.
    // Đọc: session_fsm khi nạp cho IP, frame_tx khi phát.
    // Hai bên không bao giờ chạy cùng lúc nên bộ chọn ở đây là đủ; thêm cổng
    // thứ hai cho bộ đệm sẽ tốn gấp đôi BSRAM mà không được gì.
    //------------------------------------------------------------------
    wire          ses_we;
    wire [AW-1:0] ses_waddr, ses_raddr;
    wire [7:0]    ses_wdata;
    wire [AW-1:0] tx_raddr;
    wire          tx_active;

    wire          buf_we    = rx_busy ? rxf_we    : ses_we;
    wire [AW-1:0] buf_waddr = rx_busy ? rxf_waddr : ses_waddr;
    wire [7:0]    buf_wdata = rx_busy ? rxf_wdata : ses_wdata;
    wire [AW-1:0] buf_raddr = tx_active ? tx_raddr : ses_raddr;
    wire [7:0]    buf_rdata;

    frame_buffer #(.DEPTH(512), .AW(AW)) u_buf (
        .clk(clk_27m),
        .we(buf_we), .waddr(buf_waddr), .wdata(buf_wdata),
        .raddr(buf_raddr), .rdata(buf_rdata)
    );

    //------------------------------------------------------------------
    // Tầng fabric/
    //------------------------------------------------------------------
    wire [NUM_IP-1:0] req, grant, ip_busy;
    wire              granted, viol_concurrent;

    ip_arbiter #(.NUM_IP(NUM_IP)) u_arb (
        .clk(clk_27m), .rst_n(rstn),
        .req(req), .ip_busy(ip_busy),
        .grant(grant), .granted(granted), .viol_concurrent(viol_concurrent)
    );

    wire        m_start, m_busy, m_done, m_err;
    wire [7:0]  m_mode, m_sin_data, m_sout_data;
    wire        m_sin_valid, m_sin_last, m_sin_ready;
    wire        m_sout_valid, m_sout_last, m_sout_ready;
    wire [255:0] m_result;
    wire         m_result_valid;

    wire [NUM_IP-1:0]    ip_start, ip_done, ip_err;
    wire [8*NUM_IP-1:0]  ip_mode;
    wire [8*NUM_IP-1:0]  ip_sin_data, ip_sout_data;
    wire [NUM_IP-1:0]    ip_sin_valid, ip_sin_last, ip_sin_ready;
    wire [NUM_IP-1:0]    ip_sout_valid, ip_sout_last, ip_sout_ready;
    wire [256*NUM_IP-1:0] ip_result;
    wire [NUM_IP-1:0]    ip_result_valid;

    stream_mux #(.NUM_IP(NUM_IP), .DW(8), .RW(256)) u_mux (
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

    //------------------------------------------------------------------
    // Tầng ip/ — hai IP, cùng một hình dạng cổng
    //------------------------------------------------------------------
    aes256_ctr_ip u_aes (
        .clk(clk_27m), .rst_n(rstn),
        .csi_start(ip_start[IP_AES]), .csi_mode(ip_mode[8*IP_AES +: 8]),
        .csi_busy(ip_busy[IP_AES]), .csi_done(ip_done[IP_AES]),
        .csi_err(ip_err[IP_AES]),
        .sin_data(ip_sin_data[8*IP_AES +: 8]), .sin_valid(ip_sin_valid[IP_AES]),
        .sin_last(ip_sin_last[IP_AES]), .sin_ready(ip_sin_ready[IP_AES]),
        .sout_data(ip_sout_data[8*IP_AES +: 8]), .sout_valid(ip_sout_valid[IP_AES]),
        .sout_last(ip_sout_last[IP_AES]), .sout_ready(ip_sout_ready[IP_AES]),
        .csi_result(ip_result[256*IP_AES +: 256]),
        .csi_result_valid(ip_result_valid[IP_AES])
    );

    sha256_ip u_sha (
        .clk(clk_27m), .rst_n(rstn),
        .csi_start(ip_start[IP_SHA]), .csi_mode(ip_mode[8*IP_SHA +: 8]),
        .csi_busy(ip_busy[IP_SHA]), .csi_done(ip_done[IP_SHA]),
        .csi_err(ip_err[IP_SHA]),
        .sin_data(ip_sin_data[8*IP_SHA +: 8]), .sin_valid(ip_sin_valid[IP_SHA]),
        .sin_last(ip_sin_last[IP_SHA]), .sin_ready(ip_sin_ready[IP_SHA]),
        .sout_data(ip_sout_data[8*IP_SHA +: 8]), .sout_valid(ip_sout_valid[IP_SHA]),
        .sout_last(ip_sout_last[IP_SHA]), .sout_ready(ip_sout_ready[IP_SHA]),
        .csi_result(ip_result[256*IP_SHA +: 256]),
        .csi_result_valid(ip_result_valid[IP_SHA])
    );

    //------------------------------------------------------------------
    // Điều phối phiên
    //------------------------------------------------------------------
    wire         tx_start, tx_done;
    wire [255:0] digest_tx;
    wire         drop_pulse;

    session_fsm #(.AW(AW), .NUM_IP(NUM_IP), .IP_AES(IP_AES), .IP_SHA(IP_SHA)) u_ses (
        .clk(clk_27m), .rst_n(rstn),
        .aes_key(`AES256_HARDCODED_KEY),
        .frame_ready(frame_ready), .len(len), .iv(iv), .digest_rx(digest_rx),
        .buf_raddr(ses_raddr), .buf_rdata(buf_rdata),
        .buf_we(ses_we), .buf_waddr(ses_waddr), .buf_wdata(ses_wdata),
        .req(req), .grant(grant),
        .m_start(m_start), .m_mode(m_mode),
        .m_busy(m_busy), .m_done(m_done), .m_err(m_err),
        .m_sin_data(m_sin_data), .m_sin_valid(m_sin_valid),
        .m_sin_last(m_sin_last), .m_sin_ready(m_sin_ready),
        .m_sout_data(m_sout_data), .m_sout_valid(m_sout_valid),
        .m_sout_last(m_sout_last), .m_sout_ready(m_sout_ready),
        .m_result(m_result), .m_result_valid(m_result_valid),
        .tx_start(tx_start), .digest_tx(digest_tx), .tx_done(tx_done),
        .drop_pulse(drop_pulse), .engine_busy(engine_busy)
    );

    frame_tx #(.AW(AW)) u_ftx (
        .clk(clk_27m), .rst_n(rstn),
        .start(tx_start), .len(len), .iv(iv), .digest(digest_tx),
        .done(tx_done),
        .buf_raddr(tx_raddr), .buf_rdata(buf_rdata),
        .tx_data(tx_data), .tx_valid(tx_valid), .tx_ready(tx_ready),
        .active(tx_active)
    );

    //------------------------------------------------------------------
    led_status #(.CLK_HZ(CLK_HZ)) u_led (
        .clk(clk_27m), .rst_n(rstn),
        .rx_active(rx_busy),
        .engine_busy(engine_busy),
        .drop_pulse(drop_pulse | frame_drop),
        .viol_concurrent(viol_concurrent),
        .led0_n(led0_n), .led1_n(led1_n), .led2_n(led2_n)
    );

endmodule
