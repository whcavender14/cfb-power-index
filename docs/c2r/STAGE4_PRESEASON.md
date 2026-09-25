# C2 Refinement Research: Stage 4, Preseason Calibration and Decay

**Date:** 2026-09-25. **Branch:** `c2-refinement`.
- **Plan:** `STAGE4_PLAN.md`, committed as `47739dd` after the 4A/4B diagnosis and before any candidate was scored.
- **Baseline C2L** = Stage 3 `L_last_n20`. Only the FBS preseason prior varies.
- **Selection** uses development 2017–19 and 2021–22. 2023–25 is descriptive.
- **Scripts:** `scripts/c2r/s4a_diagnose.R`, `s4b_arms.R`, `s4c_evaluate.R`, `s4d_posthoc.R`. **Tables:**
  `docs/c2r/stage4/`.

> Nothing is pre-validated. The post hoc arms in §6 were added after results were seen. They explain the result and were
> not used to select.

## Summary

**C2L's preseason treatment is already at or near the optimum. The predeclared rule keeps it unchanged.**
- **Starting ratings.** gp = 0 predictions are somewhat compressed in 2017–22 (calibration slope 1.28 in pure-prior
  games), not too extreme. Correcting that with any scale, global, offense-only or gp = 0-only, does not replicate in
  2023–25.
- **Decay.** Every faster decay is worse in essentially every games-played bucket and every subgroup. A flexible,
  bucket-by-bucket probe finds the current curve at the optimum.
- **Preseason value.** Preseason information adds value at every stage. It is large through three games and small but
  still positive after seven.

**The proposed C2L+ is therefore Stage 3's C2L with the current preseason prior.**
- Development FBS-vs-FBS log-loss is 0.52478, against frozen C2's 0.52613 and the incumbent's 0.53207.
- 2023–25 is 0.52952, against 0.53040 and 0.53616.

## The ten deliverables

| # | Deliverable | Answer |
|---|---|---|
| 1 | Current effective preseason influence | Share of a team's own rating set by its preseason prior after **1 / 2 / 3 / 4 / 5 / 6+ games: 78% / 63% / 53% / 45% / 39% / 24%** (development). 2023–25, with λ0 = 4: 80 / 67 / 56 / 48 / 42 / 26%. Roughly λ/(λ + games): the prior's precision is constant, and each game adds one unit of data. |
| 2 | Are gp = 0 ratings correctly scaled? | **Slightly compressed, not too extreme.** Pure-prior games: slope 1.28 (development, n = 228) and 1.09 (2023–25, n = 132). The compression is mostly on the offense side: coefficient 1.50 ± 0.23 vs defense 1.06 ± 0.24. Large favourites (28+ points) are about right: ratio 1.04 and 1.11. |
| 3 | Optimal starting scale | **1.00 (unchanged).** The best global scale (1.2) gains only 0.00017 honest development log-loss, inside the 0.0003 simplicity tolerance. It worsens 2023–25 (+0.0010) and over-spreads later weeks (slope 0.94). A gp = 0-only scale helps development gp = 0 but hurts 2023–25 gp = 0 (post hoc, §6). |
| 4 | Optimal decay shape and half-life | **Current: constant prior precision, no extra decay.** Half-lives of 1–5 games are all worse (development 0.5273–0.5397 vs 0.5248). The flexible probe shows weakening the prior at any bucket hurts. Strengthening it ×2 is neutral, and ×4 hurts. |
| 5 | When does preseason information stop adding value? | Log-loss gain over a no-prior model: gp 0 **0.180**, gp 1 **0.088**, gp 2 **0.073**, gp 3 **0.031**, gp 4–6 **0.021**, gp 7+ **0.003** (development; 2023–25 is similar). It fades after about 6 games but never turns negative. |
| 6 | Performance by games played | §3. |
| 7 | Overall C2L improvement | Stage 4 adds nothing, because the rule keeps C2L. C2L vs frozen C2: −0.0013 (development), −0.0009 (2023–25). C2L vs the incumbent: **−0.0073 [−0.0128, −0.0021]** (development) and −0.0066 [−0.0139, +0.0006] (2023–25). |
| 8 | Does the first-game FBS-vs-FCS bias improve? | **No, and it is not a preseason-scale problem.** Across all Stage 4 arms, development first games stay at +2.1 to +2.9 (no preseason prior: +4.6). 2023–25 is about 0 in every arm. It looks period-specific: about 2 SE with n = 226. |
| 9 | Development and 2023–25 results | §2 and §3. |
| 10 | Proposed C2L+ | §7. |

## 1. How the preseason prior works (4A)

**Prior mean (FBS team, each side).**
- The prior mean is **a × C1 prior**, centred.
- a is the C1 scale, an LAD fit of prior-only predictions on earlier seasons: 1.05, 1.06, 1.12, 1.17, 1.14 for
  2017–2022, and 1.13 for 2023–25.
