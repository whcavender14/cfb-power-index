# Round 3 results — modest MAE gain; final standard not met

The development-selected successor is **B, a convex blend with an explicitly calibrated preseason mean**. On the one-shot 2023–2025 evaluation it achieves **12.830 MAE**, compared with **12.938 for v3 under the same freeze policy** and **12.019 for the matched market benchmark**. All three outer seasons improve against the frozen baseline, but the gain is only **0.108 points**. A broader season/period bootstrap includes zero. This is a research candidate, not a claim that the requested production standard has been achieved.

The original supplied v3 result was 12.947. Its tuning policy differs, so the principal paired comparison uses a reconstructed frozen v3 baseline. Relative to the supplied headline the numerical reduction is 0.117, but that is not the clean same-policy comparison.

The new model has no preseason blend coefficient above one and no one-game jump to full current weight. However, calibration slope worsens to **1.184**, early bias persists, and conference residual differences remain. Prior-year ordering remains highly influential. Do not promote B merely because its ratings look more plausible.

## Audit findings

See AUDIT.md for confirmed defects, mathematical behavior and hypotheses. The main confirmed policy issue is v3's use of earlier outer years in subsequent candidate selection. A separate FCS-clock counting defect affects its pooled candidate. The preseason amplification is mathematically real, but compensation for ridge attenuation means coefficients above one cannot be classified as erroneous solely by their size.

The 2025 HFA estimate changes from 3.140 at ridge 0.1 to 4.377 at ridge 6 on the same games. Strong shrinkage and home-schedule composition explain a substantial part of the discrepancy with predictive HFA near 3.07; this is not a reason to raise production HFA.

## What was locked, and what remains a limitation

PREDECLARATION.md was written before any successor outer result was computed. Development used expanding forward forecasts: historical score fitting starts in 2015; preseason target regressions start in 2016; component forecasts start in 2018. The 2021 inner holdout calibrates on 2018–2019; the 2022 holdout adds 2021. All candidates see the same 1546 development games. 2020 is excluded as a calibration/regression outcome, while its preceding-season score information remains available to 2021.

After development, all candidate choices, handoff parameters, preseason-regression coefficients and HFA calibration were fixed through 2022. Previous completed-season score ratings remain admissible next-season inputs under the fixed method; current results update subsequent weeks only after the assumed availability time. No outer outcome enters tuning or candidate selection. No market field enters any estimator or production artifact.

The original supplied outer summaries were already known and motivated this requested audit. Thus this is a locked **one-shot conditional evaluation**, not a pristine independently blinded discovery sample. The source schedules are retrospective snapshots and kickoff+24 h is an assumed result availability rule. There is no independent historical snapshot authentication. Further changes informed by this report require a later untouched test period.

There are 792 games in 2023,798 in 2024 and 808 in 2025: all 2398 completed FBS–FBS games in the supplied schedule universe, regular and postseason, including overtime. Forecast cutoffs are Monday 00:00 UTC calendar periods, not provider week numbers. No target game or same-period future result is in a fit. All serious candidates use exactly this universe.

## Development results and fixed choice

| candidate | n | mae | rmse | bias | cor | calib_slope | su_rate |
| --- | --- | --- | --- | --- | --- | --- | --- |
| A | 1546 | 13.337 | 16.748 | 0.707 | 0.573 | 0.947 | 0.697 |
| B | 1546 | 13.297 | 16.699 | 0.615 | 0.578 | 1.087 | 0.690 |
| C | 1546 | 13.398 | 16.803 | 0.698 | 0.569 | 1.060 | 0.686 |
| D | 1546 | 13.465 | 16.946 | 0.426 | 0.571 | 1.274 | 0.702 |
| baseline | 1546 | 13.456 | 16.901 | 0.811 | 0.565 | 0.907 | 0.695 |
| no_prior | 1546 | 14.219 | 18.236 | -0.058 | 0.493 | 1.698 | 0.668 |
| pre_only | 1546 | 14.507 | 18.190 | 0.500 | 0.457 | 0.900 | 0.646 |

