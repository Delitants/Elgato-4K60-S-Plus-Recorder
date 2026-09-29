#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
ARCH="${ARCH:-arm64}"
case "$ARCH" in arm64|x86_64) ;; *) echo "Unsupported architecture: $ARCH" >&2; exit 1;; esac
BUILD_DIR="${BUILD_DIR:-build/$ARCH}"
APP_DIR="${APP_DIR:-build/$ARCH/Elgato Recorder.app}"
MEDIA_PREFIX="${MEDIA_PREFIX:-$(brew --prefix ffmpeg)}"
USB_PREFIX="${USB_PREFIX:-$(brew --prefix libusb)}"
export PKG_CONFIG_LIBDIR="$MEDIA_PREFIX/lib/pkgconfig"
mkdir -p "$BUILD_DIR/module-cache" "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Frameworks" "$APP_DIR/Contents/Resources"
clang++ -arch "$ARCH" -mmacosx-version-min=26.0 -std=c++17 -O2 -IHelpers/NDI/include Helpers/NDI/main.cpp -o "$APP_DIR/Contents/MacOS/NDISender"
cp Dependencies/NDI/libndi.dylib "$APP_DIR/Contents/Frameworks/"
clang++ -arch "$ARCH" -mmacosx-version-min=26.0 -std=c++17 -O2 Helpers/Media/main.cpp $(pkg-config --cflags --libs libavformat libavcodec libavutil libswscale libswresample) -o "$APP_DIR/Contents/MacOS/MediaHelper"
clang -arch "$ARCH" -O2 -Wall -Wextra -mmacosx-version-min=26.0 -I"$USB_PREFIX/include/libusb-1.0" -c Sources/USBBridge.c -o "$BUILD_DIR/USBBridge.o"
xcrun swiftc -O -target "$ARCH-apple-macosx26.0" -module-cache-path "$BUILD_DIR/module-cache" -import-objc-header Sources/USBBridge.h Sources/Completion.swift Sources/NDIOutput.swift Sources/CaptureFanout.swift Sources/MediaHelperClient.swift Sources/RecordingSink.swift Sources/FrameTiming.swift Sources/Profiles.swift Sources/PacketParser.swift Sources/Media.swift Sources/Monitoring.swift Sources/CaptureEngine.swift Sources/Settings.swift Sources/App.swift "$BUILD_DIR/USBBridge.o" -L"$USB_PREFIX/lib" -lusb-1.0 -Xlinker -rpath -Xlinker @executable_path/../Frameworks -o "$APP_DIR/Contents/MacOS/ElgatoRecorder"
if [ -f "$APP_DIR/Contents/Frameworks/libusb-1.0.0.dylib" ]; then chmod u+w "$APP_DIR/Contents/Frameworks/libusb-1.0.0.dylib"; fi
cp "$USB_PREFIX/lib/libusb-1.0.0.dylib" "$APP_DIR/Contents/Frameworks/"
install_name_tool -id @rpath/libusb-1.0.0.dylib "$APP_DIR/Contents/Frameworks/libusb-1.0.0.dylib"
USB_LINK=$(otool -L "$APP_DIR/Contents/MacOS/ElgatoRecorder" | awk '/libusb-1.0/{print $1}')
install_name_tool -change "$USB_LINK" @rpath/libusb-1.0.0.dylib "$APP_DIR/Contents/MacOS/ElgatoRecorder"
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ElgatoRecorder</string>
<key>CFBundleIdentifier</key><string>local.elgato.recorder</string>
<key>CFBundleName</key><string>Elgato Recorder</string>
<key>CFBundleDisplayName</key><string>Elgato Recorder</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>Recorder</string>
<key>CFBundleShortVersionString</key><string>0.6.8</string>
<key>CFBundleVersion</key><string>17</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>GPL-2.0. USB capture sequence adapted from Saddytech/elgato4k60sp-linux.</string>
</dict></plist>
PLIST
cp Resources/Credits.rtf "$APP_DIR/Contents/Resources/Credits.rtf"
cp Resources/Recorder.icns "$APP_DIR/Contents/Resources/Recorder.icns"
cp LICENSE "$APP_DIR/Contents/Resources/LICENSE.txt"
cp -R Licenses "$APP_DIR/Contents/Resources/"
python3 scripts/bundle-libraries.py "$APP_DIR" "$MEDIA_PREFIX" "$ARCH"
for library in "$APP_DIR"/Contents/Frameworks/*.dylib; do codesign --force --sign - "$library"; done
for executable in "$APP_DIR/Contents/MacOS/NDISender" "$APP_DIR/Contents/MacOS/MediaHelper"; do codesign --force --sign - "$executable"; done
codesign --force --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
echo "Built $APP_DIR ($ARCH)"
