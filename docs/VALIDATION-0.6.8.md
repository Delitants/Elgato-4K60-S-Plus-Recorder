# 0.6.8 — window-close shutdown validation

Tested on 2026-09-29 with an Apple M1 Pro, macOS 27.0 (26A428), and the
Elgato 4K60 S+ model 20GAP9901 over USB 3.0. Release: 0.6.8, build 17.

## Reproduction and change

The supplied 0.6.7 crash report showed an invalid retain of the main window from
`AppDelegate.refresh()` while AppKit waited for deferred termination. Closing the
installed 0.6.7 window reproduced the same crash. The direct NSWindow instance
used AppKit's close-time release behavior while the Swift delegate and refresh
timer still referenced it.

The window now disables close-time release. Main-window close and Quit stop UI
refresh and preview presentation immediately; queued callbacks ignore closing UI.
Repeated Quit requests do not start a second disconnect. Asynchronous capture
shutdown and recording finalization remain intact. No capture, encoder, audio,
or cadence implementation changed in this release.

## Verification

- New real-AppDelegate regression failed before the patch: closing the window
  left its refresh timer active. It passes with the patch on ARM and x86_64
  under Rosetta. It covers timer invalidation, queued refresh, unrelated windows,
  and one deferred termination reply for repeated Quit requests.
- The complete `test.sh` suite passed, including recording assertions and decoded
  film-preview cadence tests.
- Native candidate: closing during live preview exited without a crash.
- Native candidate: closing during recording finalized a 13.879-second H.264/AAC
  MKV. Full video and audio decode completed without errors.
- Installed `/Applications` build: Command-Q during recording finalized a
  25.873-second H.264/AAC MKV. Full video and audio decode completed without
  errors. An audio-clock warning occurred during this test and recording continued.
- Installed build: closing during live preview exited normally after restoring
  the user's recording destination. App and media helper processes exited, and
  no new crash report appeared after the pre-fix reproduction.
- Both release bundles passed strict signature checks, architecture checks,
  bundled dependency closure, and Mach-O minimum-OS audit (26.0 or earlier).
- Two disposable recordings (3,349,886 bytes total) were removed after validation.
  The user's existing recordings were preserved.

## Scope

The focused automated test delivers a close notification to an invisible window;
it does not alone test AppKit's actual close-time ownership. Native close/Quit
checks above cover that path. Intel was tested under Rosetta, not on a physical
Intel Mac. This lifecycle-only update did not repeat the 55-minute hardware soak
from [0.6.7](VALIDATION-0.6.7.md), test 4K/HDR, or test every recording container.
Builds are ad-hoc signed and are not notarized.
