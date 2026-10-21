"""Builds Packages/TouchEngine/Sources/TouchEngine/Resources/words.txt (run once; the output is committed).

Source: FrequencyWords by Hermit Dave, content/2018/en/en_50k.txt (word counts from OpenSubtitles 2018),
https://github.com/hermitdave/FrequencyWords. The word data is CC BY-SA 4.0, so words.txt is too.

Usage: python tools/make_wordlist.py path/to/en_50k.txt
"""
import re
import sys

KEEP = 20000
# Never offer these as a "fix". Prefix match, so "fuck" also covers "fucking".
BLOCKED_PREFIXES = ("fuck", "shit", "bitch", "cunt", "nigg", "fag", "retard", "whore", "slut", "motherf",
                    "dick", "cock", "pussy", "asshole", "bastard", "twat", "wank", "piss", "jackass",
                    "dumbass", "bullshit", "goddamn", "tits", "porn", "spastic", "cripple")
BLOCKED = {"ass", "damn", "crap", "prick", "spaz", "tit", "boob", "boobs", "hell"}

words = []
for line in open(sys.argv[1], encoding="utf-8"):
    word, count = line.split()
    if re.fullmatch(r"[a-z]+", word) and word not in BLOCKED and not word.startswith(BLOCKED_PREFIXES):
        words.append((word, int(count)))
    if len(words) == KEEP:
        break

out = "Packages/TouchEngine/Sources/TouchEngine/Resources/words.txt"
with open(out, "w", encoding="utf-8", newline="\n") as f:
    f.write("# Most common English words with counts, from FrequencyWords by Hermit Dave (OpenSubtitles 2018),\n")
    f.write("# https://github.com/hermitdave/FrequencyWords. Licensed CC BY-SA 4.0. Built by tools/make_wordlist.py.\n")
    for word, count in words:
        f.write(f"{word} {count}\n")
print(f"wrote {len(words)} words to {out}")
