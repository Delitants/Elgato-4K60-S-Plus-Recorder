# Elgato 4K60 S+ Recorder 0.6.11

MP4 output automatically places metadata before media for network playback. The FFmpeg helper uses `movflags=+faststart`; the native writer uses Apple's network optimization. MOV, MKV and MPEG-TS retain their previous behavior.

MP4 split parts are optimized after Stop, keeping file relocation out of live capture. Allow temporary space for one part. Optimization preserves the original until successful replacement; failure warns and retains the playable original. Finalization tracks actual write progress instead of interrupting a large file after a fixed 30 seconds.

Separate **macOS-Apple-Silicon.zip** and **macOS-Intel.zip** downloads. Requires macOS 26+. Ad-hoc signed, not notarized.

[Playback guidance](https://github.com/Delitants/Elgato-4K60-S-Plus-Recorder/blob/main/docs/NETWORK-PLAYBACK.md) · [Validation](https://github.com/Delitants/Elgato-4K60-S-Plus-Recorder/blob/main/docs/VALIDATION-0.6.11.md)
