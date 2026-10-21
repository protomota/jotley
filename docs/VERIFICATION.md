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


## Tag replacement, Settings pointer target and neutral Done — 2026-10-18

The iPhone/iPad detail header now reads its tags from the observed note instead of rendering an on-appear snapshot. Its add-tag sheet binding follows relationship changes too. A completed summary replaces this note's tag set immediately; old library entities and other notes remain intact.

The shared tagging policy uses transcript word count: fewer than 10 words yields no automatic tags, 10–39 allows one, 40–149 up to two, 150–399 up to three, and 400+ up to five. Eligible completed notes always get at least one tag. Guided Apple model classification prefers existing buckets; empty/invalid results or model errors fall back to local library matches and NaturalLanguage noun/name extraction, with a general Notes bucket if lexical analysis yields no usable topic. Cancellation or failed summary persistence still preserves prior content. Both native Mac and iOS managers apply the policy before the atomic summary/tag save.

The iPad Settings button now matches the working + button's automatic button style and 56-point size, with a rectangular hit target covering the whole label. iPhone keeps its 44-point top placement. Settings/Ask AI Done controls use an explicit neutral glass capsule in the trailing toolbar instead of semantic confirmation styling; intrinsic width prevents truncation.

Verified so far: four focused shared tests passed, including the installed Apple model selecting AI/Design and replacing a persisted ten-tag set, policy boundaries/fallbacks, entity reuse and rollback. iPad UI tests passed two regenerations without reopening a ten-tag note, five-theme light/dark neutral-glass pixel checks, and four gear-edge taps in portrait/landscape and both appearances. Screenshot review caught a truncated Done label after the first pass; intrinsic width was added, and the repeated iPad manager integration and five-theme light/dark pixel/width checks passed with the full Done label visible. Native Mac signed Debug build and the real-view-model routing harness passed, including fallback tags and saved-summary notification behavior. Simulator fixtures are Debug/Simulator-only; their tag output is synthetic, distinct from the real installed-model acceptance test. A first test selection executed no iOS unit tests; the corrected method selector executed and passed the manager integration test. The known test-host Core Data entity lookup warning was emitted, without a test failure.

A local iPad-on-Mac development wrapper built successfully, but native automation could not attach to its window. Physical mouse edge behavior is not yet verified by that attempt. No release, upload or App Store review change is claimed in this section until recorded below.


