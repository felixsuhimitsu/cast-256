//=============================================================================
// File   : rtl/protocol/session_fsm.v
// Mục đích: Điều phối một phiên xử lý khung: SHA -> so digest -> AES -> SHA ->
//           phát. Là bên duy nhất nói chuyện với tầng fabric.
// REQ    : REQ-F-22, REQ-F-24, REQ-F-25
// ADR    : ADR-0006
// Tác giả : Đội Hủ Tiếu · Ngày: 2026-09-09
//=============================================================================
// Luồng một khung (ARCHITECTURE §3):
//   1. Băm  LEN‖IV‖payload            -> digest_calc          [cấp SHA]
//   2. So digest_calc với digest_rx    -> không khớp thì IM LẶNG
//   3. Mã hóa payload tại chỗ          -> bản mã               [cấp AES]
//   4. Băm  LEN‖IV‖ciphertext          -> digest_tx            [cấp SHA]
//   5. Giao cho frame_tx phát đi
//
// FAIL CLOSED: digest không khớp thì KHÔNG phát gì cả. Im lặng là câu trả lời
// an toàn, và nó cũng làm cho test tamper phía host kiểm được đúng thứ cần kiểm.
//
// MODULE NÀY KHÔNG INSTANTIATE IP NÀO. Nó chỉ yêu cầu quyền từ ip_arbiter rồi
// nói chuyện qua stream_mux. Đó là ràng buộc phụ thuộc tầng số 2 trong
// MODULE_MAP §4, và `make lint` cưỡng chế nó.
//
// BẮT TAY PHẢI KIỂM CẢ HAI VẾ: `m_sin_valid && m_sin_ready`, không phải chỉ
// `m_sin_ready`. Vì `m_sin_valid` là thanh ghi nên ở chu kỳ đầu của mỗi trạng
// thái nạp nó vẫn bằng 0; nếu chỉ kiểm `ready` thì bộ đếm byte nhảy lên trong
// khi byte chưa hề được gửi. Lỗi này làm bước nạp khóa AES không bao giờ kết
// thúc, engine kẹt ở trạng thái bận vĩnh viễn, và vì byte đến bị chặn bởi
// `!engine_busy` nên toàn hệ thống câm lặng — nhìn từ ngoài giống hệt "khung
// nào cũng bị loại".
//
// ĐỌC BỘ ĐỆM MẤT MỘT CHU KỲ. Vì vậy mỗi byte lấy từ bộ đệm đi qua hai trạng
// thái: đặt địa chỉ, rồi mới dùng dữ liệu. Chậm gấp đôi nhưng đúng — và ở tốc
// độ UART thì hoàn toàn không phải nút thắt (512 byte x 2 chu kỳ = 38 µs, so
// với 46 ms để truyền chính 512 byte đó).
//=============================================================================

