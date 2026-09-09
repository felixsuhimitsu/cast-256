#!/usr/bin/env python3
"""
scripts/gen_sbox_basis.py
=========================
Tìm và kiểm chứng phép đẳng cấu (isomorphism) giữa trường AES GF(2^8) và trường
tháp composite GF(((2^2)^2)^2), rồi sinh ra:

  1. Hai ma trận đổi cơ sở (thuận + nghịch, đã gộp sẵn biến đổi affine)
  2. sim/vectors/sbox_ref.hex  — 256 giá trị S-Box chuẩn FIPS 197, dùng làm
     nguồn sự thật cho TC-100

REQ: REQ-F-04  ·  ADR: ADR-0001  ·  Ngày: 2026-09-09

VÌ SAO CẦN SCRIPT NÀY
---------------------
Rủi ro RSK-03: một phép biến đổi cơ sở sai làm S-Box vẫn là song ánh nhưng sai
giá trị — vector AES sẽ fail mà không có manh mối nào chỉ về S-Box. Vì vậy phép
đẳng cấu được tìm và **kiểm đủ 256 giá trị bằng Python trước khi viết một dòng
Verilog nào**. Verilog chỉ chép lại các hằng số đã được chứng minh đúng ở đây.

Chạy:  /usr/bin/python3 scripts/gen_sbox_basis.py
"""

AES_POLY = 0x11B          # x^8 + x^4 + x^3 + x + 1


# ────────────────────────────────────────────────────────────────────────────
# Trường AES GF(2^8) chuẩn
# ────────────────────────────────────────────────────────────────────────────
def aes_mul(a, b):
    r = 0
    while b:
        if b & 1:
            r ^= a
        b >>= 1
        a <<= 1
        if a & 0x100:
            a ^= AES_POLY
    return r


def aes_inv(a):
    if a == 0:
        return 0
    for x in range(1, 256):
        if aes_mul(a, x) == 1:
            return x
    raise AssertionError("khong tim thay nghich dao")


def aes_sbox_table():
    """S-Box chuẩn FIPS 197: nghịch đảo trong GF(2^8) rồi biến đổi affine."""
    out = []
    for a in range(256):
        i = aes_inv(a)
        s = i
        for _ in range(4):
            i = ((i << 1) | (i >> 7)) & 0xFF
            s ^= i
        out.append(s ^ 0x63)
    return out


# ────────────────────────────────────────────────────────────────────────────
# Trường tháp GF(2^2) ⊂ GF(2^4) ⊂ GF(2^8)
#   GF(2^2) = GF(2)[w]/(w^2 + w + 1)
#   GF(2^4) = GF(2^2)[z]/(z^2 + z + PHI)
#   GF(2^8) = GF(2^4)[y]/(y^2 + y + LAM)
# Các công thức dưới đây là ĐÚNG THỨ sẽ được chép sang Verilog.
# ────────────────────────────────────────────────────────────────────────────
def g2_mul(a, b):
    a1, a0 = (a >> 1) & 1, a & 1
    b1, b0 = (b >> 1) & 1, b & 1
    return (((a1 & b1) ^ (a1 & b0) ^ (a0 & b1)) << 1) | ((a1 & b1) ^ (a0 & b0))


def g2_sq(a):
    a1, a0 = (a >> 1) & 1, a & 1
    return (a1 << 1) | (a1 ^ a0)


def g2_inv(a):
    return g2_sq(a)            # trong GF(4): x^3 = 1 nên x^-1 = x^2


def g4_mul(a, b, PHI):
    a1, a0 = (a >> 2) & 3, a & 3
    b1, b0 = (b >> 2) & 3, b & 3
    hi = g2_mul(a1, b1) ^ g2_mul(a1, b0) ^ g2_mul(a0, b1)
    lo = g2_mul(PHI, g2_mul(a1, b1)) ^ g2_mul(a0, b0)
    return (hi << 2) | lo


def g4_sq(a, PHI):
    a1, a0 = (a >> 2) & 3, a & 3
    s1 = g2_sq(a1)
    return (s1 << 2) | (g2_mul(PHI, s1) ^ g2_sq(a0))


def g4_inv(a, PHI):
    a1, a0 = (a >> 2) & 3, a & 3
    d = g2_mul(PHI, g2_sq(a1)) ^ g2_mul(a0, a1 ^ a0)
    di = g2_inv(d)
    return (g2_mul(a1, di) << 2) | g2_mul(a1 ^ a0, di)


def g8_mul(a, b, PHI, LAM):
    a1, a0 = (a >> 4) & 15, a & 15
    b1, b0 = (b >> 4) & 15, b & 15
    hi = g4_mul(a1, b1, PHI) ^ g4_mul(a1, b0, PHI) ^ g4_mul(a0, b1, PHI)
    lo = g4_mul(LAM, g4_mul(a1, b1, PHI), PHI) ^ g4_mul(a0, b0, PHI)
    return (hi << 4) | lo


def g8_inv(a, PHI, LAM):
    a1, a0 = (a >> 4) & 15, a & 15
    d = g4_mul(LAM, g4_sq(a1, PHI), PHI) ^ g4_mul(a0, a1 ^ a0, PHI)
    di = g4_inv(d, PHI)
    return (g4_mul(a1, di, PHI) << 4) | g4_mul(a1 ^ a0, di, PHI)


