# Version 0.5.1 validation

Tested September 27, 2026 on an Apple M1 Pro running macOS 27.0.
Connected Elgato 4K60 S+ model 20GAP9901; negotiated USB 3, 5 Gbps.

## Scope

Adds incoming compressed-video throughput measurement and clarifies the source
cadence cap. No USB configuration, decoding, recording or FPS selection algorithm
was changed. Codec/depth status now uses the received format description instead
of presenting a requested HEVC profile as observed fact.

## Automated checks

- Full `test.sh` passed: parser, audio ring/meter, timer, profiles, completion,
  queue/file accounting, frame timing/selection and the new bitrate tests.
- Bitrate tests passed on ARM and Intel (Rosetta): decimal Mbps conversion,
  video-only accounting, one-second warmup, unfinished-keyframe-bucket exclusion,
  three-second averaging, idle decay, reset and 10,000-bucket wraparound.
- Both application architectures compiled, passed strict signature validation,
  architecture/dependency closure checks, and macOS 26 minimum-OS checks.
- Installed ARM binary hash matched the packaged ARM binary.

## Live device measurements

`Tests/LiveBitrateProbe.swift` uses the production USB bridge, packet parser,
bitrate meter, media converter and preview decoder. Each run lasts ten seconds;
reported rates average the one-second reports after five seconds. The first two
seconds of elementary video were temporarily saved for independent `ffprobe`
inspection, then deleted. These are short, scene-specific observations, not
controlled encoder quality benchmarks or guarantees for all targets/content.

| Codec | Requested Mbps | Measured video Mbps |
|---|---:|---:|
| H.264 | 1 | 1.010 |
| H.264 | 20 | 5.250 |
| H.264 | 200 | 5.241 |
| HEVC | 1 | 0.920 |
| HEVC | 20 | 9.281 |
| HEVC | 140 | 9.254 |

All six completed runs measured 59.94 fps and zero parser discards.
The initial probe lacked the GUI's settling retry and encountered a configuration
timeout on its second connection. Adding that existing retry behavior to the
probe allowed the subsequent runs to complete; production USB code is unchanged.

Independent stream inspection confirmed H.264 High / yuv420p / 8-bit and HEVC
Main 10 / yuv420p10le at 1920×1080. Production preview decode returned `420v`
for AVC and `x420` (10-bit bi-planar video range) for HEVC. HEVC's Core Media
format description also reported ten bits per component.

The low-target response confirms bitrate configuration affects device output.
It does not prove firmware honors every upper target or explain gradient banding.
There is no firmware target readback. High targets did not force correspondingly
high delivered bitrate on this source. Source precision and final display
compositing were not independently established; the banding origin remains open.

## Installed native GUI

- Observed live header reporting received Mbps beside requested 40 Mbps.
- Meter continued updating with video preview disabled.
- Disconnect cleared the reading; reconnect showed measuring, then a fresh value.
- Incoming remained 59.94 fps, cadence cap 30, effective Output 29.97 as expected
  from the user's saved settings. A cadence cap does not command device FPS.
- Saved profile and recording-folder values compared byte-for-byte unchanged.
- Video and audio preview restored, including the previous monitor volume.
- All temporary video samples removed; no user recording was modified.

Intel execution used Rosetta; a physical Intel Mac and USB 2 remain untested.
The prior recording validation remains in VALIDATION-0.5.0.md; the full historical
output matrix was not repeated for this status-display update. No claim is made
that the reported visual banding has been fixed.
