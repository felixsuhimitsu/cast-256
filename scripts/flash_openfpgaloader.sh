#!/usr/bin/env bash
set -euo pipefail

BITSTREAM="build/synth/crypto_transceiver.fs"
BOARD="tangnano9k"

usage() {
    echo "Usage: $0 [--sram | --flash]"
    echo "  --sram   Program volatile SRAM (default, lost on power cycle)"
    echo "  --flash  Program non-volatile flash (survives power cycle)"
    exit 1
}

MODE="sram"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --sram)  MODE="sram";  shift ;;
        --flash) MODE="flash"; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

if [ ! -f "${BITSTREAM}" ]; then
    echo "[ERROR] Bitstream ${BITSTREAM} not found. Run 'bash scripts/build_yosys.sh' first."
    exit 1
fi

SIZE=$(stat -c%s "${BITSTREAM}")
echo "========================================================================"
echo "  Tang Nano 9K Programmer (openFPGALoader)"
echo "  Bitstream : ${BITSTREAM} (${SIZE} bytes)"
echo "  Mode      : ${MODE}"
echo "========================================================================"

if [ "${MODE}" = "flash" ]; then
    echo "[1/1] Writing to external flash (non-volatile)..."
    openFPGALoader -b "${BOARD}" -f "${BITSTREAM}"
else
    echo "[1/1] Programming SRAM (volatile)..."
    openFPGALoader -b "${BOARD}" "${BITSTREAM}"
fi

echo ""
echo "[DONE] Bitstream loaded successfully. Device should be active."
echo "  LED D1 (Pin 10) = TX Active"
echo "  LED D2 (Pin 11) = RX Auth Pass"
echo "  LED D3 (Pin 13) = MAC Tamper Alert"
