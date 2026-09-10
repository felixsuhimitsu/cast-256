#!/usr/bin/env python3
"""Điền báo cáo VMBMATTT 2026 từ template. Mọi con số đều lấy từ log thật."""
import copy
from docx import Document
from docx.shared import Pt, Cm
from docx.enum.text import WD_ALIGN_PARAGRAPH

SRC = 'docs/Template_Bao_cao_San_pham_VMBMATTT_2026.docx'
OUT = 'docs/BaoCao_SanPham_HuTieu_VMBMATTT_2026.docx'
FIG = 'docs/hinh1_kien_truc.png'

d = Document(SRC)
P = d.paragraphs


def setp(p, text, size=11, bold=None, italic=False, align=None):
    for r in p.runs[1:]:
        r._element.getparent().remove(r._element)
    if not p.runs:
        p.add_run('')
    r = p.runs[0]
    r.text = text
    r.font.size = Pt(size)
    r.italic = italic
    if bold is not None:
        r.bold = bold
    if align is not None:
        p.alignment = align
    return p


def after(p, text, size=11, bold=False, italic=False):
    new = copy.deepcopy(p._element)
    p._element.addnext(new)
    from docx.text.paragraph import Paragraph
    np = Paragraph(new, p._parent)
    return setp(np, text, size, bold, italic)


def before(p, text, size=11, bold=False, italic=False):
    new = copy.deepcopy(p._element)
    p._element.addprevious(new)
    from docx.text.paragraph import Paragraph
    np = Paragraph(new, p._parent)
    return setp(np, text, size, bold, italic)


def cell(t, r, c, text, size=10, bold=False):
    cp = t.cell(r, c).paragraphs[0]
    for run in cp.runs[1:]:
        run._element.getparent().remove(run._element)
    if not cp.runs:
        cp.add_run('')
    run = cp.runs[0]
    run.text = text
    run.font.size = Pt(size)
    run.bold = bold


def drop(el):
    el.getparent().remove(el)


# ─────────────────────────── trang bìa ───────────────────────────
setp(P[1], 'THIẾT KẾ VÀ TÍCH HỢP IP MÃ HÓA AES-256 VÀ SHA-256\n'
           'CHO GIAO THỨC TRUYỀN VÀ NHẬN DỮ LIỆU', 14, bold=True,
     align=WD_ALIGN_PARAGRAPH.CENTER)
setp(P[2], 'Nhóm dự thi: Hủ Tiếu', 12, align=WD_ALIGN_PARAGRAPH.CENTER)
setp(P[3], 'Đơn vị: Trường Đại học Công nghệ Thông tin và Truyền thông – Đại học Thái Nguyên',
     11, align=WD_ALIGN_PARAGRAPH.CENTER)
setp(P[4], 'Liên hệ: huynhpham13790@gmail.com', 11, align=WD_ALIGN_PARAGRAPH.CENTER)

# ─────────────────────────── tóm tắt ───────────────────────────
setp(P[6],
     'Các thiết bị nhúng nhỏ thường truyền dữ liệu qua liên kết nối tiếp thô (UART, RS-485) '
     'vốn không có bảo mật ở tầng vật lý: ai chạm được vào đường dây đều đọc và sửa được từng '
     'byte. Sản phẩm là hai IP core mật mã tự thiết kế — AES-256 chế độ CTR và SHA-256 — cùng '
     'một hợp đồng giao diện dòng chảy chuẩn hóa (CSI v1.0), tích hợp vào một giao thức khung '
     'truyền/nhận chạy thật trên FPGA Sipeed Tang Nano 9K bằng toàn bộ toolchain mã nguồn mở. '
     'Điểm mới không nằm ở thuật toán mà ở lớp tích hợp: hai IP có cùng hình dạng cổng nên bộ '
     'định tuyến đối xử với chúng như nhau, đổi chỗ hai IP không cần sửa một dòng nào, và thêm '
     'IP thứ ba chỉ cần tăng một tham số. Kết quả đo trên phần cứng: 6664/8640 LUT4 (77%), '
     'F_max 46,85 MHz, 100 khung liên tiếp với 0% mất, độ trễ 32,42 ms và thông lượng '
     '10 778 B/s — đạt 93,6% trần lý thuyết của UART 115200.', 11)

