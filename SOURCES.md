# Sources and development provenance

This document identifies the interoperability references and software used to
build Elgato Recorder. Community USB research, vendor documentation, local device
observations, and bundled dependencies have different roles, described below.

## Device protocol and reverse engineering

### Saddytech/elgato4k60sp-linux — primary USB reference

The USB initialization sequence was adapted from this GPL-2.0 project, which
reports reverse engineering the device protocol from Windows USB captures.
The retained research snapshot identifies revision
`6a0c3c4dd121242923f90fbcb375aaefabcc4db6`.

- [live_preview.py](https://github.com/Saddytech/elgato4k60sp-linux/blob/6a0c3c4dd121242923f90fbcb375aaefabcc4db6/live_preview.py): userspace capture reference, USB startup and stream framing.
- [kernel/elgato_4k60sp.c](https://github.com/Saddytech/elgato4k60sp-linux/blob/6a0c3c4dd121242923f90fbcb375aaefabcc4db6/kernel/elgato_4k60sp.c): Linux implementation of device control and capture.
- [docs/DEVELOPMENT_LOG.md](https://github.com/Saddytech/elgato4k60sp-linux/blob/6a0c3c4dd121242923f90fbcb375aaefabcc4db6/docs/DEVELOPMENT_LOG.md): USB topology, startup sequence and proprietary block framing.
- [Upstream license](https://github.com/Saddytech/elgato4k60sp-linux/blob/6a0c3c4dd121242923f90fbcb375aaefabcc4db6/LICENSE).

In this app, see [Sources/USBBridge.c](Sources/USBBridge.c) for the adapted capture
controls and [Sources/PacketParser.swift](Sources/PacketParser.swift) for stream
parsing. The app uses libusb on macOS; it does not install the Linux kernel module.
Upstream tested USB ID 0fd9:0068; local development used the connected 20GAP9901
with ID 0fd9:0075. Support for one ID is not evidence of testing the other.

### Elgato public examples and support information

[elgatosf/capture-device-support](https://github.com/elgatosf/capture-device-support)
was consulted for device identification and the public H.264/HEVC selection API,
including the Windows custom-property interface. Its [SampleCode](https://github.com/elgatosf/capture-device-support/tree/main/SampleCode)
and [Library](https://github.com/elgatosf/capture-device-support/tree/main/Library)
are vendor API examples, not a complete public USB protocol specification or an
official macOS driver for this device. These links track upstream; the historical
revision consulted was not retained in the available provenance records.

Elgato's [supported resolutions article](https://help.elgato.com/hc/en-us/articles/360038597431-Elgato-Game-Capture-4K60-S-Supported-Resolutions)
was used to distinguish standalone source-matched recording from this app's
manual USB encoder resolution requests.

### Local interoperability work

[PROTOCOL-NOTES.md](PROTOCOL-NOTES.md) records the encoder fields checked during
local development, including codec, bitrate, dimensions and bit depth. The notes
record comparison with a downloaded Windows vendor driver and bounded live USB
tests. The exact driver package name, version, download URL and SHA-256 were not
retained in the available records, so that binary-analysis input is not yet
independently reproducible from this repository. No guessed driver identity is
provided. The Windows driver and raw user captures are not redistributed.

Local capture, timing, audio monitoring, native UI and output integration work
is documented in [VALIDATION.md](VALIDATION.md) and the
[0.4.1 output audit](OUTPUT-TEST-REPORT.md). Confirmed encoder dimensions do not
establish physical HDMI input dimensions; measured USB frame rate does not prove
physical HDMI timing. Unverified protocol fields remain unchanged.

## Media, USB and NDI components

| Source | Role in the application |
|---|---|
| [libusb 1.0.30](https://github.com/libusb/libusb/tree/v1.0.30) | USB control and bulk transfers |
| [FFmpeg 8.1.2](https://ffmpeg.org/releases/) | Separate MediaHelper: encoding, conversion and container output; ffprobe/ffmpeg also validate test recordings |
| [x264](https://www.videolan.org/developers/x264.html) | Software H.264 encoding |
| [x265](https://bitbucket.org/multicoreware/x265_git) | Software HEVC encoding |
| [SVT-AV1](https://gitlab.com/AOMediaCodec/SVT-AV1) | Software AV1 encoding |
| [Opus](https://opus-codec.org/) | Opus audio encoding |
| [Apple developer documentation](https://developer.apple.com/documentation/) | AppKit, AVFoundation, Core Media, VideoToolbox and audio framework APIs |
| [NDI SDK](https://ndi.video/for-developers/ndi-sdk/) | Public headers and proprietary runtime used by the separate NDISender process |
| [OBS dependency release 2026-08-26](https://github.com/obsproject/obs-deps/releases/tag/2026-08-26) | Intel x264 library/headers and corresponding build recipes |
| [Homebrew core](https://github.com/Homebrew/homebrew-core) | ARM dependency packages and retained build formulas |
| [DistroAV](https://github.com/DistroAV/DistroAV) | OBS receiver setup reference; not bundled in this app |

Exact architecture-specific versions, licenses and notices are in
[Licenses/THIRD-PARTY.txt](Licenses/THIRD-PARTY.txt). Build inputs and recipes are
in [BUILD.md](BUILD.md), [scripts/dependencies](scripts/dependencies/README.md)
and [Licenses/dependency-build-recipes](Licenses/dependency-build-recipes).

The [v0.4.1 release](https://github.com/Delitants/Elgato-4K60-S-Plus-Recorder/releases/tag/v0.4.1)
includes `Elgato-Recorder-0.4.1-Dependency-Sources.tar.gz` and checksums. That archive
contains corresponding open-source dependency inputs; it does not contain the
proprietary Windows driver or NDI runtime source. App/helper source is published
in this repository; the v0.4.1 application code is pinned by its release tag.

## Hardware constant quality

The CQ implementation follows the [FFmpeg 8 VideoToolbox encoder source](https://ffmpeg.org/doxygen/8.0/videotoolboxenc_8c_source.html)
and Apple's [VideoToolbox Quality property](https://developer.apple.com/documentation/videotoolbox/kvtcompressionpropertykey_quality).
The bundled encoder enables QSCALE on native Apple Silicon and translates its
quality value to the VideoToolbox 0–1 range. This platform restriction is reflected
in the UI and helper; it is not a claim that all Intel hardware lacks quality controls.

## Preview presentation timing

Apple's [sample enqueue documentation](https://developer.apple.com/documentation/avfoundation/avsamplebufferdisplaylayer/enqueue(_:))
explains why DisplayImmediately ignores media cadence. The preview maps media
PTS to host-clock deadlines using the behavior described by
[controlTimebase](https://developer.apple.com/documentation/avfoundation/avsamplebufferdisplaylayer/controltimebase),
and enqueues through the layer's sampleBufferRenderer.

## Images

The product photograph and application screenshot in the README were supplied by
the user for publication. They are presentation assets, not protocol evidence.
Elgato/Corsair and NDI references do not imply endorsement.
