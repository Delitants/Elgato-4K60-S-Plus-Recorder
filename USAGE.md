# Recording and settings guide

[Back to the README](README.md) · [Validation and test limits](VALIDATION.md)

## Recording

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
When the window is minimized, hidden or fully covered, video presentation is
flushed. Restoring it resumes from the latest frame rather than replaying queued
frames. Active capture prevents App Nap; idle system sleep is still allowed
when not recording. The audio signal label briefly holds its state across silent gaps; the
stereo meter continues to show short-term peaks.
It cannot remove the capture hardware's inherent latency. Under sustained system
load, preview may skip or resynchronize rather than grow an unbounded delay.

Recoverable audio clock drift is corrected automatically. Timing gaps or overlaps
may insert silence or trim audio; recording continues with an orange warning.
Warnings remain visible after completion. An unrecoverable disk/codec error still
attempts to finalize and expose a partial file, but completion cannot be guaranteed
if the destination itself is unavailable.

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

While recording, the app prevents App Nap and idle system sleep, including when
its window is minimized or hidden. Display sleep remains allowed. This activity
ends after the recording is finalized; it does not change macOS power settings
or prevent an explicit sleep/shutdown command.

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
of a hard-coded 60. Changes in the estimated incoming rate warn and continue recording using source
timestamps and the existing output encoder configuration. A real codec, resolution
or HDR-format change still requires a new recording.

Physical HDMI input timing is not exposed by a verified USB status field in this
implementation. If the device repeats a 30 fps HDMI source into a 60 fps encoded
stream, set **Capture → Source content cadence / cap → 30 fps**. This caps processing at
the rate you specify; it does not change or verify the device's HDMI input mode.
**Incoming** remains the measured device stream rate; **Output** reflects the cap.
A game rendering 30 fps over a 60 Hz HDMI signal still supplies a 60 Hz signal.

For **23.976 fps film carried as repeated pictures in a 59.94 fps stream**, set
**Capture → Source content cadence / cap → 23.976 fps**, and leave **Video →
Output FPS → Match incoming stream** (or choose 23.976). For 24-in-60 film, use
24 fps. With a video encoder selected, recording detects the progressive 3:2
repeat pattern and keeps each original picture once after cadence acquisition.
This avoids the repeating skips caused by blindly sampling the carrier at 25 fps.
The recovered timeline follows device timestamps so audio does not drift.

This recovery applies to **recording, preview and NDI**, requires the source-content
choice to match the effective output rate, and adds up to five carrier frames of analysis
buffering. It is intended for stable progressive 3:2 repeats, not interlaced
telecine or motion interpolation. Static pictures can make the phase ambiguous;
clear motion establishes it. Missing input pictures cannot be reconstructed.
Interrupted carrier timing falls back to ordinary timestamp-based FPS selection
and reacquires film cadence after stable input returns. Use Automatic for actual
60 fps motion and when the content cadence is unknown.

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

### Live preview pacing

Preview frames use media timestamps and a bounded buffer to smooth USB/decode
arrival jitter. Output FPS still controls preview, recording and NDI. Lowering
59.94 fps input to 25 fps reduces motion detail and uses uneven source-frame
selection; it does not synthesize intermediate images. Choose Match incoming
stream to retain all incoming motion frames.

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

## Hardware H.264 B-frames

Hardware H.264 B-frames are blocked with a warning before recording because the
VideoToolbox encoder can return invalid decode timestamps. Disable B-frames for
hardware H.264, or use software encoding. Hardware HEVC and software H.264/HEVC
have separate support; see the [output audit](OUTPUT-TEST-REPORT.md).
