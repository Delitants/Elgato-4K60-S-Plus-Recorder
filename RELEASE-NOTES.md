# Elgato Recorder 0.4.1 (experimental)

Native macOS ARM and Intel builds. Requires macOS 26+; NDI runtime is bundled.

![Elgato Game Capture 4K60 S+](https://raw.githubusercontent.com/Delitants/Elgato-4K60-S-Plus-Recorder/main/docs/images/elgato-4k60-s-plus.png)

![Elgato Recorder on macOS with live video and HDMI audio preview](https://raw.githubusercontent.com/Delitants/Elgato-4K60-S-Plus-Recorder/main/docs/images/elgato-recorder.png)

- Fixed false recording overloads caused by interleaved audio/video timestamps.
  Queue age now measures monotonic waiting time, with a bounded two-second
  cold-start allowance and the existing 64 MB memory limit.
- Replaced blurred legacy settings tabs with native segmented navigation.
- Explicit Software encoding consistently uses the bundled x264/x265 encoder
  across containers, fixing software HEVC recording failures in MOV/MP4.
- Hardware H.264/AVC B-frames now show a warning and are rejected before recording.
  On the tested Mac they produce invalid decode timestamps. Select Disabled or
  use Software encoding. Hardware HEVC B-frames remain available.
- Final elapsed time updates after queued recording data finishes writing.
- Backend failures retain the actual encoder diagnostic after output drains.
- Added a production-pipeline output matrix with frame-count, decode, lossless
  audio, profile and scaling checks. See VALIDATION.md for results and limits.

Intel tests use Rosetta, not physical Intel hardware. Builds are ad-hoc signed,
not notarized. Short matrix fixtures establish compatibility, not sustained
performance at every resolution, frame rate, bitrate and compression preset.
Physical HDR display validation remains unverified.

[Research sources and development provenance](https://github.com/Delitants/Elgato-4K60-S-Plus-Recorder/blob/main/SOURCES.md) documents upstream USB research, vendor references and dependency inputs.
