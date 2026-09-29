# Elgato 4K60 S+ Recorder 0.6.9

A recording queue stall no longer immediately ends the recording. The app warns,
drains accepted packets within its existing 64 MiB input limit, and resumes at a
video keyframe. Source timestamps preserve A/V alignment across any skipped
section. The warning reports the backlog and skipped input packet count.

The media helper now tolerates temporary pipe stalls without truncating a message.
A helper that closes its pipe or blocks a write for 30 seconds still triggers
best-effort partial-file finalization. Unrecoverable disk/codec errors and native
AVAssetWriter backpressure can also stop recording.

Timer editing disables text suggestion popups and supports Escape, Select All, and
standard clipboard shortcuts. The Record button is more prominent and shows a red
dot with red Stop Recording text while recording.

Includes the window-close fix from 0.6.8 and timing recovery from 0.6.7.

## Choose your Mac download

- **macOS-Apple-Silicon.zip** — Macs with Apple M-series chips (arm64).
- **macOS-Intel.zip** — Intel-based Macs (x86_64).

Requires **macOS 26 or later**. Ad-hoc signed, not notarized. macOS only.

[Validation details](https://github.com/Delitants/Elgato-4K60-S-Plus-Recorder/blob/main/docs/VALIDATION-0.6.9.md).
