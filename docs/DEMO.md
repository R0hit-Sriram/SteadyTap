# CAC demo video outline (target 2:30, hard max 3:00)

Film the real iPhone screen with a screen recording, plus a hand camera for the tapping. Everything shown must be live; nothing is pre-recorded "magic".

| Time | Show | Say (approx.) | Rubric area |
|---|---|---|---|
| 0:00–0:20 | A hand typing on the normal iPhone keyboard; mistakes pile up | "Some people can use a touchscreen but often hit the key next to the one they meant: because of tremor, cerebral palsy, injury, or other reasons. A short message can take minutes." | Need |
| 0:20–0:35 | App home screen → enabling the keyboard (sped up) | "We built an iPhone keyboard that learns *your* touch pattern. No diagnosis, no account, no internet, no Full Access." | Impact/originality |
| 0:35–0:55 | Calibration inside Notes: blue targets, break screen, summary percentages | "You tap 63 highlighted keys in three short sets. For every tap we record which key we asked for and where the finger actually went." | Functionality |
| **0:55–1:15** | **THE MOMENT:** Notes with *Show my touches* on. Type "hello world" with taps that land on neighboring keys | "The orange dots are where the finger actually touched: on R, not E. The green arrows show what our keyboard decided. Up here, the same touches on a fixed keyboard would read 'hrllo qorld'. Ours typed 'hello world'." | Functionality + design |
| 1:15–1:50 | Code on screen: `ModelFitter.fitParameters`, `Decoder.score`; then the purple ellipses; then the **"Your touch pattern" table** | "Here's the algorithm we wrote. For each key we learn the average offset and spread of your touches. Keys with few taps borrow from their screen region, so we don't overfit. We test four candidate touch points and keep whichever predicts your taps best, using leave-one-out testing. A new tap gets a probability for each key; if two are close, you choose. And this table shows, on your own taps, how much each part adds, including where a part *didn't* help. It keeps learning as you type: from letters you pick, letters you fix, and letters it was sure about, with old evidence fading, so it follows you if your touch changes. Then ⚙︎ ▸ What it learned shows that on screen. When you press space, it also checks the whole word: it multiplies how likely each tap was to be each letter, for you, by how common the word is, and fixes the word only if it's at least 80% sure." | Code explanation |
| 1:50–2:05 | A two-choice bar appears → tap the other letter → Undo | "We never silently guess on a close call, and Undo is always one tap away. Double letters are kept unless calibration showed accidental extra taps, and even then you can add the letter back." | Design |
| 2:05–2:25 | Comparison results screen | "A built-in test compares a standard keyboard, larger keys, and the adapted keyboard on the same phrases. These are [team testing / volunteer] results, and they come from one person, so they aren't a clinical finding." | Impact |
| 2:25–2:45 | Privacy screen and the limitations | "It stores only calibration taps, never what you type. What we learned: [one honest insight]. Next: testing with more people who have motor difficulties." | Need/impact |

## Honesty rules for the video

- Real-user results come from our 3 grandparent testers (see the README). Label them as approximate and as a small test, not a study.
- Label teammate demonstrations as a demonstration of the software, not evidence that it helps any condition.
- Use the real comparison numbers, whatever they are. A result where "larger keys" won is still a finding.
- Don't call it AI. It's "a personalized statistical model of your touches" and we can explain every step.
