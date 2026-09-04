#!/usr/bin/env bash
set -euo pipefail

BITSTREAM="build/synth/crypto_transceiver.fs"

if [ ! -f "${BITSTREAM}" ]; then
    echo "Error: Bitstream ${BITSTREAM} not found. Run 'make synth-oss' first."
    exit 1
fi

echo "Flashing ${BITSTREAM} to Tang Nano 9K via openFPGALoader..."
openFPGALoader -b tangnano9k "${BITSTREAM}"
