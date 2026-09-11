# Round 5 college-football rating development prompt

## Objective

Build a separately versioned successor to the verified Round 4 v5 model. The goal is to improve forecast quality through historically disciplined football information, with the long-run aspiration of narrowing the gap to public market forecasts. It is **not** permission to use betting lines, odds, implied probabilities, market-derived ratings, closing prices, or market-derived transformations as model inputs, preprocessing inputs, calibration inputs, feature-selection inputs, candidate-selection inputs, or production inputs.

The model must earn advancement on earlier-only, matched-game development evidence. It must remain a coherent, matchup-independent neutral-field rating:

```text
power_rating_i = off_rating_i - def_rating_i
neutral_margin(A, B) = power_rating_A - power_rating_B
home_margin(A, B) = power_rating_home - power_rating_away + HFA
```

Preserve this identity. Do not add a free-standing special-teams rating to published power. Special-teams and field-position information may be used only as preseason predictors of offense and defensive burden, or as a predeclared decomposition whose final published ratings still satisfy the identity exactly.

## Materials to read before changing code

1. `cfb_power_ratings_v5.R` and `cfb_v5_operations.R`.
2. `outputs/round4/REPORT.md`, `MODEL_SPEC.md`, `FEATURE_AUDIT.md`, `CALIBRATION_DECISION.md`, `FEATURE_ABLATIONS.md`, and `MARKET_BENCHMARK.md`.
3. `outputs/round4/candidate_ledger.csv`, `FEATURE_PROVENANCE_MANIFEST.csv`, `DERIVED_FEATURE_PROVENANCE_MANIFEST.csv`, feature coverage/routing files, optimizer diagnostics, and all test files.
4. `run_2026_rankings.R` and `validate_v5_public.R`.
5. The v4 and Round 3 artifacts as implementation history only; do not alter them.

The Round 4 selected incumbent is `EB_features`: a precision-4 joint offense/defensive-burden score update with season-appropriate historical talent, returning-production, and eligible coaching features. Its 2019/2021/2022 matched development MAE is 12.920 versus 13.238 for pure-score B. Its 2023–2025 result is a secondary conditional test, not a fresh outer test. Do not use its outcomes to choose a feature, bucket, transformation, penalty, or candidate.

The 2026 prospective archive and 2026 results are reserved for prospective evaluation. Do not use any completed or future 2026 outcome to develop, tune, choose, recalibrate, or remove a Round 5 candidate. Continue generating immutable 2026 prediction archives before games start.

## Non-negotiable timing and market rules

* Freeze every candidate family, feature definition, source eligibility rule, transform, missingness treatment, regularization grid, advancement rule, bootstrap, and simplicity order before fitting.
* Development outcomes are through 2022 only. Use all eligible expanding forward folds beginning with the earliest season supported by a candidate's historical coverage; report at least 2019, 2021, and 2022 on the identical final FBS-versus-FBS game IDs, including postseason.
* Treat 2023–2025 as secondary conditional scoring only. It may be reported after freeze, but cannot affect selection or revisions.
* Treat 2026 as prospective only. Never backfill a pregame prediction after a game starts.
* Retain the global preseason cutoff: immediately before the first FBS kickoff in each target season. Use Monday UTC operational cutoffs and only results available before the prediction cutoff.
* Fail closed for substantive future-information leakage. Do not fail closed merely because an exact historical publication timestamp cannot be recovered.
* Historical dates may be blank. Never replace missing historical publication time with retrieval time, cache time, file modification time, `cfbfastR_timestamp`, a transfer event date, a hire date, a scrape time, or an invented date.
* Market data may be read only after frozen predictions have been written. It is benchmark-only. Do not use market outcomes, price movement, lines, consensus, provider identities, or closing status in model code.

## What Round 5 should test

All features below must be season-specific, tied to the target season, and have an anti-leakage audit. Use independent source snapshots or archival evidence where possible. Keep raw records separate from derived team-season features and retain exact source hashes.

