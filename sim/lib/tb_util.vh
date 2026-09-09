//=============================================================================
// File   : sim/lib/tb_util.vh
// Mục đích: Tiện ích dùng chung cho mọi testbench — đếm PASS/FAIL và trả mã
//           thoát khác 0 khi có lỗi.
// REQ    : REQ-V-01
// Tác giả : Đội Hủ Tiếu · Ngày: 2026-09-09
//=============================================================================
// Cách dùng:
//     `include "tb_util.vh"
//     initial begin
//         `TB_BEGIN("ten_testbench")
//         `CHECK_EQ(dut_out, 32'hDEADBEEF, "mo ta phep kiem")
//         `TB_END
//     end
//=============================================================================

integer tb_pass_count = 0;
integer tb_fail_count = 0;

`define TB_BEGIN(NAME) \
    $display("=========================================================="); \
    $display("  TESTBENCH: %s", NAME); \
    $display("==========================================================");

// So sánh hai giá trị. In FAIL kèm giá trị mong đợi và thực tế.
`define CHECK_EQ(GOT, EXP, MSG) \
    if ((GOT) === (EXP)) begin \
        tb_pass_count = tb_pass_count + 1; \
    end else begin \
        tb_fail_count = tb_fail_count + 1; \
        $display("  [FAIL] %s", MSG); \
        $display("         mong doi = %h", (EXP)); \
        $display("         thuc te  = %h", (GOT)); \
    end

// Kiểm một điều kiện boolean phải đúng.
`define CHECK_TRUE(COND, MSG) \
    if (COND) begin \
        tb_pass_count = tb_pass_count + 1; \
    end else begin \
        tb_fail_count = tb_fail_count + 1; \
        $display("  [FAIL] %s  (dieu kien sai)", MSG); \
    end

// Kiểm một giá trị nằm trong ngưỡng (dùng cho REQ-P-05, REQ-P-06).
`define CHECK_LE(GOT, LIMIT, MSG) \
    if ((GOT) <= (LIMIT)) begin \
        tb_pass_count = tb_pass_count + 1; \
        $display("  [ok]   %s: %0d (nguong %0d)", MSG, (GOT), (LIMIT)); \
    end else begin \
        tb_fail_count = tb_fail_count + 1; \
        $display("  [FAIL] %s: %0d VUOT nguong %0d", MSG, (GOT), (LIMIT)); \
    end

// Kết thúc: in tổng kết và thoát với mã 0 (PASS) hoặc 1 (FAIL).
// $fatal(1,...) làm iverilog trả mã thoát khác 0 — điều kiện của REQ-V-01.
`define TB_END \
    $display("----------------------------------------------------------"); \
    $display("  PASS: %0d   FAIL: %0d", tb_pass_count, tb_fail_count); \
    if (tb_fail_count == 0) begin \
        $display("  KET QUA: PASS"); \
        $display("=========================================================="); \
        $finish; \
    end else begin \
        $display("  KET QUA: FAIL"); \
        $display("=========================================================="); \
        $fatal(1, "testbench FAIL"); \
    end

// Bộ đếm thời gian chết: mọi testbench phải có, tránh treo CI vô hạn.
`define TB_TIMEOUT(CYCLES) \
    initial begin \
        repeat (CYCLES) @(posedge clk); \
        $display("  [FAIL] TIMEOUT sau %0d chu ky", CYCLES); \
        $fatal(1, "testbench TIMEOUT"); \
    end
