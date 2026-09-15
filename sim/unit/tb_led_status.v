//=============================================================================
// File   : sim/unit/tb_led_status.v
// Mục đích: TC-606 — kiểm hành vi ba đèn chỉ thị bằng mô phỏng.
// REQ    : REQ-F-30, REQ-F-31, REQ-F-32, REQ-F-25
// Tác giả : Đội Hủ Tiếu · Ngày: 2026-09-15
//=============================================================================
// Người phụ trách đã xác nhận trực quan trên board rằng ba đèn hoạt động đúng.
// Testbench này KHÔNG thay thế việc đó mà bổ sung cho nó: quan sát bằng mắt
// khẳng định "đèn có sáng", còn mô phỏng khẳng định "đèn sáng ĐÚNG ĐIỀU KIỆN
// và tắt đúng lúc" — mắt người không phân biệt được 200 ms với 180 ms, cũng
// không nhìn thấy được chốt vi phạm loại trừ tương hỗ nếu nó chưa từng bật.
//
// LED trên Tang Nano 9K sáng ở MỨC THẤP, nên mọi phép kiểm dưới đây so với 0.
// Dùng BLINK_MS nhỏ để mô phỏng chạy nhanh; tỉ lệ thời gian không đổi.
//
// MỌI KÍCH THÍCH ĐỔI Ở SƯỜN XUỐNG. Đổi tín hiệu đúng lúc sườn lên tạo ra đua
// giữa testbench và DUT — thứ tự thực thi không xác định, nên `drop_pulse` có
// thể bị DUT nhìn thấy hoặc không. Bản đầu của testbench này mắc đúng lỗi đó và
// báo LED2 không sáng trong khi RTL hoàn toàn đúng.
//=============================================================================

`timescale 1ns / 1ps
`include "tb_util.vh"

