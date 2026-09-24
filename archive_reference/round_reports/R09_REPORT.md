# Round 9 report — opponent-adjusted efficiency + talent prior + score-margin ensemble

**Verdict: NOT PROMOTED.** 9 of 18 gate rows fail. The central question was
whether opponent-adjusted efficiency adds predictive value to the incumbent.
The answer is no, measured directly. Conditional on the incumbent, efficiency's
partial correlation with the outcome is 0.025–0.051 and its incremental R² is
0.0004–0.0016 in every one of the seven target fits, even in-sample and
unpenalized. The predeclared zeroing rule set its weight to 0 every time. The
final model is therefore a lightly recalibrated incumbent. It is +0.001 MAE
(development) and +0.012 MAE (conditional) relative to the incumbent, i.e.
indistinguishable or slightly worse.

- Predeclaration SHA-256 `6925b2e69ba0aaf91ec515b1b4e70d87b5cf1d6e3641c79a4a3bdaf6ec1465d8`,
  hashed before any Round 9 code. No amendments.
- Round 8 was closed first as NOT PROMOTED (final), with a post-results
  Amendment 01 (`d0bb03a5…` → `a5df5fc4…`).

Part B of the predeclaration records why Round 9 was restated before hashing:
Round 7/8 efficiency was already opponent-adjusted, the incumbent's prior
already uses talent, and the incumbent already learns HFA.

## Headline (pooled MAE; Δ = model − incumbent, negative is better)

| Model | Dev MAE | Dev Δ [95% season bootstrap] | Cond MAE | Cond Δ [95% season bootstrap] |
|---|---|---|---|---|
| 1. Incumbent (`v5_EB_features`) | 12.970 | — | 12.518 | — |
| 2. Opponent-adjusted efficiency alone | 14.419 | +1.450 [+1.148, +1.751] | 13.901 | +1.384 [+1.043, +1.562] |
| 3. Incumbent + efficiency, no HFA | 13.155 | +0.185 [+0.123, +0.248] | 12.699 | +0.181 [+0.142, +0.240] |
| 4. Incumbent + efficiency + learned HFA | 12.970 | +0.000 [−0.007, +0.008] | 12.517 | −0.001 [−0.006, +0.002] |
| **5. Final eligible model** | 12.970 | +0.001 [−0.006, +0.008] | 12.530 | +0.012 [−0.013, +0.055] |
| Round 8 stage-3 challenger (reference) | 14.67¹ | +1.729 | 14.28 | +1.766 |

- Development = 2018, 2019, 2021, 2022 (3,092 games).
- Conditional = 2023–2025 (2,398 games).
- Pairing with the incumbent is 100% in every season.
- ¹ The Round 8 row covers only 2019/2021/2022, because Round 8 never scored 2018.

The final model is w_s = 1, w_e = 0, with fixed +3.0 HFA. In the conditional
seasons it also retains the talent terms selected by the 2023 lock. Ablation 4
applies no zeroing rules, yet the ridge toward the incumbent still leaves
w_e ≤ 0.0025. The in-sample incremental-R² ceiling of ≤ 0.0016 bounds any
achievable gain to about 0.01 MAE points at any ridge setting.

## Why efficiency adds nothing

| Target | Partial corr | Incremental R² | E coef (OLS) | one-sided p | corr(S, E) | VIF | Zeroed by |
|---|---|---|---|---|---|---|---|
| 2018 | 0.025 | 0.0004 | 0.074 | 0.24 | 0.74 | 2.2 | partial corr, ΔR², p |
| 2019 | 0.031 | 0.0006 | 0.090 | 0.11 | 0.76 | 2.3 | partial corr, ΔR², p |
| 2021 | 0.032 | 0.0006 | 0.090 | 0.064 | 0.77 | 2.5 | partial corr, ΔR², p |
| 2022 | 0.029 | 0.0005 | 0.082 | 0.057 | 0.77 | 2.5 | partial corr, ΔR², p |
| 2023 | 0.037 | 0.0008 | 0.105 | 0.010 | 0.76 | 2.4 | partial corr, ΔR² |
| 2024 | 0.037 | 0.0008 | 0.105 | 0.005 | 0.75 | 2.3 | partial corr, ΔR² |
| 2025 | 0.051 | 0.0016 | 0.143 | 0.0001 | 0.74 | 2.2 | partial corr, ΔR² |

