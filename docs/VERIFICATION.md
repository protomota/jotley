# Source snapshot verification

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
