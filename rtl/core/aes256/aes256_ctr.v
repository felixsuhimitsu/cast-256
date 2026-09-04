`timescale 1ns/1ps
// AES-256 Counter (CTR) Mode Hardware Engine
// Standard compliance: NIST SP 800-38A
// Generates keystream block: Keystream = AES256_ECB(Key, Counter)
// Ciphertext/Plaintext: Data_Out = Data_In ^ Keystream
// Increments 128-bit Counter big-endian integer by 1 after each block
module aes256_ctr (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,        // Strobe to encrypt/decrypt a 128-bit block
    input  wire         load_iv,      // Strobe to load a new IV/Counter
    input  wire [255:0] key,          // 256-bit Cipher Key
    input  wire [127:0] iv,           // 128-bit Initial Counter / Nonce
    input  wire [127:0] data_in,      // 128-bit Plaintext or Ciphertext block
    output reg  [127:0] data_out,     // 128-bit Transformed block
    output wire [127:0] counter_out,  // Current running counter value
    output wire         ready,        // Ready to accept start
    output reg          valid         // Data output valid strobe (1 cycle)
);

    reg [127:0] counter_reg;
    reg         core_start;
    wire        core_ready;
    wire        core_valid;
    wire [127:0] keystream;

    assign counter_out = counter_reg;

    localparam CTR_IDLE = 1'b0;
    localparam CTR_BUSY = 1'b1;
    reg state;

    aes256_core u_aes_core (
        .clk(clk),
        .rst_n(rst_n),
        .start(core_start),
        .key(key),
        .block_in(counter_reg),
        .block_out(keystream),
        .ready(core_ready),
        .valid(core_valid)
    );

    assign ready = (state == CTR_IDLE) && core_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter_reg     <= 128'd0;
            data_out        <= 128'd0;
            core_start      <= 1'b0;
            valid           <= 1'b0;
            state           <= CTR_IDLE;
        end else begin
            valid      <= 1'b0;
            core_start <= 1'b0;

            if (load_iv) begin
                counter_reg <= iv;
            end

            case (state)
                CTR_IDLE: begin
                    if (start && core_ready) begin
                        core_start <= 1'b1;
                        state      <= CTR_BUSY;
                    end
                end

                CTR_BUSY: begin
                    if (core_valid) begin
                        data_out    <= data_in ^ keystream;
                        counter_reg <= counter_reg + 128'd1; // NIST SP 800-38A standard increment
                        valid       <= 1'b1;
                        state       <= CTR_IDLE;
                    end
                end

                default: begin
                    state <= CTR_IDLE;
                end
            endcase
        end
    end

endmodule
