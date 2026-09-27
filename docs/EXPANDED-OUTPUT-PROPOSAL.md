# Expanded recording and OBS output proposal

Status: historical approved design. Version 0.3.0 implements the supported subset described in README.md; VALIDATION.md records the results and remaining limitations.
Date: 2026-09-27. Existing application: 0.2.1.

## Intended result

Extend the current native macOS Elgato 4K60 S+ recorder with AV1, encoder tuning, additional audio codecs and containers, automatic file splitting, and NDI video/audio output to OBS. Preserve 1080p60 and 4K capture, independent video/audio monitoring, the recording timer, and the preview latency fix. Test recordings must be deleted after verification.

## Recommended approach and alternatives

Keep AppKit and the proven USB capture/parser. Retain the native recording path for existing supported configurations. Add an external media helper based on FFmpeg libraries for advanced encoding and multiplexing, plus a separate NDI sender using the official SDK/runtime.

A native-only extension would preserve minimal dependencies but would not satisfy the requested AV1 encoder, containers, audio codecs, and CRF controls. Replacing all existing recording paths at once with FFmpeg would simplify long-term backend routing but unnecessarily broaden regression risk. The recommended incremental approach preserves the working native path while sharing validation and recording lifecycle interfaces.

The installed FFmpeg provides libsvtav1, libx264, libx265, VideoToolbox encoders, libopus, and FLAC. First target is this Mac. Any redistributed backend must include the applicable license notices and corresponding-source arrangements; do not assume the existing app license covers it. Bundle the permitted macOS NDI runtime inside the app (Contents/Frameworks), and load it by its bundle-relative path. The recorder must not require a separate system-wide NDI installation. Include the required license notices, third-party notices, attribution, and applicable end-user terms. Verify library architecture, dependencies, signing, and loading on a Mac without a global NDI runtime. Runtime acquisition and license acceptance must follow the vendor's process. OBS remains a separate receiver: DistroAV and its own runtime requirements are not satisfied merely by bundling the recorder runtime.

## Controls and behavior

| Request | Proposed behavior |
|---|---|
| AV1 | Software SVT-AV1, encoder preset and 8/10-bit profiles as supported. No hardware AV1 encoder is available in the installed backend. Measure sustainable recording throughput; do not promise 4K60 software encoding on M1 Pro. |
| Compression | Codec-specific speed/quality presets for H.264, HEVC, and AV1; ProRes quality profiles; FLAC compression effort. No misleading universal compression slider. |
| Rate control | ABR, CBR, and CRF where actually supported by the selected encoder. CRF exposes quality rather than target bitrate. Hardware quality modes are not relabeled CRF. Lossless formats do not expose target bitrate. |
| Keyframes | Auto by default; optional interval in seconds. Convert using the detected frame rate. Original-video passthrough cannot change source keyframes. |
| Profiles | Codec profiles filtered by encoder and bit depth; reject incompatible combinations such as baseline H.264 with B-frames. |
| B-frames | Enable only where the encoder supports explicit control. Keep disabled by default for low delay. Preserve proper decode and presentation timestamps in output. Do not pretend AV1 has the same B-frame control as H.264. |
| Spatial AQ | Auto, Enabled, Disabled when the backend exposes an appropriate control. Unsupported combinations show an explanation rather than silently ignoring the choice. |
| Scaling | Disabled, Bilinear, Area, Bicubic, Lanczos, matching the screenshot's algorithm choices. Do not claim identical OBS sample counts for a different implementation. Preserve aspect ratio and valid chroma dimensions. |
| Audio | Existing PCM/AAC/ALAC plus Opus and FLAC. Opus bitrate and supported bitrate mode; FLAC effort and resulting lossless bitrate display. Source remains stereo 48 kHz PCM. |
| Containers | Existing MOV/MP4 plus MKV and MPEG-TS. Validate codec/container combinations before recording. |
| Splitting | Off, by time, or by size. Numbered files with continuous capture timing. Rotate on video keyframes; request one when re-encoding. Original passthrough waits for the next source keyframe. Size is a target, not a strict maximum: GOP and container overhead can exceed it. |
| NDI | Independent enable toggle, stream name, and output resolution; decoded video and stereo audio sent to OBS through NDI. Independent of recording and local preview toggles. Default off. |
| Dolby | No Dolby/DTS capture option: Elgato explicitly lists 4K60 S+ as unsupported for multichannel digital audio and requires stereo PCM. Encoding that stereo signal as AC-3 would not recover Dolby source audio. |

