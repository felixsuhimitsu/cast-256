//=============================================================================
// File   : rtl/ip/aes256/aes256_cipher.v
// Mục đích: Khối mã hóa AES-256 — sở hữu 16 S-Box, bộ nhớ khóa vòng, và FSM
//           14 vòng. Kiến trúc lặp: một vòng đầy đủ mỗi chu kỳ.
// REQ    : REQ-F-01, REQ-F-05, REQ-F-06, REQ-P-05, REQ-R-03
// ADR    : ADR-0001, ADR-0002, ADR-0007
// Tác giả : Đội Hủ Tiếu · Ngày: 2026-09-09
//=============================================================================
// CHỈ CÓ HÀM MÃ HÓA, KHÔNG CÓ HÀM GIẢI MÃ (REQ-F-06).
// Chế độ CTR sinh dòng khóa bằng cách mã hóa bộ đếm; cả chiều mã và chiều giải
// đều là XOR với cùng dòng khóa đó. Vì vậy không tồn tại InvSubBytes hay
// InvMixColumns trong toàn bộ rtl/ — tiết kiệm khoảng một nửa diện tích so với
// một hiện thực AES đầy đủ.
//
// CHỈ CÓ 8 KHỐI S-BOX, không phải 16. Mỗi vòng chạy trong HAI chu kỳ: chu kỳ
// đầu thay thế byte 0..7, chu kỳ sau byte 8..15, rồi mới biến đổi vòng.
// Đây là biện pháp dự phòng số 3 trong ESTIMATION §4, được kích hoạt ở WP-04
// sau khi bản 16 S-Box đo được 2961 LUT4, vượt ngưỡng REQ-R-03 (2400).
// Tiết kiệm 8 x 81 = 648 LUT4, đổi lấy 14 chu kỳ mỗi khối.
//
// 4 trong 8 khối S-Box còn được DÙNG CHUNG với key schedule (ADR-0007). An toàn
// vì key schedule chạy một lần lúc nạp khóa, không bao giờ trùng với vòng mã hóa.
//
// Khóa vòng lưu trong BỐN bộ nhớ 16 x 32 bit song song, không phải một mảng
// 15 x 128. Lý do là ràng buộc của phần cứng Gowin: cổng BSRAM rộng tối đa 32
// bit, nên mảng 128 bit không ánh xạ được vào BSRAM và yosys rơi về RAM phân
// tán (RAM16SDP4). Bản đầu sinh ra 32 khối RAM16SDP4 và nextpnr KHÔNG ĐẶT CHỖ
// ĐƯỢC — dù LUT4 mới dùng 80% và DFF 60%, vì RAM phân tán chỉ nằm được ở một
// số ô nhất định.
//
// Chia thành bốn bộ nhớ 32 bit + thuộc tính ram_style="block" đưa chúng vào
// BSRAM (còn thừa 25/26 khối), giải phóng hoàn toàn các ô RAM phân tán.
//
// Vẫn tránh được bộ chọn 15:1 trên 128 bit (~900 LUT4 nếu làm bằng mux).
//
// Thời gian: 1 chu kỳ chờ bộ nhớ + 1 chu kỳ AddRoundKey ban đầu + 14 vòng x 2
// chu kỳ = 30 chu kỳ mỗi khối. Ở 27 MHz tương đương 14,4 MB/s — vẫn nhanh hơn
// UART 115200 (11,5 kB/s) hơn 1000 lần, nên không phải nút thắt.
//=============================================================================