On holdouts, the residuals of the incumbent and of efficiency-alone correlate
at **0.90** (development) and **0.87** (conditional). The brief treats values
below 0.15 as leaving room for an ensemble. The two models miss the same
games. As training data accumulate, efficiency becomes statistically
detectable (p < 0.05 from 2023). It remains practically negligible: its best
in-sample contribution is 0.16% of margin variance.

## The "~0.60 correlation ceiling" is not efficiency-specific

Round 8 attributed a ~0.60 predicted/actual correlation to the efficiency
challenger and treated its SD ratio of 0.46 as a defect. The post-freeze
market benchmark shows otherwise (2023–2025, closing multi-book medians, used
only after hash verification):

| Forecast | corr(pred, actual) | Calibration slope | SD ratio | MAE |
|---|---|---|---|---|
| Market closing line | 0.658 | 1.016 | 0.648 | 12.00 |
| Incumbent | 0.622 | 1.014 | 0.614 | 12.52 |
| Round 9 final | 0.621 | 1.009 | 0.615 | 12.53 |

For a calibrated forecast (slope ≈ 1), the SD ratio *equals* the correlation.
The predeclared pair of gates (slope in [0.90, 1.10], SD ratio in
[0.85, 1.15]) therefore requires a correlation of at least 0.765. Neither the
closing market (0.66) nor the incumbent meets it. **The SD-ratio gate cannot
be passed by any well-calibrated college-football margin forecast.** Round 8's
"dispersion defect" was mostly correct shrinkage, and this explains why
Round 8's variance-matching fix raised MAE. The incumbent trails the closing
line by 0.52 MAE points.

## Opponent-adjustment validation (hypothesis 1, restated)

These are efficiency-only forecasts on the development split, all at the
fixed backbone settings (half-life 56, full conversion):

| Arm | Dev MAE | Cond MAE |
|---|---|---|
| Raw (unshrunk decay-weighted means) | 15.057 | 14.430 |
| League-average-adjusted (ridge, no opponent terms, λ = 1) | 14.626 | 14.006 |
| **Round 9 opponent-adjusted (joint + play-level home term, λ = 1/1)** | 14.432 | 13.923 |
| Round 7/8 reference (joint, no home term, λ = 1) | **14.262** | **13.767** |

- Opponent adjustment clearly beats both baselines: 0.20 points better than
  league-average and 0.63 better than raw. That gate passes.
- The Round 9 addition is worse than the Round 7/8 solve it extends. The
  unpenalized play-level home term is estimated at η_EPA ≈ 0.057–0.072 per
  play per side. That implies roughly 8 points of home edge per game, about
  three times the strength-adjusted HFA.
- A likely explanation is that the unpenalized home term soaks up the part of
  team strength that goes with hosting games, because the team effects are
  shrunk and η is not. This is the same confound as the naive HFA estimator
  below, now inside the solve.
- The separate λ_off/λ_def search spans 0.13 points of development MAE across
  16 pairs. The nested selection chose the least shrinkage (0.5/0.5) from
  2019 on.
- Snapshot diagnostics are in `opponent_adjust_summary.csv` and
  `opponent_adjust_diagnostics.csv`: all 7,888 solves succeeded, the median
  offensive effective sample size is 7.6 games, and |mean FBS offense effect|
  ≤ 0.065 EPA.
- The Round 9 solver reproduces every Round 8 stage-3 snapshot with a maximum
  difference of 0.

## Home-field advantage (hypothesis 4)

