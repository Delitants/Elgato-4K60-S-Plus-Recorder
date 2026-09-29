# Elgato 4K60 S+ Recorder 0.6.7

Recording no longer aborts when the rolling incoming-FPS estimate varies. It
shows a warning and continues using source timestamps and the existing encoder
configuration. True carrier-rate changes fall back from film cadence recovery
to timestamp-based FPS conversion, preserving the output cap.

Preview and NDI now recover the original pictures when the manual 23.976/24 fps
film setting is used with a repeated 59.94/60 fps stream. This fixes phase-dependent
repeated/skipped pictures caused by timestamp-only sampling. Interrupted carrier
timing uses ordinary selection until the film cadence can be reacquired.

Cold helper startup now has bounded grace, avoiding a premature pipe/queue timeout
while the helper loads. Normal recording limits and the memory cap remain in place.

Includes the audio clock, background recording and preview-resume fixes from
previous versions. Real codec/resolution/HDR changes and unrecoverable I/O/encoder
failures can still stop a recording.

## Choose your Mac download

- **macOS-Apple-Silicon.zip** — Macs with Apple M-series chips (arm64).
- **macOS-Intel.zip** — Intel-based Macs (x86_64).

Both downloads require **macOS 26 or later** and are ad-hoc signed, not notarized.
They are for macOS only, not Windows PCs.

[Validation details](https://github.com/Delitants/Elgato-4K60-S-Plus-Recorder/blob/main/docs/VALIDATION-0.6.7.md).