# ─────────────────────── 1. Mở đầu ───────────────────────
setp(P[8],
     'Cảm biến công nghiệp, thiết bị đo từ xa và module IoT giá rẻ hầu hết vẫn dùng UART hoặc '
     'RS-485 để đưa dữ liệu về bộ thu thập. Đây là liên kết hoàn toàn trần: kẻ tấn công tiếp cận '
     'được đường dây sẽ đọc trọn nội dung, và sửa được từng byte mà bên nhận không có cách nào '
     'phát hiện.', 11)
p = after(P[8],
    'Hai hướng khắc phục hiện có đều có nhược điểm rõ. Chạy mã hóa bằng phần mềm trên vi điều '
    'khiển thì tiêu tốn chu kỳ CPU vốn đã hạn hẹp, và khóa nằm trong bộ nhớ chương trình nên dễ '
    'bị trích xuất. Mua IP core mật mã thương mại thì đắt và là hộp đen — người dùng không kiểm '
    'chứng được thứ mình đang tin tưởng, điều đặc biệt khó chấp nhận với một khối mật mã.', 11)
p = after(p,
    'Đề tài chọn hướng thứ ba: tự thiết kế IP mật mã ở mức RTL, kiểm chứng bằng vector chuẩn của '
    'NIST, và quan trọng hơn — chuẩn hóa giao diện để chúng thực sự là "IP tích hợp được" chứ '
    'không phải hai khối logic nối tay. Toàn bộ dùng toolchain mã nguồn mở (Yosys, '
    'nextpnr-himbaechel, Project Apicula) trên một FPGA phổ thông giá dưới 200 nghìn đồng, nên '
    'mọi bước đều tái lập được mà không cần license.', 11)

# ─────────────────── 2. Mục tiêu và phạm vi ───────────────────
setp(P[10], '• Mục tiêu 1: Thiết kế IP AES-256 chế độ CTR và IP SHA-256 ở mức RTL, đạt 100% '
            'vector chuẩn FIPS 197, FIPS 180-4 và NIST SP 800-38A.', 11, bold=False)
setp(P[11], '• Mục tiêu 2: Chuẩn hóa một hợp đồng giao diện dùng chung cho cả hai IP, sao cho lớp '
            'giao thức không cần biết IP nào là AES, IP nào là SHA.', 11, bold=False)
setp(P[12], '• Mục tiêu 3: Đạt chỉ tiêu định lượng trên phần cứng thật — vừa trong 8640 LUT4, '
            'F_max ≥ 27 MHz, 0% mất khung trên 100 khung liên tiếp, thông lượng ≥ 8000 B/s.', 11, bold=False)
setp(P[13], '• Phạm vi: Bảo vệ tính bí mật và toàn vẹn của khung dữ liệu trên đường truyền nối '
            'tiếp giữa hai thiết bị đã tin cậy nhau. Khóa AES nạp cứng lúc tổng hợp — hệ thống '
            'KHÔNG chống được kẻ tấn công đọc được bitstream, và trường digest không có khóa nên '
            'KHÔNG chống được kẻ tấn công chủ động biết thuật toán. Hai giới hạn này được phân '
            'tích ở mục 5.4.', 11, bold=False)

# ─────────────── 3. Nghiên cứu liên quan và điểm mới ───────────────
setp(P[15],
     'S-Box AES bằng số học trường composite GF(((2²)²)²) là hướng đã được Satoh và Canright đặt '
     'nền [3][4], cho diện tích nhỏ hơn nhiều so với bảng tra 256×8. Các hiện thực AES/SHA trên '
     'FPGA nhỏ thường tối ưu từng lõi riêng lẻ và nối chúng bằng logic đặc thù.', 11)
