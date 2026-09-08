`timescale 1ns/1ps

module tb_keyed_sha256;

    reg clk;
    reg rst_n;
    reg buf_wr_en;
    reg [8:0] buf_wr_addr;
    reg [7:0] buf_wr_data;
    reg start_pad;
    reg [15:0] msg_len;
    wire busy;
    wire done;
    wire [255:0] digest;

    sha256_padder dut (
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

    always #18.5 clk = ~clk;

    task test_case(
        input [15:0] ct_len,
        input [255:0] expected_digest
    );
        integer i;
        reg [15:0] raw_len;
        begin
            raw_len = 16'd18 + ct_len;
            $display("[TEST] Running test for ct_len = %0d bytes (raw_len = %0d)...", ct_len, raw_len);
            
            // Populate RAM with test pattern matching Python script exactly
            for (i = 0; i < raw_len; i = i + 1) begin
                @(posedge clk);
                buf_wr_en   <= 1'b1;
                buf_wr_addr <= i[8:0];
                if (i == 0) buf_wr_data <= ct_len[15:8];
                else if (i == 1) buf_wr_data <= ct_len[7:0];
                else if (i < 18) buf_wr_data <= ((i - 2) * 3 + 1) & 8'hff;
                else buf_wr_data <= ((i - 18) * 7 + 5) & 8'hff;
            end
            @(posedge clk);
            buf_wr_en <= 1'b0;

            // Trigger Padder
            @(posedge clk);
            msg_len   <= raw_len;
            start_pad <= 1'b1;
            @(posedge clk);
            start_pad <= 1'b0;

            // Wait for done
            while (!done) @(posedge clk);

            $display("   Digest:   %064h", digest);
            $display("   Expected: %064h", expected_digest);
            if (digest === expected_digest) begin
                $display("   >>> PASS! <<<\n");
            end else begin
                $display("   >>> FAIL! Mismatch! <<<\n");
                $fatal(1);
            end
            @(posedge clk);
        end
    endtask

    initial begin
        clk = 0;
        rst_n = 0;
        buf_wr_en = 0;
        buf_wr_addr = 0;
        buf_wr_data = 0;
        start_pad = 0;
        msg_len = 0;

        #100;
        rst_n = 1;
        #100;

        // ct_len=16: ad295ab81ea06f591f4591cf1d79f95da6e55a9ad1b9c2321f015e5520131d49
        test_case(16'd16, 256'had295ab81ea06f591f4591cf1d79f95da6e55a9ad1b9c2321f015e5520131d49);

        // ct_len=64: aa098605c06ed1bc7c3d8e12c923d09b35f4b98dd31b2471d232e4bf7cbbd89b
        test_case(16'd64, 256'haa098605c06ed1bc7c3d8e12c923d09b35f4b98dd31b2471d232e4bf7cbbd89b);

        // ct_len=128: 4c8c8ac94fab842399d63f43115fc31f59fa9c4b606659b2569bd9192c368b2c
        test_case(16'd128, 256'h4c8c8ac94fab842399d63f43115fc31f59fa9c4b606659b2569bd9192c368b2c);

        // ct_len=448: d7d58e9fe1c927342d80fadc14d1fc5b36707bac5d9f64cd6e3d73cd417cd9cb
        test_case(16'd448, 256'hd7d58e9fe1c927342d80fadc14d1fc5b36707bac5d9f64cd6e3d73cd417cd9cb);

        $display("ALL 4 KEYED SHA-256 PADDER TESTS PASSED 100%%!");
        $finish;
    end

endmodule
