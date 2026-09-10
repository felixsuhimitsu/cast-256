//=============================================================================
// File   : rtl/config/keys.vh
// Mục đích: Khóa AES-256 nạp cứng lúc tổng hợp.
// REQ    : REQ-N-03
// Tác giả : Đội Hủ Tiếu · Ngày: 2026-09-09
//=============================================================================
// ĐÂY LÀ MỘT GIỚI HẠN THIẾT KẾ ĐÃ ĐƯỢC CÔNG BỐ, KHÔNG PHẢI SƠ SUẤT.
//
// Hệ thống không có cơ chế trao đổi khóa: ECDH hay RSA cần số học trường lớn,
// vượt xa 8640 LUT4 của thiết bị (SCOPE §4). Hệ quả trực tiếp:
//
//   Ai đọc được bitstream sẽ lấy được khóa này.
//
// Điều đó được ghi rõ trong SRS §10.1 và phải được nêu trong báo cáo. Không
// được mô tả hệ thống này là "an toàn trước kẻ tấn công có quyền truy cập vật
// lý vào thiết bị".
//
// Khóa dưới đây là khóa VÍ DỤ lấy từ NIST SP 800-38A §F.5.5, cố ý dùng một giá
// trị công khai để không ai nhầm tưởng đây là khóa thật dùng trong sản phẩm.
// Chỉ tách riêng ra file này để việc thay khóa là một thay đổi một dòng, và để
// script kiểm ràng buộc tầng cưỡng chế được rằng chỉ top mới tham chiếu nó.
//=============================================================================

`define AES256_HARDCODED_KEY \
    256'h603deb1015ca71be2b73aef0857d7781_1f352c073b6108d72d9810a30914dff4