p = after(P[15],
    'Khoảng trống mà đề tài nhắm tới không phải ở lõi mật mã mà ở lớp tích hợp. Khi mỗi lõi có một '
    'kiểu giao diện riêng, lớp giao thức phải viết mã đặc thù cho từng lõi; thêm một thuật toán '
    'thứ ba đồng nghĩa sửa lại lớp giao thức. Đóng góp của đề tài gồm ba điểm:', 11)
p = after(p, '(1) Hợp đồng giao diện CSI v1.0 — tập con tối giản kiểu AXI-Stream, đủ cho cả IP '
             'sinh dòng dữ liệu (AES) lẫn IP sinh kết quả thanh ghi (SHA), kèm 6 bất biến được '
             'kiểm tự động ở mọi chu kỳ mô phỏng.', 11)
p = after(p, '(2) Tầng định tuyến cưỡng chế loại trừ tương hỗ ở hai lớp độc lập, và phát hiện vi '
             'phạm ra đèn LED — biến một bất biến vốn chỉ kiểm được trong mô phỏng thành thứ quan '
             'sát được trên board.', 11)
p = after(p, '(3) Chia sẻ tài nguyên có kiểm chứng: key schedule mượn 4 trong 8 khối S-Box của '
             'đường dữ liệu, tiết kiệm 324 LUT4 mà không ảnh hưởng tính đúng đắn.', 11)

# ─────────────── 4. Giải pháp và kiến trúc ───────────────
setp(P[18],
     'Thiết kế chia thành bốn tầng có ràng buộc phụ thuộc một chiều, được cưỡng chế tự động bằng '
     'script trong bước lint: io/ (UART), protocol/ (ý nghĩa khung), fabric/ (cấp phát và định '
     'tuyến IP), ip/ (toán học mật mã thuần túy). Tầng ip/ không biết gì về ba tầng còn lại, nên '
     'hai IP dùng lại nguyên vẹn được ở dự án khác. Tầng protocol/ không được phép instantiate '
     'trực tiếp module trong ip/ — mọi truy cập phải đi qua fabric/. Chính hai quy tắc này biến '
     'sản phẩm từ "hai khối mật mã" thành "hai IP tích hợp được".', 11)

setp(P[19], 'Hình 1. Kiến trúc bốn tầng, luồng dữ liệu một khung và số liệu tài nguyên đo được.',
     10, italic=True, align=WD_ALIGN_PARAGRAPH.CENTER)

# ─────────────── 4.1 Cơ chế kỹ thuật ───────────────
setp(P[21],
     'Một khung đi vào có dạng A5 5A || LEN(2) || IV(16) || PAYLOAD(LEN) || DIGEST(32), với '
     'DIGEST = SHA-256(LEN||IV||PAYLOAD). Bộ mở khung quét liên tục cặp byte preamble nên không giả '
     'định biên khung và tự phục hồi sau nhiễu; LEN được kiểm thuộc [1, 512] ngay khi đọc xong, '
     'trước khi cấp phát bộ đệm.', 11)
p = after(P[21],
    'Máy trạng thái phiên xử lý theo năm bước: băm LEN||IV||payload rồi so với DIGEST nhận được; '
    'nếu không khớp thì KHÔNG phát gì cả (fail closed); nếu khớp thì mã hóa payload tại chỗ bằng '
    'AES-256-CTR, băm lại trên bản mã, rồi đóng khung trả lời. Phép so digest dùng XOR toàn bộ 256 '
    'bit rồi OR-reduce — thời gian hằng định, không có nhánh nào phụ thuộc dữ liệu.', 11)
p = after(p,
    'Chế độ CTR được chọn có chủ đích: keystream_block = AES-Encrypt(counter + j) và ciphertext = '
    'plaintext XOR keystream. Vì XOR đối xứng nên cùng một khối cipher dùng cho cả hai chiều, và '
    'thiết kế KHÔNG cần hàm AES nghịch — không tồn tại InvSubBytes hay InvMixColumns trong toàn bộ '
    'mã nguồn, tiết kiệm khoảng một nửa diện tích so với hiện thực AES đầy đủ.', 11)

