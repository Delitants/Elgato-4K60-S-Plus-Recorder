# Validation

Current release: [0.6.12 H.264 level selection](docs/VALIDATION-0.6.12.md).

Previous: [0.6.11 MP4 fast start](docs/VALIDATION-0.6.11.md).

Previous: [0.6.10 MKV network playback](docs/VALIDATION-0.6.10.md).

Previous: [0.6.9 recording backlog recovery and timer controls](docs/VALIDATION-0.6.9.md).

Previous: [0.6.8 window-close crash fix](docs/VALIDATION-0.6.8.md).

Previous: [0.6.7 recording-rate recovery and film preview](docs/VALIDATION-0.6.7.md).

Previous: [0.6.5 audio clock recovery validation](docs/VALIDATION-0.6.5.md).

Previous: [0.6.4 preview restore validation](docs/VALIDATION-0.6.4.md).

Previous: [0.6.3 background recording validation](docs/VALIDATION-0.6.3.md).

Previous: [0.6.0 hardware constant-quality validation](docs/VALIDATION-0.6.0.md).
Previous: [0.5.1 incoming bitrate and format validation](docs/VALIDATION-0.5.1.md).
Previous: [0.5.0 cadence, controls and live recording validation](docs/VALIDATION-0.5.0.md).
Earlier results below are historical and retain their original scope.

Target: Apple M1 Pro, 16 GB RAM, macOS 27.0 (26A428).
Device: Elgato Game Capture 4K60 S+, model 20GAP9901,
USB 0fd9:0075, bcdDevice 0404, negotiated link 5 Gbps.

## Results

- Direct USB capture and clean streaming stop succeeded.
- Native GUI live preview visibly showed the HDMI source on the Mac.
- First GUI Record/Stop: 26.506667 s video, 1589 H.264 frames at
  1920x1080; 48 kHz stereo PCM audio, 26.496 s, beginning at +13.333 ms.
- Second GUI Record/Stop: 83.375 s video, 4998 H.264 frames at
  1920x1080; 48 kHz stereo PCM audio, 83.370667 s, beginning at +11.667 ms.
- Both recordings passed a complete FFmpeg video/audio decode with exit 0
  and no decode-error output. The first recording had nonzero audio with
  overall peak -13.315 dBFS and RMS -28.174 dBFS.
- GUI packet/recording discard counter remained zero during live tests.
- Parser regression suite passed: real USB fixture, timestamps, arbitrary
  read boundaries, missing packets, excessive sizes, resynchronization,
  and large frames whose counter wraps 255 -> 1 (zero denotes frame start).
- Native writer fixture test passed: 513 video frames, 410624 audio frames,
  no writer drops. Result was independently decoded.
- App signature verified with codesign --verify --deep --strict.
- Main binary resolves libusb from the bundled Frameworks directory.

## Limits

No independent audible quality or known-signal lip-sync verification.
No 4K/HDR test. No physical-unplug/disk-full recovery test or extended soak.
Warnings for deprecated AVFoundation APIs are present with the macOS 27 SDK.
Local Apple Silicon build is ad-hoc signed and not notarized.

All generated test recordings, raw USB captures, extracted audio/video,
preview stills, and build caches were deleted at the user's request.
Only application/source/documentation deliverables are retained.

## Version 0.2 — 2026-09-27

- Native UI timer test with video preview disabled and audio monitoring enabled:
  eight-second limit produced 8.005 s H.264 and 8.000 s PCM; zero packet discards.
- USB 4K HEVC probe: 3840×2160, Main 10, yuv420p10le, 251 complete video frames.
- Native app 4K preview visually inspected. Timed original HEVC/MOV recording:
  3840×2160 Main 10, 4.231667 s video / 4.266667 s PCM. The six-second wall-clock
  timer included waiting for the first keyframe.
- UI conversion: 4K HEVC input → hardware H.264 1280×720 + AAC 48 kHz stereo,
  MP4, 5.971667 s video / 5.986375 s audio. Video preview off, audio monitoring
  on, zero reported discards, timer finalized automatically.
- Captured-fixture paths: hardware HEVC + ALAC, hardware ProRes + PCM, software
  H.264 + AAC at 1280×720: 251 video frames / 200704 audio samples, zero drops.
- Software ProRes stalled; Apply rejects this combination in the release.
- Recorded samples decoded with FFmpeg. When checking device timestamps, use
  a sufficiently fine output time base (`-enc_time_base:v 1:1000000`) to avoid
  false duplicate-DTS warnings from rounding into the null muxer's default.