B was selected because it improved both development seasons, had the best pooled primary MAE, and was simplest under the declared .05 tolerance order. A was also eligible but did not displace it. C was more than .05 behind B. D failed season stability. The two-season cluster interval used by the declared screen is weak evidence; the later reported period-block sensitivity is broader. No selection was changed after outer evaluation. The declared secondary-selection gate did not open because C/D did not win. The already-defined secondary specifications were later audited on development only, outside the primary execution protocol; see SECONDARY.md. They did not change the frozen model or receive outer evaluation. Optional-feature experiments were ineligible for lack of verified vintages.

MODEL_SPEC.md contains exact formulas; candidate_ledger.csv contains formulas, parameters, availability, training windows, metrics and reasons. CANDIDATES.md is a compact human-readable ledger.

## Locked outer results

| candidate | n | mae | rmse | bias | cor | calib_slope | su_rate |
| --- | --- | --- | --- | --- | --- | --- | --- |
| A | 2398 | 12.829 | 16.219 | -0.616 | 0.596 | 1.066 | 0.714 |
| B | 2398 | 12.830 | 16.280 | -0.650 | 0.598 | 1.184 | 0.717 |
| C | 2398 | 12.866 | 16.308 | -0.576 | 0.598 | 1.222 | 0.709 |
| D | 2398 | 13.117 | 16.700 | -0.940 | 0.585 | 1.387 | 0.717 |
| baseline | 2398 | 12.938 | 16.331 | -0.532 | 0.587 | 1.002 | 0.709 |
| no_prior | 2398 | 14.066 | 18.042 | -1.468 | 0.496 | 1.704 | 0.695 |
| pre_only | 2398 | 13.955 | 17.717 | -0.734 | 0.482 | 1.135 | 0.655 |

Straight-up rates in this table are fractions. Bias is prediction minus actual home margin. Calibration slope comes from actual~predicted with an intercept; it is a diagnostic, never an instruction to rescale the published ratings.

| candidate | season | n | mae | rmse | bias | calib_slope |
| --- | --- | --- | --- | --- | --- | --- |
| B | 2023 | 792 | 12.921 | 16.436 | -0.043 | 1.180 |
| B | 2024 | 798 | 13.058 | 16.415 | -0.644 | 1.129 |
| B | 2025 | 808 | 12.516 | 15.989 | -1.251 | 1.243 |
| baseline | 2023 | 792 | 12.989 | 16.413 | 0.115 | 0.999 |
| baseline | 2024 | 798 | 13.164 | 16.520 | -0.434 | 0.941 |
| baseline | 2025 | 808 | 12.664 | 16.061 | -1.262 | 1.072 |

B's paired seasonal MAE changes are −.067 in 2023, −.107 in 2024 and −.148 in 2025. A's MAE is only .0006 lower overall than B; **that outer result does not authorize switching**. D loses all three outer years, consistent with its development rejection.

| candidate | estimate | low | high | seasons | improved |
| --- | --- | --- | --- | --- | --- |
| A | -0.108 | -0.130 | -0.092 | 3 | 3 |
| B | -0.108 | -0.148 | -0.067 | 3 | 3 |
| C | -0.071 | -0.138 | -0.006 | 3 | 3 |
| D | 0.179 | 0.071 | 0.296 | 3 | 0 |
| no_prior | 1.128 | 0.857 | 1.356 | 3 | 0 |
| pre_only | 1.017 | 0.646 | 1.240 | 3 | 0 |

Above, intervals resample whole seasons. With three seasons these intervals mostly describe variation among the observed years; they are not precise evidence about future seasons. The sensitivity analysis below also resamples calendar-period blocks within sampled seasons. It retains within-period game dependence but does not fully model repeated-team dependence across periods.

| stage | estimate | paired_game_low | paired_game_high | season_period_low | season_period_high |
| --- | --- | --- | --- | --- | --- |
| development | -0.159 | -0.292 | -0.031 | -0.317 | 0.033 |
| locked_outer | -0.108 | -0.214 | -0.000 | -0.231 | 0.014 |

The locked season/period interval for B is roughly **[−.231,+.014]**. The gain is consistent across observed seasons but not decisive under broader sampling uncertainty. Neither a0.03 nor a0.10 gain should be interpreted as a proven structural advance solely from the mean.

