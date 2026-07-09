# Bulong — Taglish accuracy test

**Goal:** find out, with numbers, how well Bulong dictates real Filipino and Taglish before we build the marketing around it. ~10 minutes per tester.

This is the single test that de-risks the whole "Tagalog is the moat" bet. Send this to 3–6 Filipino friends who'll actually use it, collect their results, and score them with the guide at the bottom.

---

## For the tester — setup (2 min)

1. Open **Bulong** (menu-bar icon → the small dark rounded icon at the top-right of your screen).
2. Open **Settings → Advanced → Dictation → Language** and choose **Filipino (Tagalog)**.
3. Open **Settings → Set up → Speech models** and make sure **"All languages + translate" (Whisper)** shows **Ready** (download it if not — it's the model that does Filipino; ~600 MB, one time).
4. Make sure **Mode** is **Transcribe** (not Translate).
5. Pick any app you can type into (Notes, Messages, a text field).

## For the tester — the test (8 min)

For each line below: **tap your trigger key, read the sentence out loud naturally (don't over-enunciate), stop, and let Bulong type it.** Then copy exactly what Bulong wrote into the `Got:` line, and rate it.

**Rating:** `✅` = perfect or basically perfect · `🟡` = understandable but had small errors · `❌` = wrong / unusable / turned into English.

> Read each line the way you'd actually say it to a friend or coworker.

### A · Everyday Tagalog
1. Kumusta ka? Sana maganda ang araw mo ngayon.
   - Got: ____________________
   - Rating: ___  Notes: ___
2. Pupunta ako sa palengke mamaya para bumili ng gulay at isda.
   - Got: ____________________
   - Rating: ___  Notes: ___
3. Salamat sa tulong mo kahapon, malaking bagay iyon sa akin.
   - Got: ____________________
   - Rating: ___  Notes: ___
4. Nag-aaral ako ng bagong wika ngayong taon.
   - Got: ____________________
   - Rating: ___  Notes: ___
5. Ang init ng panahon, parang uulan mamayang hapon.
   - Got: ____________________
   - Rating: ___  Notes: ___

### B · Taglish / code-switching (the hard part)
6. Send mo na lang sa akin yung report bago mag-lunch, please.
   - Got: ____________________
   - Rating: ___  Notes: ___
7. Na-approve na ba yung leave request ko for next week?
   - Got: ____________________
   - Rating: ___  Notes: ___
8. Let's schedule a meeting bukas ng umaga, mga 10 AM sana.
   - Got: ____________________
   - Rating: ___  Notes: ___
9. Grabe, ang daming tasks today, di ko alam kung saan mag-start.
   - Got: ____________________
   - Rating: ___  Notes: ___
10. Pwede mo ba i-double check yung invoice? Baka may mali sa total.
    - Got: ____________________
    - Rating: ___  Notes: ___
11. I'll follow up na lang with the client mamaya, wag ka mag-alala.
    - Got: ____________________
    - Rating: ___  Notes: ___
12. Nag-crash yung laptop ko kaya na-delay yung deliverables.
    - Got: ____________________
    - Rating: ___  Notes: ___

### C · Tricky (numbers, names, punctuation)
13. Meeting tayo on March 15 at 2:30 PM, wag kang late ha.
    - Got: ____________________
    - Rating: ___  Notes: ___
14. Yung budget natin ay fifty thousand pesos para sa project na ito.
    - Got: ____________________
    - Rating: ___  Notes: ___
15. Text mo si Kuya Ramon at si Ate Malou tungkol sa handa.
    - Got: ____________________
    - Rating: ___  Notes: ___
16. Question: kailan ang deadline — this Friday or next Monday?
    - Got: ____________________
    - Rating: ___  Notes: ___
17. Okay, so ang plano natin: first, i-finalize yung design; second, i-send sa client.
    - Got: ____________________
    - Rating: ___  Notes: ___

### D · Freeform (your own words)
18–20. Dictate **three sentences about your day**, in whatever Taglish mix you normally speak. Paste what Bulong wrote and rate each.

**Two quick questions:**
- Overall, would you actually use this for Filipino/Taglish? (yes / maybe / no)
- The single most annoying error you saw: ____________________

---

## For you (the founder) — scoring guide

Tally each tester's ratings, then combine across testers.

| Metric | How to get it | What "good" looks like |
|---|---|---|
| **Usable rate** | (✅ + 🟡) ÷ total lines | **≥ 80%** to headline Filipino honestly |
| **Perfect rate** | ✅ ÷ total lines | ≥ 55% is strong |
| **Taglish rate** | usable rate on section **B only** | the real moat — watch this closest |
| **Deal-breakers** | count of ❌, grouped by type | look for the *pattern* (see below) |

**Failure modes to watch (and the fix if they show up):**
- **Tagalog turned into English** → the language pin isn't holding; check that Language is really set to Filipino. (Code already pins `tl`, so this should be rare.)
- **Section B (Taglish) much worse than A** → code-switching is the weak spot; try the **large-v3 (non-turbo)** model for accuracy, and/or a seeded vocabulary prompt.
- **Names/numbers/dates wrong** → mostly cosmetic; note but don't block on it.

**Decision:**
- **≥ 80% usable and B not collapsing** → greenlight the Tagalog-forward site rewrite, ideally with a real demo clip of Taglish working.
- **Below that** → keep the site privacy-led; apply the accuracy levers (large-v3, decoding prompt/custom vocab) and re-test before marketing it.

> Optional: `script/score_taglish.py` computes word error rate from a TSV of `tier⇥reference⇥hypothesis` if you want a hard number instead of eyeballing.
