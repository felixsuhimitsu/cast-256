#=============================================================================
# Makefile — Thiết kế và tích hợp IP mã hóa AES-256 và SHA-256
#            cho giao thức truyền và nhận dữ liệu
#
# Đội Hủ Tiếu · Trường ĐH CNTT&TT — ĐH Thái Nguyên
# Thiết bị: Sipeed Tang Nano 9K (GW1NR-LV9QN88PC6/I5), 27.0 MHz
#
# Toolchain (mã nguồn mở): Yosys + nextpnr-himbaechel + Project Apicula
#   Nạp trước khi dùng:  source ~/tools/oss-cad-suite/environment
#
# LƯU Ý: sau khi source oss-cad-suite, `python3` bị che bởi bản riêng KHÔNG có
# pyserial. Các target chạm phần cứng vì vậy gọi /usr/bin/python3 tường minh.
# Xem docs/07-test/TEST_PLAN.md §6.
#=============================================================================

SHELL      := /bin/bash
BUILD      := build
SYNTH_DIR  := $(BUILD)/synth
SIM_DIR    := $(BUILD)/sim
EVIDENCE   := docs/10-devbook/evidence

DEVICE     := GW1NR-LV9QN88PC6/I5
FAMILY     := GW1N-9C
TOP        := top_secure_link
CST        := constraints/tangnano9k.cst
SDC        := constraints/timing.sdc

# Cổng UART của FT2232. ttyUSB0 là kênh JTAG — KHÔNG phải UART.
PORT       ?= /dev/ttyUSB1
SYSPY      := /usr/bin/python3

IVFLAGS    := -g2005 -Wall -Wno-timescale -I sim/lib
RTL_ALL    := $(shell find rtl -name '*.v' 2>/dev/null)
RTL_IP     := $(shell find rtl/ip -name '*.v' 2>/dev/null)
RTL_AES    := $(shell find rtl/ip/aes256 -name '*.v' 2>/dev/null)
RTL_SHA    := $(shell find rtl/ip/sha256 -name '*.v' 2>/dev/null)
RTL_IO     := $(shell find rtl/io -name '*.v' 2>/dev/null)
RTL_FAB    := $(shell find rtl/fabric -name '*.v' 2>/dev/null)
RTL_PROTO  := $(shell find rtl/protocol -name '*.v' 2>/dev/null)

.PHONY: help lint sim sim-aes sim-sha sim-uart sim-fabric sim-top \
        synth synth-aes synth-sha flash test bench clean dirs

#-----------------------------------------------------------------------------
help:
	@echo ""
	@echo "  Đề tài: Thiết kế và tích hợp IP AES-256 và SHA-256"
	@echo "  ─────────────────────────────────────────────────────────────"
	@echo "  Trước tiên:  source ~/tools/oss-cad-suite/environment"
	@echo ""
	@echo "  KIỂM TRA TĨNH"
	@echo "    make lint          Cú pháp + latch + header REQ-ID + phụ thuộc tầng"
	@echo ""
	@echo "  MÔ PHỎNG (L1/L2 — không thay được test phần cứng, xem REQ-V-03)"
	@echo "    make sim-aes       IP AES-256, vector FIPS 197 + SP 800-38A"
	@echo "    make sim-sha       IP SHA-256, vector FIPS 180-4"
	@echo "    make sim-uart      Lớp vật lý UART"
	@echo "    make sim-fabric    Fabric CSI, loại trừ tương hỗ"
	@echo "    make sim-top       Toàn hệ, các kịch bản lỗi"
	@echo "    make sim           Tất cả"
	@echo ""
	@echo "  TỔNG HỢP"
	@echo "    make synth-aes     Tổng hợp riêng IP AES  (gate REQ-R-03: <= 2200 LUT4)"
	@echo "    make synth-sha     Tổng hợp riêng IP SHA  (gate REQ-R-04: <= 1800 LUT4)"
	@echo "    make synth         Toàn thiết kế + P&R    (gate REQ-R-01/02, REQ-P-01)"
	@echo ""
	@echo "  PHẦN CỨNG (L3 — chạy tiền cảnh, KHÔNG chạy nền)"
	@echo "    make flash         Nạp bitstream"
	@echo "    make test          Echo một khung           (TC-601)"
	@echo "    make bench         100 khung, đo hiệu năng  (TC-602)"
	@echo ""
	@echo "    Cổng UART hiện tại: PORT=$(PORT)"
	@echo ""

dirs:
	@mkdir -p $(SYNTH_DIR) $(SIM_DIR) $(EVIDENCE)/synth $(EVIDENCE)/sim $(EVIDENCE)/hw

#-----------------------------------------------------------------------------
# LINT — gate của mọi WP (Definition of Done mục D2)
#-----------------------------------------------------------------------------
lint: dirs
	@echo "[lint 1/3] Cú pháp và cảnh báo (iverilog)..."
	@if [ -n "$(RTL_ALL)" ]; then \
	    iverilog $(IVFLAGS) -t null $(RTL_ALL) 2>&1 | tee $(SIM_DIR)/lint.log; \
	    if grep -qi 'latch\|error' $(SIM_DIR)/lint.log; then \
	        echo "  [LINT-FAIL] có latch hoặc lỗi — xem $(SIM_DIR)/lint.log"; exit 1; \
	    fi; \
	    echo "  [LINT-OK] không latch, không lỗi cú pháp"; \
	else \
	    echo "  [lint] chưa có file RTL — bỏ qua"; \
	fi
	@echo "[lint 2/3] Header REQ-ID (REQ-N-02)..."
	@bash scripts/check_headers.sh
	@echo "[lint 3/3] Ràng buộc phụ thuộc tầng (MODULE_MAP §4)..."
	@bash scripts/check_layering.sh
	@echo "[lint] SẠCH"