### A. Position-level returning and incoming production — priority

Replace or extend coarse team-level returning production with a predeclared, position-specific representation. Keep the existing aggregate returning-production candidate as a comparator.

For offense, test separately where source coverage supports it:

* returning QB passing volume/efficiency;
* returning offensive-line snaps or starts;
* returning WR/TE receiving production or snaps;
* returning RB rushing production or snaps;
* incoming transfer QB, OL, WR/TE, and RB production from the prior school.

For defense, test separately where source coverage supports it:

* returning defensive snaps;
* front-seven continuity and disruptive production;
* secondary continuity;
* incoming transfer defensive production by unit.

Incoming and returning production must be calculated so that a player cannot be counted twice. A player who transfers out must not remain in the origin's returning numerator; a player who transfers in must carry only prior-to-target-season production. Resolve player identifiers first; name matching alone requires logged confidence, ambiguity, and manual override records. Transfers from non-FBS levels require a separately predeclared translation/shrinkage rule, not a subjective credit.

Do not decide position weights after viewing results. Predeclare either (a) a small, interpretable set of unit features with nested ridge/elastic-net selection or (b) a fixed composite with weights fixed from an external public methodology. A permissible public inspiration is SP+'s separate offensive QB/OL/WR-TE/RB continuity and defensive snap/tackle/disruption construction; it is not permission to copy undocumented values or tune weights to held-out outcomes.

Public references:

* ESPN/SP+ discussion of returning and incoming production: https://www.espn.com/college-football/story/_/id/48259759/college-football-returning-production-2026-notre-dame-texas
* ESPN/FPI preseason and transfer-QB discussion: https://www.espn.com/blog/statsinfo/post/_/id/108423/upgrades-sharpen-espns-college-fpi-model

### B. QB continuity and QB quality — priority

Build a separate QB feature pipeline only if historically valid preseason starter/transfer records can be obtained.

* A returning QB must be identified from a pre-cutoff target-season roster/starter record or a clearly season-appropriate historical snapshot, never from target-season starts, snaps, box scores, depth charts published after cutoff, or retrospective roster pages with unresolved timing.
* A transfer QB must have a resolved origin/destination and a transfer state established before the global cutoff.
* Prior QB quality must use prior-season information only: for example, prior EPA/play, success rate, sack/pressure proxy, passing efficiency, or opponent-adjusted score contribution.
* Explicitly retain `unknown_qb`, `returning_qb`, `transfer_qb_with_experience`, `transfer_qb_limited_experience`, and `new_or_unknown_qb` states. Unknown is not replacement level.
* If reliable historical starter snapshots do not span at least three usable forward development seasons, make QB effects exploratory and do not use them in primary selection.

### C. Prior-year efficiency decomposition — priority

Test a small, predeclared set of prior-season, opponent-adjusted efficiency inputs as predictors of next-season offense and defensive burden. They must be computed only from completed prior-season plays/games and standardized within training folds.

Candidate inputs, separately by offense and defense:

* EPA per play;
* success rate;
* explosiveness;
* passing and rushing efficiency;
* havoc created and havoc allowed;
* line yards or a clearly defined rushing-front proxy;
* finishing drives / points per scoring opportunity;
* average starting field position and field position allowed.

Use the underlying play-by-play or a documented advanced-stat source. Do not take an end-of-target-season advanced statistic and relabel it as preseason. If using derived source tables, retain calculation/version hashes and document their treatment of garbage time, opponent adjustment, penalties, overtime, and FCS.

CollegeFootballData publicly documents EPA, success rate, explosiveness, havoc, field position, line yards, and scoring-opportunity metrics. Use the raw or documented source data, not a market-derived ranking.

