# Elgato 4K60 S+ Recorder 0.6.13

Fixes unexpectedly large hardware H.264 constant-quality recordings when an explicit H.264 level is selected. Version 0.6.12 added a rate-limit control that made VideoToolbox derive an implicit bitrate target, interfering with CQ. Hardware CQ now uses the encoder's profile/level setting without that extra rate-limit control. The selected level is still verified in the encoded stream.

MP4 and MKV use the same CQ encoder settings. The fix preserves CQ, profile, level and keyframe choices; switching container is unnecessary. Existing oversized recordings are unchanged.

Separate **macOS-Apple-Silicon.zip** and **macOS-Intel.zip** downloads. Hardware CQ is available in the native Apple Silicon build. Requires macOS 26+. Ad-hoc signed, not notarized.

[Validation](https://github.com/Delitants/Elgato-4K60-S-Plus-Recorder/blob/main/docs/VALIDATION-0.6.13.md)
