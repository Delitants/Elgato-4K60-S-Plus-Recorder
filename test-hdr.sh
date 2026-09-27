#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/elgato-hdr-tests.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
ffmpeg -v error -f lavfi -i color=c=gray:s=320x180:r=30 -frames:v 4 -pix_fmt yuv420p10le -c:v libx265 -x265-params 'aud=1:repeat-headers=1:bframes=0:colorprim=9:transfer=16:colormatrix=9:master-display=G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1):max-cll=1000,400:log-level=error:pools=1' -f hevc "$TEST_DIR/hdr.hevc"
ffmpeg -v error -f lavfi -i color=c=gray:s=320x180:r=30 -frames:v 4 -pix_fmt yuv420p10le -c:v libx265 -x265-params 'aud=1:repeat-headers=1:bframes=0:colorprim=1:transfer=1:colormatrix=1:log-level=error:pools=1' -f hevc "$TEST_DIR/sdr.hevc"
xcrun swiftc -target arm64-apple-macosx26.0 -module-cache-path "$TEST_DIR/cache" Sources/Profiles.swift Sources/PacketParser.swift Sources/Media.swift Tests/HDRTests.swift -o "$TEST_DIR/test"
"$TEST_DIR/test" "$TEST_DIR/hdr.hevc" "$TEST_DIR/hdr.mov" "$TEST_DIR/sdr.hevc"
ffprobe -v error -select_streams v -show_frames -read_intervals '%+#1' -of json "$TEST_DIR/hdr.mov" > "$TEST_DIR/metadata.json"
python3 - "$TEST_DIR/metadata.json" <<'PY'
import json,sys
frame=json.load(open(sys.argv[1]))['frames'][0]
assert frame['color_transfer']=='smpte2084'
assert frame['color_primaries']=='bt2020'
assert frame['pix_fmt']=='yuv420p10le'
side={item['side_data_type']:item for item in frame['side_data_list']}
assert 'Mastering display metadata' in side
assert side['Content light level metadata']['max_content']==1000
print('PASS: PQ, BT.2020, 10-bit, mastering display and light-level metadata retained')
PY
