# SteadyTap (working name)

An iPhone keyboard for people who can use a touchscreen but often hit the key next to the one they meant. It learns **one person's touch pattern** from a short tapping exercise. It then uses that pattern to read their later taps, directly inside Notes, Messages and other apps.

It is an accessibility tool, not a medical device. It does not diagnose, treat or claim to help any specific condition.

## Repository layout

```
project.yml                 XcodeGen spec → generates SteadyTap.xcodeproj on a Mac
App/                        containing app (SwiftUI): setup steps, practice field, privacy, how it works
Keyboard/                   keyboard extension (UIInputViewController)
  KeyboardViewController    entry point, height, globe key, host text sync
  KeyboardController        screen state, calibration/comparison flow, settings, storage
  TouchSurfaceView          single view that captures every touch path and draws keys + demo overlay
  KeyboardViews             SwiftUI toolbar, choice bar, settings and result panels
Packages/TouchEngine/       THE ALGORITHM — pure Swift, no UIKit, unit-tested
  Layout, Gesture           key geometry; touch-down/up/path/dwell points
  ModelFitter, TouchModel   learn offsets + spread from calibration (with shrinkage, leave-one-out)
  Decoder                   score keys, decide, flag uncertain taps
  LetterContext             small letter-pair hint (secondary)
  CalibrationSession        target sequence, breaks, accidental-extra-tap detection
  TypingSession             text edits, two-choice bar, one-step undo, repeated-letter handling
  Comparison, ProfileStore  3-mode typing test metrics; local JSON storage + delete-all
docs/MAC_AND_IPHONE.md      Xcode setup and device test checklist (for the Mac teammate)
docs/DEMO.md                1–3 minute video outline
```

## Build and run

**Engine tests (any machine with Swift, or with Docker):**
```bash
cd Packages/TouchEngine && swift test
# Windows/Linux without Swift:
docker run --rm -v "$PWD/Packages/TouchEngine:/pkg" -w /pkg swift:5.10 swift test --scratch-path /tmp/b
```

**iOS app (Mac with Xcode 15+):**
```bash
brew install xcodegen
# edit BUNDLE_ID_BASE and DEVELOPMENT_TEAM at the top of project.yml
xcodegen generate
open SteadyTap.xcodeproj      # select the SteadyTap scheme + your iPhone, press Run
```
Full steps and the device checklist are in [docs/MAC_AND_IPHONE.md](docs/MAC_AND_IPHONE.md). To rename the product, change `APP_DISPLAY_NAME` in `project.yml`.

## How the algorithm works

1. **Fixed baseline.** A normal keyboard types the key under your touch-up point.
2. **Calibration.** You tap 63 highlighted keys in 3 sets, with breaks between them. For each tap we keep the requested key and the touch path (down, moves, up, with times).
3. **Which point shows intent?** We compute four candidate points per tap: lift-off, first contact, path average, and where the finger rested longest. For each, we fit a model and measure **leave-one-out** accuracy: every tap is predicted by a model that never saw it. The best one is used for this person.
4. **Learned offset and spread, protected against sparse data.** For each tap we measure the offset from the requested key's center, in points.
   - Offsets are averaged for each key, shrunk toward the average of the key's screen region. Regions are shrunk toward the overall average, with κ = 4. A key with 1–2 taps therefore mostly uses its region's pattern.
   - Spread is a 2×2 covariance per region, also shrunk, with a minimum size so it never becomes overconfident.
