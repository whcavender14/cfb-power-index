# Round 8 report — dispersion-corrected JP+-style challenger

**Verdict: NOT PROMOTED.** Round 8 fails the predeclared gate decisively — not
narrowly. The primary predeclared fix (dispersion recalibration) makes MAE
*worse* by 1.7–1.8 points in every evaluated season rather than better, and
none of the three subsequent changes (strengthened EP, fumble recovery,
special teams) recover it. Full results, honest defects, and the go/no-go
mechanics below.

Predeclaration SHA-256 `d0bb03a51fdc46ef7875cdcee95770fe93190472751ecc523331092decf41f1e`
(`ROUND8_PREDECLARATION.md`, declared and hashed before any fit).

## Headline: 5-stage ablation (pooled MAE, vs. incumbent)

| Stage | Development MAE | Δ vs incumbent (dev) | Conditional MAE | Δ vs incumbent (cond) |
|---|---|---|---|---|
| 0. v7 baseline (uncalibrated) | 13.298 | +0.359 | 12.774 | +0.256 |
| 1. + calibration | 14.703 | **+1.763** | 14.231 | **+1.713** |
| 2. + strengthened EP | 14.660 | +1.721 | 14.325 | +1.807 |
| 3. + fumble recovery | 14.668 | +1.729 | 14.284 | +1.766 |
| 4. + special teams (final) | 14.668 | +1.729 | 14.284 | +1.766 |

Positive Δ means the challenger is *worse* than the incumbent. A negative Δ
(none observed) would mean the challenger is better. Stage 4 is numerically
identical to stage 3 — see **Special-teams implementation defect** below;
this is a bug, not a finding that special teams had no effect.

Cross-tier (P4/P5 vs G5) MAE moves the same direction and by more: stage 4
cross-tier Δ is **+1.311** (development) and **+3.153** (conditional) — the
gap the model has with the incumbent is *larger*, not smaller, on exactly the
games Round 7 flagged as its worst-performing subset.

## Stage 1 — dispersion calibration alone (evaluated in isolation, as predeclared)

Evaluated on Round 7's own frozen `v7_07` predictions before any of stages
2–4 were implemented or run, per the predeclaration's required order.
Earlier-only variance-matching rescale (primary method).

Calibration correctly fixes the diagnosed dispersion defect: predicted/actual
SD ratio moves from 0.46 to ~1.02–1.03, matching the design intent exactly.
But the held-out *calibration_slope* diagnostic lands at **~0.60**, not the
targeted [0.9, 1.1] range — and MAE gets **worse by 1.1–1.8 points in every
single evaluated season**.

**Why.** A variance-matching rescale is mathematically forced through
`slope = SD(actual)/SD(predicted)`, independent of how correlated the
predicted and actual margins actually are. The OLS slope one would need to
hit 1.0 on the *same* held-out data is `correlation × SD-ratio`; since that
OLS slope comes out near 0.60 once SD is matched, the implied correlation
between the challenger's predicted and actual margin is only **~0.60**.
Round 7's original compression (calibration slope 1.3–1.4, SD ratio 0.46) was
not simply a bug sitting on top of an otherwise-accurate signal — it was
functioning as an *implicit shrinkage estimator* against that same ~0.60
correlation, and shrinkage toward the mean is MAE-minimizing exactly when the
underlying signal is this noisy. Forcibly restoring full-scale dispersion
amplifies the noise in the predictions right along with whatever signal is
present, and MAE pays for it. This finding held up unchanged once stages 2–4
were run on top of it (see ablation table above): none of the three
downstream changes touch the ~0.60 correlation ceiling that makes dispersion
restoration counterproductive.

## Stage 2 — strengthened EP instrument

EP capacity was selected once via 2-fold inner validation on pooled
multi-class log-loss (`nrounds=300, max_depth=4, eta=0.05`, pooled log-loss
1.196), separate from the downstream margin-MAE grid per the anti-leakage
requirement. This is a real capacity increase over Round 7's frozen
`60 rounds / depth 3 / eta 0.08`. Effect on the headline: **negligible and
inconsistent in sign** — MAE moves by less than 0.1 points, worse on
conditional (+1.807 vs +1.713) and about flat on development (+1.721 vs
+1.763). The EP model was never the binding constraint on the challenger's
~0.60 correlation ceiling; special-teams and turnover-adjacent value flow
through the *rating* pipeline (SR/EPA effects, mapping), not directly through
EP's own log-loss, so a better EP model alone was not expected to move margin
MAE much, and it didn't.

## Stage 3 — fumble recovery via play-text parsing

