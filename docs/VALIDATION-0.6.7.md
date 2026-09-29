# 0.6.7 recording-rate recovery and film preview

## Reported stop

The v0.6.6 window reported “Incoming frame rate changed” after 27:02. The file
was finalized at 1622.152 seconds, with 23.976 fps H.264 and stereo AAC. Its final
15 seconds decoded without errors. The original recording was left unchanged.

`RecordingSink` stopped on any rolling FPS estimate more than 1% from the initial
estimate. That estimate is derived from timestamps, not a verified HDMI mode
change. The failure screenshot does not retain the exact triggering timestamps,
so it cannot establish whether that individual excursion was jitter or a source
change. The unconditional stop was reproduced through the real Swift recording
sink using controlled timestamp changes.

It now retains the encoder configuration, preserves source timestamps, and shows
a persistent warning. Native MOV, helper stream-copy MKV, and film-transcoded MKV
continue through temporary 56 fps timing and a 59.94→30→59.94 transition. Tests
check finalization, decoding, monotonic A/V timestamps, output duration, preservation
of compressed frames in copy mode, and the 23.976 cap after a real rate change.
Actual codec/resolution/HDR changes remain separate format guards.

## Preview picture selection

Timestamp-only 59.94→23.976 selection could choose picture IDs `0,2,2,4,4,…` for
one phase of progressive 3:2 repeats. A decoded-pixel regression reproduced it.
Preview and NDI now use the same phase-detection algorithm as recording, retaining
at most five carrier frames and selecting the two original pictures. This is
not motion interpolation. It is enabled only with the matching manual film cap.

Tests cover all five phases in 8- and 10-bit buffers, static-to-motion transitions,
large gaps, timestamp resets, ordinary full-rate motion, and recurring missing
carrier frames. Interrupted cadence falls back to timestamp selection and resumes
film grouping after stable input. A review caught and the test reproduced the
otherwise possible indefinite wait for five frames when every fourth/fifth
carrier was missing.

A metadata-only live trace showed the 3:2 pattern. The corrected preview scheduled
1,612 frames over 67.15 seconds, with presentation intervals 41.476–42.022 ms,
zero clock resets, and no intervals above 65 ms. These are scheduling measurements,
not a measurement of HDMI-to-display latency or a guarantee of subjective motion
quality for all content.

## Real device jitter regression

An early candidate used a single short interval to trigger film fallback. The
live test exposed excessive recovery warnings. Timestamp-only diagnostics showed
valid ~9.95–21.91 ms intervals in an otherwise 59.94 Hz stream. The captured numeric
fixture is retained in `Tests/Fixtures/film-carrier-timestamps.json`; it contains
no images, audio or encoded media.

Both the preview and helper regressions failed on this fixture before correction.
Short intervals now remain within cadence recovery; sustained faster/slower
carrier rates are distinguished from isolated jitter. The real-jitter picture
sequence and FPS-cap regressions pass.

## Cold helper startup

The Intel Swift-to-helper check exposed a separate cold-start issue under Rosetta:
a pipe write waited 2.66 seconds while the original timeout allowed only two.
The partial write caused a truncated IPC error. A three-second delay around the
real helper reproduced this on Apple Silicon too. Continuing fixture input while
the helper was delayed also reproduced the recording queue's two-second age stop.

Helper recordings now allow up to ten seconds of initial queue/pipe grace. The
queue retains its 64 MiB hard limit throughout; the grace does not renew when the
queue drains, and normal two-second bounds resume afterward. Tests exercise both
normal startup and a delayed real helper with ongoing offers, then decode the
result and verify packet counts, timestamps, duration and film output caps.

## Other checks

The core suite, FPS/film/split suite, audio-recovery regressions, codec/container
matrix, and bundled NDI sender/receiver checks passed. NDI received video and
audio with zero incorrect FPS metadata. The native Swift-to-helper rate/recovery tests passed in both ARM64 and x86_64
builds, including paced input across the three-second helper delay. Intel tests
ran through Rosetta; physical Intel hardware is not available. Existing SDK deprecation warnings remain.

Both release bundles are audited for architecture, dependency closure, minimum
macOS deployment version and strict ad-hoc signatures. They are not notarized.

## Extended live test

The 55-minute timer completed on the connected 4K60 S+ at 1080p, H.264 capture
requested at 140 Mbps, hardware decoding/encoding, H.264 CQ 63, 23.976 fps film
output, AAC 128 kbps and MKV. The app reported **Recording saved**, with zero
discards. The window was minimized from 5:56 until 54:59, including a period with
the Mac locked. It was restored before the automatic stop and displayed live video.

The old failure condition occurred during this run: the rolling estimate moved
from 59.94 to 60.549 fps. It produced a persistent warning and recording continued.
One audio-clock drift correction also produced a warning without interrupting capture.

- Final duration: **3299.826 seconds**; file size: **1,013,015,528 bytes**.
- **79,120 video packets** and **154,680 AAC packets**, with strictly increasing
  PTS/DTS. Maximum packet spacing was 45 ms for video and 22 ms for audio.
- The audio/video end-time difference was **59 ms**.
- The complete file decoded while growing, with zero errors. Its finalized last
  15 seconds also passed a seek-and-decode check.
- Observed RSS stayed within 51.5–126.0 MiB for the app and 64.7–98.7 MiB for
  its recording helper. These observations do not guarantee unlimited-duration stability.

The startup-only queue/pipe allowance was added while this soak was running.
The final release's recording helper is byte-identical to the soak helper; the
preview/cadence code is unchanged. The final installed app also passed a separate
30.046-second live hardware recording, automatic stop and complete A/V decode.
Applications contains v0.6.7 build 16, with its signature and full bundle contents
verified against the release. The app was reopened with the original save folder,
55-minute timer, video preview on, audio preview off and volume 0.7. Both final
test recordings were deleted (1,019,796,978 bytes); the original user recording
was preserved. No subjective preview-smoothness confirmation
has been received from the user; decoded-pixel and scheduling results are reported above.
