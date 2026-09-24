# Decision: retain global HFA

Neither team-specific candidate clears the existing advancement rule. Production code, ratings, frozen designs, reporting and SOS behavior are unchanged. This is a **rejected diagnostic experiment**, not an installed production option.

The comparator is the actual frozen Round 4 `EB_features` / Round 5 `v5_EB_features` incumbent. Its 2,320 development predictions reproduce the archived Round 4 predictions within 1e-9; global mode reproduces the input margins exactly. The function bodies of `v5_ratings`, `v4_score_fit`, `v4_predict`, `v5_fit_parameters` and `v5_calibration` also match `cfb_power_ratings_vCurrent.R` exactly.

## Out-of-sample evidence

Principal development comprises all matched FBS/FBS games, including postseason, from 2019, 2021 and 2022. Negative paired MAE differences favor the candidate.

| Candidate | MAE | RMSE | Bias | HFA-removed slope | MAE difference | Season 95% CI | Season + week 95% CI |
|---|---:|---:|---:|---:|---:|---|---|
| Global | 12.92028 | 16.26838 | 0.51678 | 1.05435 | 0 | — | — |
| Common ridge | 12.91343 | 16.24661 | 0.53535 | 1.04383 | -0.00685 | [-0.01701, -0.00174] | [-0.03051, 0.01574] |
| Empirical Bayes | 12.92028 | 16.26838 | 0.51678 | 1.05435 | 0 | [0, 0] | [0, 0] |

The ridge gain is about 0.053% of incumbent MAE. It fails the required **0.05-point gain** and the **season-plus-week upper bound below zero**. It passes the other requirements: improvement in all three seasons, RMSE improvement, absolute bias deterioration of only 0.01857 (limit 0.10), and improved slope distance from one. The season-only interval is favorable, but both intervals must pass. EB's estimated between-team variance is zero at every season's earlier-only fit, so it fully pools and provides no improvement.

| Season | Games | Global MAE | Ridge MAE | Difference |
|---|---:|---:|---:|---:|
| 2019 | 774 | 12.63778 | 12.63603 | -0.00175 |
| 2021 | 770 | 13.41126 | 13.40952 | -0.00174 |
| 2022 | 776 | 12.71486 | 12.69785 | -0.01701 |
| 2023, conditional | 792 | 12.60443 | 12.56650 | -0.03793 |
| 2024, conditional | 798 | 12.73186 | 12.76903 | +0.03717 |
| 2025, conditional | 808 | 12.22125 | 12.21222 | -0.00904 |

Development home games (2,142): MAE 12.93035 → 12.92293; neutral games (178): 12.79909 unchanged. Neutral predictions are identical, not merely close on average.

The frozen design was written before this runner opened conditional inputs. Across the 2,398 already-exposed 2023–2025 conditional games, ridge MAE is 12.51452 versus 12.51773: difference -0.00320; season CI [-0.03793, 0.03717], season-plus-week CI [-0.05183, 0.05249]. RMSE is 15.77360 versus 15.78748; bias -0.00132 versus -0.04296; neutralized slope 0.99045 versus 1.01474. Conditional home MAE is 12.51544 versus 12.51894; neutral MAE remains 12.50454. These results do not rescue the development failure. They are conditional checks on previously exposed data, not a newly untouched test.

Full RMSE, bias, calibration intercept/slope and counts for each season and home/neutral split are in `development_metrics.csv` and `conditional_metrics.csv`. Both paired bootstrap procedures call the existing `v5_boot` through `v6_advance`: 2,000 replicates, seed 9041, resampled seasons and observed Monday blocks. With only three development seasons, uncertainty remains substantial.

## Formula and fitting

For each game, with the incumbent neutral ratings fixed:

```
prediction = R_home - R_away + applied_HFA
applied_HFA = 0                                      if neutral
applied_HFA = global_HFA + deviation[home_team]       otherwise
```

The global HFA remains the exact incumbent fold-local population baseline. No new venue estimate modifies offense, defensive burden, neutral power, priors or the score-fitting solver. The experimental layer estimates **remaining home prediction error**, using `actual_margin - incumbent_prediction` from archived forward predictions. This residual already removes the incumbent rating contrast and its applicable global HFA once.

For each observed home team, define raw count n, distinct seasons S, distinct opponents O, mean residual m and:

```
q = min(n, 4*S, 2*O) * min(1, 256 / mean(residual^2))
```

The fixed variance scale is 16² points². q limits evidence from one season, a narrow opponent set or unusually large prediction errors. These conservative constants were predeclared, not optimized on outcomes. They are working evidence weights, not claimed exact effective sample sizes or causal identification corrections.

Common ridge minimizes `sum(q*(m-d)^2) + lambda*sum(d^2)`, subject to `sum(d)=0` across observed home teams. Its exact solution is:

```
c = sum(q*m/(q+lambda)) / sum(1/(q+lambda))
d = q*m/(q+lambda) - c/(q+lambda)
```

Unseen teams have d=0; adding them preserves equal-team zero centering. Infinite lambda means all deviations exactly zero. The displayed shrinkage is q/(q+lambda); the CSV also reports the centering correction. Centering is equal-team, not schedule-weighted, so it does not force game-weighted bias to remain unchanged.

Ridge grid, strongest-penalty tie order: Inf, 200, 100, 50, 20. Inner scoring uses only completed earlier forward development seasons (< target and <=2022), rebuilding the deviation at every inner cutoff. The first scoreable season has no earlier eligible residual history: lambda=100 is a fixed cold-start rule. Chosen penalties are 100 for 2019 and 50 for 2021, 2022 and the frozen conditional period. No outer-season result tunes its own lambda. Inner losses and all grid values are in `nested_penalty_validation.csv`.

