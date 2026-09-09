#!/usr/bin/env bash
#=============================================================================
# scripts/check_layering.sh
# Cưỡng chế ràng buộc phụ thuộc tầng ở docs/02-module-map/MODULE_MAP.md §4.
#
#   1. ip/       KHÔNG được biết gì về protocol/, io/, fabric/
#   2. protocol/ KHÔNG được instantiate trực tiếp module trong ip/
#   3. io/       không phụ thuộc tầng nào khác
#   4. chỉ top_secure_link.v được tham chiếu config/keys.vh
#
# Đây là thứ biến "hai khối mật mã" thành "hai IP tích hợp được" — nếu vi phạm,
# đề tài mất giá trị cốt lõi. Vì vậy nó là gate tự động, không phải quy ước miệng.
#=============================================================================
set -uo pipefail

fail=0

# Thu thập tên module của từng tầng
mods_of() {   # $1 = thư mục
    find "$1" -name '*.v' 2>/dev/null -exec grep -hoE '^\s*module\s+[a-zA-Z_][a-zA-Z0-9_]*' {} \; \
        | awk '{print $2}' | sort -u
}

IP_MODS=$(mods_of rtl/ip)
PROTO_MODS=$(mods_of rtl/protocol)
IO_MODS=$(mods_of rtl/io)
FAB_MODS=$(mods_of rtl/fabric)

# Tìm các module được instantiate trong một thư mục.
# Bắt mẫu:  <tên_module> [#(...)] <tên_instance> (
insts_in() {  # $1 = thư mục
    find "$1" -name '*.v' 2>/dev/null -print0 \
      | xargs -0 -r grep -hoE '^\s{2,}[a-zA-Z_][a-zA-Z0-9_]*\s+(#\s*\()?' 2>/dev/null \
      | awk '{print $1}' | sort -u
}

check_forbidden() {   # $1 = tầng đang xét, $2 = danh sách module cấm, $3 = tên tầng cấm
    local dir="$1" forbidden="$2" label="$3"
    [ -z "$forbidden" ] && return 0
    local used
    used=$(insts_in "$dir")
    for m in $forbidden; do
        if echo "$used" | grep -qx "$m"; then
            echo "  [LAYER-FAIL] $dir dùng module '$m' của tầng $label"
            fail=1
        fi
    done
}

echo "  [LAYER] kiểm ràng buộc phụ thuộc tầng..."

# Quy tắc 1: ip/ không được dùng gì của protocol/, io/, fabric/
check_forbidden rtl/ip "$PROTO_MODS" "protocol/"
check_forbidden rtl/ip "$IO_MODS"    "io/"
check_forbidden rtl/ip "$FAB_MODS"   "fabric/"

# Quy tắc 2: protocol/ không được instantiate trực tiếp module trong ip/
check_forbidden rtl/protocol "$IP_MODS" "ip/ (phải đi qua fabric/)"

# Quy tắc 3: io/ không phụ thuộc tầng nào khác
check_forbidden rtl/io "$IP_MODS"    "ip/"
check_forbidden rtl/io "$PROTO_MODS" "protocol/"
check_forbidden rtl/io "$FAB_MODS"   "fabric/"

# Quy tắc 4: chỉ top_secure_link.v được tham chiếu config/keys.vh
if [ -f rtl/config/keys.vh ]; then
    offenders=$(grep -rl 'keys\.vh' rtl --include='*.v' 2>/dev/null \
                | grep -v '^rtl/top_secure_link\.v$' || true)
    if [ -n "$offenders" ]; then
        echo "  [LAYER-FAIL] chỉ top_secure_link.v được include keys.vh, nhưng thấy:"
        echo "$offenders" | sed 's/^/                /'
        fail=1
    fi
fi

if [ "$fail" -eq 0 ]; then
    echo "  [LAYER-OK] không vi phạm ràng buộc phụ thuộc tầng"
else
    echo "  [LAYER] xem docs/02-module-map/MODULE_MAP.md §4"
fi
exit $fail
