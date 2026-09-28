# Elgato 4K60 S+ Recorder 0.5.1

Native macOS ARM and Intel builds. Requires macOS 26+; NDI runtime is bundled.

![Elgato Game Capture 4K60 S+](https://raw.githubusercontent.com/Delitants/Elgato-4K60-S-Plus-Recorder/main/docs/images/elgato-4k60-s-plus.png)

![Elgato Recorder live preview (0.4.1 interface)](https://raw.githubusercontent.com/Delitants/Elgato-4K60-S-Plus-Recorder/main/docs/images/elgato-recorder.png)

- Added measured incoming video bitrate at the top of the app, beside the requested
  device encoder target. A rolling 3-second average excludes audio and USB padding
  and remains active with preview disabled.
- Renamed Source FPS override to Source cadence cap, with an explanation that it
  limits downstream processing without changing the measured device stream FPS.
- Codec/bit-depth status now uses the received format description rather than
  assuming HEVC Main 10 from the requested capture profile.

Live checks on the connected 1080p59.94 source: H.264 requests of 20/200 Mbps
both delivered about 5.25 Mbps; HEVC requests of 20/140 Mbps both delivered about
9.27 Mbps. A 1 Mbps request delivered about 1.01 Mbps H.264 / 0.92 Mbps HEVC,
confirming that bitrate configuration affects the device. These short scene-specific
measurements are not a universal bitrate guarantee. HEVC Main 10 and 10-bit preview
decode buffers were independently confirmed; the reported gradient banding's
source-versus-display origin remains unresolved.

See the [validation notes](https://github.com/Delitants/Elgato-4K60-S-Plus-Recorder/blob/main/VALIDATION.md)
and [research sources](https://github.com/Delitants/Elgato-4K60-S-Plus-Recorder/blob/main/SOURCES.md).
The screenshot above is the user-supplied 0.4.1 capture; the current release adds the measured bitrate header and updated controls.

Intel validation uses Rosetta, not a physical Intel Mac. Builds are ad-hoc signed,
not notarized. Non-divisible FPS conversions preserve original-frame cadence;
this release does not synthesize motion-interpolated frames. Physical HDMI input
resolution/timing detection and HDR transcoding remain unsupported.
