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

Follow-up: streaming filler prefixes (for example `- No decisions are…`) are held until the line ends, so the existing completed-summary filler filter does not first create and then remove a card. Legitimate points starting with No are retained once complete. Both the expanded streaming-prefix regression and the structured-summary grouping test passed on iPad Simulator.

The streaming regression now checks every character prefix of None, Nothing, N/A and a complete No-decisions filler sentence, including intermediate Non/Noth fragments. This exhaustive prefix test passed on iPad Simulator.

## Library-aware summary tags and sidebar controls — October 17, 2026

Every successful summary/regeneration now requests up to five broad topic tags from the installed Apple model. A bounded library snapshot prioritizes relevant and established buckets; exact spelling, punctuation/case aliases and common AI aliases resolve to existing Tag entities. A completed save replaces only this note's tag relationships. Other notes and the library remain intact. Cancellation or a tagging error preserves existing tags; a tagging error still saves the completed summary and reports that tags were kept. Summary fields, tag relationships and any new Tag entities roll back together after a rejected save.

The iPad edition on Mac uses ordinary date rows in place of pinned date headers. The installed 379 app reproduced blur over prior date groups while their labels remained readable through accessibility; this workaround removes those header material surfaces. Real iPhone/iPad devices retain native pinned headers. A Simulator-only override exercises the Mac presentation without compiling a test switch into releases.

The native Mac + action moved from the note detail header to the bottom right of the notes list. Settings is at bottom left. Both float over the list without the old toolbar strip, border or trash button; existing menu/keyboard deletion remains available.

Verified before packaging:

- Shared package: 36 tests executed, eight opt-in hardware/model tests skipped, zero failures (28 passed). Covers tag replacement, entity reuse, five-tag cap, aliases, bounded large-library candidates and transactional rollback while preserving unrelated edits.
- Installed Apple model acceptance test passed separately in 1.46 seconds, selecting the existing AI and Design buckets without Gardening; cancellation passed. An earlier longer instruction triggered an Apple guardrail; simplified classification instructions passed. This is one synthetic acceptance example, not a guarantee for every note or language.
- iPad Simulator summary-manager integration passed: success replaces tags, failed tagging retains tags and saves the summary, cancellation during tagging preserves the previous summary and tags.
- Native Mac signed development build passed. The existing Mac routing/UI harness passed with the added real-view-model tagging checks. The actual native Mac window was inspected: gear bottom left, + bottom right, no trash or footer strip, no + in note detail.
- All 198 tracked public source/assets passed the existing credential-pattern heuristic with zero findings. This is a pattern scan, not a proof of absence.

Simulator visual verification initially hit a runner launch failure and then an incorrectly oriented screenshot measurement. The pixel check was corrected to use a portrait full-screen capture and cached geometry. Final iPad Simulator scrolling check passed in dark and light appearances: 48 fixture notes across 16 dates, repeated scrolling in both directions, note selection and pixel-level title contrast checks. Result: `/tmp/jotley-sidebar-inline-v6.xcresult`. No tutorial changes are part of this update.


