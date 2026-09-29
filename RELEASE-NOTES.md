# Elgato 4K60 S+ Recorder 0.6.2

Fixes repeating picture skips when recording 23.976 fps film carried inside a
59.94 fps device stream. Previously, downsampling that stream blindly to 25 fps
could repeat some original pictures and omit others even though file timestamps
were perfectly regular.

Select **Capture → Source content cadence / cap → 23.976 fps** and **Video →
Output FPS → Match incoming stream** (or 23.976). Select a video encoder rather
than Original device stream. Use 24 fps for 24-in-60 content.

- Recording recovers the progressive 3:2 picture sequence with bounded buffering.
- Cadence acquisition handles recording start and static openings.
- Recovered timestamps follow the device clock to prevent accumulated A/V drift.
- Audio samples and recording split boundaries are preserved.

Recovery is specific to stable progressive 3:2 repeats. Preview/NDI keep the normal
FPS cap; this does not perform motion interpolation, reconstruct missing source
frames, or repair an existing recording. Automatic remains the default.

Separate Apple Silicon and Intel builds require macOS 26 or later. Hardware CQ
remains Apple Silicon only. Both are ad-hoc signed, not notarized.

See [validation details](https://github.com/Delitants/Elgato-4K60-S-Plus-Recorder/blob/main/docs/VALIDATION-0.6.2.md).