The EB candidate uses the working normal-means moment estimate `tau²=max(0, var(m)-mean(256/q))`, lambda=256/tau², fitted once using only eligible earlier seasons. Fewer than 20 home teams or tau²=0 gives complete pooling. This is approximate, conservative empirical Bayes; it is not a fitted full stadium/opponent hierarchical likelihood. No rolling candidate was added: the short validation history does not justify another search axis.

## Availability and HFA accounting

Historical score availability follows the repository's conservative convention: kickoff +24 hours, strictly before Monday UTC prediction cutoff. This is an assumed historical availability rule, not independently verified publication metadata. Target IDs are explicitly excluded; exact-cutoff results are excluded. The source prediction must precede kickoff. Fold audits retain training IDs, maximum availability, fitted tables and lambda. Later rows may exist in the input file but never enter a cutoff's fit.

Eligible forward residual history starts in 2019; 2020 is excluded. There is no invented 2018 backfill and no residual from final-season ratings. Weekly team statistics may use earlier results in the current season, while the season's penalty stays locked. Conditional penalties/selection never use 2023+ outcomes; conditional weekly estimates may use already-available 2023+ results, matching live updating. New teams and empty history safely return global HFA.

HFA is accounted for at each distinct stage:

- Existing score fitting subtracts global HFA times hx, where hx is +0.5/home, -0.5/away and zero/neutral. Together the two team-score rows remove one game's global margin advantage. This solver is untouched.
- Residual fitting subtracts the entire incumbent prediction once. The correction is not sent back through score fitting, which would change neutral ratings and double-adjust the experiment.
- Prediction adds only the difference between new and old applied HFA to the incumbent margin. It does not add a second complete HFA.
- Calibration subtracts the same game-specific applied HFA from both predicted and actual margins. Reported `hfa_applied` is exactly zero on neutral games; `global_hfa` is retained separately.
- The isolated SOS helper uses opponent neutral rating minus signed game HFA, with the actual home team's effect for both perspectives. Neutral games contribute no venue adjustment. It does not feed ratings or change production SOS.

This deliberately tests a fixed-rating venue replacement. A jointly refitted strength/venue model would be a different experiment and would not satisfy the requested invariant that changing the home-HFA estimate leaves neutral ratings unchanged.

## Descriptive team examples

These are **rejected ridge estimates**, as of February 1, 2023, after season-2022 postseason results, using frozen lambda=50 and global HFA=3.06854. They are not current 2026 estimates or evidence that team HFA works.

| Team | Estimated HFA | Home games | Effective count q | Residual signal retained before centering |
|---|---:|---:|---:|---:|
| LSU | 4.546 | 18 | 11.302 | 18.4% |
| UMass (Massachusetts) | 1.670 | 13 | 12.000 | 19.4% |
| Ohio State | 4.471 | 22 | 8.170 | 14.0% |
| Boise State | 3.704 | 18 | 12.000 | 19.4% |
| Clemson | 3.292 | 17 | 12.000 | 19.4% |
| Alabama | 3.186 | 18 | 12.000 | 19.4% |

The EB estimates for all these teams equal 3.06854 (100% pooling). LSU's raw home residual mean is +7.394 points; Ohio State's is +9.126; UMass's is -7.810. Large raw residuals should not be interpreted directly as stadium effects. UMass also has a -10.991-point away-oriented residual and Ohio State +7.055, suggesting persistent strength errors can contaminate home estimates. Opponent/season caps and shrinkage temper that problem but do not establish causal separation. The test preserves neutral ratings mechanically; it cannot establish that every residual difference is intrinsically venue-specific.

Use `team_estimates_20230201.csv` for all teams, counts, shrinkage, centering corrections and away-residual diagnostics. The initial example-only artifact had an inconsistent January-1 as-of interpretation; it is retained under `invalid_examples/` and superseded as documented in `EXAMPLE_CORRECTION.md`. No validation result or model decision changed.

`team_hfa_rankings_2022_2025.csv` provides a separate season-end diagnostic ranking for 2022–2025. It uses the already-frozen ridge penalty and is explicitly non-production; its cutoff, interpretation, evidence counts and shrinkage fields are described in `TEAM_HFA_RANKINGS_2022_2025.md`.

## Verification and reproducibility

19 targeted tests passed, covering neutral zero, global equivalence, unseen and empty-history fallbacks, zero centering, small/unusual sample shrinkage, stronger penalties, exact-cutoff and future-score exclusion, earlier-only ridge and EB tuning, historical future-season mutation, neutral rating invariance, one-time prediction/SOS application, HFA-removed calibration, and every development fit's availability bound.

Files added: `team_hfa_experiment.R`, `run_team_hfa.R`, `report_team_hfa.R`, `tests/test_team_hfa.R`, and this isolated output directory. No production file changed. The runner verifies original source/input hashes at completion and refuses to overwrite an existing frozen experiment.

Commands from the project root:

```
Rscript tests/test_team_hfa.R
Rscript report_team_hfa.R
```

For a fresh reproduction, copy the project into a separate writable workspace without the generated team_hfa outputs, retain `outputs/team_hfa/PREDECLARATION.md`, then run `Rscript run_team_hfa.R`, followed by the two commands above. Do not remove or overwrite the existing frozen evidence to rerun selection. Pre-fit input/code hashes, lock timestamps, nested losses, frozen parameters, per-fold audit RDS files and session information are retained alongside the CSVs.

The initial test run stopped because an integer fixture ID was accidentally converted to double, causing a strict identity assertion on metadata to fail. Correcting the fixture's integer literal made the test check the intended future-score invariance; estimator code did not change after scoring.

The evidence supports keeping global HFA. It does not prove that all possible team-HFA specifications fail; the conservative pooling, short residual history and potential strength confounding limit that broader claim.
