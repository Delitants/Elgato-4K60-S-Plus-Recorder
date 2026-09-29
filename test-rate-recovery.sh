#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="${1:-/Applications/Elgato Recorder.app}"
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/elgato-rate-tests.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
ditto "$APP" "$TEST_DIR/Recorder.app"
TEST_ARCH="${TEST_ARCH:-$(uname -m)}"
xcrun swiftc -O -target "$TEST_ARCH-apple-macosx26.0" -module-cache-path "$TEST_DIR/cache" Sources/Completion.swift Sources/CaptureFanout.swift Sources/MediaHelperClient.swift Sources/RecordingSink.swift Sources/FrameTiming.swift Sources/Profiles.swift Sources/PacketParser.swift Sources/Media.swift Tests/RecordingRateRecovery.swift -o "$TEST_DIR/Recorder.app/Contents/MacOS/RecordingRateRecovery"
python3 Tests/RecordingRateRecovery.py "$TEST_DIR/Recorder.app/Contents/MacOS/RecordingRateRecovery"

# A cold helper can take more than two seconds to load (observed under Rosetta).
# Delay the real helper to exercise startup through the same pipe, not a mock.
mv "$TEST_DIR/Recorder.app/Contents/MacOS/MediaHelper" "$TEST_DIR/Recorder.app/Contents/MacOS/MediaHelper.real"
cat > "$TEST_DIR/Recorder.app/Contents/MacOS/MediaHelper" <<'HELPER'
#!/bin/sh
sleep 3
exec "$0.real" "$@"
HELPER
chmod +x "$TEST_DIR/Recorder.app/Contents/MacOS/MediaHelper"
echo "Checking delayed helper startup"
FIXTURE_PACE=0.005 python3 Tests/RecordingRateRecovery.py "$TEST_DIR/Recorder.app/Contents/MacOS/RecordingRateRecovery"
