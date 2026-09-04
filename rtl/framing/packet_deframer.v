`timescale 1ns/1ps

// Inbound Packet Deframer & Authentication Engine
// Ingests [PREAMBLE (0xAA55) | LEN (2B) | IV (16B) | CIPHERTEXT (L) | MAC (32B) | POSTAMBLE (0x0D0A)]
// Holds ciphertext in Quarantine BSRAM until SHA-256 MAC validates
// Executes Gated AES-CTR decryption strictly upon MAC pass
module packet_deframer (
    input  wire         clk,
    input  wire         rst_n,

    // UART RX Interface
    input  wire [7:0]   rx_data,
    input  wire         rx_valid,
    input  wire         rx_frame_err,

    // Arbiter Interface
    output reg          rx_preamble_match,
    output reg          rx_done,

    // SHA-256 Padder Interface
    output reg          sha_pad_start,
    output reg  [15:0]  sha_pad_len,
    output reg          sha_buf_wr_en,
    output reg  [8:0]   sha_buf_wr_addr,
    output reg  [7:0]   sha_buf_wr_data,
    input  wire         sha_pad_busy,
    input  wire         sha_pad_done,
    input  wire [255:0] sha_digest,

    // AES-256 CTR Interface
    output reg          aes_start,
    output reg          aes_load_iv,
    output wire [127:0] aes_iv,
    output wire [127:0] aes_data_in,
    input  wire [127:0] aes_data_out,
    input  wire         aes_ready,
    input  wire         aes_valid,

    // Plaintext Loopback Buffer Write Interface
    output reg          pt_buf_wr_en,
    output reg  [8:0]   pt_buf_wr_addr,
    output reg  [7:0]   pt_buf_wr_data,
    output wire [15:0]  pt_payload_len,
    output wire [127:0] pt_payload_iv,
    output reg          pt_valid,

    // Status LED Strobes
    output reg          rx_pass_pulse,
    output reg          mac_err_pulse
);

    // Timeout: 2.5 ms = 67,500 cycles @ 27.0 MHz
    localparam TIMEOUT_CYCLES = 67500;

    localparam ST_IDLE       = 4'd0;
    localparam ST_PRE1       = 4'd1;
    localparam ST_LEN_H      = 4'd2;
    localparam ST_LEN_L      = 4'd3;
    localparam ST_IV         = 4'd4;
    localparam ST_CIPHER     = 4'd5;
    localparam ST_MAC        = 4'd6;
    localparam ST_POST1      = 4'd7;
    localparam ST_POST2      = 4'd8;
    localparam ST_SHA_WAIT   = 4'd9;
    localparam ST_VERIFY       = 4'd10;
    localparam ST_DECRYPT_LD   = 4'd11;
    localparam ST_DECRYPT_WAIT = 4'd12;
    localparam ST_DECRYPT_RD   = 4'd13;
    localparam ST_DECRYPT_EX   = 4'd14;
    localparam ST_DECRYPT_WR   = 4'd15;

    reg [3:0]  state;
    reg [16:0] timeout_cnt;

    // Frame Fields
    reg [15:0]  frame_len;       // Ciphertext byte length L (16..448)
    reg [15:0]  byte_cnt;
    reg [127:0] frame_iv;
    reg [255:0] frame_mac;

    // Quarantine BSRAM (holds unauthenticated ciphertext)
    (* syn_ramstyle = "block_ram", no_rw_check *)
    reg [7:0] quarantine_ram [0:511];
    reg [8:0] q_raddr;
    reg [7:0] q_rdata;
    wire       q_wr_en   = (state == ST_CIPHER) && rx_valid;
    wire [8:0] q_wr_addr = byte_cnt[8:0];
    wire [7:0] q_wr_data = rx_data;

    always @(posedge clk) begin
        if (q_wr_en) begin
            quarantine_ram[q_wr_addr] <= q_wr_data;
        end
        q_rdata <= quarantine_ram[q_raddr];
    end

    // Decryption block sequencer
    reg [8:0]   dec_byte_idx;
    reg [3:0]   dec_sub_cnt;
    wire        dec_writing = (|dec_sub_cnt);
    reg [127:0] dec_block_in;

    assign aes_iv         = frame_iv;
    assign aes_data_in    = dec_block_in;
    assign pt_payload_len = frame_len;
    assign pt_payload_iv  = frame_iv;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state             <= ST_IDLE;
            rx_preamble_match <= 1'b0;
            rx_done           <= 1'b0;
            sha_pad_start     <= 1'b0;
            sha_pad_len       <= 16'd0;
            sha_buf_wr_en     <= 1'b0;
            sha_buf_wr_addr   <= 9'd0;
            sha_buf_wr_data   <= 8'd0;
            aes_start         <= 1'b0;
            aes_load_iv       <= 1'b0;
            pt_buf_wr_en      <= 1'b0;
            pt_buf_wr_addr    <= 9'd0;
            pt_buf_wr_data    <= 8'd0;
            pt_valid          <= 1'b0;
            rx_pass_pulse     <= 1'b0;
            mac_err_pulse     <= 1'b0;
            timeout_cnt       <= 17'd0;
            frame_len         <= 16'd0;
            byte_cnt          <= 16'd0;
            frame_iv          <= 128'd0;
            frame_mac         <= 256'd0;
            q_raddr           <= 9'd0;
            dec_byte_idx      <= 9'd0;
            dec_sub_cnt       <= 4'd0;
            dec_block_in      <= 128'd0;
        end else begin
            rx_preamble_match <= 1'b0;
            rx_done           <= 1'b0;
            sha_pad_start     <= 1'b0;
            sha_buf_wr_en     <= 1'b0;
            aes_start         <= 1'b0;
            aes_load_iv       <= 1'b0;
            pt_buf_wr_en      <= 1'b0;
            pt_valid          <= 1'b0;
            rx_pass_pulse     <= 1'b0;
            mac_err_pulse     <= 1'b0;

            // Timeout watchdog (inter-byte silence detector)
            if (state != ST_IDLE && state != ST_PRE1) begin
                if (rx_valid || (state >= ST_SHA_WAIT)) begin
                    timeout_cnt <= 17'd0;
                end else if (timeout_cnt >= TIMEOUT_CYCLES) begin
                    mac_err_pulse <= 1'b1;
                    rx_done       <= 1'b1;
                    state         <= ST_IDLE;
                end else begin
                    timeout_cnt <= timeout_cnt + 17'd1;
                end
            end else begin
                timeout_cnt <= 17'd0;
            end

            // Framing error watchdog
            if (rx_frame_err && (state != ST_IDLE && state != ST_PRE1)) begin
                mac_err_pulse <= 1'b1;
                rx_done       <= 1'b1;
                state         <= ST_IDLE;
            end

            case (state)
                ST_IDLE: begin
                    byte_cnt <= 16'd0;
                    if (rx_valid && rx_data == 8'hAA) begin
                        state <= ST_PRE1;
                    end
                end

                ST_PRE1: begin
                    if (rx_valid) begin
                        if (rx_data == 8'h55) begin
                            rx_preamble_match <= 1'b1;
                            timeout_cnt       <= 17'd0;
                            state             <= ST_LEN_H;
                        end else if (rx_data == 8'hAA) begin
                            state <= ST_PRE1; // Stay in PRE1 on duplicate 0xAA
                        end else begin
                            state <= ST_IDLE;
                        end
                    end
                end

                ST_LEN_H: begin
                    if (rx_valid) begin
                        frame_len[15:8] <= rx_data;
                        // Write to Framing BSRAM at index 0
                        sha_buf_wr_en   <= 1'b1;
                        sha_buf_wr_addr <= 9'd0;
                        sha_buf_wr_data <= rx_data;
                        state           <= ST_LEN_L;
                    end
                end

                ST_LEN_L: begin
                    if (rx_valid) begin
                        frame_len[7:0]  <= rx_data;
                        // Write to Framing BSRAM at index 1
                        sha_buf_wr_en   <= 1'b1;
                        sha_buf_wr_addr <= 9'd1;
                        sha_buf_wr_data <= rx_data;
                        byte_cnt        <= 16'd0;
                        state           <= ST_IV;
                    end
                end

                ST_IV: begin
                    if (rx_valid) begin
                        frame_iv <= {frame_iv[119:0], rx_data};
                        // Write IV to Framing BSRAM at indices 2..17
                        sha_buf_wr_en   <= 1'b1;
                        sha_buf_wr_addr <= 9'd2 + byte_cnt[8:0];
                        sha_buf_wr_data <= rx_data;

                        if (byte_cnt == 16'd15) begin
                            byte_cnt <= 16'd0;
                            state    <= ST_CIPHER;
                        end else begin
                            byte_cnt <= byte_cnt + 16'd1;
                        end
                    end
                end

                ST_CIPHER: begin
                    if (rx_valid) begin
                        // Also write to Framing BSRAM (offset 18)
                        sha_buf_wr_en   <= 1'b1;
                        sha_buf_wr_addr <= 9'd18 + byte_cnt[8:0];
                        sha_buf_wr_data <= rx_data;

                        if (byte_cnt == frame_len - 16'd1) begin
                            byte_cnt <= 16'd0;
                            state    <= ST_MAC;
                        end else begin
                            byte_cnt <= byte_cnt + 16'd1;
                        end
                    end
                end

                ST_MAC: begin
                    if (rx_valid) begin
                        frame_mac <= {frame_mac[247:0], rx_data};
                        if (byte_cnt == 16'd31) begin
                            state <= ST_POST1;
                        end else begin
                            byte_cnt <= byte_cnt + 16'd1;
                        end
                    end
                end

                ST_POST1: begin
                    if (rx_valid) begin
                        if (rx_data == 8'h0D) begin
                            state <= ST_POST2;
                        end else begin
                            // Postamble byte 1 invalid
                            mac_err_pulse <= 1'b1;
                            rx_done       <= 1'b1;
                            state         <= ST_IDLE;
                        end
                    end
                end

                ST_POST2: begin
                    if (rx_valid) begin
                        if (rx_data == 8'h0A) begin
                            // Frame parsing complete! Trigger SHA-256 Padder
                            // Total authenticated bytes = 18 + frame_len
                            sha_pad_len   <= 16'd18 + frame_len;
                            sha_pad_start <= 1'b1;
                            state         <= ST_SHA_WAIT;
                        end else begin
                            mac_err_pulse <= 1'b1;
                            rx_done       <= 1'b1;
                            state         <= ST_IDLE;
                        end
                    end
                end

                ST_SHA_WAIT: begin
                    if (sha_pad_done) begin
                        state <= ST_VERIFY;
                    end
                end

                ST_VERIFY: begin
                    // Compare calculated digest with received MAC
                    if (sha_digest == frame_mac) begin
                        // AUTHENTICATION PASSED!
                        // Prepare Gated Decryption pass over Quarantine BSRAM
                        rx_pass_pulse  <= 1'b1;
                        aes_load_iv    <= 1'b1;
                        dec_byte_idx   <= 9'd0;
                        dec_sub_cnt    <= 4'd0;
                        q_raddr        <= 9'd0;
                        state          <= ST_DECRYPT_LD;
                    end else begin
                        // AUTHENTICATION FAILED!
                        mac_err_pulse <= 1'b1;
                        rx_done       <= 1'b1; // Release arbiter lock immediately
                        state         <= ST_IDLE;
                    end
                end

                // Gated Decryption Pipeline
                ST_DECRYPT_LD: begin
                    // Fetch 16 bytes of ciphertext from Quarantine BSRAM
                    q_raddr <= dec_byte_idx + {5'd0, dec_sub_cnt};
                    state   <= ST_DECRYPT_WAIT;
                end

                ST_DECRYPT_WAIT: begin
                    // 1 cycle wait for synchronous BSRAM read latency
                    state <= ST_DECRYPT_RD;
                end

                ST_DECRYPT_RD: begin
                    // Latch data from RAM into 128-bit shift register
                    dec_block_in <= {dec_block_in[119:0], q_rdata};
                    if (dec_sub_cnt == 4'd15) begin // Finished all 16 bytes
                        state <= ST_DECRYPT_EX;
                    end else begin
                        dec_sub_cnt <= dec_sub_cnt + 4'd1;
                        state       <= ST_DECRYPT_LD;
                    end
                end

                ST_DECRYPT_EX: begin
                    if (aes_ready) begin
                        aes_start   <= 1'b1;
                        dec_sub_cnt <= 4'd0;
                        state       <= ST_DECRYPT_WR;
                    end
                end

                ST_DECRYPT_WR: begin
                    if (aes_valid || dec_writing) begin
                        // Write 16 decrypted bytes into Plaintext Loopback Buffer
                        pt_buf_wr_en   <= 1'b1;
                        pt_buf_wr_addr <= dec_byte_idx + {5'd0, dec_sub_cnt};
                        pt_buf_wr_data <= aes_valid ? aes_data_out[127:120] : dec_block_in[127:120];
                        dec_block_in   <= aes_valid ? {aes_data_out[119:0], 8'd0} : {dec_block_in[119:0], 8'd0};

                        if (dec_sub_cnt == 4'd15) begin
                            dec_byte_idx <= dec_byte_idx + 9'd16;
                            if (dec_byte_idx + 9'd16 >= frame_len[8:0]) begin
                                // All blocks decrypted and committed!
                                pt_valid       <= 1'b1;
                                rx_done        <= 1'b1; // Release arbiter lock
                                state          <= ST_IDLE;
                            end else begin
                                dec_sub_cnt <= 4'd0;
                                state       <= ST_DECRYPT_LD;
                            end
                        end else begin
                            dec_sub_cnt <= dec_sub_cnt + 4'd1;
                        end
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
