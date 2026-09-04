`timescale 1ns/1ps

// Outbound Packet Framer & Serializer
// Accepts plaintext from loopback buffer, encrypts via AES-256 CTR,
// computes SHA-256 MAC, and streams deterministic packet to UART TX
module packet_framer (
    input  wire         clk,
    input  wire         rst_n,

    // Loopback Trigger
    input  wire         start_tx,
    input  wire [15:0]  tx_payload_len, // L (16..448)
    input  wire [127:0] tx_payload_iv,

    // Plaintext Buffer Read Interface
    output reg  [8:0]   pt_raddr,
    input  wire [7:0]   pt_rdata,

    // Arbiter Interface
    output reg          tx_done,

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

    // UART TX Interface
    output reg  [7:0]   uart_tx_data,
    output reg          uart_tx_start,
    input  wire         uart_tx_busy,

    // Status LED Strobe
    output reg          tx_active_pulse
);

    localparam ST_IDLE       = 4'd0;
    localparam ST_ENC_LD     = 4'd1;
    localparam ST_ENC_WAIT   = 4'd2;
    localparam ST_ENC_RD     = 4'd3;
    localparam ST_ENC_EXEC   = 4'd4;
    localparam ST_ENC_STORE  = 4'd5;
    localparam ST_SHA_INIT   = 4'd6;
    localparam ST_SHA_WAIT   = 4'd7;
    localparam ST_STREAM_PUT = 4'd8;
    localparam ST_STREAM_ACK = 4'd9;
    localparam ST_STREAM_NXT = 4'd10;
    localparam ST_DONE       = 4'd11;

    localparam S_PRE1   = 4'd0;
    localparam S_PRE2   = 4'd1;
    localparam S_LEN_H  = 4'd2;
    localparam S_LEN_L  = 4'd3;
    localparam S_IV     = 4'd4;
    localparam S_CIPHER = 4'd5;
    localparam S_MAC    = 4'd6;
    localparam S_POST1  = 4'd7;
    localparam S_POST2  = 4'd8;

    reg [3:0] state;

    wire [15:0]  frame_len = tx_payload_len;
    wire [127:0] frame_iv  = tx_payload_iv;
    reg  [255:0] frame_mac;
    reg  [127:0] shifter_128;

    // Encryption block sequencer
    reg [8:0]   enc_byte_idx;
    reg [3:0]   enc_sub_cnt;
    wire        enc_writing = (|enc_sub_cnt);

    assign aes_iv      = frame_iv;
    assign aes_data_in = shifter_128;

    // TX Serial Ciphertext RAM
    (* syn_ramstyle = "block_ram", no_rw_check *)
    reg [7:0] tx_cipher_ram [0:511];
    reg [8:0] tx_raddr;
    reg [7:0] tx_rdata;
    wire       tx_ram_wr_en   = (state == ST_ENC_STORE) && (aes_valid || enc_writing);
    wire [8:0] tx_ram_wr_addr = enc_byte_idx + {5'd0, enc_sub_cnt};
    wire [7:0] tx_ram_wr_data = aes_valid ? aes_data_out[127:120] : shifter_128[127:120];

    always @(posedge clk) begin
        if (tx_ram_wr_en) begin
            tx_cipher_ram[tx_ram_wr_addr] <= tx_ram_wr_data;
        end
        tx_rdata <= tx_cipher_ram[tx_raddr];
    end

    // Stream serializer registers
    reg [3:0] stream_phase;
    reg [4:0] stream_cnt;
    reg [8:0] stream_cipher_cnt;

    // Multiplex byte to send across stream
    reg [7:0] next_tx_byte;
    always @(*) begin
        case (stream_phase)
            S_PRE1:   next_tx_byte = 8'hAA;
            S_PRE2:   next_tx_byte = 8'h55;
            S_LEN_H:  next_tx_byte = frame_len[15:8];
            S_LEN_L:  next_tx_byte = frame_len[7:0];
            S_IV:     next_tx_byte = shifter_128[127:120];
            S_CIPHER: next_tx_byte = tx_rdata;
            S_MAC:    next_tx_byte = frame_mac[255:248];
            S_POST1:  next_tx_byte = 8'h0D;
            default:  next_tx_byte = 8'h0A; // S_POST2
        endcase
    end

    reg [4:0] sha_init_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state             <= ST_IDLE;
            tx_done           <= 1'b0;
            sha_pad_start     <= 1'b0;
            sha_pad_len       <= 16'd0;
            sha_buf_wr_en     <= 1'b0;
            sha_buf_wr_addr   <= 9'd0;
            sha_buf_wr_data   <= 8'd0;
            aes_start         <= 1'b0;
            aes_load_iv       <= 1'b0;
            uart_tx_data      <= 8'd0;
            uart_tx_start     <= 1'b0;
            tx_active_pulse   <= 1'b0;
            frame_mac         <= 256'd0;
            shifter_128       <= 128'd0;
            pt_raddr          <= 9'd0;
            tx_raddr          <= 9'd0;
            enc_byte_idx      <= 9'd0;
            enc_sub_cnt       <= 4'd0;
            stream_phase      <= S_PRE1;
            stream_cnt        <= 5'd0;
            stream_cipher_cnt <= 9'd0;
            sha_init_cnt      <= 5'd0;
        end else begin
            tx_done         <= 1'b0;
            sha_pad_start   <= 1'b0;
            sha_buf_wr_en   <= 1'b0;
            aes_start       <= 1'b0;
            aes_load_iv     <= 1'b0;
            uart_tx_start   <= 1'b0;
            tx_active_pulse <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (start_tx) begin
                        aes_load_iv     <= 1'b1;
                        enc_byte_idx    <= 9'd0;
                        enc_sub_cnt     <= 4'd0;
                        tx_active_pulse <= 1'b1;
                        state           <= ST_ENC_LD;
                    end
                end

                ST_ENC_LD: begin
                    pt_raddr <= enc_byte_idx + {5'd0, enc_sub_cnt};
                    state    <= ST_ENC_WAIT;
                end

                ST_ENC_WAIT: begin
                    // 1 cycle wait for synchronous read latency
                    state <= ST_ENC_RD;
                end

                ST_ENC_RD: begin
                    shifter_128 <= {shifter_128[119:0], pt_rdata};
                    if (enc_sub_cnt == 4'd15) begin // 16 bytes assembled
                        state <= ST_ENC_EXEC;
                    end else begin
                        enc_sub_cnt <= enc_sub_cnt + 4'd1;
                        state       <= ST_ENC_LD;
                    end
                end

                ST_ENC_EXEC: begin
                    if (aes_ready) begin
                        aes_start   <= 1'b1;
                        enc_sub_cnt <= 4'd0;
                        state       <= ST_ENC_STORE;
                    end
                end

                ST_ENC_STORE: begin
                    if (aes_valid || enc_writing) begin
                        sha_buf_wr_en   <= 1'b1;
                        sha_buf_wr_addr <= 9'd18 + enc_byte_idx + {5'd0, enc_sub_cnt};
                        sha_buf_wr_data <= aes_valid ? aes_data_out[127:120] : shifter_128[127:120];

                        shifter_128 <= aes_valid ? {aes_data_out[119:0], 8'd0} : {shifter_128[119:0], 8'd0};

                        if (enc_sub_cnt == 4'd15) begin
                            enc_byte_idx <= enc_byte_idx + 9'd16;
                            if (enc_byte_idx + 9'd16 >= frame_len[8:0]) begin
                                // All blocks encrypted!
                                sha_init_cnt <= 5'd0;
                                state        <= ST_SHA_INIT;
                            end else begin
                                enc_sub_cnt <= 4'd0;
                                state       <= ST_ENC_LD;
                            end
                        end else begin
                            enc_sub_cnt <= enc_sub_cnt + 4'd1;
                        end
                    end
                end

                ST_SHA_INIT: begin
                    // Write LEN (2B) and IV (16B) to Framing BSRAM (indices 0..17)
                    sha_buf_wr_en <= 1'b1;
                    if (sha_init_cnt == 5'd0) begin
                        sha_buf_wr_addr <= 9'd0;
                        sha_buf_wr_data <= frame_len[15:8];
                        sha_init_cnt    <= 5'd1;
                    end else if (sha_init_cnt == 5'd1) begin
                        sha_buf_wr_addr <= 9'd1;
                        sha_buf_wr_data <= frame_len[7:0];
                        shifter_128     <= frame_iv;
                        sha_init_cnt    <= 5'd2;
                    end else if (sha_init_cnt <= 5'd17) begin
                        sha_buf_wr_addr <= {4'd0, sha_init_cnt};
                        sha_buf_wr_data <= shifter_128[127:120];
                        shifter_128     <= {shifter_128[119:0], 8'd0};
                        if (sha_init_cnt == 5'd17) begin
                            sha_pad_len   <= 16'd18 + frame_len;
                            sha_pad_start <= 1'b1;
                            state         <= ST_SHA_WAIT;
                        end else begin
                            sha_init_cnt  <= sha_init_cnt + 5'd1;
                        end
                    end
                end

                ST_SHA_WAIT: begin
                    if (sha_pad_done) begin
                        frame_mac         <= sha_digest;
                        shifter_128       <= frame_iv;
                        stream_phase      <= S_PRE1;
                        stream_cnt        <= 5'd0;
                        stream_cipher_cnt <= 9'd0;
                        tx_raddr          <= 9'd0;
                        state             <= ST_STREAM_PUT;
                    end
                end

                // Serialization over UART TX
                ST_STREAM_PUT: begin
                    tx_active_pulse <= 1'b1;
                    if (!uart_tx_busy) begin
                        uart_tx_data  <= next_tx_byte;
                        uart_tx_start <= 1'b1;
                        if (stream_phase == S_CIPHER) begin
                            tx_raddr <= stream_cipher_cnt + 9'd1;
                        end
                        state <= ST_STREAM_ACK;
                    end
                end

                ST_STREAM_ACK: begin
                    tx_active_pulse <= 1'b1;
                    if (uart_tx_busy) begin
                        state <= ST_STREAM_NXT;
                    end
                end

                ST_STREAM_NXT: begin
                    tx_active_pulse <= 1'b1;
                    if (!uart_tx_busy) begin
                        state <= ST_STREAM_PUT;
                        case (stream_phase)
                            S_PRE1:  stream_phase <= S_PRE2;
                            S_PRE2:  stream_phase <= S_LEN_H;
                            S_LEN_H: stream_phase <= S_LEN_L;
                            S_LEN_L: begin
                                stream_phase <= S_IV;
                                stream_cnt   <= 5'd0;
                            end
                            S_IV: begin
                                shifter_128 <= {shifter_128[119:0], 8'd0};
                                if (stream_cnt == 5'd15) begin
                                    stream_phase      <= S_CIPHER;
                                    stream_cipher_cnt <= 9'd0;
                                end else begin
                                    stream_cnt <= stream_cnt + 5'd1;
                                end
                            end
                            S_CIPHER: begin
                                if (stream_cipher_cnt == frame_len[8:0] - 9'd1) begin
                                    stream_phase <= S_MAC;
                                    stream_cnt   <= 5'd0;
                                end else begin
                                    stream_cipher_cnt <= stream_cipher_cnt + 9'd1;
                                end
                            end
                            S_MAC: begin
                                frame_mac <= {frame_mac[247:0], 8'd0};
                                if (stream_cnt == 5'd31) begin
                                    stream_phase <= S_POST1;
                                end else begin
                                    stream_cnt <= stream_cnt + 5'd1;
                                end
                            end
                            S_POST1: stream_phase <= S_POST2;
                            S_POST2: begin
                                state   <= ST_DONE;
                            end
                            default: state <= ST_DONE;
                        endcase
                    end
                end

                ST_DONE: begin
                    tx_done <= 1'b1;
                    state   <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