* https://cdn.collegefootballdata.com/CFBD%20Starter%20Pack%20-%20Data%20Files%20Guide.pdf
* https://cdn.collegefootballdata.com/CFBD%20Model%20Training%20Pack%20-%20Data%20Info%20Sheet.pdf

### D. Special teams and field position

Test a small, fixed special-teams/field-position predictor block, if historical coverage and timing pass audit:

* prior kicking reliability/field-goal value;
* punt and kick return value;
* punt/kick efficiency;
* field-position advantage and field position allowed;
* special-teams continuity where preseason player records are available.

Do not build a published third rating component unless the rating identity is formally changed in a separately declared candidate and all algebra/tests are updated. In the main Round 5 family, these variables influence preseason offense/defensive burden only. They must not become a disguised matchup or stadium effect.

FPI publicly describes separate offense, defense, and special-teams components, which motivates testing this information while Round 5 retains its two-component published identity:

* https://www.espn.com/blog/statsinfo/post/_/id/122612/an-inside-look-at-college-fpi

### E. Multi-year prior performance

Compare the v5 prior-score input to a declared recency-weighted history of two through four preceding seasons.

* Predeclare weights or a tiny grid before fitting. For example, use an exponentially decayed score/efficiency history with half-life grid {1, 2, 3 years}; select only inside each training fold.
* A team's immediately preceding season remains distinct from older history.
* Promotion/reclassification and sparse-history states must remain explicit.
* Never let target-season performance affect the multi-year normalization.

FPI publicly describes using multiple earlier seasons with greatest weight on the most recent one. This is methodological inspiration, not a source of model targets or hyperparameters:

* https://www.espn.com/blog/statsinfo/post/_/id/122612/an-inside-look-at-college-fpi

### F. Coaching and coordinator continuity

Retain v5's strict head-coach whitelist. Add coordinator identity/continuity only when a season-appropriate historical staff source exists.

* Whitelist identity, hire/assignment state, continuity, and tenure entering the target season.
* Mechanically reject target-season games, wins, losses, rankings, SRS, SP, EPA, target-season unit performance, or any derivative.
* Handle an assignment after the global preseason cutoff as unavailable for that target season.
* Do not select an opening coach/coordinator based on eventual games coached or wins.

### G. In-season measurement improvement — separate from preseason features

The existing current-score update is based on points. Test, as separately declared alternatives, whether an opponent-adjusted current-season efficiency update based on pre-cutoff play-level evidence improves early behavior. This is not permission to blend target-game information into a prediction.

Candidates may use past-only current-season EPA, success rate, explosiveness, or field-position-adjusted score evidence, provided all of the following are true:

* each team has one matchup-independent rating at a cutoff;
* the target game and all later games are excluded from every feature and graph edge;
* the FCS clock remains excluded from counted FBS evidence;
* the current update does not use the upcoming opponent as a feature beyond ordinary opponent adjustment through already observed games;
* zero-game and one-game algebra is explicit; and
* the model does not retrospectively refit old game predictions using later-season information.

Do not install arbitrary calendar-week intercepts, a global HFA increase, or a conference discount to erase residual plots.

## Candidate families and pre-fit ordering

Declare all exact families before fitting. At minimum include these fixed labels, in this simplicity order:

1. `v5_EB_features` — exact frozen incumbent reproduction.
2. `position_RP_EB` — v5 plus position-level returning/incoming production.
3. `QB_position_RP_EB` — position candidate plus valid QB states/quality, only if the required history exists; otherwise mark exploratory.
4. `efficiency_prior_EB` — v5 plus prior-year advanced efficiency block.
5. `special_teams_prior_EB` — v5 plus special-teams/field-position predictor block.
6. `multi_year_prior_EB` — v5 plus recency-weighted historical score/efficiency prior.
7. `coordinator_EB` — v5 plus valid coordinator continuity.
8. `full_preseason_EB` — only the components that individually passed a predeclared nested-development gate.
9. `current_efficiency_EB` — v5/final eligible preseason prior plus past-only current efficiency update.
10. `full_preseason_current_efficiency_EB` — only if both components pass nested gates.

