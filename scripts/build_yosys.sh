#!/usr/bin/env bash
set -euo pipefail

# Build script for Tang Nano 9K (GW1NR-LV9QN88PC6/I5)
# Toolchain: Yosys + nextpnr-himbaechel + Project Apicula

BUILD_DIR="build/synth"
mkdir -p "${BUILD_DIR}"

echo "[1/3] Synthesizing with Yosys..."
yosys -p "
    read_verilog -sv rtl/core/aes256/*.v rtl/core/sha256/*.v rtl/framing/*.v rtl/comm/*.v rtl/top_crypto_transceiver.v;
    synth_gowin -no-rw-check -nowidelut -top top_crypto_transceiver -json ${BUILD_DIR}/crypto_transceiver.json
" | tee "${BUILD_DIR}/yosys.log"

echo "[2/3] Place & Route with nextpnr-himbaechel..."
nextpnr-himbaechel \
    --json "${BUILD_DIR}/crypto_transceiver.json" \
    --write "${BUILD_DIR}/crypto_transceiver_pnr.json" \
    --device GW1NR-LV9QN88PC6/I5 \
    --vopt family=GW1N-9C \
    --vopt cst=constraints/tangnano9k.cst \
    --sdc constraints/timing.sdc \
    --placer-heap-beta 0.98 \
    --placer-heap-timingweight 5 \
    | tee "${BUILD_DIR}/nextpnr.log"

echo "[3/3] Packing bitstream with Project Apicula..."
gowin_pack -d GW1N-9C -o "${BUILD_DIR}/crypto_transceiver.fs" "${BUILD_DIR}/crypto_transceiver_pnr.json"

echo "Build complete: ${BUILD_DIR}/crypto_transceiver.fs"