| Target | Learned h | SE | 95% CI | Non-neutral training games | Naive raw home margin | Incumbent HFA | MAE learned − fixed 3.0 |
|---|---|---|---|---|---|---|---|
| 2018 | 2.99 | 0.61 | [1.65, 4.06] | 719 | 4.51 | 3.31 | −0.000 |
| 2019 | 2.77 | 0.44 | [1.79, 3.50] | 1,430 | 4.43 | 3.37 | +0.007 |
| 2021 | 3.00 | 0.35 | [2.16, 3.55] | 2,145 | 4.49 | 3.48 | +0.000 |
| 2022 | 2.88 | 0.31 | [2.15, 3.35] | 2,857 | 4.29 | 3.28 | −0.002 |
| 2023 | 2.64 | 0.28 | [2.00, 3.08] | 3,572 | 4.27 | 3.07 | −0.003 |
| 2024 | 2.62 | 0.25 | [2.04, 3.02] | 4,302 | 4.24 | 3.07 | −0.002 |
| 2025 | 2.72 | 0.23 | [2.18, 3.09] | 5,024 | 4.40 | 3.07 | +0.008 |

(h is the constrained-fit value; the SE and CI come from the OLS diagnostic
fit.)

- Strength-adjusted HFA is about 2.6–3.0 points and stable (SE < |h| in every
  fit).
- Part A's raw-margin estimator would have said 4.2–4.5. The ~1.5-point gap is
  the strength confound, which is why Part B replaced that estimator.
- Learned HFA ties fixed +3.0 to within ±0.01 MAE. The HFA rule reverted to
  fixed +3.0 from 2021 because it was fractionally better on inner holdouts.
- Dropping HFA entirely costs about 0.15–0.20 MAE (ablation 3).
- Both HFA gates pass. The learned value sits slightly below both 3.0 and the
  incumbent's frozen 3.07.

## Talent prior (hypothesis 2, restated)

The talent terms are the talent composite relative to the program's own
trailing norm, portal net, and a new-coach flag. They enter decayed by
k/(k+n) and are measured *beyond* the incumbent's own talent/coaching prior.

| Split | All games | September | Either team 0 PBP games |
|---|---|---|---|
| Development | −0.051 | −0.129 | −0.347 |
| Conditional | +0.013 | +0.029 | −0.013 |

(MAE with talent − without; negative = talent helps.)

- **Development:** the talent terms helped September games by 0.13 points,
  enough for the 2023 lock to retain them.
- **Conditional:** they made September slightly worse (+0.03), so the gate
  fails. The early-season gain did not replicate.
- **Coefficients:** the recruiting-deviation coefficient is consistently
  *negative* (−0.7 to −2.2 points per z). Programs whose talent rose above
  their own norm did worse than the incumbent expected, which suggests the
  incumbent's `log_talent` term already over-reacts.
- **New coach:** −0.8 to −1.9 points from 2019 on (−0.10 to −0.22 team-rating
  SD, not the −0.5σ suggested in the brief). The one-season 2018 fit gave
  +2.1.
- **Portal:** small and sign-unstable. It is identified only from 2021, and
  CFBD destination vintage is unverified.

## Cross-tier and conference audit

| | P4-vs-G5 bias (dev) | P4-vs-G5 bias (cond) | Big Ten − MAC gap (dev) | Big Ten − MAC gap (cond) |
|---|---|---|---|---|
| Incumbent | 5.57 | 3.44 | 2.66 | 2.15 |
| Final | 5.80 (worse) | 2.68 (better) | 2.76 (worse) | 1.99 (better) |

Bias is the mean (actual − predicted) oriented from the P4 side. The
incumbent under-rates P4 teams against G5 opponents by 3.4–5.6 points; this is
the largest remaining systematic defect in the project. The final model
worsens it on development and improves it on conditional, entirely through
the talent terms in the lock. The no-worsening gates fail on development.
Per-conference residuals are in `conference_residuals.csv`; home and neutral
bias are in `site_bias.csv`.

## Go/no-go

