# Round 7 report — JP+-style play-by-play efficiency challenger

**Status: COMPLETED NEGATIVE EXPERIMENT. NOT PROMOTED.**

The challenger was fully implemented, fitted on real play-by-play across eight
walk-forward holdout seasons, and evaluated against the frozen `v5_EB_features`
incumbent on identical game identifiers. It is **worse than the incumbent**, by a
margin that is outside season-bootstrap noise, on both the development and the
conditional splits. 13 of 20 frozen promotion gates fail. Nothing was promoted, and
no production file, public export or dashboard was touched.

Predeclaration SHA-256 `f3610ba0faed78588a0a1137b64db636a0f37da0c9d0cfed790be842f4fe828a`
(Amendments 1–3; hash chain in `predeclaration.sha256`).
Forward spec SHA-256 `906f84b6cff13939a1a2bfdadf0fae6f6a7137501a9cf81475366dce70f8a31f`.
All three amendments were declared while the candidate ledger was unfitted and both
prediction CSVs were headers-only, so none of them can have been chosen to favour a
result. Amendment 3 was written during this session and is described below.

## Headline result

Locked candidate **v7_07** (ridge lambda 1, half-life 56 days, prior k 4, raw EPA),
selected identically in every nested fold. Positive `paired MAE delta` means the
challenger is **worse**.

| Split | n | Challenger MAE | Incumbent MAE | Paired delta | 95% season bootstrap |
|---|---|---|---|---|---|
| Development (2019, 2021, 2022) | 2,320 | 13.298 | 12.939 | **+0.359** | [+0.013, +0.641] |
| Conditional (2023–2025) | 2,398 | 12.774 | 12.518 | **+0.256** | [+0.198, +0.361] |
| Development, cross-tier | 268 | 14.259 | — | **+0.259** | [+0.073, +0.616] |
| Conditional, cross-tier | 318 | 13.709 | — | **+0.664** | [+0.298, +0.886] |

Both bootstrap intervals lie entirely above zero. This is not a near-miss that more
data would rescue; the challenger is reliably behind. The gate required a **0.25
point improvement**, and the challenger delivered a 0.26–0.36 point **regression**.

Straight-up accuracy is the one place the challenger is not clearly behind: 0.722 vs
0.709 in development, 0.714 vs 0.719 conditional. Ordering teams and forecasting
margins are different tasks, and only the margin task was gated.

## Why it lost

**1. The forecasts are under-dispersed.** Challenger calibration slope is 1.30–1.38
in every season; the incumbent sits at 0.98–1.13. Predicted margins have standard
deviation 9.3 against an actual 20.7. The earlier-only ridge mapping from
opponent-adjusted efficiency to points shrinks hard — ridge in the team-effects solve,
ridge again in the points mapping, and the preseason blend on top — and nothing in the
declared design restores scale. A slope of 1.33 means the model is systematically
too timid, and MAE pays for it on exactly the games where the signal is strongest.

**2. Accuracy degrades as the efficiency signal takes over.** This is the most
informative diagnostic in the run, and it speaks directly to the research question:

| Minimum games played | Development paired delta | Conditional paired delta |
|---|---|---|
| 0 (pure preseason prior) | **−0.179** (better) | −0.009 (tied) |
| 1 | +0.289 | +0.001 |
| 2–3 | +0.216 | +0.569 |
| 4+ | **+0.459** (worse) | +0.229 |

With zero games played the challenger is running on the inherited incumbent prior and
is level with or slightly ahead of the incumbent. The more opponent-adjusted
play-by-play efficiency it blends in, the further behind it falls. In this
implementation the efficiency signal is not merely failing to beat final-score
margin — it is actively displacing something better.

