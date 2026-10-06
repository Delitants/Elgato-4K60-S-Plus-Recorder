#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="${1:-/Applications/Elgato Recorder.app}"
python3 Tests/NetworkPlayback.py "$APP/Contents/MacOS/MediaHelper"