# ─────────────── 4.2 Kiến trúc RTL và giao diện ───────────────
p = after(P[22],
    'Hai IP có đúng cùng một tập cổng: nhóm điều khiển (csi_start / csi_mode / csi_busy / csi_done '
    '/ csi_err), dòng dữ liệu vào và ra theo bắt tay valid/ready, và một cổng kết quả dạng thanh '
    'ghi. IP nào không dùng một nhóm thì buộc dây cố định chứ không được xóa cổng: SHA-256 đặt '
    'dòng ra bằng 0, AES-CTR đặt kết quả thanh ghi bằng 0.', 11)
p = after(p,
    'Sáu bất biến của hợp đồng (done không lên khi chưa busy; done rộng đúng một chu kỳ; ready chỉ '
    'lên khi busy; busy phải lên trong hai chu kỳ sau start; err thì kết quả không hợp lệ; last '
    'xuất hiện đúng một lần mỗi thao tác) được một module kiểm tra chạy song song với IP trong mọi '
    'testbench, đếm vi phạm ở từng chu kỳ. Kiểm này đã bắt được lỗi thật: bản đầu của IP SHA-256 '
    'báo done ở nhánh lỗi mà chưa từng vào trạng thái busy.', 11)
p = after(p,
    'AES-256 dùng kiến trúc lặp với 8 khối S-Box, hai chu kỳ mỗi vòng, tổng 30 chu kỳ mỗi khối '
    '128 bit. Con số 8 là kết quả của một lần tối ưu có đo: bản 16 S-Box chiếm 2961 LUT4, vượt '
    'ngân sách, và phép đo cho thấy S-Box chiếm 44% diện tích IP nên đó mới là chỗ đáng cắt. '
    'SHA-256 dùng cửa sổ trượt 16 word thay vì lưu đủ 64 word của lịch trình thông điệp, tiết kiệm '
    '1536 thanh ghi. Khóa vòng AES nằm trong bốn khối BSRAM 16×32 bit; đây cũng là một phát hiện '
    'phải trả giá bằng một lần P&R thất bại, trình bày ở mục 5.3.', 11)

# ─────────────── 5.1 Thiết lập thực nghiệm ───────────────
setp(P[25], 'Nền tảng và công cụ:', 11, bold=True)

t = d.tables[2]
cell(t, 0, 0, 'FPGA / board', 10, True)
cell(t, 0, 1, 'Sipeed Tang Nano 9K — GW1NR-LV9QN88PC6/I5 (8640 LUT4, 6480 DFF, 26 BSRAM)', 10)
cell(t, 1, 0, 'Toolchain', 10, True)
cell(t, 1, 1, 'Yosys 0.68 + nextpnr-himbaechel 0.11.1 + Project Apicula — toàn bộ mã nguồn mở, '
              'không dùng license thương mại', 10)
cell(t, 2, 0, 'Clock / constraints', 10, True)
cell(t, 2, 1, 'Một miền xung nhịp duy nhất 27,0 MHz (create_clock -period 37.037). Không CDC, '
              'không FIFO bất đồng bộ', 10)
cell(t, 3, 0, 'Kiểm chứng chức năng', 10, True)
cell(t, 3, 1, '6 testbench Icarus Verilog (S-Box, UART, SHA, AES, fabric, toàn hệ) với vector '
              'FIPS 197 / FIPS 180-4 / SP 800-38A', 10)
cell(t, 4, 0, 'Kiểm chứng phần cứng', 10, True)
cell(t, 4, 1, 'scripts/hw_test.py qua UART /dev/ttyUSB1; giá trị kỳ vọng sinh từ hiện thực tham '
              'chiếu Python (hashlib, cryptography)', 10)

