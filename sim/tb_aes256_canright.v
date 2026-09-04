// Self-checking testbench for Canright S-Box and AES-256 CTR Mode
// Standards: NIST FIPS 197 & NIST SP 800-38A KAT
`timescale 1ns/1ps

module tb_aes256_canright;

    reg clk;
    reg rst_n;
    reg start;
    reg load_iv;
    reg [255:0] key;
    reg [127:0] iv;
    reg [127:0] data_in;
    wire [127:0] data_out;
    wire [127:0] counter_out;
    wire ready;
    wire valid;

    integer sbox_err_count;
    integer ctr_err_count;
    integer i;

    // Direct S-Box instance for testing all 256 inputs
    reg  [7:0] sbox_test_in;
    wire [7:0] sbox_test_out;
    reg  [7:0] sbox_expected [0:255];

    aes_sbox_canright u_sbox_test (
        .in(sbox_test_in),
        .out(sbox_test_out)
    );

    // AES-256 CTR instance
    aes256_ctr u_aes_ctr (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .load_iv(load_iv),
        .key(key),
        .iv(iv),
        .data_in(data_in),
        .data_out(data_out),
        .counter_out(counter_out),
        .ready(ready),
        .valid(valid)
    );

    // Clock generation (27.0 MHz -> ~37 ns period, using 18ns/19ns half-cycles)
    always #18.5 clk = ~clk;

    // NIST SP 800-38A Section F.5.5 Test Vectors:
    // Key: 603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4
    // IV:  f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff
    reg [127:0] kat_pt [0:3];
    reg [127:0] kat_ct [0:3];

    initial begin
        // Initialize S-Box expected LUT
        sbox_expected[8'h00] = 8'h63; sbox_expected[8'h01] = 8'h7c; sbox_expected[8'h02] = 8'h77; sbox_expected[8'h03] = 8'h7b;
        sbox_expected[8'h04] = 8'hf2; sbox_expected[8'h05] = 8'h6b; sbox_expected[8'h06] = 8'h6f; sbox_expected[8'h07] = 8'hc5;
        sbox_expected[8'h08] = 8'h30; sbox_expected[8'h09] = 8'h01; sbox_expected[8'h0a] = 8'h67; sbox_expected[8'h0b] = 8'h2b;
        sbox_expected[8'h0c] = 8'hfe; sbox_expected[8'h0d] = 8'hd7; sbox_expected[8'h0e] = 8'hab; sbox_expected[8'h0f] = 8'h76;
        sbox_expected[8'h10] = 8'hca; sbox_expected[8'h11] = 8'h82; sbox_expected[8'h12] = 8'hc9; sbox_expected[8'h13] = 8'h7d;
        sbox_expected[8'h14] = 8'hfa; sbox_expected[8'h15] = 8'h59; sbox_expected[8'h16] = 8'h47; sbox_expected[8'h17] = 8'hf0;
        sbox_expected[8'h18] = 8'had; sbox_expected[8'h19] = 8'hd4; sbox_expected[8'h1a] = 8'ha2; sbox_expected[8'h1b] = 8'haf;
        sbox_expected[8'h1c] = 8'h9c; sbox_expected[8'h1d] = 8'ha4; sbox_expected[8'h1e] = 8'h72; sbox_expected[8'h1f] = 8'hc0;
        sbox_expected[8'h20] = 8'hb7; sbox_expected[8'h21] = 8'hfd; sbox_expected[8'h22] = 8'h93; sbox_expected[8'h23] = 8'h26;
        sbox_expected[8'h24] = 8'h36; sbox_expected[8'h25] = 8'h3f; sbox_expected[8'h26] = 8'hf7; sbox_expected[8'h27] = 8'hcc;
        sbox_expected[8'h28] = 8'h34; sbox_expected[8'h29] = 8'ha5; sbox_expected[8'h2a] = 8'he5; sbox_expected[8'h2b] = 8'hf1;
        sbox_expected[8'h2c] = 8'h71; sbox_expected[8'h2d] = 8'hd8; sbox_expected[8'h2e] = 8'h31; sbox_expected[8'h2f] = 8'h15;
        sbox_expected[8'h30] = 8'h04; sbox_expected[8'h31] = 8'hc7; sbox_expected[8'h32] = 8'h23; sbox_expected[8'h33] = 8'hc3;
        sbox_expected[8'h34] = 8'h18; sbox_expected[8'h35] = 8'h96; sbox_expected[8'h36] = 8'h05; sbox_expected[8'h37] = 8'h9a;
        sbox_expected[8'h38] = 8'h07; sbox_expected[8'h39] = 8'h12; sbox_expected[8'h3a] = 8'h80; sbox_expected[8'h3b] = 8'he2;
        sbox_expected[8'h3c] = 8'heb; sbox_expected[8'h3d] = 8'h27; sbox_expected[8'h3e] = 8'hb2; sbox_expected[8'h3f] = 8'h75;
        sbox_expected[8'h40] = 8'h09; sbox_expected[8'h41] = 8'h83; sbox_expected[8'h42] = 8'h2c; sbox_expected[8'h43] = 8'h1a;
        sbox_expected[8'h44] = 8'h1b; sbox_expected[8'h45] = 8'h6e; sbox_expected[8'h46] = 8'h5a; sbox_expected[8'h47] = 8'ha0;
        sbox_expected[8'h48] = 8'h52; sbox_expected[8'h49] = 8'h3b; sbox_expected[8'h4a] = 8'hd6; sbox_expected[8'h4b] = 8'hb3;
        sbox_expected[8'h4c] = 8'h29; sbox_expected[8'h4d] = 8'he3; sbox_expected[8'h4e] = 8'h2f; sbox_expected[8'h4f] = 8'h84;
        sbox_expected[8'h50] = 8'h53; sbox_expected[8'h51] = 8'hd1; sbox_expected[8'h52] = 8'h00; sbox_expected[8'h53] = 8'hed;
        sbox_expected[8'h54] = 8'h20; sbox_expected[8'h55] = 8'hfc; sbox_expected[8'h56] = 8'hb1; sbox_expected[8'h57] = 8'h5b;
        sbox_expected[8'h58] = 8'h6a; sbox_expected[8'h59] = 8'hcb; sbox_expected[8'h5a] = 8'hbe; sbox_expected[8'h5b] = 8'h39;
        sbox_expected[8'h5c] = 8'h4a; sbox_expected[8'h5d] = 8'h4c; sbox_expected[8'h5e] = 8'h58; sbox_expected[8'h5f] = 8'hcf;
        sbox_expected[8'h60] = 8'hd0; sbox_expected[8'h61] = 8'hef; sbox_expected[8'h62] = 8'haa; sbox_expected[8'h63] = 8'hfb;
        sbox_expected[8'h64] = 8'h43; sbox_expected[8'h65] = 8'h4d; sbox_expected[8'h66] = 8'h33; sbox_expected[8'h67] = 8'h85;
        sbox_expected[8'h68] = 8'h45; sbox_expected[8'h69] = 8'hf9; sbox_expected[8'h6a] = 8'h02; sbox_expected[8'h6b] = 8'h7f;
        sbox_expected[8'h6c] = 8'h50; sbox_expected[8'h6d] = 8'h3c; sbox_expected[8'h6e] = 8'h9f; sbox_expected[8'h6f] = 8'ha8;
        sbox_expected[8'h70] = 8'h51; sbox_expected[8'h71] = 8'ha3; sbox_expected[8'h72] = 8'h40; sbox_expected[8'h73] = 8'h8f;
        sbox_expected[8'h74] = 8'h92; sbox_expected[8'h75] = 8'h9d; sbox_expected[8'h76] = 8'h38; sbox_expected[8'h77] = 8'hf5;
        sbox_expected[8'h78] = 8'hbc; sbox_expected[8'h79] = 8'hb6; sbox_expected[8'h7a] = 8'hda; sbox_expected[8'h7b] = 8'h21;
        sbox_expected[8'h7c] = 8'h10; sbox_expected[8'h7d] = 8'hff; sbox_expected[8'h7e] = 8'hf3; sbox_expected[8'h7f] = 8'hd2;
        sbox_expected[8'h80] = 8'hcd; sbox_expected[8'h81] = 8'h0c; sbox_expected[8'h82] = 8'h13; sbox_expected[8'h83] = 8'hec;
        sbox_expected[8'h84] = 8'h5f; sbox_expected[8'h85] = 8'h97; sbox_expected[8'h86] = 8'h44; sbox_expected[8'h87] = 8'h17;
        sbox_expected[8'h88] = 8'hc4; sbox_expected[8'h89] = 8'ha7; sbox_expected[8'h8a] = 8'h7e; sbox_expected[8'h8b] = 8'h3d;
        sbox_expected[8'h8c] = 8'h64; sbox_expected[8'h8d] = 8'h5d; sbox_expected[8'h8e] = 8'h19; sbox_expected[8'h8f] = 8'h73;
        sbox_expected[8'h90] = 8'h60; sbox_expected[8'h91] = 8'h81; sbox_expected[8'h92] = 8'h4f; sbox_expected[8'h93] = 8'hdc;
        sbox_expected[8'h94] = 8'h22; sbox_expected[8'h95] = 8'h2a; sbox_expected[8'h96] = 8'h90; sbox_expected[8'h97] = 8'h88;
        sbox_expected[8'h98] = 8'h46; sbox_expected[8'h99] = 8'hee; sbox_expected[8'h9a] = 8'hb8; sbox_expected[8'h9b] = 8'h14;
        sbox_expected[8'h9c] = 8'hde; sbox_expected[8'h9d] = 8'h5e; sbox_expected[8'h9e] = 8'h0b; sbox_expected[8'h9f] = 8'hdb;
        sbox_expected[8'ha0] = 8'he0; sbox_expected[8'ha1] = 8'h32; sbox_expected[8'ha2] = 8'h3a; sbox_expected[8'ha3] = 8'h0a;
        sbox_expected[8'ha4] = 8'h49; sbox_expected[8'ha5] = 8'h06; sbox_expected[8'ha6] = 8'h24; sbox_expected[8'ha7] = 8'h5c;
        sbox_expected[8'ha8] = 8'hc2; sbox_expected[8'ha9] = 8'hd3; sbox_expected[8'haa] = 8'hac; sbox_expected[8'hab] = 8'h62;
        sbox_expected[8'hac] = 8'h91; sbox_expected[8'had] = 8'h95; sbox_expected[8'hae] = 8'he4; sbox_expected[8'haf] = 8'h79;
        sbox_expected[8'hb0] = 8'he7; sbox_expected[8'hb1] = 8'hc8; sbox_expected[8'hb2] = 8'h37; sbox_expected[8'hb3] = 8'h6d;
        sbox_expected[8'hb4] = 8'h8d; sbox_expected[8'hb5] = 8'hd5; sbox_expected[8'hb6] = 8'h4e; sbox_expected[8'hb7] = 8'ha9;
        sbox_expected[8'hb8] = 8'h6c; sbox_expected[8'hb9] = 8'h56; sbox_expected[8'hba] = 8'hf4; sbox_expected[8'hbb] = 8'hea;
        sbox_expected[8'hbc] = 8'h65; sbox_expected[8'hbd] = 8'h7a; sbox_expected[8'hbe] = 8'hae; sbox_expected[8'hbf] = 8'h08;
        sbox_expected[8'hc0] = 8'hba; sbox_expected[8'hc1] = 8'h78; sbox_expected[8'hc2] = 8'h25; sbox_expected[8'hc3] = 8'h2e;
        sbox_expected[8'hc4] = 8'h1c; sbox_expected[8'hc5] = 8'ha6; sbox_expected[8'hc6] = 8'hb4; sbox_expected[8'hc7] = 8'hc6;
        sbox_expected[8'hc8] = 8'he8; sbox_expected[8'hc9] = 8'hdd; sbox_expected[8'hca] = 8'h74; sbox_expected[8'hcb] = 8'h1f;
        sbox_expected[8'hcc] = 8'h4b; sbox_expected[8'hcd] = 8'hbd; sbox_expected[8'hce] = 8'h8b; sbox_expected[8'hcf] = 8'h8a;
        sbox_expected[8'hd0] = 8'h70; sbox_expected[8'hd1] = 8'h3e; sbox_expected[8'hd2] = 8'hb5; sbox_expected[8'hd3] = 8'h66;
        sbox_expected[8'hd4] = 8'h48; sbox_expected[8'hd5] = 8'h03; sbox_expected[8'hd6] = 8'hf6; sbox_expected[8'hd7] = 8'h0e;
        sbox_expected[8'hd8] = 8'h61; sbox_expected[8'hd9] = 8'h35; sbox_expected[8'hda] = 8'h57; sbox_expected[8'hdb] = 8'hb9;
        sbox_expected[8'hdc] = 8'h86; sbox_expected[8'hdd] = 8'hc1; sbox_expected[8'hde] = 8'h1d; sbox_expected[8'hdf] = 8'h9e;
        sbox_expected[8'he0] = 8'he1; sbox_expected[8'he1] = 8'hf8; sbox_expected[8'he2] = 8'h98; sbox_expected[8'he3] = 8'h11;
        sbox_expected[8'he4] = 8'h69; sbox_expected[8'he5] = 8'hd9; sbox_expected[8'he6] = 8'h8e; sbox_expected[8'he7] = 8'h94;
        sbox_expected[8'he8] = 8'h9b; sbox_expected[8'he9] = 8'h1e; sbox_expected[8'hea] = 8'h87; sbox_expected[8'heb] = 8'he9;
        sbox_expected[8'hec] = 8'hce; sbox_expected[8'hed] = 8'h55; sbox_expected[8'hee] = 8'h28; sbox_expected[8'hef] = 8'hdf;
        sbox_expected[8'hf0] = 8'h8c; sbox_expected[8'hf1] = 8'ha1; sbox_expected[8'hf2] = 8'h89; sbox_expected[8'hf3] = 8'h0d;
        sbox_expected[8'hf4] = 8'hbf; sbox_expected[8'hf5] = 8'he6; sbox_expected[8'hf6] = 8'h42; sbox_expected[8'hf7] = 8'h68;
        sbox_expected[8'hf8] = 8'h41; sbox_expected[8'hf9] = 8'h99; sbox_expected[8'hfa] = 8'h2d; sbox_expected[8'hfb] = 8'h0f;
        sbox_expected[8'hfc] = 8'hb0; sbox_expected[8'hfd] = 8'h54; sbox_expected[8'hfe] = 8'hbb; sbox_expected[8'hff] = 8'h16;

        kat_pt[0] = 128'h6bc1bee22e409f96e93d7e117393172a;
        kat_ct[0] = 128'h601ec313775789a5b7a7f504bbf3d228;

        kat_pt[1] = 128'hae2d8a571e03ac9c9eb76fac45af8e51;
        kat_ct[1] = 128'hf443e3ca4d62b59aca84e990cacaf5c5;

        kat_pt[2] = 128'h30c81c46a35ce411e5fbc1191a0a52ef;
        kat_ct[2] = 128'h2b0930daa23de94ce87017ba2d84988d;

        kat_pt[3] = 128'hf69f2445df4f9b17ad2b417be66c3710;
        kat_ct[3] = 128'hdfc9c58db67aada613c2dd08457941a6;

        clk = 0;
        rst_n = 0;
        start = 0;
        load_iv = 0;
        key = 256'h603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4;
        iv  = 128'hf0f1f2f3f4f5f6f7f8f9fafbfcfdfeff;
        data_in = 128'd0;
        sbox_err_count = 0;
        ctr_err_count = 0;

        $display("================================================================================");
        $display("   TEST SUITE 1: CANRIGHT S-BOX EXHAUSTIVE 256-BYTE VERIFICATION");
        $display("================================================================================");

        #10;
        for (i = 0; i < 256; i = i + 1) begin
            sbox_test_in = i[7:0];
            #1;
            if (sbox_test_out !== sbox_expected[i]) begin
                $display("[S-BOX FAIL] Input 0x%02x: got 0x%02x, expected 0x%02x", i[7:0], sbox_test_out, sbox_expected[i]);
                sbox_err_count = sbox_err_count + 1;
            end
        end

        if (sbox_err_count == 0)
            $display("[S-BOX PASS] 256/256 S-Box transformations match NIST table 100%%!");
        else
            $display("[S-BOX FAIL] %0d mismatches detected!", sbox_err_count);

        $display("\n================================================================================");
        $display("   TEST SUITE 2: NIST SP 800-38A AES-256 CTR KNOWN ANSWER TESTS (KAT)");
        $display("================================================================================");

        #50;
        rst_n = 1;
        #50;

        // Load initial IV/Counter
        @(posedge clk);
        #1;
        load_iv = 1;
        @(posedge clk);
        #1;
        load_iv = 0;

        // Process all 4 blocks in CTR mode
        for (i = 0; i < 4; i = i + 1) begin
            while (!ready) @(posedge clk);
            #1;
            data_in = kat_pt[i];
            start = 1;
            @(posedge clk);
            #1;
            start = 0;

            @(posedge valid);
            #1;
            $display("[CTR ENCRYPT Block %0d] Input : %h", i, kat_pt[i]);
            $display("                    Cipher: %h", data_out);
            $display("                  Expected: %h", kat_ct[i]);
            if (data_out !== kat_ct[i]) begin
                $display("                  >>> MISMATCH on Block %0d! <<<", i);
                ctr_err_count = ctr_err_count + 1;
            end else begin
                $display("                  >>> MATCH <<<");
            end
        end

        $display("\n================================================================================");
        $display("   TEST SUITE 3: AES-256 CTR DECRYPTION ROUND-TRIP VERIFICATION");
        $display("================================================================================");

        // Reset counter back to IV for decryption pass
        @(posedge clk);
        #1;
        load_iv = 1;
        @(posedge clk);
        #1;
        load_iv = 0;

        for (i = 0; i < 4; i = i + 1) begin
            while (!ready) @(posedge clk);
            #1;
            data_in = kat_ct[i]; // Feed ciphertext to decrypt
            start = 1;
            @(posedge clk);
            #1;
            start = 0;

            @(posedge valid);
            #1;
            $display("[CTR DECRYPT Block %0d] Cipher: %h", i, kat_ct[i]);
            $display("                   Recover: %h", data_out);
            $display("                  Expected: %h", kat_pt[i]);
            if (data_out !== kat_pt[i]) begin
                $display("                  >>> MISMATCH on Decryption Block %0d! <<<", i);
                ctr_err_count = ctr_err_count + 1;
            end else begin
                $display("                  >>> MATCH <<<");
            end
        end

        $display("\n================================================================================");
        if (sbox_err_count == 0 && ctr_err_count == 0) begin
            $display("   [OVERALL PASS] ALL AES-256 TESTS PASSED WITH ZERO FAILURES!");
            $display("================================================================================");
        end else begin
            $display("   [OVERALL FAIL] DETECTED SBOX ERRORS: %0d, CTR ERRORS: %0d", sbox_err_count, ctr_err_count);
            $display("================================================================================");
        end

        $finish;
    end

endmodule
