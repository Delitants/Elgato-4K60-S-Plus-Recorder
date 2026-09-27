# Execution status

This is the original implementation checklist, retained for design history. For the
shipped feature set and tested limits, see ../README.md and ../VALIDATION.md.
Native execution is complete for the supported 0.3.0 scope. Precise forced-keyframe
splitting, automatic HDMI source detection, physical Intel/HDR testing and an
extended failure/soak matrix remain outside the verified release.

# Expanded Recording and NDI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Deliver the approved advanced recording controls, codecs, containers, splitting, and bundled NDI sender without regressing live preview.

**Architecture:** Keep native AppKit and USB acquisition. Introduce independently bounded recording and NDI sinks, a timestamped IPC media helper using FFmpeg libraries, and a separate NDI helper loading the app-bundled runtime. Preserve the working native recorder for existing configurations.

**Tech stack:** Swift/AppKit, CoreMedia/VideoToolbox, C++17 helper, installed FFmpeg 8.1 libraries, official macOS NDI SDK/runtime; arm64, macOS 26+.

**Spec:** [Approved design](EXPANDED-OUTPUT-PROPOSAL.md).

## Global Constraints

- Preserve 1080p60 and 4K capture, independent video/audio monitoring, the recording timer, and the preview latency fix.
- Test recordings must be deleted after verification.
- Bundle the permitted macOS NDI runtime inside the app (Contents/Frameworks), and load it by its bundle-relative path.
- The recorder must not require a separate system-wide NDI installation.
- No Dolby/DTS capture option: source audio is stereo PCM.
- Original video bypasses encoder controls and scaling.
- Do not promise 4K60 software AV1; measure sustainable throughput and expose overload clearly.
- Existing user recordings, settings, and release 0.2.1 remain recoverable. Build the candidate separately until verified.
- Do not introduce a GPL-linked NDI/FFmpeg binary. Check upstream and existing GPL-derived code licensing before distributing the combined package; process separation alone is not a legal conclusion.
- No Git repository is currently established for this app; record milestones in the plan rather than fabricating commits.

## Review Focus

- Existing saved profiles missing new fields must migrate without losing user selections (Task 1).
- Disk full, helper exit, and slow output must stop recording cleanly without freezing acquisition or preview (Tasks 2–3).
- B-frame reorder and codec priming at split boundaries must not produce invalid timestamps or audible gaps (Tasks 3–4).
- Disconnect, reconnect, and format changes during recording/NDI must release resources and visibly report state (Tasks 2, 5–6).
- A clean installation with no global NDI library must load the bundled runtime; missing OBS receiver support must not be reported as a sender success (Tasks 6–7).

## Milestones and file responsibilities

A: Advanced recording (Tasks 1–4), B: Native settings integration (Task 5), C: Bundled NDI and release validation (Tasks 6–7). Each milestone has its own working acceptance criteria; the full request completes only when all pass or physical-source limitations are explicitly reported.

Keep existing USB/parser code stable. New Swift files: EncoderCapabilities.swift (validation), RecordingSink.swift (sink contract), CaptureFanout.swift (bounded delivery), MediaHelperClient.swift and MediaIPC.swift (helper communication), SegmentPolicy.swift (split decisions), NDIOutput.swift (sender lifecycle). New helper sources under Helpers/Media and Helpers/NDI. Keep code units focused; Settings.swift remains the AppKit settings entry point.

### Task 1: Typed settings, migration, and capability validation

**Files:** Modify Sources/Profiles.swift, Tests/ProfileTests.swift, test.sh; create Sources/EncoderCapabilities.swift, Tests/CapabilityTests.swift.

**Interfaces:** Extend RecordingProfile with typed codec/container/rate-control/scaling/profile/preset/split options while retaining legacy decoding. Define EncoderCapabilities.validate(profile: RecordingProfile) throws and availableOptions(profile: RecordingProfile) -> [String: [String]]. Add SplitPolicy.off, .time(seconds: Double), .size(bytes: Int64); ScalingFilter.disabled, .bilinear, .area, .bicubic, .lanczos. Use optional keyframe interval (nil = Auto), optional B-frame count (nil = encoder default), and AQ auto/enabled/disabled.

