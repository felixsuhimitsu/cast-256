//=============================================================================
// File   : rtl/ip/aes256/aes256_keysched.v
// Mục đích: Sinh 15 khóa vòng (60 word) từ khóa 256 bit, theo FIPS 197 §5.2.
// REQ    : REQ-F-05, REQ-R-03
// ADR    : ADR-0007 (dùng chung S-Box với đường dữ liệu)
// Tác giả : Đội Hủ Tiếu · Ngày: 2026-09-09
//=============================================================================
// AES-256: Nk = 8, Nr = 14, cần W[0..59].
//   W[i] = W[i-8] ^ temp
//   temp = SubWord(RotWord(W[i-1])) ^ Rcon[i/8]   nếu i mod 8 == 0
//        = SubWord(W[i-1])                        nếu i mod 8 == 4
//        = W[i-1]                                 các trường hợp còn lại
//
// MODULE NÀY KHÔNG SỞ HỮU S-BOX. Nó "mượn" 4 trong 16 khối S-Box của
// aes256_cipher qua cặp cổng sw_in / sw_out. Đây là hiện thực trực tiếp của
// quyết định trong ADR-0007: dùng 16 S-Box thay vì 20, tiết kiệm 4 x 81 = 324
// LUT4. Việc mượn là an toàn vì key schedule và vòng mã hóa không bao giờ chạy
// cùng lúc — key schedule chạy một lần lúc nạp khóa.
//
// Kết quả ghi ra ngoài theo từng khóa vòng 128 bit (rk_we, rk_addr, rk_data)
// để aes256_cipher lưu vào bộ nhớ, tránh phải dựng bộ chọn 15:1 trên 128 bit.
//=============================================================================

`timescale 1ns / 1ps

module aes256_keysched (
    input  wire         clk,
    input  wire         rst_n,

    input  wire         start,
    input  wire [255:0] key,          // khóa 256 bit, big-endian
    output reg          done,

    // Mượn 4 khối S-Box của aes256_cipher
    output wire [31:0]  sw_in,
    input  wire [31:0]  sw_out,

    // Ghi khóa vòng ra ngoài — TỔ HỢP, không qua thanh ghi.
    // Bản đầu để ba tín hiệu này là `reg`. Bên nhận (aes256_cipher) ghi vào bộ
    // nhớ ở sườn xung nên tín hiệu tổ hợp là đủ.
    //
    // ĐO ĐƯỢC: DFF 1490 -> 1357 (giảm 133), nhưng LUT4 2526 -> 2528, tức là
    // KHÔNG giảm LUT. Tôi đã dự đoán tiết kiệm ~130 LUT4 và dự đoán đó SAI:
    // các thanh ghi này ánh xạ thẳng vào ô DFF, không tiêu LUT nào để bỏ đi.
    // Giữ thay đổi vì DFF rẻ hơn thì vẫn tốt, nhưng ghi lại ở đây đúng như số
    // đo — xem DEVELOPMENT_BOOK §4.2.
    output wire         rk_we,
    output wire [3:0]   rk_addr,
    output wire [127:0] rk_data
);

    localparam [1:0] ST_IDLE = 2'd0,
                     ST_SEED = 2'd1,   // ghi W[0..7] = round key 0 và 1
                     ST_EXP  = 2'd2;   // sinh W[8..59]

    reg [1:0]   state;
    reg [5:0]   i;              // chỉ số word đang sinh, 8..59
    reg [255:0] w;              // cửa sổ 8 word gần nhất: {W[i-8] ... W[i-1]}
    reg [127:0] rkbuf;          // gom 4 word thành một khóa vòng
    reg [1:0]   seed_step;

    wire [31:0] w_prev = w[31:0];      // W[i-1]
    wire [31:0] w_m8   = w[255:224];   // W[i-8]

    // RotWord: xoay trái 1 byte
    wire [31:0] rotw = {w_prev[23:0], w_prev[31:24]};

    // Chọn đầu vào cho 4 S-Box mượn được
    wire is_mod8 = (i[2:0] == 3'd0);
    wire is_mod4 = (i[2:0] == 3'd4);
    assign sw_in = is_mod8 ? rotw : w_prev;

    // Rcon[i/8] — chỉ dùng khi i mod 8 == 0, i/8 chạy 1..7
    reg [31:0] rcon;
    always @(*) begin
        case (i[5:3])
            3'd1:    rcon = 32'h01000000;
            3'd2:    rcon = 32'h02000000;
            3'd3:    rcon = 32'h04000000;
            3'd4:    rcon = 32'h08000000;
            3'd5:    rcon = 32'h10000000;
            3'd6:    rcon = 32'h20000000;
            3'd7:    rcon = 32'h40000000;
            default: rcon = 32'h00000000;
        endcase
    end

    wire [31:0] temp = is_mod8 ? (sw_out ^ rcon) :
                       is_mod4 ?  sw_out         :
                                  w_prev;

    wire [31:0] w_new = w_m8 ^ temp;

    //------------------------------------------------------------------
    // Cổng ghi khóa vòng — tổ hợp
    //------------------------------------------------------------------
    wire [127:0] rk_exp = {rkbuf[95:0], w_new};

    assign rk_we   = (state == ST_SEED) ||
                     ((state == ST_EXP) && (i[1:0] == 2'd3));
    assign rk_addr = (state == ST_SEED) ? {3'd0, seed_step[0]} : i[5:2];
    assign rk_data = (state == ST_SEED)
                     ? (seed_step[0] ? w[127:0] : w[255:128])
                     : rk_exp;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= ST_IDLE;
            i         <= 6'd8;
            w         <= 256'd0;
            rkbuf     <= 128'd0;
            seed_step <= 2'd0;
            done      <= 1'b0;
        end else begin
            done <= 1'b0;

            case (state)

                ST_IDLE: begin
                    if (start) begin
                        w         <= key;
                        i         <= 6'd8;
                        seed_step <= 2'd0;
                        state     <= ST_SEED;
                    end
                end

                //--------------------------------------------------------
                // W[0..7] chính là khóa: khóa vòng 0 = W[0..3],
                // khóa vòng 1 = W[4..7]. Ghi thẳng, không cần tính.
                //--------------------------------------------------------
                // Khóa vòng 0 và 1 chính là khóa gốc W[0..7]. Lấy từ `w` (bản
                // đã chốt lúc start), KHÔNG lấy từ cổng `key`: aes256_ctr_ip
                // ghép byte khóa cuối cùng thẳng từ dòng vào cổng đó, nên sang
                // chu kỳ sau nó đã đổi giá trị và hai khóa vòng đầu bị lệch một
                // byte. Khóa vòng 2..14 vẫn đúng vì sinh từ `w`, nên lỗi rất
                // khó nhìn ra: 13/15 khóa vòng đúng mà bản mã vẫn sai hoàn toàn.
                ST_SEED: begin
                    if (seed_step == 2'd0)
                        seed_step <= 2'd1;
                    else
                        state <= ST_EXP;
                end

                //--------------------------------------------------------
                // Sinh W[8..59], mỗi chu kỳ một word
                //--------------------------------------------------------
                ST_EXP: begin
                    w     <= {w[223:0], w_new};       // trượt cửa sổ
                    rkbuf <= {rkbuf[95:0], w_new};    // gom 4 word
                    // rk_we/rk_addr/rk_data là tổ hợp, xem phần trên

                    if (i == 6'd59) begin
                        state <= ST_IDLE;
                        done  <= 1'b1;
                    end else begin
                        i <= i + 6'd1;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