# ─────────────── 5.2 Kiểm chứng chức năng ───────────────
setp(P[27],
     'Cả 6 testbench mô phỏng đều PASS. IP AES-256 vượt 17/17 phép kiểm, gồm vector khối đơn của '
     'FIPS 197 phụ lục C.3 và toàn bộ 4 khối liên tiếp của NIST SP 800-38A §F.5.5 — phép kiểm sau '
     'chứng minh bộ đếm CTR tăng đúng qua ranh giới khối, không chỉ đúng ở một khối đơn lẻ. '
     'IP SHA-256 vượt 17/17, gồm các độ dài biên 55, 56, 63, 64, 119 và 120 byte; hai giá trị 55 và '
     '56 nằm hai bên ranh giới nơi phần đệm phải tràn sang khối thứ hai. S-Box được đối chiếu đủ '
     'cả 256 giá trị ở mức module con.', 11)
p = after(P[27],
    'Trên phần cứng thật, chương trình kiểm quét 19 độ dài payload từ 1 đến 512 byte: mọi khung '
    'trả về đều có bản mã AES-256-CTR và digest SHA-256 khớp chính xác hiện thực tham chiếu, và '
    'giải mã lại cho đúng bản rõ ban đầu. LEN = 0 và LEN = 1024 đều bị loại đúng như đặc tả.', 11)
p = after(p,
    'Ba kịch bản đối kháng — sửa một bit trong payload, cắt khung giữa chừng, gửi 32 byte rác '
    'trước preamble — đều cho kết quả đúng, và mỗi kịch bản đều chạy HAI PHA: pha A kiểm hệ thống '
    'im lặng, pha B gửi ngay một khung hợp lệ để chứng minh FPGA còn sống. Đây không phải hình '
    'thức: một bộ kiểm chỉ có pha A sẽ báo PASS ngay cả khi thiết kế đã chết hoàn toàn, và trong '
    'quá trình phát triển đã có đúng một lỗi làm toàn hệ câm lặng với triệu chứng bên ngoài y hệt '
    'hành vi từ chối đúng.', 11)

# ─────────────── 5.3 Kết quả triển khai ───────────────
setp(P[29], 'Kết quả sau P&R trên GW1NR-LV9QN88PC6/I5:', 11, bold=True)

t = d.tables[3]
cell(t, 0, 0, 'Khối', 10, True)
cell(t, 0, 1, 'LUT4', 10, True)
cell(t, 0, 2, 'DFF', 10, True)
cell(t, 0, 3, 'F_max', 10, True)
cell(t, 0, 4, 'Chu kỳ/khối', 10, True)
cell(t, 0, 5, 'Thông lượng', 10, True)
cell(t, 0, 6, 'BSRAM', 10, True)

cell(t, 1, 0, 'IP AES-256-CTR', 10)
cell(t, 1, 1, '2 528', 10); cell(t, 1, 2, '1 357', 10); cell(t, 1, 3, '—', 10)
cell(t, 1, 4, '30', 10); cell(t, 1, 5, '14,4 MB/s', 10); cell(t, 1, 6, '4', 10)

cell(t, 2, 0, 'IP SHA-256', 10)
cell(t, 2, 1, '1 661', 10); cell(t, 2, 2, '1 146', 10); cell(t, 2, 3, '—', 10)
cell(t, 2, 4, '65', 10); cell(t, 2, 5, '6,6 MB/s', 10); cell(t, 2, 6, '0', 10)

cell(t, 3, 0, 'protocol/ + fabric/ + io/', 10)
cell(t, 3, 1, '≈ 2 475', 10); cell(t, 3, 2, '≈ 1 065', 10); cell(t, 3, 3, '—', 10)
cell(t, 3, 4, '—', 10); cell(t, 3, 5, '—', 10); cell(t, 3, 6, '1', 10)

cell(t, 4, 0, 'THIS WORK (toàn hệ)', 10, True)
cell(t, 4, 1, '6 664 / 8 640 (77%)', 10, True)
cell(t, 4, 2, '3 568 / 6 480 (55%)', 10, True)
cell(t, 4, 3, '46,85 MHz', 10, True)
cell(t, 4, 4, '—', 10, True)
cell(t, 4, 5, '10 778 B/s', 10, True)
cell(t, 4, 6, '5 / 26', 10, True)