- **The mean never shrinks or decays during the season.** Only the data around it grow.

**Precision.**
- λ_i = λ0 · exp(−b (u_i − ū)) per side, where u is the turnover index.
- λ0 = 3 in 2017–18 and 4 from 2019.
- b_off is 0.12–0.30, so higher turnover means a weaker offense prior. b_def is −0.03 to −0.42.
- λ ranges from about 2.7 to 5.7 (p10–p90). Precision is **constant through the season**.

**Data per game.**
- Each game adds a points row of weight 1 to the team's offense and defense.
- It also adds an SR row at ω = 0.25 (0.5 in 2017).
- Offense and defense end up with the same effective weights: 0.79 vs 0.79 at gp 1.

**Effective influence,** exact from the solved system. This is the response of a team's own rating to a unit change in
its own prior (development):

| Games played | 0 | 1 | 2 | 3 | 4 | 5 | 6+ |
|---|---|---|---|---|---|---|---|
| Own-prior share of the rating | 99% | 78% | 63% | 53% | 45% | 39% | 24% (p10–p90: 16–33%) |
| Share of rating variance from all FBS priors (own and opponents') | 100% | 65% | 50% | 38% | 32% | 29% | 21% |

**In plain terms:** after three games, about half of a team's C2L rating is still its preseason rating. After six, about
a quarter.

## 2. gp = 0 calibration (4B)

Games are classed by **all-games gp** (including FCS games), which is what drives C2's solve. R15's frame gp matches it
only 19% of the time.

| Development | n | Log-loss | Brier | MAE | RMSE | Winners | Bias | Calibration slope | Predicted SD | P4-vs-G5 |
|---|---|---|---|---|---|---|---|---|---|---|
| C2L, both teams gp = 0 (pure prior) | 228 | 0.439 | 0.143 | 13.14 | 16.50 | 76.8% | −2.78 | **1.28** | 12.9 | +7.6 |
| C2L, either team gp = 0 | 289 | 0.467 | 0.155 | 12.79 | 16.13 | 74.4% | −2.18 | 1.23 | 13.2 | +6.5 |
| Incumbent, pure prior | 228 | 0.443 | 0.143 | 13.61 | 17.13 | 79.4% | −3.00 | 1.29 | 12.4 | +8.5 |

| 2023–25 | n | Log-loss | Brier | MAE | RMSE | Winners | Bias | Calibration slope | Predicted SD | P4-vs-G5 |
|---|---|---|---|---|---|---|---|---|---|---|
| C2L, pure prior | 132 | 0.447 | 0.148 | 12.76 | 15.99 | 77.3% | −0.67 | 1.09 | 14.2 | +2.6 |
| C2L, either team gp = 0 | 170 | 0.462 | 0.155 | 12.86 | 16.01 | 75.3% | −0.82 | 1.11 | 14.1 | +3.8 |

**By predicted margin** (favourite-oriented, net of home field; actual / predicted):

| Pure-prior games | 0–7 | 7–14 | 14–21 | 21–28 | 28+ |
|---|---|---|---|---|---|
| Development | 1.92 | 1.49 | 1.28 | 1.50 | 1.04 |
| 2023–25 | 2.06 | 1.12 | 0.86 | 1.21 | 1.11 |

At gp 4+ these ratios fall to 0.8–1.0.

**Large preseason differences are not producing margins that are too extreme** in FBS-vs-FBS games. The "strong FBS teams
beat FCS teams by less than predicted" pattern from Stage 3 is a mismatch (blowout) effect, not preseason scaling.

## 3. Candidates, selection and results by games played

**Leave-one-season-out selection** (development FBS-vs-FBS log-loss):

| Family | Picks by held-out season | Honest log-loss | Chosen on all five | Worst bucket vs C2L | Whole-system J vs C2L |
|---|---|---|---|---|---|
| C2L | | 0.524782 | | | |
| S (global scale 0.90–1.30) | 1.1, 1.1, 1.2, 1.2, 1.2 | 0.524613 | S1.20 | +0.0011 | −0.0005 |
| O (offense scale 1.1–1.4) | 1.2, 1.2, 1.3, 1.4, 1.3 | 0.524654 | O1.30 | +0.0018 | −0.0004 |
| D (half-life 1–5, at scale 1.0) | C2L in all five folds | 0.524782 | C2L | | |

**Rule outcome:** S and O are within 0.0003 of C2L, so the simpler C2L is kept. D chooses no extra decay.

**Log-loss by games played** (min of the two teams, all-games gp):

| gp | Development: C0 (frozen C2) | C2L | S1.20 | D3 | D5 | Incumbent | No prior | 2023–25: C0 | C2L | S1.20 | D5 | Incumbent | No prior |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 0.4723 | **0.4665** | 0.4616 | 0.4749 | 0.4718 | 0.4749 | 0.6463 | 0.4609 | 0.4620 | 0.4601 | 0.4649 | 0.5125 | 0.6538 |
| 1 | 0.4974 | **0.4942** | 0.4934 | 0.4984 | 0.4965 | 0.5112 | 0.5818 | 0.4732 | 0.4708 | 0.4750 | 0.4694 | 0.4661 | 0.5574 |
| 2 | 0.5050 | 0.5067 | 0.5044 | 0.5146 | 0.5109 | 0.5076 | 0.5800 | 0.4483 | 0.4500 | 0.4522 | 0.4516 | 0.4623 | 0.5101 |
| 3 | 0.4981 | **0.4946** | 0.4950 | 0.5011 | 0.4976 | 0.4994 | 0.5261 | 0.4989 | 0.4967 | 0.4967 | 0.4977 | 0.4924 | 0.5364 |
| 0–3 | 0.4933 | **0.4906** | 0.4888 | 0.4974 | 0.4943 | 0.4981 | 0.5822 | 0.4704 | **0.4700** | 0.4711 | 0.4711 | 0.4835 | 0.5629 |
| 4–6 | 0.5567 | 0.5560 | 0.5546 | 0.5666 | 0.5619 | 0.5653 | 0.5767 | 0.5608 | **0.5596** | 0.5603 | 0.5637 | 0.5693 | 0.5734 |
| 7+ | 0.5314 | 0.5306 | 0.5317 | 0.5316 | 0.5304 | 0.5367 | 0.5332 | 0.5516 | **0.5507** | 0.5518 | 0.5514 | 0.5514 | 0.5546 |
| **All** | 0.5261 | **0.5248** | 0.5244 | 0.5299 | 0.5273 | 0.5321 | 0.5586 | 0.5304 | **0.5295** | 0.5305 | 0.5312 | 0.5362 | 0.5616 |

**Calibration slope, C2L by gp** (0 / 1 / 2 / 3 / 4–6 / 7+ / all):
- development: 1.23 / 1.20 / 1.10 / 0.97 / 0.86 / 0.99 / 1.00;
- 2023–25: 1.11 / 1.03 / 1.00 / 0.96 / 0.90 / 0.98 / 0.98.
- **S1.20 over-spreads overall:** 0.94 / 0.91.

MAE, Brier, RMSE, bias and predicted SD for every arm and bucket are in `stage4/s4_by_gp_all.csv`.

**Flexible probe** (change in development log-loss when one bucket's prior precision is multiplied):

| gp bucket | × 0.25 | × 0.5 | × 2 | × 4 |
|---|---|---|---|---|
| 1 | +0.0023 | +0.0005 | +0.0002 | +0.0006 |
| 2 | +0.0035 | +0.0012 | −0.0001 | +0.0004 |
| 3 | +0.0017 | +0.0005 | +0.0003 | +0.0012 |
| 4 | +0.0022 | +0.0009 | −0.0001 | +0.0005 |
| 5+ | +0.0036 | +0.0014 | +0.0018 | +0.0086 |

The minimum is at ×1 (the current setting) in every bucket, within ±0.0001. An exponential decay cannot improve on a
curve whose optimum is "no extra decay".

## 4. Overall absolute metrics (FBS vs FBS)

| | Log-loss | Brier | MAE | RMSE | Winners | Calibration slope | P4-vs-G5 | Whole-system J |
|---|---|---|---|---|---|---|---|---|
| Development, incumbent | 0.53207 | 0.17963 | 12.97 | 16.35 | 72.2% | 1.075 | 5.77 | |
| Development, frozen C2 | 0.52613 | 0.17681 | 12.83 | 16.21 | 72.5% | 0.999 | 4.57 | 0.49140 |
| **Development, C2L = C2L+** | **0.52478** | **0.17636** | **12.82** | **16.17** | 72.6% | 0.998 | 4.42 | **0.48348** |
| 2023–25, incumbent | 0.53616 | 0.18202 | 12.52 | 15.79 | 71.9% | 1.015 | 3.44 | |
| 2023–25, frozen C2 | 0.53040 | 0.18003 | 12.27 | 15.44 | 72.0% | 0.985 | 0.48 | 0.48782 |
| **2023–25, C2L = C2L+** | **0.52952** | **0.17972** | 12.27 | **15.43** | 72.1% | 0.982 | 0.34 | **0.47487** |

**Deltas** (block bootstrap, 95% CI):

| C2L vs | Development log-loss | Development MAE | 2023–25 log-loss | 2023–25 MAE |
|---|---|---|---|---|
| Frozen C2 | −0.0013 [−0.0028, +0.0001] | −0.018 [−0.043, +0.007] | −0.0009 [−0.0021, +0.0003] | +0.002 [−0.023, +0.028] |
| Incumbent | −0.0073 [−0.0128, −0.0021] | −0.156 [−0.284, −0.035] | −0.0066 [−0.0139, +0.0006] | −0.250 [−0.399, −0.106] |

## 5. Subgroups and the Stage 3 interaction

**Descriptive subgroups** (development log-loss, games with min gp ≤ 3):

| Subgroup | n | C2L | No prior | D1 | D3 | D5 |
|---|---|---|---|---|---|---|
| P4-P4 | 358 | **0.552** | 0.611 | 0.578 | 0.558 | 0.555 |
| G5-G5 | 291 | **0.570** | 0.629 | 0.594 | 0.575 | 0.572 |
| P4-G5 | 390 | **0.397** | 0.523 | 0.419 | 0.405 | 0.402 |
| With an independent | 127 | **0.422** | 0.577 | 0.453 | 0.433 | 0.429 |
| A new head coach | 367 | **0.490** | 0.572 | 0.508 | 0.494 | 0.492 |
| Both coaches returning | 799 | **0.491** | 0.587 | 0.519 | 0.499 | 0.496 |
| High continuity | 560 | **0.510** | 0.599 | 0.535 | 0.517 | 0.514 |
| Low continuity | 581 | **0.472** | 0.569 | 0.500 | 0.481 | 0.477 |
| Large preseason favourite (≥ 21) | 108 | **0.171** | 0.401 | 0.186 | 0.176 | 0.174 |
| FBS-vs-FCS first games | 226 | 0.250 | 0.342 | 0.241 | 0.241 | 0.243 |

- **The current decay is best in every FBS-vs-FBS subgroup.** That includes new-coach and low-continuity teams, where
  faster decay might have been expected to help.
- **The only exception is FBS-vs-FCS first games,** which slightly favour faster decay. That is not a basis for selection.
- **No subgroup-specific rule is warranted.**

**Interaction with Stage 3:**
- Because C2L+ = C2L, **nothing from Stage 3 is undone.** The same holds for every Stage 4 arm tested:
  - FCS level at cutoffs 2–5 stays −25.5 / −27.5 / −28.3 / −28.8;
  - the FBS rating change vs frozen C2 is unchanged (0 FCS opponents +0.65; 1: −0.11; 2: −0.70);
  - first-game FBS-vs-FCS bias moves only within +2.1 to +2.9 (development) and −0.1 to −0.3 (2023–25).

## 6. Post hoc diagnostics (not used to select)

| | Development: all | Development: gp 0 | 2023–25: all | 2023–25: gp 0 |
|---|---|---|---|---|
| C2L | 0.5248 | 0.4665 | 0.5295 | 0.4620 |
| Scale 1.2 + half-life 5 | 0.5258 | 0.4641 | 0.5308 | 0.4607 |
| Scale 1.2 + half-life 3 | 0.5281 | 0.4660 | 0.5324 | 0.4616 |
| Scale only while gp = 0: 1.1 / 1.2 / 1.3 | 0.5245 / 0.5243 / 0.5242 | 0.4628 / 0.4607 / 0.4601 | 0.5296 / 0.5298 / 0.5301 | 0.4626 / 0.4649 / 0.4687 |

- **Combining a larger scale with faster decay does not help.**
- **A gp = 0-only scale** is the cleanest "starting calibration" fix. It helps development gp = 0 but reverses in 2023–25,
  so the development compression is not a stable property.

## 7. Proposed C2L+ specification

**C2L+ = frozen C2 + Stage 3 FCS level model + the current preseason prior.**
- **Garbage time:** treatment A (Stage 2).
- **FCS:** two in-model group levels (Stage 3).
  - Δ_FCS is informed by FBS-vs-FCS games; Δ_low by FCS-vs-lower-division games.
  - Each has a prior worth about 20 games at the prior-season end-of-season level.
  - Stage 3 found simplifications with no measured cost: C2's pooled μ and an expanding-mean anchor.
  - Team deviations keep C2's ρ and λ_FCS. A first-game FCS team gets its prior deviation plus the current level.
- **FBS preseason prior:** C1 as frozen.
  - Mean = a × C1 prior (no extra scale).
  - Turnover-scaled precision λ_i, constant through the season (no extra decay).
- **Everything else is unchanged:** SR rows, ω, β, fumble luck, home field.
- **This is a candidate for a future predeclared round.** None of these results are pre-validated.
- **Open residuals, all descriptive:**
  - gp = 0 compression in 2017–22 that does not replicate;
  - development first-game FBS-vs-FCS over-prediction (+2.7), which does not replicate;
  - blowout compression in FBS-vs-FCS mismatches;
  - conference compression within FCS.
