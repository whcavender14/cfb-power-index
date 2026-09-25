# C2 Refinement Research: Stage 3, FCS Level Correction

**Date:** 2026-09-25. **Branch:** `c2-refinement`. **Plan:** `STAGE3_PLAN.md`, committed as `51c241f` before any arm was
run.
- The garbage-time rule is treatment A throughout.
- Every non-FCS component of C2 is frozen.
- Selection uses development 2017–19 and 2021–22 only. 2023–25 is descriptive.

**Scripts:** `scripts/c2r/lib_s3.R`, `s3a_level_history.R`, `s3b_arms.R`, `s3c_evaluate.R`, `s3d_posthoc.R`.
**Tables:** `docs/c2r/stage3/*.csv`.

> **Governance.**
> - Nothing here is pre-validated. The selected structure is a candidate for a future predeclared round.
> - The two post hoc attribution arms in §7 were added after results were seen. They explain the result and were not used
>   for selection.

## Summary

**Correcting the FCS group level fixes C2's FCS problem, and it also improves the FBS-vs-FBS model.**

The predeclared rule selects **L: two group-level parameters** inside C2's ridge.
- **Δ_FCS** is the non-FBS level. Only FBS-vs-FCS games inform it.
- **Δ_low** is the lower-division level relative to FCS. Only FCS-vs-lower-division games inform it.
- Each has a prior worth about 20 games, centred on last season's end-of-season level.
- Every individual FCS team keeps C2's own relative prior and shrinkage.

**Results on development:**
- **Whole system** (every game involving an FBS team): log-loss −0.0079 [−0.0124, −0.0035] vs frozen C2, as a
  leave-one-season-out score.
- **FBS vs FBS:** log-loss −0.0013 [−0.0028, +0.0001].
- **FBS vs FCS:** MAE 15.9 → 13.6; bias −10.2 → +1.5.
- **FCS vs FCS:** MAE 13.26 → 13.03.

2023–25 improves on every one of these as well.

### The eight questions

| # | Question | Answer |
|---|---|---|
| 1 | Is the FCS problem solved by correcting the group level? | **Yes.** L puts the FCS mean at about −28.5, against C2's −17.5. FBS-vs-FCS bias goes from −10.2 to +1.5 (development) and from −11.7 to +0.4 (2023–25). MAE falls by 2.3–3.2 points. Within-FCS ranking is preserved: Spearman correlation with C2's ranks is 0.98. |
| 2 | Is a roughly 10-point correction stable enough to use? | **The FCS level itself is stable. A fixed correction is usable but not the best choice.** The end-of-season FCS level shows no drift: slope −0.11 per season (SE 0.10), p = 0.66 against a constant; range −27.0 to −30.4. The fixed prior correction G(δ) chose δ = 10–14 across folds and works (whole-system log-loss −0.0064), but it is beaten by L. |
| 3 | Is a fixed correction inferior to a data-derived or rolling anchor? | **The fixed correction G is inferior to the in-model level L** (honest whole-system log-loss 0.48503 vs 0.48348). Within L, **the anchor's form does not matter**: fixed, expanding, rolling3 and last all fall within 0.0002. What matters is estimating the level in the model with a moderate prior: n0 = 20 beats a free level by 0.0038, because early-season estimates are noisy. |
| 4 | Do C2's relative FCS rankings add value over treating all FCS teams the same? | **Strongly yes.** The flat arm (every FCS team at the corrected level) has development FBS-vs-FCS MAE 15.2 vs 13.6 and FCS-vs-FCS MAE 16.7 vs 13.0. It also loses FBS-vs-FBS accuracy: +0.0015 log-loss vs L. |
| 5 | Does stronger FCS shrinkage help once the level is corrected? | **No.** k = 2 or 4 compresses FCS ratings (SD 11.3 → 8.8) and breaks FCS-vs-FCS calibration (slope 1.29–1.30, outside the predeclared 0.9–1.1). It worsens FCS-vs-FCS MAE (13.54 vs 13.03) and FBS-vs-FCS MAE (13.74 vs 13.60). Current shrinkage stays. |
| 6 | Does fixing FCS ratings improve FBS-vs-FBS predictions? | **Yes, modestly and consistently.** Development log-loss −0.0013 [−0.0028, +0.0001] and 2023–25 −0.0009 [−0.0021, +0.0003]. For scale, that is about a quarter of C2's whole development gain over the incumbent. The G12 fixed correction gives −0.0014 [−0.0027, −0.00015]. The mechanism: FBS teams that played FCS opponents lose the 0.7–1.4 points of credit that over-rated opponents gave them (§6). Ratings also become steadier. |
| 7 | What is the right treatment for an FCS team's first game? | **Its prior deviation plus the current solved group level,** which is what the system assigns a team with no games yet. Development MAE 14.7 vs 16.1 for C2; 2023–25 12.2 vs 15.5. Development first games still carry +2.7 bias (not in 2023–25: −0.1). See §5. |
| 8 | What specification works prospectively? | **L as specified.** It uses only information available before each cutoff: the anchor comes from earlier seasons' end-of-season fits, and the level updates from that season's FBS-vs-FCS games already played. No future results are needed. |

