# v10_refined: Amendment 2 to the Post-Hoc Refinement Predeclaration (Gate 5)

**Status: SIGNED, 2026-09-22T14:31:18Z. Locked.** See §8. No Gate 5 evaluation has been run under this amendment, and it gives no promote/hold verdict — the earliest possible final look is 2028-02-01 (§4.2).

**Amends:** `archive/v10-round10/docs/v10_posthocrefinement_predeclaration.md` (as committed in c146b91 on `codex/round7-pbp-efficiency`). Amendment 1 is the inline "Amendment (2026-09-21)" in its Part D, which fixed the 0.65 shrink factor.

**Scope:** Gate 5 only (the 2026+ forward P4-vs-G5 test). This amendment does four things:

- (a) sets a season-indexed tier map;
- (b) replaces the two conflicting Gate 5 rules with one;
- (c) sets a sample plan that can actually be met;
- (d) patches `gate5_2026.R` to match.

---

## 0. Disclosure: this was written after the interim read

This amendment was drafted on 2026-09-22. By then the n = 34 interim read (`v10_refined_2026_interim_check.md`) had been run and read, and the n = 28 re-cut had been computed. Read everything below with that in mind.

**What had been seen before drafting**

| Read | v10_refined bias | Incumbent bias | Also seen |
|---|---|---|---|
| Interim, pre-amendment tier map, n = 34 (weeks 2–3), 2026-09-21/22 | +1.56 (SE 2.48; CI [−2.87, +6.32]) | +5.64 | paired ΔMAE −0.416; venue and conference splits; back-solved shrink 0.90 |
| Re-cut dropping the 6 Pac-12-side games, n = 28, 2026-09-22 | +0.49 (SE 2.46) | +4.61 | — |

**What each candidate rule says about the data already seen**

| Candidate rule | n = 34 | n = 28 |
|---|---|---|
| A. Predeclaration band [−1.60, +1.14] | outside | inside |
| B. Prompt rule \|bias\| < 0.23 | fail | fail |
| C. Band re-derived with σ = 16.24: [−2.02, +1.56] | outside (+1.564 vs +1.556) | inside |
| **D. This amendment: \|v10_refined bias\| < \|incumbent bias\|** | **satisfied** | **satisfied** |

**Of all the candidate rules, the one chosen here is the one the already-seen data favors most.** That is the main integrity risk in this amendment. Four things limit it:

1. **No seen game can enter the Gate 5 sample.** Every game that kicked off before the lock is excluded (§4.1). That includes all 34 interim games.
2. **Rule D was suggested before the interim read.** The note in `v10_refined_2026_forward_validation_prompt.md` proposes "v10_refined |bias| < incumbent |bias| in 2026". That file's mtime is 2026-09-21 11:13 EDT. The interim results were written at 2026-09-22 09:26 EDT. This is file-mtime evidence only: the prompt was first committed together with the interim doc (c146b91, 2026-09-22 09:48).
3. **The rule was chosen on 2018–25 data only.** Its operating characteristics (§3.2) use scenarios set at historical era biases, not at 2026 values.
4. **Nothing else changes.** Coefficients, the incumbent design and the consequences of pass/fail stay as they are (§1).

**What this drafting session looked at, and what it did not**

- **Read:**
  - all v10 docs and the original `gate5_2026.R`;
  - the 34 interim rows, to reproduce the n = 28 figures above;
  - 2026 schedule fields, for tier classification, counts and kickoff times;
  - 2018–25 P4-vs-G5 residuals, for σ, venue mix and timing (§3.2, §4).
- **Not computed:** any margin, residual or bias for a 2026 game outside the 34. In particular, nothing was computed for the 6 played P4-vs-2026-Pac-12 games that the corrected map adds (§2.2).
  - So the interim figure under the corrected map is **unknown**. The +0.49 (n = 28) figure is not it, because the corrected map's already-played set is still 34 games.
- **Not run:** Gate 5 itself; the patched script's final-look path on real data; any hashing of this amendment.

---

