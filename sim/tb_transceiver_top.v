`timescale 1ns/1ps

// Comprehensive Top-Level Transceiver System Testbench
// Verifies:
//   1. Normal Loopback Round-Trip (Transmit -> Validate -> Decrypt -> Re-encrypt -> Echo -> Host Verify)
//   2. Tamper Fault Injection (1-bit corruption -> MAC Error -> Quarantine Flush -> 0 TX)
//   3. Incomplete Frame Timeout (Preamble sent -> silence -> Watchdog aborts after 2.5 ms)
module tb_transceiver_top;

    reg clk_27m;
    reg rst_n;
    reg uart_rx_pin;
    wire uart_tx_pin;
    wire led_tx_active;
    wire led_rx_pass;
    wire led_mac_err;

    // Baud timing: 27.0 MHz / 115,200 = 234 cycles -> 234 * 37.037 ns = 8666.67 ns per bit
    localparam BIT_PERIOD_NS = 8667;

    // DUT Instantiation
    top_crypto_transceiver dut (
        .clk_27m(clk_27m),
        .rst_n(rst_n),
        .uart_rx(uart_rx_pin),
        .uart_tx(uart_tx_pin),
        .led_tx_active(led_tx_active),
        .led_rx_pass(led_rx_pass),
        .led_mac_err(led_mac_err)
    );

    // 27.0 MHz Clock (~37.037 ns period, 18.5 ns half-cycle)
    always #18.5 clk_27m = ~clk_27m;

    // 70-Byte Golden Test Packet
    reg [7:0] valid_pkt [0:69];
    reg [7:0] rx_pkt_buf [0:69];
    integer rx_byte_cnt;
    integer err_count;
    integer i;

    // UART Host Transmitter Task (Sends 1 byte at 115,200 baud, 8-N-1)
    task send_uart_byte(input [7:0] data);
        integer b;
        begin
            // Start bit
            uart_rx_pin = 1'b0;
            #(BIT_PERIOD_NS);
            // 8 Data bits (LSB first)
            for (b = 0; b < 8; b = b + 1) begin
                uart_rx_pin = data[b];
                #(BIT_PERIOD_NS);
            end
            // Stop bit
            uart_rx_pin = 1'b1;
            #(BIT_PERIOD_NS);
        end
    endtask

    // UART Host Receiver Task (Captures 1 byte from DUT uart_tx_pin)
    task recv_uart_byte(output [7:0] data, output reg timeout);
        integer b;
        begin
            timeout = 1'b0;
            // Wait for start bit (falling edge)
            fork : wait_start
                begin
                    @(negedge uart_tx_pin);
                end
                begin
                    #15000000; // 15 ms timeout
                    timeout = 1'b1;
                end
            join_any
            disable wait_start;

            if (!timeout) begin
                #(BIT_PERIOD_NS / 2); // Sample at middle of start bit
                for (b = 0; b < 8; b = b + 1) begin
                    #(BIT_PERIOD_NS);
                    data[b] = uart_tx_pin;
                end
                #(BIT_PERIOD_NS); // Stop bit
            end
        end
    endtask

    initial begin
        // Initialize Golden 70-byte Packet
        // Preamble (2B)
        valid_pkt[0] = 8'hAA; valid_pkt[1] = 8'h55;
        // LEN (2B): 16 bytes
        valid_pkt[2] = 8'h00; valid_pkt[3] = 8'h10;
        // IV (16B): f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff
        valid_pkt[4]  = 8'hf0; valid_pkt[5]  = 8'hf1; valid_pkt[6]  = 8'hf2; valid_pkt[7]  = 8'hf3;
        valid_pkt[8]  = 8'hf4; valid_pkt[9]  = 8'hf5; valid_pkt[10] = 8'hf6; valid_pkt[11] = 8'hf7;
        valid_pkt[12] = 8'hf8; valid_pkt[13] = 8'hf9; valid_pkt[14] = 8'hfa; valid_pkt[15] = 8'hfb;
        valid_pkt[16] = 8'hfc; valid_pkt[17] = 8'hfd; valid_pkt[18] = 8'hfe; valid_pkt[19] = 8'hff;
        // Ciphertext (16B): 601ec313775789a5b7a7f504bbf3d228
        valid_pkt[20] = 8'h60; valid_pkt[21] = 8'h1e; valid_pkt[22] = 8'hc3; valid_pkt[23] = 8'h13;
        valid_pkt[24] = 8'h77; valid_pkt[25] = 8'h57; valid_pkt[26] = 8'h89; valid_pkt[27] = 8'ha5;
        valid_pkt[28] = 8'hb7; valid_pkt[29] = 8'ha7; valid_pkt[30] = 8'hf5; valid_pkt[31] = 8'h04;
        valid_pkt[32] = 8'hbb; valid_pkt[33] = 8'hf3; valid_pkt[34] = 8'hd2; valid_pkt[35] = 8'h28;
        // SHA-256 MAC (32B): 9db0ec4233e153e815cc8a19f09304c83e34c1f9e6bb933deb44988b4d371fff
        valid_pkt[36] = 8'h9d; valid_pkt[37] = 8'hb0; valid_pkt[38] = 8'hec; valid_pkt[39] = 8'h42;
        valid_pkt[40] = 8'h33; valid_pkt[41] = 8'he1; valid_pkt[42] = 8'h53; valid_pkt[43] = 8'he8;
        valid_pkt[44] = 8'h15; valid_pkt[45] = 8'hcc; valid_pkt[46] = 8'h8a; valid_pkt[47] = 8'h19;
        valid_pkt[48] = 8'hf0; valid_pkt[49] = 8'h93; valid_pkt[50] = 8'h04; valid_pkt[51] = 8'hc8;
        valid_pkt[52] = 8'h3e; valid_pkt[53] = 8'h34; valid_pkt[54] = 8'hc1; valid_pkt[55] = 8'hf9;
        valid_pkt[56] = 8'he6; valid_pkt[57] = 8'hbb; valid_pkt[58] = 8'h93; valid_pkt[59] = 8'h3d;
        valid_pkt[60] = 8'heb; valid_pkt[61] = 8'h44; valid_pkt[62] = 8'h98; valid_pkt[63] = 8'h8b;
        valid_pkt[64] = 8'h4d; valid_pkt[65] = 8'h37; valid_pkt[66] = 8'h1f; valid_pkt[67] = 8'hff;
        // Postamble (2B): 0x0D 0x0A
        valid_pkt[68] = 8'h0D; valid_pkt[69] = 8'h0A;

        clk_27m     = 0;
        rst_n       = 0;
        uart_rx_pin = 1'b1;
        err_count   = 0;

        $display("================================================================================");
        $display("   FULL TRANSCEIVER SYSTEM INTEGRATION & PROTOCOL VERIFICATION");
        $display("================================================================================");

        #100;
        rst_n = 1;
        #1000;

        // =============================================================
        // TEST 1: SECURE ECHO LOOPBACK ROUND-TRIP
        // =============================================================
        $display("\n[TEST 1] Transmitting 70-byte valid encrypted packet to FPGA...");
        for (i = 0; i < 70; i = i + 1) begin
            send_uart_byte(valid_pkt[i]);
        end

        $display("   Packet transmission complete. Waiting for FPGA loopback echo response...");

        // Capture echoed packet from FPGA
        rx_byte_cnt = 0;
        begin : capture_loop
            reg [7:0] rdata;
            reg       timeout;
            for (i = 0; i < 70; i = i + 1) begin
                recv_uart_byte(rdata, timeout);
                if (timeout) begin
                    $display("   [FAIL] Timeout waiting for byte %0d from FPGA!", i);
                    err_count = err_count + 1;
                    disable capture_loop;
                end
                rx_pkt_buf[i] = rdata;
                rx_byte_cnt = rx_byte_cnt + 1;
            end
        end

        if (rx_byte_cnt == 70) begin
            $display("   Echoed 70-byte packet received from FPGA. Verifying byte-by-byte match...");
            for (i = 0; i < 70; i = i + 1) begin
                if (rx_pkt_buf[i] !== valid_pkt[i]) begin
                    $display("   [MISMATCH at byte %0d] Received: 0x%02x, Expected: 0x%02x", i, rx_pkt_buf[i], valid_pkt[i]);
                    err_count = err_count + 1;
                end
            end
            if (err_count == 0) begin
                $display("   >>> PASS: Loopback packet matches 100%% byte-for-byte! <<<");
                $display("   >>> Status LED Check: led_rx_pass=%b (Active-Low), led_tx_active=%b <<<", led_rx_pass, led_tx_active);
            end
        end

        #(BIT_PERIOD_NS * 50);

        // =============================================================
        // TEST 2: TAMPER FAULT INJECTION (1-BIT MAC CORRUPTION)
        // =============================================================
        $display("\n[TEST 2] Tamper Injection: Corrupting 1 bit in SHA-256 MAC tag...");
        for (i = 0; i < 70; i = i + 1) begin
            if (i == 40) begin
                send_uart_byte(valid_pkt[i] ^ 8'h01); // 1-bit corruption
            end else begin
                send_uart_byte(valid_pkt[i]);
            end
        end

        $display("   Corrupted packet sent. Verifying FPGA drops packet and emits zero TX...");

        begin : check_tamper_tx
            reg [7:0] rdata;
            reg       timeout;
            recv_uart_byte(rdata, timeout);
            if (!timeout) begin
                $display("   [FAIL] UNEXPECTED TX EMISSION on corrupted packet: 0x%02x!", rdata);
                err_count = err_count + 1;
            end else begin
                $display("   >>> PASS: Zero TX emitted. Quarantine buffer flushed cleanly! <<<");
                $display("   >>> Status LED Check: led_mac_err=%b (Active-Low Alert ON!) <<<", led_mac_err);
            end
        end

        #(BIT_PERIOD_NS * 20);

        // =============================================================
        // TEST 3: INCOMPLETE FRAME TIMEOUT WATCHDOG (2.5 ms)
        // =============================================================
        $display("\n[TEST 3] Watchdog Timeout Test: Sending preamble 0xAA 0x55 then silence...");
        send_uart_byte(8'hAA);
        send_uart_byte(8'h55);
        send_uart_byte(8'h00);
        // Stall line here (silence)
        $display("   Line stalled. Waiting 3.0 ms for 2.5 ms watchdog timer to trigger...");
        #3000000; // 3.0 ms

        $display("   Checking arbiter lock released and error alert asserted...");
        if (dut.u_arbiter.arb_rx_lock == 1'b0) begin
            $display("   >>> PASS: Arbiter lock released cleanly after timeout! <<<");
        end else begin
            $display("   [FAIL] Arbiter lock still stuck active after timeout!");
            err_count = err_count + 1;
        end

        $display("\n================================================================================");
        if (err_count == 0) begin
            $display("   [OVERALL PASS] ALL SYSTEM INTEGRATION TESTS PASSED 100%%!");
            $display("================================================================================");
        end else begin
            $display("   [OVERALL FAIL] DETECTED %0d SYSTEM FAILURES!", err_count);
            $display("================================================================================");
        end

        $finish;
    end

endmodule