- [ ] Add failing tests: legacy JSON with only current keys retains every old selection; new fields obtain conservative defaults; unknown future enum values produce an actionable error rather than crash.
- [ ] Add matrix tests: MKV accepts AV1/Opus and AV1/FLAC; TS initially accepts H.264/HEVC plus AAC only; original video rejects rescaling/encoder overrides; lossless audio rejects bitrate mode; baseline H.264 rejects B-frames; forced AV1 hardware is rejected.
- [ ] Run `bash test.sh` from the app source folder and confirm the new tests fail for missing behavior.
- [ ] Implement migration and capability records from encoder discovery, not a universal list of fake controls. Preserve current defaults. Provide explicit reasons for unsupported CRF/AQ/profile combinations.
- [ ] Re-run `bash test.sh`; all old and new tests must pass.

### Task 2: Bounded fanout and recording lifecycle

**Files:** Create Sources/RecordingSink.swift, Sources/CaptureFanout.swift, Tests/FanoutTests.swift; modify Sources/CaptureEngine.swift, Sources/Media.swift, test.sh.

**Interfaces:** RecordingSink.offer(_ sample: CMSampleBuffer, type: UInt8, key: Bool) -> Bool; finish(completion: @escaping (Result<[URL], Error>) -> Void). CaptureFanout routes retained immutable samples to independent workers. False from recording offer means terminal recording overload, never a silent packet drop. Adapt MovieRecorder behind the contract without changing native file behavior.

- [ ] Add failing tests for a paused sink, overflow, disconnect during finish, and exactly-once completion. Bound recording ingress to 64 MiB and 500 ms of source timestamps, whichever is hit first; bounds must include queued IPC writes. Decoded preview keeps only the latest frame; NDI limits are defined in Task 6.
- [ ] Run `bash test.sh` and confirm the fanout tests fail before implementation.
- [ ] Implement queue ownership and state transitions: idle, starting, recording, finishing, failed. Keep USB acquisition free of sink waits. On overload stop the recorder, report the reason, and continue preview. Change audio-monitor volume only on actual configuration changes.
- [ ] Test slow/failing sinks, quit while finalizing, and source-format changes. Confirm retained memory stays bounded and no callbacks outlive a disconnected session.
- [ ] Run `bash test.sh`; parser throughput regression and existing recorder/monitor tests must remain green.

### Task 3: Timestamped media helper and advanced codecs

**Files:** Create Helpers/Media/{main.cpp,Protocol.hpp,Encoder.cpp,Muxer.cpp}, Sources/{MediaIPC.swift,MediaHelperClient.swift}, Tests/MediaHelperTests.swift, test-advanced.sh; modify build.sh and capability routing.

**Interfaces:** Protocol version 1: little-endian header with magic, version, message type, payload length; setup JSON followed by audio/video packets carrying signed 64-bit PTS/DTS/duration in microseconds, key flag, and format generation. Limit individual messages to 16 MiB and validate before allocation. Use original Annex-B compressed video and signed 16-bit stereo 48 kHz PCM. Setup carries codec configuration and desired settings; replies carry effective settings, errors, and final output URLs. Reject unexpected versions/types and truncated messages. MediaHelperClient implements RecordingSink.

