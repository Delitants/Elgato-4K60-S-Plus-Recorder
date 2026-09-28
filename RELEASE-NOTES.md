# Elgato 4K60 S+ Recorder 0.5.0

Native macOS ARM and Intel builds. Requires macOS 26+; NDI runtime is bundled.

![Elgato Game Capture 4K60 S+](https://raw.githubusercontent.com/Delitants/Elgato-4K60-S-Plus-Recorder/main/docs/images/elgato-4k60-s-plus.png)

![Elgato Recorder live preview (0.4.1 interface)](https://raw.githubusercontent.com/Delitants/Elgato-4K60-S-Plus-Recorder/main/docs/images/elgato-recorder.png)

- Corrected jitter-induced frame selection during FPS conversion. Selection now
  follows the measured source cadence, so 60→30 uses every second source frame.
- Stop after can be changed during recording and stays anchored to the first
  accepted video keyframe. Disabling/re-enabling it does not restart the timer.
- Replaced USB bytes received with MB written across the recording's split files.
- Added the app icon, negotiated USB speed badge, orange warnings, Audio preview
  label, and responsive horizontal stereo dBFS meter with peak hold.
- Capture bitrate is now a codec-bounded target menu with a clear distinction
  from USB link speed. USB 3 is required; USB 2 capture is unsupported.
- Made software compression effort presets and their hardware limitations explicit.

See the [validation notes](https://github.com/Delitants/Elgato-4K60-S-Plus-Recorder/blob/main/VALIDATION.md)
and [research sources](https://github.com/Delitants/Elgato-4K60-S-Plus-Recorder/blob/main/SOURCES.md).
The screenshot above is the user-supplied 0.4.1 capture; 0.5.0 adds the new controls.

Intel validation uses Rosetta, not a physical Intel Mac. Builds are ad-hoc signed,
not notarized. Non-divisible FPS conversions preserve original-frame cadence;
this release does not synthesize motion-interpolated frames. Physical HDMI input
resolution/timing detection and HDR transcoding remain unsupported.