## 1. What does not change

- **Coefficients:** a = 2.356, b = 1.831.
  - `correction = s × (a + b × p4_home)`
  - `v10_refined = incumbent + correction`
  - No re-fit and no new shrink factor.
- **Incumbent for Gate 5:** the frozen `EB_features` design.
  - design_hash `0f876d7390dace668ab8fb80547b949e`
  - feature_hash `6a7e01742348969e8c623e21702185c6`
  - This holds even if production changes before the final look.
- **Gates 1–4:** as executed on 2026-09-21 (`v10_refined.py`, interim report). All passed; not reopened.
- **Consequences (predeclaration Part E):** Gate 5 PASS → promote v10_refined. FAIL → stay on the incumbent.
- **Not covered:** `v10_refined_v2` (the empirical-Bayes candidate, a = 3.503, b = 2.834). Evaluating it on the same window needs its own predeclaration, and the report must then show both candidates.

---

## 2. Tier map (season-indexed)

### 2.1 Map

| Conference label (CFBD, per game and season) | Seasons ≤ 2025 | Seasons ≥ 2026 |
|---|---|---|
| ACC, Big Ten, Big 12, SEC | P4 | P4 |
| Pac-12 | P4 | **G5** |
| American Athletic, Conference USA, Mid-American, Mountain West, Sun Belt | G5 | G5 |
| Anything else (FBS Independents, FCS, missing) | Other | Other |

- **Game encoding:** `s` = +1 if a P4 home team hosts a G5 team, −1 if a G5 home team hosts a P4 team, 0 otherwise. `p4_home` = 1 when s = +1 and the site is not neutral.
- **Consistency:** this is the same map as the Round 12 draft (B3).
- **2024–25 two-team Pac-12** (Oregon State, Washington State): stays P4, as executed. It touches 26 of the 318 conditional games, which are report-only. The frozen coefficients use 2018–19 and 2021–22 only, so they are unaffected.
- **2027 labels:** before the first 2027 kickoff, check the 2027 labels against this table (labels only, no outcomes). A new label counts as Other unless an amendment made before that kickoff says otherwise.
- **`v10_refined.py` needs no change.** Its data ends in 2025, where its map and this one agree. It must not be reused on 2026+ games.

### 2.2 Effect on 2026

| | Pre-amendment map | Season-indexed map |
|---|---|---|
| P4-vs-G5 games scheduled | 77 | 76 |
| Dropped: 2026 Pac-12 vs G5 | — | 13 (7 played; 6 were in the interim 34) |
| Added: P4 vs 2026 Pac-12 | — | 12 (11 played; 6 of those have a Sep-9 prediction) |
| Played with a snapshot prediction (weeks 2–3) | 34 | 34 (28 overlap + 6 added, unseen) |

- **Dropped from the interim set:** Texas State–UTSA, Boise State–Memphis, Fresno State–Sacramento State, Texas State–North Texas, San Diego State–James Madison, San José State–Fresno State.
- **Added (played, with a prediction):** Kansas State–Washington State, Washington–Utah State, UCLA–San Diego State, Oregon State–Texas Tech, Utah–Utah State, Colorado State–BYU.
- All twelve kicked off before any possible lock, so they are excluded from Gate 5 either way.

---

## 3. Gate 5 rule

### 3.1 The rule

Let E be the eligible set (§4.1) and n = |E|. For each game i in E:

- r_i = (actual_i − incumbent_i) × s_i. This is the incumbent's P4-oriented residual.
- c_i = a + b × p4_home_i. This is the applied correction, always > 0.
- B_inc = mean(r_i).
- B_ref = mean(r_i − c_i) = B_inc − C̄, where C̄ = mean(c_i).

**Gate 5 PASSES iff |B_ref| < |B_inc|.**

- Ties fail.
- The rule uses point estimates and is applied at a single look.
- It is equivalent to **B_inc > C̄ / 2**.
- **Why C̄ / 2:** for a constant shift c, the shifted predictions have lower mean squared error on these games exactly when the true incumbent bias exceeds c / 2. So the rule asks the promotion question directly: in 2026–27, does the frozen correction make P4-vs-G5 predictions better or worse?

