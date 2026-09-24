# Round 10 report — opponent-adjustment cleanup + cross-tier correction + talent gate

**Verdict: NOT PROMOTED.** 4 of 12 gate rows fail: MAE improvement (both
splits), the conditional bootstrap bound, and the SD ratio. The incumbent
`v5_EB_features` stays frozen.

The three changes each did what they were designed to do mechanically. None
moved conditional MAE:

1. **Opponent arm without the home term:** confound fixed, no ensemble value.
   `v10_opponent_nohome` beats Round 9's home-term arm by 0.18 efficiency-only
   MAE and edges out the Round 7/8 reference (−0.009 development, −0.022
   conditional). Its ensemble weight is still exactly 0 in every fit.
2. **Cross-tier correction:** helps development, does nothing on conditional.
   It cuts development MAE by 0.10 (bootstrap interval excludes 0), but gives
   −0.001 on conditional (interval [−0.038, +0.022]). The development-learned
   correction (≈ 5.5 points) overshoots the conditional-era bias (3.4), so the
   bias flips sign rather than disappearing.
3. **Talent September gate:** fails. Talent makes conditional September games
   worse by 0.086, so it is not retained. This replicates Round 9.

Declaration: SHA-256 `3a5de2df…` (pre-code, pre-fit). **Amendment 01**
(`4f7ea313…`) corrected an adversarial *check*. The original B7.2 check
wrongly expected 2024 predictions to ignore 2023 outcomes, but the 2024 fit
legitimately trains on 2023. The fix changes no prediction or decision (see
the declaration, B12).

## Headline (pooled MAE; Δ = model − incumbent, negative is better)

| Model | Dev MAE | Dev Δ [95% season bootstrap] | Cond MAE | Cond Δ [95% season bootstrap] |
|---|---|---|---|---|
| Incumbent (`ablation1`) | 12.970 | — | 12.518 | — |
| Ensemble, no correction | 12.970 | +0.001 [−0.006, +0.008] | 12.518 | −0.000 [−0.002, +0.001] |
| Incumbent + cross-tier correction | 12.873 | −0.096 [−0.145, −0.027] | 12.519 | +0.001 [−0.036, +0.024] |
| **`v10_candidate`** | **12.869** | **−0.101 [−0.153, −0.023]** | **12.517** | **−0.001 [−0.038, +0.022]** |
| Conditional, talent on (not locked) | — | — | 12.549 | +0.031 [−0.024, +0.105] |
| Closing market (post-freeze) | — | — | 12.00 | −0.52 |

- Development = 2018, 2019, 2021, 2022 (3,092 games).
- Conditional = 2023–2025 (2,398 games).
- Pairing with the incumbent is 100% in every season.
- The candidate is the ensemble (w_s = 1, w_e = 0; HFA learned for 2018–19 and
  fixed at +3.0 from 2021) plus the cross-tier correction, with talent off.

## 1. Opponent arm without the home term

Efficiency-only MAE:

| Arm | Dev | Cond |
|---|---|---|
| Raw | 15.057 | 14.429 |
| League-average (λ = 1) | 14.626 | 14.006 |
| Round 9 opponent + home term (1/1) | 14.432 | 13.923 |
| Round 7/8 reference (1/1) | 14.262 | 13.767 |
| **`v10_opponent_nohome` (nested-selected)** | **14.253** | **13.745** |

- **The confound is resolved** under the B2 criterion.
  - Dropping η recovers the full 0.18 points Round 9 lost.
  - At λ = 1/1 the new arm reproduces the reference snapshots with a maximum
    difference of 0, verified on all 11 seasons.
  - Separate λs add only 0.01–0.02 on top of that.
- **Selected configurations:**
  - 2018: (1, 1), which is the reference itself.
  - 2019: (0.5, 1).
  - 2021, 2022 and the conditional lock: (0.5, 0.5), all with full
    conversion.
