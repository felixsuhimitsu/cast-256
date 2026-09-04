# Automation Makefile for FPGA Crypto Transceiver (Tang Nano 9K)
# Target Device: Gowin GW1NR-LV9QN88PC6/I5

SIM_DIR    = build/sim
SYNTH_DIR  = build/synth

IVERILOG   = iverilog
VVP        = vvp
FLAGS      = -Wall -g2005-sv -I rtl/core/aes256 -I rtl/core/sha256 -I rtl/framing -I rtl/comm -I rtl

.PHONY: all lint sim sim-aes sim-sha sim-top synth-oss flash clean

all: lint sim

lint:
	@mkdir -p $(SIM_DIR)
	@echo "[LINT] Checking Verilog syntax with iverilog..."
	@if [ -f rtl/top_crypto_transceiver.v ]; then \
		$(IVERILOG) $(FLAGS) -t null rtl/core/aes256/*.v rtl/core/sha256/*.v rtl/framing/*.v rtl/comm/*.v rtl/top_crypto_transceiver.v; \
	else \
		echo "[LINT] RTL files pending Phase 2 generation."; \
	fi

sim: sim-aes sim-sha sim-top

sim-aes:
	@mkdir -p $(SIM_DIR)
	@echo "[SIM] Compiling and running AES-256 Canright testbench..."
	@if [ -f sim/tb_aes256_canright.v ]; then \
		$(IVERILOG) $(FLAGS) -o $(SIM_DIR)/tb_aes256.vvp sim/tb_aes256_canright.v rtl/core/aes256/*.v && \
		$(VVP) $(SIM_DIR)/tb_aes256.vvp; \
	else \
		echo "[SIM] sim/tb_aes256_canright.v not yet created."; \
	fi

sim-sha:
	@mkdir -p $(SIM_DIR)
	@echo "[SIM] Compiling and running SHA-256 testbench..."
	@if [ -f sim/tb_sha256_core.v ]; then \
		$(IVERILOG) $(FLAGS) -o $(SIM_DIR)/tb_sha256.vvp sim/tb_sha256_core.v rtl/core/sha256/*.v && \
		$(VVP) $(SIM_DIR)/tb_sha256.vvp; \
	else \
		echo "[SIM] sim/tb_sha256_core.v not yet created."; \
	fi

sim-top:
	@mkdir -p $(SIM_DIR)
	@echo "[SIM] Compiling and running full loopback transceiver testbench..."
	@if [ -f sim/tb_transceiver_top.v ]; then \
		$(IVERILOG) $(FLAGS) -o $(SIM_DIR)/tb_top.vvp sim/tb_transceiver_top.v rtl/core/aes256/*.v rtl/core/sha256/*.v rtl/framing/*.v rtl/comm/*.v rtl/*.v && \
		$(VVP) $(SIM_DIR)/tb_top.vvp; \
	else \
		echo "[SIM] sim/tb_transceiver_top.v not yet created."; \
	fi

synth-oss:
	@echo "[SYNTH] Running open-source synthesis flow..."
	@./scripts/build_yosys.sh

flash:
	@echo "[FLASH] Programming Tang Nano 9K via openFPGALoader..."
	@./scripts/flash_openfpgaloader.sh

clean:
	@echo "[CLEAN] Removing build directories..."
	@rm -rf $(SIM_DIR) $(SYNTH_DIR)
