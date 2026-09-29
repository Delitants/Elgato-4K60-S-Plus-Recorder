# Recording backpressure recovery

Goal: keep recording through recoverable queue/pipe stalls, including preview-off minimized operation.
Architecture: retain the 64 MiB compressed-data bound. When the queue is full or old, drain accepted packets, skip new input, then resume both streams at a video keyframe with original timestamps. Report persistent warnings and skipped counts. Preserve IPC framing across a temporary pipe stall; a dead or indefinitely stalled helper remains a terminal error. Reset decoder and film state at the discontinuity without restarting the output container.

- [x] Reproduce the existing abort with a suspended real helper, after startup grace.
- [x] Implement bounded queue recovery and keyframe resumption in RecordingSink; add helper discontinuity message and bounded pipe waiting.
- [x] Verify age/capacity, repeated stalls, decode and A/V timestamp alignment; run existing core/rate/audio tests and independent review.
- [x] Run native preview-off/minimized hardware recording with a forced stall; stopped at 6:37 at user request instead of a long soak. Full decode passed; disposable capture deleted and user file preserved.
- [ ] Build/audit both architectures, install and publish the verified version with scoped validation notes.

Limits: existing release logs identify queue rejection but cannot distinguish the original encoder, scheduler, or filesystem stall. Do not attribute it to App Nap without evidence. No unbounded buffers, arbitrary compressed-frame resumption, or changes to encoding quality.