| Gate | Split | Value | Threshold | Pass |
|---|---|---|---|---|
| Tests, integrity, coverage | all | 62 + 18 checks; coverage 100% | all pass | ✅ |
| MAE improvement | dev / cond | −0.001 / −0.012 | ≥ 0.25 | ❌ / ❌ |
| Bootstrap Δ upper bound | dev / cond | +0.008 / +0.055 | ≤ 0 | ❌ / ❌ |
| Calibration slope | cond | 1.009 | [0.90, 1.10] | ✅ |
| SD ratio | cond | 0.615 | [0.85, 1.15] | ❌ (unattainable; see above) |
| P4-vs-G5 bias not worse | dev / cond | +0.23 / −0.76 | ≤ 0 | ❌ / ✅ |
| Big Ten–MAC gap not worse | dev / cond | +0.10 / −0.16 | ≤ 0 | ❌ / ✅ |
| Opponent-adjusted beats raw and league | dev | −0.19 vs best baseline | < 0 | ✅ |
| Stable conditional efficiency value | 7 fits | 0 of 7 | 7 of 7 | ❌ |
| Learned HFA ties or beats fixed 3.0 | dev | +0.001 | ≤ 0.01 | ✅ |
| Learned HFA stable | 7 fits | max SE/|h| = 0.21 | < 1 | ✅ |
| Talent: no September degradation | dev / cond | −0.129 / +0.029 | ≤ 0 | ✅ / ❌ |
| Zero target-season leakage | all | adversarial permutations unchanged | all | ✅ |

Full detail: `outputs/round9/promotion_gates.csv` and `promotion_decision.csv`.

## Honest limitations

- **Talent data.** No recruiting class rankings were available locally and no
  CFBD key is configured. The 247 roster talent composite stood in for them,
  with unverified vintage. Portal data start in 2021, and 1–6% of events have
  unresolved school names (`portal_audit.csv`). Coaching uses identity fields
  only.
- **Development bootstrap.** Four development seasons give only 35 distinct
  season resamples; three conditional seasons give 10. The intervals are
  coarse.
- **Incumbent selection overlaps development.** The incumbent's structure was
  selected on 2019–2022 evidence in Rounds 4–5, so development-split
  comparisons inherit that optimism. The conditional split is the clean test.
- **Opponent-adjustment identifiability.** The ridge intercept plus penalties
  identify the solve; the mean FBS offense effect is ≤ 0.065 EPA, not exactly
  0. The play-level home term is confounded with team strength (see above).
- **Early-season sample size.** The median offensive effective sample size is
  7.6 games at a typical snapshot and near 0 in week 1. Efficiency is 0 before
  a team's first game, so efficiency-only forecasts are weakest in September.
- **Special teams** remain untested; the Round 8 defect is carried forward.
- **The SD-ratio gate** is structurally unattainable for calibrated forecasts
  at the correlation this sport allows. Future rounds should drop it or restate
  it in terms of calibration slope alone.

## What this implies for Round 10

Round 9 is the third consecutive round showing that play-by-play efficiency
carries almost no information the incumbent's score-based ratings lack. The
largest measurable gaps now are:

1. The incumbent trails the closing market by 0.52 MAE.
2. The incumbent's P4-vs-G5 bias is 3.4–5.6 points.

Neither is an efficiency problem. A cross-tier or connectivity correction to
the incumbent's rating solve is a more promising target than more efficiency
features.

## Reproducibility

```
Rscript archive/v9-round9/code/tests/test_v9.R            # 62 synthetic checks
Rscript archive/v9-round9/code/tests/test_v9_forward.R    # 18 real-input checks
V9_TESTS_PASSED=1 Rscript archive/v9-round9/code/scripts/run_round9_forward.R
V9_TESTS_PASSED=1 Rscript archive/v9-round9/code/scripts/report_round9.R
Rscript archive/v9-round9/code/scripts/market_benchmark_round9.R   # post-freeze only
```

The forward run takes about 40 minutes, mostly 34 × 11 seasons of snapshot
solves, and caches under `outputs/round9/cache/`. The six frozen artifacts are
hash-locked in `prediction_freeze_manifest.csv`, and the report and market
scripts refuse to run if any has changed. Logs: `forward_run.log` and
`report_run.log`.
