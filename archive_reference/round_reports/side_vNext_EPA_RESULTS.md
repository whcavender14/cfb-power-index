# Local vNext evaluation: 2023–2025

## Decision

Retain the incumbent. The frozen EPA challenger has worse paired margin MAE in this conditional evaluation.

The paired Big Ten-minus-MAC residual gap is 1.901 points for the incumbent and 1.756 for vNext.
The 2024–2025 season-frozen gap is 2.362 for the incumbent and 2.432 for vNext; the 2025-only gap is 2.760 and 3.157 respectively. This run does not establish closure of the conference defect.

## Paired game-margin and closing-spread metrics

| scope | model | n | margin_mae | margin_rmse | n_market | closing_mae | closing_rmse |
| --- | --- | --- | --- | --- | --- | --- | --- |
| pooled | incumbent | 2245.000 | 12.530 | 15.831 | 2245.000 | 3.312 | 4.304 |
| pooled | vNext | 2245.000 | 13.446 | 17.041 | 2245.000 | 6.010 | 7.972 |
| season_frozen_2024_2025 | incumbent | 1606.000 | 12.475 | 15.755 | 1606.000 | 3.375 | 4.394 |
| season_frozen_2024_2025 | vNext | 1606.000 | 13.468 | 17.055 | 1606.000 | 6.283 | 8.357 |
| 2023 | incumbent | 639.000 | 12.668 | 16.022 | 639.000 | 3.153 | 4.067 |
| 2023 | vNext | 639.000 | 13.389 | 17.005 | 639.000 | 5.325 | 6.913 |
| 2024 | incumbent | 798.000 | 12.732 | 16.005 | 798.000 | 3.525 | 4.597 |
| 2024 | vNext | 798.000 | 13.238 | 16.859 | 798.000 | 6.035 | 8.104 |
| 2025 | incumbent | 808.000 | 12.221 | 15.504 | 808.000 | 3.228 | 4.184 |
| 2025 | vNext | 808.000 | 13.696 | 17.246 | 808.000 | 6.528 | 8.599 |

Closing metrics use provider consensus where available, otherwise the explicitly derived median of at least two books. They measure disagreement with the market, not error against the final score. Both models use identical game IDs in each row pair.
Of the paired quoted games, 2245 use derived book medians and 0 use provider-labeled consensus. The full saved file contains 29 direct consensus rows; availability there does not imply coverage of the paired evaluation.

## ATS and hypothetical ROI

| scope | model | ats_wins | ats_losses | ats_pushes | no_bets | ats_win_rate | roi_minus110 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| pooled | incumbent | 1112.000 | 1087.000 | 46.000 | 0.000 | 0.506 | -0.034 |
| pooled | vNext | 1137.000 | 1062.000 | 46.000 | 0.000 | 0.517 | -0.013 |
| season_frozen_2024_2025 | incumbent | 791.000 | 782.000 | 33.000 | 0.000 | 0.503 | -0.039 |
| season_frozen_2024_2025 | vNext | 820.000 | 753.000 | 33.000 | 0.000 | 0.521 | -0.005 |
| 2023 | incumbent | 321.000 | 305.000 | 13.000 | 0.000 | 0.513 | -0.021 |
| 2023 | vNext | 317.000 | 309.000 | 13.000 | 0.000 | 0.506 | -0.033 |
| 2024 | incumbent | 384.000 | 397.000 | 17.000 | 0.000 | 0.492 | -0.060 |
| 2024 | vNext | 420.000 | 361.000 | 17.000 | 0.000 | 0.538 | 0.026 |
| 2025 | incumbent | 407.000 | 385.000 | 16.000 | 0.000 | 0.514 | -0.019 |
| 2025 | vNext | 400.000 | 392.000 | 16.000 | 0.000 | 0.505 | -0.035 |

Win rates and ROI are fractions. One unit risked per nonzero model edge; every quoted paired game is considered; no optimized threshold. Pushes return stakes, no-edge games are no bets. ROI = profit / total staked, including pushes in staked units. Wins return 100/110 profit; losses lose one unit.
**ROI assumes −110 on every spread. Actual ATS prices are unavailable, so realized/executable ROI cannot be calculated. Consensus/median lines may not be available at a single book.**