## 1. Arms, grids and the selection rule

All arms were run exactly as fixed in `STAGE3_PLAN.md`:
- C0, frozen C2;
- M(X), X ∈ {0, 4, 6, 8, 10, 12, 14}, the margin-only benchmark;
- G(δ), δ ∈ {4, …, 14}, the prior level shifted down by δ inside the model;
- L(anchor ∈ {fixed, expanding, rolling3, last} × n0 ∈ {0, 20});
- S(k ∈ {1, 2, 4}) on the selected L and the selected G;
- FLAT;
- SR-level (a sensitivity arm).

**Checks.** C0 reproduces frozen C2 exactly: all 6,266 predictions, the FCS ratings and the first-game priors (< 1e-9).

**Selection objective J.** Log-loss over every development game involving an FBS team:
- 3,868 FBS-vs-FBS games plus 561 FBS-vs-FCS games, including first games;
- each arm uses its own σ, fitted leave-one-season-out.

**Grid values** are chosen leave-one-season-out within each family, which gives an honest J.

| Family | Leave-one-season-out picks | Honest J | Δ vs C0 | FBS-vs-FBS log-loss Δ | FBS-vs-FCS bias / MAE | FCS-vs-FCS MAE, calibration slope | Eligible |
|---|---|---|---|---|---|---|---|
| C0 | | 0.49140 | | | −10.17 / 15.91 | 13.26, 1.00 | |
| M (benchmark) | X = 10, 8, 8, 12, 10 | 0.48595 | −0.0054 | 0 | −0.56 / 13.59 | unchanged | benchmark only |
| G | δ = 12, 10, 10, 14, 12 | 0.48503 | −0.0064 | −0.0013 | +0.55 / 13.65 | 13.17, 1.03 | yes |
| **L** | last_n20 in all five folds | **0.48348** | **−0.0079** | −0.0013 | +1.52 / 13.60 | 13.03, 1.06 | **yes: chosen** |
| S on L | k = 4, 2, 4, 2, 4 | 0.48338 | −0.0080 | −0.0013 | +1.52 / 13.70 | 13.54, **1.30** | no (calibration) |
| S on G | k = 4, 4, 4, 2, 4 | 0.48387 | −0.0075 | −0.0015 | +1.39 / 13.70 | 13.59, **1.28** | no (calibration) |

**Applying the rule.** The best eligible family is L. G is 0.0016 worse, beyond the 0.0005 tolerance that would have
favoured the simpler family. **L is chosen: L_last_n20.**

**L arms on development** (J / FBS-vs-FCS bias):

| Anchor | n0 = 0 (free) | n0 = 20 |
|---|---|---|
| fixed | 0.48737 / +0.38 | 0.48367 / +1.80 |
| expanding | 0.48736 / +0.37 | 0.48365 / +1.73 |
| rolling3 | 0.48735 / +0.34 | 0.48367 / +1.76 |
| last | 0.48730 / +0.41 | **0.48348** / +1.52 |

**The anchor choice is immaterial.** For a future predeclaration, "expanding" would be equally defensible and less
exposed to a single season's noise.

## 2. FBS vs FBS (the system test)

