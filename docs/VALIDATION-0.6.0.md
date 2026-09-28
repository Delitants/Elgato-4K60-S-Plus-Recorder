# Version 0.6.0 validation

Tested September 27, 2026 on an Apple M1 Pro running macOS 27.0 with the
connected Elgato 4K60 S+ model 20GAP9901, USB 3 at 5 Gbps.

## Scope and implementation

Hardware constant quality is a separate CQ mode for H.264/HEVC recording.
The helper sets FFmpeg QSCALE and global quality, clears the bitrate target and
disallows software fallback. The bundled VideoToolbox implementation maps this
to Apple's Quality property only on native ARM. Intel recording rejects CQ
before creating output, while saved settings remain loadable.

Hardware quality is independently persisted (default 65, range 0–100).
Inactive bitrate/CRF fields do not block CQ; an extreme inactive bitrate is sent
as zero before any multiplication. Existing ABR/CBR/CRF meanings are preserved.
No USB protocol, decoder or frame selection algorithm was changed.

## Automated verification

- Full `test.sh` passed, including profile migration, separate quality values,
  helper routing, codec/platform restrictions and inactive-field boundaries.
- CQ profile tests passed on ARM and Intel under Rosetta.
- `Tests/HardwareCQIntegration.py` exercised the production helper with temporary
  synthetic video/audio. On the prior helper, CQ 20 and 80 produced identical
  output, establishing a failing regression case. The updated helper produced
  the following results (PSNR compares aligned decoded frames):

| Hardware codec | CQ 20 bytes | CQ 80 bytes | CQ 20 PSNR | CQ 80 PSNR |
|---|---:|---:|---:|---:|
| H.264 | 78,211 | 462,350 | 33.364 dB | 53.703 dB |
| HEVC | 44,136 | 456,523 | 32.233 dB | 52.986 dB |

These two-second 640×360 synthetic cases verify that quality affects encoding;
they do not establish visual transparency or storage savings for arbitrary input.

- Integration passed MOV, MP4, MKV and MPEG-TS, CQ endpoints 0/100, HEVC Main 10,
  and downsampling 30 to 15 fps. Encoded outputs passed full decoding.
- Unsupported copy/software/ProRes and invalid quality settings failed without
  creating a recording. Intel explicitly rejected CQ for both hardware codecs.
- Existing advanced recording and FPS suites passed on ARM. Advanced Intel tests
  passed applicable cases under Rosetta; required hardware HEVC was unavailable
  there with VideoToolbox error -12908, an existing platform limitation.
- Both release architectures built and passed strict signatures, dependency
  closure and minimum macOS 26 checks. Installed ARM executable/helper matched
  the release build.
- Read-only code review found an inactive-bitrate overflow edge case. It was
  fixed with a CQ zero-bitrate guard and an Int.max regression test; follow-up
  review found no remaining actionable issue.

The historical full output-combination matrix was not repeated.

## Native application and real-device recording

- Confirmed CQ is selectable for hardware H.264 on ARM. CQ enables hardware
  quality and disables bitrate/software CRF; ABR restores the appropriate fields.
- Applying CQ 101 displayed validation feedback; CQ 65 persisted correctly.
- Recorded through the installed GUI using hardware H.264 CQ 65, AAC 192 kbps,
  MKV, output 29.97 fps and an eight-second stop timer. Input was 1080p AVC with
  requested device target 200 Mbps.
- App reported recording saved with zero parser discards. Independent inspection
  found 8.049 seconds, 3,475,605 bytes, 241 H.264 frames at 30000/1001 and AAC audio.
  Full-file decoding completed without error.
- Restored the user's previous ABR profile, recording folder, preview preferences,
  monitoring volume and timer. Temporary recordings were deleted.

## High-input-bitrate preview investigation

`Tests/LivePreviewTimingProbe.swift` uses production capture/decode and saves no
media. Two 22-second runs requested 200 and 40 Mbps with a 29.97 fps preview cap.
After startup, the 200 Mbps run received approximately 94–123 Mbps, 58–61 input
frames/s and 29.8–30.2 preview frames/s. Relative presentation-timestamp to host
arrival delay stayed within about 25 ms rather than accumulating. The 40 Mbps
run received approximately 40–41 Mbps with comparable cadence and zero discards.

These measurements did not reproduce a sustained 139 Mbps reading, do not measure
GPU/display presentation, and do not establish that the reported stutter is fixed.
A single process CPU sample is insufficient to rule out CPU/GPU pressure. CQ
reduces output according to scene complexity; it does not reduce incoming traffic.

Physical Intel hardware, USB 2, real HDR HDMI capture, long-duration lip sync,
endurance, disk-full and unplug recovery remain unverified. Gradient banding's
source-versus-display origin also remains open.
