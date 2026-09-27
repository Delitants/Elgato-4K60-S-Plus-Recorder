#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/elgato-tests.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -module-cache-path "$TEST_DIR/cache" Sources/PacketParser.swift Tests/ParserTests.swift -o "$TEST_DIR/parser-tests"
if [ "$#" -gt 0 ]; then
  "$TEST_DIR/parser-tests" "$1"
  xcrun swiftc -target arm64-apple-macosx26.0 -module-cache-path "$TEST_DIR/cache" Sources/PacketParser.swift Sources/Profiles.swift Sources/Media.swift Tests/MediaTests.swift -o "$TEST_DIR/media-tests"
  "$TEST_DIR/media-tests" "$1" "$TEST_DIR/native-fixture.mov"
else
  "$TEST_DIR/parser-tests"
fi
xcrun swiftc -module-cache-path "$TEST_DIR/cache" Sources/Monitoring.swift Tests/MonitoringTests.swift -o "$TEST_DIR/monitoring-tests"
"$TEST_DIR/monitoring-tests"
xcrun swiftc -module-cache-path "$TEST_DIR/cache" Sources/Monitoring.swift Tests/AudioRingTests.swift -o "$TEST_DIR/audio-ring-tests"
"$TEST_DIR/audio-ring-tests"
xcrun swiftc -module-cache-path "$TEST_DIR/cache" Sources/Profiles.swift Sources/Media.swift Sources/PacketParser.swift Tests/ProfileTests.swift -o "$TEST_DIR/profile-tests"
"$TEST_DIR/profile-tests"
xcrun swiftc -O -module-cache-path "$TEST_DIR/cache" Sources/PacketParser.swift Tests/ParserPerformanceTests.swift -o "$TEST_DIR/parser-performance-tests"
"$TEST_DIR/parser-performance-tests"
xcrun swiftc -suppress-warnings -module-cache-path "$TEST_DIR/cache" Sources/Profiles.swift Sources/Media.swift Sources/PacketParser.swift Tests/AdvancedProfileTests.swift -o "$TEST_DIR/advanced-profiles"
"$TEST_DIR/advanced-profiles"
xcrun swiftc -module-cache-path "$TEST_DIR/cache" Sources/Completion.swift Tests/CompletionTests.swift -o "$TEST_DIR/completion-tests"
"$TEST_DIR/completion-tests"
xcrun swiftc -module-cache-path "$TEST_DIR/cache" Sources/CaptureFanout.swift Tests/FanoutTests.swift -o "$TEST_DIR/fanout-tests"
"$TEST_DIR/fanout-tests"
echo "Temporary test artifacts cleaned on exit."
