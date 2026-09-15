import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, Rectangle, FancyArrowPatch

# Bố cục băng ngang + CỘT LỀ TRÁI dành riêng cho nhãn tầng.
# Mọi khối nằm bên phải x = XB nên nhãn không bao giờ đè lên khối.
# Mọi mũi tên chỉ đi thẳng đứng hoặc thẳng ngang -> không có đường chéo,
# không thể chồng chéo.
fig, ax = plt.subplots(figsize=(8.9, 6.4))
ax.set_xlim(0, 100)
ax.set_ylim(0, 100)
ax.axis("off")

XL, XB, XR = 3.0, 21.0, 96.0       # mép trái băng · mép trái khối · mép phải

C_IO    = ("#FDF6E8", "#B7791F")
C_PROTO = ("#EAF6EF", "#22803F")
C_FAB   = ("#FCEDEA", "#C0392B")
C_IP    = ("#E9F1FB", "#1F4E79")
C_HOST  = ("#F4F4F4", "#6E6E6E")


def band(y0, y1, label, col):
    fc, ec = col
    ax.add_patch(Rectangle((XL, y0), XR - XL, y1 - y0, facecolor=fc,
                           edgecolor=ec, linewidth=1.2, zorder=1))
    ax.text((XL + XB) / 2 - 0.5, (y0 + y1) / 2, label, fontsize=8.4,
            weight="bold", color=ec, ha="center", va="center",
            linespacing=1.6, zorder=3)


def box(x0, x1, y0, y1, txt, col, fs=7.9, bold=False, lw=1.3):
    _, ec = col
    ax.add_patch(FancyBboxPatch((x0, y0), x1 - x0, y1 - y0,
                                boxstyle="round,pad=0.3,rounding_size=0.9",
                                facecolor="white", edgecolor=ec,
                                linewidth=lw, zorder=2))
    ax.text((x0 + x1) / 2, (y0 + y1) / 2, txt, ha="center", va="center",
            fontsize=fs, weight=("bold" if bold else "normal"),
            linespacing=1.45, zorder=3)


def varrow(x, y_from, y_to, label=None, side="right", label_y=None):
    ax.add_patch(FancyArrowPatch((x, y_from), (x, y_to), arrowstyle="-|>",
                                 mutation_scale=11, color="#333", lw=1.5,
                                 shrinkA=0, shrinkB=0, zorder=5))
    if label:
        dx = 1.3 if side == "right" else -1.3
        ly = label_y if label_y is not None else (y_from + y_to) / 2
        ax.text(x + dx, ly, label, fontsize=6.9,
                color="#333", ha=("left" if side == "right" else "right"),
                va="center", zorder=5)


def harrow(x_from, x_to, y):
    ax.add_patch(FancyArrowPatch((x_from, y), (x_to, y), arrowstyle="-|>",
                                 mutation_scale=11, color="#333", lw=1.5,
                                 shrinkA=0, shrinkB=0, zorder=5))


# ───────────────────────────── tiêu đề ─────────────────────────────
ax.text(50, 99.5,
        "Sipeed Tang Nano 9K  ·  GW1NR-LV9QN88PC6/I5  ·  một miền xung nhịp 27,0 MHz",
        ha="center", va="top", fontsize=9.2, weight="bold", color="#111")
ax.text(50, 96.2,
        "6664/8640 LUT4 (77%)    3568/6480 DFF (55%)    5/26 BSRAM    F_max 46,85 MHz",
        ha="center", va="top", fontsize=8.0, color="#555")

# ───────────────────────────── HOST ─────────────────────────────
box(30, 70, 85.5, 92.5,
    "HOST (PC)  —  scripts/hw_test.py\nđóng khung  ·  kiểm bản mã và digest",
    C_HOST, fs=8.0)

varrow(38, 85.5, 79.2, "khung gửi", side="left")
varrow(62, 79.2, 85.5, "khung nhận", side="right")
ax.text(50, 82.3, "UART 8-N-1 · 115200 baud", ha="center", va="center",
        fontsize=7.2, color="#777", style="italic", zorder=5)

# ───────────────────────────── tầng io/ ─────────────────────────────
band(67.0, 79.2, "tầng io/\n331 LUT4", C_IO)
box(XB, 55, 69.5, 76.5, "uart_rx\nbiểu quyết 3 điểm", C_IO)
box(60, XR - 1, 69.5, 76.5, "uart_tx  +  baud_gen", C_IO)

varrow(38, 69.5, 60.5)
varrow(80, 60.5, 69.5)

# ─────────────────────────── tầng protocol/ ───────────────────────────
band(35.5, 63.5, "tầng protocol/", C_PROTO)
box(XB, 44, 52.5, 60.5, "frame_rx\nquét preamble A5 5A\nkiểm LEN ∈ [1,512]", C_PROTO, fs=7.5)
box(48, 68, 52.5, 60.5, "frame_buffer\n512 B  ·  1 BSRAM", C_PROTO, fs=7.5)
box(72, XR - 1, 52.5, 60.5, "frame_tx\nđóng khung trả lời", C_PROTO, fs=7.5)
box(XB, 55, 38.5, 46.5, "session_fsm\nđiều phối phiên\nwatchdog 2²⁴", C_PROTO, fs=7.5)
box(60, XR - 1, 38.5, 46.5, "digest_check\nso 32 byte\nthời gian hằng định", C_PROTO, fs=7.5)

harrow(44, 48, 56.5)
harrow(68, 72, 56.5)
varrow(30, 52.5, 46.5)
varrow(80, 46.5, 52.5)

# ──────────────────────────── tầng fabric/ ────────────────────────────
band(17.5, 31.5, "tầng fabric/\n286 LUT4", C_FAB)
box(XB, 55, 19.0, 26.5, "ip_arbiter\ncấp quyền one-hot", C_FAB, fs=7.5)
box(60, XR - 1, 19.0, 26.5, "stream_mux\nđịnh tuyến  ·  chặn IP chưa được cấp", C_FAB, fs=7.5)
ax.text((XB + XR) / 2, 29.3,
        "loại trừ tương hỗ: KHÔNG BAO GIỜ hai IP cùng chiếm đường dữ liệu",
        ha="center", va="center", fontsize=7.6, weight="bold",
        color="#C0392B", zorder=3)

varrow(30, 38.5, 31.8, "yêu cầu IP", side="left", label_y=33.5)
varrow(80, 31.8, 38.5, "kết quả", side="right", label_y=33.5)

# ───────────────────────────── tầng ip/ ─────────────────────────────
band(1.5, 15.5, "tầng ip/\nhai IP,\nMỘT hợp đồng\ngiao diện CSI", C_IP)
box(XB, 55, 3.0, 13.5,
    "IP AES-256-CTR\n2 528 LUT4  ·  32 chu kỳ/khối\nFIPS 197 + NIST SP 800-38A",
    C_IP, fs=7.9, bold=True, lw=1.8)
box(60, XR - 1, 3.0, 13.5,
    "IP SHA-256\n1 661 LUT4  ·  66 chu kỳ/khối\nFIPS 180-4",
    C_IP, fs=7.9, bold=True, lw=1.8)

varrow(38, 19.0, 13.8, "CSI", side="left", label_y=16.6)
varrow(78, 19.0, 13.8, "CSI", side="right", label_y=16.6)

plt.tight_layout(pad=0.25)
plt.savefig("docs/hinh1_kien_truc.png", dpi=200, bbox_inches="tight",
            facecolor="white")
print("ok")
