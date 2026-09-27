# Elgato Recorder — first native build

Goal: Direct USB recording from the user's Elgato 4K60 S+ model 20GAP9901,
USB 0fd9:0075, on an Apple M1 Pro Mac running macOS 27. First release:
1080p60 SDR and HDMI audio. 4K is deferred. User authorized proceeding
without an audible source or external monitor; audio and A/V synchronization
must remain explicitly unverified until an audible source can be tested.

Native AppKit window with live HDMI preview, capture status, audio meter,
record/stop controls, save folder selection, and reveal-last-recording.
User-space libusb backend. No firmware changes, kernel driver, or installer.
Local ad-hoc signed Apple Silicon application; bundled libusb dylib.

Pipeline: USB capture worker -> bounded packet reassembly -> timestamped
H.264/PCM frames -> CoreMedia samples -> native preview and AVAssetWriter.
MOV records H.264 without re-encoding; PCM track is provisionally interpreted
as 48 kHz stereo signed 16-bit little endian, based on 4096-byte packets at
21.33 ms intervals. A silent track does not establish correct audible capture.
Recording starts on an IDR frame and preserves relative device timestamps.
Malformed/incomplete frames are discarded; disconnect stops capture and
finalizes a partial recording where possible. UI updates are bounded.

Implementation and validation:
1. Test reassembly using captured USB packets, fragmentation, loss and size bounds.
2. Port the tested capture controls with deterministic stop/close handling.
3. Implement CoreMedia conversion, MOV writer and native preview.
4. Build a relocatable app bundle and ship source/build instructions/licenses.
5. Exercise the actual app on this device, record, decode both tracks, check
   preview and stop/restart behavior. Label all remaining audio uncertainties.

USB control sequence is adapted from Saddytech/elgato4k60sp-linux (GPL-2.0).
This application source is distributed under GPL-2.0; libusb has its own
LGPL license. No Windows binaries or device firmware are bundled.

## Version 0.2 additions

RecordingProfile validates container/codec combinations and supplies native
AVAssetWriter settings. Compressed originals retain their HEVC/H.264 samples;
Mac encoding receives synchronously decoded samples and uses native scaling.
Preview decoding remains asynchronous when not needed by a recording encoder.
Explicit hardware requirements use VideoToolbox specification keys; software
sets hardware acceleration false. Software ProRes is guarded unavailable after
runtime tests. Recorder format equality checks prohibit changes mid-file.

AudioMonitor converts captured PCM to planar float for AVAudioEngine, with a
maximum of eight queued packets and generation-safe completion accounting.
Video display and audio playback toggles never gate media passed to recording.
RecordingDeadline uses system uptime independently of incoming media timestamps.
Stop cancels a pending start; workerActive prevents reconnect until teardown;
finalization completes before shutdown callbacks. The USB connection retries
once after a failure, including a one-second settling interval.