### 3.2 Why this rule

The table gives the probability that each candidate passes, at the design sample n = 100.

- **Residual SD:** σ = 16.24, the incumbent's P4-vs-G5 residual SD in 2023–25.
- **Mean applied correction:** C̄ = 3.88 (§4.5), so the break-even incumbent bias is 1.94.
- **Scenarios:** the era biases from predeclaration A1.

| True incumbent bias | v10_refined true bias | Better model | A: band [−1.60, +1.14] | B: \|bias\| < 0.23 | C: band [−2.02, +1.56] | **D: \|B_ref\| < \|B_inc\|** |
|---|---|---|---|---|---|---|
| 0.00 (bias gone) | −3.88 | incumbent | 0.08 | 0.01 | 0.13 | **0.12** |
| 1.00 | −2.88 | incumbent | 0.21 | 0.02 | 0.29 | **0.28** |
| 1.94 (break-even) | −1.94 | tie | 0.39 | 0.06 | 0.50 | **0.50** |
| 3.44 (2023–25) | −0.44 | v10_refined | 0.60 | 0.11 | 0.72 | **0.82** |
| 4.25 (2018–19) | +0.37 | v10_refined | 0.57 | 0.11 | 0.70 | **0.92** |
| 7.10 (2021–22) | +3.22 | v10_refined | 0.10 | 0.02 | 0.15 | **1.00** |

**The bands (A and C) answer the wrong question.**

- **They test stability, not benefit.** Both are centered on −0.23, the 2023–25 value that the 0.65 shrink was chosen to reach (interim report, caveat 3a). So they test "is 2026 like 2023–25?", not "does the correction help?"
- **They reject hardest when the correction helps most.** With 2021–22-level bias, only 10–15% pass.
- **Band A has two further problems:**
  - It uses σ = 13, giving an SE of 0.73. The actual SE on those 318 games is 0.91.
  - It treats the 2023–25 estimate's confidence interval as if it were a prediction interval for a new estimate.

**Rule B almost never passes.** It passes at most 11% of the time in every scenario, including when the correction is exactly right.

**Rule D is the only one whose pass rate rises with the benefit.**

- **Its errors cluster near break-even,** where the two models are nearly equally accurate.
- **Cost of promoting, per P4-vs-G5 game.** Promoting changes MSE per P4-vs-G5 game by:
  - +15 if the bias has vanished;
  - 0 at break-even;
  - −12 at 2023–25 levels;
  - −40 at 2021–22 levels.
  - The baseline MSE is about 264.

**Why the rule does not require significance.** At n = 100, a one-sided superiority test would pass a correction that is right at 2023–25 levels only 24% of the time at α = 0.05, or 36% at α = 0.10. At any sample size reachable here, that amounts to holding by default. If you want that stricter rule anyway, choose it at sign-off (§7).

**Monte Carlo check.** 20,000 replications using the empirical shape of the 2023–25 residuals, at n = 100, give rule D pass rates of 0.11, 0.28, 0.50, 0.83, 0.92 and 1.00. These match the normal approximation.

### 3.3 Reported but never gating

- Standard errors and 95% CIs, both iid and week-block bootstrap (2,000 reps, seed 42)
- Paired ΔMAE and ΔMSE
- Venue split and P4-conference split
- Snapshot age at kickoff

### 3.4 Gate numbering

The predeclaration's B2 section labels two different gates "Gate 5": the calibration slope and the forward validation. The executed run (`v10_refined.py` and the interim report) numbers them differently: 3 = bias reduction, 4 = calibration slope, 5 = forward test.

This amendment uses the executed numbering. "Gate 5" means the forward test only.

### 3.5 How the conflicting documents are reconciled

