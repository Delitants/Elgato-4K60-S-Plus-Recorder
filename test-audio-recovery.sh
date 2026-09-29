#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
python3 Tests/AudioRecoveryIntegration.py "${MEDIA_HELPER:-build/${ARCH:-arm64}/Elgato Recorder.app/Contents/MacOS/MediaHelper}"
