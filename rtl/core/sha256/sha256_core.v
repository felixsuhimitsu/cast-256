`timescale 1ns/1ps

// NIST FIPS 180-4 Compliant SHA-256 Iterative Compression Engine
// Processes 512-bit message blocks in 65 clock cycles (64 rounds + 1 accumulation)
// Uses a 16-register shift scheduler with zero RAM overhead
module sha256_core (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         init,         // Reset hash state to H^{(0)}
    input  wire         block_valid,  // Strobe to process 512-bit block
    input  wire [511:0] block_in,     // 512-bit Big-Endian message block
    output wire         ready,        // High when idle and ready for next block
    output reg          digest_valid, // High for 1 cycle when block compression completes
    output wire [255:0] digest        // Concatenated 256-bit digest {H0..H7}
);

    localparam STATE_IDLE       = 2'd0;
    localparam STATE_ROUNDS     = 2'd1;
    localparam STATE_ACCUMULATE = 2'd2;

    reg [1:0] state;
    reg [5:0] round_cnt;

    // 8 32-bit Hash Accumulator Registers
    reg [31:0] H0, H1, H2, H3, H4, H5, H6, H7;

    // Working variables
    reg [31:0] a, b, c, d, e, f, g, h;

    // 16 32-bit Message Scheduler Shift Registers
    reg [31:0] w [0:15];

    assign ready = (state == STATE_IDLE);
    assign digest = {H0, H1, H2, H3, H4, H5, H6, H7};

    // SHA-256 Bitwise Functions
    function [31:0] rotr(input [31:0] x, input [4:0] n);
        rotr = (x >> n) | (x << (32 - n));
    endfunction

    function [31:0] ch(input [31:0] x, input [31:0] y, input [31:0] z);
        ch = (x & y) ^ (~x & z);
    endfunction

    function [31:0] maj(input [31:0] x, input [31:0] y, input [31:0] z);
        maj = (x & y) ^ (x & z) ^ (y & z);
    endfunction

    function [31:0] sigma0(input [31:0] x);
        sigma0 = rotr(x, 2) ^ rotr(x, 13) ^ rotr(x, 22);
    endfunction

    function [31:0] sigma1(input [31:0] x);
        sigma1 = rotr(x, 6) ^ rotr(x, 11) ^ rotr(x, 25);
    endfunction

    function [31:0] sig0(input [31:0] x);
        sig0 = rotr(x, 7) ^ rotr(x, 18) ^ (x >> 3);
    endfunction

    function [31:0] sig1(input [31:0] x);
        sig1 = rotr(x, 17) ^ rotr(x, 19) ^ (x >> 10);
    endfunction

    // 64 32-bit Round Constants (K_t)
    reg [31:0] kt;
    always @(*) begin
        case (round_cnt)
            6'd0:  kt = 32'h428a2f98; 6'd1:  kt = 32'h71374491; 6'd2:  kt = 32'hb5c0fbcf; 6'd3:  kt = 32'he9b5dba5;
            6'd4:  kt = 32'h3956c25b; 6'd5:  kt = 32'h59f111f1; 6'd6:  kt = 32'h923f82a4; 6'd7:  kt = 32'hab1c5ed5;
            6'd8:  kt = 32'hd807aa98; 6'd9:  kt = 32'h12835b01; 6'd10: kt = 32'h243185be; 6'd11: kt = 32'h550c7dc3;
            6'd12: kt = 32'h72be5d74; 6'd13: kt = 32'h80deb1fe; 6'd14: kt = 32'h9bdc06a7; 6'd15: kt = 32'hc19bf174;
            6'd16: kt = 32'he49b69c1; 6'd17: kt = 32'hefbe4786; 6'd18: kt = 32'h0fc19dc6; 6'd19: kt = 32'h240ca1cc;
            6'd20: kt = 32'h2de92c6f; 6'd21: kt = 32'h4a7484aa; 6'd22: kt = 32'h5cb0a9dc; 6'd23: kt = 32'h76f988da;
            6'd24: kt = 32'h983e5152; 6'd25: kt = 32'ha831c66d; 6'd26: kt = 32'hb00327c8; 6'd27: kt = 32'hbf597fc7;
            6'd28: kt = 32'hc6e00bf3; 6'd29: kt = 32'hd5a79147; 6'd30: kt = 32'h06ca6351; 6'd31: kt = 32'h14292967;
            6'd32: kt = 32'h27b70a85; 6'd33: kt = 32'h2e1b2138; 6'd34: kt = 32'h4d2c6dfc; 6'd35: kt = 32'h53380d13;
            6'd36: kt = 32'h650a7354; 6'd37: kt = 32'h766a0abb; 6'd38: kt = 32'h81c2c92e; 6'd39: kt = 32'h92722c85;
            6'd40: kt = 32'ha2bfe8a1; 6'd41: kt = 32'ha81a664b; 6'd42: kt = 32'hc24b8b70; 6'd43: kt = 32'hc76c51a3;
            6'd44: kt = 32'hd192e819; 6'd45: kt = 32'hd6990624; 6'd46: kt = 32'hf40e3585; 6'd47: kt = 32'h106aa070;
            6'd48: kt = 32'h19a4c116; 6'd49: kt = 32'h1e376c08; 6'd50: kt = 32'h2748774c; 6'd51: kt = 32'h34b0bcb5;
            6'd52: kt = 32'h391c0cb3; 6'd53: kt = 32'h4ed8aa4a; 6'd54: kt = 32'h5b9cca4f; 6'd55: kt = 32'h682e6ff3;
            6'd56: kt = 32'h748f82ee; 6'd57: kt = 32'h78a5636f; 6'd58: kt = 32'h84c87814; 6'd59: kt = 32'h8cc70208;
            6'd60: kt = 32'h90befffa; 6'd61: kt = 32'ha4506ceb; 6'd62: kt = 32'hbef9a3f7; 6'd63: kt = 32'hc67178f2;
            default: kt = 32'h00000000;
        endcase
    end

    // Next round computations
    wire [31:0] t1 = h + sigma1(e) + ch(e, f, g) + kt + w[0];
    wire [31:0] t2 = sigma0(a) + maj(a, b, c);
    wire [31:0] next_w15 = sig1(w[14]) + w[9] + sig0(w[1]) + w[0];

    integer j;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= STATE_IDLE;
            round_cnt    <= 6'd0;
            digest_valid <= 1'b0;
            H0 <= 32'h6a09e667; H1 <= 32'hbb67ae85; H2 <= 32'h3c6ef372; H3 <= 32'ha54ff53a;
            H4 <= 32'h510e527f; H5 <= 32'h9b05688c; H6 <= 32'h1f83d9ab; H7 <= 32'h5be0cd19;
            a <= 32'd0; b <= 32'd0; c <= 32'd0; d <= 32'd0;
            e <= 32'd0; f <= 32'd0; g <= 32'd0; h <= 32'd0;
            for (j = 0; j < 16; j = j + 1) w[j] <= 32'd0;
        end else begin
            digest_valid <= 1'b0;

            if (init) begin
                H0 <= 32'h6a09e667; H1 <= 32'hbb67ae85; H2 <= 32'h3c6ef372; H3 <= 32'ha54ff53a;
                H4 <= 32'h510e527f; H5 <= 32'h9b05688c; H6 <= 32'h1f83d9ab; H7 <= 32'h5be0cd19;
            end

            case (state)
                STATE_IDLE: begin
                    if (block_valid) begin
                        // Load working variables from accumulator
                        a <= H0; b <= H1; c <= H2; d <= H3;
                        e <= H4; f <= H5; g <= H6; h <= H7;

                        // Load initial 16 words from block_in (big-endian)
                        w[0]  <= block_in[511:480]; w[1]  <= block_in[479:448];
                        w[2]  <= block_in[447:416]; w[3]  <= block_in[415:384];
                        w[4]  <= block_in[383:352]; w[5]  <= block_in[351:320];
                        w[6]  <= block_in[319:288]; w[7]  <= block_in[287:256];
                        w[8]  <= block_in[255:224]; w[9]  <= block_in[223:192];
                        w[10] <= block_in[191:160]; w[11] <= block_in[159:128];
                        w[12] <= block_in[127:96];  w[13] <= block_in[95:64];
                        w[14] <= block_in[63:32];   w[15] <= block_in[31:0];

                        round_cnt <= 6'd0;
                        state     <= STATE_ROUNDS;
                    end
                end

                STATE_ROUNDS: begin
                    // Compression round update
                    h <= g;
                    g <= f;
                    f <= e;
                    e <= d + t1;
                    d <= c;
                    c <= b;
                    b <= a;
                    a <= t1 + t2;

                    // Message schedule shift update
                    for (j = 0; j < 15; j = j + 1) begin
                        w[j] <= w[j+1];
                    end
                    w[15] <= next_w15;

                    if (round_cnt == 6'd63) begin
                        state <= STATE_ACCUMULATE;
                    end else begin
                        round_cnt <= round_cnt + 6'd1;
                    end
                end

                STATE_ACCUMULATE: begin
                    // Accumulate round results into running hash registers
                    H0 <= H0 + a;
                    H1 <= H1 + b;
                    H2 <= H2 + c;
                    H3 <= H3 + d;
                    H4 <= H4 + e;
                    H5 <= H5 + f;
                    H6 <= H6 + g;
                    H7 <= H7 + h;

                    digest_valid <= 1'b1;
                    state        <= STATE_IDLE;
                end

                default: begin
                    state <= STATE_IDLE;
                end
            endcase
        end
    end

endmodule