Released and verified: public app source `e6e26d7`, private release source `66220ab`. iPhone/iPad 2.2 (387) uploaded in run [39129953298](https://github.com/protomota/jotley-app/actions/runs/39129953298); [39130285545](https://github.com/protomota/jotley-app/actions/runs/39130285545) confirms VALID / IN_BETA_TESTING, available in Jotley Home. IPA 6,326,193 bytes, SHA-256 `76215943d961aed88323d0987d8cd34bd474584eb0254c307b5d57f0b6b4aa5c`. App/widget versions, original identifiers, production iCloud, no-debug entitlement and Foundation Models/background registration passed; all Simulator fixture switches are absent. The complete iPhone UI set and final five-theme neutral/width check passed. Actual TestFlight 386 reproduced a colored-edge click selecting the note underneath; the same left-edge coordinate opened Settings after installing 387 on Mac. Other Mac mouse edges were not verified.

Mac 2.2 (388), [run 39129947937](https://github.com/protomota/jotley-app/actions/runs/39129947937), passed Apple notarization, strict/deep signature and Gatekeeper checks, signed Sparkle update verification, and installer geometry/app-byte validation. DMG 4,862,465 bytes, SHA-256 `eba1ff816983f17731047e2dd38b2466fa235698f62438857ec3cabfc74e9b3e`. Public website source `ae4b454` deployed as `dpl_4KfEC8LB78jXpohQzK8wYB7Xhmab` (production READY). The live /download page advertises 388; a download through its actual button has the exact signed hash. The R2 object passed full-byte verification. Production build and three local download/Sparkle tests passed. Initial local checks lacked the ignored DMG fixture and the expected Playwright browser; a temporary local fixture, existing Chrome and a fresh server resolved those test-environment failures. The fixture was removed before deployment. No tutorials were changed. Read-only status run [39130355362](https://github.com/protomota/jotley-app/actions/runs/39130355362) confirms 2.1 (384) remains WAITING_FOR_REVIEW.

## Compact Settings artwork and iPad selection — 2026-10-18

At the user's request the iPad gear returns to its original 44-point circle/16-point glyph, retaining the automatic button style and invisible 56-point rectangular target. iPhone remains 44 points. A four-edge test now taps padding beyond the smaller visible circle and passed in portrait/landscape and both appearances.

The list now receives the main container's split-view mode instead of re-reading the sidebar's potentially compact horizontal size class. Row selection and navigation use the same mode. Selected rows expose the selected accessibility trait, theme fill and outline; nil legacy IDs do not appear selected. The iPad UI regression passed switching between notes, checking actual colored pixels and clearing the old highlight, and retaining selection after Settings dismissal in Light/Dark and both orientations. The first new test fixture had a raw-string delimiter syntax error; it was corrected before the passing run. Screenshots use synthetic notes. No Mac capture-modal change is included in this iOS follow-up.


The compact gear/selection follow-up is released as iPhone/iPad 2.2 (389), public source `b0a9520` / private release source `f07616d`. [Upload 39131065716](https://github.com/protomota/jotley-app/actions/runs/39131065716) succeeded; [verification 39131492000](https://github.com/protomota/jotley-app/actions/runs/39131492000) confirms VALID / IN_BETA_TESTING in Jotley Home. IPA 6,324,983 bytes, SHA-256 `0f18c1848ab8bfa7d9a61f62ed64131e4304d2d7ec970847f5c2f6235bca2bb4`. App/widget 2.2/389, original bundle identifiers, production iCloud, no-debug signature, Foundation Models/background registrations and fixture exclusion checks passed. [Status 39131493588](https://github.com/protomota/jotley-app/actions/runs/39131493588) confirms 2.1 (384) remains WAITING_FOR_REVIEW.

## Native Mac live-transcription modal — 2026-10-18

Mac + and Continue Transcription open a dedicated 600×660 live sheet on the existing capture engine. The sheet contains a top-aligned, bottom-following timestamped transcript, independently animated Core Animation waveform, elapsed time and Pause/Continue/Stop controls. Close and Escape finalize capture, save the transcript and return to its static note without a discard prompt. Start errors dismiss the sheet and report through the existing error path. The previous bottom control capsule, arrow, caption bubble, unused follow-scroll state and Live Captions setting were removed. The optional desktop indicator remains available only while Jotley is in the background.

Meter changes no longer invalidate the entire note/sidebar model: the waveform polls level directly, and the text pane subscribes only to speech revisions. Transcript bubbles observe theme changes directly to avoid stale light/dark text colors. The model keeps its live sheet open during finalization and closes after the final persistence attempt; accidental sheet dismissal routes through stop/save too.

Verified before packaging: signed native Mac Debug build; full existing routing/UI harness including tag fallback and notifications; new actual-view/model modal checks for start, pause, continue, close/save, rejecting late fixture text, and continuing the same saved note without replacement. Light/dark transcript glyph pixel checks and controls/layout checks passed. A first close assertion expected three raw utterances; the existing coalescer correctly produced two display bubbles with the complete saved text, so the assertion now verifies preserved text. An inactive-window capture exposed a real stale text-color issue, which was fixed and rechecked. A forced-key bitmap capture produced transparent pixels; that invalid capture approach was removed and an opaque-background check added. Finally, an isolated native preview using synthetic speech, a real macOS sheet and no microphone access passed CUA Pause→Continue→Pause and header Close→saved transcript interactions. Its active-window screenshot shows enabled buttons. These tests do not claim a new real-microphone or system-audio endurance test. Credential-pattern scan: all 198 tracked public files, zero findings (heuristic only). No tutorial work or App Store submission changes are part of this update.


### Native Mac live transcription modal — 2026-10-18

Mac 2.2 (390) replaces the in-window bottom capsule, expansion arrow and caption bubble with a focused transcription sheet. The sheet contains timestamped text, the waveform, elapsed time and Pause/Continue/Stop controls. Close and Escape stop capture, save the transcript and return to the static note without confirmation. The optional floating indicator appears only while Jotley is in the background. Audio-meter updates no longer invalidate the full notes list/detail view. Transcript bubbles observe appearance changes directly.

The native routing harness passed the start/failure/double-start, pause/continue, close/save, continued-note append and late-update checks. Real-view light/dark text-contrast and footer-layout checks passed. In an isolated native preview using synthetic text and no microphone, the production sheet buttons were clicked: Pause changed to Continue, Continue resumed, and Close returned to the saved transcript. This does not establish physical microphone or locked-device endurance behavior; the capture engine was unchanged.

Release source: public `9ed7290`, private `45ae1aa`; [build 39132267824](https://github.com/protomota/jotley-app/actions/runs/39132267824) succeeded. The actual DMG passed Apple notarization/staple validation, strict/deep signature and Gatekeeper checks. Installer geometry and app-byte validation passed in packaging. Release-only resources exclude the synthetic-session symbols. DMG: 4,857,472 bytes, SHA-256 `ae5a17641b8f67bfc420e20f8db3c7326fb588809140a447f117f1b75bbd9c1a`.

Website source `266dee1` passed the production build and all three local download checks, including the signed Sparkle feed. R2 full-byte verification passed. Deployment `dpl_H92Yhkpa77HM1kxktdnDY3t8zJbH` is production READY, aliased to jotley.ai. The live /download page shows 390, and its actual download button delivered the exact DMG digest above. No tutorial content was changed.

The user confirmed that the next iPhone/iPad update is **2.1.1**, keeping **2.1 (384)** in review. Earlier 2.2 internal beta records above remain historical facts; they are not the next App Store version. The transient 2.0.1 upload workflow and an unstarted 2.1.1 workflow were canceled after the version clarification. No App Store submission was withdrawn or replaced.


### Corrected iPhone/iPad 2.1.1 delivery

Public version configuration `5717622` and private release source `bb2a9d2` use 2.1.1 for the app and widget. [Upload 39132904120](https://github.com/protomota/jotley-app/actions/runs/39132904120) succeeded; [availability check 39133245268](https://github.com/protomota/jotley-app/actions/runs/39133245268) confirms **2.1.1 (392), VALID / IN_BETA_TESTING, available in Jotley Home**. The native TestFlight Previous Builds screen independently shows 2.1.1 (392) with Install enabled and correctly labeled release notes. Older 2.2 betas remain listed separately.

The downloaded IPA is 6,324,994 bytes, SHA-256 `99c01450f72390ddf2180b1aa5cd3480fb5e829485d2c6129129e1eb84e51ef8`. Both exported app and widget report 2.1.1/392 and their original bundle IDs. Strict/deep code-signing verification, production iCloud, iPhone/iPad family support, disabled debug entitlement, Foundation Models linkage and summary background registration passed. This is a version correction of the already tested iPhone/iPad source; no UI or model logic changed. The next App Store release notes are saved as 2.1.1; no future App Store submission was created.


### Mac version alignment — 2.1.1 (393)

The website initially still showed 2.2 because the native Mac binary and its release manifest had not been renumbered along with iPhone/iPad. All six app/widget Debug and Release version settings now resolve to 2.1.1. The native Mac binary was rebuilt as 2.1.1 (393), rather than relabeling the old installer. Public source `a13f388`, private release source `3694105`; [release run 39133818226](https://github.com/protomota/jotley-app/actions/runs/39133818226) passed. Apple notarization/staple, deep/strict signing, Gatekeeper and installer-layout/app-byte checks passed. The actual bundled Sparkle comparator confirmed 393 is newer than 390; the user-facing version is separate from this internal build comparison.

DMG: 4,857,452 bytes, SHA-256 `c669f68c7ff0f8438782ce6866f83d7ca6b08f95b1b1633f1e895e8c7e2a895a`. The R2 object passed full-byte verification. Website source `04e016a` passed the production build and all three download tests, including the Ed25519 update signature. Deployment `dpl_E9xAaVNPtbvrNUVB88dUyLtpVFfC` reports production READY and is aliased to jotley.ai. The live browser page shows Jotley 2.1.1 for Mac / Version 2.1.1 (393); downloading through its real button produced the exact signed DMG digest above. The current feed, manifest, download page and app agree. No App Store submission was modified. iPhone/iPad 2.1.1 (392) remains the previously verified TestFlight build.


## Mac support reminders — 2026-10-18

The direct-download Mac edition now presents the themed support card after five successfully saved summaries, once the app is idle and foregrounded for 11 seconds. Closing without choosing an action delays the next reminder for five more saved summaries. Clicking any one of Rate, Tip, Share or Feedback closes the card and permanently stops automatic reminders on that Mac; individual clicks persist across launches. Resetting checkmarks does not restart retired reminders. The manual entry is Settings → General → About → More Information & Support. Checkmarks record clicks, not completed reviews, payments, shares or feedback.

The read-only PulseCanvas reference informed the left-aligned card, prominent rating action, secondary support rows and saved checkmarks; no PulseCanvas files changed. Store/iOS automatic ratings remain native and one-time.

Verification passed: native Mac Debug build; the full Mac routing/UI harness, including independent persistence/retirement tests for all four actions, five-summary repeat cadence, multi-window claims, legacy-click migration and reset behavior; production card rendering in five themes × Light/Dark; three focused iOS engagement/storefront regression tests. A synthetic native preview showed the automatic card after five summaries. Clicking each real production button dismissed it; intercepted destinations were correct. Sharing survived sheet dismissal and displayed the native picker, which was canceled. No review, payment, share or feedback was submitted. The final status-copy change was followed by another passing Mac build/full harness. Release packaging is recorded separately after completion.


### Mac 2.1.1 (394) delivery

Public implementation `00ee384`, private release source `2887744`; [release run 39141917480](https://github.com/protomota/jotley-app/actions/runs/39141917480) succeeded. The downloaded DMG passed Apple notarization/staple, strict/deep signature, Gatekeeper and manifest checks. Actual app metadata is 2.1.1/394 with the expected identifier and Sparkle feed; support policy strings are present and preview harness strings absent. Packaging verified installer geometry and matching app bytes. DMG: 4,870,775 bytes, SHA-256 `e943d133ed2e3649dfac462b88610955993e269998124834153b2614c0fc5d2d`. The immutable R2 object passed full-byte verification.

Website source `79f431d` passed production build and all three local download/Sparkle checks. The first build correctly blocked an installer not yet uploaded; after R2 publication the build passed. The temporary local DMG fixture was removed before deployment. Production deployment `dpl_6nEmFF5o9oAShcNNG5YA7M1LLtH8` reports READY. The actual live /download page shows 2.1.1 (394), and its button downloaded the exact signed hash above. iPhone/iPad 2.1.1 (392) and App Store 2.1 (384) were not changed. No tutorial work or PulseCanvas files were changed.


## Restore compact Mac transcription — 2026-10-18

Removed the blocking live-transcription sheet and its presentation state. The compact bottom capsule is attached to the detail column, so it remains available while browsing any note. It reuses the original RecordingIndicator with its three bars; meter polling is isolated to the indicator. Pause/Continue and Stop use the existing session and persistence lifecycle. Stopping while browsing another note saves the active transcript without switching the selected note or its tab. The optional background desktop widget remains unchanged. The removed caption preview and down-arrow control remain absent.

The active transcript follows incoming words at the bottom. User scrolling suspends following, including while dragging at the bottom; following resumes after the gesture ends at the bottom. Summary scrolling is unchanged.

Passed: Mac Debug build and full routing/UI harness, including immediate start, navigation during capture, transcript ownership, pause/continue, stop/save without displacing the browsed note, late-word rejection and append-on-continue. Compact controls fit long timers at 52-point height in Light/Dark. Follow-state checks cover scroll interruption, reading older text and resumption. A native synthetic preview exercised a long transcript: appending while reading retained the viewport, returning to bottom restored following, and the capsule remained visible when browsing another note. The preview needed Finder activation before native input was reliable; no microphone was used. The final three-bar implementation was rebuilt and regression-tested after that preview. iPhone/iPad and the support-reminder card are unchanged.


The final capsule uses a floating overlay rather than a safe-area inset. The scroll view retains the full detail height; bottom content padding keeps the last words above the capsule, and idle transcript actions stay hidden while another note is being transcribed. A dedicated native layout check measured the actual NSScrollView against the host window and passed with less than two points of bottom gap. This check uses the isolated app's single persistence model. Earlier experiments rendering full note metadata with two registered Core Data models failed (including an AppKit/SwiftUI observation crash in the preview); those test setups were replaced with the single-store check, which passed. No microphone or production note store was accessed. The first unpublished 395 CI artifact predates this scrollbar correction and is superseded by the final release run.


Final live scroll verification found and fixed a non-user scroll-phase edge case: an idle/layout phase must not disable initial following. Only a preceding user gesture can end in a manual-follow decision. The native preview now uses a synchronous AppKit entry point, keeping SwiftUI tasks responsive. CUA verified initial bottom following, scrolling to earlier text, appending without a viewport jump, returning to the bottom and appending with scrollbar still at 1. It also verified original three-bar artwork, browsing another correctly loaded note with the capsule still visible, Pause/Continue and Stop without navigating away. Screenshot: `/tmp/jotley-395-compact-transcription.png` (synthetic notes). Two earlier unpublished build-395 artifacts are superseded; only the final corrected artifact is distributed.


Final verification rerun: native Debug build, full routing harness, and the separate single-store viewport/navigation check all passed. The CLI harness now pumps the AppKit run loop; a dispatch-only test loop timed out and was replaced. The first rerun also correctly refused to delete leftover synthetic preview notes; their test-only store was moved intact to `/tmp/jotley-395-preview-sandbox-backup`, then the clean recovery checks passed. This test isolation work changes no production behavior. Final runtime release source remains public `4493a2e` / private `808c280`.


### Mac 2.1.1 (395) delivered

Final runtime source public `4493a2e` / private `808c280`; [release run 39147258657](https://github.com/protomota/jotley-app/actions/runs/39147258657) succeeded. Earlier unpublished 395 artifacts were never distributed. The final DMG passed Apple notarization/staple, strict/deep signing, Gatekeeper, expected version/bundle/feed, installer geometry and app-byte checks. Release resources contain the compact controls and exclude the old modal and preview diagnostics. DMG: 4,856,745 bytes, SHA-256 `afec68becfbb2d12c7f1108e6d2e88e83f37a32ab530b86013b3a9dddc999b91`. R2 full-byte verification passed.

Website source `60218f8` passed its production build and three local download/Sparkle checks. Deployment `dpl_J85p2SiTxb4PehNhE5P7tiPdRUFD` is production READY. The live /download page shows 2.1.1 (395), and clicking its actual download button yielded the exact signed hash above. The temporary local DMG fixture was removed before deployment.


### Universal iPhone/iPad 2.1.1 (396) delivered

At the user's request all current builds were published: native Mac 395 remains live, and a fresh iPhone/iPad build uses public source `1d0df49` / private release source `9b340fb`. [Upload 39147568457](https://github.com/protomota/jotley-app/actions/runs/39147568457) succeeded; [verification 39147840141](https://github.com/protomota/jotley-app/actions/runs/39147840141) confirms **2.1.1 (396), VALID / IN_BETA_TESTING, available in Jotley Home**. The existing mobile UI is unchanged by the Mac-only capsule correction. Current-source iPhone simulator compilation and all three engagement/storefront tests passed.

Downloaded IPA: 6,337,131 bytes, SHA-256 `ff08c3f2d32cd8b7ed1c8bbe8688fc5a3df84e6154767cd3a68b7df01fc99305`. Actual app and widget version/build, original bundle identifiers, iPhone/iPad device families, strict/deep signatures, disabled debugging, production iCloud, summary background registration and Foundation Models linkage checks passed. [Read-only status 39147656535](https://github.com/protomota/jotley-app/actions/runs/39147656535) confirms **2.1 (384) remains WAITING_FOR_REVIEW**. No App Store submission was withdrawn, replaced or newly submitted.


## Summary progress, recovered tagging and Mac glass actions — 2026-10-18

The summary progress spinner/title now form a centered group above Cancel Generation; multiline phase details also center. The production footer is a reusable MacSummaryProgressFooter in the existing source file.

Mac and iPhone/iPad no longer turn a successful local tag fallback into a modal error. A refused/unavailable tag response still uses LocalNoteTags.completedNames, replaces old tags, reuses library buckets and saves the completed summary before its notification. Cancellation still preserves the previous result; genuine summary or persistence failures retain their error paths. Optional title-generation warnings are unchanged.

The Mac support card's Close and Back controls use a shared SwiftUI button style with Apple's native interactive glass material, neutral theme-aware text and circle/capsule shapes, replacing the white rectangular primitive-style fallback. The same default style is applied to standard Mac actions, transcript editor and folder/tag sheets, Ask AI header/stop/dismiss/suggestion actions, Settings actions and Close, Obsidian actions and Cancel Generation. Existing custom themed navigation, note rows, compact transcription controls and OS-owned dialogs retain their own presentation. Disabled controls dim and remain disabled.

Verification passed: Mac Debug build and full routing/UI harness, including ten theme/appearance support-card renders; explicit fallback success without a sync alert, genuine summary failure with an alert, saved replacement tags and notification behavior. The iPhone simulator built and passed successfulSummaryReplacesTagsAndFallsBackWithoutOverwritingCancelledWork, updated to require no error after fallback. Native CUA previews showed the real centered Writing summary footer and glass Cancel button; Cancel stopped the simulated generation. The real support sheet showed a circular glass Close and capsule Back control; both dismissed correctly. Screenshots: `/tmp/jotley-397-summary-progress.png` and `/tmp/jotley-397-support-glass.png` (synthetic data). The final disabled-state polish was followed by a passing Mac build/full harness. Unrelated untracked JotleyVideoCaptureUITests.swift was preserved and excluded.


### Mac 397 / iPhone and iPad 398 delivery

Runtime implementation public `308b2ec`, private release source `236fd90`. Mac [release run 39150076026](https://github.com/protomota/jotley-app/actions/runs/39150076026) succeeded. The actual 2.1.1 (397) DMG passed notarization/staple, strict/deep signing, Gatekeeper, version/identifier/feed, installer layout/app-byte, digest and preview-exclusion checks. The recovered-tag warning text is absent from the binary. DMG 4,862,060 bytes, SHA-256 `3328751aa4348de97794a135fcbad1ed0b16b366fbbac0f70d1a954699392070`. R2 full-byte verification passed. Website source `da69e8b` passed its production build and three download/Sparkle tests. Deployment `dpl_2HBb21FGNH1zSuoWuZogeKz5tVc5` is production READY; the real /download button downloaded the exact signed hash.

Universal [upload 39150078068](https://github.com/protomota/jotley-app/actions/runs/39150078068) succeeded; [beta verification 39150258239](https://github.com/protomota/jotley-app/actions/runs/39150258239) confirms **2.1.1 (398), VALID / IN_BETA_TESTING, available in Jotley Home**. Exported app/widget version and original identifiers, strict/deep signatures, iPhone/iPad families, production iCloud, disabled debugging, summary background registration and Foundation Models linkage passed. The recovered-tag warning is absent from the exported app. IPA 6,337,744 bytes, SHA-256 `6a997c7ce5b2ae12e01d23128cc57347ef3bfcf9563c4bc4f58ee5022178d761`. The App Store submission was not modified.


## Mac detail fixes — 2026-10-18

The completed transcript reserves the footer gradient's full height plus 16 points of clearance in its scrollable content. Live capture retains its existing 88-point clearance and full-height scrollbar. Ask AI uses a plain multiline input with the selected theme for its focus outline, caret and selection accent. The obsolete Transcribe Saved Audio menu item and its view-model action are removed. Save to File lists Summary as PDF first, followed by Summary Only, Transcript Only and the two full-note formats; unavailable content types remain hidden.

Passed: signed native Mac Debug build and full existing routing/UI harness. An isolated native preview with synthetic timestamped text and historical audio metadata was scrolled to the bottom: the final paragraph remained completely above the fade and the scrollbar reached the bottom. Its real More menu omitted the saved-audio action and displayed the intended export order. Focusing and typing in Ask AI showed the selected magenta outline and caret without the purple system ring. No microphone, external AI request, user notes or actual export destination was used. Proof images: `/tmp/jotley-399-transcript-clearance.png`, `/tmp/jotley-399-export-order.png`, `/tmp/jotley-399-ask-theme.png`. Release delivery is recorded only after verification.


### Mac 2.1.1 (399) delivery

Implementation: public `56d9682`, private release source `d8c6d92`. [Release run 39151435774](https://github.com/protomota/jotley-app/actions/runs/39151435774) succeeded. The actual downloaded installer passed notarization/staple validation, deep/strict signing, Gatekeeper, version/identifier/feed, SHA-256 and Sparkle Ed25519 checks. CI inspected the final DMG's saved window geometry, artwork, app bytes and Applications shortcut. Actual release binary checks confirmed the saved-audio action and synthetic preview strings are absent. DMG: 4,857,318 bytes; SHA-256 `b77f64048659ac552213662c6c937f809997b81621eb978dbca2a6517b7e80e5`. R2 full-byte verification passed.

Website source `2cd2c69` passed the production build and all three download tests, including the update signature. The first browser test attempt could not launch because the Playwright headless shell was absent; rerunning with the installed Chrome executable passed all three checks. The temporary local installer fixture was removed before deployment. Deployment `dpl_6fArAvWaBmVwEsR6fdxXqmTpUHQg` is production READY and aliased to jotley.ai. The live /download page shows 2.1.1 (399); the real download button delivered the exact digest above. The live Sparkle feed advertises build 399 with the verified signature. The dedicated native viewport regression also passed: the scrollbar retains full detail height under the compact live controls. iPhone/iPad builds and the App Store submission were not modified.


## Ask AI keyboard, header and summary controls — 2026-10-18

Mac Ask AI submits on Return/Enter (Command–Return remains supported); Shift–Return/Option–Return insert a newline at the current selection. IME composition confirmation is not submitted. Empty or unavailable submissions use the same guard as the disabled Send button. Both apps center the explicitly theme-colored send arrow beside their growing input. The mobile input uses a themed UITextView because a vertical SwiftUI TextField displayed Send but still inserted newlines. Pasted multiline text remains multiline; modified hardware Return can insert a line. Add Tag now submits with Return. Folder fields use themed carets and focus outlines rather than the system focus ring.

The mobile Ask AI custom header follows the Mac order: title, Copy, Share, Reset, Done. The controls share the same neutral glass style, with mobile touch sizing. Done stays at the far right. Native Mac Summary now has Ask AI above the fixed-width template selector and Regenerate Summary; Continue Transcription stays on Transcript. Template selection saves without starting generation. The larger summary footer reserves matching bottom scroll clearance. Mac indeterminate progress uses the selected theme color, with reduced-motion support.

Passed: final signed native Debug build, complete Mac routing/UI harness and dedicated full-height viewport check. Native CUA checks used only synthetic notes: Shift–Return inserted a line without submitting; Return sent one question and the installed Apple model answered. Summary Ask AI opened the correct sheet; template selection and Regenerate Summary completed successfully without a fallback alert. Themed summary progress and cancellation were verified in the simulated progress preview. Folder creation showed the theme outline/caret and Return created/assigned the folder. Proof images: `/tmp/jotley-400-summary-footer.png`, `/tmp/jotley-400-ask-theme.png`, `/tmp/jotley-400-themed-progress.png`, `/tmp/jotley-400-folder-theme.png`.

The updated iPhone and iPad simulator UI test case each passed, checking contextual footer controls, centered Send geometry, far-right Done, Return submission and an actual on-device answer with Copy/Share enabled. The first SwiftUI Return implementation failed this check and was replaced before delivery. Xcode 27's simulator diagnostic collector hung after the passing cases; these collector processes were stopped. The additional combined diagnostic-disabled run did not finish and was stopped. Therefore no clean overall xcodebuild UI-test completion or finalized result bundle is claimed. Current simulator app compilation passed. Earlier unexpected synthetic test notes were preserved in `/tmp/jotley-400-*-sandbox-backup` rather than deleted. Release artifacts are verified separately after packaging.


### Mac 400 / iPhone and iPad 401 delivery

Implementation public `fb688eb`, private release source `3d59cab`. [Mac release 39154169253](https://github.com/protomota/jotley-app/actions/runs/39154169253) succeeded. The actual 2.1.1 (400) installer passed notarization/staple, deep/strict signing, Gatekeeper, identity/version/feed, checksum and Sparkle Ed25519 validation. Final installer layout/artwork/app bytes were verified in packaging. The actual binary contains the new summary controls and excludes the obsolete saved-audio action, recovered-tag warning and synthetic previews. DMG: 4,883,168 bytes; SHA-256 `00c76376dbe703465ffa9a8f84b8fcc66cde797434087c61ea9e62f2894d8fac`. R2 full-byte verification passed.

Website source `c83fd4d` passed the production build and all three download tests. Deployment `dpl_BYuJQxxMP2CkrSFxwoiR8i7JX91D` is production READY, aliased to jotley.ai. The real /download button delivered the exact verified installer digest, and the live Sparkle feed advertises 400 with the verified signature. The temporary local installer fixture was removed before deployment.

[iPhone/iPad upload 39154170883](https://github.com/protomota/jotley-app/actions/runs/39154170883) and [availability check 39154576891](https://github.com/protomota/jotley-app/actions/runs/39154576891) succeeded. Apple confirms **2.1.1 (401), VALID / IN_BETA_TESTING, available in Jotley Home**. The exported app/widget have matching 2.1.1/401 versions and original identifiers; strict/deep signatures, production iCloud, disabled debugging, iPhone/iPad families, background summary registration and Foundation Models compatibility passed. The new native question input is present; the recovered-tag warning and debug screenshot fixtures are absent. IPA: 6,376,897 bytes; SHA-256 `95e58de239ea29d18bb35dc3403acb7a9b4bb8107b1567050ecd2692374c54ad`. UI-check/diagnostic-export limitations are recorded above; no additional clean UI-test result bundle is claimed. No App Store submission was modified.


## Inline mobile Settings support / TestFlight 2.1.2 (402) — 2026-10-20

Rate on the App Store, Tip the Developer, Share Jotley and Send Feedback are separate rows directly in iPhone/iPad Settings. The extra support-card entry is removed from mobile Settings. Rows preserve saved action-click tracking, readable themed labels, native sharing and the existing storefront policy for website tips. Mac support behavior is unchanged. The release includes the iPhone gear-shadow stacking fix and prior 2.1.1 app updates.

Passed targeted iPhone and iPad UI tests in Light and Dark, including row order/alignment/touch targets, absence of the extra support modal, native Share → Copy → Settings and relaunch. Both devices also passed the restricted-storefront check: rate/share/feedback stay inline while website tips are omitted. The shared change passed the native Mac Debug build.

Public implementation `6eef11f`, private release source `21064d5`. [Universal upload 39438865773](https://github.com/protomota/jotley-app/actions/runs/39438865773) succeeded. Apple confirms **2.1.2 (402), VALID / IN_BETA_TESTING, available in Jotley Home**, with matching English TestFlight notes. Exported app/widget versions are 2.1.2/402; original identifiers, iPhone/iPad device families, strict/deep code signatures, production iCloud, disabled debugging, summary background registration and Foundation Models linkage checks passed. IPA: 6,314,588 bytes; SHA-256 `7af181a6a8a11e31e3f529f89e7881f9bf04763057794fcef07c10604b5ead0b`. The existing **2.1.1 (401), WAITING_FOR_REVIEW** App Store submission was read back unchanged.


## Mobile swipe-delete tint — 2026-10-20

The notes-list Delete swipe action now has an explicit red tint. Its destructive role and deletion behavior are unchanged, and the list can retain its readable action-text tint without making Delete gray in Dark appearance. The shared notes list covers iPhone and iPad.

The iOS Simulator Debug build passed. The existing Settings neutral-glass regression passed across all five accent themes in Light and Dark. No TestFlight, App Store or Mac release was created for this change.


## App Privacy correction — 2026-10-20

App Store Connect still declared Email Address (App Functionality), Product Interaction (Analytics) and Crash Data (Other Purposes). Reviewed the native app source and its package list: there is no app analytics or third-party crash-reporting SDK, support counters are device-local, and note sync uses the user's private CloudKit database. Voluntary user-sent feedback and direct-download Mac update delivery are separate from automatic app telemetry.

Saved “No, we do not collect data from this app” in App Store Connect. The page confirmed the answers were published, and its product-page preview now reads **Data Not Collected** with no collected data types. This app-level privacy correction did not require withdrawing or resubmitting 2.1.1 (401), which remains Waiting for Review; 2.1.2 (402) remains the latest available TestFlight build. The public US storefront still showed its older cached labels at the subsequent browser check; the published Connect state is verified, but public-storefront propagation is not claimed.

The live privacy policy now explicitly distinguishes the native apps' lack of contact-information collection, usage analytics, diagnostics and cross-app tracking from optional iCloud, user-sent feedback, website analytics and Mac update requests. Website source `64b9b44f` passed the production build and deployed READY to production as `dpl_9x3fAcb7xrtAFgWic4kXhVr5FLq8`; the live browser showed the new October 20 text. No app build or release was created. Screenshots are preserved in the task's `jotley-privacy-20261020` evidence directory.


## Guided welcome setup across Mac, iPhone and iPad — 2026-10-20

First launch offers a theme-aware welcome flow: private notes, real Apple Intelligence readiness, the existing saved transcription language with explicit Apple speech setup, and optional microphone access. Native Mac adds a separate optional system-audio step; Designed for iPad on Mac keeps the mobile microphone flow. Completion is local, notes are preserved, and Settings → Welcome to Jotley reopens setup. Settings exposes the same preferred transcription-language value, used by subsequent transcription sessions. No interface translation is claimed.

Native Mac uses a fixed two-column layout without a ScrollView or scrollbar. Mobile can scroll for small windows and accessibility text, with indicators hidden. Wide iPad layouts keep chrome/content/footer within an 820-point reading area. Clean first-party AppIcon artwork replaces the old gray-backed onboarding image; high-quality interpolation, antialiasing, correct aspect ratio and a subtle theme glow apply to both logo sizes. Primary actions have readable contrast, including Yellow; page changes respect Reduce Motion.

Only explicit buttons request consent or install speech assets. Mac system-audio setup uses a private unmuted Core Audio tap-backed device with no microphone subdevice; its callback discards input, creates no notes/files, and stops on back/skip/finish/disappearance or after 60 seconds. Requesting consent is not presented as proof of approval; microphone-only mode and the system privacy-settings link remain available. App privacy usage descriptions now describe live transcription. Native permission approval and audio capture with a stable signed identity were not exercised in this UI review and remain part of signed-device release validation.

Passed actual Mac and iOS Simulator Debug builds, plus the full existing Mac routing/UI harness. The harness's initial unexpected test-sandbox notes were preserved in `/tmp/jotley-onboarding-routing-sandbox-backup-20261020` before rerunning; no installed-app notes were deleted. Final targeted iPhone and iPad UI checks passed in Light/Dark: all four pages, no automatic permission alerts, complete on-screen primary controls, skip/finish, completion surviving relaunch, language choice surviving relaunch into Settings, replay and preservation of the existing note. Separate accessibility-size Yellow-theme checks passed. Earlier iPad test navigation overscrolled the virtualized sheet; the final test scrolls the Settings Form directly. Native Mac checks verified all five pages without a scrollbar, real ready/needs-setup language states, language changes in both directions between Settings and welcome, and the microphone-only preference. Local preview preferences were restored.

Evidence: `/tmp/jotley-onboarding-iphone-checked.xcresult`, `/tmp/jotley-onboarding-ipad-checked.xcresult`, `/tmp/jotley-onboarding-mac-checks-final.log` and the task's `jotley-onboarding-20261020` screenshot directory. No version change, TestFlight upload, Mac installer publication or App Store review change was made.

### Welcome footer alignment — 2026-10-20

Narrowed the native Mac welcome footer from 380 to 344 points. Progress and secondary actions now share the primary action’s centerline, with an explicit 54-point space for Back and a 12-point gap. Verified all five Mac pages in the actual rebuilt app; the system-audio primary action, progress and Use Microphone Only align, with no scrollbar. No permissions were requested and no release was created. Proof: `mac-system-audio-aligned.png` in the onboarding preview directory. Mac Debug build passed; iOS Simulator compatibility build also checked before commit.

### Welcome action aligned with copy — 2026-10-20

Wide onboarding layouts now use the same illustration/spacing/content columns for the footer and page copy. The primary button starts at the copy’s left edge; progress and alternate actions center on the primary button, with Back positioned outside the content column. Compact phone layouts retain their existing arrangement. Actual Mac preview confirmed the system-audio page, no scrollbar, and no permission request. Mac and iOS Simulator Debug builds passed. Proof: `mac-system-audio-copy-aligned.png` in the onboarding preview directory. No release created.

### Welcome artwork and logo sampling — 2026-10-20

Removed the duplicate logo from the welcome illustration. The first page now shows the same three-bar live-transcription preview flowing into a summary/action card, while the Jotley identity appears once in the header. Prepared the original first-party logo at its actual 34-point display size with separate 34/68/102-pixel 1x/2x/3x renditions using Lanczos filtering and alpha preservation. This avoids rendering the 1024-pixel source directly at a tiny UI size; no brand shape or app icon was changed. Mac and iOS Simulator Debug builds passed. Native Mac preview confirms the single smoother logo and preserved copy/button alignment, with no scrollbar. Proof: `mac-welcome-refreshed.png` in the onboarding preview directory. No release created.

The shared welcome illustration uses a shorter summary card on compact phones. Targeted iPhone checks passed with the first artwork revision in Light/Dark and accessibility-size Yellow (2 tests, 0 failures); the final compact-layout Light/Dark language/persistence/replay check also passed (1 test, 0 failures; `/tmp/jotley-welcome-artwork-iphone-final.xcresult`).

### Onboarding inside the main app window — 2026-10-20

Replaced the onboarding sheet/full-screen-cover presentation with content hosted in the main app view on Mac, iPhone and iPad. The notes/navigation view stays mounted but hidden, disabled and excluded from accessibility while onboarding is active; finishing fades back to the same note/navigation state. Settings replay dismisses Settings before switching the main view, and returns to Settings afterward. Mobile widget and summary-notification navigation waits through both initial setup and replay; support prompts wait too. Native window controls remain available and the Mac status footer stays hidden during setup. The system microphone/audio permission prompts remain controlled by the OS and require an explicit request.

Actual native Mac inspection verified all five steps are in the original `main-AppWindow-1` standard window, with no onboarding sheet, no scrollbar, and no interactive notes controls. Replay/Skip returns to Settings. Mac Debug build and existing Mac routing/UI harness passed; iPhone Light/Dark language/persistence/replay and accessibility-size Yellow checks passed (2 tests, 0 failures). No permissions granted and no release created. Proof: `mac-inline-01.png` through `mac-inline-05.png` in the onboarding preview directory.

The iPad landscape Light/Dark language/persistence/replay check also passed (1 test, 0 failures). Final evidence: `/tmp/jotley-inline-onboarding-iphone-verified.xcresult`, `/tmp/jotley-inline-onboarding-ipad.xcresult`, `/tmp/jotley-onboarding-inline-mac-final-build.log` and `/tmp/jotley-inline-onboarding-mac-routing.log`; fresh inline iPhone/iPad welcome screenshots are saved beside the Mac previews.

### Delivered Jotley 2.1.2 (403) — 2026-10-20

Published the requested iPhone/iPad TestFlight update and native Mac website download from private release source `3fa9c270` (runtime code matches public main `40f4078`). TestFlight upload run [39486852127](https://github.com/protomota/jotley-app/actions/runs/39486852127) succeeded; verification run [39487695058](https://github.com/protomota/jotley-app/actions/runs/39487695058) confirms `VALID / IN_BETA_TESTING` and available in the existing Jotley Home group. App Store Connect also shows 2.1.2 (403) as Testing in that group. IPA metadata confirms version 2.1.2, build 403 and device families 1/2; 6,537,573 bytes, SHA-256 `3a506d2278ce95b00428a2f52e6ba3dab00b036d14811dc678934fd973c1648e`.

Mac release run [39486855887](https://github.com/protomota/jotley-app/actions/runs/39486855887) succeeded with Apple notarization Accepted and a stapled ticket. Local Gatekeeper assessment, code-signature validation, installer SHA-256 and Sparkle Ed25519 checks passed. `Jotley-2.1.2-403.dmg`: 4,936,406 bytes, SHA-256 `17818fa74ab4e87bc439d590205e4abc47346c6acd73a01aa9c00e51b0c61d41`. Uploaded immutably to `https://media.jotley.ai/downloads/Jotley-2.1.2-403.dmg`, retaining the old installer. Website main `1b1959a2` publishes matching appcast/manifest and download-page version. Production build and all three Mac download browser checks passed (including installer bytes and update signature); the local test-only installer symlink was removed before deployment. Vercel production deployment `dpl_ES6bsRHJZUuopUwsuVyikmNchnWi` is READY and aliased to jotley.ai; live browser verification shows 2.1.2 (403) at `https://jotley.ai/download`.

The real Mac-window onboarding walkthrough is online at `https://media.jotley.ai/clips/jotley-onboarding-main-window-20261020.mp4` (28.54 seconds, H.264, 900×652). Recorded 230 live window frames; hosted video metadata confirms it plays. No audio captured and no microphone/system-audio permission granted. Screenshots and video masters are in the task's onboarding preview directory; a master copy is also in the site's Music-drive media library. No App Store submission was withdrawn or changed by these TestFlight/direct-download operations.

### App Store replacement submitted — 2026-10-20

Following explicit authorization to replace the pending submission, withdrew iOS 2.1.1 (401), changed the editable version to 2.1.2, selected the existing validated build 403, and submitted it for App Review. App Store Connect confirms **2.1.2 (403), Waiting for Review**, submitted October 20, 2026 at 4:18 PM; submission ID `8f8f68e3-2182-4578-ad8c-b8ebb798b7a5`. Receipt: [App Review](https://appstoreconnect.apple.com/apps/6746770199/distribution/reviewsubmissions/details/8f8f68e3-2182-4578-ad8c-b8ebb798b7a5).

What's New leads with Jotley 2's free, private live transcription, summaries, Ask AI, organization and supported widgets, followed by a short description of this update's welcome setup, transcription-language preference and consistent controls. Reviewer instructions now describe build 403 and its inline onboarding. Preserved screenshots, other listing fields, automatic release after approval, immediate availability to all users and existing ratings. The Mac website download remains the already published 2.1.2 (403); no additional binary was built. Screenshot: `appstore-212-403-submitted.png` in the task's onboarding preview directory.

### Apple Intelligence language compatibility — 2026-10-21

Corrected the shared Settings/onboarding language catalog to intersect Apple's 16 published Apple Intelligence languages with runtime `SystemLanguageModel.supportsLocale` and the on-device Speech/Dictation inventories. Regional speech variants are grouped into one choice per language; Simplified and Traditional Chinese remain distinct. Supported older regional preferences normalize to the corresponding choice, while unsupported saved preferences remain unselected and cannot reach asset reservation, installation or capture. Existing notes are preserved. The same shared service is used on Mac, iPhone and iPad. Apple's reference: https://support.apple.com/en-us/121115 and https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models.

Actual Mac and iOS Simulator Debug builds passed. The Mac language regression harness passed deterministic intersection/filtering, regional normalization, separate Chinese scripts and unsupported legacy configuration rejection; live model/speech inventory returned exactly 16 choices. Simulator UI execution was initially blocked by a pre-existing Xcode/CoreSimulator service version mismatch; test execution and release delivery are recorded below when available.

### Delivered language correction, 2.1.2 (404) — 2026-10-21

Published runtime source private `56b1ad78` / public `1eac339`. iPhone/iPad upload [39607538093](https://github.com/protomota/jotley-app/actions/runs/39607538093) succeeded; verification [39608588408](https://github.com/protomota/jotley-app/actions/runs/39608588408) confirms `VALID / IN_BETA_TESTING`, available in Jotley Home. Apple build ID `cdd3a1b5-19b1-44db-974b-fa6c987391d2`; IPA metadata is 2.1.2 (404), device families 1/2, 6,559,520 bytes, SHA-256 `5e42178de083833afce00b008726f02f4bcc0801b891dc26eb9e42e4a20fea9d`.

Mac release [39607542450](https://github.com/protomota/jotley-app/actions/runs/39607542450) succeeded. Apple notarization Accepted; stapled ticket, code-signature and Gatekeeper checks passed. Installer `Jotley-2.1.2-404.dmg` is 4,950,317 bytes, SHA-256 `6eb7fa5b33197ab4a78187808726f51829194b3267c9e9d937d7cbdf01064218`. Published immutably at https://media.jotley.ai/downloads/Jotley-2.1.2-404.dmg, preserving older installers. Site main `3cc838b3` updates the matching appcast/manifest and adds the 16-language list and device-specific speech/Intelligence intersection to requirements and FAQ. Production build and all three download checks passed, including bytes/SHA-256 and Sparkle Ed25519 signature. Test-only local DMG symlink removed before deployment. Vercel `dpl_8Hnf1W14ae9Fj9kzL8Kz7QNfpFF3` is READY, production, aliased to jotley.ai; live browser confirms download 2.1.2 (404) and the language list.

After the owner withdrew build 403, selected 404 and resubmitted with their renewed authorization. Apple confirms **2.1.2 (404), Waiting for Review**, October 21 at 9:34 AM; submission `e32c48c5-04ce-422c-b60c-88afa5e84b48`. Preserved screenshots, listing fields, automatic release, immediate rollout and ratings. Customer-facing What's New is restored exactly to the prior Jotley 2 marketing copy per the owner's request; the language correction appears only in private reviewer instructions.

Final checks: full Mac routing/regression harness passed, including the actual 16-language runtime catalog; native Mac menu visually verified. iPhone and iPad Light/Dark onboarding UI tests passed, including unsupported/duplicate language exclusion, selecting French/German, language persistence into Settings and replay without losing the fixture note. The targeted iOS language policy regression passed (1 test, 0 failures), covering intersection, Chinese scripts, regional normalization and rejection of unsupported legacy configuration before assets/capture. Xcode's first-launch installation resolved the initial CoreSimulator mismatch. An additional existing capture test crashed in the hosted app's SwiftUI/CoreData fetch during XCTest; a retry was stopped and is not counted as passed. No test-only runtime changes were shipped. No physical microphone or system-audio permission was granted during these checks.

Evidence: `/tmp/jotley-language-mac-build.log`, `/tmp/jotley-language-mac-routing.log`, `/tmp/jotley-language-iphone.xcresult`, `/tmp/jotley-language-ipad.xcresult`, `/tmp/jotley-language-ios-policy.xcresult`, `/tmp/jotley-language-site-tests.log`, and the task's `jotley-language-20261021` proof directory (native Mac language menu, iPhone/iPad language pages, live website and App Store submission receipt).


## iPhone Duo 2.2 preparation — October 21, 2026

The simulator build uses Xcode 27.1 / iOS SDK 27.1 with a marketing-version override of 2.2. No production binary or App Store submission was changed during these checks.

Changes under verification:

- Keep one NavigationSplitView through folds and rotations, preserving the selected note, tab and editor/sheet state.
- Use a device-wide Duo action row with equal gaps. Measure the primary action's rendered height for the circular + button; mirror the gear's corner padding.
- Center Ask AI / Continue Transcription on the device.
- Host the footer beneath the native Notes drawer and its dimming layer. When the columns sit beside each other, share the full-width bottom row.
- Use the SwiftUI color-scheme observation for dynamic theme colors and a more compact live-capture control area on short displays.

Passing automated checks:

- Duo corner controls in portrait and landscape: exactly one +, no overlap, matching primary-action height and vertical center, Share/More available, simulated pause/resume/stop/continue.
- Continued-transcript flow saves and returns to the note.
- Live transcript starts at the top, keeps a stable first-card position and follows incoming content at the bottom.
- Standard iPhone appearance switching and persistence.
- iPad split selection in both appearances and orientations.
- Native Mac debug build and the real Mac routing harness (the shared appearance change).

Direct simulator checks:

- Opening Notes covers the left part of the footer and dims the exposed controls with the detail. Tapping the dimmed + dismisses the drawer without starting capture.
- Opening and closing the drawer restores the full, aligned action row. Adjacent landscape columns retain the full device-wide row.
- The selected note/tab and an open summary editor survive unfolding. Transcript editing saves and returns to the note. Settings Done remains visible during scrolling and closes the sheet.
- The closed-display More menu, transcript/summary editors and their Cancel/Save controls open correctly.

Remaining release gate:

The broad Duo UI suite is not green. The first 30-case pass reported 15 passed, 10 failed and 5 device-specific skips. Targeted fixes/rechecks subsequently passed the corner/capture/continuation cases above. Remaining automated failures include support-settings toolbar accessibility after scrolling, exact streaming-heading visibility, background/back navigation, and legacy summary/editor assertions. Direct operation succeeds on several of these paths, but that disagreement has not been fully resolved. Do not treat this receipt as full Duo regression approval or publish 2.2 from it.

Capture lifecycle checks use simulator-only synthetic speech. Actual microphone recognition and Apple Intelligence generation still need supported physical-device verification; the synthetic hooks are excluded from shipping builds.

### Duo portrait selection and simulator clock — October 21, 2026

Selecting a note from an overlaid Notes column now dismisses that column on expanded iPhone layouts. Rotating into a wide layout restores automatic columns. Direct simulator operation confirmed the initial portrait selection closes the drawer.

The DEBUG-only simulated microphone clock previously added one synthetic second on each 0.25-second progress tick. It now derives synthetic frames from monotonic elapsed time for each active segment. The production microphone path continues to use captured audio frames. The focused UI test `testSimulatedCaptureTimerMatchesElapsedTimeAndPauses` passed on iPhone Duo: elapsed duration matches wall time and remains unchanged while paused. The existing `testDuoCornerCaptureStaysClearOfNoteActions` also passed on the same build. Result: `/tmp/jotley-duo-realtime-timer-final.xcresult`. These two checks do not resolve the outstanding broad regression findings above.

Screenshot fixtures can seed fictional Ask AI conversations and fixed live transcript examples in disposable in-memory stores. These hooks remain DEBUG/simulator-only and are excluded from Release. Marketing captures identify the conversation as scripted sample content.

### Floating controls and complete library scrolling — October 21, 2026

The Duo footer previously used full-height overlay geometry that could intercept library swipes. Footer geometry is now limited to its measured height. List content has a bottom scroll margin, and note content has clearance equal to its measured action footer. This lets content travel behind the floating controls while allowing the last row or transcript card to scroll fully above them. The solid footer background is removed on iPhone/iPad, including Duo. Action buttons use a shared theme-colored glow and soft drop shadow. Duo safe-area handling surrounds the overlay so its bottom padding stays aligned with the existing corner placement.

The new 20-note reachability check reproduced the original failure before the fix. With the fix, the oldest note is reachable and opens on Duo, iPhone 17 Pro Max, and iPad Pro 13-inch simulators. The long transcript check confirms the final card clears Continue Transcription and the generation controls in both Light and Dark. Initial transcript assertions were corrected to match the normalized timestamped card containing the final sentence; the fixture's last paragraph is combined into that card. Duo drawer clearance uses actual rendered window geometry, because requesting an orientation can leave the other display in its prior orientation. These are focused checks, not resolution of the outstanding broad regression findings above.

Results: `/tmp/jotley-duo-floating-final.xcresult`, `/tmp/jotley-iphone-scroll-final.xcresult` (library), `/tmp/jotley-iphone-footer-diagnostic.xcresult` (transcript), `/tmp/jotley-ipad-scroll-final.xcresult` (library), and `/tmp/jotley-ipad-footer-verified.xcresult` (transcript). The native closed-Duo capture was inspected for correct corner padding. No new build was uploaded or released for these changes.

### Opaque floating button surfaces — October 21, 2026

Template, Ask AI, Continue Transcription and Cancel Generation now use a capsule with an opaque theme-background base beneath the accent tint. Scrolling text cannot show through the button, including its disabled state; the space around each control remains transparent. Light mode uses the app's near-white base and dark mode uses its solid dark base. Existing shadows and corner spacing remain. The iOS Simulator build and the focused Duo corner/capture and final-transcript checks passed, including Light/Dark (`/tmp/jotley-opaque-pills.xcresult`). No build was uploaded or released.

### Readable summary actions and fold-safe footer — October 21, 2026

Generate Summary and Regenerate Summary reserve their full, unscaled 15-point semibold labels plus 20 points of horizontal padding per side. A width-aware layout gives the template a compact slot when needed, or moves it above the primary row on narrower windows. The + remains 58 points tall and aligned with the primary action; secondary controls retain their opaque backing.

The Duo footer now measures the complete viewport including the system toolbar safe area, aligns using the current detail bounds, and retains natural height. This fixes the left-clipped template after unfolding and avoids stale footer height when folding back. Native simulator checks covered closed portrait → open landscape → closed portrait with the same note open. Both summary and no-summary/transcript states were captured.

Seven focused UI checks passed: Duo action/capture continuation, summary label padding and control bounds through rotations without relaunch, and final transcript clearance in Light/Dark; the latter two also passed on standard iPhone 17 Pro Max and iPad Pro 13-inch. Results: `/tmp/jotley-footer-safe-area-duo.xcresult`, `/tmp/jotley-footer-safe-area-iphone.xcresult`, `/tmp/jotley-footer-safe-area-ipad.xcresult`. This does not clear the earlier broad regression release gate. No build was uploaded or released.
