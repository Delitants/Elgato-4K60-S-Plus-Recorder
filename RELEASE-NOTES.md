# Elgato Recorder 0.3.0 (experimental)

Native macOS recording for Elgato Game Capture 4K60 S+ (20GAP9901).
Choose the separate **arm64** (Apple Silicon) or **x86_64** (Intel) ZIP.
Requires **macOS 26+**. The recorder includes its dependencies and NDI runtime.

- 1080p/4K capture, independent video/audio preview, recording timer.
- AV1, H.264, HEVC, ProRes and original stream; PCM/AAC/ALAC/Opus/FLAC.
- MOV/MP4/MKV/MPEG-TS, supported rate controls, profiles, compression effort,
  B-frames, AQ, keyframe interval and downscaling filters.
- Time/approximate-size splitting and NDI output for OBS with DistroAV.
- Audio monitor changed to a bounded pull-rendered buffer; the user confirmed
  steadier playback on the connected device.

This is independent, unofficial device support. Binaries are ad-hoc signed and
not notarized. Intel testing used Rosetta, not physical Intel hardware. Software
AV1 at 1080p60 could not keep up on the loaded M1 Pro in the live test. Hardware
codec support varies by Mac. HDR10 preservation has synthetic test coverage;
physical HDR capture remains unverified. Dolby/DTS capture is unsupported.
Device encoder resolution is manual: select 1080p for a 1080p source; this release
does not automatically detect the physical HDMI input resolution.

See README.md for installation, the native screenshot and compatibility, and
VALIDATION.md for measured results and limitations. Dependency-Sources contains
matching third-party source archives and build recipes. SHA256SUMS covers all
release assets.