- Synthetic HDR10: PQ transfer, BT.2020, 10-bit pixels, mastering-display
  coordinates/luminance and MaxCLL=1000/MaxFALL=400 retained in native MOV.
- Parser, timer and profile regressions passed. Code review identified and
  corrected slow-finalization quit, immediate-stop, and mid-recording format/
  HDR transition handling. Record is available while waiting for HDMI.
- Actual HDR HDMI source, audio lip-sync, software HEVC, software decoding,
  long-duration performance, disk-full and unplug recovery remain unverified.
- Source captures, encoded tests, generated HDR media and build caches are
  temporary and removed after final validation. No Windows driver binary is
  included in the deliverable.


## Version 0.2.1 — preview performance fix

- Three-second sample of the reported slow app: 771/1121 capture-thread samples
  inside PacketParser.feed, dominated by Data copy-on-write / vm_copy. The
  value-type Assembly copied out of a dictionary retained a second Data owner,
  forcing a complete accumulating-frame copy for each ~1 KB packet.
- Reproduction: twelve 1 MiB frames, fed in live-sized 2048-byte chunks. Before:
  6.5 MB/s, 1.925 seconds (fails 50 MB/s regression threshold). After: 3373 MB/s
  in final test, retaining exact frame data. Single reference-owned assembly
  with reserved capacity removes repeated whole-frame copying.
- Matched 30-second live probes used 4K HEVC / 60 Mbps without saving video.
  Both short runs stayed near 60 fps; the original probe did not reproduce the
  user's full delay on that scene. Fixed probe: zero discards, latest decoded
  timestamp drift about 71 ms over the sampled interval, no multi-second growth.
  The metric is relative to the first decoded frame, not absolute HDMI latency.
- Preview Timer now runs at 60 Hz in common run-loop modes (was 30 Hz/default),
  preventing UI tracking/menu operation from suspending refresh.
- Updated GUI timed recording: HEVC 3840×2160, 5.988333 seconds; AAC 48 kHz stereo,
  6.034687 seconds. Zero reported discards; complete FFmpeg decode succeeded.
- Parser correctness, throughput, duration, profile and HDR-guard tests passed.
  Test recording and build/probe caches removed. Physical input-to-display
  latency still requires comparison with the source; not claimed measured.


## Version 0.3.0 — release validation

Target remains the physical 20GAP9901 on M1 Pro/macOS 27. Release deployment
minimum is macOS 26. The x86_64 build was tested through Rosetta on this Mac;
physical Intel hardware has not been tested.

- ARM packaged MediaHelper: 14 codec/container/control cases passed full
  video/audio decode, frame counts, and split checks. Includes AV1/Opus,
  AV1/FLAC, H.264/AAC TS, software HEVC Main10/FLAC, hardware H.264,
  hardware HEVC Main10/ALAC and hardware ProRes/PCM.
- Intel packaged helper: 13 cases passed. Required hardware HEVC was unavailable
  through Rosetta (VideoToolbox -12908); this is an explicit unavailable result,
  not a successful test. Software HEVC Main10 passed.
- PCM time-split regression: each one-second part contains exactly 48,000 audio
  frames, and concatenated decoded PCM matches the source byte-for-byte.
- Approximate size splitting produced multiple independently decodable MKV parts.
- Synthetic HDR10 metadata preservation and mid-stream format guards passed.
  Physical HDR HDMI and HDR transcoding are not validated/supported respectively.
- Parser, throughput, timer, profile, audio-ring, bounded recording queue,
  partial-error reporting, stopped-process termination/reaping, and fragmented
  Unicode filename/EOF-drain regressions passed.
- NDI receiver measured 298 video frames and 235 audio blocks in five seconds.
  OBS 32.2.2 with DistroAV 6.2.1 visibly received moving video and audio levels.
  Bundled runtime discovery and missing-runtime error handling passed.
- Preview audio diagnosis caught a 314 ms AVAudioPlayerNode submission on the
  USB capture thread. Replacing per-packet scheduling with a preallocated ring
  and AVAudioSourceNode reduced observed submission to below 0.15 ms.
  The user confirmed the updated monitor sounds steady. This is not a guarantee
  of zero underruns under every workload or a calibrated lip-sync measurement.
