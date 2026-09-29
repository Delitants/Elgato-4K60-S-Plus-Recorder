# 0.6.9 validation

Target: Apple M1 Pro, Elgato 4K60 S+ (20GAP9901), USB 3 at 5 Gbps.

## Recording recovery

The original failure was a queue rejection, followed by a truncated helper IPC message during shutdown. Historical logs do not identify whether encoding, scheduling, or storage caused the initial stall. The recording activity assertion was active while minimized; App Nap was not established as the cause.

A regression using the real recording sink and media helper reproduced the old abort. With the fix, these forced-stall cases passed: temporary stall after startup, repeated stalls, the 64 MiB capacity limit before the age limit, stop during recovery, stream copy, and a permanently stalled helper with salvage of its partial file. Resumed files passed monotonic A/V timestamp checks and full decode. HEVC input with hardware H.264 constant-quality output passed separately. Intel stream-copy recovery passed under Rosetta; this was not a physical Intel Mac test.

A native GUI recording ran for 6 minutes 37 seconds with both previews disabled and the window minimized, using 1080p H.264 input around 140 Mbps and hardware H.264 constant quality at 23.976 fps with AAC in MKV. A deliberate four-second helper suspension produced a visible warning and recovery, skipping 392 input packets. The saved file was 397.452 seconds, passed full decode, and had the expected approximately 3.7-second A/V gap. The disposable recording was deleted; the user's original recording was preserved.

The planned longer soak was stopped early at the user's request. This validates forced-stall recovery, not immunity to every long-running failure. Pipe closure, a write blocked for 30 seconds, disk/codec failure, and native AVAssetWriter backpressure can still stop recording. Queue bounds remain unchanged; recovery may create a visible/audible gap.

Existing core, audio-clock recovery, and incoming-rate recovery suites passed.

## Timer and controls

The missing standard Edit menu was reproduced by a failing regression. The updated test verifies text-editing shortcuts, a dedicated numeric timer editor without completion/prediction/Writing Tools, and Escape handling. Existing window-close and deferred-quit regressions also passed. The exact reported stuck blank popup was not reproduced; the change removes text suggestion services from the timer field.

Native UI checks confirmed Cmd+A replacement, Escape moving focus out of the timer, and inline validation for incomplete input. A five-second timer recording stopped automatically, decoded completely, and was deleted. The active red button was verified visually.

The Record button uses a bolder label and a red dot with red Stop Recording text while recording is active.

## Packaging

Separate arm64 and x86_64 macOS bundles are built with version 0.6.9, build 18. Bundle audits check executable architectures, linked dependencies, minimum macOS versions, and strict ad-hoc signatures. Dependencies are unchanged from 0.6.8.
