#!/usr/bin/env python3
"""Score Bulong's Taglish accuracy from tester results.

Usage:
    python3 script/score_taglish.py results.tsv

Input: a TSV with a header row and columns `tier`, `reference`, `hypothesis`
(one row per dictated line; `tier` is A/B/C/etc.). Prints word error rate
(WER) overall and per tier. Lower WER = better; ~0.15 or below is strong.

WER = (word insertions + deletions + substitutions) / reference words,
computed with a standard word-level edit distance. Comparison is
lowercased and stripped of punctuation so spelling/wording is what counts.
"""
import sys
import re
from collections import defaultdict


def normalize(text: str) -> list[str]:
    text = text.lower()
    text = re.sub(r"[^\w\s]", " ", text)          # drop punctuation
    return text.split()


def edit_distance(ref: list[str], hyp: list[str]) -> int:
    # Classic Levenshtein over word tokens.
    prev = list(range(len(hyp) + 1))
    for i, r in enumerate(ref, 1):
        cur = [i]
        for j, h in enumerate(hyp, 1):
            cost = 0 if r == h else 1
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost))
        prev = cur
    return prev[-1]


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2

    rows = []
    with open(sys.argv[1], encoding="utf-8") as f:
        header = f.readline().rstrip("\n").split("\t")
        try:
            ti, ri, hi = header.index("tier"), header.index("reference"), header.index("hypothesis")
        except ValueError:
            print("error: TSV needs a header with columns: tier, reference, hypothesis")
            return 2
        for line in f:
            cols = line.rstrip("\n").split("\t")
            if len(cols) <= max(ti, ri, hi):
                continue
            rows.append((cols[ti].strip(), cols[ri], cols[hi]))

    if not rows:
        print("no data rows found")
        return 1

    by_tier: dict[str, list[int]] = defaultdict(lambda: [0, 0])  # tier -> [errors, ref_words]
    tot_err = tot_words = 0
    for tier, ref, hyp in rows:
        r, h = normalize(ref), normalize(hyp)
        if not r:
            continue
        err = edit_distance(r, h)
        by_tier[tier][0] += err
        by_tier[tier][1] += len(r)
        tot_err += err
        tot_words += len(r)

    def wer(err: int, words: int) -> str:
        return f"{err / words:6.1%}" if words else "   n/a"

    print(f"\n  Lines scored: {len(rows)}\n")
    print("  Tier    WER      (errors / ref words)")
    print("  ----    ------   --------------------")
    for tier in sorted(by_tier):
        err, words = by_tier[tier]
        print(f"  {tier:<6}  {wer(err, words)}   ({err} / {words})")
    print("  ----    ------")
    print(f"  ALL     {wer(tot_err, tot_words)}   ({tot_err} / {tot_words})")
    print("\n  Rule of thumb: <15% strong, 15-30% usable-with-edits, >30% weak.")
    print("  Watch tier B (Taglish) — it's the real test.\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
