//=============================================================================
// File   : sim/lib/csi_checker.v
// Mục đích: Kiểm tự động các bất biến INV-1..6 và quy tắc bắt tay H1..H5 của
//           hợp đồng CSI v1.0. Chỉ dùng trong mô phỏng, KHÔNG tổng hợp.
// REQ    : REQ-I-01, REQ-I-02
// Tham chiếu: docs/03-architecture/IP_INTERFACE_CONTRACT.md §3, §5
// Tác giả : Đội Hủ Tiếu · Ngày: 2026-09-09
//=============================================================================
// Cách dùng: instantiate song song với IP cần kiểm, nối cùng các tín hiệu.
//
//     csi_checker #(.NAME("aes256_ctr_ip")) u_chk (
//         .clk(clk), .rst_n(rst_n),
//         .csi_start(start), .csi_busy(busy), .csi_done(done), .csi_err(err),
//         .sin_valid(sv), .sin_ready(sr), .sin_data(sd), .sin_last(sl),
//         .sout_valid(ov), .sout_ready(orr), .sout_data(od), .sout_last(ol),
//         .csi_result_valid(rv)
//     );
//
// Checker tự đếm lỗi vào cổng ra `viol_count`; testbench kiểm cổng này = 0.
//=============================================================================

`timescale 1ns / 1ps

module csi_checker #(
    parameter NAME       = "unnamed_ip",
    parameter CSI_DATA_W = 8
) (
    input  wire                    clk,
    input  wire                    rst_n,

    input  wire                    csi_start,
    input  wire                    csi_busy,
    input  wire                    csi_done,
    input  wire                    csi_err,

    input  wire [CSI_DATA_W-1:0]   sin_data,
    input  wire                    sin_valid,
    input  wire                    sin_last,
    input  wire                    sin_ready,

    input  wire [CSI_DATA_W-1:0]   sout_data,
    input  wire                    sout_valid,
    input  wire                    sout_last,
    input  wire                    sout_ready,

    input  wire                    csi_result_valid,

    output reg  [15:0]             viol_count
);

    // ---- trạng thái theo dõi -------------------------------------------
    reg                    busy_d;
    reg                    done_d;
    reg                    sin_valid_d;
    reg [CSI_DATA_W-1:0]   sin_data_d;
    reg                    sin_last_d;
    reg                    sin_ready_d;
    reg                    sout_valid_d;
    reg [CSI_DATA_W-1:0]   sout_data_d;
    reg                    sout_last_d;
    reg                    sout_ready_d;
    reg [7:0]              start_age;      // đếm chu kỳ từ csi_start
    reg                    start_pending;
    reg                    last_seen;      // đã thấy sin_last trong thao tác này

    task viol;
        input [255:0] msg;
        begin
            viol_count = viol_count + 1;
            $display("  [CSI-VIOL] %0s @%0t: %0s", NAME, $time, msg);
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            viol_count    <= 16'd0;
            busy_d        <= 1'b0;
            done_d        <= 1'b0;
            sin_valid_d   <= 1'b0;
            sin_data_d    <= {CSI_DATA_W{1'b0}};
            sin_last_d    <= 1'b0;
            sin_ready_d   <= 1'b0;
            sout_valid_d  <= 1'b0;
            sout_data_d   <= {CSI_DATA_W{1'b0}};
            sout_last_d   <= 1'b0;
            sout_ready_d  <= 1'b0;
            start_age     <= 8'd0;
            start_pending <= 1'b0;
            last_seen     <= 1'b0;
        end else begin

            //---------------------------------------------------------------
            // INV-1: csi_done không bao giờ lên khi csi_busy đang là 0
            //---------------------------------------------------------------
            if (csi_done && !csi_busy && !busy_d)
                viol("INV-1: done len khi khong busy");

            //---------------------------------------------------------------
            // INV-2: csi_done rộng đúng 1 chu kỳ
            //---------------------------------------------------------------
            if (csi_done && done_d)
                viol("INV-2: done rong hon 1 chu ky");

            //---------------------------------------------------------------
            // INV-3: sin_ready không bao giờ lên khi csi_busy = 0
            //---------------------------------------------------------------
            if (sin_ready && !csi_busy)
                viol("INV-3: sin_ready len khi khong busy");

            //---------------------------------------------------------------
            // INV-4: sau csi_start, csi_busy phải lên trong <= 2 chu kỳ
            //---------------------------------------------------------------
            if (csi_start && !csi_busy) begin
                start_pending <= 1'b1;
                start_age     <= 8'd0;
            end else if (start_pending) begin
                if (csi_busy) begin
                    start_pending <= 1'b0;
                end else if (start_age >= 8'd2) begin
                    viol("INV-4: busy khong len trong 2 chu ky sau start");
                    start_pending <= 1'b0;
                end else begin
                    start_age <= start_age + 8'd1;
                end
            end

            //---------------------------------------------------------------
            // INV-5: csi_err = 1  =>  csi_result_valid = 0
            //---------------------------------------------------------------
            if (csi_err && csi_result_valid)
                viol("INV-5: err va result_valid cung len");

            //---------------------------------------------------------------
            // INV-6: sin_last chỉ được xuất hiện đúng một lần mỗi thao tác
            //---------------------------------------------------------------
            if (sin_valid && sin_ready && sin_last) begin
                if (last_seen)
                    viol("INV-6: sin_last xuat hien lan thu hai trong 1 thao tac");
                last_seen <= 1'b1;
            end
            if (csi_done)
                last_seen <= 1'b0;

            //---------------------------------------------------------------
            // H2: valid đã lên thì PHẢI giữ valid/data/last cho tới khi ready
            //     (áp dụng cho cả hai chiều dòng dữ liệu)
            //---------------------------------------------------------------
            if (sin_valid_d && !sin_ready_d) begin
                if (!sin_valid)
                    viol("H2: sin_valid bi rut lai truoc khi thay ready");
                else if (sin_data !== sin_data_d)
                    viol("H2: sin_data doi khi dang cho ready");
                else if (sin_last !== sin_last_d)
                    viol("H2: sin_last doi khi dang cho ready");
            end

            if (sout_valid_d && !sout_ready_d) begin
                if (!sout_valid)
                    viol("H2: sout_valid bi rut lai truoc khi thay ready");
                else if (sout_data !== sout_data_d)
                    viol("H2: sout_data doi khi dang cho ready");
                else if (sout_last !== sout_last_d)
                    viol("H2: sout_last doi khi dang cho ready");
            end

            //---------------------------------------------------------------
            // H5: last chỉ có nghĩa khi valid = 1. Cảnh báo nếu last lên
            //     trong khi valid = 0 (không sai chức năng nhưng là mùi lỗi).
            //---------------------------------------------------------------
            if (sin_last && !sin_valid)
                viol("H5: sin_last len khi sin_valid = 0");
            if (sout_last && !sout_valid)
                viol("H5: sout_last len khi sout_valid = 0");

            //---------------------------------------------------------------
            // REQ-F-07: csi_start bị bỏ qua khi đang busy — chỉ ghi nhận,
            // không coi là vi phạm (IP phải bỏ qua chứ không phải cấm phát).
            //---------------------------------------------------------------

            // ---- ghi trễ cho chu kỳ sau ---------------------------------
            busy_d       <= csi_busy;
            done_d       <= csi_done;
            sin_valid_d  <= sin_valid;
            sin_data_d   <= sin_data;
            sin_last_d   <= sin_last;
            sin_ready_d  <= sin_ready;
            sout_valid_d <= sout_valid;
            sout_data_d  <= sout_data;
            sout_last_d  <= sout_last;
            sout_ready_d <= sout_ready;
        end
    end

    // Báo cáo cuối mô phỏng
    task report;
        begin
            if (viol_count == 0)
                $display("  [CSI-OK]   %0s: khong vi pham hop dong CSI", NAME);
            else
                $display("  [CSI-FAIL] %0s: %0d vi pham", NAME, viol_count);
        end
    endtask

endmodule
