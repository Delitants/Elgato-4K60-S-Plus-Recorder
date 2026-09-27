#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/elgato-fps.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
python3 Tests/FrameRateIntegration.py "$TEST_DIR" "${MEDIA_HELPER:-build/${ARCH:-arm64}/Elgato Recorder.app/Contents/MacOS/MediaHelper}"
