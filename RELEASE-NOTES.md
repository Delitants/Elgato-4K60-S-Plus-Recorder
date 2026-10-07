# Elgato 4K60 S+ Recorder 0.6.12

Adds **Settings → Video → H.264 level**: Auto, 3.0, 3.1, 3.2, 4.0, 4.1, 4.2, 5.0, 5.1 and 5.2. Works with hardware and software H.264 encoding in MOV, MP4, MKV and MPEG-TS. Existing settings retain Auto. Original device stream and other codecs cannot use this override.

Explicit levels validate actual output resolution, frame rate and requested bitrate, constrain encoder bitrate/reference-frame settings, and verify the encoded H.264 level. Incompatible combinations report an error instead of silently raising the level. Auto profile resolves to High when a level is explicit; software presets can emit a compatible lower profile, so bitrate limits remain conservative for all profiles. Explicit levels also impose a bitrate ceiling in constant-quality mode.

For Full HD compatibility, 4.1 permits up to 30 fps and 4.2 permits 60 fps. This update does not establish LG TV/DLNA seeking compatibility.

Separate **macOS-Apple-Silicon.zip** and **macOS-Intel.zip** downloads. Requires macOS 26+. Ad-hoc signed, not notarized.

[Validation](https://github.com/Delitants/Elgato-4K60-S-Plus-Recorder/blob/main/docs/VALIDATION-0.6.12.md)
