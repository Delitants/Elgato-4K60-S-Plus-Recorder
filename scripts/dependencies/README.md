# Release dependency recipes

Run these recipes from the repository root. They require Xcode, CMake, Ninja,
pkg-config, and make. They are build recipes, not automatic download installers.
Obtain the pinned Dependency-Sources release asset and verify its checksums.

Extract FFmpeg to `work/implementation/{arm,intel}/ffmpeg-8.1.2`.
For Intel, extract the archives preserving their upstream top-level directories:

- SVT-AV1 under `work/implementation/intel/svt-av1/SVT-AV1-v4.2.0`
- Opus under `work/implementation/intel/opus/opus-1.6.1`
- x265 under `work/implementation/intel/x265/x265_4.3`
- libusb under `work/implementation/intel/libusb/libusb-1.0.30`

The Intel x264 library/headers were taken from the official OBS dependencies
2026-08-26 macOS SDK, extracted into `work/implementation/obsdeps`.
Its source and build project are included in the source asset; use the x264
recipe there to rebuild that component. The SDK is available at
https://github.com/obsproject/obs-deps/releases/tag/2026-08-26 .
`build-intel.sh` creates the prefix, builds portable SVT-AV1/Opus, calls the
8+10-bit x265 recipe, imports that SDK's x264, builds libusb, then FFmpeg.
`build-intel-ffmpeg.sh` can rebuild FFmpeg after dependencies are installed.

ARM libraries came from Homebrew. Matching formulas are under
`Licenses/dependency-build-recipes`; upstream sources accompany the release.
Install those dependencies under `/opt/homebrew`, then run
`build-arm-ffmpeg.sh` for the minimal release FFmpeg prefix.

Build the app with `MEDIA_PREFIX` pointing at the resulting prefix. For Intel,
set `USB_PREFIX` to that prefix too. See BUILD.md. These recipes were consolidated
from the successful release commands; the entire clean-room build has not been
repeated after consolidation.
