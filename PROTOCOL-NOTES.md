# Verified encoder configuration notes

Tested device: 20GAP9901, USB 0fd9:0075, configuration 2, interface 0,
USB 3 5 Gbps. Endpoint 0x81 provides interleaved video/PCM in 1024-byte blocks.
The source also accepts VID/PID 0fd9:0068 (not physically tested).

Volatile vendor control 0x31, value 0x50, sends 26 encoder bytes:

| Offset | Meaning / implementation |
|---|---|
| 0 | 0 = H.264, 1 = HEVC |
| 1–4 | Target bitrate in kbps, little endian |
| 5–13 | Reference encoder parameters; level at 12 uses 41 for 1080p H.264, 52 for 4K H.264, 153 for HEVC |
| 14 | 8 for H.264, 10 for HEVC |
| 15–18 | Encoded width, little endian |
| 19–22 | Encoded height, little endian |
| 23–25 | Reference timing bytes 01 70 17 (nominal 60 fps) |

The vendor-driver construction and bounded live tests established codec,
bitrate, dimensions and bit-depth fields. These are interoperability findings,
not an official public USB specification. Unexplained reference fields remain
unchanged. There are no firmware writes, resets, or persistent configuration
changes. Encoder stop is sent before the USB interface is released.

HEVC 3840×2160 Main 10 was confirmed independently with ffprobe. Encoded output
size does not independently establish the HDMI source's native resolution.
Likewise, 10-bit does not establish HDR. The app uses Core Media's transfer
function metadata to identify PQ/HLG and preserves the original stream.

Relevant vendor public API source recognizes both product IDs and describes
H.264/HEVC selection (custom Windows property 400):
https://github.com/elgatosf/capture-device-support

USB startup sequence originated in the GPL-2.0 community implementation:
https://github.com/Saddytech/elgato4k60sp-linux

Raw user captures and the downloaded Windows driver are not distributed.

## Source matching

The encoder width/height controls are manual output requests. They are not HDMI
input detection. Do not treat a 3840×2160 SPS as proof of a native 4K input.
The default remains 1920×1080; an automatic source-matching option must wait for
validated input-status decoding. Never infer input size from this encoder setting.
Elgato documents source-matched recording in standalone SD-card mode:
https://help.elgato.com/hc/en-us/articles/360038597431-Elgato-Game-Capture-4K60-S-Supported-Resolutions