# ────────────────────────────────────────────────────────────────────────────
# Tìm phép đẳng cấu
# ────────────────────────────────────────────────────────────────────────────
def g8_pow(a, n, PHI, LAM):
    r = 1
    for _ in range(n):
        r = g8_mul(r, a, PHI, LAM)
    return r


def is_aes_root(t, PHI, LAM):
    """t có phải nghiệm của x^8+x^4+x^3+x+1 trong trường tháp không."""
    acc = 0
    for e in (8, 4, 3, 1, 0):
        acc ^= g8_pow(t, e, PHI, LAM)
    return acc == 0


def build_matrix(t, PHI, LAM):
    """Cột i của ma trận = ảnh của x^i (cơ sở AES) trong trường tháp."""
    return [g8_pow(t, i, PHI, LAM) for i in range(8)]


def apply_matrix(cols, a):
    r = 0
    for i in range(8):
        if (a >> i) & 1:
            r ^= cols[i]
    return r


def invert_matrix(cols):
    """Nghịch đảo ma trận 8x8 trên GF(2) bằng khử Gauss."""
    m = [cols[i] | (1 << (8 + i)) for i in range(8)]   # [A | I], theo cột
    # chuyển sang thao tác theo hàng cho dễ
    rows = []
    for r in range(8):
        v = 0
        for c in range(8):
            if (cols[c] >> r) & 1:
                v |= 1 << c
        rows.append(v | (1 << (8 + r)))
    for c in range(8):
        p = next((r for r in range(c, 8) if (rows[r] >> c) & 1), None)
        if p is None:
            return None
        rows[c], rows[p] = rows[p], rows[c]
        for r in range(8):
            if r != c and (rows[r] >> c) & 1:
                rows[r] ^= rows[c]
    inv_cols = [0] * 8
    for r in range(8):
        v = rows[r] >> 8
        for c in range(8):
            if (v >> c) & 1:
                inv_cols[c] |= 1 << r
    return inv_cols


def affine(x):
    s = x
    for _ in range(4):
        x = ((x << 1) | (x >> 7)) & 0xFF
        s ^= x
    return s ^ 0x63


def main():
    ref = aes_sbox_table()
    print("Tim phep dang cau AES GF(2^8) -> GF(((2^2)^2)^2)...")

    found = None
    for PHI in (1, 2, 3):
        for LAM in range(1, 16):
            for t in range(2, 256):
                if not is_aes_root(t, PHI, LAM):
                    continue
                fwd = build_matrix(t, PHI, LAM)
                inv = invert_matrix(fwd)
                if inv is None:
                    continue
                # Kiem tra DAY DU 256 gia tri
                ok = True
                for a in range(256):
                    v = apply_matrix(fwd, a)          # sang truong thap
                    v = g8_inv(v, PHI, LAM)           # nghich dao o truong thap
                    v = apply_matrix(inv, v)          # ve truong AES
                    if affine(v) != ref[a]:
                        ok = False
                        break
                if ok:
                    found = (PHI, LAM, t, fwd, inv)
                    break
            if found:
                break
        if found:
            break

    if not found:
        raise SystemExit("KHONG tim duoc phep dang cau — dung lai")

    PHI, LAM, t, fwd, inv = found
    print(f"  PHI = {PHI}  LAM = {LAM}  nghiem t = 0x{t:02X}")
    print(f"  KIEM CHUNG: 256/256 gia tri khop S-Box FIPS 197  [PASS]")

    # Gop bien doi affine vao ma tran nghich, de Verilog chi can 2 ma tran
    # thay vi 2 ma tran + 1 khoi affine rieng.
    aff_lin = [affine(1 << i) ^ 0x63 for i in range(8)]      # phan tuyen tinh
    comb = []
    for i in range(8):
        comb.append(apply_matrix(aff_lin, inv[i]))

    # Kiem lai voi ma tran da gop
    for a in range(256):
        v = apply_matrix(fwd, a)
        v = g8_inv(v, PHI, LAM)
        v = apply_matrix(comb, v) ^ 0x63
        assert v == ref[a], f"gop affine sai tai a=0x{a:02X}"
    print("  KIEM CHUNG: ma tran da gop affine cung khop 256/256  [PASS]")

    print("\n--- Hang so de chep sang Verilog ---")
    print(f"  localparam PHI = 2'd{PHI};")
    print(f"  localparam LAM = 4'd{LAM};")
    print("  // MAP_FWD: cot i = anh cua bit i (AES -> thap)")
    for i in range(8):
        print(f"  //   fwd[{i}] = 8'h{fwd[i]:02X}")
    print("  // MAP_INV_AFF: cot i (thap -> AES, da gop phan tuyen tinh affine)")
    for i in range(8):
        print(f"  //   inv[{i}] = 8'h{comb[i]:02X}")

    with open("sim/vectors/sbox_ref.hex", "w") as f:
        for i in range(0, 256, 16):
            f.write(" ".join(f"{v:02x}" for v in ref[i:i + 16]) + "\n")
    print("\n  Da ghi sim/vectors/sbox_ref.hex (256 gia tri, nguon: FIPS 197 Hinh 7)")

    with open("build/sbox_params.txt", "w") as f:
        f.write(f"PHI {PHI}\nLAM {LAM}\nT {t}\n")
        f.write("FWD " + " ".join(f"{v:02X}" for v in fwd) + "\n")
        f.write("INVAFF " + " ".join(f"{v:02X}" for v in comb) + "\n")
    print("  Da ghi build/sbox_params.txt")


if __name__ == "__main__":
    main()