## Conference residual audit

| scope | model | big_ten | mac | gap |
| --- | --- | --- | --- | --- |
| original_2398_games | incumbent | 0.762 | -1.389 | 2.151 |
| 2023 | incumbent | 0.011 | -0.551 | 0.562 |
| 2023 | vNext | -0.341 | -0.093 | -0.249 |
| 2024 | incumbent | 0.780 | -1.175 | 1.954 |
| 2024 | vNext | 1.007 | -0.682 | 1.689 |
| 2025 | incumbent | 1.197 | -1.563 | 2.760 |
| 2025 | vNext | 1.672 | -1.485 | 3.157 |
| pooled | incumbent | 0.758 | -1.143 | 1.901 |
| pooled | vNext | 0.943 | -0.813 | 1.756 |
| season_frozen_2024_2025 | incumbent | 0.987 | -1.374 | 2.362 |
| season_frozen_2024_2025 | vNext | 1.338 | -1.095 | 2.432 |

Residual is actual minus predicted, from each team’s perspective. The original 2.151-point figure uses all 2,398 incumbent games. The pooled paired comparison excludes vNext warm-up games and uses the same remaining games for both models. Do not compare different samples as if they were identical.

Direct Big Ten–MAC matchups, oriented toward the Big Ten:

| model | n | big_ten_outperformance |
| --- | --- | --- |
| incumbent | 24.000 | 6.321 |
| vNext | 24.000 | 12.105 |

## Coverage and temporal validation

| season | scheduled | scored | warmup | paired | paired_with_lines | paired_provider_consensus | paired_derived_median |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 2023 | 792 | 639 | 153 | 639 | 639 | 0 | 639 |
| 2024 | 798 | 798 | 0 | 798 | 798 | 0 | 798 |
| 2025 | 808 | 808 | 0 | 808 | 808 | 0 | 808 |

2023 uses expanding earlier-week calibration after 100 completed archived observations; the initial warm-up games remain unavailable. The 2024 mapping is frozen at season start using 2023, and the 2025 mapping uses 2023–2024. Ratings at every Monday cutoff use only earlier completed games. No game is evaluated using a whole-season fit that includes itself.
The 2024–2025 season-frozen subset is reported separately. This is temporal out-of-sample scoring on previously exposed conditional seasons, not a fresh untouched model-selection holdout. Defaults were not tuned against these results.

Training evidence is unavailable for 381 of 808 FBS/FBS games in 2025 because the terminal timestamp is missing or implausible. This is a major information disadvantage versus the incumbent; the comparison evaluates the pipeline as implemented, not the isolated causal value of EPA or hierarchical shrinkage.
All preseason EPA priors are zero. The incumbent has established preseason priors; this challenger does not. Early-season compression is therefore a substantive limitation, not evidence that EPA is inherently inferior.

## Source and feature quality

| season | schedule_fbs_games | matched_raw_rows | classified_scrimmage | invalid_scrimmage | valid_scrimmage | games_valid_terminal | games_without_valid_terminal | identical_play_rows_removed | total_scrimmage | retained | excluded |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2023 | 792 | 139063 | 103976 | 253 | 103723 | 656 | 136 | 0 | 85995 | 79492 | 6503 |
| 2024 | 798 | 142016 | 104717 | 358 | 104359 | 680 | 118 | 45 | 89000 | 81702 | 7298 |
| 2025 | 808 | 144080 | 106289 | 403 | 105886 | 427 | 381 | 0 | 55973 | 51131 | 4842 |