#-----------------------------------------------------------------------------
# MÔ PHỎNG
#-----------------------------------------------------------------------------
define run_sim
	@echo "=== $(1) ==="
	@mkdir -p $(SIM_DIR)
	@iverilog $(IVFLAGS) -o $(SIM_DIR)/$(1).vvp $(2) $(3)
	@cd $(SIM_DIR) && vvp $(1).vvp 2>&1 | tee $(1).log; \
	  exit $${PIPESTATUS[0]}
	@cp $(SIM_DIR)/$(1).log $(EVIDENCE)/sim/ 2>/dev/null || true
endef

sim-sha: dirs
	$(call run_sim,tb_sha256_ip,sim/unit/tb_sha256_ip.v,$(RTL_SHA) sim/lib/csi_checker.v)

sim-aes: dirs
	$(call run_sim,tb_aes256_ip,sim/unit/tb_aes256_ip.v,$(RTL_AES) sim/lib/csi_checker.v)

sim-uart: dirs
	$(call run_sim,tb_uart,sim/unit/tb_uart.v,$(RTL_IO))

sim-fabric: dirs
	$(call run_sim,tb_fabric,sim/integ/tb_fabric.v,$(RTL_FAB) sim/lib/csi_checker.v)

sim-top: dirs
	$(call run_sim,tb_top,sim/integ/tb_top.v,$(RTL_ALL) sim/lib/csi_checker.v)

sim: sim-uart sim-sha sim-aes sim-fabric sim-top
	@echo "[sim] TẤT CẢ PASS"

#-----------------------------------------------------------------------------
# TỔNG HỢP RIÊNG TỪNG IP — gate ngân sách diện tích (WP-02)
#-----------------------------------------------------------------------------
# -nowidelut là BẮT BUỘC: trên Gowin, MUX2_LUT5..8 được dựng TỪ chính LUT4,
# nên bỏ cờ này làm số LUT4 tăng vọt. Đã đo: 7359 -> 9248. Xem ADR-0004.
YOSYS_FLAGS := -no-rw-check -nowidelut

define synth_ip
	@echo "=== tổng hợp riêng: $(1) (ngân sách $(3) LUT4) ==="
	@mkdir -p $(SYNTH_DIR)
	@yosys -p "read_verilog $(2); \
	           synth_gowin $(YOSYS_FLAGS) -top $(1) -json $(SYNTH_DIR)/$(1).json" \
	       2>&1 | tee $(SYNTH_DIR)/$(1)_yosys.log
	@echo "--- số LUT4 thật ---"
	@grep -E 'LUT[0-9]|DFF' $(SYNTH_DIR)/$(1)_yosys.log | tail -20
	@cp $(SYNTH_DIR)/$(1)_yosys.log $(EVIDENCE)/synth/ 2>/dev/null || true
endef

synth-aes: dirs
	$(call synth_ip,aes256_ctr_ip,$(RTL_AES),2200)

synth-sha: dirs
	$(call synth_ip,sha256_ip,$(RTL_SHA),1800)

#-----------------------------------------------------------------------------
# TỔNG HỢP TOÀN THIẾT KẾ
#-----------------------------------------------------------------------------
synth: dirs
	@echo "[1/3] Yosys..."
	@yosys -p "read_verilog $(RTL_ALL); \
	           synth_gowin $(YOSYS_FLAGS) -top $(TOP) -json $(SYNTH_DIR)/$(TOP).json" \
	       2>&1 | tee $(SYNTH_DIR)/yosys.log
	@echo "[2/3] nextpnr-himbaechel..."
	@# nextpnr ghi TOÀN BỘ ra stderr — thiếu 2>&1 thì log rỗng. Đã mất thời gian vì lỗi này.
	@nextpnr-himbaechel \
	    --json $(SYNTH_DIR)/$(TOP).json \
	    --write $(SYNTH_DIR)/$(TOP)_pnr.json \
	    --device $(DEVICE) \
	    --vopt family=$(FAMILY) \
	    --vopt cst=$(CST) \
	    $$( [ -f $(SDC) ] && echo "--sdc $(SDC)" ) \
	    2>&1 | tee $(SYNTH_DIR)/nextpnr.log
	@echo "[3/3] gowin_pack..."
	@gowin_pack -d $(FAMILY) -o $(SYNTH_DIR)/$(TOP).fs $(SYNTH_DIR)/$(TOP)_pnr.json
	@cp $(SYNTH_DIR)/nextpnr.log $(EVIDENCE)/synth/$$(date +%Y%m%d-%H%M)-$$(git rev-parse --short HEAD).log
	@echo ""
	@echo "=== TÀI NGUYÊN (gate REQ-R-01: LUT4 <= 7776, REQ-R-02: DFF <= 5184) ==="
	@grep -E 'LUT4:|DFF:|BSRAM:|ALU:|Max frequency' $(SYNTH_DIR)/nextpnr.log || true
	@echo ""
	@echo "Bitstream: $(SYNTH_DIR)/$(TOP).fs"

#-----------------------------------------------------------------------------
# PHẦN CỨNG
#-----------------------------------------------------------------------------
flash:
	@echo "[flash] nạp $(SYNTH_DIR)/$(TOP).fs (chạy tiền cảnh)..."
	@openFPGALoader -b tangnano9k $(SYNTH_DIR)/$(TOP).fs

test:
	@$(SYSPY) scripts/hw_test.py --port $(PORT) --mode echo

bench:
	@$(SYSPY) scripts/hw_test.py --port $(PORT) --mode bench --frames 100 \
	    | tee $(EVIDENCE)/hw/bench-$$(date +%Y%m%d-%H%M).log

clean:
	@rm -rf $(BUILD)
	@echo "[clean] đã xóa $(BUILD)/"