- **Arm rule:** passed for every target, and the gate passes on development
  (−0.37 vs the best baseline). The reference fallback was never used.
- **Ensemble contribution: none.**
  - Partial correlation with the outcome given the incumbent is 0.048–0.067.
  - Incremental R² is 0.0013–0.0026.
  - The zeroing rules therefore set w_e = 0 in all 10 fits.
  - This is Round 9's result again, with a cleaner arm. The B1.1 ceiling
    (≤ 0.01 MAE) held.

## 2. Cross-tier correction

Development residual, P4-oriented, by strata (actual − incumbent):

| P4 team side | vs G5 | vs independent | n (vs G5) |
|---|---|---|---|
| Home | **+6.38** (SE 1.00) | +2.66 | 267 |
| Away | +3.84 (SE 2.05) | +1.37 | 66 |
| Neutral | +2.45 (SE 2.82) | −4.12 | 33 |

For comparison, P4-vs-P4 games show −1.21 and all other games −1.30 (home
orientation) on development.

Fitted correction, `s × (a + b × p4_home)`:

| Target | a | b | P4 home | P4 away/neutral | Training |
|---|---|---|---|---|---|
| 2018 | 9.71 | −4.52 | 5.20 | 9.71 | 2017 |
| 2019 | 6.53 | −1.51 | 5.02 | 6.53 | 2017–18 |
| 2021 | 4.61 | +0.57 | 5.18 | 4.61 | 2017–19 |
| 2022 | 4.59 | +1.41 | 6.00 | 4.59 | 2017–21 |
| 2023–25 (frozen) | 3.38 | +3.00 | 6.38 | 3.38 | 2018, 19, 21, 22 |

- **Magnitude:** 12–13% of games are corrected, by an average of 5.5–5.7
  points.
- **Drop rule (development only):** kept. MAE improved 12.970 → 12.869.
- **Development:** P4-vs-G5 games improve by 0.86 MAE, and the bias falls from
  +5.57 to +0.13.
- **Conditional (the clean test):** the correction **neither helps nor
  hurts**.
  - Overall: −0.0004 MAE.
  - P4-vs-G5 games: +0.003 MAE.
  - Bias: +3.44 → −2.05. |bias| gate 4 passes, but only because 2.05 < 3.44.
  - Calibration slope: 1.014 → 0.946.
- **By season:** the correction helped 2018, 2021, 2022 and 2024 (−0.04 to
  −0.17) and hurt 2019, 2023 and 2025 (+0.01 to +0.02).

The defect is real but shrinking and noisy:

- **It is not something the market shares.** The closing line's own P4-vs-G5
  residual is +0.29 (conditional), against the incumbent's +3.44. So the gap is
  a genuine incumbent defect, not a feature of the games.
- **It is not stationary.** P4-home-vs-G5 fell from +6.4 (development) to +3.9
  (conditional), and the fitted a fell from 9.7 to 3.4 as training grew.
- **The per-stratum SEs (1–3 points) are as large as the effects.** A flat
  per-game offset learned from ~370 games moves 318 conditional predictions by
  5.5 points each. The residual SD on those games is ~16, so the offset adds
  about as much error on games it overshoots as it removes on the others.
- **Pre-fit ceiling (B1.2):** even a perfectly sized flat correction was worth
  ≤ 0.07 MAE overall.

## 3. Talent gate

| Conditional subset | Talent off | Talent on | Improvement (off − on) |
|---|---|---|---|
| September (757 games) | 12.32 | 12.41 | **−0.086** → gate fails, talent dropped |
| All games | 12.52 | 12.55 | −0.032 |
| Either team with 0 games played | 13.23 | 13.37 | −0.145 |

- This replicates Round 9's conditional September result: it was +0.029 there
  and is worse here with the correction applied.
- As disclosed in B1.5, this choice reads conditional outcomes. Because the gate
  failed, it only removed terms, so it could not flatter conditional metrics.

## Go/no-go