- Packaged ARM live HEVC 3840x2160 + Opus MKV recording finalized by its six-second
  timer and passed complete strict decode. The FFmpeg null-output time base was
  explicitly set to 1/1000000 to avoid duplicate-DTS rounding artifacts.
- Live software AV1 at 1080p60/preset 13 with 4K input and NDI exceeded the bounded
  recording queue on this loaded M1 Pro. The UI correctly reported overload and
  exposed a decodable partial file. AV1 is supported, but real-time performance
  at this setting is not established. Reduce resolution/workload as needed.
- Both architecture bundles passed dependency-closure and ad-hoc signature checks.

Device encoder resolution remains a manual setting. Encoded dimensions do not
prove the physical HDMI source dimensions; automatic source-resolution detection
is not implemented. Dolby/DTS capture is unsupported; source audio must be PCM.
Long-duration soak, disk-full/unplug recovery and precise source-to-preview
latency remain unverified. Release binaries are ad-hoc signed, not notarized.
Test recordings are removed after inspection; synthetic test scripts clean their
own temporary media.

Final Intel live retest: removing an unnecessary hardware-frame CPU download
from Original video recording allowed the timed 4K HEVC/Opus MKV test to finish
under Rosetta with NDI active. Both codec matrices passed again after this change.
The final Intel live file passed strict full video/audio decode with no errors;
the test recording was deleted.


## Version 0.4.0 — FPS and downsampling

- Regression first reproduced: 30 fps samples were labeled 59.94, and a requested
  two-second 60→30 conversion kept 120 frames instead of 60.
- Swift suite passes integer/fractional selection, no upsampling, timestamp gaps,
  settings migration, manual source override, and honest recording-start counters.
- Real Elgato timestamps have alternating short/long intervals. A median-filtered
  estimate incorrectly reported ~62.8 fps. Timeline regression now measures the
  cadence; the live test settled at 59.94 fps. Synthetic alternating jitter and
  a 500 ms gap remain at the correct rate throughout recovery.
- Both packaged ARM and x86_64 helpers pass 60→30, 30→30, 29.97→29.97,
  59.94→29.97, 60→24, 60→15 and 30→60 capped at 30. Tests check frame counts,
  output timeline, complete decode, and byte-identical decoded PCM audio.
- Original compressed 30 fps passthrough preserves all frames. Attempting 30→15
  in Original mode is rejected before a file is created.
- Time splitting with source GOP61 at 60→15 passes: 75 frames over five seconds,
  complete PCM, independently keyed parts within the documented split bound.
- Existing codec matrix remains ARM 14 passes; Intel 13 passes and required
  hardware HEVC explicitly unavailable through Rosetta. HDR preservation passes.
- Native CaptureEngine live test on the connected 20GAP9901: incoming 1080p H.264
  settled at 59.94; output cap 30; preview delivered 183 frames at ~29.58 fps
  across the measured interval. Four-second wall-clock timed H.264/Opus MKV
  recording finalized. NDI receiver got 76 video frames plus 145 audio blocks
  during discovery/three-second capture, with zero incorrect FPS metadata.
- Both self-contained bundles pass signatures, architecture, dependency closure,
  and a minimum-OS audit of every Mach-O. FFmpeg was rebuilt with macOS 26 linker
  flags; 0.3.0 inadvertently included libraries declaring macOS 27.

Physical HDMI 30 Hz switching has not been verified; no source-change response
was available during the test. Automatic FPS follows the encoded USB timestamps,
not a verified HDMI input-status field. Manual source FPS caps repeated streams.
The final native-window visual check is pending because the desktop was locked;
the live test exercised the real capture engine through a developer-only CLI
harness, including preview delivery, recording, and NDI. macOS 26 runtime and
physical Intel hardware testing remain unverified; host runtime was macOS 27.
The final live MKV reports 30/1 fps, 118 H.264 frames, 48 kHz stereo Opus,
and 3.962 seconds. Full strict decode passed with no errors; the file was deleted.

## Version 0.4.1 — recording startup and output audit

See [OUTPUT-TEST-REPORT.md](OUTPUT-TEST-REPORT.md) for the 949-case audit, the
recording failures reproduced and corrected, native UI/live-recording checks,
and explicit test boundaries. Raw per-configuration results are stored alongside
that report. Hardware H.264 B-frames are intentionally blocked with a warning;
hardware HEVC B-frames and software H.264/HEVC B-frames passed their tests.