`timescale 1ns / 1ps

module session_fsm #(
    parameter AW      = 9,
    parameter NUM_IP  = 2,
    parameter IP_AES  = 0,          // chỉ số IP AES trong fabric
    parameter IP_SHA  = 1
) (
    input  wire              clk,
    input  wire              rst_n,

    input  wire [255:0]      aes_key,

    // từ frame_rx
    input  wire              frame_ready,
    input  wire [15:0]       len,
    input  wire [127:0]      iv,
    input  wire [255:0]      digest_rx,

    // bộ đệm khung
    output wire [AW-1:0]     buf_raddr,
    input  wire [7:0]        buf_rdata,
    output reg               buf_we,
    output reg  [AW-1:0]     buf_waddr,
    output reg  [7:0]        buf_wdata,

    // tới ip_arbiter / stream_mux
    output reg  [NUM_IP-1:0] req,
    input  wire [NUM_IP-1:0] grant,
    output reg               m_start,
    output reg  [7:0]        m_mode,
    input  wire              m_busy,
    input  wire              m_done,
    input  wire              m_err,
    output reg  [7:0]        m_sin_data,
    output reg               m_sin_valid,
    output reg               m_sin_last,
    input  wire              m_sin_ready,
    input  wire [7:0]        m_sout_data,
    input  wire              m_sout_valid,
    input  wire              m_sout_last,
    output reg               m_sout_ready,
    input  wire [255:0]      m_result,
    input  wire              m_result_valid,

    // tới frame_tx
    output reg               tx_start,
    output reg  [255:0]      digest_tx,
    input  wire              tx_done,

    // chỉ thị
    output reg               drop_pulse,     // xung: khung bị loại
    output wire              engine_busy
);

    // csi_mode của hai IP
    localparam [7:0] AES_LOAD_KEY = 8'h00,
                     AES_LOAD_IV  = 8'h01,
                     AES_CRYPT    = 8'h02,
                     SHA_HASH     = 8'h00;

    localparam [4:0] ST_KEY_REQ  = 5'd0,
                     ST_KEY_STRT = 5'd1,
                     ST_KEY_FEED = 5'd2,
                     ST_KEY_WAIT = 5'd3,
                     ST_IDLE     = 5'd4,
                     ST_S1_REQ   = 5'd5,
                     ST_S1_STRT  = 5'd6,
                     ST_S1_ADDR  = 5'd7,
                     ST_S1_DATA  = 5'd8,
                     ST_S1_WAIT  = 5'd9,
                     ST_CHECK    = 5'd10,
                     ST_IV_REQ   = 5'd11,
                     ST_IV_STRT  = 5'd12,
                     ST_IV_FEED  = 5'd13,
                     ST_IV_WAIT  = 5'd14,
                     ST_AE_STRT  = 5'd15,
                     ST_AE_ADDR  = 5'd16,
                     ST_AE_DATA  = 5'd17,
                     ST_AE_WAIT  = 5'd18,
                     ST_S2_REQ   = 5'd19,
                     ST_S2_STRT  = 5'd20,
                     ST_S2_ADDR  = 5'd21,
                     ST_S2_DATA  = 5'd22,
                     ST_S2_WAIT  = 5'd23,
                     ST_TX       = 5'd24,
                     ST_DROP     = 5'd25;

    reg  [4:0]  state;
    reg  [AW+1:0] fidx;          // chỉ số byte đang nạp cho SHA (0 .. 17+LEN-1)
    reg  [AW:0] aes_in;
    reg  [AW:0] aes_out;
    reg  [5:0]  kidx;
    reg  [255:0] digest_calc;

    wire [AW+1:0] feed_total = {6'd0, len[AW-1:0]} + 18;

    wire [255:0] key_r = aes_key;

    //------------------------------------------------------------------
    // ĐỊA CHỈ ĐỌC LÀ TỔ HỢP, KHÔNG QUA THANH GHI.
    //
    // Đọc bộ nhớ mất một chu kỳ: buf_rdata ở chu kỳ N = mem[buf_raddr ở chu kỳ
    // N-1]. Nếu buf_raddr cũng là thanh ghi thì cần TỔNG CỘNG hai chu kỳ chờ,
    // và trạng thái *_ADDR một chu kỳ là không đủ — dữ liệu dùng ở *_DATA sẽ là
    // của byte TRƯỚC ĐÓ.
    //
    // Đây là lần thứ ba cùng một kiểu lỗi trong dự án (hai lần trước ở bộ nhớ
    // khóa vòng của AES, WP-04). Cách chữa gốc: để địa chỉ là tổ hợp, khi đó
    // một trạng thái chờ là đủ và đúng.
    //------------------------------------------------------------------
    reg [AW-1:0] raddr_c;
    always @(*) begin
        if ((state == ST_AE_ADDR) || (state == ST_AE_DATA))
            raddr_c = aes_in[AW-1:0];
        else if (fidx >= 18)
            raddr_c = fidx[AW-1:0] - 18;
        else
            raddr_c = {AW{1'b0}};
    end
    assign buf_raddr = raddr_c;

    //------------------------------------------------------------------
    // Byte thứ `fidx` của chuỗi LEN‖IV‖dữ_liệu
    //------------------------------------------------------------------
    reg [7:0] feed_byte;
    always @(*) begin
        if (fidx == 0)
            feed_byte = len[15:8];
        else if (fidx == 1)
            feed_byte = len[7:0];
        else if (fidx < 18)
            feed_byte = iv[127 - 8*(fidx - 2) -: 8];
        else
            feed_byte = buf_rdata;
    end

    wire match;
    digest_check u_chk (.a(digest_calc), .b(digest_rx), .match(match));

    assign engine_busy = (state != ST_IDLE);

    //------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_KEY_REQ;
            req          <= {NUM_IP{1'b0}};
            m_start      <= 1'b0;
            m_mode       <= 8'd0;
            m_sin_data   <= 8'd0;
            m_sin_valid  <= 1'b0;
            m_sin_last   <= 1'b0;
            m_sout_ready <= 1'b0;
            buf_we       <= 1'b0;
            buf_waddr    <= {AW{1'b0}};
            buf_wdata    <= 8'd0;
            fidx         <= 0;
            aes_in       <= 0;
            aes_out      <= 0;
            kidx         <= 6'd0;
            digest_calc  <= 256'd0;
            digest_tx    <= 256'd0;
            tx_start     <= 1'b0;
            drop_pulse   <= 1'b0;
        end else begin
            m_start    <= 1'b0;
            tx_start   <= 1'b0;
            drop_pulse <= 1'b0;
            buf_we     <= 1'b0;

            case (state)

            //===============================================================
            // Nạp khóa AES một lần lúc khởi động
            //===============================================================
            ST_KEY_REQ: begin
                req <= (1 << IP_AES);
                if (grant[IP_AES]) begin
                    m_mode  <= AES_LOAD_KEY;
                    m_start <= 1'b1;
                    kidx    <= 6'd0;
                    state   <= ST_KEY_STRT;
                end
            end

            ST_KEY_STRT: state <= ST_KEY_FEED;

            ST_KEY_FEED: begin
                if (m_sin_valid && m_sin_ready) begin
                    m_sin_valid <= 1'b0;
                    m_sin_last  <= 1'b0;
                    if (kidx == 6'd31)
                        state <= ST_KEY_WAIT;
                    else
                        kidx <= kidx + 6'd1;
                end else if (!m_sin_valid) begin
                    m_sin_data  <= key_r[255 - 8*kidx -: 8];
                    m_sin_valid <= 1'b1;
                    m_sin_last  <= (kidx == 6'd31);
                end
            end

            ST_KEY_WAIT: begin
                if (m_done) begin
                    req   <= {NUM_IP{1'b0}};
                    state <= ST_IDLE;
                end
            end

            //===============================================================
            ST_IDLE: begin
                req <= {NUM_IP{1'b0}};
                if (frame_ready) begin
                    fidx  <= 0;
                    state <= ST_S1_REQ;
                end
            end

            //===============================================================
            // Vòng 1: băm LEN‖IV‖payload
            //===============================================================
            ST_S1_REQ: begin
                req <= (1 << IP_SHA);
                if (grant[IP_SHA]) begin
                    m_mode  <= SHA_HASH;
                    m_start <= 1'b1;
                    fidx    <= 0;
                    state   <= ST_S1_STRT;
                end
            end

            ST_S1_STRT: state <= ST_S1_ADDR;

            // Một chu kỳ chờ bộ nhớ trả dữ liệu về (địa chỉ đã là tổ hợp)
            ST_S1_ADDR: state <= ST_S1_DATA;

            ST_S1_DATA: begin
                if (m_sin_valid && m_sin_ready) begin
                    m_sin_valid <= 1'b0;
                    m_sin_last  <= 1'b0;
                    if (fidx == feed_total - 1)
                        state <= ST_S1_WAIT;
                    else begin
                        fidx  <= fidx + 1;
                        state <= ST_S1_ADDR;
                    end
                end else if (!m_sin_valid) begin
                    m_sin_data  <= feed_byte;
                    m_sin_valid <= 1'b1;
                    m_sin_last  <= (fidx == feed_total - 1);
                end
            end

            ST_S1_WAIT: begin
                if (m_done) begin
                    digest_calc <= m_result;
                    req         <= {NUM_IP{1'b0}};
                    state       <= ST_CHECK;
                end
            end

            //===============================================================
            // So digest — FAIL CLOSED
            //===============================================================
            ST_CHECK: begin
                if (match)
                    state <= ST_IV_REQ;
                else
                    state <= ST_DROP;
            end

            //===============================================================
            // Nạp IV cho bộ đếm CTR
            //===============================================================
            ST_IV_REQ: begin
                req <= (1 << IP_AES);
                if (grant[IP_AES]) begin
                    m_mode  <= AES_LOAD_IV;
                    m_start <= 1'b1;
                    kidx    <= 6'd0;
                    state   <= ST_IV_STRT;
                end
            end

            ST_IV_STRT: state <= ST_IV_FEED;

            ST_IV_FEED: begin
                if (m_sin_valid && m_sin_ready) begin
                    m_sin_valid <= 1'b0;
                    m_sin_last  <= 1'b0;
                    if (kidx == 6'd15)
                        state <= ST_IV_WAIT;
                    else
                        kidx <= kidx + 6'd1;
                end else if (!m_sin_valid) begin
                    m_sin_data  <= iv[127 - 8*kidx[3:0] -: 8];
                    m_sin_valid <= 1'b1;
                    m_sin_last  <= (kidx == 6'd15);
                end
            end

            ST_IV_WAIT: begin
                if (m_done) begin
                    // GIỮ nguyên quyền cấp AES: bước mã hóa đi ngay sau đây.
                    aes_in  <= 0;
                    aes_out <= 0;
                    m_mode  <= AES_CRYPT;
                    m_start <= 1'b1;
                    state   <= ST_AE_STRT;
                end
            end

            //===============================================================
            // Mã hóa tại chỗ: đọc bản rõ, ghi đè bản mã vào cùng bộ đệm
            //===============================================================
            ST_AE_STRT: begin
                m_sout_ready <= 1'b1;
                state        <= ST_AE_ADDR;
            end

            ST_AE_ADDR: state <= ST_AE_DATA;

            ST_AE_DATA: begin
                if (m_sin_valid && m_sin_ready) begin
                    m_sin_valid <= 1'b0;
                    m_sin_last  <= 1'b0;
                    if (aes_in == len - 1)
                        state <= ST_AE_WAIT;
                    else begin
                        aes_in <= aes_in + 1;
                        state  <= ST_AE_ADDR;
                    end
                end else if (!m_sin_valid) begin
                    m_sin_data  <= buf_rdata;
                    m_sin_valid <= 1'b1;
                    m_sin_last  <= (aes_in == len - 1);
                end
            end

            ST_AE_WAIT: begin
                if (m_done) begin
                    m_sout_ready <= 1'b0;
                    req          <= {NUM_IP{1'b0}};
                    fidx         <= 0;
                    state        <= ST_S2_REQ;
                end
            end

            //===============================================================
            // Vòng 2: băm LEN‖IV‖ciphertext để host tự kiểm được khung về
            //===============================================================
            ST_S2_REQ: begin
                req <= (1 << IP_SHA);
                if (grant[IP_SHA]) begin
                    m_mode  <= SHA_HASH;
                    m_start <= 1'b1;
                    fidx    <= 0;
                    state   <= ST_S2_STRT;
                end
            end

            ST_S2_STRT: state <= ST_S2_ADDR;

            ST_S2_ADDR: state <= ST_S2_DATA;

            ST_S2_DATA: begin
                if (m_sin_valid && m_sin_ready) begin
                    m_sin_valid <= 1'b0;
                    m_sin_last  <= 1'b0;
                    if (fidx == feed_total - 1)
                        state <= ST_S2_WAIT;
                    else begin
                        fidx  <= fidx + 1;
                        state <= ST_S2_ADDR;
                    end
                end else if (!m_sin_valid) begin
                    m_sin_data  <= feed_byte;
                    m_sin_valid <= 1'b1;
                    m_sin_last  <= (fidx == feed_total - 1);
                end
            end

            ST_S2_WAIT: begin
                if (m_done) begin
                    digest_tx <= m_result;
                    req       <= {NUM_IP{1'b0}};
                    tx_start  <= 1'b1;
                    state     <= ST_TX;
                end
            end

            //===============================================================
            ST_TX: begin
                if (tx_done)
                    state <= ST_IDLE;
            end

            ST_DROP: begin
                drop_pulse <= 1'b1;
                state      <= ST_IDLE;
            end

            default: state <= ST_IDLE;
            endcase

            //----------------------------------------------------------
            // Thu bản mã từ AES, ghi đè vào bộ đệm. Chạy song song với
            // FSM ở trên. An toàn vì aes_out luôn <= aes_in: byte ra chỉ
            // xuất hiện sau khi byte vào đã được đọc.
            //----------------------------------------------------------
            if (m_sout_valid && m_sout_ready) begin
                buf_we    <= 1'b1;
                buf_waddr <= aes_out[AW-1:0];
                buf_wdata <= m_sout_data;
                aes_out   <= aes_out + 1;
            end
        end
    end

endmodule