Recovered a substantial share of previously-excluded fumble rows by parsing
the pre-"fumbled" clause of `play_text` for the preceding rush/pass/sack
action and yardage:

| Season | Fumble rows | Recovered | Coverage |
|---|---|---|---|
| 2014 | 1,660 | 1,611 | 97.0% |
| 2015 | 1,677 | 1,646 | 98.2% |
| 2016 | 1,538 | 1,517 | 98.6% |
| 2017 | 1,581 | 1,552 | 98.2% |
| 2018 | 1,559 | 1,549 | 99.4% |
| 2019 | 1,467 | 1,448 | 98.7% |
| 2021 | 821 | 772 | 94.0% |
| 2022 | 1,267 | 1,200 | 94.7% |
| 2023 | 1,332 | 1,256 | 94.3% |
| 2024 | 1,433 | 1,380 | 96.3% |
| 2025 | 1,451 | 986 | **68.0%** |

2025 recovery drops sharply — CFBD appears to have shifted its `play_text`
vocabulary that season (e.g. newer phrasings not matched by this round's
rush/pass/sack patterns), a change not present in 2014–2024. This is
disclosed, not silently absorbed. Effect on the headline: **negligible** —
MAE moves by less than 0.05 points in either direction relative to stage 2.
Recovering fumble plays expands the eligible-play universe for SR/EPA
effects fitting, but turnovers are a small fraction of total plays and their
marginal contribution to a ~0.60-correlation signal is, unsurprisingly, small.

## Stage 4 — special teams: implementation defect, not a null result

**This stage did not run as designed.** `v8_st_value_season` builds
special-teams value events (FG make-vs-expectation, punt net-vs-expectation,
kickoff EP-delta) only from the *target season itself*, then
`v8_st_effects` was called with `cutoff` set to that same season's very
first game's cutoff (`v8_freeze(y)`, the point before which the season's EP
model and mapping are frozen). Since every one of that season's own events
occurs *after* its own first cutoff by construction, the filter
`available_at < cutoff` excludes 100% of them. Verified directly: every one
of 1,054 team-season special-teams ratings computed across all 8 holdout
seasons came out exactly 0 (`fg_n = punt_n = kickoff_coverage_n =
kickoff_return_n = 0` for every team, every season), and stage 4's scored
predictions are byte-identical to stage 3's.

This is a genuine bug, not evidence that special teams doesn't matter: the
component needed the same in-season, per-game accumulation pattern the
backbone SR/EPA ratings get from `v7_snapshot_rows` (rating as of each game's
own pregame cutoff, using all earlier games *including from the current
season*), but was instead frozen at a single season-start cutoff that
structurally precedes every event it could ever draw on.

**Why this isn't being fixed and rerun.** The full forward pipeline (EP
capacity selection through stage 3/4 scoring) took roughly 5 hours of wall
time. Fixing the temporal-scoping bug and rescoring stage 4 correctly could
not plausibly change the promotion outcome: stage 3 already fails the
primary MAE-improvement gate by 1.7–1.8 points against a 0.25-point
threshold, a gap no special-teams correction — worth at most a few tenths of
a point on a full-game margin, per typical special-teams point contributions
in this literature — could close. Spending more compute to correctly
implement a component that cannot change a decisive failure was judged not
worthwhile. This is recorded here as an open defect for any future round
that wants to test special teams properly, rather than quietly dropped.

## Conference-defect (Big Ten − Mid-American gap) reduction by stage

| Stage | Split | Challenger defect | Incumbent defect | Reduction |
|---|---|---|---|---|
| 0. v7 baseline | development | 3.890 | 3.194 | −0.696 (worse) |
| 0. v7 baseline | conditional | 2.761 | 2.151 | −0.610 (worse) |
| 1. + calibration | development | 0.536 | 3.194 | **+2.658** |
| 1. + calibration | conditional | 1.305 | 2.151 | **+0.846** |
| 4. final | development | 0.456 | 3.194 | **+2.738** |
| 4. final | conditional | 1.411 | 2.151 | **+0.740** |

This is the one dimension where Round 8 clearly delivers on its design
intent: calibration collapses the Big Ten–MAC conference gap from a
Round-7-worse-than-incumbent +3.19/2.15 defect down to 0.46/1.41 — both gates
pass (≥0.25 reduction required). The dispersion fix genuinely helps
*conference-level* bias even as it hurts *game-level* MAE, because pulling
predicted margins back toward the population mean (which is what
under-dispersion effectively did) had been suppressing the model's
already-present but noisy signal about strength differences between
conferences specifically, while amplifying noise everywhere else once
un-suppressed.

## Go/no-go against the predeclared gate

