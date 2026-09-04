`timescale 1ns/1ps
// 14-Round Iterative AES-256 Forward Cipher Datapath
// Instantiates 16 parallel Canright composite Galois field S-Boxes
// Consumes 1 round per clock cycle (14 cycles total for full 128-bit transformation)
module aes256_core (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [255:0] key,
    input  wire [127:0] block_in,
    output wire [127:0] block_out,
    output reg          ready,
    output reg          valid
);

    localparam STATE_IDLE   = 1'b0;
    localparam STATE_ROUNDS = 1'b1;

    reg state;
    reg [3:0] round_cnt;
    reg [127:0] state_reg;

    // Key Expansion Engine instantiation
    // key_load is asserted combinational on start in IDLE so keys load on edge 0
    wire key_load = (state == STATE_IDLE && start);
    wire key_step = (state == STATE_ROUNDS && round_cnt != 4'd14);
    wire [127:0] round_key;

    aes256_key_expand u_key_expand (
        .clk(clk),
        .rst_n(rst_n),
        .load(key_load),
        .key_in(key),
        .step(key_step),
        .round_num(round_cnt),
        .round_key(round_key)
    );

    // 1. SubBytes: 16 parallel Canright S-Boxes
    wire [127:0] sb;
    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : gen_sbox
            aes_sbox_canright u_sbox (
                .in(state_reg[127 - 8*i -: 8]),
                .out(sb[127 - 8*i -: 8])
            );
        end
    endgenerate

    // 2. ShiftRows
    // Input state matrix (bytes 0..15):
    // [ sb0  sb4  sb8  sb12 ]
    // [ sb1  sb5  sb9  sb13 ]
    // [ sb2  sb6  sb10 sb14 ]
    // [ sb3  sb7  sb11 sb15 ]
    //
    // After row shifts (0, 1, 2, 3):
    // Row 0: sb0,  sb4,  sb8,  sb12
    // Row 1: sb5,  sb9,  sb13, sb1
    // Row 2: sb10, sb14, sb2,  sb6
    // Row 3: sb15, sb3,  sb7,  sb11
    wire [7:0] sr [0:15];
    assign sr[0]  = sb[127:120];
    assign sr[1]  = sb[87:80];
    assign sr[2]  = sb[47:40];
    assign sr[3]  = sb[7:0];

    assign sr[4]  = sb[95:88];
    assign sr[5]  = sb[55:48];
    assign sr[6]  = sb[15:8];
    assign sr[7]  = sb[103:96];

    assign sr[8]  = sb[63:56];
    assign sr[9]  = sb[23:16];
    assign sr[10] = sb[111:104];
    assign sr[11] = sb[71:64];

    assign sr[12] = sb[31:24];
    assign sr[13] = sb[119:112];
    assign sr[14] = sb[79:72];
    assign sr[15] = sb[39:32];

    wire [127:0] shift_rows_out = {
        sr[0],  sr[1],  sr[2],  sr[3],
        sr[4],  sr[5],  sr[6],  sr[7],
        sr[8],  sr[9],  sr[10], sr[11],
        sr[12], sr[13], sr[14], sr[15]
    };

    // 3. MixColumns (Galois Field GF(2^8) matrix multiplication)
    function [7:0] xtime(input [7:0] b);
        xtime = {b[6:0], 1'b0} ^ (b[7] ? 8'h1b : 8'h00);
    endfunction

    function [31:0] mix_single_col(input [7:0] a0, input [7:0] a1, input [7:0] a2, input [7:0] a3);
        reg [7:0] t, d0, d1, d2, d3;
        begin
            t  = a0 ^ a1 ^ a2 ^ a3;
            d0 = a0 ^ t ^ xtime(a0 ^ a1);
            d1 = a1 ^ t ^ xtime(a1 ^ a2);
            d2 = a2 ^ t ^ xtime(a2 ^ a3);
            d3 = a3 ^ t ^ xtime(a3 ^ a0);
            mix_single_col = {d0, d1, d2, d3};
        end
    endfunction

    wire [31:0] mc_col0 = mix_single_col(sr[0],  sr[1],  sr[2],  sr[3]);
    wire [31:0] mc_col1 = mix_single_col(sr[4],  sr[5],  sr[6],  sr[7]);
    wire [31:0] mc_col2 = mix_single_col(sr[8],  sr[9],  sr[10], sr[11]);
    wire [31:0] mc_col3 = mix_single_col(sr[12], sr[13], sr[14], sr[15]);

    wire [127:0] mix_cols_out = {mc_col0, mc_col1, mc_col2, mc_col3};

    // Final round (round 14) bypasses MixColumns
    wire [127:0] round_transform = (round_cnt == 4'd14) ? shift_rows_out : mix_cols_out;

    // 4. AddRoundKey
    wire [127:0] next_round_state = round_transform ^ round_key;

    assign block_out = state_reg;

    // Control FSM
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= STATE_IDLE;
            round_cnt <= 4'd0;
            state_reg <= 128'd0;
            ready     <= 1'b1;
            valid     <= 1'b0;
        end else begin
            valid <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    ready <= 1'b1;
                    if (start) begin
                        ready     <= 1'b0;
                        state_reg <= block_in ^ key[255:128]; // Round 0 ARK
                        round_cnt <= 4'd1;
                        state     <= STATE_ROUNDS;
                    end
                end

                STATE_ROUNDS: begin
                    state_reg <= next_round_state;
                    if (round_cnt == 4'd14) begin
                        valid     <= 1'b1;
                        ready     <= 1'b1;
                        state     <= STATE_IDLE;
                        round_cnt <= 4'd0;
                    end else begin
                        round_cnt <= round_cnt + 4'd1;
                    end
                end

                default: begin
                    state <= STATE_IDLE;
                end
            endcase
        end
    end

endmodule
