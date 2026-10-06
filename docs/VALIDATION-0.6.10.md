# 0.6.10 validation

The real FFmpeg 8 media helper was exercised with generated H.264/PCM fixtures. A regression first failed against 0.6.9 because enabling the new option did not move Cues before media. The saved-profile round-trip also failed before implementation.

With the change, structural EBML parsing verifies nonempty Cues before the first Cluster when enabled and the unchanged default end index when disabled. Full decoding and seeking pass. Decoded video/audio frame hashes match with the option on and off. Time splits, size splits and salvage after malformed IPC each retain a usable index and decode successfully.

An 8,300-keyframe fixture exercises the conservative front-index capacity limit without a long recording. It verifies a warning, a valid end index, full video decode, and seeking near the end. The fallback clears the reservation option before FFmpeg's trailer; the reserved area remains a Void and no media is relocated. The bound is based on the bundled FFmpeg 8 muxer's single-video-track CuePoint encoding, using 128 bytes per video key packet plus 1 KiB of overhead. Audio contributes no cues when video exists. Every split resets the count.

The existing core suite, including saved-profile migration, compatibility, timers and window lifecycle, passed. Native UI checks cover the MKV-only setting and persistence. Both architecture bundles are audited for dependency closure, minimum macOS version and strict signatures.

The capture device could not be opened during this session; no live HDMI recording or LG TV/DLNA playback claim is made. Synthetic recordings are temporary and deleted by the tests. This option targets completed MKV files; server/TV seek support remains necessary. MP4 fast start and encoder changes are not part of this update.
