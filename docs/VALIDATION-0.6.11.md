# 0.6.11 validation

MP4 fast start is automatic and limited to the MP4 container. Single-file FFmpeg output uses `movflags=+faststart`; the native AVAssetWriter uses `shouldOptimizeForNetworkUse`. MOV, MKV and MPEG-TS keep their existing policies.

Short generated H.264/PCM fixtures exercised the actual release helper on Apple Silicon and the Intel helper under Rosetta. MP4 atom parsing confirms `moov` before `mdat`; MOV retains its end metadata. Full decoding and seeking pass. Decoded video/audio frame hashes match between equivalent MOV and MP4 outputs.

For split MP4, a test inspects a completed part while capture is still open and confirms no relocation occurs then. After Stop, each part has front metadata, with identical decoded content and timestamps. A separate helper compiled with an injected final output-close failure verifies warning-only fallback, intact playable originals, and temporary-file cleanup. The original upstream utility incorrectly returned success for that injected failure before the local close check was added. The embedded optimizer has no child process that can outlive the recorder backend.

Native MOV and MP4 fixtures pass full decoding and atom-order checks using the macOS AAC encoder. Watchdog tests cover complete protocol lines, paths with spaces, same-size file writes, continuing progress beyond 30 seconds, and stalled-progress expiry.

The existing core suite passed. MKV regression tests pass for the option off/on, time and size splits, salvage, and front-index capacity fallback. Both release bundles pass strict signature, architecture, dependency-closure, and minimum-macOS audits. The Intel helper was exercised under Rosetta, not on a physical Intel Mac.

Split optimization runs after Stop and needs temporary space for one part. A normal optimization failure retains the original and removes its temporary copy. Forced process termination can leave an unfinished temporary copy alongside the intact original. The progress watchdog uses observed file size and modification time; no long-duration soak or large-file benchmark was run.

The installed Apple Silicon app visibly reports v0.6.11 (build 20), and the Output page explains automatic MP4 fast start. The existing MKV profile was preserved. The capture device could not be opened during this check.

All generated test recordings were deleted. No live HDMI recording or LG TV/DLNA playback was tested for this change.