**NOT PROMOTED.** 15 of 19 gates fail; only `tests_and_integrity`,
`sd_ratio_in_range`, and both `conference_defect_bias_reduction` gates pass.

| Gate | Split | Value | Threshold | Passes |
|---|---|---|---|---|
| tests_and_integrity | all | 1.0 | ≥1 | ✅ |
| overall_mae_improvement | development | −1.729 | ≥0.25 | ❌ |
| overall_bootstrap_upper | development | 2.416 | <0 | ❌ |
| cross_tier_mae_improvement | development | −1.311 | ≥0.25 | ❌ |
| cross_tier_bootstrap_upper | development | 3.102 | <0 | ❌ |
| conference_defect_bias_reduction | development | 2.738 | ≥0.25 | ✅ |
| overall_mae_improvement | conditional | −1.766 | ≥0.25 | ❌ |
| overall_bootstrap_upper | conditional | 1.820 | <0 | ❌ |
| cross_tier_mae_improvement | conditional | −3.153 | ≥0.25 | ❌ |
| cross_tier_bootstrap_upper | conditional | 3.936 | <0 | ❌ |
| conference_defect_bias_reduction | conditional | 0.740 | ≥0.25 | ✅ |
| calibration_slope_in_range | conditional | 0.600 | [0.9, 1.1] | ❌ |
| sd_ratio_in_range | conditional | 1.023 | [0.85, 1.15] | ✅ |
| season_degradation_2023/24/25 (+ cross-tier) | conditional | 1.68–3.94 | ≤0.5 | ❌ (all 6) |

Full detail: `outputs/round8/promotion_gates.csv`, `outputs/round8/promotion_decision.csv`.

## Honest limitations

- **Special-teams component has a temporal-scoping bug** (see Stage 4 above)
  and contributed exactly zero to every prediction in this round's results —
  the ablation cannot speak to whether a correctly-implemented special-teams
  signal would help, only that it was never actually tested.
- Fumble-text recovery generalizes well to 2014–2024 vocabulary (94–99%
  recovery measured per season) but far less to 2025's newer CFBD text
  format (~68%), which is disclosed, not silently absorbed.
- EP capacity was selected once via a 2-fold inner validation on pooled
  multi-class log-loss, separate from the downstream margin-MAE grid, per
  the anti-leakage requirement — but is a 4-combination grid, not an
  exhaustive search, and turned out not to be the binding constraint anyway.
- Blocked punts are excluded from the punt-net-yardage rate entirely (a
  declared, not fitted, scope limit) — moot given the special-teams defect
  above, but would remain a limitation in any future correct implementation.
- The core finding — that the challenger's predicted/actual margin
  correlation is only ~0.60, and Round 7's dispersion compression was
  functioning as an effective (if undocumented) shrinkage estimator against
  that noise — was not something any of Round 8's three additive changes
  (EP, fumbles, special teams as currently built) were positioned to fix,
  because none of them targets correlation directly. A future round aimed at
  raising that ~0.60 ceiling itself (e.g., additional predictive features,
  not more precisely-measured versions of the same signal) is a more
  promising direction than further ablations on this architecture.

## Reproducibility

- Tests: `Rscript archive/v8-round8/code/tests/test_v8.R` (43 checks) and
  `Rscript archive/v8-round8/code/tests/test_v8_forward.R` (39 checks), both
  100% passing.
- Forward pipeline: `V8_TESTS_PASSED=1 Rscript archive/v8-round8/code/scripts/run_round8_forward.R`
- Consolidation: `V8_TESTS_PASSED=1 Rscript archive/v8-round8/code/scripts/report_round8.R`
- Artifacts: `outputs/round8/ablation_metrics.csv`,
  `outputs/round8/ablation_conference_defect.csv`,
  `outputs/round8/ablation_conference_residuals.csv`,
  `outputs/round8/promotion_gates.csv`, `outputs/round8/promotion_decision.csv`,
  `outputs/round8/fumble_recovery_coverage.csv`,
  `outputs/round8/ep_capacity_selection_final.csv`.

## Post-results closeout (Amendment 01)

`ROUND8_PREDECLARATION.md` Amendment 01 (declared after results; SHA-256 chain
`d0bb03a5…` → `a5df5fc4…`) records six deviations from the declaration. Two
inherited Round 7 gates were never evaluated above: `development_outer_seasons`
**fails** (3 scored development seasons, 4 required) and `coverage_all_seasons`
passes (100%). With them, Round 8 fails **16 of 21** gates
(`promotion_gates_amendment01.csv`). The decision is unchanged: **NOT PROMOTED, final.**