| Document | Text | Status |
|---|---|---|
| Predeclaration B2, "Gate 5: Forward validation" | Band [−1.60, +1.14], derived with SE 0.7 from σ = 13 | Replaced by §3.1 |
| Predeclaration Part C, expected outcomes | "2026 forward bias: testing only; no threshold set in advance" | Replaced by §3.1 |
| Predeclaration Part E and Next Steps §2–3 | Band test on "2026 data" | Rule replaced by §3.1 and sample by §4. PASS → promote and FAIL → stay are kept. |
| `v10_refined_2026_forward_validation_prompt.md` | Decision rule \|bias\| < 0.23; tier set in Step 1 without a season index; Step 4 code | Replaced by §3.1 and §2. That document's own note proposed rule D. |
| `v10_refined_2026_interim_check.md` | "Re-check at n = 100–150" | Replaced by the single look in §4.2 |
| `v10_refined_shrinkage_methodology.md` | "Run gate 5 on both at n ≈ 100–150" | Not governed by this amendment (§1) |
| `gate5_2026.R` | Tier map without a season index; band; PASS/FAIL printed at any n | Patched (§5) |

---

## 4. Sample plan

### 4.1 Eligibility (a game must meet all five)

1. It is P4-vs-G5 under §2, for that game's season.
2. It kicks off at or after `LOCK_UTC`, which is set at sign-off (§6). Every earlier game is excluded, whether or not anyone has seen it.
3. It is in season 2026 or 2027, regular season or postseason. The development set includes 55 December–January games from 2018–25.
4. It is completed, with both scores.
5. It has an incumbent prediction that meets all of these conditions:
   - It comes from an md5-verified snapshot in `outputs/round4/prospective/`.
   - The snapshot carries the frozen design and feature hashes.
   - Its `predicted_at` is before kickoff. The schedule's kickoff time is authoritative.
   - If more than one snapshot qualifies, the latest is used.
   - A game with no qualifying snapshot is excluded, never back-filled.

### 4.2 Window and the single look

- **Window:** from the lock through the end of the 2027 postseason.
- **Final look:** the first run on or after **2028-02-01**. Gate 5 is evaluated **once**; the script refuses a second final look.
- **Floor:** if n < 60 at the final look, no verdict is given. The window then extends through 2028 regular-season weeks 1–4, and the look happens on or after 2028-10-01 at whatever n has been reached. The extension depends only on counts.
- **Before the final look, counts only:** scheduled, in-window, played, and missing a snapshot. No session computes a bias, residual, MAE or CI for in-window games before then. The interim check's re-check cadence is withdrawn.

### 4.3 Projected supply

| Source | Expected n | Basis |
|---|---|---|
| 2026 weeks 4–9 | **14** | 2026 schedule; all 14 have a Sep-9 prediction. Only 5 remain if the lock falls after the first week-4 kickoff (2026-09-26 16:00 UTC). |
| 2026 postseason | ≈ 8 | 2018–25 had 55 December–January P4-vs-G5 games over 7 seasons |
| 2027 regular season | ≈ 76 (64–90) | The 2026 count under §2 |
| 2027 postseason | ≈ 8 | Same basis as 2026 |
| **Total** | **≈ 106 (≈ 80–125)** | Design point for power: n = 100 |

For reference, a 2026-only test would have about 22 games. At that size, rule D passes a correction that has become useless 29% of the time (§4.5).

### 4.4 Operational requirements (these decide whether the sample exists)

- **Weekly snapshots.** Archive an incumbent snapshot every week of the window: `v5_weekly_update()` then `v5_archive_upcoming()` in `cfb_vCurrent_operations.R`, with a Monday information cutoff. That matches the 5–6-day protocol used for 2018–25. The single Sep-9 snapshot is valid (all 710 of its rows were made before kickoff), but it is stale for later weeks.
- **2027 preseason snapshot before the first 2027 kickoff.** Week 1 holds 32% of P4-vs-G5 games (2018–25). The 2026 archive started on 2026-09-09 and missed all 28 week-1 games.
- **Postseason coverage.** Snapshots must include postseason games.
  - By default `v5_archive_upcoming()` reads the cached schedule `cfb_data_v3/raw_schedule_<season>.rds`. That cache has no bowls: the Sep-9 snapshot's latest kickoff is 2026-12-12.
  - After bowl pairings are announced, pass it a refreshed schedule. `read_schedule(..., refresh = TRUE)` pulls both season types.