- [ ] Write failing framing tests for fragmented reads, oversized lengths, missing setup, EOF mid-packet, timestamp discontinuity, and helper crash. Reject non-monotonic source timing; preserve encoder-produced PTS/DTS rather than forcing equality.
- [ ] Add short fixture cases for AV1+Opus MKV, AV1+FLAC MKV, H.264/HEVC AAC TS, existing MOV/MP4, and software/hardware H.264/HEVC controls. Assert requested encoder selection and effective options, dimensions, channels, and sample rate using ffprobe.
- [ ] Run `bash test-advanced.sh`; confirm failure before implementation. Use a trap-owned temporary directory for every media fixture and log output; preserve only concise text evidence.
- [ ] Implement libavcodec/libavformat mux/encode pipeline, libswscale filter mapping, resampling, and timestamp handling. Map presets, ABR/CBR/CRF, keyframe interval, B-frames, codec profiles, and AQ only to verified encoder options. Opus exposes its supported bitrate modes; FLAC exposes validated effort range. Discover actual encoder option bounds rather than assuming them.
- [ ] Implement decoder Auto/Require hardware/Software choices and report the effective decoder. Fail explicitly if required hardware is unavailable. Avoid silently degrading unsupported HDR: retain native original HEVC HDR path; only enable new HDR paths after metadata and 10-bit checks pass.
- [ ] Run `bash test-advanced.sh`; decode every produced file fully with ffmpeg and assert nonzero frames, valid timestamp ordering, expected audio length, and color metadata where applicable. Exercise disk-write failure and unavailable encoder. CRF must not accidentally inherit an ABR bitrate target; CBR verification must account for encoder/container semantics.
- [ ] Run `bash test.sh` and `bash test-hdr.sh`; preserve native-path and HDR regression results.

### Task 4: Time and size splitting

**Files:** Create Sources/SegmentPolicy.swift, Tests/SegmentTests.swift; extend Helpers/Media/Muxer.cpp, MediaHelperClient.swift, test-advanced.sh. Route split-enabled recording through the segment-capable helper, including original-video passthrough.

**Interfaces:** SegmentPolicy.shouldRequestBoundary(elapsed: Double, writtenBytes: Int64) -> Bool. Muxer owns keyframe-aligned rotation, monotonically numbered filenames, per-file timestamp rebasing, and reported finalized URLs. The whole-session timer remains in CaptureEngine.

- [ ] Add failing tests for threshold crossings, first keyframe after threshold, filenames with existing parts, timer stop during pending split, and split-disabled behavior.
- [ ] Add a fixture with B-frames and continuous audio across multiple short segments; assert each part independently decodes and ordered segment contents reconstruct continuous timestamps within one video frame/audio packet of documented boundary behavior.
- [ ] Run `bash test-advanced.sh` and confirm split cases fail before implementing rotation.
- [ ] Implement forced keyframes for transcoding and next-source-keyframe splitting for passthrough. Drain/rebase muxed streams correctly; account for reordered packets and audio encoder priming. Carry valid codec configuration into each new part. Never overwrite existing files. Explain possible size overshoot in UI.
- [ ] Run both test scripts; test failure to create the next part and stop/quit at a boundary. Every finalized part must remain playable, and every test recording must be removed.

### Task 5: Native controls and live recording acceptance

**Files:** Modify Sources/Settings.swift, Sources/App.swift, Sources/CaptureEngine.swift; add Tests/SettingsStateTests.swift; update README.md, VALIDATION.md.

**Interfaces:** RecordingSettings edits a draft profile, validates through EncoderCapabilities, and applies atomically. Existing preview/monitor toggles and recording timer retain their current interfaces. Expose actual encoder, progress, errors, and current segment in CaptureState.

- [ ] Write failing state tests for changing codec/container while editing, cancelling changes, persisting and restoring new settings, and preventing incompatible active-recording reconfiguration.
- [ ] Run `bash test.sh` and confirm missing state behavior fails.
- [ ] Build native Video, Audio, Output, and NDI sections. Include every approved control with units/defaults and concise explanations when disabled. Use screenshot algorithm names without claiming OBS's exact sample counts. Keep Dolby unavailable with the documented device explanation.
- [ ] Run `bash test.sh`, `bash test-advanced.sh`, and build the separate candidate app. Exercise all controls in the live native UI, including toggling both previews, selecting encoding modes, splitting, and timer stop.
- [ ] Make bounded live recordings at 1080p60 and 4K; fully decode results. Check source-relative timing drift and queue depth with simultaneous preview/monitoring. Test a deliberately overloaded software configuration and confirm prompt failure without preview backlog. Report absolute HDMI latency as unmeasured unless a synchronized physical source is available.
- [ ] Delete only generated test files and caches, recording their paths and cleanup result in concise validation evidence.

