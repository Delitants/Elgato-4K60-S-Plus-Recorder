#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/elgato-window-tests.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
# Keep the real delegate and view implementations; replace only the app entrypoint.
python3 - "$TEST_DIR/App.swift" <<'PY'
from pathlib import Path
import sys
source=Path('Sources/App.swift').read_text()
head,marker,_=source.partition('@main struct ElgatoRecorderApp')
assert marker
Path(sys.argv[1]).write_text(head)
PY
TEST_ARCH="${TEST_ARCH:-$(uname -m)}"
USB_PREFIX="${USB_PREFIX:-$(brew --prefix libusb)}"
USB_LIB="${USB_LIB:-$USB_PREFIX/lib/libusb-1.0.0.dylib}"
clang -arch "$TEST_ARCH" -O2 -mmacosx-version-min=26.0 -I"$USB_PREFIX/include/libusb-1.0" -c Sources/USBBridge.c -o "$TEST_DIR/USBBridge.o"
xcrun swiftc -suppress-warnings -target "$TEST_ARCH-apple-macosx26.0" -module-cache-path "$TEST_DIR/cache" -import-objc-header Sources/USBBridge.h Sources/Completion.swift Sources/NDIOutput.swift Sources/CaptureFanout.swift Sources/MediaHelperClient.swift Sources/RecordingSink.swift Sources/FrameTiming.swift Sources/Profiles.swift Sources/PacketParser.swift Sources/Media.swift Sources/Monitoring.swift Sources/CaptureEngine.swift Sources/Settings.swift "$TEST_DIR/App.swift" Tests/WindowLifecycleTests.swift "$TEST_DIR/USBBridge.o" -Xlinker "$USB_LIB" -Xlinker -rpath -Xlinker "$(dirname "$USB_LIB")" -o "$TEST_DIR/window-tests"
"$TEST_DIR/window-tests"