Compatibility baseline: MKV is the principal container for AV1, Opus, and FLAC. Initially constrain MPEG-TS to H.264/HEVC with AAC. Preserve current working MOV/MP4 combinations; enable additional combinations only after muxing, full decoding, seeking, and timing checks. Original video bypasses encoder controls and scaling. Show the reason for disabled controls.

HDR: preserve the existing original HEVC Main10 recording path and its color metadata. New transcoding combinations must preserve bit depth, primaries, transfer, matrix, and relevant HDR metadata before being exposed as HDR-capable. Reject unsupported HDR transformations explicitly. NDI HDR must likewise be validated separately; never label ordinary SDR output as HDR. A real HDR HDMI source remains required for physical-device HDR acceptance.

## Data flow and failure handling

Fan out timestamped capture packets into independent sinks for recording, preview, and NDI. Use bounded queues and explicit ownership. Preview/NDI can discard stale decoded video; recording must report an inability to keep up rather than silently corrupting or dropping reference frames. Slow sinks must not block USB acquisition. Audio monitoring must retain its short queue.

The media helper receives versioned, length-framed messages containing codec configuration, packet type, source timestamps, durations, and payload. It owns decoder, encoder, muxer, and segment lifecycle and returns status/errors. Avoid independent raw pipes that invent separate audio/video clocks. Avoid intermediate recordings and post-record conversion, which consume unnecessary SSD space.

Segment closure and final recording stop drain encoders and finalize every file. The timer covers the whole recording session, not each part. Quit waits for finalization with visible progress and error reporting. A failed NDI sender must not stop file recording.

Settings use versioned persistence with defaults for fields missing from older profiles. Organize the native settings panel into Video, Audio, Output, and NDI sections. Display the effective encoder and settings; never silently substitute software for explicitly required hardware.

## Verification required before release

- Capability and validation tests for encoder/container/profile combinations, including rejected combinations and migration from current saved settings.
- Fixture-based mux/decode checks for each exposed new codec/container, including B-frame timestamp reordering and audio alignment.
- Timed and size-based split recordings: every part independently decodes, starts correctly, and preserves continuous audio/video without unexplained gaps or duplication.
- Live USB recording at 1080p60 and 4K, with simultaneous preview and audio monitoring; monitor throughput and queue bounds.
- Explicit overload tests: slow AV1 encoder and unavailable NDI receiver must not accumulate preview delay or unbounded memory.
- NDI discovery and visible/audible reception in OBS via DistroAV. OBS 32.2.2 is installed; runtime/plugin were not found in standard locations searched. Installation alone is not an end-to-end pass.
- Preserve HDR metadata in fixtures, and distinguish that from unverified physical HDR input.
- Remove all generated recordings and temporary caches; preserve the user's recordings and existing deliverables.

## Research references

- Elgato audio limitation: https://help.elgato.com/hc/en-us/articles/360027951892-Elgato-Game-Capture-hardware-doesn-t-support-multichannel-digital-audio-Dolby-DTS
- FFmpeg encoders: https://www.ffmpeg.org/ffmpeg-codecs.html
- Scaling: https://ffmpeg.org/ffmpeg-scaler.html
- Containers: https://ffmpeg.org/ffmpeg-formats.html
- NDI runtime distribution: https://docs.ndi.video/all/developing-with-ndi/sdk/software-distribution
- NDI dynamic loading: https://docs.ndi.video/all/developing-with-ndi/sdk/dynamic-loading-of-ndi-libraries
- NDI SDK licensing: https://docs.ndi.video/all/developing-with-ndi/sdk/licensing
- NDI and FFmpeg: https://docs.ndi.video/all/faq/sdk/using-ffmpeg-with-ndi
- OBS receiver requirements: https://github.com/DistroAV/DistroAV/blob/master/README.md
- Local evidence: installed FFmpeg 8.1.2 encoder listings and encoder help; OBS Info.plist version 32.2.2. These indicate availability, not successful live encoding or reception.