p = before(P[30], 'Đo hiệu năng trên board với 100 khung liên tiếp, payload 128 byte: tỉ lệ mất '
                  'khung 0,00%; độ trễ khứ hồi min 32,34 ms, trung bình 32,42 ms, tối đa 32,55 ms, '
                  'độ lệch chuẩn 0,03 ms; thông lượng 10 778 B/s tương đương 86,2 kbps.', 11, bold=True)
p = after(p,
    'Độ lệch chuẩn 0,03 ms trên 100 khung cho thấy đường xử lý là tất định — không có bộ đệm nào '
    'tràn và không có đường nào phụ thuộc dữ liệu. Thông lượng đạt 93,6% trần lý thuyết của UART '
    '115200 (11 520 B/s); phần thiếu là 20 byte header và 32 byte digest của mỗi khung chứ không '
    'phải do engine chậm. Bản thân engine AES chạy ở 14,4 MB/s, tức nhanh hơn đường truyền hơn '
    '1000 lần, nên nút thắt nằm hoàn toàn ở lớp vật lý.', 11)
p = after(p,
    'Một kết quả đáng ghi lại: lần P&R đầu tiên THẤT BẠI dù báo cáo cùng lúc cho thấy LUT4 mới '
    'dùng 80% và DFF 60%. Nguyên nhân là bộ nhớ khóa vòng AES được khai báo dạng mảng 15×128 bit, '
    'trong khi cổng BSRAM của Gowin rộng tối đa 32 bit; công cụ tổng hợp rơi về RAM phân tán và '
    'sinh 32 khối RAM16SDP4, loại tài nguyên chỉ đặt được ở một số vị trí nhất định. Tách thành '
    'bốn bộ nhớ 16×32 bit đưa chúng vào BSRAM và P&R chạy qua ngay. Bài học: "còn 20% tài nguyên" '
    'không đồng nghĩa với "đặt chỗ được" — loại tài nguyên và ràng buộc vị trí quan trọng ngang số '
    'lượng.', 11)

# ─────────────── 5.4 Đánh giá mức độ bảo mật ───────────────
setp(P[31],
     'Mô hình đe dọa: kẻ tấn công tiếp cận được đường dây nối tiếp giữa hai thiết bị, đọc và chèn '
     'được byte tùy ý, nhưng không truy cập được vào bên trong FPGA.', 11, bold=False, italic=False)
p = after(P[31], 'Những gì hệ thống bảo vệ được:', 11, bold=True)
p = after(p, '• Tính bí mật của payload. Dữ liệu đi trên dây ở dạng bản mã AES-256-CTR. Không có '
             'khóa thì không khôi phục được nội dung.', 11)
p = after(p, '• Toàn vẹn trước nhiễu và sửa đổi ngẫu nhiên. Một bit sai bất kỳ trong payload hay '
             'digest đều làm khung bị loại; đã kiểm chứng trên phần cứng.', 11)
p = after(p, '• Rò rỉ qua thời gian phản hồi. Phép so digest quét đủ 32 byte, không thoát sớm, '
             'nên không lộ vị trí byte sai. Độ lệch chuẩn độ trễ 0,03 ms trên 100 khung là bằng '
             'chứng định lượng cho tính tất định này.', 11)

p = after(p, 'Những gì hệ thống KHÔNG bảo vệ được — công bố đầy đủ:', 11, bold=True)
p = after(p, '• Kẻ tấn công CHỦ ĐỘNG. Trường 32 byte là SHA-256(LEN||IV||PT) — một checksum toàn vẹn '
             'KHÔNG CÓ KHÓA, không phải MAC. Kẻ tấn công biết thuật toán có thể sửa payload rồi '
             'tính lại digest và bên nhận sẽ chấp nhận. Cách đúng là HMAC-SHA-256 (RFC 2104); đã '
             'hiện thực và vượt mô phỏng nhưng không vừa thiết bị (đo được 85–107% LUT4). Chúng '
             'tôi chọn nộp một thiết kế chạy thật kèm công bố giới hạn, thay vì một thiết kế đúng '
             'lý thuyết mà không nạp được lên board.', 11)