Portal-only and QB-only families may be reported as exploratory if their historical forward-validation history is insufficient. Do not discard a season-appropriate feature only because exact publication time is missing; do discard it if substantive future-state contamination or wrong-season assignment is found.

For each feature family, use separate offense and defensive-burden models. Use training-only imputation for prior-score history only. Do not zero-fill substantive external features. Route missing external-feature team-seasons through the exact declared coverage regime or incumbent fallback without changing the game universe.

Use a predeclared nested ridge/elastic-net procedure. A recommended small grid is alpha {0, 0.5, 1} and standardized penalty {0.01, 0.1, 1, 10, 100}; training-only standardization, QR rank audit, and fold-local penalty selection are mandatory. If elastic net is not available, use ridge only and state it. No manual coefficient signs, conference multipliers, or feature pruning after validation results.

## Calibration, probabilities, and public evaluation

Continue fitting the point-scale parameter only from prior development folds. Never force a held-out margin slope to 1. Keep HFA additive and separate from any neutral-rating scale. Use bracketed scalar profiles for scalar parameters; use multiple starts and diagnostics for any genuinely multidimensional optimizer.

Add a separate, predeclared win-probability layer for public evaluation only if it can be fit entirely inside each earlier training fold. It may transform a frozen predicted margin into `P(home win)` using a logistic or probit mapping fitted on earlier outcomes. It must not alter published ratings, margins, HFA, candidate selection MAE, or point-scale calibration.

For this probability layer, report held-out:

* Brier score;
* log loss;
* probability reliability bins;
* straight-up accuracy;
* calibration intercept and slope for probabilities;
* uncertainty by season and calendar-period block.

For point margins, report MAE, RMSE, bias, calibration slope/intercept after HFA removal, prediction SD, actual-margin SD, reliability bins, and performance by declared calendar period, evidence state, neutral/non-neutral site, promotion state, prior-strength magnitude, and connectivity bucket.

ATS may be reported only after model outputs are frozen and joined to a read-only line file. Define the home market margin as `-spread`; pick a side only when model margin differs from market margin; exclude pushes and exact model/line ties; state coverage and closing-line verification status. ATS is descriptive and does not prove betting profitability. Compare market MAE and paired seasonal/block uncertainty, but never optimize against it.

## Advancement rule

Predeclare the following conservative rule before fitting:

1. Primary: lower pooled development MAE on identical game IDs.
2. Minimum signal: at least 0.05 points/game lower MAE than the incumbent.
3. Calibration safeguard: held-out margin-slope distance from 1 may worsen by no more than 0.05, and bias/RMSE must not materially worsen.
4. Stability: improve in at least two of the three principal development seasons.
5. Paired uncertainty: both season-cluster and season-plus-calendar-period block-bootstrap 95% upper bounds for candidate-minus-incumbent MAE must be below zero.
6. If several candidates pass within 0.05 MAE of the best, choose the earlier simplicity-order candidate.
7. A full family may advance only if its components passed their declared nested-development gates. A conference/network candidate must also beat the general uncertainty comparator.

Use deterministic seed 9041 and at least 2,000 bootstrap replicates. Resample seasons, then calendar-period blocks within sampled seasons. State clearly that three development seasons limit precision.

## Feature-provenance requirements

Maintain a source-level and derived-team-level manifest with at least:

```text
season
team_id
player_id where applicable
feature_snapshot_id
feature_values
source URL/query/provider/version
raw content hash
historical_available_at_if_verified
timestamp evidence kind/reference
vintage_status
leakage_risk_status
aggregation rule
source-to-team resolution status
```

Required statuses include `verified_historical_vintage`, `historical_vintage_unverified`, `known_post_cutoff`, and `potentially_contaminated`. Record source retrieval time in a separately named retrieval field only. A transfer or hire event date may establish an event cutoff only; it is not publication evidence.