## Early-season behavior

| candidate | period_bucket | n | mae | bias | calib_slope |
| --- | --- | --- | --- | --- | --- |
| B | 1 | 13 | 10.681 | -5.857 | 0.792 |
| B | 2 | 123 | 14.709 | -4.528 | 1.431 |
| B | 3 | 149 | 13.754 | -3.839 | 1.531 |
| B | 4 | 153 | 14.676 | -0.845 | 1.649 |
| B | 5+ | 1960 | 12.512 | -0.115 | 1.107 |
| baseline | 1 | 13 | 12.472 | -6.617 | 0.493 |
| baseline | 2 | 123 | 15.094 | -4.040 | 0.881 |
| baseline | 3 | 149 | 13.972 | -3.050 | 1.009 |
| baseline | 4 | 153 | 14.844 | -1.185 | 1.161 |
| baseline | 5+ | 1960 | 12.578 | -0.029 | 0.989 |

B improves MAE in each aggregated period but **does not remove early bias**. Period 2 bias worsens from−4.040 to−4.528, and period 3 from−3.050 to−3.839. Slopes in periods 2–4 are approximately 1.43,1.53,1.65: substantial underdispersion. Period 1 has only 13 games and its apparent gain is especially uncertain.

The bias appears at both home and neutral sites. In period 2, B has home-site bias−4.461 across 111 games and neutral-site bias−5.147 across 12; increasing HFA cannot fix a neutral-site error. Those neutral samples are small. The provider-week/calendar crosswalk, favorite magnitude, prior magnitude, promotion, minimum games played, opponent quality and schedule-network tables are supplied. They are diagnostics, not fitted correction terms. No arbitrary calendar intercept, global HFA increase or final slope multiplication was added.

## Conference and schedule-network evidence

The following are **team appearances**, so each game contributes two rows. A positive signed error means that team's predicted margin is too high; positive/negative conference biases need not indicate a causal conference effect.

| conference | n | mae | bias |
| --- | --- | --- | --- |
| ACC | 575 | 12.570 | -0.426 |
| American Athletic | 494 | 14.018 | 0.797 |
| Big 12 | 544 | 13.358 | -0.798 |
| Big Ten | 615 | 11.971 | -1.405 |
| Conference USA | 367 | 11.528 | 1.755 |
| FBS Independents | 106 | 13.669 | -2.130 |
| Mid-American | 432 | 12.227 | 2.241 |
| Mountain West | 422 | 12.781 | 0.580 |
| Pac-12 | 192 | 14.481 | -0.407 |
| SEC | 552 | 12.297 | -1.847 |
| Sun Belt | 497 | 13.737 | 1.240 |

Conference USA, the MAC, Sun Belt and American still have positive bias. SEC and Big Ten have negative bias. B modestly reduces some of the original differences but **cannot be said to eliminate weak-schedule overrating**. Low cross-conference exposure has higher MAE: B is 14.407 with no distinct cross-conference opponents versus 11.966 with more than 3. This also mixes early-season information scarcity with schedule structure; it is not an identified connectivity effect. D's broad shrinkage damages dispersion and does not validate a blanket uncertainty discount.

Files include conference-by-season results; distinct FBS-opponent, P4/Pac-12 historical-power-opponent, component-size, cross-conference, FCS-exposure, one-score concentration, prior-variance and opponent-quality buckets. The historical power-conference label includes Pac-12 for its earlier structure and is used only descriptively. Conference labels never enter B. No subjective G5 penalty or SOS bonus is applied.

## Ratings and zero/one-game teams

ZERO_ONE.md reports all named examples, exact contributions, sample counts and limitations. zero_one_game_teams.csv contains every primary candidate's zero/one-game rows; production_all_candidates.csv contains all 138 teams for each candidate. off_rating−def_rating equals power_rating throughout, and current+prior+common-centering contributions reconstruct power exactly.

Selected B rates Indiana 19.142, Ohio State 17.625, James Madison 6.493, South Florida 6.484 and Old Dominion 4.538 at the fixed 2026-09-09 cutoff. These are changes from a model experiment, not evidence of real offseason improvement/decline. James Madison and South Florida remain mostly prior-driven. B's power SD is 7.377 versus frozen-v3 SD 10.066. Its correlation with prior finish is.961, so compressed amplitudes must not be presented as solved carryover dependence.

