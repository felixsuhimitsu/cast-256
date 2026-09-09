//=============================================================================
// File   : rtl/fabric/ip_arbiter.v
// Mục đích: Trọng tài cấp phát IP mật mã. Cưỡng chế loại trừ tương hỗ: không
//           bao giờ có hai IP cùng chiếm đường dữ liệu.
// REQ    : REQ-F-25
// ADR    : ADR-0006
// Tác giả : Đội Hủ Tiếu · Ngày: 2026-09-09
//=============================================================================
// Module này CHỈ quyết định "ai được cấp". Việc nối dây do stream_mux làm.
// Tách hai việc là có chủ đích (ARCHITECTURE §4.3): khi thêm IP thứ ba, chính
// sách cấp phát ở đây thay đổi còn cơ chế nối dây chỉ tăng số cổng. Trộn hai
// việc vào một module là nguyên nhân phổ biến của lỗi khó tìm.
//
// Chính sách: ưu tiên cố định theo chỉ số, IP 0 cao nhất. Không có nguy cơ đói
// tài nguyên (starvation) vì bên điều phối (session_fsm) chạy tuần tự — nó chỉ
// yêu cầu một IP tại một thời điểm.
//
// Quyền cấp được GIỮ cho tới khi bên yêu cầu hạ `req` VÀ IP đó đã hết bận.
// Không nhả sớm: nhả khi IP còn bận sẽ cho phép IP khác được cấp trong lúc IP
// cũ vẫn đang đẩy dữ liệu — đúng cái mà REQ-F-25 cấm.
//
// `viol_concurrent` là chốt cảnh báo PHẦN CỨNG, không phải chỉ để mô phỏng: nếu
// vì lý do nào đó hai IP cùng báo bận, cờ này bật và giữ. Nó được nối ra LED
// báo lỗi ở tầng trên, nên vi phạm REQ-F-25 nhìn thấy được trên board thật chứ
// không chỉ thấy trong testbench.
//=============================================================================

`timescale 1ns / 1ps

module ip_arbiter #(
    parameter NUM_IP = 2
) (
    input  wire                clk,
    input  wire                rst_n,

    input  wire [NUM_IP-1:0]   req,        // mức: bên điều phối muốn dùng IP nào
    input  wire [NUM_IP-1:0]   ip_busy,    // cờ bận của từng IP

    output reg  [NUM_IP-1:0]   grant,      // one-hot, hoặc toàn 0
    output wire                granted,
    output reg                 viol_concurrent
);

    integer k;

    assign granted = |grant;

    // Chỉ số yêu cầu có ưu tiên cao nhất
    reg [NUM_IP-1:0] pick;
    always @(*) begin
        pick = {NUM_IP{1'b0}};
        for (k = NUM_IP - 1; k >= 0; k = k - 1)
            if (req[k])
                pick = ({{(NUM_IP-1){1'b0}}, 1'b1} << k);
    end

    // Quyền đang cấp có còn được giữ không
    wire hold = |(grant & req) || |(grant & ip_busy);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            grant <= {NUM_IP{1'b0}};
        end else begin
            if (!granted) begin
                grant <= pick;
            end else if (!hold) begin
                // Bên yêu cầu đã nhả VÀ IP đã hết bận -> có thể chuyển
                grant <= pick;
            end
        end
    end

    //------------------------------------------------------------------
    // Chốt cảnh báo: nhiều hơn một IP cùng bận. Không bao giờ được bật.
    //------------------------------------------------------------------
    reg [$clog2(NUM_IP+1)-1:0] busy_count;
    always @(*) begin
        busy_count = 0;
        for (k = 0; k < NUM_IP; k = k + 1)
            busy_count = busy_count + ip_busy[k];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            viol_concurrent <= 1'b0;
        else if (busy_count > 1)
            viol_concurrent <= 1'b1;      // chốt, không tự xóa
    end

endmodule
