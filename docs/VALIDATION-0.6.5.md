# 0.6.5 audio clock recovery validation

The user's 617,962,834-byte MKV was preserved and fully decoded without errors.
It lacks a finalized duration/index because the old helper exited on an audio
clock guard. The app itself remained alive.

A 65-second metadata-only probe of the connected 4K60 S+ measured -58.24 ppm
between audio timestamps and 48 kHz PCM sample counts, with zero parser discards.
That rate accumulates 100 ms in 28.62 minutes, consistent with the reported 28:32
stop. The old helper never corrected accumulated skew.

## Recovery behavior

libswresample now uses timestamp compensation with a 1 ms tolerance, gradual
correction limited to 48 samples/second, and hard fill/trim above 100 ms. Buffers
are sized using the resampler's output bound, and delayed samples are drained at
file/split boundaries. Undisturbed PCM remains bit-exact in the existing split
and film-cadence tests.

Forward gaps above two seconds advance the audio timeline after draining prior
audio, avoiding arbitrary silence allocation. Out-of-order audio is discarded
with a warning. When video timing holds audio beyond three seconds, queued audio
is written rather than aborting an already started recording. A pending initial
keyframe retains only bounded recent audio.

The helper emits complete warning lines. The UI retains the latest warning even
if split-file progress evicts it from the bounded helper log. It displays an
orange recording warning and keeps recording. On terminal errors the helper tries
to finalize the existing output, with guards for incomplete initialization and
single-attempt trailer finalization.

[FFmpeg's resampler documentation](https://ffmpeg.org/ffmpeg-resampler.html)
describes the timestamp compensation used here.

## Automated evidence

The new integration test first reproduced the exact old 100 ms abort. Tests then
covered 250 ms missing/overlapping audio, out-of-order packets, three-second gaps
including PCM, three 55-minute generated media timelines with +/-60 ppm skew (FLAC) and -60 ppm (AAC), and
terminal malformed IPC preserving a finalized decodable partial file. Invalid
encoder initialization returns an error instead of entering unsafe cleanup.

The 55-minute cases are accelerated generated-media tests through the real helper,
not 55 minutes of live HDMI capture. Outputs are checked for monotonic timestamps,
end-time alignment, decodability, audible data after recovery, warnings and explicit
successful finalization. Temporary fixtures are removed automatically.

The core tests, codec/container integration matrix (including native hardware
encoders), FPS conversion and film-cadence/split fidelity tests are also exercised.
Existing SDK deprecation and C++ qualification warnings remain.

## Live native app check

The release candidate recorded 90.035 seconds on the same external SSD using the
user's hardware H.264 CQ / AAC / MKV profile. The native window showed an orange
audio-drift warning while the timer and recording continued. It then stopped at
the test timer, reported Recording saved, retained the warning, and enabled Show
Last Recording. The 28,431,359-byte result fully decoded without errors. The UI
reported zero discards. The test recording was deleted afterward, and the user's
original folder and 55-minute timer were restored.

A separate link-time fault test makes the real FFmpeg trailer deinitialize and
then report an I/O failure. The helper exits cleanly and calls the trailer exactly
once, avoiding unsafe cleanup retry. See `Tests/TrailerFault.cpp` and
`Tests/AudioTrailerFailure.py`.

Both ARM64 and x86_64 bundles passed architecture, dependency closure, minimum-OS
and strict ad-hoc signature checks. Native Intel hardware recording and a full
55-minute live HDMI run were not repeated. Generated long-timeline tests exercise
the exact accumulation defect; the short live test establishes on-device warning,
continued recording and successful finalization.
