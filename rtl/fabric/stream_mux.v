//=============================================================================
// File   : rtl/fabric/stream_mux.v
// Mục đích: Định tuyến toàn bộ tín hiệu CSI giữa bên điều phối và IP đang được
//           cấp quyền. Thuần tổ hợp.
// REQ    : REQ-I-01, REQ-I-02
// ADR    : ADR-0006
// Tác giả : Đội Hủ Tiếu · Ngày: 2026-09-09
//=============================================================================
// ĐÂY LÀ CHỖ ĐỀ TÀI "TÍCH HỢP IP" THỂ HIỆN RÕ NHẤT.
// Module này KHÔNG biết IP nào là AES, IP nào là SHA. Nó chỉ biết hợp đồng CSI.
// Vì vậy đổi chỗ hai IP trong sơ đồ khối không cần sửa một dòng nào ở đây —
// TC-402 kiểm chính điều đó.
//
// Thêm IP thứ ba: chỉ cần tăng tham số NUM_IP. Không đụng `protocol/`, không
// đụng `io/`.
//
// Cổng phía IP được làm phẳng (flatten) thành bus vì Verilog-2001 không cho
// khai báo mảng cổng (REQ-C-04). Quy ước: IP thứ i chiếm bit [i], hoặc lát
// [DW*i +: DW] với tín hiệu nhiều bit.
//
// Tín hiệu đi TỚI IP được CHẶN bằng bit grant: IP không được cấp quyền nhìn
// thấy valid = 0 và start = 0. Không chỉ dựa vào việc bên điều phối "cư xử
// đúng" — chặn ở đây là tuyến phòng thủ thứ hai cho REQ-F-25.
//=============================================================================

`timescale 1ns / 1ps

module stream_mux #(
    parameter NUM_IP = 2,
    parameter DW     = 8,
    parameter RW     = 256
) (
    input  wire [NUM_IP-1:0]      grant,          // one-hot từ ip_arbiter

    //---- phía bên điều phối (session_fsm) ----------------------------
    input  wire                   m_start,
    input  wire [7:0]             m_mode,
    output wire                   m_busy,
    output wire                   m_done,
    output wire                   m_err,

    input  wire [DW-1:0]          m_sin_data,
    input  wire                   m_sin_valid,
    input  wire                   m_sin_last,
    output wire                   m_sin_ready,

    output wire [DW-1:0]          m_sout_data,
    output wire                   m_sout_valid,
    output wire                   m_sout_last,
    input  wire                   m_sout_ready,

    output wire [RW-1:0]          m_result,
    output wire                   m_result_valid,

    //---- phía các IP (làm phẳng) -------------------------------------
    output wire [NUM_IP-1:0]      ip_start,
    output wire [8*NUM_IP-1:0]    ip_mode,
    input  wire [NUM_IP-1:0]      ip_busy,
    input  wire [NUM_IP-1:0]      ip_done,
    input  wire [NUM_IP-1:0]      ip_err,

    output wire [DW*NUM_IP-1:0]   ip_sin_data,
    output wire [NUM_IP-1:0]      ip_sin_valid,
    output wire [NUM_IP-1:0]      ip_sin_last,
    input  wire [NUM_IP-1:0]      ip_sin_ready,

    input  wire [DW*NUM_IP-1:0]   ip_sout_data,
    input  wire [NUM_IP-1:0]      ip_sout_valid,
    input  wire [NUM_IP-1:0]      ip_sout_last,
    output wire [NUM_IP-1:0]      ip_sout_ready,

    input  wire [RW*NUM_IP-1:0]   ip_result,
    input  wire [NUM_IP-1:0]      ip_result_valid
);

    genvar i;

    //------------------------------------------------------------------
    // Điều phối -> IP: chặn bằng grant
    //------------------------------------------------------------------
    generate
        for (i = 0; i < NUM_IP; i = i + 1) begin : gen_fanout
            assign ip_start[i]                = m_start     & grant[i];
            assign ip_mode[8*i +: 8]          = m_mode;      // mức, không cần chặn
            assign ip_sin_data[DW*i +: DW]    = m_sin_data;
            assign ip_sin_valid[i]            = m_sin_valid  & grant[i];
            assign ip_sin_last[i]             = m_sin_last   & grant[i];
            assign ip_sout_ready[i]           = m_sout_ready & grant[i];
        end
    endgenerate

    //------------------------------------------------------------------
    // IP -> điều phối: gộp OR với mặt nạ grant.
    // Vì grant là one-hot, phép OR này tương đương một bộ chọn nhưng rẻ hơn
    // và không cần biết chỉ số.
    //------------------------------------------------------------------
    function [DW-1:0] sel_dw;
        input [DW*NUM_IP-1:0] bus;
        input [NUM_IP-1:0]    g;
        integer j;
        begin
            sel_dw = {DW{1'b0}};
            for (j = 0; j < NUM_IP; j = j + 1)
                if (g[j])
                    sel_dw = bus[DW*j +: DW];
        end
    endfunction

    function [RW-1:0] sel_rw;
        input [RW*NUM_IP-1:0] bus;
        input [NUM_IP-1:0]    g;
        integer j;
        begin
            sel_rw = {RW{1'b0}};
            for (j = 0; j < NUM_IP; j = j + 1)
                if (g[j])
                    sel_rw = bus[RW*j +: RW];
        end
    endfunction

    assign m_busy         = |(ip_busy         & grant);
    assign m_done         = |(ip_done         & grant);
    assign m_err          = |(ip_err          & grant);
    assign m_sin_ready    = |(ip_sin_ready    & grant);
    assign m_sout_valid   = |(ip_sout_valid   & grant);
    assign m_sout_last    = |(ip_sout_last    & grant);
    assign m_result_valid = |(ip_result_valid & grant);

    assign m_sout_data    = sel_dw(ip_sout_data, grant);
    assign m_result       = sel_rw(ip_result,    grant);

endmodule
