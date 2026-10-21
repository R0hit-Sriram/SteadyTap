# Mac + iPhone: build, install, test

This guide is for the teammate who builds on a Mac. The code was written on Windows. The **engine** compiles and its tests pass. The **iOS app and keyboard have only been syntax-checked**, so expect a few compile fixes on the first build. Please push the fixes so everyone stays in sync.

## 1. One-time setup

1. Install Xcode 15 or newer from the App Store. Open it once and let it install its components.
2. Xcode ▸ Settings ▸ Accounts: add your Apple ID. A free personal team works; its builds expire after 7 days.
3. Install XcodeGen: `brew install xcodegen` (if needed, install Homebrew from https://brew.sh first).
4. On the iPhone, turn on **Settings ▸ Privacy & Security ▸ Developer Mode** (iOS 16+), then restart. The option appears after the iPhone has been connected to Xcode once.

## 2. Build

```bash
git clone <repo-url> && cd SteadyTap
# Edit the top of project.yml:
#   BUNDLE_ID_BASE: com.<yourname>.steadytap     (must be globally unique)
#   DEVELOPMENT_TEAM: <your Team ID>              (Xcode ▸ Settings ▸ Accounts ▸ your team)
xcodegen generate
open SteadyTap.xcodeproj
```

- Choose the **SteadyTap** scheme and your connected iPhone, then press **Run (⌘R)**.
- If signing fails, open both targets ▸ *Signing & Capabilities* and check that "Automatically manage signing" is on with your team selected. Then copy the team ID into `project.yml` so it survives regeneration.
- The first time, the iPhone may ask you to trust the developer: **Settings ▸ General ▸ VPN & Device Management**.
- Run `xcodegen generate` again after every `git pull` that adds or removes files.

**Run the engine unit tests:**
```bash
cd Packages/TouchEngine && swift test
```
Or open `Packages/TouchEngine/Package.swift` in Xcode and press ⌘U.

**Debugging the keyboard:**
1. Select the **SteadyTapKeyboard** scheme ▸ Run.
2. Pick Notes as the host app.
3. Switch to the keyboard in Notes.

Breakpoints and `print` output then work.

## 3. Enable the keyboard

1. Open **Settings ▸ General ▸ Keyboard ▸ Keyboards ▸ Add New Keyboard…** and choose **SteadyTap**.
2. **Leave "Allow Full Access" OFF.**
3. In any text field, tap or hold 🌐 and choose SteadyTap.

## 4. Device checklist

Write down the iPhone model, iOS version, date and pass/fail for each item. Don't record anything personal.

**Setup and switching**
- [ ] The keyboard appears in Settings and can be added without Full Access.
- [ ] 🌐 on our keyboard: a tap switches to the next keyboard; holding it shows the keyboard list.
- [ ] On iPhones with no 🌐 key in our layout (`needsInputModeSwitchKey` is false), the system's own globe key below the keyboard still switches.

**Typing in other apps** (test at least **Notes** and **Messages**, plus one more such as Reminders or Safari's address bar)
- [ ] Letters, space, backspace, return and the `,` `.` keys work.
- [ ] Shift: one tap capitalizes the next letter; a quick double tap gives caps lock (the icon changes).
- [ ] Auto-capitalization at the start of a field and after ". ".
- [ ] The 123 page: digits and punctuation; ABC returns to letters.
- [ ] Undo removes the last letter or restores a deleted one.
- [ ] Rapid two-finger typing doesn't drop or duplicate letters.
- [ ] Touches at the far left and right edges register promptly. Note any delay: a known iOS issue with edge gestures.

**No calibration**
- [ ] With a fresh install, typing works as a normal fixed keyboard and the bar says "Not calibrated yet".

**Calibration**
- [ ] ⚙︎ ▸ Calibrate. The blue target moves on each tap, the progress bar advances, and a break appears after each set.
- [ ] "Save & stop" after set 1 saves a usable profile.
- [ ] Completing all 3 sets shows the "Your touch pattern" table (standard keyboard → one shift → screen areas → per key, plus contrast rows), and the best point type.
- [ ] ⚙︎ ▸ "What each part of the model adds" reopens that table.
- [ ] **Survives restarts:**
  - force-quit the host app, reopen and switch to the keyboard: still calibrated (⚙︎ shows "Learned from N taps")
  - reboot the iPhone: still calibrated

**Choices and repeats**
- [ ] A tap halfway between two letters shows two buttons. Tapping the other letter replaces it in the text field. Undo restores the original.
- [ ] Typing "hello", "letter", "coffee" keeps the double letters.
- [ ] Holding backspace deletes repeatedly after about half a second. Sliding off it before then just deletes once. The toggle in ⚙︎ turns this off.
- [ ] **Keep adapting** (on by default):
  - After typing a few sentences, ⚙︎ shows "Learned while typing: N picks, N corrections, N sure taps".
  - Type with a deliberately different touch (for example, always tap a little to the right). Within a few dozen letters, more first taps should come out right. The bar may say "Your taps changed — adapting faster".
  - "Go back to just my calibration" resets the counts.
  - With the toggle off, the counts don't change.
  - Counts survive force-quitting the host app (saved every 10 letters and when the keyboard closes).
- [ ] **Fix misspelled words** (on by default):
  - Type "tge" with the middle tap a little toward H, then space. It becomes "the ", and the bar says “Fixed "tge" → "the"”. Undo gives back "tge ".
  - Carefully typed real words ("car", "form") and names stay as typed.
  - Capital first letters are kept ("Tge" → "The").
  - Typing feels as fast as before. If space lags, tell us.
  - With the toggle off, nothing is changed.
- [ ] ⚙︎ ▸ **What it learned about my touch** draws arrows and ovals on the letter keys, plus one sentence about the average offset. After using "Keep adapting" for a while, the shaded ovals move away from the dashed ones.

**Settings**
- [ ] Adaptation off: the touches overlay says "fixed keyboard".
- [ ] Large key height: the keyboard gets taller.
- [ ] Each "Offer two choices" level changes how often the bar appears.

**Delete**
- [ ] ⚙︎ ▸ Delete (tap twice). The bar shows "Not calibrated yet" and the settings are back to defaults. This still holds after a force-quit.

**Secure and restricted fields**
- [ ] In a password field (for example a login form in Safari, or Settings ▸ Wi-Fi ▸ another network's password), iOS shows Apple's keyboard. Leaving the field brings ours back.
- [ ] A phone-number field shows Apple's number pad.

**Demo view**
- [ ] ⚙︎ ▸ Show my touches:
  - rings, dots and paths appear
  - green arrows point to the chosen key
  - purple ellipses appear around the top two keys after calibration
  - the bar shows percentages and "Fixed keyboard: … / Adapted: …"

**Comparison**
- [ ] ⚙︎ ▸ Typing comparison runs 9 phrases. The larger-keys trials are taller. Nothing is typed into the host app.
- [ ] The results show words/min and accuracy (typical value and range), corrections and choices, plus the "may be chance" note when results overlap. After keeping scores from two runs, the second results screen also shows the combined report. "Type this summary" inserts it into the current field. "Keep scores" persists them.

**Privacy**
- [ ] Settings ▸ SteadyTap ▸ Keyboards shows Full Access OFF.

**Containing app**
- [ ] All screens read well at the largest text size (Settings ▸ Accessibility ▸ Display & Text Size).
- [ ] The Open Settings button works.

## 5. Things to tune on a real phone

These are constants, not guesses to defend. Change them if the device says so, then rerun `swift test`.

| Constant | Where | Default |
|---|---|---|
| Row height | `KeyboardController.baseRowHeight` | 54 pt |
| Large key multiplier | `KeySize.rowHeightMultiplier` | 1.4 |
| Ask threshold | `AskLevel.threshold` | 0.85 / 0.70 / 0.55 |
| Minimum spread | `ModelFitter.minSigmaFraction` | 0.15 × key width |
| Shrinkage | `ModelFitter.kappa` | 4 |
| Extra-tap detection | `CalibrationSession.extraTapMaxGap` / `extraTapRadiusFraction` | 0.3 s / 0.6 key |

## 6. Optional sessions with people who have motor difficulties

- **Who:** adults, or minors only with a parent's or guardian's consent. Volunteers only; they can stop at any time.
- **Consent, in plain words:** "This is a student project, not a medical device. We'll ask you to tap some keys and type 6 short phrases. We record only time, accuracy and correction counts. We don't record your name, your health condition or anything else you type."
- **Procedure:**
  1. Install on the team's phone.
  2. Calibrate.
  3. Run the comparison.
  4. Ask "Which mode felt easiest?"
- **Do not ask about diagnosis.** Record only: a participant code (P1, P2…), the phone model, the comparison summary, and their one-sentence preference if they're willing to share it.
- **Do not** present teammates imitating a tremor as evidence. Teammate data is labeled "team testing" and used only to check that the software works.
