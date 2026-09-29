# Elgato 4K60 S+ Recorder 0.6.4

Fixes stale, jerky preview playback when restoring a minimized or hidden window.
Video presentation now stops and flushes while the window is not visible, then
resumes from the newest decoded frame. A stalled UI timer also discards its
stale preview batch. Recording and audio monitoring remain independent.

Active USB capture now prevents App Nap even when not recording, avoiding a
transport backlog that would burst through after restoring the window. Idle
system sleep remains allowed outside recording; disconnecting releases this
activity.

The HDMI audio status no longer flickers when a USB polling interval contains
no new PCM packet. Actual silent PCM still updates the stereo meter promptly;
the signal label holds recent audible activity for 750 ms before showing silence.

Includes the 0.6.3 App Nap protection during recording and finalization. Encoder,
file format, recording cadence and queue limits are unchanged.

Separate Apple Silicon and Intel builds require macOS 26 or later. Hardware CQ
remains Apple Silicon only. Both apps are ad-hoc signed, not notarized.

See [validation details](https://github.com/Delitants/Elgato-4K60-S-Plus-Recorder/blob/main/docs/VALIDATION-0.6.4.md).
