# Elgato 4K60 S+ Recorder 0.6.1

Native macOS ARM and Intel builds. Requires macOS 26+; NDI runtime is bundled.

![Elgato Game Capture 4K60 S+](https://raw.githubusercontent.com/Delitants/Elgato-4K60-S-Plus-Recorder/main/docs/images/elgato-4k60-s-plus.png)

![Elgato Recorder live preview (0.4.1 interface)](https://raw.githubusercontent.com/Delitants/Elgato-4K60-S-Plus-Recorder/main/docs/images/elgato-recorder.png)

- Fixed uneven live preview timing caused by displaying frames immediately on
  arrival. Frames now receive host-clock display deadlines from media timestamps.
- Bounded preview queues absorb short bursts and retry renderer backpressure.
  Preview restarts its timeline after long stalls instead of building a backlog.
- Recording, encoding, USB settings and NDI frame timing are unchanged.

At a requested 200 Mbps, a live run averaged 137 Mbps received and maintained
25 fps display deadlines with no skipped slots after warmup. The renderer
reported zero dropped frames. Hardware decode remained below 12 ms in this run.
The old preview path showed a 24 ms 95th-percentile timing error at 25 fps.

Output FPS still applies to preview. Converting 59.94 fps to 25 fps cannot retain
every motion frame or create interpolation; select Match incoming stream for
full incoming motion cadence. The small bounded pacing buffer adds preview delay
but cannot accumulate an unbounded playback backlog.

See [validation details](https://github.com/Delitants/Elgato-4K60-S-Plus-Recorder/blob/main/docs/VALIDATION-0.6.1.md)
and [sources](https://github.com/Delitants/Elgato-4K60-S-Plus-Recorder/blob/main/SOURCES.md).
The screenshot is the user-supplied 0.4.1 capture. Builds are ad-hoc signed, not
notarized. Intel checks use Rosetta, not physical Intel hardware. USB 2, source
HDMI timing detection, HDR transcoding and gradient-banding origin remain
unverified or unsupported as described in the README.