The exact scalar B weights on calibrated prior/current are 1/0 at zero games, .708/.292 at one, .548/.452 at two, .447/.553 at three, .288/.712 at six and .168/.832 at twelve. For EB candidates, scalar schedules are conditional illustrations; the exact joint update uses matrix weights. Both the formulas and this distinction are documented.

## Matched market benchmark

| candidate | n | coverage | model_mae | market_mae | delta_mae |
| --- | --- | --- | --- | --- | --- |
| B | 2398 | 1 | 12.830 | 12.019 | 0.811 |
| baseline | 2398 | 1 | 12.938 | 12.019 | 0.919 |

Source is the supplied CFBD latest-available benchmark export. Provider counts: DraftKings 2246, Bovada 123, consensus 29. No independent closing timestamp verification exists. Latest-available semantics do not establish historical closing lines. The benchmark covers 100% of the 2398 model games, uses `market_margin=−home_spread`, and was joined only after the frozen design and saved outer predictions. The model-market delta is **+.811**; the season-cluster interval is approximately[+.691,+.983]. Paired seasonal model/market MAE tables and provider coverage are included. Lines were not used to fit, select, rescale or produce ratings.

## Feature ablations and unfinished objectives

FEATURES.md and feature_inventory.csv document every cached feature season and why optional inputs remained disabled. Event dates were not relabeled as publication dates, unavailable years were not zero-filled, and target-season starters/coaches were not inferred from participation or wins. No valid feature-effect estimate can be claimed from these caches.

The score-only ablations show useful preseason information: zero-prior C has 14.066 outer MAE; preseason-only has 13.955; C has 12.866. Their seasonal variation and paired intervals are supplied. These do not estimate the value of QB continuity or any unavailable feature. EPA, garbage-time processing and game-context experiments remain unperformed because no admissible implementation was advanced. The declared secondary C selection was gated out. A supplementary development-only audit subsequently tested the six fixed specifications, explicitly outside the primary execution protocol. C4 had development MAE 13.244, a small .053 improvement over B; it is not substituted after viewing the primary outer report. See SECONDARY.md for all metrics and the protocol-deviation disclosure.

The final requested standard is **not met**: the market gap remains substantial; gain uncertainty crosses zero under block resampling; early bias and underdispersion remain; prior-finish dependence and weaker-conference residual bias remain. B is a coherent, reproducible candidate suitable for prospective evaluation. There is no evidence here to authorize an outer-informed retuning while continuing to call 2023–2025 untouched.

## Reproducibility and deliverables

- cfb_power_ratings_v4.R is separately versioned; its v4_* entry points implement the new models. Legacy v3 helpers remain for comparison. Use cfb_v4_operations.R and the exact commands in COMMANDS.md; do not call inherited v3 build/tune functions by mistake.
- run_round3.R implements development/freeze and outer evaluation. The freeze refuses reselection if its artifact exists and outer execution checks the source hash.
- 25 unit/invariant tests and 12 integration checks pass, including full production reconstruction for all primary candidates, target exclusion, future-score counterfactual, timestamp/provenance rejection, HFA once-only, zero/one handling, disconnected graphs, FCS clock, near-rank deficiency, deterministic cache behavior and source integrity.
- A dated prospective prediction archive was actually created for future games only. It excludes outcomes and market fields, refuses overwrite, has integrity digests and read-only file permissions. This is **local append-only practice, not tamper-proof WORM storage**; a filesystem owner can still replace it. A true immutable external store is not configured.
- input_manifest.csv identifies raw inputs and scripts; pre_outer_manifest.csv records the pre-evaluation implementation; design_frozen.rds preserves fitted choices. Development and outer prediction RDS/CSVs retain game IDs and cutoffs; component snapshots retain the exact training rows.

The plots in diagnostics.png and diagnostics.pdf were visually checked. All CSVs and operational artifacts are under outputs/round3. No v3 source, input RDS, or original validation artifact was overwritten.