`timescale 1ns / 1ps

module aes256_cipher (
    input  wire         clk,
    input  wire         rst_n,

    // Nạp khóa và chạy key schedule
    input  wire         key_start,
    input  wire [255:0] key,
    output wire         key_done,

    // Mã hóa một khối
    input  wire         enc_start,
    input  wire [127:0] block_in,
    output reg  [127:0] block_out,
    output reg          enc_done,
    output wire         busy
);

    localparam [1:0] ST_IDLE  = 2'd0,
                     ST_KEXP  = 2'd1,
                     // Một chu kỳ chờ bộ nhớ khóa vòng trả về rk[0]. Đọc bộ
                     // nhớ có thanh ghi nên trễ một chu kỳ; thiếu trạng thái
                     // này thì AddRoundKey đầu tiên dùng dữ liệu rác.
                     ST_ELOAD = 2'd2,
                     ST_ENC   = 2'd3;

    reg  [1:0]   state;
    reg  [3:0]   round;          // 0..14
    reg          half;           // 0 = đang xử lý byte 0..7, 1 = byte 8..15
    reg  [63:0]  sb_hi;          // kết quả S-Box của byte 0..7, giữ sang chu kỳ sau
    reg  [127:0] st;             // state AES hiện tại

    //------------------------------------------------------------------
    // Bộ nhớ khóa vòng — 15 x 128 bit, truy cập tuần tự
    //------------------------------------------------------------------
    (* ram_style = "block" *) reg [31:0] rk_mem0 [0:15];
    (* ram_style = "block" *) reg [31:0] rk_mem1 [0:15];
    (* ram_style = "block" *) reg [31:0] rk_mem2 [0:15];
    (* ram_style = "block" *) reg [31:0] rk_mem3 [0:15];
    reg  [127:0] rk_rd;
    // Đọc bộ nhớ có thanh ghi: rk_rd ở chu kỳ N = rk_mem[rk_addr_rd ở chu kỳ N-1].
    // Với hai chu kỳ mỗi vòng, địa chỉ được nâng ở nửa sau của vòng nên nửa đầu
    // của vòng kế tiếp đã có sẵn khóa đúng.
    // (Bản 16 S-Box trước đây chỉ nâng địa chỉ trước MỘT nhịp và vòng 1 dùng
    //  nhầm rk[0] — khóa vòng hoàn toàn đúng mà kết quả vẫn sai.)
    reg  [3:0]   rk_addr_rd;

    wire         ks_we;
    wire [3:0]   ks_addr;
    wire [127:0] ks_data;

    always @(posedge clk) begin
        if (ks_we) begin
            rk_mem0[ks_addr] <= ks_data[127:96];
            rk_mem1[ks_addr] <= ks_data[95:64];
            rk_mem2[ks_addr] <= ks_data[63:32];
            rk_mem3[ks_addr] <= ks_data[31:0];
        end
        rk_rd <= {rk_mem0[rk_addr_rd], rk_mem1[rk_addr_rd],
                  rk_mem2[rk_addr_rd], rk_mem3[rk_addr_rd]};
    end

    //------------------------------------------------------------------
    // 8 khối S-Box, dùng hai lần mỗi vòng. Bốn khối đầu chia sẻ với key
    // schedule.
    //------------------------------------------------------------------
    wire        kexp_active = (state == ST_KEXP);
    wire [31:0] sw_in, sw_out;

    // Nửa state đang được thay thế trong chu kỳ này
    wire [63:0] st_half = half ? st[63:0] : st[127:64];

    wire [63:0] sb_half;
    genvar g;
    generate
        for (g = 0; g < 8; g = g + 1) begin : gen_sbox
            wire [7:0] din_state = st_half[63 - 8*g -: 8];
            wire [7:0] din;
            wire [7:0] dout;

            // Phải dùng generate-if chứ không phải toán tử ?: — biểu thức
            // sw_in[31-8*g -: 8] vẫn được elaborate cho mọi g, và với g >= 4
            // nó chỉ số âm, iverilog cảnh báo "selecting before vector".
            if (g < 4) begin : gen_shared
                assign din = kexp_active ? sw_in[31 - 8*g -: 8] : din_state;
            end else begin : gen_plain
                assign din = din_state;
            end

            aes256_sbox u_sbox (.a(din), .s(dout));
            assign sb_half[63 - 8*g -: 8] = dout;
        end
    endgenerate

    assign sw_out = sb_half[63:32];    // 4 byte đầu = SubWord của key schedule

    // State đầy đủ sau SubBytes: nửa trên đã chốt từ chu kỳ trước
    wire [127:0] sb_out = {sb_hi, sb_half};

    //------------------------------------------------------------------
    aes256_keysched u_ks (
        .clk     (clk),
        .rst_n   (rst_n),
        .start   (key_start && (state == ST_IDLE)),
        .key     (key),
        .done    (key_done),
        .sw_in   (sw_in),
        .sw_out  (sw_out),
        .rk_we   (ks_we),
        .rk_addr (ks_addr),
        .rk_data (ks_data)
    );

    //------------------------------------------------------------------
    wire         is_last = (round == 4'd14);
    wire [127:0] round_out;

    aes256_round u_round (
        .sb   (sb_out),
        .rk   (rk_rd),
        .last (is_last),
        .out  (round_out)
    );

    assign busy = (state != ST_IDLE);

    //------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= ST_IDLE;
            round      <= 4'd0;
            half       <= 1'b0;
            sb_hi      <= 64'd0;
            rk_addr_rd <= 4'd0;
            st         <= 128'd0;
            block_out  <= 128'd0;
            enc_done   <= 1'b0;
        end else begin
            enc_done <= 1'b0;

            case (state)

                ST_IDLE: begin
                    if (key_start) begin
                        state <= ST_KEXP;
                        round <= 4'd0;
                    end else if (enc_start) begin
                        st         <= block_in;
                        round      <= 4'd0;
                        half       <= 1'b0;
                        rk_addr_rd <= 4'd0;
                        state      <= ST_ELOAD;
                    end
                end

                ST_KEXP: begin
                    if (key_done)
                        state <= ST_IDLE;
                end

                ST_ELOAD: begin
                    // rk_addr_rd đang là 0 -> cuối chu kỳ này rk_rd nhận rk[0]
                    rk_addr_rd <= 4'd0;
                    state      <= ST_ENC;
                end

                ST_ENC: begin
                    if (round == 4'd0) begin
                        // AddRoundKey ban đầu: KHÔNG qua SubBytes, một chu kỳ
                        st         <= st ^ rk_rd;
                        round      <= 4'd1;
                        half       <= 1'b0;
                        rk_addr_rd <= 4'd1;
                    end else if (half == 1'b0) begin
                        // Nửa đầu: chốt S-Box của byte 0..7, chưa đổi state
                        sb_hi <= sb_half;
                        half  <= 1'b1;
                    end else begin
                        // Nửa sau: có đủ 16 byte sau SubBytes -> biến đổi vòng
                        st   <= round_out;
                        half <= 1'b0;
                        if (is_last) begin
                            block_out  <= round_out;
                            enc_done   <= 1'b1;
                            state      <= ST_IDLE;
                            round      <= 4'd0;
                            rk_addr_rd <= 4'd0;
                        end else begin
                            round      <= round + 4'd1;
                            rk_addr_rd <= round + 4'd1;
                        end
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
