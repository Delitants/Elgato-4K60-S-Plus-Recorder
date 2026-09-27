#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
HELPER="${NDI_HELPER:-build/${ARCH:-arm64}/Elgato Recorder.app/Contents/MacOS/NDISender}"
RUNTIME="${NDI_RUNTIME:-build/${ARCH:-arm64}/Elgato Recorder.app/Contents/Frameworks/libndi.dylib}"
"$HELPER" "$RUNTIME" --probe
if "$HELPER" /nonexistent/libndi.dylib --probe; then echo 'Missing runtime incorrectly accepted'; exit 1; fi
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/elgato-ndi.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
clang++ -std=c++17 -O2 -IHelpers/NDI/include Tests/NDIRateReceiver.cpp -o "$TEST_DIR/receiver"
python3 Tests/NDIRateIntegration.py "$HELPER" "$RUNTIME" "$TEST_DIR/receiver"
