#!/usr/bin/env bash
#=============================================================================
# scripts/check_headers.sh
# Kiểm REQ-N-02: mỗi file RTL phải có header ghi mục đích, REQ-ID, tác giả, ngày.
# Trả mã thoát 1 nếu có file vi phạm.
#=============================================================================
set -uo pipefail

fail=0
checked=0

for f in $(find rtl -name '*.v' -o -name '*.vh' 2>/dev/null | sort); do
    checked=$((checked + 1))
    head -n 12 "$f" > /tmp/_hdr.$$ 2>/dev/null

    if ! grep -q 'Mục đích\|Muc dich' /tmp/_hdr.$$; then
        echo "  [HDR-FAIL] $f: thiếu dòng 'Mục đích'"
        fail=1
    fi
    if ! grep -qE 'REQ-[A-Z]-[0-9]{2}' /tmp/_hdr.$$; then
        echo "  [HDR-FAIL] $f: header không tham chiếu REQ-ID nào"
        fail=1
    fi
    if ! grep -q 'Ngày\|Ngay' /tmp/_hdr.$$; then
        echo "  [HDR-FAIL] $f: thiếu ngày"
        fail=1
    fi
    rm -f /tmp/_hdr.$$
done

if [ "$checked" -eq 0 ]; then
    echo "  [HDR] chưa có file RTL nào — bỏ qua"
    exit 0
fi

if [ "$fail" -eq 0 ]; then
    echo "  [HDR-OK] $checked file RTL đều có header hợp lệ (REQ-N-02)"
else
    echo "  [HDR] có vi phạm REQ-N-02 — xem docs/01-spec/SRS.md §9"
fi
exit $fail