| | Log-loss | Brier | MAE | RMSE | Winners | Calibration slope | P4-vs-G5 under-prediction |
|---|---|---|---|---|---|---|---|
| Development, C0 | 0.52613 | 0.1768 | 12.83 | 16.21 | 72.5% | 0.999 | 4.57 |
| Development, G12 | 0.52476 | 0.1763 | 12.82 | 16.17 | 72.6% | 0.998 | 4.41 |
| **Development, L** | **0.52478** | 0.1764 | 12.82 | 16.17 | 72.7% | 0.998 | 4.42 |
| Development, FLAT | 0.52629 | 0.1771 | 12.90 | 16.29 | 72.8% | 0.976 | 4.63 |
| 2023–25, C0 | 0.53040 | 0.1800 | 12.27 | 15.44 | 72.0% | 0.985 | 0.48 |
| **2023–25, L** | **0.52952** | 0.1797 | 12.27 | 15.43 | 72.1% | 0.982 | 0.34 |

**Paired Δ vs C0,** with the R15 block bootstrap:

| | Development log-loss | 2023–25 log-loss |
|---|---|---|
| L | −0.00134 [−0.00285, +0.00006] | −0.00088 [−0.00208, +0.00030] |
| G12 | −0.00137 [−0.00270, −0.00015] | −0.00070 [−0.00171, +0.00029] |

**Whole system (all games), L:** development −0.0079 [−0.0124, −0.0035]; 2023–25 −0.0129 [−0.0200, −0.0066].

**By season (L vs C0 log-loss):**
- better in 2017, 2018, 2019, 2021 and all three 2023–25 seasons;
- slightly worse in 2022 (0.5629 vs 0.5627).

**By games played:**
- gains at 0, 2–3, 4–6 and 7+;
- a loss at gp = 1 in development (0.5140 vs 0.5101), not repeated in 2023–25.

**Rating stability.** The mean absolute week-to-week FBS change is 0.943 vs 0.968 (development) and 0.797 vs 0.827
(2023–25).

## 3. FBS vs FCS

| | n | Bias | MAE | RMSE | Winners | Log-loss | Predicted-margin SD |
|---|---|---|---|---|---|---|---|
| Development, C0 | 561 | −10.17 | 15.91 | 19.71 | 92.9% | 0.252 | 12.1 |
| Development, M10 | 561 | −0.17 | 13.44 | 16.88 | 93.4% | 0.201 | 12.1 |
| Development, G12 | 561 | +0.90 | 13.57 | 16.89 | 93.4% | 0.204 | 12.0 |
| **Development, L** | 561 | **+1.52** | **13.60** | **16.86** | 93.4% | **0.199** | | 12.1 |
| Development, FLAT | 561 | +1.08 | 15.22 | 18.88 | 93.1% | 0.218 | 10.4 |
| 2023–25, C0 | 365 | −11.73 | 15.53 | 19.33 | 94.0% | 0.208 | 12.5 |
| 2023–25, M10 | 365 | −1.73 | 12.37 | 15.46 | 96.4% | 0.123 | 12.5 |
| **2023–25, L** | 365 | **+0.38** | **12.31** | **15.30** | 96.2% | **0.116** | | 12.5 |

Brier scores are in `stage3/s3_summary_all_arms.csv`.

**Bias by season:**

| | 2017 | 2018 | 2019 | 2021 | 2022 | 2023 | 2024 | 2025 |
|---|---|---|---|---|---|---|---|---|
| C0 | −8.1 | −13.6 | −10.0 | −7.0 | −12.0 | −10.0 | −12.0 | −13.1 |
| L | +2.9 | +0.6 | +2.5 | +2.5 | −0.8 | +1.9 | −0.1 | −0.6 |

