# 0.5.0 validation — 2026-09-27

Test host: Apple M1 Pro, macOS 27.0. Device: Elgato 4K60 S+ 20GAP9901,
USB 0fd9:0075, negotiated USB 3.0 / 5 Gbps. Intel execution used Rosetta.

## FPS cadence regression

A new regression checks decoded frame contents as well as FPS metadata. With
jittered device timestamps, the old helper selected frames 0, 3, 4, 7, 8… for
60→30 conversion even though its output advertised 30 fps. Both the Swift
selection test and the old installed helper reproduced the failure.

The corrected implementation quantizes the device timestamp to the measured
source cadence before selecting output intervals. The following cases passed on
both ARM and Intel helper binaries: 60→30, 59.94→29.97, 60→24, 60→25, 60→50,
and 60→60. Each test checks exact decoded source-frame content using lossless
x264 output, evenly spaced output timestamps, and byte-identical stereo PCM.
Fixtures are generated in temporary directories and removed on exit.

The existing FPS suite also passed for both architectures, including fractional
rates, no upsampling, passthrough, compressed-downsampling rejection, splitting
and unaligned keyframes with continuous PCM. These checks establish correct
selection and timing, not motion interpolation. Non-divisible rates still have
the cadence inherent in selecting original frames.

## Live installed application

- Installed 0.5.0 was tested with hardware H.264 High, CBR 8 Mbps, 29.97 fps,
  AAC stereo 48 kHz and MKV; encoded input was 1080p59.94.
- Started without a timer. Enabled Stop after at elapsed 31 seconds, changed the
  total to 60 seconds, and observed 24 seconds remaining at elapsed 36.
- Disabled the timer at elapsed 45 and enabled it again at elapsed 50; 10 seconds
  remained. It stopped at the original 60-second recording deadline.
- Result: 1,799 H.264 frames at 30000/1001 fps, duration including audio 60.063 s,
  59,586,441 bytes. Full decode returned no errors. All adjacent video timestamps
  were 33 or 34 ms, as expected at Matroska's timestamp precision for 29.97 fps.
- The UI showed 59 MB written after finalization, matching the integer decimal-MB
  file size. Capture reported zero parser discards.
- Native UI inspection confirmed the header icon, blue negotiated USB badge,
  Audio preview label, bitrate dropdown, software effort choices and fitting
  settings layout. The source was silent during this run; audible monitoring
  and active-meter visual response were not independently verified with live sound.
- Restored the user's external save folder, hardware profile and disabled timer.
  The 59.6 MB test recording was deleted after verification.

## Regression and packaging checks

- Full Swift test.sh passed, including live deadline edits, meter channel/peak
  calculations and 20 ms publication, file-size/split accounting, queue bounds,
  parser, audio ring, profiles, completion and frame timing.
- Codec/control helper integration passed on ARM. Intel passed the available
  cases; required hardware HEVC reported unavailable (-12908) under Rosetta and
  is explicitly not counted as a successful hardware test.
- Both bundles passed signature, architecture, dependency closure and minimum
  macOS 26 audits. Read-only code review found no blocking issues.
- No physical Intel, USB 2 capture, macOS 26 runtime or extended soak validation
  was performed. USB 2 capture remains rejected. The prior 949-case output audit
  belongs to 0.4.1 and was not repeated in full for this update.

## Reproduce

```sh
bash test.sh
MEDIA_HELPER='/path/to/Elgato Recorder.app/Contents/MacOS/MediaHelper' bash test-fps.sh
MEDIA_HELPER='/path/to/Elgato Recorder.app/Contents/MacOS/MediaHelper' bash test-advanced.sh
python3 Tests/JitterCadenceIntegration.py '/path/to/Elgato Recorder.app/Contents/MacOS/MediaHelper'
```

For Intel execution under Rosetta, ALLOW_UNAVAILABLE_HW=1 allows the integration
runner to report known unavailable required-hardware encoders separately; it does
not turn those cases into passes.
