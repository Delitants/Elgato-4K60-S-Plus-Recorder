#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
HELPER="${NDI_HELPER:-build/${ARCH:-arm64}/Elgato Recorder.app/Contents/MacOS/NDISender}"
RUNTIME="${NDI_RUNTIME:-build/${ARCH:-arm64}/Elgato Recorder.app/Contents/Frameworks/libndi.dylib}"
"$HELPER" "$RUNTIME" --probe
if "$HELPER" /nonexistent/libndi.dylib --probe; then echo 'Missing runtime incorrectly accepted'; exit 1; fi