- **Weekly monitoring.** Run `gate5_2026.R` weekly in counts-only mode. It warns when an in-window game was played without a pre-kickoff snapshot.

### 4.5 Power: rule D pass probability by n

σ = 16.24. Break-even incumbent bias is 1.94.

| True incumbent bias | n = 22 | 60 | 80 | **100** | 120 | 150 | 200 |
|---|---|---|---|---|---|---|---|
| SE of bias | 3.46 | 2.10 | 1.82 | **1.62** | 1.48 | 1.33 | 1.15 |
| 0.00 (bias gone; hold is right) | 0.29 | 0.18 | 0.14 | **0.12** | 0.10 | 0.07 | 0.05 |
| 1.00 (hold is right) | 0.39 | 0.33 | 0.30 | **0.28** | 0.26 | 0.24 | 0.21 |
| 1.94 (break-even) | 0.50 | 0.50 | 0.50 | **0.50** | 0.50 | 0.50 | 0.50 |
| 3.44 (2023–25; promote is right) | 0.67 | 0.76 | 0.80 | **0.82** | 0.84 | 0.87 | 0.90 |
| 4.25 (2018–19) | 0.75 | 0.86 | 0.90 | **0.92** | 0.94 | 0.96 | 0.98 |
| 7.10 (2021–22) | 0.93 | 0.99 | 1.00 | **1.00** | 1.00 | 1.00 | 1.00 |

**Planning value for C̄: 3.88.**

- It assumes a P4-home share of 0.83: the 2026 regular season is 0.91, and bowls are at neutral sites.
- **Sensitivity:** the break-even is 1.84 at a share of 0.72 (2018–25) and 2.06 at 0.96.
- **Which C̄ gates:** the rule uses the realized C̄ of the eligible set, not this planning value.

---

## 5. Patch to `gate5_2026.R`

**Files:**

- Patched script: `gate5_2026.R`
- Unified diff against the pre-amendment script: `archive/v10-round10/docs/v10_refined_amendment_02_gate5_2026R.diff`
  - The pre-amendment script's sha256 is `79d3203005071793cf62ede8a40fe63be5a99abf31e8a545dc913853dae7d920`.
  - The diff reverse-applies to recover it.

**Changes:**

1. **Tier map.** `tier_of(conference, season)` implements §2.1 and replaces the fixed `P4`/`G5` vectors.
2. **Schedule pulls.** Pulls regular season and postseason for 2026 and 2027, and for 2028 only if the extension triggers. Each pull is saved with a timestamp.
3. **Snapshot handling.**
   - Reads every snapshot in `outputs/round4/prospective/` and verifies each one's md5.
   - Keeps only the frozen `EB_features` design and feature hashes.
   - Takes the latest `predicted_at` before kickoff. `predicted_at` is parsed as America/New_York local time; kickoff is UTC.
4. **Lock.** Applies `LOCK_UTC`. While it is unset, the script only reports counts.
5. **Output before and at the final look.**
   - Before the final look it prints counts only.
   - At the final look it applies §3.1 once and writes a read-only report and row file.
6. **Removed:**
   - the [−1.60, +1.14] band;
   - the PASS/FAIL printout on every run;
   - the back-solved shrink and the "actionable fix" section. A new shrink factor would be a new candidate, not a Gate 5 output.
7. **Output location.** It never overwrites the interim files (`2026_schedule_refreshed.csv`, `2026_predictions_incumbent.csv`, `2026_gate5_results.csv`). Outputs go to `archive/v10-round10/results/gate5_amendment02/`.

**Verification (2026-09-22): 17 checks pass.**

