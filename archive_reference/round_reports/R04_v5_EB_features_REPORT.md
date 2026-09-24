# Round 4 results

**Selected: EB_features, the precision-4 empirical-Bayes score model with eligible talent, returning-production and coaching preseason features.** It earned advancement from earlier-only matched development evidence, before the secondary conditional test. v4 and all Round 3 artifacts remain unchanged.

## Development decision

The expanded development sample has 2,320 final FBS-versus-FBS games, including postseason, in 2019, 2021 and 2022. The earliest usable forward prior component is 2018; it calibrates 2019. Every candidate scores exactly the same game IDs. The original 2021–2022 B predictions are reproduced to numerical tolerance below 1e-9.

Selected MAE is **12.920**, versus **13.238** for B: a paired change of **-0.317 points/game**. Its season-cluster 95% interval is [-0.481, -0.144], and season-plus-calendar-period block interval is [-0.520, -0.103]. Its HFA-adjusted held-out calibration slope is **1.054**, versus 1.136; no held-out slope was forced to one.

| candidate | mae | slope | estimate | block_low | block_high | passes |
| --- | --- | --- | --- | --- | --- | --- |
| B | 13.238 | 1.136 | 0.000 | 0.000 | 0.000 | FALSE |
| B_scale | 13.176 | 0.982 | -0.062 | -0.171 | 0.067 | FALSE |
| C4 | 13.154 | 1.044 | -0.083 | -0.173 | 0.017 | FALSE |
| Coach | 13.232 | 1.134 | -0.006 | -0.032 | 0.017 | FALSE |
| Conference | 13.146 | 1.059 | -0.092 | -0.201 | 0.011 | FALSE |
| EB_features | 12.920 | 1.054 | -0.317 | -0.520 | -0.103 | TRUE |
| Full | 13.042 | 1.170 | -0.195 | -0.346 | -0.060 | TRUE |
| RP | 13.218 | 1.138 | -0.020 | -0.096 | 0.058 | FALSE |
| RP_def | 13.234 | 1.135 | -0.003 | -0.043 | 0.030 | FALSE |
| RP_off | 13.216 | 1.140 | -0.022 | -0.063 | 0.023 | FALSE |
| Talent_RP | 13.023 | 1.137 | -0.215 | -0.425 | -0.031 | TRUE |
| Uncertainty | 13.206 | 1.063 | -0.032 | -0.128 | 0.068 | FALSE |

TRUE means the declared pooled-MAE, calibration, seasonal-stability and paired-uncertainty requirements passed, not that the candidate was necessarily selected. EB_features is more than .05 MAE better than the other passing candidates, so the simplicity tie-break does not override it. B is the incumbent reference and is not tested for advancement against itself.

| season | delta_mae |
| --- | --- |
| 2019 | -0.481 |
| 2021 | -0.144 |
| 2022 | -0.326 |

Only three independent development seasons support this decision. Bootstrap intervals are descriptive resampling evidence, not a guarantee for a different football era. Talent_RP and Full also passed; RP alone, Coach alone, C4, B_scale, and both structural candidates did not clear all requirements. Conference also failed its required comparison against general Uncertainty. There is no installed conference or G5 penalty.

## Features and provenance

Historical offseason data with missing exact publication dates were used in primary development when substantively season-appropriate. All cached feature observations remain **historical_vintage_unverified**. No download, scrape, cfbfastR, file-modification, transfer or hire date is represented as a historical publication date. FEATURE_AUDIT.md gives field-level decisions; raw files and hashes are separate from team-level transformations and snapshot IDs.

Returning production is represented by separate offensive and defensive fractions. On FBS-only records, offense covers 128/130 teams in 2021; defense covers 47/130. Defense is absent before 2017. Coverage regimes retain available offense, use earlier training only, and never turn a missing substantive feature into zero. RP's development MAE change is -0.020 with block interval [-0.096, 0.058]: **its independent incremental benefit is inconclusive**. Offense-only and defense-only ablations are reported, not discarded for missing publication metadata.

No independently stronger historical-vintage or contributor-construction subset was recovered with enough training/forward coverage. Thus a distinct higher-provenance RP estimate is unavailable. is_estimated is missing for all pre-2026 rows and cannot authenticate them. Every external-feature improvement therefore depends on lower-confidence historical aggregates; these data do not establish historical-vintage robustness. Removing all external features routes the feature pipeline back to exact B.

