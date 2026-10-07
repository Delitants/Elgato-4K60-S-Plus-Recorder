# 0.6.13 — Hardware CQ with explicit H.264 levels

## Reproduction and cause

The user reported a 53-minute MP4 at over 30 Mbps/12 GB, compared with an older
45–50-minute MKV under 1 GB. The older recording used Auto H.264 level; the
new recording used level 4.1, hardware CQ 62, Main profile, two-second keyframes
and spatial AQ enabled. The original recordings were not inspected.

Identical generated 1920×1080/23.976 fps input reproduced a bitrate regression:

| Hardware CQ 62 configuration | Encoded video bytes, 96 frames |
| --- | ---: |
| Auto level, MP4 | 2,915,654 |
| Auto level, MKV | 2,915,654 |
| 0.6.12 level 4.1, MP4 | 6,335,329 |
| 0.6.12 level 4.1, MKV | 6,335,329 |

The containers carried equal video payload sizes. Independent changes to
profile, keyframe interval and spatial AQ did not explain the increase.
Removing only the added rate-limit control restored 2,915,654 video bytes
while retaining level 4.1. Removing only the reference-frame limit did not.

Version 0.6.12 set `rc_max_rate` for explicit H.264 levels. FFmpeg maps this
to VideoToolbox `DataRateLimits`. Apple documents in `VTCompressionProperties.h`
that a rate limit without `AverageBitRate` creates an implicit average bitrate
target below the limit. This interfered with CQ, where no average bitrate is set.

## Correction

Hardware H.264 CQ retains the requested VideoToolbox profile/level and encoded
SPS verification, without adding a separate rate-limit property. Software
encoding and hardware ABR/CBR retain their existing bitrate-limit behavior.
Dimension/FPS checks and reference-frame limits remain in place. UI help now
explains that a level is a compatibility setting, not a CQ bitrate target.

`Tests/HardwareCQLevel.py` failed against the installed 0.6.12 helper with a
2.173× size increase. It compares MP4/MKV video payloads, Auto/explicit level,
frame counts, encoded level and complete decode using temporary generated media.

## Scope

This isolates an encoder-control regression; it does not measure the exact
size reduction for the user's recordings. CQ still has scene-dependent size.
No full-length recording or LG/DLNA playback test was performed. Existing
recordings are not modified. Test recordings are deleted automatically.

## Release checks

- The corrected packaged ARM helper produced 2,915,654 video bytes in all four
  Auto/4.1 × MP4/MKV cases. Frame counts, level 4.1 SPS and full decode passed.
- The complete H.264 level integration suite passed: all nine levels and four
  profiles with ARM software/hardware encoders, four containers, rate-control
  variants, invalid-setting guards, Full HD 30/60 fps boundaries and DPB limits.
- The existing core regression suite passed, including parser, timing, audio,
  recording assertions, preview and window lifecycle tests.
- Apple Silicon and Intel builds passed strict signatures, bundled dependency,
  architecture and minimum-OS audits. ZIP integrity checks passed.
- The installed app was visually verified as 0.6.13 (build 22), native ARM64.

Intel hardware CQ remains unsupported; the Intel package was build/audit checked
without running it under Rosetta for this correction. Hardware CQ validation
used Apple Silicon on macOS 27. Test/compiler builds retain existing deprecation
and unqualified `std::move` warnings.

A brief installed-app recording using the user's unchanged settings finalized
successfully: MP4, H.264 Main level 4.1, 1920×1080, 24000/1001 fps, 339 frames,
AAC-LC, 14.136 seconds and 571,494 bytes. Complete decode passed; the UI reported
zero discarded packets. The scene was largely static with silent audio, so its
0.323 Mbps total bitrate is not a movie-size prediction. The disposable file
was deleted after inspection.
