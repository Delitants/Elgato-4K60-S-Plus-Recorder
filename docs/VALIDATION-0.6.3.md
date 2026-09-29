# 0.6.3 background recording validation

The reported MKV finalized at 382.004 seconds. It decoded without errors. The
app's two-second recording queue guard stopped further capture; the app process
itself remained alive. VideoToolbox logs reported zero dropped encoder/decoder
frames at finalization.

RunningBoard logs showed App Nap becoming active for the recording app at
19:49:28, with CPU, disk, priority and timer throttling enabled. The user confirmed
the app was in the background/minimized and the Mac stayed awake. The app had no
recording-specific process activity to prevent App Nap.

The fix acquires a user-initiated NSProcessInfo activity after profile validation
and retains it through media-queue drain and helper/native file finalization.
Cleanup releases it on error and abandonment as well. Encoding, cadence, queue
capacity and timeout limits are unchanged.

The new regression failed before the fix because no actual macOS recording
assertion existed. It passes with the fix, querying IOPM assertions to verify
acquisition, both native/helper failed-start cleanup, abandonment and rejection
of invalid settings. The full core regression suite also passes.

A separate controlled 2.5-second pause of a diagnostic helper reproduced a
short-timeout failure. That was a fault-injection experiment, not the cause of
the user's original failure, and is not claimed to be supported by this update.

## Background recording result

The production ARM64 candidate recorded for the full ten-minute timer with its
window minimized, using the user's hardware H.264 CQ 63 / AAC / MKV profile and
the same external SSD. The file contained 14,386 video frames at 24000/1001 fps,
lasted 600.033 seconds and occupied 159,545,267 bytes. Video intervals were 41–43
ms without holes; audio remained continuous through the end. A full software
decode completed without errors. The UI reported zero parser discards.

The source was initially relatively static, then moving content was confirmed by
decoded picture comparisons during the test. At completion, incoming video bitrate
was 139.6 Mbps against the unchanged 140 Mbps target. This is a ten-minute test,
not proof of a full 55-minute or overnight recording.

Process/power monitoring confirmed the recording activity throughout the sampled
run and its release after automatic finalization. RunningBoard reported App Nap
inactive with CPU, disk and timer throttling prevented for the background app.
Both ARM64 and x86_64 bundles passed architecture, dependency-closure, minimum-OS
and strict ad-hoc signature checks. Native Intel recording was not tested.

The original 6:22 recording was inspected read-only and preserved. All recordings
created for diagnosis/validation were removed afterward.
