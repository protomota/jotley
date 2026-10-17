# Source snapshot verification

## iPad Settings placement preview — October 15, 2026

The iPad Settings gear moves to the bottom-left of the notes column, opposite +. Native navigation chrome keeps window controls above Search, including compact iPad layouts; the iPhone header position is unchanged. Local iPad Pro 13-inch (M5), iPadOS 27 checks passed for portrait/landscape, Light/Dark, alignment and opening/dismissing Settings. An actual resized Simulator window passed Settings/Search interaction checks, and the test restored full screen afterward. The final iPhone 17 Pro Max regression passed in both appearances. No failures/skips in the final runs. Native screenshots were inspected; physical iPad testing was not performed. The screenshot was reviewed and approved before uploading TestFlight 2.0 (361). The iPhone gear remains at the top; only iPad uses the bottom-left placement. The signed package passed its identity/version, device-family, widget-version, code-signature, background-processing and Foundation Models linkage checks.

## Mobile glass controls and readable actions — October 15, 2026

Native UI checks passed on iPhone 17 Pro Max and iPad Pro 13-inch (M5), iOS/iPadOS 27: Done placement and dismissal across Settings, folders, folder management, Filter & Sort and Ask AI; actual rendered contrast in dark appearance; readable selected Settings values after switching to light; and Purple/Orange theme changes. The version/build line remained visible and correctly formatted after scrolling. Native screenshots were inspected. A stale selected-value tint discovered during Light/Dark switching was reproduced by a pixel assertion and fixed with explicit theme-aware labels around native selection menus.

Actual Apple model Ask AI answers and compact Copy/Share controls passed on both simulators. Stop/Done completion and rejection of late transcript updates also passed on both. The summary modal/Markdown regression passed in both appearances. These are simulator checks; physical microphone and locked-device behavior were not retested. The unsigned Mac build passed for the shared files.

## Summary editor and Markdown lists — October 15, 2026

Three UI scenarios passed on both the iPhone 17 Pro Max and iPad Pro 13-inch (M5), iOS/iPadOS 27 simulators: summary modal Save/Cancel and reopening in light/dark appearance; transcript editing and conditional menu availability; and repeated template switching with a 500-item summary. Three focused unit cases also passed on both devices for summary persistence and stale-draft rejection, transcript/timestamp preservation, and Markdown bullet/numbered/nested-list parsing with inline bold formatting. No failures or skips. Native screenshots were visually inspected. These checks do not establish physical-device behavior.

## Initial snapshot

The clean public snapshot was checked on macOS 27 with Xcode 27.

- The exported shared Swift package passed 25 tests with seven explicitly skipped opt-in model checks.
- Both exported app projects built: unsigned Mac Debug and unsigned Release iPhone/iPad SDK builds.
- iPhone core/model checks: 36 passed; one real-speech check explicitly skipped because Apple exposed no compatible installed speech audio format in Simulator.
- iPhone UI checks passed for summary auto-follow/pinned Cancel, Stop/Close, and real Apple model summary/title regeneration.
- iPad summary auto-follow/pinned Cancel and current screenshot captures passed. The refreshed iPad capture run also verifies the native sidebar divider in light and dark appearance; the README image uses the original exported PNG.
- A real Apple model summarized a multi-chunk note into one consolidated result and finished.
- The Mac routing harness passed 17 groups. The separate mounted summary test followed two content growth steps, confirmed a visible pinned Cancel footer, and cancelled the actual task with Escape while preserving the saved summary.
- Release binary inspection excluded all Debug-only live/summary test injection. Foundation Models linkage checks passed.
- The exported tree was scanned with a credential-pattern audit and checksum-verified Gitleaks 8.30.1. Final scans reported no findings. These are heuristic scans, not a guarantee that every possible secret can be detected.

Physical microphone recognition, prolonged locked-device transcription and device frame-rate measurements are not established by simulator fixtures. The waveform's native layer interpolation and bounded transcript update rate are tested structurally; device performance still needs real-device review.

The public snapshot contains no earlier private Git history, private release workflows, signing credentials/configuration, review contact information, internal audits or Xcode user state. Third-party notices remain included.


Summary progress and immediate regeneration were checked with the actual Apple model. The iPhone simulator reviewed six sections of a 64-paragraph transcript, produced four final-summary snapshots and finished in 12.9 seconds. The native Mac view model regenerated a long transcript in 11.2 seconds with nine snapshots, preserving the title. Tests confirm preparation progress, writing, successful persistence and termination. The real iPhone UI also completed long-note generation with the section indicator visible; separate iPhone/iPad checks cover pinned progress/Cancel, streamed bottom-follow, direct template regeneration and preservation on cancellation. Simulator/model timings do not establish physical-device speed.


## Current distribution — October 15, 2026

The iPhone/iPad build 2.0 (361) was re-verified as VALID / IN_BETA_TESTING in the existing internal TestFlight group. No newer mobile application code was pending. The standalone Mac build 2.0 (362) was built from the same current application source, signed with Developer ID, notarized by Apple, and published at https://jotley.ai/download with a signed Sparkle update feed. All 157 tracked application files compared with this public main snapshot matched byte for byte (excluding reference-only Shared/Docs).

