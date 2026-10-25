"""Builds Packages/TouchEngine/Sources/TouchEngine/Resources/words.txt (run once; the output is committed).

Source: FrequencyWords by Hermit Dave, content/2018/en/en_50k.txt (word counts from OpenSubtitles 2018),
https://github.com/hermitdave/FrequencyWords. The word data is CC BY-SA 4.0, so words.txt is too.

Usage: python tools/make_wordlist.py path/to/en_50k.txt
"""
import re
import sys

KEEP = 40000
# Never offer these as a "fix". Prefix match, so "fuck" also covers "fucking".
BLOCKED_PREFIXES = ("fuck", "shit", "bitch", "cunt", "nigg", "fag", "retard", "whore", "slut", "motherf",
                    "dick", "cock", "pussy", "asshole", "bastard", "twat", "wank", "piss", "jackass",
                    "dumbass", "bullshit", "goddamn", "tits", "porn", "spastic", "cripple")
BLOCKED_PREFIXES += ('negro', 'dyke', 'skank', 'rape', 'rapist', 'nazi', 'hitler', 'midget', 'tranny', 'nigger', 'jizz', 'dildo', 'orgasm', 'sperm', 'semen', 'penis', 'vagina', 'boner', 'horny', 'milf', 'hooker', 'porno', 'molest', 'pedophil', 'incest', 'kike', 'chink', 'wetback', 'gook', 'beaner', 'raghead', 'towelhead', 'mongoloid', 'imbecile', 'cretin', 'stripper', 'prostitut', 'erotic', 'kinky', 'fetish', 'bondage')
BLOCKED_EXTRA = ['anal', 'bimbo', 'coon', 'coons', 'cum', 'darkie', 'dumb', 'dumbest', 'escort', 'escorts', 'gay', 'gays', 'hoe', 'hoes', 'homo', 'homos', 'homosexual', 'idiot', 'idiotic', 'idiots', 'jap', 'japs', 'lame', 'lesbian', 'lesbians', 'lunatic', 'lunatics', 'moron', 'morons', 'naked', 'nude', 'nudes', 'paki', 'pakis', 'pimp', 'pimps', 'psycho', 'psychopath', 'psychos', 'psychotic', 'queer', 'queers', 'retard', 'retards', 'sex', 'sexist', 'sexual', 'sexuality', 'sexually', 'sexy', 'spic', 'spics', 'stupid', 'stupidest', 'thot']
# Misspellings common in the subtitle counts, so they'd never be fixed (checked against Wikipedia's
# "Lists of common misspellings/For machines"). Contractions typed without the apostrophe (didnt) stay.
MISSPELLINGS = ['dum', 'ther', 'everytime', 'alot', 'noone', 'overthere', 'upto', 'happend', 'holliday', 'fleed', 'loosing', 'sherif', 'untill', 'gae', 'beggin', 'belive', 'realy', 'commited', 'occured', 'appartment', 'accidently', 'comming', 'wich', 'embarassing', 'ect', 'noth', 'carefull', 'vermillion', 'adress']
BLOCKED = set(BLOCKED_EXTRA) | set(MISSPELLINGS) | {"ass", "damn", "crap", "prick", "spaz", "tit", "boob", "boobs", "hell"}

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