5. **Scoring a new tap.** `score(key) = log Gaussian(point − keyCenter − learnedOffset; learnedSpread) + 0.3 × letterPairHint`. Softmax turns the scores into probabilities. The letter-pair hint comes from a short public-domain text, is clamped, and can only tip near-ties. Turn it off in settings to see the touch model alone.
6. **Uncertainty.** If the top key's probability is below the threshold (adjustable: often, sometimes, rarely), we type it and show **both** letters. One tap switches, and Undo reverses the last action.
7. **Repeated letters.** Double letters are never discarded by default. Bounce filtering turns on only if calibration saw repeated accidental extra contacts, and only with a time window shorter than this person's own intentional double-letter speed. A held-back tap is shown with an "add it" button.
8. **Function keys** (shift, backspace, return, 123, globe) behave as normal buttons. Backspace repeats while held (0.6 s delay; this can be turned off).
9. **What each part adds (measured, per person).** After calibration, the keyboard shows a table:
   - the standard keyboard
   - one shift for the whole keyboard
   - plus a shift per screen area
   - plus a shift per key with borrowing (the model actually used)
   - for contrast: per key with no borrowing, and the same model on the lift-off point

   Every number is leave-one-out accuracy on that person's own calibration taps. Layers don't always help: for a very regular person "no borrowing" can score slightly higher. The table shows that honestly rather than hiding it.
10. **Optional learning from confirmed choices** (off by default). When the person *taps* one of the two offered letters, that touch is labeled by the person. We add its offset to a running per-key total, then refit. Each key's total is capped at a weight of 30, so newer touches count more and the model can follow gradual change. Typing on without tapping the bar is *not* counted. Only per-key sums are stored: no letters in order, no text, no times.

**Demo view.** Turn on ⚙︎ → *Show my touches*. Each tap is drawn with:
- its path, a ring where the finger first touched and a dot where it lifted (orange if a fixed keyboard would have typed something else)
- a green arrow to the chosen key
- purple dashed ellipses showing the learned pattern for the top two keys

The toolbar shows the top-three probabilities and two lines: what a fixed keyboard would have typed versus what was typed.

## Privacy

- **Full Access is not requested.** The keyboard therefore has no network access and no shared storage with the app (enforced by iOS).
- **Stored**, in the keyboard extension's own container as JSON:
  - calibration taps (requested key + touch path)
  - the learned parameters
  - if the person turns on learning: per-key offset totals from letters they explicitly picked
  - settings
  - comparison **scores** if the person opts in
- **Never stored:** typed text or keystroke history. The engine has no type that holds typed text, and a unit test types a word and checks it is absent from every saved file.
- **What we read from the host app:** the character before the cursor (for the letter-pair hint and auto-capitalization), and a check that our last inserted letter is still there before swapping a choice.
- **Delete:** ⚙︎ → *Delete my calibration and settings*, or delete the app.
- **Password and phone-pad fields:** iOS always uses Apple's keyboard there. Apps can also refuse third-party keyboards.

## What is implemented vs. verified

| | Status |
|---|---|
| Touch engine + 39 unit tests (calibration, scoring, sparse data, ambiguity, repeated letters, undo/choice, per-layer evaluation, confirmed-choice learning and forgetting, comparison statistics, storage, delete, no typed text on disk) | **Implemented and passing** (`swift test`, Swift 5.10) |
| Keyboard extension and containing app | **Written and syntax-checked only.** Not yet compiled in Xcode or run on an iPhone. |
| Device behavior (enabling, typing in other apps, switching, persistence, secure fields) | **Not yet verified.** See the checklist. |
| Testing with people who have motor difficulties | **Not done.** Do not claim results until it is. |

## Known limitations

- It learns only from calibration. If someone's movement varies through the day, they need to recalibrate.
- The cursor can't be moved from our keyboard. Use the host app's text selection.
- There is no word prediction, autocorrect, dictation or emoji.
- The keys are drawn on screen and are **not exposed to VoiceOver** individually.
- Some apps and fields block third-party keyboards.
- Landscape works, but the model was learned in the orientation used for calibration.
- We have **not** shown that it helps people with any particular condition. The comparison measures one person on one phone.

## Prior art

Apple Touch Accommodations, ParkinsonKey (larger keys and shortcuts), and research on individualized layouts for people with cerebral palsy. Our contribution is narrower: **personalized interpretation of an individual's own touch pattern, made visible, and measured against fixed layouts.**
