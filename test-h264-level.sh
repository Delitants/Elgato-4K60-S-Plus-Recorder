#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="${1:-/Applications/Elgato Recorder.app}"
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/elgato-level-tests.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -suppress-warnings -module-cache-path "$TEST_DIR/cache" Sources/FrameTiming.swift Sources/Profiles.swift Sources/Media.swift Sources/PacketParser.swift Tests/H264LevelProfileTests.swift -o "$TEST_DIR/profiles"
"$TEST_DIR/profiles"
clang++ -std=c++17 Tests/H264LevelTests.cpp -o "$TEST_DIR/limits"
"$TEST_DIR/limits"
python3 Tests/H264LevelIntegration.py "$APP/Contents/MacOS/MediaHelper" "${@:2}"