For player movement, retain unmatched, ambiguous, duplicate, origin-only, destination-only, manual-override, excluded-after-cutoff, and accepted statuses. Prohibit silent loss of origin records when destination is absent.

## Required tests

Port all v5 and v4 parity, graph, FCS-clock, HFA-once, cache, archive, leakage, and power-identity tests. Add at least:

1. Exact v5 incumbent reproduction under the same feature snapshots and cutoffs.
2. Objective-to-prediction equality: every optimization objective equals the reported prediction error on the same rows. Include tests guarding R logical-negation/operator precedence in site/HFA terms.
3. Player-level no-double-counting for returning/incoming production and transfers.
4. No target-season game, player statistic, roster state, injury state, starter state, coach/coordinator state, or advanced-stat record can affect that game's prediction.
5. Position-level aggregates use only resolved player IDs and pre-cutoff target-season states.
6. Incoming transfer production comes only from prior-season source-school information and has a declared cross-division treatment.
7. QB unknown is not recoded to returning, transfer, or zero quality.
8. All advanced-stat predictors are prior-season or pre-cutoff current-season only, with documented garbage-time/opponent-adjustment rules.
9. Special-teams/field-position predictors preserve final `power = offense - defensive burden` exactly.
10. Multi-year prior calculations do not use target-season outcomes and honor promotion/missing-history states.
11. Coordinator records reject target-season performance columns and late appointments.
12. Fold-local imputation, transformations, standardization, collinearity filters, and penalties do not read held-out rows.
13. Feature coverage routing cannot alter the scored game-ID universe.
14. Probability mapping is fitted on earlier outcomes only and does not feed margin/rating calibration or selection.
15. Market columns cannot enter any model, preprocessing, probability, calibration, or candidate object.
16. ATS reporting fails closed on incomplete line coverage, duplicate lines, unverified semantics labels, and accidental market-column ingress.
17. Cache invalidates on code, raw source, source version, feature artifact, transformation, regularization grid, and configuration changes.
18. Prospective archives refuse overwrite, past games, outcomes, market columns, mismatched feature/design hashes, and target-game training IDs.

## Required deliverables

1. `cfb_power_ratings_v6.R` and `cfb_v6_operations.R`; do not modify v5/v4 or frozen Round 4 artifacts.
2. `ROUND5_PREDECLARATION.md` written before fitting.
3. `FEATURE_AUDIT.md`, `FEATURE_PROVENANCE_MANIFEST.csv`, and a player-resolution/event ledger where applicable.
4. Candidate ledger with formulas, inputs, coverage, provenance class, training seasons, game-universe hash, parameters, optimizer diagnostics, held-out metrics, paired uncertainty, and disposition.
5. Separate development and 2023–2025 secondary conditional reports. Label 2026 as prospective only.
6. Position-level/incoming-production ablations; QB, advanced-efficiency, special-teams, multi-year, and coordinator ablations; coverage and provenance sensitivity analyses.
7. Calibration, probability, network, conference, and distribution diagnostics under fixed buckets.
8. Public-validation report with MAE, RMSE, bias, margin calibration, straight-up accuracy, probability metrics if eligible, and benchmark-only ATS/market comparison.
9. Full source/input/cache/design manifests and exact commands.
10. Immutable prospective archives with snapshot IDs/hashes and no outcomes or market fields.

## Final standard

Do not claim advancement because a feature has an intuitive sign, a conditional 2023–2025 result improves, an ATS percentage exceeds 50% in a small sample, or rankings look more plausible. A successor advances only through earlier-only matched development evidence, sound timing/provenance controls, stable paired uncertainty, exact production/validation parity, and coherent rating algebra.

The immediate aim is better non-market predictive performance. The market gap is a benchmark that helps quantify remaining work; it is not a target variable.