**3. Cross-tier games are badly biased.** In P4/P5-versus-G5 games the challenger's
bias is −4.89 (development) and −3.90 (conditional) points: it under-rates the
favourite. The incumbent's known cross-tier defect was supposed to be the challenger's
opening, and instead the challenger widens it. The Big Ten-minus-Mid-American
conference gap grows from 3.19 to 3.89 points in development (gate needed a 0.25
*reduction*; it got a 0.70 increase) and shows the same direction conditionally.

**4. Nothing in the hyperparameter grid mattered.** Pooled MAE across all 36
candidates spans 13.162 to 13.349 — a range of 0.19 points, smaller than the deficit
to the incumbent. Mean MAE by EPA treatment: raw 13.252, clip 13.256, clip-then-0.5x-
turnover 13.264. **The predeclared robust-EPA treatments are indistinguishable from
raw EPA.** No turnover-luck claim of any kind is supported by this run. The
turnover-heavy diagnostic bucket (4+ realised turnovers) is the single bucket where
the challenger edges ahead conditionally (−0.048), on 415 games — far too thin to
mean anything, and it is a realised-outcome bucket, not a predictive result.

## What was actually built and run

- **1,061,478 eligible plays in 9,449 games**, from 1,762,776 raw rows across 2014–2025
  (2020 excluded throughout, no sensitivity). Per-season counts in `source_coverage.csv`,
  per-reason counts in `exclusion_reasons_by_season.csv`.
- **11 expected-points models**, one per target season, each trained only on seasons
  strictly earlier than its target and frozen before that season's first forecast
  cutoff. Training sets grow 110,121 → 1,241,002 states. Eleven distinct model hashes
  are recorded in `FEATURE_PROVENANCE_MANIFEST.csv`. **No vendor EPA, PPA or win
  probability field is read anywhere in Round 7** — the earlier plan to consume
  cfbfastR EPA was abandoned because that model is trained through 2025 and would
  leak into every replay cutoff.
- **36 candidates, all fitted**, each scored on the identical 6,266-game universe
  across eight holdout seasons (2017–2019, 2021–2025).
- **Nested forward selection**: each outer development season picks hyperparameters
  using only strictly earlier inner holdouts; the final candidate is locked on
  development evidence through 2022 and only then scored on 2023–2025. v7_07 won
  every fold, so the lock is not a knife-edge.
- **Coverage is 100%** of incumbent game identifiers in all six evaluated seasons
  (gate required 95%).
- **Priors** are the inherited, legally dated `v5_EB_features` preseason components,
  recovered through the incumbent's own `v5_components()`. The 2019 replay reproduces
  the saved snapshot to within 1e-10 (`prior_reproduction.csv`); 2017 is rebuilt from
  Round 6's expanded 2013-start history.

## Amendment 3, and a data defect worth recording

The first implementation lagged CFBD's post-play scoreboard directly. Administrative
rows — Kickoff, Kickoff Return, Timeout, Penalty, End of Half — report the scoreboard
as of *before* the preceding scoring play. Game 401403853 (2022) shows a Vanderbilt
touchdown row correctly at 21, then the very next kickoff-return row back at 14.
Lagging that stale row fabricates a second touchdown on the next scrimmage play and
condemns the game as nonmonotone. That reader defect was discarding **30% of 2014
games and 58% of 2025 games**.

Amendment 3 reconstructs each team's scoreboard as a running cumulative maximum
(football scores never decrease), marks rows reporting below that maximum as stale,
and adds a gate that did not previously exist: **a game is eligible only if its
reconstructed final score equals the official final score for both teams**. Game loss
fell to 0.8–7.9% per season, and the surviving games are now verified against an
independent source rather than a heuristic. A second defect was found in the same
pass: the 2013 source uses a legacy play-type vocabulary (`Pass Completion`,
`Pass Interception`, touchdowns folded into `Rush`/`Pass`, sacks not broken out), and
the code's allowlist enumerated only the modern synonyms. The declared rule —
"unequivocal rush, pass, sack and interception classifications" — always covered both;
the enumeration was incomplete. Fixing it raised 2013's usable states from 78,386 to
110,121 and materially improved the earliest EP model. The complete vocabulary and
the disposition of every play type is in `play_type_inventory.csv`.

