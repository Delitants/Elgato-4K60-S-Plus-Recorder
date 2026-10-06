# Elgato 4K60 S+ Recorder 0.6.10

Adds **Settings → Output → MKV network playback → Prefer seek index at front** for completed MKV recordings shared over DLNA/HTTP. Video and audio quality are unchanged; each split part gets its own index.

The option is off by default and reserves 1 MiB per file. If its conservative index budget fills, recording continues with a warning and a standard end index, avoiding a full-file rewrite during Stop or splitting. No DLNA compatibility guarantee is made for an untested TV/server.

Separate **macOS-Apple-Silicon.zip** and **macOS-Intel.zip** downloads. Requires macOS 26+. Ad-hoc signed, not notarized.

[Windows repair command and network playback advice](https://github.com/Delitants/Elgato-4K60-S-Plus-Recorder/blob/main/docs/NETWORK-PLAYBACK.md) · [Validation](https://github.com/Delitants/Elgato-4K60-S-Plus-Recorder/blob/main/docs/VALIDATION-0.6.10.md)
