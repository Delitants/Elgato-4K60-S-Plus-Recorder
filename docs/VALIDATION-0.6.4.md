# 0.6.4 preview restore and audio status validation

Target: M1 Pro, macOS 27, Elgato 4K60 S+ 20GAP9901 on USB 3 at 140 Mbps,
1080p H.264 incoming approximately 59.94 fps, preview cadence cap 23.976 fps.

## Investigation

The first metadata trace reproduced a stale first frame after restore. The
renderer was also fed 927 frames during a 39-second hidden interval. Capture
and decoding initially continued normally while the UI paused during window
animations.

Suspending/flushing the hidden renderer fixed that path, but a longer test
exposed a second cause. RunningBoard activated App Nap at 20:37:58 for the
live-preview process, enabling CPU, disk and timer throttling. On restore,
5.42 seconds of source video arrived in 2.99 seconds of wall time. The new
regression rejected that 1.82x transport catch-up burst.

Active USB capture now holds a user-initiated activity allowing idle system
sleep. A defer releases it on every capture-worker exit. The separate recording
activity continues to prevent idle sleep until recording finalization finishes.
No permanent system power settings are changed.

The audio regression reproduced empty USB polling windows being mistaken for
silent PCM. Meter publication now waits for samples or a bounded no-input timeout;
actual silent PCM still updates it promptly. The text indicator holds recent sound
for 750 ms independently of the meter, avoiding flicker between brief pauses.

## Reproduce the metadata check

Build with `-D PREVIEW_DIAGNOSTICS -D CAPTURE_DIAGNOSTICS`, leave video preview on,
minimize the native window for at least a minute, then restore and leave it visible
for at least five seconds. The diagnostic build emits timing/level metadata only
into `$TMPDIR/ElgatoPreviewTrace.json`; it does not save media. The event buffer is
bounded, so start a fresh connection for each long test.

Run `python3 Tests/PreviewVisibilityTraceTests.py "$TMPDIR/ElgatoPreviewTrace.json"`.
It checks that hidden windows receive no renderer enqueues, the first restored frame
is fresh, incoming video returns at real-time speed, and presentation deadlines
preserve media timing. `bash test.sh` covers the independent audio/pacing/recording
regressions. Normal release builds omit diagnostic tracing.

Apple's documented [activity option](https://developer.apple.com/documentation/foundation/processinfo/activityoptions/userinitiatedallowingidlesystemsleep)
allows idle system sleep; its [process activity guidance](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/PrioritizeWorkAtTheAppLevel.html)
explains App Nap prevention for user-initiated work.

## Final results

The final ARM64 diagnostic candidate passed two real minimize/restore cycles.
The longer cycle remained minimized for 83.18 seconds. USB source timestamps
advanced at 1.0005x wall-clock speed over the first three seconds after restore,
versus the failing 1.82x burst before the capture activity change. The renderer
scheduled 72 frames at the selected 23.976 fps cadence in that interval, with
only the initial clock reset. No frames were enqueued while hidden. The first
restored frame matched the live edge; presentation deadlines preserved source
timing. The native UI reported zero parser discards.

RunningBoard reported App Nap inactive for the capture process while minimized.
Power assertions showed no idle-system-sleep assertion owned by this preview-only
process. The separate 0.6.3 recording activity remains covered by the regression
suite.

The complete core test suite passed, including real macOS recording assertion
cleanup, audio ring, meter/signal transitions, frame selection, timing, parser,
queue and profile checks. Existing SDK deprecation warnings remain. Both release
bundles passed architecture, dependency-closure, minimum-macOS and strict ad-hoc
signature checks; both ZIPs passed integrity checks.

This validation used the connected 1080p device on Apple Silicon. Native Intel,
4K/HDR restore performance and a new long recording soak were not tested. No test
recordings were created for this update; temporary diagnostic apps and compiler
caches were removed after deployment.
