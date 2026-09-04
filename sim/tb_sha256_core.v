`timescale 1ns/1ps

// Self-checking testbench for SHA-256 Iterative Core and Autonomous Padder
// Standard compliance: NIST FIPS 180-4
module tb_sha256_core;

    reg clk;
    reg rst_n;

    // Padder interface
    reg         buf_wr_en;
    reg  [8:0]  buf_wr_addr;
    reg  [7:0]  buf_wr_data;
    reg         start_pad;
    reg  [15:0] msg_len;
    wire        busy;
    wire        done;
    wire [255:0] digest;

    sha256_padder u_sha256_padder (
        .clk(clk),
        .rst_n(rst_n),
        .buf_wr_en(buf_wr_en),
        .buf_wr_addr(buf_wr_addr),
        .buf_wr_data(buf_wr_data),
        .start_pad(start_pad),
        .msg_len(msg_len),
        .busy(busy),
        .done(done),
        .digest(digest)
    );

    // 27.0 MHz Clock Generation (~37.037 ns period)
    always #18.5 clk = ~clk;

    // NIST FIPS 180-4 Standard Vectors
    localparam [255:0] EXP_DIGEST_V1 = 256'hba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad; // "abc"
    localparam [255:0] EXP_DIGEST_V2 = 256'he3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855; // ""
    localparam [255:0] EXP_DIGEST_V3 = 256'h248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1; // 56-byte vector

    reg [7:0] vector3_bytes [0:55];
    integer err_count;
    integer i;

    initial begin
        // Populate 56-byte vector 3 ("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
        vector3_bytes[0]  = "a"; vector3_bytes[1]  = "b"; vector3_bytes[2]  = "c"; vector3_bytes[3]  = "d";
        vector3_bytes[4]  = "b"; vector3_bytes[5]  = "c"; vector3_bytes[6]  = "d"; vector3_bytes[7]  = "e";
        vector3_bytes[8]  = "c"; vector3_bytes[9]  = "d"; vector3_bytes[10] = "e"; vector3_bytes[11] = "f";
        vector3_bytes[12] = "d"; vector3_bytes[13] = "e"; vector3_bytes[14] = "f"; vector3_bytes[15] = "g";
        vector3_bytes[16] = "e"; vector3_bytes[17] = "f"; vector3_bytes[18] = "g"; vector3_bytes[19] = "h";
        vector3_bytes[20] = "f"; vector3_bytes[21] = "g"; vector3_bytes[22] = "h"; vector3_bytes[23] = "i";
        vector3_bytes[24] = "g"; vector3_bytes[25] = "h"; vector3_bytes[26] = "i"; vector3_bytes[27] = "j";
        vector3_bytes[28] = "h"; vector3_bytes[29] = "i"; vector3_bytes[30] = "j"; vector3_bytes[31] = "k";
        vector3_bytes[32] = "i"; vector3_bytes[33] = "j"; vector3_bytes[34] = "k"; vector3_bytes[35] = "l";
        vector3_bytes[36] = "j"; vector3_bytes[37] = "k"; vector3_bytes[38] = "l"; vector3_bytes[39] = "m";
        vector3_bytes[40] = "k"; vector3_bytes[41] = "l"; vector3_bytes[42] = "m"; vector3_bytes[43] = "n";
        vector3_bytes[44] = "l"; vector3_bytes[45] = "m"; vector3_bytes[46] = "n"; vector3_bytes[47] = "o";
        vector3_bytes[48] = "m"; vector3_bytes[49] = "n"; vector3_bytes[50] = "o"; vector3_bytes[51] = "p";
        vector3_bytes[52] = "n"; vector3_bytes[53] = "o"; vector3_bytes[54] = "p"; vector3_bytes[55] = "q";

        clk = 0;
        rst_n = 0;
        buf_wr_en = 0;
        buf_wr_addr = 0;
        buf_wr_data = 0;
        start_pad = 0;
        msg_len = 0;
        err_count = 0;

        $display("================================================================================");
        $display("   TEST SUITE: SHA-256 NIST FIPS 180-4 VERIFICATION");
        $display("================================================================================");

        #50;
        rst_n = 1;
        #50;

        // -------------------------------------------------------------
        // Test 1: Vector 1 ("abc") - 3 bytes, single 512-bit block
        // -------------------------------------------------------------
        $display("\n[TEST 1] Running NIST Vector 1: \"abc\" (3 Bytes)");
        @(posedge clk);
        #1;
        buf_wr_en = 1;
        buf_wr_addr = 0; buf_wr_data = "a"; @(posedge clk); #1;
        buf_wr_addr = 1; buf_wr_data = "b"; @(posedge clk); #1;
        buf_wr_addr = 2; buf_wr_data = "c"; @(posedge clk); #1;
        buf_wr_en = 0;

        msg_len = 16'd3;
        start_pad = 1;
        @(posedge clk);
        #1;
        start_pad = 0;

        @(posedge done);
        #1;
        $display("   Calculated Digest: %h", digest);
        $display("     Expected Digest: %h", EXP_DIGEST_V1);
        if (digest === EXP_DIGEST_V1) begin
            $display("   >>> MATCH: Vector 1 Verified PASS <<<");
        end else begin
            $display("   >>> FAIL: Vector 1 Mismatch! <<<");
            err_count = err_count + 1;
        end

        #50;

        // -------------------------------------------------------------
        // Test 2: Vector 2 ("") - 0 bytes (Empty String), single block
        // -------------------------------------------------------------
        $display("\n[TEST 2] Running NIST Vector 2: Empty String \"\" (0 Bytes)");
        @(posedge clk);
        #1;
        msg_len = 16'd0;
        start_pad = 1;
        @(posedge clk);
        #1;
        start_pad = 0;

        @(posedge done);
        #1;
        $display("   Calculated Digest: %h", digest);
        $display("     Expected Digest: %h", EXP_DIGEST_V2);
        if (digest === EXP_DIGEST_V2) begin
            $display("   >>> MATCH: Vector 2 Verified PASS <<<");
        end else begin
            $display("   >>> FAIL: Vector 2 Mismatch! <<<");
            err_count = err_count + 1;
        end

        #50;

        // -------------------------------------------------------------
        // Test 3: Vector 3 (56-Byte Multi-Block Boundary Vector)
        // -------------------------------------------------------------
        $display("\n[TEST 3] Running NIST Vector 3: 56-Byte Boundary Crossing Vector");
        @(posedge clk);
        #1;
        buf_wr_en = 1;
        for (i = 0; i < 56; i = i + 1) begin
            buf_wr_addr = i[8:0];
            buf_wr_data = vector3_bytes[i];
            @(posedge clk);
            #1;
        end
        buf_wr_en = 0;

        msg_len = 16'd56;
        start_pad = 1;
        @(posedge clk);
        #1;
        start_pad = 0;

        @(posedge done);
        #1;
        $display("   Calculated Digest: %h", digest);
        $display("     Expected Digest: %h", EXP_DIGEST_V3);
        if (digest === EXP_DIGEST_V3) begin
            $display("   >>> MATCH: Vector 3 Verified PASS <<<");
        end else begin
            $display("   >>> FAIL: Vector 3 Mismatch! <<<");
            err_count = err_count + 1;
        end

        $display("\n================================================================================");
        if (err_count == 0) begin
            $display("   [OVERALL PASS] ALL SHA-256 NIST TEST VECTORS PASSED 100%%!");
            $display("================================================================================");
        end else begin
            $display("   [OVERALL FAIL] DETECTED %0d SHA-256 VECTOR FAILURES!", err_count);
            $display("================================================================================");
        end

        $finish;
    end

endmodule
