#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="${1:?Pass the built app bundle}"
REPORTS="${2:?Pass a report directory}"
shift 2
mkdir -p "$REPORTS"
REPORTS="$(cd "$REPORTS" && pwd)"
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/elgato-output-tests.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
ditto "$APP" "$TEST_DIR/Recorder.app"
xcrun swiftc -O -module-cache-path "$TEST_DIR/cache" Sources/Completion.swift Sources/CaptureFanout.swift Sources/MediaHelperClient.swift Sources/RecordingSink.swift Sources/FrameTiming.swift Sources/Profiles.swift Sources/PacketParser.swift Sources/Media.swift Tests/OutputMatrix.swift -o "$TEST_DIR/Recorder.app/Contents/MacOS/OutputMatrix"
if [ "$#" -eq 0 ]; then set -- all hevc controls hardware 4k hdr; fi
status=0
for mode in "$@"; do
 if ! python3 Tests/OutputMatrix.py "$TEST_DIR/Recorder.app/Contents/MacOS/OutputMatrix" "$REPORTS/$mode.jsonl" "$mode"; then status=1; fi
done
exit "$status"