**Bias by FCS strength** (C0's rating quintile, development, Q1 weakest → Q5 strongest):
- C0: −10.3 / −12.2 / −9.6 / −9.6 / −9.2;
- L: +1.0 / −1.2 / +2.0 / +2.6 / +3.1.

**Bias by FBS strength** (development):
- C0: −12.2 → −7.7 from weakest to strongest;
- L: −0.4 → +4.3.

The FBS-strength gradient is the Stage 1 finding that actual margins respond less to FBS strength than predicted
(blowout compression). The level fix does not change it.

## 4. FCS vs FCS (within-FCS ordering)

| | Development MAE / RMSE / bias / calibration slope / Spearman | 2023–25 |
|---|---|---|
| C0 | 13.26 / 16.87 / +0.73 / 1.00 / 0.583 | 12.74 / 16.26 / −0.07 / 1.02 / 0.591 |
| G12 | 13.17 / 16.73 / +0.79 / 1.03 / 0.593 | 12.62 / 16.12 / −0.01 / 1.05 / 0.600 |
| **L** | **13.03 / 16.49** / +0.90 / 1.06 / **0.608** | **12.44 / 15.90** / +0.13 / 1.07 / **0.614** |
| S4 on L | 13.54 / 17.11 / +0.74 / 1.30 / 0.583 | 12.81 / 16.36 / −0.03 / 1.30 / 0.603 |
| FLAT | 16.68 / 21.08 / +0.23 / 1.07 / 0.114 | 15.95 / 20.45 / −0.74 / 0.03 / 0.517 |

**The level fix also improves within-FCS prediction.**
- **Likely reason:** in C0, the unexplained margin on FBS-vs-FCS games is pushed onto the particular FCS teams that played
  FBS teams, which distorts their standing within FCS. With a level parameter, that evidence goes to the level instead.
- **The lower-division level column helps too** (§7).

## 5. First games

| | Development first game (226): bias / MAE | Development later (335) | 2023–25 first game (153) | 2023–25 later (212) |
|---|---|---|---|---|
| C0 (C2 prior mean) | −9.4 / 16.1 | −10.7 / 15.8 | −12.3 / 15.5 | −11.3 / 15.6 |
| M10 | +0.6 / 14.4 | −0.7 / 12.8 | −2.3 / 12.2 | −1.3 / 12.5 |
| G12 | +2.6 / 14.7 | −0.3 / 12.8 | −0.3 / 12.1 | −0.9 / 12.5 |
| **L** | **+2.7 / 14.7** | **+0.7 / 12.8** | **−0.1 / 12.2** | **+0.8 / 12.4** |

**The rule** is the team's own prior deviation, ρ·(last season − its division's mean), plus the current solved group
level. At the season's first cutoff, before any FBS-vs-FCS game, that level is the anchor.

**A residual in development first games.** They are over-predicted by about 2.7 points in every corrected arm (not in
2023–25).
- These are week 1–3 games where FBS ratings are pure preseason prior.
- The pattern matches Stage 1's flatter-than-1 response to FBS strength.
- It is left as a known residual. It belongs with Stage 4 (preseason prior), not with the FCS level.

## 6. Rating effects (each season's final cutoff, development; 2023–25 in `stage3/s3_rating_effects.csv`)

| | C0 | G12 | L | S4 on L | FLAT |
|---|---|---|---|---|---|
| FCS-division mean rating | −19.3 | −26.8 | **−28.6** | −28.3 | −28.4 |
| FCS rating SD | 10.8 | 10.8 | 11.3 | 8.8 | 1.1 |
| Spearman correlation of FCS ranks vs C0 | 1 | 0.996 | 0.983 | 0.970 | 0.917 |
| Lower-division mean rating | | −39.6 | −60.6 | −59.2 | −57.1 |
| SD of FBS rating change | | 0.27 | 0.35 | 0.39 | 0.80 |
| FBS change, teams with 0 / 1 / 2+ FCS opponents | | +0.52 / −0.09 / −0.58 | **+0.65 / −0.11 / −0.70** | +0.64 / −0.11 / −0.63 | +0.62 / −0.11 / −0.28 |
| Strength-of-schedule change, 0 / 1+ FCS opponents | | +0.18 / −0.59 | +0.24 / −0.72 | +0.23 / −0.72 | +0.20 / −0.72 |
| Spearman correlation of SOS ranks vs C0 | | 0.998 | 0.996 | 0.995 | 0.981 |

**Simulation input: predicted FBS win probability against FCS opponents.**

| | Development | 2023–25 |
|---|---|---|
| Actual FBS win rate | 93.1% | 96.2% |
| C0 | 83.2% | 83.7% |
| **L** | **94.0%** | **94.6%** |