Neither correction changed a rule, a hyperparameter, a candidate or a threshold.

## Honest limitations

- **Three development outer seasons, not four.** The frozen gate requires four and
  this run yields 2019, 2021 and 2022 only: 2013 seeds the EP model, 2014 is the
  earliest EP-scored season, three earlier mapping seasons make 2017 the earliest
  candidate holdout, and two inner holdouts make 2019 the earliest outer season. That
  gate was *not* relaxed to fit the data, and it fails independently of performance.
  The point is moot here — the challenger loses on every performance gate too — but if
  a future variant did win, this gate would still block it until the history extends.
- **Availability is a scheduled proxy, not observed publication** (Amendment 1).
  Eligibility means "scheduled and reported complete", never "publication observed".
- **Fumble plays are excluded entirely.** CFBD's fumble classifications do not state
  the underlying scrimmage play, so the declared allowlist drops them (16,476 rows).
  The consequence is that interceptions are the only turnovers in the eligible set,
  which structurally weakens every turnover-treatment candidate. This is a design
  limitation of the declared rule, not a bug, and it should be reconsidered before any
  future turnover work.
- **The EP instrument is deliberately weak and was not tuned.** 60 rounds, depth 3,
  eta 0.08, frozen in the forward spec with "no EP hyperparameter search". Measured
  out-of-sample calibration on 2014 is good in the middle of the range and shrunk at
  the tails (predicted 4.56 vs realised 5.21 in the top bin). A stronger EP model
  might change the result; testing that requires a new predeclaration, not a quiet
  edit to this one.
- **Special teams, the totals model and the betting-selection engine were not built.**
  The instruction was to run the baseline before adding them, and the baseline failed.
  Building them on top of a losing baseline would produce numbers, not evidence.
  `special_teams_rating` is a structural zero everywhere, an omitted component and not
  an estimate of average performance.
- Overtime is excluded from labelling, fitting and scoring throughout.

## Market benchmark

Read only after the predictions were written and hashed, and gated on re-verifying
those hashes. Details and caveats in `MARKET_BENCHMARK.md`. Summary: on 2,398 shared
conditional games the market's MAE is 11.998, the incumbent's 12.518 and the
challenger's 12.774 — both models trail the market, and the challenger trails it by
more. **2,369 of 2,398 "lines" are derived multi-book medians, which are not
executable prices.** The source carries no spread prices at all, so **no ROI is
computed or claimable**. The predeclared selection rule (edge ≥ 3 points *and* an
earlier-only 80% interval wholly beyond the line) qualified exactly 1 bet in 2,398,
which lost. No threshold was tuned. Nothing here influenced selection or promotion.

## Verdict

The JP+-style substitution tested here — replacing the current-season score-margin
signal with opponent-adjusted Success Rate and EPA per play — **does not work in this
configuration**, and the failure is informative rather than ambiguous: the model is
systematically under-dispersed, and it gets worse precisely as the efficiency signal
displaces the prior. The incumbent stays frozen and in production.

The most promising follow-up is not another hyperparameter sweep, which this run shows
to be inert, but the dispersion defect: an earlier-only scale calibration, a stronger
EP instrument, and a re-examination of the fumble exclusion. Each of those requires a
fresh predeclaration before any fitting.

## Reproduction

```
Rscript tests/test_v7.R && Rscript tests/test_v7_forward.R
Rscript archive/v7-round7/code/scripts/run_round7_forward.R      # stages 1-4, ~20 min, cached per stage
V7_TESTS_PASSED=1 Rscript archive/v7-round7/code/scripts/report_round7.R
Rscript archive/v7-round7/code/scripts/provenance_round7.R
Rscript archive/v7-round7/code/scripts/market_benchmark_round7.R # post-freeze only, verifies hashes first
```
