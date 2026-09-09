//=============================================================================
// File   : sim/unit/tb_sbox.v
// Mục đích: TC-100 — đối chiếu TOÀN BỘ 256 giá trị S-Box với vector FIPS 197.
// REQ    : REQ-F-04, REQ-V-02
// Tác giả : Đội Hủ Tiếu · Ngày: 2026-09-09
//=============================================================================
// Đây là test quan trọng nhất của WP-04. Rủi ro RSK-03: S-Box sai vẫn có thể
// là song ánh, nên nếu chỉ test vài giá trị hoặc chỉ test ở mức khối AES thì
// lỗi sẽ lộ ra dưới dạng "vector FIPS 197 fail" mà không có manh mối nào.
// Vì vậy phải kiểm đủ 256/256 ngay tại đây.
//=============================================================================

`timescale 1ns / 1ps
`include "tb_util.vh"

module tb_sbox;

    `TB_DECL

    reg  [8:0] i;
    reg  [7:0] a;
    wire [7:0] s;

    reg  [7:0] ref_table [0:255];
    integer    mismatches;

    aes256_sbox dut (.a(a), .s(s));

    initial begin
        `TB_BEGIN("TC-100: S-Box composite field vs FIPS 197")

        // Nguồn sự thật: sinh bởi scripts/gen_sbox_basis.py từ định nghĩa
        // FIPS 197 (nghịch đảo GF(2^8) + affine), KHÔNG phải chép tay.
        $readmemh("../../sim/vectors/sbox_ref.hex", ref_table);

        // Kiểm tra file vector đã nạp được, tránh trường hợp đọc hụt mà
        // vẫn "PASS" vì so sánh x === x.
        `CHECK_EQ(ref_table[8'h00], 8'h63, "vector nap duoc: S(00) = 63")
        `CHECK_EQ(ref_table[8'h53], 8'hED, "vector nap duoc: S(53) = ED")

        mismatches = 0;
        for (i = 0; i < 256; i = i + 1) begin
            a = i[7:0];
            #1;
            if (s !== ref_table[i[7:0]]) begin
                mismatches = mismatches + 1;
                if (mismatches <= 8)
                    $display("  [FAIL] S(%02h): mong doi %02h, thuc te %02h",
                             i[7:0], ref_table[i[7:0]], s);
            end
        end

        `CHECK_EQ(mismatches, 0, "so gia tri sai trong 256")

        // Kiểm phụ: S-Box phải là song ánh (điều kiện cần, không đủ).
        // Giữ lại vì nếu vector file hỏng thì phép kiểm này vẫn bắt được
        // một lớp lỗi khác.
        begin : bijection_check
            reg [255:0] seen;
            integer     j, dup;
            seen = 256'd0;
            dup  = 0;
            for (j = 0; j < 256; j = j + 1) begin
                a = j[7:0];
                #1;
                if (seen[s]) dup = dup + 1;
                seen[s] = 1'b1;
            end
            `CHECK_EQ(dup, 0, "S-Box la song anh (khong gia tri trung)")
        end

        `TB_END
    end

endmodule