### Task 6: App-bundled NDI sender and OBS reception

**Files:** Create Helpers/NDI/{main.cpp,NDILoader.cpp}, Sources/NDIOutput.swift, Tests/NDIOutputTests.swift, test-ndi.sh; modify build.sh, CaptureEngine.swift, Settings.swift, licenses/documentation.

**Interfaces:** NDIOutput.start(name: String, width: Int, height: Int) throws; offerVideo(_ sample: CMSampleBuffer); offerAudio(_ sample: CMSampleBuffer); stop(). NDI helper dynamically loads Contents/Frameworks runtime using an absolute bundle-derived path, exchanges versioned timestamped messages, and reports initialization/connection/error state. Default disabled; default output 1080p with optional source resolution.

- [ ] Verify permitted official macOS SDK redistribution files, runtime architectures/dependencies, actual license text, and compatibility with the existing GPL-derived application. Record provenance and hashes. If the legal architecture cannot satisfy both licenses, resolve it before linking/distributing; do not claim subprocess separation alone resolves it. Obtain user action only if vendor account or legal acceptance requires it.
- [ ] Add failing tests using a mock runtime for load failure, initialization failure, receiver loss, restart, and capture disconnect; assert recording remains independent.
- [ ] Run `bash test-ndi.sh` and confirm unimplemented lifecycle cases fail.
- [ ] Implement sender with supported decoded video format and 48 kHz stereo audio. Keep at most two decoded video frames and 100 ms audio pending, bounded across IPC. Drop stale video with correct ownership; discard obsolete audio with explicit clock reset rather than accumulate delay. Monitor enabled state and scale NDI independently from recording.
- [ ] Bundle the runtime and required notices; sign embedded components before the outer app. Include required NDI attribution/link in its settings and About/documentation. Do not bundle unrelated NDI Tools. Reject unsupported HDR NDI output explicitly.
- [ ] Run `bash test-ndi.sh` and verify the exact loaded library path is inside the candidate app, with global-runtime search disabled. Verify all non-system dependency paths are portable.
- [ ] Install supported DistroAV/receiver dependencies if absent, preserving OBS settings. In OBS, observe source discovery, moving picture, and audible stereo from the actual device. Test sender off/on, receiver reconnect, concurrent recording, and source disconnect. Distinguish no receiver from sender failure.

### Task 7: Release integration, icon, and final review

**Files:** Modify build.sh, README.md, VALIDATION.md, Licenses/THIRD-PARTY.txt; create dependency manifest and release checksum. Icon proposal resides separately in outputs/icon-proposals until selected.

- [x] User selected capture-frame-v1.png. Created Resources/Recorder.icns, added CFBundleIconFile to the app and build script, and verified bundle metadata and code signature.
- [ ] Check Finder/Dock appearance after the next safe app relaunch; do not interrupt active capture just to refresh the cached icon.
- [ ] Run `bash test.sh`, `bash test-hdr.sh`, `bash test-advanced.sh`, and `bash test-ndi.sh`; collect a short pass/fail matrix and remaining physical HDR limitations.
- [ ] Verify signed candidate dependencies with `otool -L`, architecture with `lipo -info`, and signing with `codesign --verify --deep --strict`. Include the required FFmpeg and NDI distribution materials and dependency versions.
- [ ] Complete a fresh integrated code review focused on queue ownership, IPC bounds, timestamps, container compatibility, settings migration, and finalization. Resolve substantive findings and rerun affected tests.
- [ ] Replace the running app only after recordings are stopped and finalized. Retain the prior release archive for rollback. Verify launch, settings migration, USB capture, recording, and NDI reception in the delivered app.
- [ ] Remove all generated test recordings/caches; package the new app/source and checksum. State exactly which capabilities were verified on physical hardware and which only with fixtures.

## Handoff

Design is approved. Plan execution awaits user review and method selection. Recommend native execution in this session because capture ownership, settings, and helper protocols are tightly coupled; one fresh integrated review follows implementation. Subagent-driven execution is the alternative for independent task-by-task reviews with additional context overhead.