Portal has event accounting, separate incoming/outgoing aggregates, name-resolution statuses and duplicate-player exclusions, but only one possible pre-2023 forward test season. Destination-state timing is also not independently authenticated. No portal effect is fitted. No acceptable QB continuity source exists; unknown_QB is explicit. Coaching excludes all target-season performance fields and uses only a unique pre-cutoff hire/tenure state. All transformations, penalty choices, imputation of previous-score inputs, rank screens and standardization are fold-local.

The feature extensions replace B's preseason OLS with the declared ridge coverage-regime model. Their differences include this estimation policy as well as feature content; they are not causal effects of roster changes. Talent_RP's gain is stronger than RP alone, while adding coaching to it does not improve its pooled MAE. The full EB family was fixed in advance and was not redesigned from conditional results.

## Secondary conditional test: 2023–2025

These outcomes were already conditionally exposed by Round 3. They are **not a fresh locked outer test**. The frozen selected candidate remains unchanged.

| candidate | n | mae | rmse | bias | intercept | slope |
| --- | --- | --- | --- | --- | --- | --- |
| B | 2398.000 | 12.830 | 16.280 | -0.650 | 0.443 | 1.186 |
| B_scale | 2398.000 | 12.793 | 16.164 | -0.460 | 0.443 | 1.012 |
| C4 | 2398.000 | 12.731 | 16.118 | -0.486 | 0.341 | 1.114 |
| RP | 2398.000 | 12.770 | 16.193 | -0.613 | 0.399 | 1.187 |
| Talent_RP | 2398.000 | 12.558 | 15.904 | -0.333 | 0.133 | 1.140 |
| Full | 2398.000 | 12.542 | 15.879 | -0.304 | 0.120 | 1.127 |
| EB_features | 2398.000 | 12.518 | 15.787 | -0.043 | 0.018 | 1.015 |
| Uncertainty | 2398.000 | 12.808 | 16.219 | -0.576 | 0.423 | 1.129 |
| Conference | 2398.000 | 12.701 | 16.064 | -0.357 | 0.201 | 1.112 |

Selected-vs-B paired MAE change is -0.312, with block interval [-0.497, -0.139]. Global HFA-adjusted slope 1.015 and bias -0.043 are encouraging conditional diagnostics. They do not authorize new tuning or prove that early-season behavior is solved.

## Calibration, evidence states and schedule structure

Slopes/intercepts below use actual and predicted margins with each fitted HFA removed. The raw game-scale MAE/RMSE/bias remain unadjusted. Neutral and nonneutral games are separately evaluated. Reliability bins, all declared game-state buckets, provider weeks, promotion, prior/favorite magnitudes, and bootstrap intervals are in the calibration CSVs.

Selected development period diagnostics:

| period_bucket | n | mae | bias | slope | slope_low | slope_high |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 13.000 | 22.415 | -0.380 | 0.489 | 0.018 | 0.636 |
| 2 | 132.000 | 12.884 | -4.343 | 1.270 | 1.038 | 1.558 |
| 3 | 141.000 | 13.302 | -1.120 | 1.170 | 0.975 | 1.243 |
| 4 | 150.000 | 14.409 | -0.735 | 1.239 | 1.200 | 1.279 |
| 5+ | 1884.000 | 12.710 | 1.086 | 1.006 | 0.900 | 1.085 |

Period 1 is small and unstable; periods 2–4 still show compression in development. The selected model improves aggregate behavior but does not eliminate every early-state defect.

Selected conditional site diagnostics:

| site | n | mae | bias | intercept | slope | slope_low | slope_high |
| --- | --- | --- | --- | --- | --- | --- | --- |
| neutral | 202.000 | 12.505 | -0.682 | 0.686 | 0.986 | 0.686 | 1.308 |
| nonneutral | 2196.000 | 12.519 | 0.016 | -0.046 | 1.017 | 0.950 | 1.077 |

Network reports cover historical conference, distinct FBS opponents, distinct cross-conference opponents, component size, descriptive power-conference opponents, FCS exposure, one-score concentration, prior uncertainty, already-faced opponent prior strength/current working variance, and zero/one/multiple-game states. Future edges are excluded. Conference membership is season-labeled provider metadata, not independently archived announcements. Unknown/ambiguous historical membership remains a provenance limitation. Conference-average plausibility did not determine selection.

