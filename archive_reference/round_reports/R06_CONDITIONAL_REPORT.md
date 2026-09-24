# Round 6 — secondary conditional scoring, 2023–2025

Scored with the frozen design only (`bcf35f7`, design MD5 `3a9e7753a7d35da9d6c8123b30ad3e68`).
Nothing was re-fitted on 2023–2025. No market data was read. Results were written once and are
read-only. **This result cannot change the frozen selection, and nothing is promoted.**

The frozen selection is `P4_E3AB_state_mean_tail`, a **manual override** of the predeclared
preference rule. The rule's pick, `P4_E3AB_hfa_mean`, is scored alongside as the comparator.

Universe: **2,398** completed FBS-vs-FBS games, the same game IDs Round 5 scored. All three
seasons admitted the full efficiency metric set.

---

## 1. Confirmation readouts (predeclared in §4.5c)

| readout | frozen selection | rule-preferred comparator |
|---|---|---|
| **C1** paired MAE gain > 0 | **+0.0646** ✓ | +0.0257 ✓ |
| **C2** bias deterioration ≤ 0.10 | **+0.315** ✗ | +0.300 ✗ |
| **C3** tail: T1 both buckets and T2 | ✓ | ✗ (T1 28+ and T2 fail) |
| **C4** identity to 1e-9 | ✓ | ✓ |
| **all four** | **no — fails C2 only** | no — fails C2 and C3 |

| | incumbent | frozen selection | comparator |
|---|---|---|---|
| MAE | 12.518 | **12.454** | 12.492 |
| RMSE | 15.79 | **15.68** | 15.71 |
| bias (mean error) | −0.010 | −0.325 | −0.310 |
| neutralised slope | 1.022 | 0.967 | 0.937 |
| paired gain, season 95% interval | — | [−0.075, **−0.048**] | [−0.063, +0.029] |
| paired gain, season-then-block 95% interval | — | [−0.129, **+0.001**] | [−0.114, +0.068] |
| seasons improved | — | **3 / 3** | 2 / 3 |
| binding SE / MDE@80% | — | 0.033 / 0.082 | 0.046 / 0.114 |

The Round 6 incumbent's MAE matches Round 5's published 12.518 to within 0.0005, although its
per-game predictions differ (mean absolute difference 0.17, maximum 1.38) because of the wider
Round 6 history. The agreement is a coincidence of the aggregate.

---

## 2. What held up out of sample

**The MAE gain is real in every held-out season.**

| season | n | incumbent MAE | selection Δ | comparator Δ |
|---|---|---|---|---|
| 2023 | 792 | 12.61 | **−0.075** | −0.044 |
| 2024 | 798 | 12.73 | **−0.070** | −0.063 |
| 2025 | 808 | 12.22 | **−0.048** | +0.029 |

The held-out gain of 0.065 is **72% of the 0.089 development gain**, which is a normal amount of
shrinkage out of sample. It clears the season-cluster bound, though with only three clusters. It
misses the season-then-block bound by **0.0012**. The predeclaration expected about 0.45 power,
so a miss of that size is consistent with a real effect.

**The override was the better choice on these seasons.** The selection beats the rule's pick by
**0.039** MAE and improves on it in all three seasons. On development evidence the ranking was the
other way (−0.015). The difference is not significant (block upper bound +0.013), so this
supports the override without proving it.

**The tail guard earned its place.**

| favourite outperformance | incumbent | selection | comparator |
|---|---|---|---|
| predicted 21–28 | +1.582 | −0.986 | −0.813 |
| predicted 28+ | +1.774 | **−0.510**, interval [−3.11, 1.73] | **−2.562**, interval [−5.12, **−0.21**] |

Out of sample, the unguarded comparator's 28+ reversal became **demonstrable**: its whole interval
lies below zero, so it fails T2. It also fails T1: its magnitude is 0.79 worse than the
incumbent's, against a 0.10 allowance. The guarded selection reverses too, but
by far less, and its interval contains zero. That is exactly the protection the override was
chosen for.

**The calibration defects stay closed.**