p = after(p, '• Khóa nạp cứng. Không có cơ chế trao đổi khóa vì số học trường lớn (ECDH/RSA) vượt '
             'xa 8640 LUT4. Ai đọc được bitstream sẽ lấy được khóa.', 11)
p = after(p, '• Tấn công kênh kề. Thời gian chạy AES là hằng định do kiến trúc lặp không phụ thuộc '
             'dữ liệu, nhưng không có biện pháp chống phân tích công suất (DPA); che mặt nạ '
             '(masking) sẽ nhân đôi diện tích.', 11)

# ─────────────── 6.1 Hồ sơ và demo ───────────────
t = d.tables[4]
cell(t, 0, 0, 'MÃ NGUỒN', 10, True)
cell(t, 0, 1, 'github.com/felixsuhimitsu/cast-256 — nhánh feat/aes-sha256-ip-integration.\n'
              'Gồm 20 file RTL, 6 testbench, bộ kiểm phần cứng, và lớp tài liệu 11 bước trong '
              'docs/ (scope, spec, module map, kiến trúc, hợp đồng giao diện, WBS, ước lượng, rủi '
              'ro, gate, kế hoạch test, ma trận truy vết, 8 quyết định kiến trúc và nhật ký phát '
              'triển).\nVIDEO DEMO: [chờ quay — kịch bản ở mục dưới]', 10)
cell(t, 1, 0, 'TRẠNG THÁI HOÀN THIỆN', 10, True)
cell(t, 1, 1, '[RTL ✓]   [Simulation ✓ — 6/6 testbench PASS]   [FPGA ✓ — chạy thật, 0% mất khung]   '
              '[ASIC synthesis ✗ — ngoài phạm vi]', 10)

p = after(P[33],
    'Kịch bản video: bài toán và mô hình đe dọa → sơ đồ bốn tầng và điểm tích hợp CSI → make sim '
    '(6/6 PASS) → nạp bitstream, chạy sweep 19 độ dài và bench 100 khung, quan sát ba đèn LED → '
    'chế độ tamper/timeout với hai pha A/B → kết luận và giới hạn.', 9, italic=True)

# ─────────────── 6.2 Kết luận ───────────────
setp(P[35],
     'Đề tài đã hoàn thành hai IP mật mã tự thiết kế và chứng minh chúng tích hợp được vào một '
     'giao thức truyền/nhận chạy thật, bằng toàn bộ công cụ mã nguồn mở trên FPGA phổ thông. Ba '
     'kết quả định lượng chính: 6664/8640 LUT4 (77%) với F_max 46,85 MHz — dư 73% biên tần số so '
     'với yêu cầu 27 MHz; 100 khung liên tiếp với 0% mất và độ lệch chuẩn độ trễ 0,03 ms; và 19/19 '
     'độ dài payload từ 1 đến 512 byte cho bản mã cùng digest khớp chính xác hiện thực tham chiếu.', 11)
p = after(P[35],
    'Mức độ hoàn thiện: RTL và mô phỏng đầy đủ, đã chạy trên phần cứng thật với bằng chứng log '
    'lưu kèm. Sản phẩm dùng được ngay cho các liên kết cảm biến–bộ thu thập trong mạng nội bộ đã '
    'tin cậy nhau. Hướng phát triển tiếp theo, theo thứ tự ưu tiên: thay digest không khóa bằng '
    'HMAC-SHA-256 bằng cách chia sẻ đường dữ liệu SHA giữa hai lần gọi thay vì dùng hai instance; '
    'bổ sung trao đổi khóa khi chuyển sang thiết bị lớn hơn; và cắm thêm một IP thứ ba (ChaCha20) '
    'để kiểm chứng lần nữa rằng hợp đồng giao diện thực sự mở.', 11)