Released as iPhone/iPad 2.1 (381) and native Mac 2.1 (382), from public source `1abb207` / private release source `a7f673d`. Apple verified 381 as `VALID / IN_BETA_TESTING`, available in Jotley Home ([upload](https://github.com/protomota/jotley-app/actions/runs/39064690464), [verification](https://github.com/protomota/jotley-app/actions/runs/39064913427)). The signed IPA and widget preserve the original bundle IDs, production iCloud entitlement and no-debug entitlement; Simulator data/layout switches are absent, and the Foundation Models linkage check passed. IPA: 6,267,122 bytes, SHA-256 `e7388b8b29f08de12393391f0388e5e6baba7b7cba08eaa4fbdb55faff33657d`.

[Mac build 382](https://github.com/protomota/jotley-app/actions/runs/39064692057) passed notarization, strict/deep signature verification and Gatekeeper assessment. DMG: 4,832,612 bytes, SHA-256 `e2e0111c5159cb8f43c70e0f4a0cb30038055355fdf2e557ef154a45f37cc3fd`. The website production build and all three download tests passed, including the Sparkle Ed25519 signature. Website commit `3ef1818` deployed with production target READY; the live /download page shows 382, and bytes downloaded through its button match the signed artifact. No App Store review submission or tutorial changes were made.


After release, TestFlight 381 was installed on this Mac. Browsing older date groups, selecting a note and scrolling in both directions kept titles/previews sharp where 379 had shown blurred rows. The installed native Mac 382 was also launched and its floating sidebar controls were visually confirmed. New Note and Settings were functionally checked in the identical development layout. Proof images remain local; no private note content was added to the repository.

## Direct Mac transcription and terminology — 2026-10-17

Mac sidebar +, welcome action and Command-N now call the existing new-transcription start route immediately. Startup disables duplicate entry and hides the secondary Continue Transcription action. User-facing recording terminology was replaced across both apps, including accessibility labels, menus, Settings, permissions and errors. Persisted storage paths, widget identifiers, serialized activity attributes and legacy inbound URLs remain compatible. Native Mac audio recovery is unchanged; iPhone/iPad sessions remain transcript-only.

Verification: signed development Mac build passed; shared package executed 36 tests with eight opt-in skips and zero failures (28 passed). Mac routing harness passed, including a simulated capture-start rejection that verifies immediate dispatch, one new note, duplicate-start protection and lease cleanup. iPad Simulator Settings placement/appearance test passed. Source credential-pattern scan: 198 tracked files, zero findings. No tutorial changes.

The initial hosted-sidebar test failed because its copied Core Data model made global entity lookup ambiguous; it was replaced with the real view-model lifecycle regression above. Manual development-app UI confirmed one + press creates the note and enters startup with the second action hidden; this environment remained waiting during hardware authorization, so actual microphone recognition was not verified in this turn. Existing speech tests were not rerun on physical iPhone hardware.

Released as iPhone/iPad 2.1 (384) and native Mac 2.1 (383), from public source `5cebefb` / private release source `19beabb`. Apple verified 384 as `VALID / IN_BETA_TESTING`, available in Jotley Home ([upload](https://github.com/protomota/jotley-app/actions/runs/39066143594), [verification](https://github.com/protomota/jotley-app/actions/runs/39066429241)). The signed IPA and widget preserve original bundle IDs, production iCloud and distribution entitlements; Simulator switches are absent and the Foundation Models linkage/background-registration checks passed. IPA: 6,267,219 bytes, SHA-256 `64725569f07782c23dc96f8c94bf5995b0df83605af5be3b707cc2f06e730f86`.

[Mac 383](https://github.com/protomota/jotley-app/actions/runs/39066141875) passed notarization, deep/strict signature verification and Gatekeeper. The first two CI attempts failed while copying into the disk image; the unchanged third attempt succeeded. The same packaging script also passed locally against installed 382. No packaging-code change was needed. The final 383 installer passed layout and bundled-byte checks before and after notarization. DMG: 4,835,056 bytes, SHA-256 `5b97f543cb56b3adede6207048e5ad64076389343e3fbadf088aabc2aff09c8e`.

Website commit `65de1ba` passed the production build and three focused download tests, including the Sparkle Ed25519 signature. Deployment `dpl_939VpN8frw3VNT8toVDdNfiDWTFv` reports production READY. The live /download page shows 383, and the installer downloaded through its actual button has the exact artifact hash above. Its appcast was updated with the signed 383 enclosure. No App Store review submission or tutorial changes were made. Hardware microphone recognition was not retested in this turn; the Mac start lifecycle and failure cleanup were verified using the Debug-only injected start hook, which is absent from Release.

## Summary-ready local notifications and Settings hit area — 2026-10-18

Version 2.2 adds local UserNotifications alerts on Mac/iPhone/iPad after successful summary persistence. Consent is requested alongside the first user-started summary, never on launch. A Settings toggle defaults on, subject to system permission. Alerts contain a generic title/body and only a note UUID; tapping opens the matching summary. No APNs registration or remote service is used. Cancelled and failed generation paths do not notify; a saved summary with a tagging warning does notify. The full Settings button label has an explicit circular hit shape on iOS/iPadOS and native Mac.

Passed: native Mac signed development build and routing harness, including save-before-delivery and failed-generation checks; three focused iPad Simulator tests for consent, disabled/denied settings, duplicate prevention, successful/tag-warning saves, cancellation/failure, and actual delivery through UNUserNotificationCenter after a simulated summary was saved. The real OS-delivery test was not skipped. The iPad UI test passed taps on four cardinal edges outside the gear glyph, in portrait/landscape and Light/Dark. No physical iPhone background notification delivery has been tested yet.

An initial full iOS test run hit an existing global Core Data entity lookup ambiguity in the model-acceptance suite after the long-summary acceptance check passed; the speech hardware check skipped because no usable speech model was available. That crashed run was stopped. Focused notification/integration tests then passed. An initial Settings UI attempt was blocked by the outstanding system notification permission alert; it passed after the test handled that specific alert. Source credential-pattern scan: 198 tracked files, no findings. This is a heuristic, not proof that secrets cannot exist.

Before release, read-only App Store status confirmed version 2.1 / build 384 WAITING_FOR_REVIEW. Do not withdraw, replace or submit that version as part of 2.2 TestFlight delivery.

Released: native Mac 2.2 (385), iPhone/iPad 2.2 (386). Public app source: `9f7de25`. Mac release source: private `5853087`; iOS release source: private `3be2c60` (adds 2.2 to the CI version selector; app source is unchanged). iPhone UI regression passed all four edge taps in Light/Dark with Settings still at the top. The same iPad test passed portrait/landscape and Light/Dark.

[Mac build](https://github.com/protomota/jotley-app/actions/runs/39127910842) passed notarization, strict/deep signatures, Gatekeeper and installer layout/app-byte checks. DMG: 4,856,885 bytes, SHA-256 `ff65b1bf7d8f645e0ab1e02da5053f728ab3f485b6907bc51c9973f74e72278a`. The Release binary contains the notification service metadata and preference key, and excludes the Debug capture hook. An optimized small-string literal is not a reliable binary substring probe; notification contents were checked through the real OS delivery test instead.

[iOS upload](https://github.com/protomota/jotley-app/actions/runs/39127978535) and [TestFlight verification](https://github.com/protomota/jotley-app/actions/runs/39128298629) passed: 2.2 (386) VALID / IN_BETA_TESTING, available in Jotley Home. IPA: 6,309,537 bytes, SHA-256 `5c4060e154f18c2e4ce53750c14dea242d8827b59f36cb0929556bc7b65b8157`. App/widget versions and original bundle IDs match, production iCloud and distribution entitlements are preserved, Foundation Models/background registration checks passed, and Simulator switches are absent. TestFlight 386 was installed and opened on this Mac; the new Notifications setting was visible and enabled. The circle-edge hit checks were performed through iPhone/iPad Simulator UI tests; a physical mouse edge-click result on iPad-on-Mac has not been established by the native automation tool.

Website `2bd66e4` preserves newer upstream website assets (`a718589`) and changes only release metadata/tests/documentation. Production build and three download checks passed, including the Sparkle Ed25519 signature. Deployment `dpl_96en3QmbvWXkZqjNbvaEwF6zA2Bg` reports production READY. The live /download page shows 2.2 (385), and bytes downloaded through its actual button have the exact DMG hash above. The signed Sparkle feed was updated.

[Read-only App Store status after upload](https://github.com/protomota/jotley-app/actions/runs/39128300065) confirms 2.1 (384) remains WAITING_FOR_REVIEW, identical to the pre-upload status. Nothing was withdrawn, replaced or submitted for App Store review. Draft 2.2 release copy is saved privately for a later App Store submission. No tutorial work was authored in this task.
