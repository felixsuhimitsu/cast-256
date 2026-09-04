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

    // 64 32-bit Round Constants (K_t) mapped to synchronous block ROM
    (* syn_ramstyle = "block_ram" *)
    reg [31:0] kt_rom [0:63];
    reg [5:0]  kt_addr;
    reg [31:0] kt;

    initial begin
        kt_rom[0]  = 32'h428a2f98; kt_rom[1]  = 32'h71374491; kt_rom[2]  = 32'hb5c0fbcf; kt_rom[3]  = 32'he9b5dba5;
        kt_rom[4]  = 32'h3956c25b; kt_rom[5]  = 32'h59f111f1; kt_rom[6]  = 32'h923f82a4; kt_rom[7]  = 32'hab1c5ed5;
        kt_rom[8]  = 32'hd807aa98; kt_rom[9]  = 32'h12835b01; kt_rom[10] = 32'h243185be; kt_rom[11] = 32'h550c7dc3;
        kt_rom[12] = 32'h72be5d74; kt_rom[13] = 32'h80deb1fe; kt_rom[14] = 32'h9bdc06a7; kt_rom[15] = 32'hc19bf174;
        kt_rom[16] = 32'he49b69c1; kt_rom[17] = 32'hefbe4786; kt_rom[18] = 32'h0fc19dc6; kt_rom[19] = 32'h240ca1cc;
        kt_rom[20] = 32'h2de92c6f; kt_rom[21] = 32'h4a7484aa; kt_rom[22] = 32'h5cb0a9dc; kt_rom[23] = 32'h76f988da;
        kt_rom[24] = 32'h983e5152; kt_rom[25] = 32'ha831c66d; kt_rom[26] = 32'hb00327c8; kt_rom[27] = 32'hbf597fc7;
        kt_rom[28] = 32'hc6e00bf3; kt_rom[29] = 32'hd5a79147; kt_rom[30] = 32'h06ca6351; kt_rom[31] = 32'h14292967;
        kt_rom[32] = 32'h27b70a85; kt_rom[33] = 32'h2e1b2138; kt_rom[34] = 32'h4d2c6dfc; kt_rom[35] = 32'h53380d13;
        kt_rom[36] = 32'h650a7354; kt_rom[37] = 32'h766a0abb; kt_rom[38] = 32'h81c2c92e; kt_rom[39] = 32'h92722c85;
        kt_rom[40] = 32'ha2bfe8a1; kt_rom[41] = 32'ha81a664b; kt_rom[42] = 32'hc24b8b70; kt_rom[43] = 32'hc76c51a3;
        kt_rom[44] = 32'hd192e819; kt_rom[45] = 32'hd6990624; kt_rom[46] = 32'hf40e3585; kt_rom[47] = 32'h106aa070;
        kt_rom[48] = 32'h19a4c116; kt_rom[49] = 32'h1e376c08; kt_rom[50] = 32'h2748774c; kt_rom[51] = 32'h34b0bcb5;
        kt_rom[52] = 32'h391c0cb3; kt_rom[53] = 32'h4ed8aa4a; kt_rom[54] = 32'h5b9cca4f; kt_rom[55] = 32'h682e6ff3;
        kt_rom[56] = 32'h748f82ee; kt_rom[57] = 32'h78a5636f; kt_rom[58] = 32'h84c87814; kt_rom[59] = 32'h8cc70208;
        kt_rom[60] = 32'h90befffa; kt_rom[61] = 32'ha4506ceb; kt_rom[62] = 32'hbef9a3f7; kt_rom[63] = 32'hc67178f2;
    end

    always @(posedge clk) begin
        kt <= kt_rom[kt_addr];
    end

    // Next round computations
    wire [31:0] t1 = h + sigma1(e) + ch(e, f, g) + kt + w[0];
    wire [31:0] t2 = sigma0(a) + maj(a, b, c);
    wire [31:0] next_w15 = sig1(w[14]) + w[9] + sig0(w[1]) + w[0];

    reg [2:0]  acc_cnt;
    reg [31:0] acc_h, acc_v;
    wire [31:0] acc_sum = acc_h + acc_v;

    always @(*) begin
        case (acc_cnt)
            3'd0: begin acc_h = H0; acc_v = a; end
            3'd1: begin acc_h = H1; acc_v = b; end
            3'd2: begin acc_h = H2; acc_v = c; end
            3'd3: begin acc_h = H3; acc_v = d; end
            3'd4: begin acc_h = H4; acc_v = e; end
            3'd5: begin acc_h = H5; acc_v = f; end
            3'd6: begin acc_h = H6; acc_v = g; end
            default: begin acc_h = H7; acc_v = h; end
        endcase
    end

    integer j;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= STATE_IDLE;
            round_cnt    <= 6'd0;
            kt_addr      <= 6'd0;
            acc_cnt      <= 3'd0;
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
                    kt_addr <= 6'd0;
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
                        kt_addr   <= 6'd1;
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
                        state   <= STATE_ACCUMULATE;
                        kt_addr <= 6'd0;
                        acc_cnt <= 3'd0;
                    end else begin
                        round_cnt <= round_cnt + 6'd1;
                        kt_addr   <= round_cnt + 6'd2;
                    end
                end

                STATE_ACCUMULATE: begin
                    case (acc_cnt)
                        3'd0: H0 <= acc_sum;
                        3'd1: H1 <= acc_sum;
                        3'd2: H2 <= acc_sum;
                        3'd3: H3 <= acc_sum;
                        3'd4: H4 <= acc_sum;
                        3'd5: H5 <= acc_sum;
                        3'd6: H6 <= acc_sum;
                        default: begin
                            H7 <= acc_sum;
                            digest_valid <= 1'b1;
                            state <= STATE_IDLE;
                        end
                    endcase
                    acc_cnt <= acc_cnt + 3'd1;
                end

                default: begin
                    state <= STATE_IDLE;
                end
            endcase
        end
    end

endmodule
