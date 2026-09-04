`timescale 1ns/1ps

// Hardware Mutual Exclusion Arbiter for Half-Duplex Transceiver
// Prioritizes inbound UART RX transactions over outbound TX packets
// Shares AES-256 and SHA-256 cryptographic hardware engines collision-free
module crypto_arbiter (
    input  wire clk,
    input  wire rst_n,

    // RX deframer interface
    input  wire rx_preamble_match, // Strobe on 0xAA 0x55 detected
    input  wire rx_done,           // Strobe on RX completion (MAC OK or Error/Timeout)
    output reg  arb_rx_lock,       // High when crypto pipeline is locked to RX

    // TX framer interface
    input  wire tx_req,            // Strobe or level requesting TX transmission
    input  wire tx_done,           // Strobe on TX packet completion
    output reg  arb_tx_lock,       // High when crypto pipeline is locked to TX
    output reg  tx_grant,          // 1-cycle strobe granting TX to proceed
    output reg  tx_pending         // High when TX is waiting for RX lock to release
);

    localparam ARB_IDLE      = 2'd0;
    localparam ARB_RX_LOCKED = 2'd1;
    localparam ARB_TX_LOCKED = 2'd2;

    reg [1:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= ARB_IDLE;
            arb_rx_lock <= 1'b0;
            arb_tx_lock <= 1'b0;
            tx_grant    <= 1'b0;
            tx_pending  <= 1'b0;
        end else begin
            tx_grant <= 1'b0;

            case (state)
                ARB_IDLE: begin
                    if (rx_preamble_match) begin
                        arb_rx_lock <= 1'b1;
                        state       <= ARB_RX_LOCKED;
                    end else if (tx_req || tx_pending) begin
                        arb_tx_lock <= 1'b1;
                        tx_grant    <= 1'b1;
                        tx_pending  <= 1'b0;
                        state       <= ARB_TX_LOCKED;
                    end
                end

                ARB_RX_LOCKED: begin
                    if (tx_req) begin
                        tx_pending <= 1'b1;
                    end

                    if (rx_done) begin
                        arb_rx_lock <= 1'b0;
                        if (tx_pending || tx_req) begin
                            tx_pending  <= 1'b0;
                            arb_tx_lock <= 1'b1;
                            tx_grant    <= 1'b1;
                            state       <= ARB_TX_LOCKED;
                        end else begin
                            state <= ARB_IDLE;
                        end
                    end
                end

                ARB_TX_LOCKED: begin
                    if (tx_done) begin
                        arb_tx_lock <= 1'b0;
                        state       <= ARB_IDLE;
                    end
                end

                default: begin
                    state <= ARB_IDLE;
                end
            endcase
        end
    end

endmodule