## Current ratings and exact contributions

At the fixed 2026-09-09 00:00 UTC information cutoff, the selected rating SD is 11.673 points. Preseason prior-finish Pearson correlation is 0.922; Spearman is 0.932. Correlation reduction was not optimized or treated as a success criterion.

| team | games_played | power_rating | prior_contribution | current_contribution | centering_contribution | power_prior_inputs_at_mean |
| --- | --- | --- | --- | --- | --- | --- |
| Ohio State | 1.000 | 28.994 | 20.672 | 8.322 | -0.000 | 18.473 |
| Indiana | 1.000 | 21.510 | 16.021 | 5.489 | -0.000 | 4.394 |
| Old Dominion | 0.000 | 2.163 | 2.163 | -0.000 | -0.000 | -1.292 |
| South Florida | 1.000 | 1.842 | 0.687 | 1.155 | -0.000 | -3.182 |
| James Madison | 1.000 | -0.867 | -1.522 | 0.655 | -0.000 | -6.076 |

Prior and current contributions come from the coupled score system, not scalar marginal percentages. They sum to power with centering. The counterfactual replaces only previous-score offense/defense inputs by the centered FBS mean while keeping valid offseason features, promotion state and current evidence fixed. Team movements are model outputs, not evidence that a team's real ability changed by that amount.

The selected EB objective uses prior precision4, preseason scale 1.12271478057756, prediction HFA 3.06853968902663 and gamma1. It has no convex handoff parameter. Reported fitted k values for EB are unused comparison diagnostics. At globally zero games, EB is the centered calibrated preseason mean. After one game, its opponent-coupled matrix solve updates both units. The exact zero/one synthetic outputs and additive contributions are in zero_one_algebra_fixtures.csv. component_schedules.csv explicitly labels EB shares as conditional illustrations.

## Matched market benchmark

The read-only supplied CFBD latest-available export covers all 2,398 conditional games. Provider counts are in market_providers.csv. Source/query and content hash are in market_source_manifest.csv. No independent closing quote timestamp was recovered: **latest-available is not verified closing**. Lines were joined only after design and predictions were saved.

Selected model MAE **12.518**, market MAE **12.019**, model-minus-market **+0.499**. The model still trails this benchmark materially. Market inputs never enter priors, preprocessing, calibration, selection or production. Seasonal paired comparisons and both uncertainty intervals are exported.

## Verification and reproducibility

19 v5 invariant groups and 58 integration checks pass; the integration suite includes both original v4 suites (37 checks total) with output paths redirected into Round 4. Full production reconstruction passes for all twelve candidates using the frozen feature snapshots. Future/target score perturbations leave the target predictions unchanged, and conditional B reproduces v4 to below 1e-9. Tests cover missing-date eligibility, substantive leakage rejection, forbidden fields, no zero-filled returning shares, duplicate joins, portal accounting, nested preprocessing, graph/FCS clock, power/HFA identities, cache dependency invalidation and archive guards.

The first development execution had an R negation-precedence error in the new scale objectives. It was invalidated and retained under pre_fix_invalid_run/. The mathematical bug was fixed before any Round 4 conditional scoring; all declarations and selection rules stayed unchanged. Objective-to-prediction equality is now tested. See IMPLEMENTATION_CORRECTION.md. These invalid results must not be cited as evidence.

A future-game archive was actually created under prospective/, with prediction and information times, team IDs, neutral status, feature snapshot IDs/hashes and design hash, and no outcomes or market columns. Exclusive create, digest and read-only permissions provide local append-only practice; a filesystem owner can still alter files, so no hardware-WORM claim is made.

Use COMMANDS.md for exact reproduction and operational commands. design_frozen.rds contains the selected policy and fitted parameters; pre_selection_manifest.csv and pre_conditional_manifest.csv preserve stage hashes. diagnostics.png was visually inspected. Full formulas and limitations are in MODEL_SPEC.md and FEATURE_AUDIT.md.

## Decision boundary

This successor earns **development advancement**, not a claim of market superiority or fully verified historical vintage. It retains early-period uncertainty, strong prior dependence, uncertain historical feature revisions, and only three development seasons. Prospective performance and stronger historical provenance remain the most useful next evidence.
