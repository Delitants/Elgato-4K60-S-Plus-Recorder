# Network playback and seeking

In **Settings → Output**, select **Matroska MKV**, then **MKV network playback → Prefer seek index at front**. The setting is optional and defaults off, including for existing saved profiles. It applies to new files and every split part, preserving encoded quality.

The app reserves 1 MiB per MKV for the seeking index. To avoid rewriting a large recording during Stop or a split, it conservatively falls back to the standard end index with a visible warning if the front-index budget is exhausted. Audio/video remain intact. This is intended for completed recordings, not playback while recording.

## Existing MKV files on Windows

Obtain FFmpeg through the Windows builds linked from [FFmpeg's download page](https://ffmpeg.org/download.html#build-windows). In Command Prompt or PowerShell, with ffmpeg.exe on PATH:

```powershell
ffmpeg.exe -n -i "C:\Videos\recording.mkv" -map 0 -c copy -cues_to_front 1 "C:\Videos\recording-seekable.mkv"
```

If ffmpeg.exe is in the current PowerShell directory, use `.\ffmpeg.exe`. Replace the example paths. The command preserves the original and refuses to overwrite an existing destination. It remuxes without re-encoding; allow space for another copy of the file. Wait for it to finish before trying the new file on the TV. Unlike live recording, this offline command may shift the whole output file to put the complete index first.

## Other useful choices

- MP4 fast start is automatic when MP4 is selected, independently of the MKV option. It puts metadata at the beginning for progressive network playback. For split recordings, parts are optimized after Stop so relocation does not block capture. Allow temporary space for one additional part; the original remains intact until the optimized copy is complete. If optimization fails, the app warns and retains the playable original. MOV and MPEG-TS do not receive this optimization. For a recording whose video/audio are compatible with MP4 and the TV, an offline example is `ffmpeg.exe -n -i "input.mkv" -map 0:v:0 -map 0:a:0? -c copy -movflags +faststart "output.mp4"`.
- A shorter keyframe interval, such as two seconds, gives the player more seek entry points. This setting already exists under Video when re-encoding. It can increase file size or reduce compression efficiency; stream copy cannot add keyframes.
- Use codecs supported natively by the specific TV to avoid server transcoding. H.264/AVC 8-bit video and AAC stereo are candidates to test, not a guarantee for an unknown TV model.
- The DLNA server must support seeking and advertise it correctly. A front index cannot fix missing byte/time seeking or unsupported TV codecs. Compare the same file from USB and DLNA to narrow down the problem.

References: [FFmpeg Matroska options](https://ffmpeg.org/ffmpeg-formats.html#matroska), [FFmpeg MOV/MP4 options](https://ffmpeg.org/ffmpeg-formats.html#mov_002c-mp4_002c-ismv), [Serviio developer on transcoding and seeking](https://www.serviio.org/forum/viewtopic.php?f=7&t=15078).
