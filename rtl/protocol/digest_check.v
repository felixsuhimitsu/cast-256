//=============================================================================
// File   : rtl/protocol/digest_check.v
// Mục đích: So sánh hai digest 256 bit trong THỜI GIAN HẰNG ĐỊNH.
// REQ    : REQ-F-22, REQ-F-23
// Tác giả : Đội Hủ Tiếu · Ngày: 2026-09-09
//=============================================================================
// So sánh bằng XOR toàn bộ 256 bit rồi OR-reduce. Không có vòng lặp, không có
// thoát sớm, không có nhánh nào phụ thuộc dữ liệu. Thời gian luôn là một chu kỳ
// bất kể hai giá trị khác nhau ở byte đầu hay byte cuối.
//
// Vì sao quan trọng: một hiện thực so sánh từng byte và dừng ở byte đầu tiên
// khác nhau sẽ rò rỉ vị trí byte sai qua thời gian phản hồi. Kẻ tấn công có thể
// dò từng byte một để dựng lại digest hợp lệ. Với 32 byte, đó là khác biệt giữa
// 2^256 và 32 x 256 lần thử.
//
// Ở thiết kế này digest KHÔNG có khóa (SRS §10.2) nên tấn công đó vốn đã không
// cần thiết. Nhưng module vẫn được viết hằng thời, để khi nâng cấp lên HMAC thì
// phần này đã đúng sẵn.
//=============================================================================

`timescale 1ns / 1ps

module digest_check (
    input  wire [255:0] a,
    input  wire [255:0] b,
    output wire         match
);

    wire [255:0] diff = a ^ b;

    // OR-reduce toàn bộ 256 bit. Cây OR, độ sâu log2(256) = 8 mức.
    assign match = ~(|diff);

endmodule