- **C2 had been badly under-predicting FBS wins over FCS teams,** which matters for season simulations.
- **L removes the phantom credit FBS teams got for beating over-rated FCS teams.** A team with one FCS opponent drops
  about 0.8 point relative to a team with none.
- **The in-season FCS level under L** is about −27.5 at cutoff 3 and −28.7 from cutoff 5 on. It is stable within the
  season.

## 7. Post hoc attribution (not used for selection)

| | Development J | FBS-vs-FBS log-loss | FBS-vs-FCS bias | FCS-vs-FCS MAE |
|---|---|---|---|---|
| L (selected) | 0.48348 | 0.52478 | +1.52 | 13.03 |
| L without division-specific prior pools | 0.48346 | 0.52474 | +1.52 | 13.05 |
| L without the lower-division level column | 0.48349 | 0.52478 | +1.25 | 13.10 |

- **The division-specific pools are redundant** once group levels are estimated. The level columns absorb the pool
  difference. **A simpler L keeps C2's pooled μ and adds the two level columns.**
- **The lower-division column is what keeps D-II, D-III and unknown teams from contaminating FCS.** It adds a little on
  FCS-vs-FCS (13.03 vs 13.10).
- **The SR-level sensitivity arm** (FBS-vs-FCS SR rows get their own level) gives J 0.4836, bias +0.99 and an FCS mean of
  −27.4. The β mismatch from Stage 2 shifts the level by about 1 point and does not change the conclusion.

## 8. The FCS level over time

End-of-season FCS level, from fits with both group levels free (2020 excluded: 22 FCS teams):

| 2013 | 2014 | 2015 | 2016 | 2017 | 2018 | 2019 | 2021 | 2022 | 2023 | 2024 | 2025 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| −27.5 | −29.0 | −30.3 | −28.2 | −27.5 | −29.7 | −28.4 | −27.0 | −29.6 | −28.3 | −30.4 | −30.4 |

Each value has an SE of about 1.3–1.5.

- **Is the movement statistically meaningful? No.**
  - Weighted slope −0.11 per season (SE 0.10, p = 0.27).
  - Heterogeneity against a constant: Q = 8.6 on 11 df, p = 0.66. The season-to-season variation is what the
    measurement error alone predicts.
  - Period means: 2013–16 −28.8, 2017–22 −28.5, 2023–25 −29.7.
- **Smooth or season-specific?** Neither beyond noise.
- **Composition:**
  - A fixed panel of 114 FCS teams present every season tracks the full FCS mean within 0.8 point every year.
  - 0–3 teams enter FCS per season, mostly weak at entry (about −31 to −44). 0–3 leave for FBS, often strong ones
    (for example, one at +2.1 in 2021).
  - FBS programs schedule FCS teams 0.1–3.4 points stronger than the FCS average.
  - None of these creates a trend.
- **Stage 1's −25 → −33 "drift"** was in the level implied inside individual FBS-vs-FCS games. That measure also carries
  early-season FBS rating error and scheduling selection. The end-of-season FCS level itself is flat.
- **Fixed vs season-specific vs rolling anchors:** indistinguishable (§1). **A fixed long-run level of about −28.5 is
  adequate. A rolling or expanding estimate costs nothing and would catch a real shift if one appeared.**

## 9. The selected structure and a note for a future predeclaration

- **In-model group levels**, `FCS team power = group level + team deviation`:
  - **Δ_FCS:** informed by FBS-vs-FCS games; prior at the historical FCS level with about 20 games' weight.
  - **Δ_low:** informed by FCS-vs-lower-division games; prior at the historical gap.
- **Team deviations** keep C2's relative prior (ρ, λ_FCS) and shrinkage. Stronger shrinkage hurt.
- **First games:** prior deviation plus the current level.
- **Everything else in C2 is unchanged.**
- **Simplifications the evidence supports** (for a future predeclaration, not applied here):
  - use C2's pooled μ (division pools are redundant);
  - use an expanding-mean anchor (immaterial vs last).
- **Residuals left explicitly open:**
  - development first-game over-prediction (+2.7);
  - FBS-strength compression in mismatches;
  - conference-level compression within FCS (Stage 1).
  - The first two point to the preseason-prior and blowout questions, not to the FCS level.
