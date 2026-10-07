# 0.6.12 — H.264 level selection

Validated on Apple Silicon/macOS 27. The installed native app reports version
0.6.12 (build 21). The Intel software tests ran through Rosetta, not a physical
Intel Mac.

## Results

- Settings → Video exposes Auto and levels 3.0, 3.1, 3.2, 4.0, 4.1, 4.2,
  5.0, 5.1 and 5.2. Native UI inspection confirmed the complete menu, readable
  layout, and automatic reset/disable when switching to HEVC. Cancel preserved
  the existing recording preferences. The app reconnected to the USB 3 device.
- Legacy settings decode with Auto. Profile serialization, codec guards and
  routing to the helper passed for the supported encoders and containers.
- Generated 640×360/30 fps input passed all nine explicit levels across Auto,
  Baseline, Main and High profiles with both libx264 and VideoToolbox on ARM
  (72 combinations). Each output had the requested SPS level, 30 frames and a
  successful complete decode. The corresponding 36 software combinations
  passed in the Intel helper through Rosetta.
- Explicit levels passed in MP4, MOV, MKV and MPEG-TS. MPEG-TS verification reads
  in-band SPS when encoder extradata is absent. Software CRF/CBR and hardware
  CQ/CBR paths passed. Invalid levels, incompatible codecs, excessive bitrates
  and excessive macroblock rates were rejected.
- A 1920×1080/60 fps fixture produced level 4.1 at 30 fps and level 4.2 at
  60 fps with both native ARM encoders; frame counts and full decode passed.
  Level 4.1 at 1080p60 was rejected. Software veryslow/B-frame output remained
  within the level's decoded-picture-buffer limit.
- Conservative Baseline/Main bitrate ceilings apply to every selected profile,
  because software presets may emit a lower profile. The ultrafast/High/level
  3.0/12 Mbps case was rejected rather than emitting a nonconforming stream.
- Unit tests cover rational frame rates, dimensions, 4K level boundaries,
  bitrate limits, avcC/Annex-B SPS parsing, and malformed/truncated headers.
- The existing core regression suite passed. Both release bundles passed
  architecture, bundled dependency, minimum-OS and strict signature checks.
  Installed executables are ARM64; all installed libraries include ARM64.

The pre-change helper reproduced the missing-level defect by emitting level
3.0 when 4.1 was requested. A separate MPEG-TS regression reproduced rejection
before the in-band SPS fallback was added. Both cases now pass.

## Limits

No new live HDMI recording, long soak, physical Intel hardware, macOS 26 runtime
or LG TV/DLNA seeking test was performed for this change. Generated encoder
tests do not establish TV or DLNA server compatibility. Explicit levels constrain
recorded H.264 output; they do not change the device's incoming stream.

Test media is created in temporary directories and removed automatically.
Release binaries are ad-hoc signed and not notarized.

## Auto keyframe behavior

A separate 22-second generated-input probe at 23.976 fps measured the installed
helper's output: hardware H.264/CQ Auto emitted keyframes every 12 frames
(about 0.5005 seconds), while software libx264/CRF Auto used up to 250 frames
(about 10.427 seconds). Explicit two-second intervals produced 48-frame GOPs
(about 2.002 seconds) on both encoders. Auto delegates to encoder defaults; it
is not a fixed interval across all paths. Original video preserves the device's
keyframes, and the native AVAssetWriter path leaves the interval to Apple.
The probe recordings were removed. These measurements do not diagnose a
particular user's file or establish DLNA seeking support.
