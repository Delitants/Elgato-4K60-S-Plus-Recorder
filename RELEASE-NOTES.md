# Elgato 4K60 S+ Recorder 0.6.0

Native macOS ARM and Intel builds. Requires macOS 26+; NDI runtime is bundled.

![Elgato Game Capture 4K60 S+](https://raw.githubusercontent.com/Delitants/Elgato-4K60-S-Plus-Recorder/main/docs/images/elgato-4k60-s-plus.png)

![Elgato Recorder live preview (0.4.1 interface)](https://raw.githubusercontent.com/Delitants/Elgato-4K60-S-Plus-Recorder/main/docs/images/elgato-recorder.png)

- Added hardware constant-quality (CQ) recording for H.264 and HEVC on native
  Apple Silicon. In Settings → Video, select Automatic or Require hardware,
  then CQ. Hardware quality runs from 0 to 100, with a default of 65; higher
  values favor quality over file size. It is separate from software CRF.
- CQ uses a quality target instead of the video bitrate setting. It has no fixed
  bitrate or file-size limit, and 100 does not mean lossless. Unsupported hardware
  fails explicitly without switching to software or bitrate mode.
- Intel builds retain ABR/CBR and software CRF; hardware CQ is unavailable with
  the bundled Intel encoder implementation. Saved CQ profiles remain readable,
  with an explicit warning before recording.

Validated both hardware codecs, MOV/MP4/MKV/MPEG-TS output, HEVC Main 10,
FPS downsampling, quality endpoints and unsupported configurations. A native GUI
recording from the connected device at H.264 CQ 65 produced an 8.049-second,
3.48 MB file with 241 video frames and clean full-file decoding. That short
scene-specific result is not a file-size or quality guarantee.

The reported high-input-bitrate preview stutter remains unresolved. A short
capture/decode probe sustained roughly 60 incoming / 30 preview frames per
second without growing delay, but did not isolate final display presentation.
CQ controls recording compression and does not reduce device USB traffic.

See the [validation notes](https://github.com/Delitants/Elgato-4K60-S-Plus-Recorder/blob/main/docs/VALIDATION-0.6.0.md)
and [research sources](https://github.com/Delitants/Elgato-4K60-S-Plus-Recorder/blob/main/SOURCES.md).
The screenshot is the user-supplied 0.4.1 capture; current controls differ.

Intel validation uses Rosetta, not a physical Intel Mac. Builds are ad-hoc signed,
not notarized. Non-divisible FPS conversions preserve original-frame cadence;
this release does not synthesize motion-interpolated frames. Physical HDMI input
resolution/timing detection and HDR transcoding remain unsupported. Gradient
banding and USB 2 operation remain unverified.
