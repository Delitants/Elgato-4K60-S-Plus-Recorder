# Elgato Recorder 0.4.1 output audit

Tested on the current Apple Silicon Mac running macOS 27.0 (26A428), with the
connected Elgato 4K60 S+ 20GAP9901. **949 matrix checks passed: 945 finalized
recordings and 4 expected HDR-transcoding rejections.** Generated media was removed.
The detailed configurations and results are in [OUTPUT-TEST-RESULTS.json](OUTPUT-TEST-RESULTS.json).

| Suite | Cases | Result |
|---|---:|---|
| 1080p60 H.264 input: all accepted base output combinations | 348 | Pass |
| 10-bit HEVC input: all accepted base output combinations | 348 | Pass |
| Compression presets, profiles, audio effort/modes, FPS, AQ and B-frames | 146 | Pass |
| Hardware ABR/CBR × profiles, video bitrate boundaries and AAC bitrates | 40 | Pass |
| Synthetic 4K input, output dimensions, sampling filters and software codecs | 59 | Pass |
| PQ/BT.2020 passthrough in four containers | 4 | Pass |
| Unsupported HDR transcoding rejected before file creation | 4 | Pass |

Each base suite enumerates the 900 combinations of 4 containers × 5 video
selections × 5 audio selections × 3 encoder selections × 3 decoder selections.
Profile validation rejects 552 incompatible configurations; all 348 accepted
configurations are recorded through the production RecordingSink, not a parallel
implementation. The H.264 base fixture is 1920×1080; the HEVC fixture is 320×180,
10-bit SDR. The separate scaling suite uses 3840×2160 input.

Every successful matrix recording is probed and fully decoded, checking codec,
frame count and stereo 48 kHz audio. The HEVC/control/4K/HDR suites also compare
lossless PCM output byte-for-byte. Profile and output-dimension assertions cover
the relevant control/scaling cases. One 59.94 fps test expectation was corrected:
in a one-second 60-frame source, the last frame's PTS is 983333 µs, before output
slot 59 at 984317 µs; 59 selected frames are correct. Its targeted rerun passed.

## Bugs and compatibility findings

- The recording budget incorrectly treated a video/audio PTS inversion as
  overload. Queue age now uses monotonic waiting time. A regression reproduced
  the old failure before the fix.
- Cold helper initialization sometimes exceeded the old 0.5-second allowance.
  The bounded allowance is now two seconds; the 64 MB cap remains. The final
  complete 1080p matrix passed after the change.
- Explicit software HEVC in basic MOV/MP4 used Apple's software path and fell
  behind, while x265 in MKV passed. Software encoding now consistently uses the
  bundled software backend across containers.
- Hardware H.264 B-frames produced invalid PTS/DTS on this Mac, independently
  reproduced with FFmpeg. The app warns and rejects that selection before
  recording; use Disabled or Software. Hardware HEVC B-frame cases passed.
- Settings use native segmented navigation; all five pages were checked in the
  installed app. H.264 is explicitly labeled AVC.
- The final elapsed-time display is updated after the recording queue drains.
- Helper failures retain their final diagnostic instead of masking it with the
  pipe's generic failure. The HDR rejection cases exercise that path.

## Additional verification

- Full Swift regression suite passed, including parser, audio ring, queue bounds,
  timing, profile validation and process completion tests.
- ARM: 14 codec/control integration cases and the complete FPS/splitting suite
  passed. Intel under Rosetta: 13 codec/control cases and the FPS/splitting suite
  passed; required hardware HEVC was explicitly unavailable (-12908), not passed.
- Split-by-time and split-by-size, B-frame outputs and unaligned source keyframes
  were decoded; split frame counts and PCM continuity passed.
- Native HDR metadata test retained PQ, BT.2020, 10-bit samples, mastering-display
  and content-light metadata.
- NDI receiver observed video and audio with no incorrect FPS metadata.
- Both architecture bundles passed signature, architecture, dependency-closure
  and minimum-macOS-26 audits.
- The installed Applications app completed a 30-second timer session using the
  user's hardware H.264 High / CBR 9 Mbps / 30 fps / AAC / MKV settings with
  B-frames disabled. The file contained 895 video frames at 30 fps, stereo AAC,
  and lasted 29.870 seconds; full decode produced no errors. Incoming USB rate
  was 59.94 fps, with no parser discards. The HDMI audio source was silent during
  that run, so this does not establish audible monitoring quality.

- Final rebuilt Applications app also completed a ten-second timer check: 299
  H.264 frames at 30 fps, stereo AAC, 10.005 seconds including audio, and no
  decode errors. The final video elapsed display was 9 seconds (whole seconds).

## Boundaries

The matrix uses one-second synthetic fixtures. It checks compatibility and
finalization, not sustained throughput for every preset or the full Cartesian
product of all FPS, resolution, bitrate, compression and split settings. Slow
software presets can still fall behind at high resolutions. The two-second queue
allowance intentionally stops a sustained overload rather than dropping media.

Physical Intel hardware, macOS 26 runtime, physical HDR display behavior, extended
soaks and every HDMI source mode remain unverified. Physical HDMI resolution/FPS
detection remains unavailable; automatic FPS measures the encoded USB stream.
