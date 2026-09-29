#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="${1:-/Applications/Elgato Recorder.app}"
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/elgato-backpressure-app.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
ditto "$APP" "$TEST_DIR/Recorder.app"
# Keep Rosetta test launches distinct from the user's installed native app.
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.elgato.recorder.backpressure-test' "$TEST_DIR/Recorder.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Elgato Backpressure Test' "$TEST_DIR/Recorder.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Elgato Backpressure Test' "$TEST_DIR/Recorder.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable RecordingBackpressure' "$TEST_DIR/Recorder.app/Contents/Info.plist"
TEST_ARCH="${TEST_ARCH:-$(uname -m)}"
xcrun swiftc -suppress-warnings -O -target "$TEST_ARCH-apple-macosx26.0" -module-cache-path "$TEST_DIR/cache" Sources/Completion.swift Sources/CaptureFanout.swift Sources/MediaHelperClient.swift Sources/RecordingSink.swift Sources/FrameTiming.swift Sources/Profiles.swift Sources/PacketParser.swift Sources/Media.swift Tests/RecordingBackpressure.swift -o "$TEST_DIR/Recorder.app/Contents/MacOS/RecordingBackpressure"
python3 Tests/RecordingBackpressure.py "$TEST_DIR/Recorder.app/Contents/MacOS/RecordingBackpressure"

if [ "${TEST_MATRIX:-0}" = 1 ]; then
 TEST_MODE=film TEST_STALLS=11:3,17:3 python3 Tests/RecordingBackpressure.py "$TEST_DIR/Recorder.app/Contents/MacOS/RecordingBackpressure"
 TEST_PADDING=1048576 TEST_STALLS=11:1.7 python3 Tests/RecordingBackpressure.py "$TEST_DIR/Recorder.app/Contents/MacOS/RecordingBackpressure"
 TEST_STOP_AT=14 python3 Tests/RecordingBackpressure.py "$TEST_DIR/Recorder.app/Contents/MacOS/RecordingBackpressure"
 TEST_MODE=copy python3 Tests/RecordingBackpressure.py "$TEST_DIR/Recorder.app/Contents/MacOS/RecordingBackpressure"
 TEST_TERMINAL=1 TEST_STALLS=11:34 python3 Tests/RecordingBackpressure.py "$TEST_DIR/Recorder.app/Contents/MacOS/RecordingBackpressure"
fi

if [ "${TEST_TERMINAL_CASE:-0}" = 1 ]; then
 TEST_TERMINAL=1 TEST_STALLS=11:34 python3 Tests/RecordingBackpressure.py "$TEST_DIR/Recorder.app/Contents/MacOS/RecordingBackpressure"
fi
