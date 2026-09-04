`timescale 1ns/1ps

// Autonomous Hardware Message Padder & Scheduler for SHA-256
// Ingests up to 512 bytes of frame data into internal Framing BSRAM partition
// Autonomous state machine appends 0x80, variable zero-fill, and 64-bit length
// Dispatches 512-bit blocks sequentially to sha256_core (65 cycles per block)
module sha256_padder (
    input  wire         clk,
    input  wire         rst_n,

    // Buffer Write Interface (e.g. from UART RX or TX Assembler)
    input  wire         buf_wr_en,
    input  wire [8:0]   buf_wr_addr,   // 0 .. 511
    input  wire [7:0]   buf_wr_data,

    // Padding Control Interface
    input  wire         start_pad,     // Strobe to start hashing
    input  wire [15:0]  msg_len,       // Length in bytes (0 .. 466)
    output wire         busy,          // High while padder/core is operating
    output reg          done,          // High for 1 cycle when final digest is valid
    output wire [255:0] digest         // 256-bit Output Digest
);

    // Internal 512-byte Dual-Port Framing Memory
    (* syn_ramstyle = "block_ram", no_rw_check *)
    reg [7:0] framing_ram [0:511];
    reg [7:0] mem_rdata;
    reg [8:0] mem_raddr;

    always @(posedge clk) begin
        if (buf_wr_en) begin
            framing_ram[buf_wr_addr] <= buf_wr_data;
        end
        mem_rdata <= framing_ram[mem_raddr];
    end

    // Core Instantiation
    reg          core_init;
    reg          core_block_valid;
    wire [511:0] core_block_in;
    wire         core_ready;
    wire         core_digest_valid;

    sha256_core u_sha256_core (
        .clk(clk),
        .rst_n(rst_n),
        .init(core_init),
        .block_valid(core_block_valid),
        .block_in(core_block_in),
        .ready(core_ready),
        .digest_valid(core_digest_valid),
        .digest(digest)
    );

    // State Machine Definitions
    localparam PAD_IDLE       = 3'd0;
    localparam PAD_INIT_CORE  = 3'd1;
    localparam PAD_FETCH_BYTE = 3'd2;
    localparam PAD_LATCH_BYTE = 3'd3;
    localparam PAD_DISPATCH   = 3'd4;
    localparam PAD_WAIT_CORE  = 3'd5;
    localparam PAD_DONE_ST    = 3'd6;

    reg [2:0] state;

    reg [15:0] total_len;
    reg [3:0]  total_blocks;
    reg [3:0]  curr_block;
    reg [5:0]  byte_idx;      // 0 .. 63 within current block
    reg [511:0] block_builder;

    assign busy = (state != PAD_IDLE);

    // Calculate byte value for current block position (curr_block, byte_idx)
    wire [15:0] global_idx = {7'd0, curr_block[2:0], byte_idx};
    wire is_last_block = (curr_block == total_blocks - 4'd1);

    reg [7:0] constructed_byte;
    always @(*) begin
        if (global_idx < total_len) begin
            constructed_byte = mem_rdata;
        end else if (global_idx == total_len) begin
            constructed_byte = 8'h80;
        end else if (is_last_block && (byte_idx >= 6'd56)) begin
            if (byte_idx == 6'd61) begin
                constructed_byte = {5'd0, total_len[15:13]};
            end else if (byte_idx == 6'd62) begin
                constructed_byte = total_len[12:5];
            end else if (byte_idx == 6'd63) begin
                constructed_byte = {total_len[4:0], 3'b000};
            end else begin
                constructed_byte = 8'h00;
            end
        end else begin
            constructed_byte = 8'h00;
        end
    end

    assign core_block_in = block_builder;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= PAD_IDLE;
            core_init        <= 1'b0;
            core_block_valid <= 1'b0;
            total_len        <= 16'd0;
            total_blocks     <= 4'd0;
            curr_block       <= 4'd0;
            byte_idx         <= 6'd0;
            block_builder    <= 512'd0;
            mem_raddr        <= 9'd0;
            done             <= 1'b0;
        end else begin
            core_init        <= 1'b0;
            core_block_valid <= 1'b0;
            done             <= 1'b0;

            case (state)
                PAD_IDLE: begin
                    if (start_pad) begin
                        total_len    <= msg_len;
                        // total_blocks = (msg_len + 9 + 63) / 64 = (msg_len + 72) >> 6
                        total_blocks <= (msg_len + 16'd72) >> 6;
                        curr_block   <= 4'd0;
                        byte_idx     <= 6'd0;
                        core_init    <= 1'b1;
                        state        <= PAD_INIT_CORE;
                    end
                end

                PAD_INIT_CORE: begin
                    // Set up memory address for first byte
                    mem_raddr <= {curr_block[2:0], 6'd0};
                    state     <= PAD_FETCH_BYTE;
                end

                PAD_FETCH_BYTE: begin
                    // Address registered in RAM, wait 1 cycle for synchronous read
                    state <= PAD_LATCH_BYTE;
                end

                PAD_LATCH_BYTE: begin
                    // Latch constructed byte into 512-bit shift register
                    block_builder <= {block_builder[503:0], constructed_byte};

                    if (byte_idx == 6'd63) begin
                        // Full 512-bit block assembled
                        state <= PAD_DISPATCH;
                    end else begin
                        byte_idx  <= byte_idx + 6'd1;
                        mem_raddr <= {curr_block[2:0], byte_idx + 6'd1};
                        state     <= PAD_FETCH_BYTE;
                    end
                end

                PAD_DISPATCH: begin
                    if (core_ready) begin
                        core_block_valid <= 1'b1;
                        state            <= PAD_WAIT_CORE;
                    end
                end

                PAD_WAIT_CORE: begin
                    if (core_digest_valid) begin
                        if (curr_block == total_blocks - 4'd1) begin
                            // Final block processed
                            done  <= 1'b1;
                            state <= PAD_IDLE;
                        end else begin
                            // Advance to next 512-bit block
                            curr_block <= curr_block + 4'd1;
                            byte_idx   <= 6'd0;
                            mem_raddr  <= {curr_block[2:0] + 3'd1, 6'd0};
                            state      <= PAD_FETCH_BYTE;
                        end
                    end
                end

                default: begin
                    state <= PAD_IDLE;
                end
            endcase
        end
    end

endmodule