| slope | incumbent | selection |
|---|---|---|
| D3 at gp = 0 | 1.210 | **0.984** |
| D3 at gp = 1 | 1.027 | 0.923 |
| D2 at 0 cross-conference games | 1.251 | **0.998** |
| D2 at 1 cross-conference game | 1.024 | 0.924 |

The early-season compression that motivated Family E is removed out of sample. The one-game
buckets now overshoot slightly (about 0.92), and the pooled slope is 0.967. The conditional
incumbent was already closer to 1 (1.022) than it had been in development.

**D1 survives realignment.** Big Ten − MAC per season: **1.69 → 0.45** (2023), **2.04 → 1.25**
(2024), **2.81 → 1.30** (2025). The raw conference-residual spread is misleading in 2024–2025. It is
dominated by the two-team rump Pac-12 (23 team-rows; −5.9 in 2024 for every model) and by the
Independents. Restricting to conferences with at least 50 team-rows, the spread falls in every
season: 2.91 → 1.71, 2.26 → 1.45 and 2.81 → 2.02. **That 50-row cut was chosen after seeing the
result and is descriptive only, not a readout.** Pooled over all conferences, the spread moves from
3.358 to 2.892.

Promoted and transitional teams (D5): MAE 11.43 → 10.88.

---

## 3. What failed: bias, because home-field advantage rose after the freeze

C2 fails for both Phase 4 models, and the cause is specific.

| non-neutral residual the data wanted as HFA | 2023 | 2024 | 2025 |
|---|---|---|---|
| realised | 2.19 | 2.95 | 3.08 |

| frozen location | value |
|---|---|
| incumbent HFA | 3.12 |
| selection pooled `HFA'` | 2.43 |
| comparator `HFA'` | 2.36 |

The location term was estimated on 2017–2022, when realised home advantage ran lower, and it
correctly lowered HFA for that era. Home advantage then rose through 2024–2025, so the frozen
`HFA'` was too low and both models under-predict home margins:

| mean error | 2023 | 2024 | 2025 |
|---|---|---|---|
| incumbent | +0.54 | −0.02 | −0.54 |
| selection | +0.25 | −0.41 | **−0.81** |

The Phase 4 report warned that bias drifts by season and that a location fitted on past seasons
would carry that drift forward. That is what happened. The incumbent's older, higher HFA landed
nearer the 2023–2025 average by accident of timing, not better design. Neutral-site games were
outside the instrument's scope: −0.53 for the selection against −0.68 for the incumbent.

**Per the predeclaration, this failure does not re-open the design.** It is the frozen design's
out-of-sample result.

---

## 4. What this means for the next decision

- **On MAE, tails, early-season calibration and the conference defect, the frozen design
  replicated.** It improved in every held-out season, beat the rule's pick, avoided the tail
  reversal that became demonstrable in the unguarded model, and kept D1–D3 largely closed through
  realignment.
- **On bias it did not replicate**, because a static location cannot follow a moving home-field
  environment.
- **2023–2025 is no longer untouched.** Any bias remedy tried from here — for example an HFA
  re-estimated each season from a trailing window — would need its own predeclaration and a fresh
  development test. It could not use 2023–2025 as clean confirmation, because those seasons have
  now been seen. The remaining untouched evidence is prospective 2026, through immutable pregame
  archives.
- Promotion remains a separate decision and needs an explicit instruction. Nothing here performs
  it.

---

## 5. Integrity

- Hashes: the design, model code, protocol and development inputs were verified against
  `FROZEN_DESIGN_MANIFEST.csv` before scoring. The 2023–2025 plays and drives were acquired after
  the freeze commit through `cfbd_plays()` / `cfbd_drives()`, hashed in
  `acquisition_manifest_plays_conditional.csv`, and verified before scoring.
- Leakage: every preseason prior fit and base prior asserted a training year of 2022 or earlier.
  In-season evidence uses only games completed before each Monday cutoff. The frozen points
  mapping, scale, location and `τ` were applied without re-fitting. Unit tests reconstruct the
  selection's and comparator's predictions from the frozen parameters to 1e-9.
- Re-scoring is refused: the results file is read-only and the runner stops if it exists.
- Tests: `test_v7conditional` 8 groups, plus every existing suite. See the commit for the gate.