The pipeline reads the original cfb_data/pbp_2023.rds through pbp_2025.rds and games_2023.rds through games_2025.rds. Source hashes are saved. FBS/FBS games match incumbent scope. Missing or implausible terminal wallclocks exclude games from training; no end times are invented. Such games may still be forecast and scored against their known final outcome. Invalid scrimmage rows and their denominators are reported.
Primary garbage-time filtering uses pre-snap margin: >38 Q2, >28 Q3, >22 Q4; overtime is excluded. Separate WP-filtered feature files retain [0.05,0.95] and report missing WP. WP aggregates are descriptive sensitivity outputs, not selected or used in primary forecasts. Embedded market fields are never model inputs.
The cached EPA/WP model training vintage is unknown; retrospective provider model revisions remain a limitation. Therefore the results are conditional on the supplied EPA values, not a guarantee of historically available EPA-model vintages.
45 identical play rows were removed only after matching all normalized fields, event text, and wallclock. Duplicate-play CSVs preserve the removed records. The normalizer still rejects conflicting play keys.
Opponent-adjusted overall/pass/rush EPA and overall/standard/passing-down success ratings are saved in fits_YEAR.rds. The frozen points mapping uses overall/pass/rush EPA, overall success, and site; standard/passing-down ratings are diagnostics. EPA cap ±4, turnover multiplier 0.5, 8-week half-life, and hierarchy penalties 8/2/1 remain frozen.

## Closing-line provenance

| season | benchmark_type | games |
| --- | --- | --- |
| 2023 | derived_median_books | 831 |
| 2024 | derived_median_books | 825 |
| 2025 | derived_median_books | 928 |
| 2023 | provider_consensus | 29 |
| 2024 | provider_consensus | 0 |
| 2025 | provider_consensus | 0 |

The [CFBD API documentation](https://github.com/CFBD/CFBSharp/blob/master/docs/BettingApi.md) describes /lines as closing betting lines. We use spread, not spread_open, and verify its home-side sign against formatted_spread. No exact quote time or spread prices are supplied. Conflicting provider/game quotes are quarantined; repeated identical quotes are deduplicated. The saved RDS retains direct consensus and derived medians separately.

## Paired uncertainty

| delta | lower | upper | one_sided_upper | seasons |
| --- | --- | --- | --- | --- |
| 0.916 | 0.506 | 1.475 | 1.261 | 3.000 |

Intervals resample whole seasons (2,000 draws, seed 7101). With only three season blocks these intervals are descriptive and cannot establish a stable small edge. No 2026 data, market targets, or conditional-loss tuning was used.

## Reproduce

```sh
Rscript archive/vnext-epa/code/scripts/run_vNext_local.R
Rscript archive/vnext-epa/code/scripts/ingest_vNext_betting_lines.R
# Force provider refresh: VNEXT_REFRESH_LINES=true Rscript archive/vnext-epa/code/scripts/ingest_vNext_betting_lines.R
Rscript archive/vnext-epa/code/scripts/report_vNext_local.R
Rscript tests/test_vNext_local.R
```

Production vCurrent, published ratings, and the website are unchanged.

## Final audit disposition

This audit is complete for the local 2023--2025 inputs. The candidate does not
advance: on the 2,245 identical scored games, its paired MAE is 0.916 points
higher than the incumbent's. The season-block bootstrap interval for that
increment is +0.506 to +1.475 points, so the observed regression is not a
small-sample tie. The 2024--2025 frozen-mapping subset reaches the same
decision.

The historical market artifact is complete as a local benchmark: it contains
2,613 unique game IDs, a checked home-side spread, source/provider fields, and
a per-request cfbfastR provenance manifest. It contains 29 provider-labelled
consensus lines; all paired model comparisons use the separately labelled
multi-book median. Treat both as historical closing-line benchmarks, not as
executable odds. Actual spread prices are absent, so the reported ROI remains a
uniform -110 sensitivity calculation.

No production model, public JSON, or dashboard export is pending because this
candidate failed the advancement check. The following local research artifacts
are deliberately ignored by Git and would need an explicit export decision
before sharing or versioning: `cfb_data/betting_lines_2023_2025.rds` and
`outputs/vNext/local_2023_2025/`. The implementation, tests, scripts, and this
report are currently untracked; a summary commit is pending if the repository
should retain the vNext experiment.