| # | Gate | Split | Value | Threshold | Pass |
|---|---|---|---|---|---|
| 1 | Tests, integrity, coverage, training < target | all | 49 + 17 checks; coverage 100% | all | ✅ |
| 2 | MAE improvement | dev / cond | 0.101 / 0.001 | ≥ 0.25 | ❌ / ❌ |
| 3 | Bootstrap Δ upper bound | dev / cond | −0.023 / +0.022 | ≤ 0 | ✅ / ❌ |
| 4 | \|P4-vs-G5 bias\| not worse | dev / cond | 0.13 vs 5.57 / 2.05 vs 3.44 | ≤ incumbent | ✅ / ✅ |
| 5a | Calibration slope | cond | 0.946 | [0.90, 1.10] | ✅ |
| 5b | SD ratio | cond | 0.661 | [0.85, 1.15] | ❌ (unattainable, B1.4) |
| 6 | Opponent arm beats raw and league | dev | −0.373 | < 0 | ✅ |
| 7 | Talent September | cond | not retained | — | ✅ |
| 8 | Adversarial leakage | all | 9 of 9 unchanged | all | ✅ |

The market row shows why 5b cannot pass. The closing line's SD ratio is 0.648,
its correlation 0.658 and its slope 1.016.

## Honest limitations

- **The brief's expected outcome was not reachable.** The ceilings in B1.1–B1.3
  (≤ ~0.08 total) were written before any fit. The result (0.10 on development,
  0.00 on conditional) sits at that ceiling on development and below it on
  conditional.
- **The development gain for the correction is partly in-sample.** Each
  development target's correction is forward-chained, but the keep/drop choice
  was made on pooled development MAE. The conditional split is the clean test,
  and there the gain is zero.
- **The incumbent was selected on 2019–2022 evidence**, so development
  comparisons inherit optimism.
- **The bootstrap is coarse:** 35 (development) and 10 (conditional) distinct
  season resamples.
- **Amendment 01** was written after the first run had logged the drop decision
  and the talent-gate value. It corrects only the leakage-check design and
  changes no prediction.

## What this implies for Round 11

- **Efficiency is exhausted.** Four rounds (7–10) show that play-by-play
  efficiency adds no information the incumbent lacks, even with the cleanest
  arm. It should not be revisited.
- **The P4-vs-G5 gap is real** (the market does not have it) **but not
  constant.** A post-hoc offset is too blunt. The more promising fix is inside
  the incumbent's rating solve: cross-conference connectivity, or
  conference-level shrinkage targets, so the gap is estimated from the current
  season's inter-tier games rather than extrapolated from past seasons.
- **Retire the talent add-on and the SD-ratio gate.** Talent has now failed the
  conditional September test twice. The SD-ratio gate cannot be passed by any
  calibrated forecast, including the market.
- **The incumbent still trails the closing line by 0.52 MAE.** That gap is the
  honest measure of remaining headroom.

## Reproducibility

```
Rscript archive/v10-round10/code/tests/test_v10.R            # 49 synthetic checks
Rscript archive/v10-round10/code/tests/test_v10_forward.R    # 17 real-input checks
V10_TESTS_PASSED=1 Rscript archive/v10-round10/code/scripts/run_round10_forward.R
V10_TESTS_PASSED=1 Rscript archive/v10-round10/code/scripts/report_round10.R
Rscript archive/v10-round10/code/scripts/market_benchmark_round10.R   # post-freeze only
```

- **Runtime:** the forward run takes about 3 minutes. It builds 16 snapshot
  sets into `outputs/round10/cache/` and reuses Round 9's raw, league and
  reference forecasts after verifying Round 9's declaration and freeze hashes.
- **Freeze:** nine artifacts are hash-locked in `prediction_freeze_manifest.csv`.
  The report and market scripts refuse to run if any of them changes.
- **Location:** all outputs are in `outputs/round10/`, a symlink to
  `archive/v10-round10/results/artifacts/`.
