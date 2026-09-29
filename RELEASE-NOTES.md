# Elgato 4K60 S+ Recorder 0.6.5

Recoverable audio timing errors now warn and continue recording. The previous
helper aborted when audio sample counts drifted 100 ms from device timestamps;
on the tested device, ordinary clock skew reached that limit after about 29 minutes.

Small differences are corrected gradually with audio resampling. Missing audio
is filled with silence, overlapping/stale audio is trimmed or discarded, and
large forward gaps resume at the next audio timestamp without allocating an
unbounded silence buffer. Video recording continues. An orange warning remains
visible during and after the recording.

Unrecoverable errors still attempt to drain the encoders and finalize a playable
partial file. Disk or encoder failures cannot be guaranteed recoverable. Failed
initialization and failed trailer writes are guarded against unsafe retry.

The App Nap and preview restoration fixes from 0.6.3/0.6.4 remain included.
Separate Apple Silicon and Intel apps require macOS 26 or later; both builds are
ad-hoc signed, not notarized.

See [validation details](https://github.com/Delitants/Elgato-4K60-S-Plus-Recorder/blob/main/docs/VALIDATION-0.6.5.md).