# ─────────────── Tài liệu tham khảo ───────────────
REFS = [
    '[1] NIST, FIPS PUB 197: Advanced Encryption Standard (AES), 2001.',
    '[2] NIST, FIPS PUB 180-4: Secure Hash Standard (SHS), 2015.',
    '[3] NIST, SP 800-38A: Recommendation for Block Cipher Modes of Operation, 2001.',
    '[4] D. Canright, "A Very Compact S-Box for AES", CHES 2005, LNCS 3659, pp. 441–455.',
    '[5] A. Satoh et al., "A Compact Rijndael Hardware Architecture with S-Box Optimization", '
    'ASIACRYPT 2001, LNCS 2248.',
    '[6] H. Krawczyk et al., RFC 2104: HMAC — Keyed-Hashing for Message Authentication, 1997.',
    '[7] YosysHQ, Yosys Open SYnthesis Suite và nextpnr, tài liệu chính thức, 2024.',
    '[8] Project Apicula — bitstream documentation cho FPGA Gowin, 2024.',
]
setp(P[37], REFS[0], 9, bold=False)
ref = P[37]
for x in REFS[1:]:
    ref = after(ref, x, 9)

# ─────────────── dọn phần khung mẫu ───────────────
# Lấy tham chiếu TRƯỚC khi xóa: xóa bảng 0 làm mọi chỉ số sau đó lùi một bậc.
_req_box  = d.tables[0]._element     # hộp "YÊU CẦU"
_grading  = d.tables[5]._element     # bảng tiêu chí chấm điểm
_fig_tbl  = d.tables[1]._element     # bảng "HÌNH 1" — bỏ luôn, ảnh đặt ở đoạn thường
drop(_req_box)
drop(_grading)
drop(_fig_tbl)
for para in list(d.paragraphs):
    t = para.text.strip()
    if t.startswith('MỘT SỐ TIÊU CHÍ CHẤM ĐIỂM') or t.startswith('Có thể xem Mục IV'):
        drop(para._element)

# Chèn hình 1 vào một đoạn thường ngay TRƯỚC dòng chú thích.
# Không đặt trong bảng: ô bảng của mẫu có bề rộng cố định hẹp hơn vùng chữ nên
# ảnh bị cắt mất phần bên phải (đúng chỗ có hai khối IP).
from docx.oxml.ns import qn
import copy as _copy
_cap = None
for _p in d.paragraphs:
    if _p.text.strip().startswith('Hình 1.'):
        _cap = _p
        break
_newel = _copy.deepcopy(_cap._element)
_cap._element.addprevious(_newel)
from docx.text.paragraph import Paragraph as _Par
_imgp = _Par(_newel, _cap._parent)
for _r in _imgp.runs:
    _r._element.getparent().remove(_r._element)
_imgp.alignment = WD_ALIGN_PARAGRAPH.CENTER
_imgp.add_run().add_picture(FIG, width=Cm(16.8))

# bỏ ngắt trang và đoạn rỗng
for para in list(d.paragraphs):
    for br in para._element.findall('.//' + qn('w:br')):
        if br.get(qn('w:type')) == 'page':
            br.getparent().remove(br)
for para in list(d.paragraphs):
    if not para.text.strip() and not para._element.findall('.//' + qn('w:drawing')):
        drop(para._element)

# Khổ A4 và lề hẹp — mẫu gốc là Letter, quy định cuộc thi là A4 tối đa 5 trang
for sec in d.sections:
    sec.page_width   = Cm(21.0)
    sec.page_height  = Cm(29.7)
    sec.left_margin  = Cm(2.0)
    sec.right_margin = Cm(2.0)
    sec.top_margin   = Cm(1.6)
    sec.bottom_margin = Cm(1.6)

for para in d.paragraphs:
    pf = para.paragraph_format
    pf.space_before = Pt(0)
    pf.space_after = Pt(2)
    pf.line_spacing = 1.0

d.save(OUT)
print('da ghi', OUT)
