# Elgato Recorder 0.4.0 (experimental)

Separate macOS ARM and Intel builds with bundled NDI runtime. Requires macOS 26+.

- Measured incoming FPS replaces hard-coded 59.94/60 timing.
- Output FPS cap applies to preview, recording and NDI: 15, 23.976, 24, 25,
  29.97, 30, 50, 59.94 or 60. No upsampling or interpolation.
- Source FPS override for devices that repeat a lower-rate source in a higher-rate
  encoded stream. Physical HDMI rate detection remains unverified.
- Decoded-frame downsampling preserves audio and playback duration. Original
  compressed recording reports an error if FPS reduction requires transcoding.
- Correct NDI rate metadata, startup counters, and splits when source keyframes
  fall on discarded output frames. Device timestamp jitter is covered by regressions.
- Corrected FFmpeg library minimum OS to macOS 26; 0.3.0 had libraries declaring 27.

See README.md for controls and VALIDATION.md for tested limits. Intel testing uses
Rosetta, not physical Intel hardware. Builds are ad-hoc signed, not notarized.
Software AV1 performance and physical HDR validation limitations remain.
