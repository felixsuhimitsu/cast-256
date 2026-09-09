#!/usr/bin/env python3
"""
scripts/area.py — Đọc log yosys và in số tài nguyên của MỘT module.

Vì sao cần script này thay vì `grep | awk`:
    Log của yosys in bảng thống kê HAI LẦN — một lần cho module, một lần cho
    "design hierarchy". Cộng bằng grep/awk thô sẽ ra số GẤP ĐÔI. Lỗi này đã
    xảy ra thật: SHA IP báo 3322 LUT4 (vượt ngưỡng 2000) trong khi số thật là
    1661 (đạt). Một gate cho số sai còn tệ hơn không có gate.

Dùng:  /usr/bin/python3 scripts/area.py <file.log> <ten_module> [nguong_lut4]
"""
import re
import sys


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    logfile, module = sys.argv[1], sys.argv[2]
    limit = int(sys.argv[3]) if len(sys.argv) > 3 else None

    txt = open(logfile, encoding="utf-8", errors="replace").read()
    marker = f"=== {module} ==="
    if marker not in txt:
        sys.exit(f"[ERROR] khong thay '{marker}' trong {logfile}")

    # CHỈ lấy khối đầu tiên, dừng trước "=== design hierarchy ==="
    blk = txt.split(marker, 1)[1]
    for stop in ("=== design hierarchy ===", "\n2.5", "\nEnd of script"):
        if stop in blk:
            blk = blk.split(stop, 1)[0]

    cells = re.findall(r"^\s+(\d+)\s+(\S+)\s*$", blk, re.M)

    def total(pred):
        return sum(int(n) for n, c in cells if pred(c))

    lut = total(lambda c: c.startswith("LUT"))
    dff = total(lambda c: c.startswith("DFF"))
    alu = total(lambda c: c.startswith("ALU"))
    ram = total(lambda c: "BSRAM" in c or c.startswith(("SDP", "DPB", "SP")))

    print(f"  module {module}")
    print(f"    LUT4  {lut:5d}   (moi LUT1/2/3/4 chiem mot slot LUT4 tren Gowin)")
    print(f"    DFF   {dff:5d}")
    print(f"    ALU   {alu:5d}")
    print(f"    BSRAM {ram:5d}")

    if limit is not None:
        pct = 100.0 * lut / limit
        if lut <= limit:
            print(f"    GATE  DAT  ({lut} <= {limit}, dung {pct:.0f}% ngan sach)")
        else:
            print(f"    GATE  VUOT ({lut} > {limit}, {pct:.0f}% ngan sach)")
            sys.exit(1)


if __name__ == "__main__":
    main()
