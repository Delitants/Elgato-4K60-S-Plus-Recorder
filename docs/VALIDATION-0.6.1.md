# Version 0.6.1 preview pacing validation

Tested September 27–28, 2026 on M1 Pro, macOS 27, with the connected
Elgato 4K60 S+ 20GAP9901 on USB 3 at 5 Gbps.

## Investigation

A separate diagnostic build recorded only timestamps, byte counts and renderer
counters. No video or audio recording was created. The installed 0.6.0 release
was left intact while this copy was tested.

The prior short capture/decode probe measured average FPS but did not evaluate
presentation cadence. Instrumentation was added at compressed-frame ingestion,
decode completion, frame selection, UI refresh, enqueue and renderer metrics.
It is excluded from production unless PREVIEW_DIAGNOSTICS is defined.

The original app set DisplayImmediately and polled a one-frame mailbox. This
preserved low latency but made display follow arrival jitter rather than PTS;
a later decoded frame could also replace an unconsumed frame during a burst.
At a 200 Mbps target, the baseline averaged 145 Mbps and about 60 input frames/s.
Hardware decode was typically 6–8 ms, not an accumulating decoder backlog.
Selected 25 fps timestamps were uniformly 40 ms apart, but immediate enqueue
intervals varied around 33–67 ms. The 95th-percentile timing error was 24.01 ms.
The 40 Mbps comparison showed the same architectural problem, so it was not
isolated to high USB throughput. UI interaction also caused a separate brief
main-thread stall; that event is not attributed to USB.

## Change

Preview uses a host-clock mapping of media timestamps and a 60 ms initial
scheduling cushion. Decoded frames wait in bounded queues, each limited to eight
frames and 120 ms of media. Renderer backpressure retains frames for retry on
the next refresh. A late/discontinuous timeline is restarted instead of allowing
indefinite delay; scheduled deadlines are limited to 200 ms ahead of the current
host time. These are software scheduling bounds, not a measurement of total
HDMI-to-screen latency. Clear/toggle/reconnect reset the presentation state.

Recording, USB controls, decoder choice, FPS selection and NDI timing are unchanged.
The selected output FPS still applies to preview; 59.94 to 25 fps drops source
frames with uneven selection cadence and cannot synthesize motion interpolation.

## Regression and live evidence

- The trace regression failed on the original 200 Mbps run with 24.01 ms p95
  cadence error. The first paced trial exposed two skipped slots from renderer
  backpressure; a stricter maximum-gap assertion failed by 40 ms. Retrying those
  frames fixed the second defect.
- Unit tests cover burst jitter, 25/29.97/59.94 timing, bounded queue retention,
  duplicate/invalid timestamps, backward/forward discontinuities, long stalls
  and reset. ARM and Intel/Rosetta executions passed.
- Full test.sh passed. Read-only code review checked the clock, queue ownership
  and retry path; its renderer-clear recommendation was implemented.
- Final high-target run: 125 seconds total, about 118 seconds after warmup,
  151.3 Mbps average, 59.94 incoming frames/s and 25 selected frames/s.
  All 2,957 scheduled preview frames passed the complete post-warmup trace
  assertion, with no skipped slots and <0.001 ms cadence error. Two not-ready
  renderer attempts were retried successfully. Renderer counters reported zero
  dropped frames and effectively zero accumulated display delay.
- An earlier 55-second final-build run averaged 137 Mbps, also with no skipped
  presentation slots. Decode latency was below 12 ms in that sample.
- Final 40 Mbps comparison averaged 40.1 Mbps. All 817 scheduled frames in the
  post-warmup interval passed the maximum-gap assertion; six temporary not-ready
  attempts were retried, and the renderer drop counter did not increase.
- Full-rate 59.94 fps preview at a 200 Mbps target averaged 141.4 Mbps. All 3,108
  selected frames in the measured interval were scheduled; 355 backpressure
  attempts were retried, with no timeline resets or missing interior frames.
  One renderer drop occurred during startup/reconfiguration; its counter stayed
  unchanged throughout the measured post-warmup interval.
- Production ARM app was installed after preserving the old release for rollback;
  its executable/helper hashes matched the audited release bundle. Native UI
  verified live capture, preview clear/resume, and restored recording settings,
  folder, timer, audio toggle and monitor volume.

Renderer metrics and deadlines are evidence of scheduled presentation, not an
independent camera measurement of the physical display. Motion smoothness also
depends on source content cadence, chosen output FPS and display refresh rate.
No claim is made that reducing 59.94 fps to 25 fps retains every motion frame.

Both production architectures build without diagnostic logging. Physical Intel,
USB 2, HDMI end-to-end latency and long-term audiovisual synchronization remain
unverified. This change does not resolve the previously reported gradient banding.
