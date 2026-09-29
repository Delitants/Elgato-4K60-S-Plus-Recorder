# Elgato 4K60 S+ Recorder 0.6.3

Fixes recording stopping with “Recording cannot keep up” after the app is left
in the background or minimized and macOS activates App Nap.

The recorder now holds a user-initiated macOS activity from recording startup
through final file completion. This prevents App Nap and idle system sleep while
recording. The display can still sleep. The activity is released after success,
failure, or recorder cleanup. No permanent power settings are changed.

Video/audio settings, picture-cadence recovery and bounded recording queue limits
are unchanged. A real encoder or storage stall can still stop recording safely.

Separate Apple Silicon and Intel builds require macOS 26 or later. Hardware CQ
remains Apple Silicon only. Both apps are ad-hoc signed, not notarized.

See [validation details](https://github.com/Delitants/Elgato-4K60-S-Plus-Recorder/blob/main/docs/VALIDATION-0.6.3.md).
