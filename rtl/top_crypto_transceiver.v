`timescale 1ns/1ps

// Top-Level Cryptographic Transceiver Core
// Target Platform: Sipeed Tang Nano 9K (Gowin GW1NR-LV9QN88PC6/I5)
// Physical Pins: clk_27m (52), rst_n (3), uart_tx (17), uart_rx (18)
// Status LEDs: led_tx_active (10), led_rx_pass (11), led_mac_err (13) (Active-Low)
module top_crypto_transceiver (
    input  wire clk_27m,
    input  wire rst_n,
    input  wire uart_rx,
    output wire uart_tx,
    output wire led_tx_active,
    output wire led_rx_pass,
    output wire led_mac_err
);

    // Hardened Cryptographic Parameters
    localparam [255:0] ROOT_KEY = 256'h603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4;
    localparam [127:0] BASE_IV  = 128'hf0f1f2f3f4f5f6f7f8f9fafbfcfdfeff;

    // LED Pulse Stretch: ~150 ms (62 ticks of 65536 cycles @ 27.0 MHz = 150.5 ms)
    localparam [5:0] LED_STRETCH_TICKS = 6'd62;

    // -------------------------------------------------------------
    // 1. Asynchronous Reset 2-Stage Synchronizer
    // -------------------------------------------------------------
    reg rst_sync0, rst_sync1;
    always @(posedge clk_27m or negedge rst_n) begin
        if (!rst_n) begin
            rst_sync0 <= 1'b0;
            rst_sync1 <= 1'b0;
        end else begin
            rst_sync0 <= 1'b1;
            rst_sync1 <= rst_sync0;
        end
    end
    wire sys_rst_n = rst_sync1;

    // -------------------------------------------------------------
    // 2. Physical UART Interface
    // -------------------------------------------------------------
    wire [7:0] rx_byte;
    wire       rx_valid;
    wire       rx_frame_err;

    uart_rx u_uart_rx (
        .clk(clk_27m),
        .rst_n(sys_rst_n),
        .rx_pin(uart_rx),
        .rx_data(rx_byte),
        .rx_valid(rx_valid),
        .rx_frame_err(rx_frame_err)
    );

    wire [7:0] tx_byte;
    wire       tx_start;
    wire       tx_busy;

    uart_tx u_uart_tx (
        .clk(clk_27m),
        .rst_n(sys_rst_n),
        .tx_data(tx_byte),
        .tx_start(tx_start),
        .tx_pin(uart_tx),
        .tx_busy(tx_busy)
    );

    // -------------------------------------------------------------
    // 3. Hardware Mutual Exclusion Arbiter
    // -------------------------------------------------------------
    wire rx_preamble_match;
    wire rx_done;
    wire arb_rx_lock;

    reg  loopback_tx_req;
    wire tx_done;
    wire arb_tx_lock;
    wire tx_grant;
    wire tx_pending;

    crypto_arbiter u_arbiter (
        .clk(clk_27m),
        .rst_n(sys_rst_n),
        .rx_preamble_match(rx_preamble_match),
        .rx_done(rx_done),
        .arb_rx_lock(arb_rx_lock),
        .tx_req(loopback_tx_req),
        .tx_done(tx_done),
        .arb_tx_lock(arb_tx_lock),
        .tx_grant(tx_grant),
        .tx_pending(tx_pending)
    );

    // -------------------------------------------------------------
    // 4. Shared Cryptographic Hardware Engines
    // -------------------------------------------------------------
    // AES-256 CTR Multiplexing
    wire        rx_aes_start,      tx_aes_start;
    wire        rx_aes_load_iv,    tx_aes_load_iv;
    wire [127:0] rx_aes_iv,         tx_aes_iv;
    wire [127:0] rx_aes_data_in,    tx_aes_data_in;
    wire [127:0] shared_aes_data_out;
    wire         shared_aes_ready;
    wire         shared_aes_valid;

    wire        mux_aes_start   = arb_rx_lock ? rx_aes_start   : tx_aes_start;
    wire        mux_aes_load_iv = arb_rx_lock ? rx_aes_load_iv : tx_aes_load_iv;
    wire [127:0] mux_aes_iv      = rx_aes_iv;
    wire [127:0] mux_aes_data_in = arb_rx_lock ? rx_aes_data_in : tx_aes_data_in;

    aes256_ctr u_shared_aes_ctr (
        .clk(clk_27m),
        .rst_n(sys_rst_n),
        .start(mux_aes_start),
        .load_iv(mux_aes_load_iv),
        .key(ROOT_KEY),
        .iv(mux_aes_iv),
        .data_in(mux_aes_data_in),
        .data_out(shared_aes_data_out),
        .counter_out(),
        .ready(shared_aes_ready),
        .valid(shared_aes_valid)
    );

    // SHA-256 Padder Multiplexing
    wire        rx_sha_pad_start,   tx_sha_pad_start;
    wire [15:0] rx_sha_pad_len,     tx_sha_pad_len;
    wire        rx_sha_buf_wr_en,   tx_sha_buf_wr_en;
    wire [8:0]  rx_sha_buf_wr_addr, tx_sha_buf_wr_addr;
    wire [7:0]  rx_sha_buf_wr_data, tx_sha_buf_wr_data;
    wire        shared_sha_pad_busy;
    wire        shared_sha_pad_done;
    wire [255:0] shared_sha_digest;

    wire        mux_sha_pad_start   = arb_rx_lock ? rx_sha_pad_start   : tx_sha_pad_start;
    wire [15:0] mux_sha_pad_len     = arb_rx_lock ? rx_sha_pad_len     : tx_sha_pad_len;
    wire        mux_sha_buf_wr_en   = arb_rx_lock ? rx_sha_buf_wr_en   : tx_sha_buf_wr_en;
    wire [8:0]  mux_sha_buf_wr_addr = arb_rx_lock ? rx_sha_buf_wr_addr : tx_sha_buf_wr_addr;
    wire [7:0]  mux_sha_buf_wr_data = arb_rx_lock ? rx_sha_buf_wr_data : tx_sha_buf_wr_data;

    sha256_padder u_shared_sha_padder (
        .clk(clk_27m),
        .rst_n(sys_rst_n),
        .buf_wr_en(mux_sha_buf_wr_en),
        .buf_wr_addr(mux_sha_buf_wr_addr),
        .buf_wr_data(mux_sha_buf_wr_data),
        .start_pad(mux_sha_pad_start),
        .msg_len(mux_sha_pad_len),
        .busy(shared_sha_pad_busy),
        .done(shared_sha_pad_done),
        .digest(shared_sha_digest)
    );

    // -------------------------------------------------------------
    // 5. Plaintext Loopback Buffer (512 Bytes Dual-Port RAM)
    // -------------------------------------------------------------
    (* syn_ramstyle = "block_ram", no_rw_check *)
    reg [7:0] pt_loopback_ram [0:511];
    wire       pt_buf_wr_en;
    wire [8:0] pt_buf_wr_addr;
    wire [7:0] pt_buf_wr_data;
    wire [8:0] pt_raddr;
    reg  [7:0] pt_rdata;

    always @(posedge clk_27m) begin
        if (pt_buf_wr_en) begin
            pt_loopback_ram[pt_buf_wr_addr] <= pt_buf_wr_data;
        end
        pt_rdata <= pt_loopback_ram[pt_raddr];
    end

    // -------------------------------------------------------------
    // 6. Packet Deframer (Inbound RX)
    // -------------------------------------------------------------
    wire [15:0]  pt_payload_len;
    wire [127:0] pt_payload_iv;
    wire         pt_valid;
    wire         rx_pass_pulse;
    wire         mac_err_pulse;

    packet_deframer u_deframer (
        .clk(clk_27m),
        .rst_n(sys_rst_n),
        .rx_data(rx_byte),
        .rx_valid(rx_valid),
        .rx_frame_err(rx_frame_err),
        .rx_preamble_match(rx_preamble_match),
        .rx_done(rx_done),
        .sha_pad_start(rx_sha_pad_start),
        .sha_pad_len(rx_sha_pad_len),
        .sha_buf_wr_en(rx_sha_buf_wr_en),
        .sha_buf_wr_addr(rx_sha_buf_wr_addr),
        .sha_buf_wr_data(rx_sha_buf_wr_data),
        .sha_pad_busy(shared_sha_pad_busy),
        .sha_pad_done(shared_sha_pad_done),
        .sha_digest(shared_sha_digest),
        .aes_start(rx_aes_start),
        .aes_load_iv(rx_aes_load_iv),
        .aes_iv(rx_aes_iv),
        .aes_data_in(rx_aes_data_in),
        .aes_data_out(shared_aes_data_out),
        .aes_ready(shared_aes_ready),
        .aes_valid(shared_aes_valid),
        .pt_buf_wr_en(pt_buf_wr_en),
        .pt_buf_wr_addr(pt_buf_wr_addr),
        .pt_buf_wr_data(pt_buf_wr_data),
        .pt_payload_len(pt_payload_len),
        .pt_payload_iv(pt_payload_iv),
        .pt_valid(pt_valid),
        .rx_pass_pulse(rx_pass_pulse),
        .mac_err_pulse(mac_err_pulse)
    );

    // -------------------------------------------------------------
    // 7. Secure Loopback Echo Controller
    // -------------------------------------------------------------
    wire framer_start_tx = tx_grant;

    always @(posedge clk_27m or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            loopback_tx_req <= 1'b0;
        end else begin
            if (pt_valid) begin
                // New decrypted plaintext ready for echo
                loopback_tx_req <= 1'b1;
            end

            if (tx_grant) begin
                loopback_tx_req <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------------
    // 8. Packet Framer (Outbound TX)
    // -------------------------------------------------------------
    wire tx_active_pulse;

    packet_framer u_framer (
        .clk(clk_27m),
        .rst_n(sys_rst_n),
        .start_tx(framer_start_tx),
        .tx_payload_len(pt_payload_len),
        .tx_payload_iv(pt_payload_iv),
        .pt_raddr(pt_raddr),
        .pt_rdata(pt_rdata),
        .tx_done(tx_done),
        .sha_pad_start(tx_sha_pad_start),
        .sha_pad_len(tx_sha_pad_len),
        .sha_buf_wr_en(tx_sha_buf_wr_en),
        .sha_buf_wr_addr(tx_sha_buf_wr_addr),
        .sha_buf_wr_data(tx_sha_buf_wr_data),
        .sha_pad_busy(shared_sha_pad_busy),
        .sha_pad_done(shared_sha_pad_done),
        .sha_digest(shared_sha_digest),
        .aes_start(tx_aes_start),
        .aes_load_iv(tx_aes_load_iv),
        .aes_iv(tx_aes_iv),
        .aes_data_in(tx_aes_data_in),
        .aes_data_out(shared_aes_data_out),
        .aes_ready(shared_aes_ready),
        .aes_valid(shared_aes_valid),
        .uart_tx_data(tx_byte),
        .uart_tx_start(tx_start),
        .uart_tx_busy(tx_busy),
        .tx_active_pulse(tx_active_pulse)
    );

    // -------------------------------------------------------------
    // 9. 150 ms LED Pulse Stretchers (Active-Low Outputs)
    // -------------------------------------------------------------
    reg [15:0] led_prescaler;
    wire led_tick = (led_prescaler == 16'd65535);
    reg [5:0]  cnt_tx_active;
    reg [5:0]  cnt_rx_pass;
    reg [5:0]  cnt_mac_err;

    always @(posedge clk_27m or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            led_prescaler <= 16'd0;
            cnt_tx_active <= 6'd0;
            cnt_rx_pass   <= 6'd0;
            cnt_mac_err   <= 6'd0;
        end else begin
            led_prescaler <= led_prescaler + 16'd1;

            // TX Active
            if (tx_active_pulse) cnt_tx_active <= LED_STRETCH_TICKS;
            else if (led_tick && cnt_tx_active != 6'd0) cnt_tx_active <= cnt_tx_active - 6'd1;

            // RX Auth Pass
            if (rx_pass_pulse) cnt_rx_pass <= LED_STRETCH_TICKS;
            else if (led_tick && cnt_rx_pass != 6'd0) cnt_rx_pass <= cnt_rx_pass - 6'd1;

            // MAC Error
            if (mac_err_pulse) cnt_mac_err <= LED_STRETCH_TICKS;
            else if (led_tick && cnt_mac_err != 6'd0) cnt_mac_err <= cnt_mac_err - 6'd1;
        end
    end

    // Active-Low drive (low when glowing)
    assign led_tx_active = ~(cnt_tx_active != 6'd0);
    assign led_rx_pass   = ~(cnt_rx_pass   != 6'd0);
    assign led_mac_err   = ~(cnt_mac_err   != 6'd0);

endmodule
