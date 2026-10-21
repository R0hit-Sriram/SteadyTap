# SteadyTap — Build Plan (CAC 2026, TX-03) — iOS keyboard version

Deadline **Oct 26, 2026**. Build: Oct 14–23. Video + buffer: Oct 24–26.
This plan **replaces** the earlier PWA plan. The product is now an iPhone app with a **custom keyboard extension** that types directly into other apps.

## Decisions (and why)

| Decision | Why |
|---|---|
| Containing app (SwiftUI) + keyboard extension (`UIInputViewController`) | Required for a system-wide custom keyboard on iOS. |
| **No "Allow Full Access"** (`RequestsOpenAccess = false`) | Apple: without it, a keyboard has no network and **no shared container with its app**. This is the strongest privacy story. |
| **Calibration, settings, comparison all run *inside the keyboard*** | Without Full Access the app can't read the keyboard's data. So the learned profile lives in the extension's own container. The app explains the steps and offers a practice field. |
| Engine = local Swift package `Packages/TouchEngine` (Foundation only) | The algorithm is separate from UI and can be tested with `swift test`. It already passes in a Linux container on the Windows laptop. |
| XcodeGen (`project.yml`) instead of a committed `.xcodeproj` | A hand-written `.pbxproj` can't be verified from Windows and merges badly. Running `xcodegen generate` on the Mac gives a deterministic project. |
| iPhone only, portrait-first, iOS 16+ | Narrow scope for the deadline. |
| Fixed keyboard when not calibrated | Ordinary typing works out of the box. Adaptation turns on only after calibration. |

## Algorithm (unchanged in substance — now Swift)

1. **Baseline:** the touch-up point is assigned to the key under it.
2. **Calibration:** about 63 requested taps in 3 sets, with breaks:
   - every letter twice
   - 4 double letters
   - 3 spaces

   Consecutive targets are at least 2 key widths apart. This is so an accidental extra contact can't be confused with the next target.
3. **Intent point:** four candidates (lift-off, first contact, path mean, dwell). The one with the best **leave-one-out** accuracy on that person's taps is chosen.
4. **Offsets with shrinkage:** global → 12 screen regions → key, with κ = 4. Spread is a full 2×2 covariance per region with a minimum σ floor.
5. **Score:** Gaussian log-likelihood + 0.3 × a clamped letter-pair hint (from the Gettysburg Address, computed on device). Softmax gives probabilities.
6. **Decide:** if the top probability is below the threshold, type the top letter and show a two-choice bar. Undo reverts the last action.
7. **Repeats:** bounce filtering turns on only if calibration saw at least 2 accidental extra taps. Its window stays below the person's own double-letter speed. A filtered tap appears as a "add it" button.
8. **Function keys** stay plain buttons, checked after correcting for the person's overall offset.

## Status

- [x] Engine + 39 unit tests (pass on Swift 5.10, Linux)
- [x] Per-person "what each part adds" table (leave-one-out, shown after calibration)
- [x] Online learning while typing (picks / corrections / confident taps, fading evidence, fix-rate change detection), 46 tests incl. drift simulations
- [x] Whole-word fixing on space (noisy-channel decoder over 20k words using the person's own touch model), "What it learned" map, 56 tests
- [x] Comparison: 3 phrases per mode, words per minute, median + range, "may be chance" note when ranges overlap, combined report across saved runs
- [x] Hold-to-delete backspace (toggle)
- [x] Keyboard extension:
  - letters/symbols pages, shift/caps lock, space, backspace, return, globe (`handleInputModeList`)
  - choice bar, undo
  - in-keyboard calibration, settings, comparison
  - "show my touches" demo overlay
  - delete-all
- [x] Containing app: welcome, enable steps, practice field, comparison info, how it works, privacy
- [x] XcodeGen project spec
- [ ] **First Xcode build on the Mac** — the UIKit/SwiftUI code has only been syntax-checked, not compiled
- [ ] Device checklist (`docs/MAC_AND_IPHONE.md`)
- [ ] Tune `baseRowHeight`, the ask threshold and the minimum σ on a real iPhone
- [ ] Optional sessions with consenting users who have motor difficulties (protocol in docs)
- [ ] Record demo (`docs/DEMO.md`)

## Schedule

| Days | Windows laptop | Mac + iPhone teammate | Others |
|---|---|---|---|
| Oct 14–16 | engine + tests ✔, iOS sources ✔ | install XcodeGen, first build, fix compile errors, device install | read docs, prepare demo script |
| Oct 17–19 | engine fixes from device feedback | full device checklist; tune sizes | consent + test protocol |
| Oct 20–22 | polish copy, README | regression pass after each pull | volunteer sessions (only with consent) |
| Oct 23 | freeze | final build on device | — |
| Oct 24–26 | — | record video in Notes/Messages | edit + submit |

## Known risks

- **System edge gestures delay touches.** Touches at the far left and right edges of a keyboard can arrive late. Check this on device.
- **Choice-bar swap** relies on `documentContextBeforeInput` reflecting our insert. Some host apps report context lazily, in which case the swap is skipped safely (tested in the engine).
- **No VoiceOver support for individual keys** in this version. This is a documented limitation.
- **Free Apple ID signing expires after 7 days.** Re-run from Xcode before the demo.