The mounted Mac app passed deep/strict signature and Gatekeeper checks; its original bundle identity, version, enabled Sparkle feed and notarization ticket were verified. The installer layout checks passed. DMG SHA-256: `70ccf1efa21404cac3e939707d7af4f58177cca00542006e2f3085eb9a808930` (4,715,624 bytes). The website production build and all three focused download checks passed locally and on production, including real downloaded bytes and the Ed25519 update signature. Website release commit: [1824a68](https://github.com/protomota/jotley-site/commit/1824a68643dc6b39166be358895b34e06f518f3e).

The shared Swift package passed 25 tests, with seven opt-in model checks skipped and zero failures. This release audit did not repeat physical-device microphone/background or model-performance tests, and did not submit or replace an App Store review build.


## Experimental iPad app on Mac — October 17, 2026

Local crash reports for the installed iPad edition 2.1 (372) on macOS 27.0.1 show a SwiftUI `EnvironmentObject.error()` trap when opening transcription. The transcription sheet now requires its existing session manager as an observed initializer dependency for both new and continued sessions. It no longer relies on sheet environment-object inheritance. The audio capture implementation is unchanged: microphone-only live transcription, with no saved audio files or system-audio capture.

The selected note now has an explicit view identity so its fetch, tab and editing state reset when a different note opens. A regular-width split view and its row/finish navigation now use the same decision; a missing size class uses stack navigation. The note-selection regression failed against the previous view identity, even allowing five seconds for the Summary action to appear, and passed with the fix. The test repeatedly switches a summarized note and a transcript-only note, then continues transcription into the correct note.

The Designed for iPad Mac destination was enabled through Xcode's General settings; no Catalyst target was added. Xcode also normalized the existing source-file reference ordering and moved the microphone privacy string into the generated Info settings. The actual signed development app's prompt was verified to say live on-device transcription with no saved audio files. Local Xcode user state is ignored. The native Mac app source and App Store Connect availability were not changed.

Verification:

- Final iPad Pro 13-inch (M5), iPadOS 27 Simulator: two UI cases passed, zero failures/skips, covering repeated note selection and new/continued transcription, Stop/Done completion, automatic opening of the saved note, and rejection of late callbacks. Result: `/tmp/jotley-ipad-on-mac-final.xcresult`.
- iPhone 17 Pro Max, iOS 27 Simulator: start/stop/Done/continue lifecycle regression passed, zero failures/skips. Result: `/tmp/jotley-ipad-on-mac-phone.xcresult`.
- An initial note-selection test referenced an obsolete button identifier; corrected before the final verification. The separate comparison with the previous note identity is an expected failing regression check, not a passing result.
- Shared package: 25 passed, seven opt-in model tests skipped, zero failures.
- Unsigned iPhone/iPad SDK and Simulator builds passed. A real Designed for iPad Mac build signed with the existing development identity/profile passed; its signature and generated microphone privacy text were checked. Signing settings were supplied to the local build command, not stored in source.
- Full on-Mac functional validation remains blocked. The installed iPad edition's native UI connection repeatedly timed out. Xcode rejected the Mac UI-test destination with `UI tests are not supported on My Mac (Designed for iPad)`. An app-hosted microphone check then failed before executing: the test host was killed before establishing its test connection. That unexecuted check was removed. These failures do not establish a sandbox restriction or prove that microphone capture works on Mac.
- Source-tree credential-pattern scan passed with no findings. No new TestFlight build, App Store submission, Mac availability toggle, or website deployment was performed. This branch is a compatibility fix for review, not a verified iPad-on-Mac microphone release.

## Stable streaming summary layout — October 17, 2026

The shared summary renderer now measures its cards eagerly while output grows, instead of relying on lazy estimated heights during repeated scroll-to-bottom updates. A streaming parse holds unfinished heading, bold-heading and list-marker syntax until it can be classified, while normal prose and list bodies keep streaming. Completed summaries and exports still use the full saved Markdown. Overview and section blocks retain their source-line identity, and streaming updates do not inherit layout animations.

- Three iPad Simulator parser regression tests passed: unfinished-structure/card identity, structured summary grouping and inline Markdown/list rendering. The first test command selected only the UI test because the Swift Testing method filters lacked parentheses; the corrected invocation ran all three parser tests successfully.
- The iPad Simulator UI test for following new summary content with Cancel Generation pinned passed.
- A development-signed build for My Mac (Designed for iPad) passed. The installed TestFlight app was accessible on this Mac and a real summary completed, but the short baseline run did not capture the transient defect. Do not treat Simulator checks as proof of the corrected Mac rendering under real model output.
- App display names are already Jotley. macOS had named the second local installation Jotley 2 to avoid a filename collision. The iPad copy was moved into its own Applications subfolder and renamed Jotley; the native Mac app was preserved. No source bundle identity was changed.
