# Elgato 4K60 S+ Recorder

A native AppKit recorder for **Elgato Game Capture 4K60 S+ (20GAP9901)** over USB 3.
Independent community software; not affiliated with Elgato or Corsair. This is
experimental support for a device that Elgato does not officially support on macOS.

[Download ARM or Intel releases](https://github.com/Delitants/Elgato-4K60-S-Plus-Recorder/releases)

![Elgato Game Capture 4K60 S+](docs/images/elgato-4k60-s-plus.png)

![Elgato Recorder on macOS with live video and HDMI audio preview](docs/images/elgato-recorder.png)

## Install

Requires **macOS 26 or later**. Choose **arm64** for Apple Silicon or **x86_64** for
Intel, extract the ZIP, and move **Elgato Recorder.app** to Applications.
The app includes its USB library, recording backend, and NDI runtime. Homebrew,
FFmpeg, and a separate NDI installation are not needed to run the recorder.

These builds are ad-hoc signed, not Apple notarized. macOS may require approval
in System Settings → Privacy & Security on first launch. Verify the release
checksums before approving a downloaded build.

ARM was tested on an M1 Pro. Intel code and bundled libraries were tested through
Rosetta on that Mac; a physical Intel Mac has not been tested. Hardware encoders
and performance depend on the Mac. See [validation and limitations](VALIDATION.md).

## Device compatibility

This application supports the **Elgato Game Capture 4K60 S+** only. Local hardware
validation used model **20GAP9901**, USB ID **0fd9:0075**. The USB implementation
also accepts **0fd9:0068**, based on the upstream community driver, but that ID
has not been tested locally.

Other Elgato models are not supported. The app uses the 4K60 S+ proprietary USB
control and stream protocol rather than a generic camera capture interface.
Models such as HD60 S/S+, HD60 X, 4K X and 4K60 Pro require separate integration
and validation; sharing the Elgato brand does not establish compatibility.

## Capture

1. Connect the Elgato power supply, its **PC/data USB port** to a USB 3 port, and
   the source to **HDMI IN**. Close other software using the device.
2. Open the app, choose **Save Folder…**, and select recording settings.
3. Click **Record** (⌘R). Stop, disconnect, or quit to finalize the recording.
4. **Show Last Recording** reveals the most recently finalized file or split part.

The HDMI source must send supported, unencrypted video and **stereo PCM audio**.
HDCP-protected video cannot be recorded. Dolby/DTS multichannel input is not
supported by this device; select stereo PCM on the source.

**Match the device encoder resolution to the HDMI source.** Use 1920×1080 for
1080p, and 3840×2160 only for a 4K source. This release requests encoder dimensions
manually; it does **not** detect the physical HDMI input resolution automatically.
The displayed **Encoded** resolution describes the incoming compressed stream,
not an independently measured HDMI input. Frame rate follows measured incoming timestamps; see the FPS controls below.

Video and audio preview toggles are independent of recording. Monitoring volume
only affects playback through the Mac. Audio uses a bounded, preallocated ring
buffer, with approximately 64 ms of startup buffering and recovery after a stall.
It cannot remove the capture hardware's inherent latency. Under sustained system
load, preview may skip or resynchronize rather than grow an unbounded delay.

**Stop after** takes `hh:mm:ss` and can be enabled, disabled or edited while
recording. Press Return or leave the field to apply an edit. The limit is measured
from the first accepted video keyframe, not from when the checkbox is enabled.
Turning it off and back on preserves that start time. A limit already exceeded
stops recording promptly; lost HDMI time still counts after recording has begun.

The footer reports **MB written** for the current or most recent recording,
including all split parts. This measures output file sizes, not USB input traffic.
The stereo meter uses dBFS, green/yellow/red ranges and peak hold; monitoring
volume does not change its readings or the recorded audio.

The header reports the negotiated USB connection speed. USB 3.0 (5 Gbps) is shown
in blue. USB 2.0 is identified but capture remains unsupported. The capture bitrate
menu chooses an **encoder target**, not USB bandwidth; a faster host port does
not create additional device modes. Existing valid custom targets are preserved.

The header also shows **Device video: … Mbps received** beside the requested
encoder target. This measures reassembled compressed video payload before decoding,
preview, FPS selection or recording, excluding audio and USB headers/padding.
It uses completed 100 ms buckets over a rolling 3-second window, with a one-second
warmup. A target is not a firmware readback or a guarantee of constant bitrate.
A lower measured rate alone does not prove the target was ignored.

HEVC capture requests 10-bit video, but cannot recover smooth gradients already
lost in the source or HDMI signal. Codec/bit-depth text is taken from the received
format description (bit depth is omitted if unavailable). Preview requests 10-bit
pixel buffers for HEVC; the final display path and source precision are separate.

## Frame rate and downsampling

**Settings → Video → Output FPS** applies to video preview, recording, and NDI.
The default **Match incoming stream** follows device timestamps. Available caps
are 15, 23.976, 24, 25, 29.97, 30, 50, 59.94 and 60 fps. A 30 fps stream stays
30 even if a 60 fps cap is selected. Lower caps select frames against the measured source cadence, correcting
sub-frame device timestamp jitter before selection and writing evenly spaced
output timestamps. Playback speed and audio are preserved. Missing source frames
remain gaps; no motion interpolation or frame duplication is performed. Conversion
between non-divisible rates (for example 60→24) retains the unavoidable original
frame cadence; it cannot create intermediate motion that was never captured. Resolution scaling is independent of this setting.

The incoming rate is measured over a short timestamp window to tolerate the
device's timing jitter. The status shows **Incoming** and **Output** FPS instead
of a hard-coded 60. A substantial sustained incoming-rate change stops an active
recording so its timing metadata remains consistent; start a new recording.

Physical HDMI input timing is not exposed by a verified USB status field in this
implementation. If the device repeats a 30 fps HDMI source into a 60 fps encoded
stream, set **Capture → Source cadence cap → 30 fps**. This caps processing at
the rate you specify; it does not change or verify the device's HDMI input mode.
**Incoming** remains the measured device stream rate; **Output** reflects the cap.
A game rendering 30 fps over a 60 Hz HDMI signal still supplies a 60 Hz signal.

**Original device stream** preserves every compressed frame. If the effective
output rate is lower, recording reports that a video encoder is required; choose
H.264, HEVC, ProRes or AV1. Preview and NDI can still use the lower rate. Select
a supported encoder and reduce output resolution/workload if it cannot keep up.

## Formats and controls

| Area | Options |
|---|---|
| Device encoding | H.264 8-bit; HEVC Main 10; 1080p or 4K |
| Recorded video | Original device stream, H.264, HEVC, ProRes 422, AV1 |
| Containers | MOV, MP4, MKV, MPEG-TS |
| Audio | PCM, AAC, ALAC, Opus, FLAC; 48 kHz stereo |
| Processing | Automatic, required hardware, software decoding/encoding where supported |
| Rate control | ABR; CBR for supported H.264/HEVC paths; software CRF; hardware CQ on Apple Silicon |
| Compression | Software presets, AV1 effort, ProRes profiles, Opus/FLAC effort |
| Advanced video | Codec profiles, B-frames, keyframe interval (0 = Auto), spatial AQ |
| Frame rate | Match incoming stream or explicit FPS cap; manual source override; no upsampling |
| Downscale | Keep encoded dimensions, 1080p, 720p; Disabled/Bilinear/Area/Bicubic/Lanczos |
| Splitting | Time or approximate size, at the next source keyframe |
| OBS output | NDI video and stereo audio; original, 1080p, or 720p SDR |

Use **MKV** for AV1, Opus, or FLAC. MP4 requires H.264/HEVC with AAC; MPEG-TS
requires H.264/HEVC with AAC. Unsupported combinations are rejected before capture
is reconfigured. Original video copies the device's compressed stream and does
not expose Mac-encoder controls. Bitrate controls are targets, not exact file-size
guarantees. CRF trades variable bitrate for a quality target.

AV1 is software-only in this release and may not keep up with real-time 4K60 on
your CPU. Intel AV1 uses a portable C build and has reduced performance. Required
hardware modes fail clearly when unavailable. Software ProRes is unavailable.

Splits can exceed their time/size target by a source GOP, one output frame
interval, and encoder/container buffering. After a source keyframe, a transcode
split starts on the next selected frame. Each finalized part starts at a video keyframe; PCM is divided at the
corresponding audio sample. Lossy audio encoders may introduce priming/padding at
individual segment boundaries. If the recording backend cannot keep up, recording
stops with an error instead of silently dropping recording frames. Keep any
reported partial file; an error does not guarantee the last file was finalized.

### Hardware constant quality

In **Settings → Video**, choose **H.264 / AVC** or **HEVC**, use **Automatic**
or **Require hardware**, then select **CQ · hardware constant quality**.
Set **Hardware CQ · 0–100** (default 65). Higher means better quality and larger
files; lower means smaller files with more compression. Quality 100 is not lossless.
Compare representative motion, dark gradients and fine detail before choosing
an archival setting. Values are not equivalent to software CRF: its scale runs
in the opposite direction, and the two quality settings are saved independently.

CQ disables the video bitrate control. It uses VideoToolbox's quality target,
allowing bitrate and file size to vary with scene complexity; there is no bitrate
or file-size guarantee. CQ requires hardware even when Automatic is selected;
an unsupported hardware encoder fails clearly, without falling back to software
or ABR. Incoming device bitrate, preview, audio and output FPS controls retain
their existing meanings. CQ changes recording compression, not USB input traffic.

The bundled CQ implementation requires the **native Apple Silicon build**.
Intel builds show the option as unavailable and retain ABR/CBR and software CRF.
Saved CQ profiles remain readable on Intel, with an explicit warning before
recording. H.264 hardware B-frame and HDR-transcoding restrictions still apply.

### Compression effort

In **Settings → Video**, choose **H.264 / AVC** or **HEVC**, then
**Mac encoder → Software** to enable **Software compression effort**: ultrafast,
superfast, veryfast, faster, fast, medium, slow, slower and veryslow. Auto uses
veryfast. Slower presets use more CPU time for compression efficiency. AV1 exposes
its numeric effort presets (lower numbers are slower); Auto uses 10. Hardware
VideoToolbox encoding does not expose the x264/x265 speed presets.

## HDR

Use **HEVC** capture and **Original device stream** to preserve HDR10 metadata.
A 10-bit stream is not by itself evidence of HDR. The status reports the signaled
transfer function. Synthetic PQ/BT.2020 metadata preservation was tested; actual
HDR HDMI capture and display appearance remain unverified. HDR transcoding,
tone mapping, HDR NDI output, Dolby Vision, and HLG capture are not supported.

## NDI output to OBS

Enable **Settings → NDI**, set a stream name, and select the output size. In OBS,
install [DistroAV](https://github.com/DistroAV/DistroAV), add an **NDI Source**, and
select the recorder's stream. OBS/DistroAV may require its own NDI runtime setup;
the recorder's bundled runtime is private to the recorder. Video and stereo audio
output continue independently of local preview toggles and recording.

[About NDI](https://ndi.video) · NDI® is a registered trademark of Vizrt NDI AB.
The bundled proprietary runtime has [separate terms](Licenses/NDI-RUNTIME-TERMS.txt).
This project is not sponsored or endorsed by NDI.

## Build and test

See [BUILD.md](BUILD.md) for ARM/Intel build commands and dependency versions.
The release provides a matching dependency source archive and build recipes.

```sh
bash test.sh
bash test-hdr.sh
MEDIA_HELPER='/path/to/Elgato Recorder.app/Contents/MacOS/MediaHelper' bash test-advanced.sh
NDI_HELPER='/path/to/Elgato Recorder.app/Contents/MacOS/NDISender' \
NDI_RUNTIME='/path/to/Elgato Recorder.app/Contents/Frameworks/libndi.dylib' bash test-ndi.sh
bash test-fps.sh
```

Media fixtures and test recordings use temporary directories and are removed on
exit. Test tools require FFmpeg/ffprobe and Xcode command-line tools.

## Licenses

The native application and adapted USB initialization are GPL-2.0; see [LICENSE](LICENSE).
The standalone media helper is GPL-3.0-or-later and uses FFmpeg and its separately
licensed codec libraries. The standalone NDI sender source and headers are MIT;
the NDI runtime is proprietary. These are separate executable components, using
bounded PCM/video IPC; FFmpeg is not linked to NDI. See [component notices](Licenses/THIRD-PARTY.txt)
and the licenses shipped inside the app. GPL/LGPL source, rebuild, and library
replacement rights apply to their respective components; NDI terms do not apply
to those open-source components.

## Research sources and acknowledgments

USB interoperability work builds on [Saddytech/elgato4k60sp-linux](https://github.com/Saddytech/elgato4k60sp-linux)
and [Elgato's public device-support examples](https://github.com/elgatosf/capture-device-support).
See [Sources and development provenance](SOURCES.md) for specific upstream files,
the retained reference revision, local device findings, dependency sources and
the Windows-driver provenance limitation.

Live release testing found that AV1 1080p60 with 4K input and NDI could not keep up
on the loaded M1 Pro. The app reports overload and retains the partial file.
See [validation results](VALIDATION.md) for the tested matrix and limitations.

### Recording startup and B-frames (0.4.1)

Recording queue age uses monotonic waiting time, so interleaved HDMI audio/video
timestamps cannot trigger a false overload. Cold encoder startup has a bounded
two-second allowance; a recorder that falls behind still stops rather than losing frames.
Explicit Software encoding uses the bundled x264/x265 encoder consistently across
containers. H.264 is also labeled AVC.

Hardware H.264 B-frames are blocked with a warning before recording because the
VideoToolbox encoder can return invalid decode timestamps. Use hardware encoding
with B-frames Disabled, or select Software for B-frames. Existing saved settings
remain visible so the app can explain an incompatible selection.

See [BUILD.md](BUILD.md#output-combination-audit) for the output-matrix runner.

[0.6.0 validation](docs/VALIDATION-0.6.0.md) · [0.5.1 validation](docs/VALIDATION-0.5.1.md) · [0.5.0 validation](docs/VALIDATION-0.5.0.md) · [0.4.1 output test report](OUTPUT-TEST-REPORT.md) · [Detailed matrix results](OUTPUT-TEST-RESULTS.json)
