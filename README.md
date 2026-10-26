# SteadyTap

An iPhone keyboard for older adults and anyone whose taps often land on the key next to the one they meant, including people with tremor or other motor difficulties. It learns **one person's touch pattern** from a short tapping exercise. It then uses that pattern to read their later taps, directly inside Notes, Messages and other apps.

It is an accessibility tool, not a medical device. It does not diagnose, treat or claim to help any specific condition.

Made by Rohit Sriram (Wakeland High School) and Prajin Kannan Babu Sangitha (Emerson High School), Frisco ISD, Texas, for the 2026 Congressional App Challenge.

## Repository layout

```
project.yml                 XcodeGen spec → generates SteadyTap.xcodeproj on a Mac
App/                        containing app (SwiftUI): setup steps, practice field, privacy, how it works
Keyboard/                   keyboard extension (UIInputViewController)
  KeyboardViewController    entry point, height, globe key, host text sync
  KeyboardController        screen state, calibration/comparison flow, settings, storage
  TouchSurfaceView          single view that captures every touch path and draws keys + demo overlay
  KeyboardViews             SwiftUI toolbar, choice bar, settings and result panels
Packages/TouchEngine/       the algorithm: pure Swift, no UIKit, unit-tested
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

**iOS app (Mac with Xcode 15+):** the Xcode project is committed, so there is nothing to install first.
```bash
git clone https://github.com/R0hit-Sriram/SteadyTap.git
open SteadyTap/SteadyTap.xcodeproj   # pick the SteadyTap scheme + your iPhone, press Run
```
Set **Signing & Capabilities ▸ Team** to your own Apple ID for both targets (or edit `BUNDLE_ID_BASE`
and `DEVELOPMENT_TEAM` at the top of `project.yml`), since the committed values are one team member's.

`project.yml` is still the source of truth. After changing it, run `xcodegen generate`
(`brew install xcodegen`) and commit the regenerated project. If a pull ever conflicts inside
`project.pbxproj`, delete the `.xcodeproj` and regenerate it rather than merging by hand.

Full steps and the device checklist are in [docs/MAC_AND_IPHONE.md](docs/MAC_AND_IPHONE.md). To rename the product, change `APP_DISPLAY_NAME` in `project.yml`.

**iPhone or iPad only.** Building and installing an iOS app needs Xcode, which Apple ships for macOS
alone, so a Windows or Linux machine cannot build or run SteadyTap. Those teammates can still read and
change the code, the engine, and `project.yml`; the engine's tests run anywhere Swift does (above).

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

   Every number is leave-one-out accuracy on that person's own calibration taps. Layers don't always help: for a very regular person "no borrowing" can score slightly higher, and the table shows that too.
10. **Keeps adapting while you type (online learning, `OnlineLearner.swift`, on by default, can be switched off).** Everyday typing doesn't tell us the intended key, so the keyboard keeps the last 3 typed letters in memory only and waits to see what happens to them. Each becomes one of three labeled examples, trusted differently:

    | Label | When | Weight | Updates |
    |---|---|---|---|
    | **picked** | the person tapped a letter in the two-choice bar | 1.0 | average + spread |
    | **corrected** | the letter was deleted and a nearby key retyped, and the model had given that key ≥ 2% for the original touch (so changing "cat" → "car" teaches nothing) | 1.0 | average + spread |
    | **confident** | the model was ≥ 90% sure and the letter survived 3 more letters | 0.3 | average only |

    Unverified "confident" labels never shrink the spread, because they're biased toward easy taps and would make the model overconfident.
    - Each update fades all earlier evidence by 0.5% (calibration included), so evidence halves after about 140 learned touches and the model follows the person's current style.
    - **Change detection:** we track the share of letters needing a fix over the last ~10 letters and the last ~100. When the recent rate is 15 points above the usual rate (after 30 letters), fading speeds up to 3% per update for 60 updates.
    - ⚙︎ shows what it learned and offers "Go back to just my calibration".
    - **Simulation results** (synthetic typist, first-try accuracy per 100 letters, static → adaptive):
      - touch shifted 22pt after calibration: 41–50% → 78% in the first 100 letters, then 100%
      - shift appears after 300 letters: 66–74% → 95%, then 100%
      - no change: 100% → 100%, so adapting doesn't hurt a stable typist

      These are simulations, not people.
11. **Fixes whole words when space is pressed (`WordFixer.swift`, on by default, can be switched off).** A "noisy channel" decoder, the same idea phone keyboards use, kept small enough to explain:

    score(word) = log P(taps | word) + log P(word)

    - **P(letter | tap)** comes from this person's touch model (touch evidence only; the letter-pair hint is left out so it isn't counted twice). Each letter also keeps a 3% "spelling slip" chance, shared across the alphabet, so even a tap right on a key can be a typo (otherwise a careful typist's typos could never be fixed).
    - **P(word)** comes from about 40,000 of the most common English words (`Resources/words.txt`, built by `tools/make_wordlist.py`; profanity, slurs and sexual words filtered out).
    - **P(taps | word)** lines the taps up with the word's letters (dynamic programming, like a spell checker). Usually each tap means one letter, but a tap can also be **extra** (a repeated tap on the same letter, a tremor "bounce", is the likeliest kind), a letter can be **missed**, or two letters can be **swapped**. Each of these costs a fixed penalty, so the plain reading wins unless another word is much better.
    - Every listed word with one letter more, the same number, or one fewer competes with what was typed (an unlisted typed word gets the rarest word's prior times e⁻⁷, because most unlisted words people type are misspellings; names stay when no listed word is close). A letter picked in the two-choice bar can't be changed. The scores become probabilities with softmax. The word changes only if the best one is ≥ 80% likely.
    - **Checking its own confidence.** After calibration we test how sure the touch model says it is against how often it was actually right on this person's taps (each tap scored by a model that never saw it). If it was too sure, its letter probabilities are turned down for word fixing (`ModelFitter.confidenceScale`, never turned up), so "80% sure" means closer to 80% for this person.
    - Letters picked in the two-choice bar are treated as certain. Undo restores the typed word. Capitals are kept, and ALL-CAPS words are left alone.
    - Not used in the typing comparison, so that test still measures touch reading alone. A word fix is a guess, so online learning doesn't learn from it.
    - **Simulation result** (synthetic noisy typist, σ = 10 pt, typing once with no corrections): words right **64% → 93%**. A steady typist (σ = 3 pt) stays at 100%. A typist who also misses some letters and taps some twice (σ = 6 pt): **70% → 92%**. Common spelling mistakes typed with clean taps ("becuase", "tommorow", "goverment"…): **31 of 31** fixed, while names like "rohit" and real words like "diner" stay.
    - At most about one missing, extra or swapped letter per word is realistic to fix; heavily garbled words are left alone.
12. **"What it learned about my touch"** (⚙︎). For each letter it draws an arrow from the key's middle to where this person's taps really land, with an oval for their spread. A dashed oval shows the calibration-only model, so you can see how far it has adapted since. Below, one plain sentence gives the average offset.

**Demo view.** Turn on ⚙︎ → *Show my touches*. Each tap is drawn with:
- its path, a ring where the finger first touched and a dot where it lifted (orange if a fixed keyboard would have typed something else)
- a green arrow to the chosen key
- purple dashed ellipses showing the learned pattern for the top two keys

The toolbar shows the top-three probabilities and two lines: what a fixed keyboard would have typed versus what was typed.

## Testing with real people

Three of our grandparents in India tried SteadyTap. Each one typed the same phrases on the normal iPhone keyboard and then on SteadyTap after calibrating, with an adult family member helping, and we screen-recorded both. We counted the results from the recordings, so the numbers are approximate.

| Tester | Letters correct (normal → SteadyTap) | Other notes |
|---|---|---|
| Rohit's grandma | 71% → 83% | Typing speed went from about 8 to 10 words per minute |
| Prajin's grandma | 85% → 92% | Backspaces went from 17 to 9 |
| Prajin's grandpa | 95% → 95% | Already accurate. He said calibration felt too long |

Both grandmas liked it because they could send cleaner messages to family. The grandpa's feedback is the main thing we'd change next: a shorter calibration for people whose first test is already accurate. Three people is a small test, none of them were tested for a specific condition, and this is not a medical study.

## Credits

- Word list: [FrequencyWords](https://github.com/hermitdave/FrequencyWords) by Hermit Dave (OpenSubtitles 2018 counts), CC BY-SA 4.0. Our filtered `words.txt` is shared under the same license.

## AI use (disclosed, as the Congressional App Challenge rules require)

We used Claude (Anthropic), through Claude Code. It helped us write and debug code (mostly UI bugs we couldn't track down), wrote and ran the unit tests and the simulated-typist tests described above, helped write this README, and helped edit our demo video. Our grandparents' results come from their own screen recordings, not from the simulations. The app itself uses no AI: everything runs on the phone with our own algorithm, and we can explain how each part works.

## Privacy

- **Full Access is not requested.** The keyboard therefore has no network access and no shared storage with the app (enforced by iOS).
- **Stored**, in the keyboard extension's own container as JSON:
  - calibration taps (requested key + touch path)
  - the learned parameters
  - if "Keep adapting" is on: running per-key offset totals with older evidence faded, fix-rate averages and label counts. No text, no letter order, no times; the last 3 typed letters are held in memory only and never written.
  - settings
  - comparison **scores** if the person opts in
- **Never stored:** typed text or keystroke history. The engine has no type that holds typed text, and a unit test types a word and checks it is absent from every saved file.
- **What we read from the host app:** the character before the cursor (for the letter-pair hint and auto-capitalization), and a check that our last inserted letter is still there before swapping a choice.
- **Delete:** ⚙︎ → *Delete my calibration and settings*, or delete the app.
- **Password and phone-pad fields:** iOS always uses Apple's keyboard there. Apps can also refuse third-party keyboards.

## What is implemented vs. verified

| | Status |
|---|---|
| Touch engine + 79 unit tests (calibration, scoring, sparse data, ambiguity, repeated letters, undo/choice, per-layer evaluation, online learning under drift and no drift, labeling rules, change detection, whole-word fixing, comparison statistics, storage, delete, no typed text on disk) | **Implemented and passing** (`swift test`, Swift 5.10) |
| Keyboard extension and containing app | **Built in Xcode and running on an iPhone** (team-tested). |
| Device behavior (enabling, typing in other apps, switching, persistence, secure fields) | **Checked by the team on one iPhone.** The full list is in docs/MAC_AND_IPHONE.md. |
| Testing with real users | **3 older adults** (our grandparents, see above), plus team testing. We have not tested with people who have specific motor conditions, and we make no claims about them. |

## Known limitations

- Online learning needs a few dozen letters to catch up with a big change; recalibrating is faster. Its labels are inferred from behavior (picks, corrections, kept letters), so unusual editing habits could teach it the wrong thing. "Go back to just my calibration" undoes this.
- The cursor can't be moved from our keyboard. Use the host app's text selection.
- Word fixing handles wrong, missing, extra and swapped letters, but only within one letter of the typed length, English only. There is no word prediction or dictation. Emoji come from a small built-in panel of 48 common ones.
- Word fixing reads the current word before the cursor so it can replace it. The word is held in memory only and cleared at the next space.
- The keys are drawn on screen and are **not exposed to VoiceOver** individually.
- Some apps and fields block third-party keyboards.
- Landscape works, but the model was learned in the orientation used for calibration.
- We have **not** shown that it helps people with any particular condition. Our real-user test was 3 people, and the built-in comparison measures one person on one phone.
- Calibration (63 taps) can feel long for someone who already types accurately.

## Prior art

Apple Touch Accommodations, ParkinsonKey (larger keys and shortcuts), and research on individualized layouts for people with cerebral palsy. Our contribution is narrower: **personalized interpretation of an individual's own touch pattern, made visible, and measured against fixed layouts.**