- **Real data, classification and counts only:**
  - the tier map, including Pac-12 at 2025 vs 2026;
  - the 2026 P4-vs-G5 count of 76, with 13 dropped and 12 added;
  - snapshot md5 and timezone handling;
  - no week-1 predictions exist;
  - the counts summary (this caught and fixed a column-shadowing bug in `summarise`).
- **Synthetic data only:**
  - the latest pre-kickoff snapshot is used and a post-kickoff one is ignored, including across the EDT/UTC boundary;
  - the verdict matches a hand calculation, and the rule is equivalent to B_inc > C̄ / 2;
  - a second final look is refused;
  - the n < 60 extension gives no verdict;
  - an unsigned run prints no bias.
- **Real counts-only run with a hypothetical lock of 2026-09-24T00:00Z:** 76 P4-vs-G5 games, 62 excluded as pre-lock, 14 in window, 0 played.

---

## 6. Lock procedure (after sign-off only)

1. Complete §8.
2. Set `LOCK_UTC` in `gate5_2026.R` to a time at or after sign-off. To keep the 9 week-4 games, it must be before **2026-09-26 16:00 UTC**.
3. Copy this file, the diff and the patched script into the main checkout. The drafts currently sit in a Claude worktree.
4. Write the sha256 of this file and of `gate5_2026.R` to `archive/v10-round10/docs/v10_refined_amendment_02.sha256`, then commit all of them. `gate5_2026.R` is currently untracked; track it.
5. Add a one-line "Superseded by Amendment 2" pointer to the forward-validation prompt and to the interim check. Leave the predeclaration itself unedited.
6. Start the weekly snapshots (§4.4).

---

## 7. Decisions for sign-off (default in bold)

1. **Rule:**
   - **D on point estimates** (default).
   - Alternative: D with a one-sided 90% bound. It is stricter: it passes 36% of the time at 2023–25 bias and under 1% at zero bias.
2. **Postseason:**
   - **Included** (default).
   - Alternative: regular season only, which costs about 16 games.
3. **Floor and extension:**
   - **n ≥ 60; otherwise extend through 2028 weeks 1–4** (default).
4. **Interim reads:**
   - **None; counts only** (default).
5. **2024–25 Pac-12:**
   - **P4, as executed** (default).

---

## 8. Sign-off

- Approved by: Will Cavender (user, via chat instruction to finalize)
- Date/time (UTC): 2026-09-22T14:31:18Z
- `LOCK_UTC`: 2026-09-22T14:31:18Z
- Options changed from defaults (§7): none — all five defaults accepted
- sha256 of this file: see `v10_refined_amendment_02.sha256`
- sha256 of `gate5_2026.R`: see `v10_refined_amendment_02.sha256`

**Provenance (sha256, recorded 2026-09-22 before drafting):**

| File | sha256 |
|---|---|
| `v10_posthocrefinement_predeclaration.md` (matches c146b91) | `297ecf1f31a9bdbabafdb34a718741f4daca553f191a9e783c4dbfb453c9a447` |
| `v10_refined_2026_forward_validation_prompt.md` (matches c146b91) | `d7272434a6c2454d189e0997e5043a35f745d6f73029382c3c286adba44e736c` |
| `gate5_2026.R` (pre-amendment) | `79d3203005071793cf62ede8a40fe63be5a99abf31e8a545dc913853dae7d920` |
| `results/2026_gate5_results.csv` (the 34 seen rows) | `372d5d92f45a25e166035fbeba955724341a72e7c02bea6d0333b4573453a578` |
| `results/2026_schedule_refreshed.csv` | `86ce2905d49812445a182d5b1fa7bc9ea7d936f8945a5596f8edb9ee7bc24fa8` |
| `outputs/round4/prospective/predictions_20260909T142134.csv` (md5 `5ee7fcce…` matches its sidecar) | `b2732b2c60dd4dc718052b839938d4bf744e2585c32959af720f533f0aebd323` |
| `results/refined/v10_refined.py` | `ab3117eca7fb88ec38b5800ea9c74d5160b3c9fd83b2674fe07d29e34686897e` |
