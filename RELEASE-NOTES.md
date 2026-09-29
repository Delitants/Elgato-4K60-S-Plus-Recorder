# Elgato 4K60 S+ Recorder 0.6.8

Fixes a crash when closing the main window. The window stays owned until shutdown
completes, UI refresh stops immediately, and queued callbacks cannot access the
closed UI. Closing the window or choosing Quit still waits for an active recording
to finish writing before the app exits.

Includes the recording-rate recovery and film-preview fixes from 0.6.7.

## Choose your Mac download

- **macOS-Apple-Silicon.zip** — Macs with Apple M-series chips (arm64).
- **macOS-Intel.zip** — Intel-based Macs (x86_64).

Requires **macOS 26 or later**. Ad-hoc signed, not notarized. macOS only.

[Validation details](https://github.com/Delitants/Elgato-4K60-S-Plus-Recorder/blob/main/docs/VALIDATION-0.6.8.md).
