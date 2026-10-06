# Building Elgato Recorder

Requires Xcode/Swift with the macOS 26 SDK or newer, clang++, Python 3,
`pkg-config`, libusb, and FFmpeg development libraries with libx264, libx265,
SVT-AV1, Opus, and VideoToolbox. The release was built with Xcode's macOS 27 SDK,
deployment target 26.0, and FFmpeg 8.1.2. FFmpeg 9 is not validated.

## Application

For ARM, install compatible dependencies with Homebrew, then:

```sh
brew install ffmpeg@8 libusb pkg-config
MEDIA_PREFIX="$(brew --prefix ffmpeg@8)" bash build.sh
```

The default output is `build/arm64/Elgato Recorder.app`.
For an Intel dependency prefix (every library must contain x86_64):

```sh
ARCH=x86_64 MEDIA_PREFIX=/path/to/intel/prefix \
USB_PREFIX=/path/to/intel/prefix bash build.sh
```

The output is `build/x86_64/Elgato Recorder.app`. An ARM Mac can cross-compile it;
Rosetta is useful for tests, but is not a substitute for testing physical Intel
hardware. `APP_DIR` and `BUILD_DIR` can override output/scratch directories.

The bundler copies non-system libraries, rewrites their load paths, and signs
nested libraries/helpers before the outer bundle. Builds use ad-hoc signatures.
A Developer ID and notarization are not included. To substitute LGPL components,
replace the corresponding dylib, retain its ABI/install name, and re-sign it and
the application with `codesign --force --sign -`.

## Exact release dependencies

| Library | ARM | Intel |
|---|---|---|
| FFmpeg | 8.1.2, minimal build | 8.1.2, minimal build |
| x264 | r3222, b35605ace3ddf7c1a5d67a2eb553f034aef41d55 | r3106, eaa68fa, OBS dependency SDK 2026-08-26 |
| x265 | 4.2, Homebrew multilib | 4.3, 8-bit + 10-bit multilib, assembly disabled |
| SVT-AV1 | 4.2.0, Homebrew | 4.2.0, portable C build |
| Opus | 1.6.1 | 1.6.1 |
| libusb | 1.0.30 | 1.0.30, `ac_cv_func_pipe2=no` for macOS 26 compatibility |
| NDI runtime | 6.3.2.0.260413 | Same vendor universal runtime |

The release's **Dependency-Sources** archive includes source archives, checksums,
the OBS dependency build scripts, and the original Homebrew formulas used for
ARM libraries. Those formulas specify source versions, patches, and build flags.
See `scripts/dependencies/` for the minimal FFmpeg and Intel build commands.
Build tools (CMake, Ninja, pkg-config, Xcode) must be installed separately. The
recipes are not a promise of bit-for-bit reproducibility across Xcode versions.

NDI's unmodified vendor runtime is included in `Dependencies/NDI` for bundling.
It is dynamically loaded by the separate MIT NDISender executable. Review the
NDI runtime terms before using or redistributing it. The runtime package used
for this release had SHA-256
`939d73d8456dcb1b64c609cdf36d8bb365a55d4329fab040241202492b993dce`;
its library had SHA-256
`af53789fcb8fc1737e6827a54d7ccea09736dc759e00ef02d53f4ed64d9abbd5`
before app-bundle signing. The package was signed by NewTek (W8U66ET244).

## Tests

Tests require FFmpeg/ffprobe and Xcode command-line tools. Point the helper
variables at a built app:

```sh
bash test.sh
# Included in test.sh; also runnable separately (requires libusb):
bash test-window-lifecycle.sh
# Pauses only its own disposable helper; never the live capture process:
TEST_MATRIX=1 bash test-backpressure.sh "/path/to/Elgato Recorder.app"
bash test-hdr.sh
bash test-fps.sh
bash test-rate-recovery.sh "/path/to/Elgato Recorder.app"
# For an Intel bundle on Apple Silicon (requires Rosetta):
TEST_ARCH=x86_64 bash test-rate-recovery.sh "/path/to/Intel/Elgato Recorder.app"
MEDIA_HELPER='/path/to/Elgato Recorder.app/Contents/MacOS/MediaHelper' bash test-advanced.sh
MEDIA_HELPER='/path/to/Elgato Recorder.app/Contents/MacOS/MediaHelper' bash test-audio-recovery.sh
NDI_HELPER='/path/to/Elgato Recorder.app/Contents/MacOS/NDISender' \
NDI_RUNTIME='/path/to/Elgato Recorder.app/Contents/Frameworks/libndi.dylib' bash test-ndi.sh
```

Hardware codec tests need normal macOS VideoToolbox access.
`TEST_HEVC=1` makes the recording matrix use HEVC source fixtures.
The fixtures are bounded and trap-cleaned; tests never write to the user's
recording folder.

Defining `CAPTURE_DIAGNOSTICS` when compiling Swift enables a bounded temporary
`ElgatoRecorder-AudioDiagnostics.json` snapshot with timing and queue counters.
It contains no captured media and is overwritten every five seconds. Release
builds omit that flag.

Version 0.4.0 rebuilds FFmpeg with `-mmacosx-version-min=26.0` in both compiler
and linker flags. All bundled Mach-O minimum OS versions are audited before
packaging. Version 0.3.0 unintentionally contained FFmpeg dylibs declaring 27.0
despite the app's 26.0 minimum; use 0.4.0 or later on macOS 26. Actual runtime testing was
on macOS 27. `test-fps.sh` checks integer/fractional rates, no upsampling,
audio continuity, original-stream rejection, and unaligned-keyframe splitting.

### Output combination audit

`./test-output-matrix.sh '/path/Elgato Recorder.app' /path/to/reports`
compiles the production `RecordingSink` into a temporary copy of the app, replays
synthetic interleaved audio/video, decodes each output, and removes generated media.
The modes are `all` (1080p H.264 input), `hevc` (10-bit HEVC input), `controls`
(encoder/audio controls), `hardware` (hardware rate/profile combinations and bitrate boundaries),
`4k` (4K input and output scaling), and `hdr` (PQ passthrough and transcode rejection). An optional list
of modes follows the report directory. Each failed case is retained in JSONL and
makes the runner exit nonzero. Hardware tests require normal VideoToolbox access;
a sandbox denial is not a device capability result. These short fixtures check
compatibility, not extended real-time throughput.

The 0.5.0 cadence regression also checks decoded source-frame content under jitter:

```sh
python3 Tests/JitterCadenceIntegration.py "/path/to/Elgato Recorder.app/Contents/MacOS/MediaHelper"
```

MKV network playback layout, content preservation, split, salvage and bounded-index tests: `bash test-network-playback.sh /path/to/Elgato\ Recorder.app`.
