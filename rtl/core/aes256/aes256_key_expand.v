`timescale 1ns/1ps
// On-the-fly round key generator for AES-256 (Nr = 14)
// Generates round keys on each cycle using 4 shared Canright S-Boxes
module aes256_key_expand (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         load,
    input  wire [255:0] key_in,
    input  wire         step,
    input  wire [3:0]   round_num,
    output wire [127:0] round_key
);

    reg [127:0] w_hi;
    reg [127:0] w_lo;

    // Rcon lookup for step from odd round_num (1, 3, 5, 7, 9, 11, 13)
    reg [7:0] rcon;
    always @(*) begin
        case (round_num)
            4'd1:    rcon = 8'h01; // Step to Round 2
            4'd3:    rcon = 8'h02; // Step to Round 4
            4'd5:    rcon = 8'h04; // Step to Round 6
            4'd7:    rcon = 8'h08; // Step to Round 8
            4'd9:    rcon = 8'h10; // Step to Round 10
            4'd11:   rcon = 8'h20; // Step to Round 12
            4'd13:   rcon = 8'h40; // Step to Round 14
            default: rcon = 8'h00;
        endcase
    end

    // SubWord / RotWord multiplexer
    // On odd round_num (1, 3, 5, 7, 9, 11, 13): RotWord + SubWord + Rcon
    // On even round_num (2, 4, 6, 8, 10, 12): SubWord only
    wire [31:0] last_word = w_lo[31:0];
    wire is_rot = round_num[0]; // 1, 3, 5, 7, 9, 11, 13

    wire [31:0] sbox_in_word = is_rot ? {last_word[23:0], last_word[31:24]} : last_word;

    wire [31:0] sub_word;
    aes_sbox_canright u_sb3 (.in(sbox_in_word[31:24]), .out(sub_word[31:24]));
    aes_sbox_canright u_sb2 (.in(sbox_in_word[23:16]), .out(sub_word[23:16]));
    aes_sbox_canright u_sb1 (.in(sbox_in_word[15:8]),  .out(sub_word[15:8]));
    aes_sbox_canright u_sb0 (.in(sbox_in_word[7:0]),   .out(sub_word[7:0]));

    wire [31:0] temp_word = is_rot ? (sub_word ^ {rcon, 24'h000000}) : sub_word;

    // Next 4 words
    wire [31:0] next_w0 = w_hi[127:96] ^ temp_word;
    wire [31:0] next_w1 = w_hi[95:64]  ^ next_w0;
    wire [31:0] next_w2 = w_hi[63:32]  ^ next_w1;
    wire [31:0] next_w3 = w_hi[31:0]   ^ next_w2;
    wire [127:0] next_key = {next_w0, next_w1, next_w2, next_w3};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_hi <= 128'd0;
            w_lo <= 128'd0;
        end else if (load) begin
            w_hi <= key_in[255:128];
            w_lo <= key_in[127:0];
        end else if (step) begin
            w_hi <= w_lo;
            w_lo <= next_key;
        end
    end

    // Output current round key (w_lo)
    assign round_key = w_lo;

endmodule