module tb_led_status;

    `TB_DECL

    localparam CLK_HZ   = 27_000_000;
    localparam BLINK_MS = 1;                       // 27 000 chu kỳ
    localparam integer BLINK_CYCLES = (CLK_HZ / 1000) * BLINK_MS;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg rx_active       = 1'b0;
    reg engine_busy     = 1'b0;
    reg drop_pulse      = 1'b0;
    reg viol_concurrent = 1'b0;

    wire led0_n, led1_n, led2_n;

    led_status #(.CLK_HZ(CLK_HZ), .BLINK_MS(BLINK_MS)) dut (
        .clk(clk), .rst_n(rst_n),
        .rx_active(rx_active), .engine_busy(engine_busy),
        .drop_pulse(drop_pulse), .viol_concurrent(viol_concurrent),
        .led0_n(led0_n), .led1_n(led1_n), .led2_n(led2_n)
    );

    integer on_cycles;

    initial begin
        `TB_BEGIN("TC-606: ba den chi thi trang thai")

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        //---------------------------------------------------------------
        // Trang thai nghi: ca ba den phai TAT (muc cao)
        //---------------------------------------------------------------
        `CHECK_EQ({led0_n, led1_n, led2_n}, 3'b111,
                  "TC-606a: khi ranh, ca ba den deu tat")

        //---------------------------------------------------------------
        // REQ-F-30: LED0 sang khi dang nhan khung
        //---------------------------------------------------------------
        @(negedge clk); rx_active = 1'b1;
        @(posedge clk); #1;
        `CHECK_EQ(led0_n, 1'b0, "TC-606b / REQ-F-30: LED0 sang khi dang nhan")
        `CHECK_EQ(led1_n, 1'b1, "TC-606c: LED1 khong sang lay theo LED0")
        @(negedge clk); rx_active = 1'b0;
        @(posedge clk); #1;
        `CHECK_EQ(led0_n, 1'b1, "TC-606d: LED0 tat ngay khi het nhan")

        //---------------------------------------------------------------
        // REQ-F-31: LED1 sang khi engine mat ma ban
        //---------------------------------------------------------------
        @(negedge clk); engine_busy = 1'b1;
        @(posedge clk); #1;
        `CHECK_EQ(led1_n, 1'b0, "TC-606e / REQ-F-31: LED1 sang khi engine ban")
        `CHECK_EQ(led0_n, 1'b1, "TC-606f: LED0 khong sang lay theo LED1")
        @(negedge clk); engine_busy = 1'b0;
        @(posedge clk); #1;
        `CHECK_EQ(led1_n, 1'b1, "TC-606g: LED1 tat khi engine ranh")

        //---------------------------------------------------------------
        // REQ-F-32: LED2 chop khi khung bi loai.
        // Day la cho mat nguoi KHONG kiem duoc: do dai xung chop.
        //---------------------------------------------------------------
        @(negedge clk);
        drop_pulse = 1'b1;
        @(negedge clk);
        drop_pulse = 1'b0;
        #1;
        `CHECK_EQ(led2_n, 1'b0, "TC-606h / REQ-F-32: LED2 sang sau xung loai khung")

        on_cycles = 0;
        while (led2_n === 1'b0 && on_cycles < BLINK_CYCLES * 2) begin
            @(posedge clk);
            on_cycles = on_cycles + 1;
        end
        #1;
        `CHECK_EQ(led2_n, 1'b1, "TC-606i: LED2 tu tat sau khi chop xong")
        // Cho phep sai so vai chu ky quanh gia tri danh dinh
        `CHECK_TRUE((on_cycles >= BLINK_CYCLES - 4) && (on_cycles <= BLINK_CYCLES + 4),
                    "TC-606j: do dai chop dung ~BLINK_MS")
        $display("         do dai chop do duoc = %0d chu ky (danh dinh %0d)",
                 on_cycles, BLINK_CYCLES);

        //---------------------------------------------------------------
        // Xung loai khung moi phai LAM MOI bo dem, khong cong don
        //---------------------------------------------------------------
        @(negedge clk); drop_pulse = 1'b1;
        @(negedge clk); drop_pulse = 1'b0;
        repeat (BLINK_CYCLES / 2) @(posedge clk);
        @(negedge clk); drop_pulse = 1'b1;                       // lam moi
        @(negedge clk); drop_pulse = 1'b0;
        repeat (BLINK_CYCLES / 2 + 10) @(posedge clk); #1;
        `CHECK_EQ(led2_n, 1'b0,
                  "TC-606k: xung loai khung moi lam moi thoi gian chop")
        repeat (BLINK_CYCLES) @(posedge clk); #1;
        `CHECK_EQ(led2_n, 1'b1, "TC-606l: sau do van tu tat")

        //---------------------------------------------------------------
        // REQ-F-25 quan sat duoc tren phan cung: chot vi pham loai tru
        // tuong ho bat LED2 VINH VIEN, khong tu tat.
        // Mat nguoi khong the biet dieu nay neu chot chua bao gio bat.
        //---------------------------------------------------------------
        @(negedge clk); viol_concurrent = 1'b1;
        @(posedge clk); #1;
        `CHECK_EQ(led2_n, 1'b0,
                  "TC-606m / REQ-F-25: chot vi pham bat LED2")
        repeat (BLINK_CYCLES * 2) @(posedge clk); #1;
        `CHECK_EQ(led2_n, 1'b0,
                  "TC-606n: LED2 GIU sang khi co vi pham, khong tu tat")

        //---------------------------------------------------------------
        // Reset phai tat het den
        //---------------------------------------------------------------
        viol_concurrent = 1'b0;
        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk); #1;
        `CHECK_EQ({led0_n, led1_n, led2_n}, 3'b111,
                  "TC-606o: sau reset, ca ba den tat")

        `TB_END
    end

    initial begin
        #50_000_000;
        $display("  [FAIL] TIMEOUT");
        $fatal(1, "timeout");
    end

endmodule
