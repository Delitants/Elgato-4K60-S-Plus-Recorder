#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="${1:-/Applications/Elgato Recorder.app}"
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/elgato-faststart.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
LIB="$APP/Contents/Frameworks"
mkdir -p "$TEST_DIR/MacOS"
ln -s "$LIB" "$TEST_DIR/Frameworks"
clang -O2 -Dmain=mp4_faststart_main -Dfclose=test_fclose -c Helpers/MP4/qt-faststart.c -o "$TEST_DIR/optimizer.o"
clang -O2 -c Tests/FastStartCloseFailure.c -o "$TEST_DIR/close.o"
clang++ -std=c++17 -O2 -I"$(brew --prefix ffmpeg@8)/include" Helpers/Media/main.cpp "$TEST_DIR/optimizer.o" "$TEST_DIR/close.o" "$LIB/libavformat.62.dylib" "$LIB/libavcodec.62.dylib" "$LIB/libavutil.60.dylib" "$LIB/libswscale.9.dylib" "$LIB/libswresample.6.dylib" -Wl,-rpath,@executable_path/../Frameworks -o "$TEST_DIR/MacOS/MediaHelper"
python3 Tests/MP4FastStart.py "$APP/Contents/MacOS/MediaHelper" "$TEST_DIR/MacOS/MediaHelper"
xcrun swiftc -module-cache-path "$TEST_DIR/cache" Sources/Completion.swift Tests/FastStartWatchdog.swift -o "$TEST_DIR/watchdog"
"$TEST_DIR/watchdog"
xcrun swiftc -suppress-warnings -module-cache-path "$TEST_DIR/cache" Sources/PacketParser.swift Sources/FrameTiming.swift Sources/Profiles.swift Sources/Media.swift Tests/NativeFastStart.swift -o "$TEST_DIR/native"
ffmpeg -v error -f lavfi -i testsrc2=size=160x90:rate=30 -frames:v 1 -c:v libx264 -preset ultrafast -f h264 "$TEST_DIR/frame.h264"
"$TEST_DIR/native" "$TEST_DIR"
python3 - "$TEST_DIR" <<'PY'
import pathlib,struct,subprocess as sp,sys
for ext in ['mov','mp4']:
 p=pathlib.Path(sys.argv[1])/('native.'+ext);data=p.read_bytes();pos=0;tags=[]
 while pos<len(data):
  size,tag=struct.unpack_from('>I4s',data,pos)
  if size==1:size=struct.unpack_from('>Q',data,pos+8)[0]
  if size==0:size=len(data)-pos
  assert size>=8 and pos+size<=len(data)
  tags.append(tag);pos+=size
 assert (tags.index(b'moov')<tags.index(b'mdat'))==(ext=='mp4'),(ext,tags)
 sp.run(['ffmpeg','-v','error','-xerror','-i',str(p),'-f','null','-'],check=True)
 print('PASS native',ext,'box order and full decode')
PY
