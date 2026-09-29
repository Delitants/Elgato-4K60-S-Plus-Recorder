# 0.6.2 recording cadence validation

## Diagnosis

The reported 44.282-second MKV contained 1,106 H.264 frames at 25 fps. Every
adjacent video timestamp differed by exactly 40 ms, and the file decoded without
errors. Picture comparison during motion showed periodic repeats and larger
motion jumps despite that regular timeline.

A separate 12-second sample from the connected 4K60 S+ contained 721 frames with
no parser discards. Device timestamps measured approximately 59.943 fps. Decoded
pictures revealed progressive 3:2 repetition of approximately 23.976 fps content.
The previous frame-rate selector sampled the carrier without identifying those
repeats, creating repeated/skipped film pictures at a 25 fps output setting.

## Regression coverage

- Lossless picture-ID fixtures at all five possible 3:2 phases: consecutive
  source-picture IDs from startup, including a static-opening acquisition test.
- H.264 and HEVC 10-bit input coverage.
- Exact PCM preservation and independently decodable split files with the same
  picture sequence as an unsplit recording.
- Four combinations of 59.94/60 carrier and 23.976/24 output clock over a simulated
  hour: recovered cycle anchors stay within 2 ms of device time, including jitter.
  This is a clock simulation, not a one-hour hardware recording.
- Existing FPS, passthrough, gap, preview pacing, parser, queue, audio and profile
  regression suites.
- Captured-device replay using both software and Apple hardware decoding/encoding:
  721 carrier frames produce 289 pictures with no repeated/skipped picture IDs
  under nearest-picture comparison. All 577,345 test PCM samples are unchanged.
  Replay audio is a known PCM fixture, not a claim about the original HDMI audio.

## Scope

This is progressive repeated-picture recovery for recording. It does not implement
interlaced inverse telecine or motion interpolation, alter HDMI timing, recover
pictures already missing from an existing recording, or apply film recovery to
preview/NDI. Use the explicit 23.976/24 source-content selection with matching
effective output cadence. Clear motion establishes phase; fully static images
cannot identify their original cadence. Intel binaries are cross-built on Apple
Silicon; native Intel hardware capture has not been tested.

## Installed app check

The production ARM64 app was installed in Applications and recorded directly from
the connected device using hardware H.264 CQ 63, AAC, MKV and a 23.976 fps source
content cadence. The 12-second timer finalized a 2,995,471-byte recording containing
288 video frames at 24000/1001 fps, with 41/42 ms Matroska timestamp intervals.
Video and audio decoded without errors; the app reported zero parser discards.
The original external save folder and 55-minute timer were restored. Only source
content cadence and output-FPS profile fields changed. Temporary test media was
removed after analysis; the user-supplied recording was preserved.

ARM64 and x86_64 bundles passed dependency-closure, architecture, macOS minimum
version and strict ad-hoc signature audits. Native Intel execution remains untested.
