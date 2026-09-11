# Round 4 college-football rating development prompt

## Materials provided with this prompt

Read these attached project files before changing code or running an experiment:

1. `ROUND4_DEVELOPMENT_PROMPT.md` — this protocol.
2. `cfb_power_ratings_v4.R` — the verified Round 3 model implementation.
3. `cfb_v4_operations.R` — production, validation, archive, and feature-ingress operations.
4. `outputs/round3/REPORT.md` — Round 3 conclusions and limitations.
5. `outputs/round3/AUDIT.md` — confirmed implementation findings, HFA audit, and unresolved hypotheses.
6. `outputs/round3/MODEL_SPEC.md` — exact Candidate B and comparator formulas.
7. `outputs/round3/FEATURES.md` and `outputs/round3/feature_inventory.csv` — cached-feature status and coverage.
8. `outputs/round3/candidate_ledger.csv` — candidate definitions and metrics.
9. `tests/test_v4.R` and `tests/test_v4_integration.R` — the Round 3 invariant and integration-test baseline.

The project also contains local data caches. Inspect them as needed; do not attach, copy, mutate, or regard them as independently authenticated historical sources merely because they are present:

```
cfb_data_v2/     # legacy feature and schedule caches
cfb_data_v3/     # audited schedule and Round 3 caches
outputs/round3/  # frozen design, predictions, manifests, diagnostics, and reports
```

Treat every cached offseason table as **ineligible** until its historical publication vintage and provenance are independently verified. A 2026 download timestamp, `cfbfastR_timestamp`, scrape time, cached file modification time, or transfer event date is not a valid historical `available_at` timestamp.

Build Round 4 directly from the verified Round 3 Candidate B implementation in `cfb_power_ratings_v4.R`. Create a separately versioned `cfb_power_ratings_v5.R`; do not modify v4 or any Round 3 artifact.

The work has two purposes:

1. Build a fail-closed, historically vintage-verified offseason feature pipeline.
2. Test a small, predeclared set of point-scale rating models that may improve preseason information, calibration, early-season behavior, and weak-schedule handling.

The model must remain a coherent matchup-independent neutral-field rating:

```
power_rating_i = off_rating_i - def_rating_i
neutral_margin(A, B) = power_rating_A - power_rating_B
home_margin(A, B) = power_rating_home - power_rating_away + HFA
```

Do not use betting lines as model inputs, priors, features, preprocessing inputs, candidate-selection inputs, calibration inputs, or production inputs. They are benchmark-only after all predictions have been frozen.

## Existing evidence and limits

Round 3 selected Candidate B on pre-2023 development data. Its frozen 2023–2025 result was MAE 12.830, versus 12.938 for the comparable frozen v3 baseline and 12.019 for the supplied matched market benchmark. Its calibration slope was 1.184, indicating compressed predicted margins. Early period slopes were roughly 1.43–1.65 in periods 2–4, and B retained conference residual patterns and high correlation with prior-season ratings.

These are diagnostics, not new tuning data. The 2023–2025 outcomes have now been conditionally exposed by Round 3. Any result on them in this effort is a **secondary conditional test**, not a fresh locked outer result. Do not use their outcomes to choose a candidate, transform a feature, choose a hyperparameter, define a bucket, or revise a selection rule.

The candidate B baseline is not simply `0.901 * prior power`. It has separate preseason offense and defensive-burden regressions based on prior offense, prior defensive burden, and a missing-history/promotion state; a separately fitted preseason point-scale calibration; and the convex handoff

```
w_i = n_i / (n_i + 2.423410)
off_i = (1 - w_i) * preseason_off_i + w_i * current_off_i
def_i = (1 - w_i) * preseason_def_i + w_i * current_def_i
```

where `n_i` is counted FBS-versus-FBS games. At 0, 1, 2, 3, 6, and 12 games, B's prior/current weights are 1.000/0.000, 0.708/0.292, 0.548/0.452, 0.447/0.553, 0.288/0.712, and 0.168/0.832. The one-game current component is opponent-adjusted ridge-1 efficiency, not raw margin.

## Protocol and validation

### Development and conditional testing

- Freeze all model design, candidate families, preprocessing, feature eligibility rules, regularization grids, and advancement criteria using only outcomes through 2022.
- Use expanding, strictly forward development folds. At minimum report the existing 2021 and 2022 validation seasons; if a new feature has verified coverage earlier than 2021, add all eligible earlier forward validation seasons without revising the declared rule after results are observed.
- For each fold, fit every transformation, imputation value, standardization, feature screen, elastic-net penalty, conference hierarchy, point-scale parameter, HFA, and handoff parameter using only earlier outcomes and feature artifacts available at that fold.
- Score every serious candidate on the identical final FBS-versus-FBS game IDs, including postseason. Do not let a feature candidate gain an apparent advantage by dropping incomplete teams or seasons.
- If a feature is unavailable for a team-season, use the declared pure-score fallback or a separately trained coverage-regime model. Do not zero-fill a substantive offseason feature.
- After design freeze, report 2023–2025 only as a secondary conditional test. Do not replace the selected candidate or rerun selection using those results.
- Report paired game-level MAE differences, season-cluster uncertainty, and a season-plus-calendar-period block bootstrap. Treat two development seasons and three conditional-test seasons as limited evidence.

### Selection rule

Predeclare candidate ordering and a two-part advancement rule before fitting:

1. Primary criterion: lower pooled development MAE on matched games.
2. Calibration safeguard: a candidate may advance only if its development calibration is materially improved or preserved under a predeclared tolerance, without materially worsening MAE. Estimate calibration using held-out predictions only.

Do not force a held-out slope to exactly 1.0. Do not decide that a 0.03–0.10 MAE change is decisive without paired and season-level evidence. Declare the tolerance, bootstrap method, and simplicity order before execution.

## Phase 1 — fail-closed offseason feature pipeline

Start by auditing the existing cache and documenting that it is not presently eligible as historical preseason evidence:

- `talent_2014_2026.rds` has team IDs and complete talent fields but lacks source provenance and historical publication timestamps.
- `returning_2014_2026.rds` has team IDs but lacks provenance/timestamps and has uneven coverage, including especially incomplete 2021 coverage and no usable defensive field before 2017.
- `portal_2014_2026.rds` has event dates but no team IDs, incomplete destinations, and no publication timestamps or source-vintage record. A transfer date is not an `available_at` timestamp.
- `coaches_1989_2026.rds` combines coach identity/hire fields with target-season outcomes such as games, wins, rankings, SRS, and SP; its cached version has no historical source vintage.
- No dated historical QB-continuity or projected-starter snapshot is currently supplied.

Therefore, none of these cached tables may enter a v5 fit unless independently vintage-verified source artifacts are acquired.

For every new raw source and every derived team-season row, require:

```
season
team_id
feature_snapshot_id
available_at
source_url_or_query
source_provider
source_version_or_retrieval_identifier
raw_content_hash
feature_values
aggregation_rule
```

`available_at` must be an actual publication/observation timestamp, not a cache-download time, scrape time, `cfbfastR_timestamp`, retrospective database timestamp, or transfer event date. For an aggregate, its `available_at` is the latest timestamp among its contributing raw records.

Use one declared global preseason cutoff per season: strictly before that season's first FBS kickoff. Do not quietly grant later information to teams whose first game occurs later. A source snapshot that does not meet this standard must be excluded.

Maintain raw feature artifacts separately from derived team features. Add an explicit team-name resolver for portal sources with matches, unmatched records, ambiguous matches, and manually overridden matches. An unmatched portal record must not be silently assigned or discarded without a logged status.

### Feature-specific requirements

**Returning production**

- Keep offensive and defensive values separate.
- Preserve `is_estimated` as provenance, not as a numeric football feature unless a predeclared ablation supports it.
- Never impute unavailable historical seasons as zero.

**Portal**

- Build incoming and outgoing aggregates separately; net value is a derived quantity, not the only retained feature.
- Require a valid origin and/or destination team-ID resolution and a transfer record available before the global cutoff.
- Define rating/stars missingness handling before fitting. Do not treat absent rating as zero player value.
- Test that a player cannot be double counted and cannot disappear from the originating team because the destination is missing.
- Establish actual historical coverage before testing. If validated portal coverage does not provide enough pre-2023 forward validation seasons, label portal effects exploratory and do not use them for primary candidate selection.

**QB continuity**

- Use only a dated preseason source identifying projected starter/continuity and, if used, prior QB quality measured only through the preceding season.
- Do not infer the starter from target-season starts, snaps, depth charts published after cutoff, or target-season outcomes.
- Maintain an explicit `unknown_QB` state; unknown is not continuity or a replacement-level QB.

**Talent and recruiting**

- Use a fixed, documented transform for talent composite, blue-chip ratio, and recruits. State whether values are logged, ranked, or preseason-standardized.
- Fit all standardization constants in the training fold only. Do not use target-season outcomes to normalize values.

**Coaching**

- Whitelist only dated preseason identity, hire, and continuity fields.
- Statistically and mechanically prohibit target-season games, wins, losses, rankings, SRS, SP, or derived outcomes from feature matrices.
- Handle late hires after the global cutoff as unavailable rather than retroactively known.

The pipeline must fail closed: if a source cannot substantiate vintage and provenance, route that team-season to the pure-score model rather than manufacturing a numerical proxy.

## Phase 2 — preseason-prior model

Retain separate offense and defensive-burden priors. For example, fit fold-local models of the form:

```
pre_off_i = alpha_off + beta_oo * prev_off_i + beta_od * prev_def_i + z_i' * theta_off
pre_def_i = alpha_def + beta_do * prev_off_i + beta_dd * prev_def_i + z_i' * theta_def
```

where `z_i` includes only validated offseason features. Center resulting offense and defensive burden across the relevant FBS team universe before producing power.

Compare these predeclared models:

1. Round 3 pure-score B prior, exactly reproduced.
2. Validated talent/returning-production extension, if and only if vintage artifacts support it.
3. Validated portal extension, if and only if its verified era supports sufficient forward validation.
4. Validated QB/coaching extension, if and only if its verified era supports sufficient forward validation.
5. A full eligible-feature model, only if the component features individually have legitimate coverage and nested development evidence.

Use nested ridge or elastic net separately for offense and defense. Predeclare alpha and penalty grids. Fit imputation values, missingness handling, standardization, collinearity filtering, and penalty selection inside each training fold. The feature pipeline must retain exactly one row per team-season and report all dropped predictors with reasons.

Do not optimize a reduction in raw correlation with prior-season rating. Report it, but evaluate whether offseason features add incremental held-out predictive value, improve calibration, and create interpretable preseason departures from prior score. Report prior-finish Pearson and rank correlations, component shares at 0/1/2/3/6/12 games, and a counterfactual replacing only prior-score inputs with the FBS mean while holding valid offseason features fixed.

When all external features are absent, v5 must reproduce v4 Candidate B’s prior and predictions exactly for the same inputs.

## Phase 3 — point-scale calibration and early-season underdispersion

Round 3’s global slope of 1.184 means predictions were compressed. It does not justify rescaling published ratings after testing, raising HFA, or fitting an arbitrary early-week intercept.

Diagnose separately whether compression comes from:

1. Preseason-prior underdispersion.
2. Attenuation from current ridge efficiency.
3. The handoff speed.
4. HFA and schedule-composition confounding.
5. Information-state-dependent uncertainty.

Use a predeclared, identifiable point-scale family. One acceptable family is:

```
predicted_margin = gamma * (latent_power_home - latent_power_away) + HFA * non_neutral
published_power_i = gamma * latent_power_i
```

where `gamma > 0` is learned only from earlier development folds, applies to the neutral team-rating difference only, and never multiplies HFA. This is allowed only if it is part of the fitted model and published ratings use the same fitted scale. It is not allowed as a post-fit correction selected from held-out calibration.

Keep an explicit, interpretable handoff. At minimum compare:

1. B with the existing convex handoff.
2. A scale-aware convex B variant with a learned model-scale parameter as above.
3. The already declared empirical-Bayes C4 comparator: direct offense/defense score fitting with prior precision 4. It had promising development-only evidence in Round 3 but no outer evaluation; it is a fixed conditional comparator, not an incumbent winner.
4. An empirical-Bayes version with valid offseason prior means, if features pass Phase 1.

For every candidate report formulas, parameter values, units, optimizer diagnostics, exact zero/one-game behavior, full schedules at 0/1/2/3/6/12 games, and additive power decomposition. If a joint empirical-Bayes fit has matrix rather than scalar weights, state this clearly and do not present conditional weights as exact marginal weights.

Measure calibration separately for neutral games and non-neutral games after removing fitted HFA. Report slope, intercept, reliability bins, MAE, RMSE, bias, and uncertainty by calendar period, provider week, games-played state, preseason-favorite magnitude, prior-strength magnitude, promotion/reclassification state, and schedule-connectivity bucket. Keep bucket definitions fixed before results are examined.

No candidate may use a calendar-week intercept, a global HFA increase, or a matchup-dependent team-rating scale solely to erase early bias. A permitted state-dependent update must depend on a team’s available evidence or model uncertainty, not on its upcoming opponent.

## Phase 4 — schedule network and conference structure

Do not apply a hardcoded G5 discount, conference penalty, subjective SOS bonus, or post-hoc conference rescaling.

First report residual and rating diagnostics by:

- Conference using announced pre-kickoff membership for that team-season.
- Distinct FBS opponents.
- Distinct cross-conference opponents.
- Graph component size.
- Number of P4/Pac-12 historical-power-conference opponents, descriptive only.
- FCS exposure, while keeping FCS games out of the counted-FBS clock.
- Opponent prior strength and current uncertainty.
- One-score concentration.
- Zero/one/multiple FBS-game states.

Then test only predeclared structural candidates:

1. Valid roster/portal/QB priors as an explanation for conference residual patterns.
2. A zero-centered hierarchical conference prior estimated only from earlier seasons, with announced historical membership, partial pooling toward the FBS mean, and an explicit predeclared variance prior.
3. A general connectivity/uncertainty shrinkage model based on posterior uncertainty, component size, and distinct cross-conference evidence.

Conference effects must be weighted-centered across FBS, trained only on earlier seasons, and must fade through informative evidence—not merely a count of nonconference games. Report the full effect/uncertainty distribution. A conference candidate must improve development results beyond a general uncertainty model; it cannot be accepted because conference-average ratings appear more plausible.

## Optimizer, cache, and reproducibility rules

Round 3 found that unconstrained Nelder–Mead is unreliable for a one-dimensional handoff parameter and that a multi-parameter independent blend could converge to a boundary-like near-zero timing parameter. Therefore:

- Use bracketed scalar optimization with an objective profile for scalar parameters.
- Use multiple starts for multidimensional optimizers.
- Report parameterization, starts, convergence status, objective values, gradient/boundary diagnostics, and agreement among starts.
- If an optimum is at or near a meaningful boundary, report and interpret the implied reduced model; do not report a tiny number as a substantively estimated timescale.
- Use deterministic seeds and record package versions.
- Cache keys must include full configuration, code version/hash, raw source hashes, feature artifact hashes, and preprocessing configuration.
- Preserve a pre-selection manifest and a frozen-design artifact before conditional 2023–2025 scoring.

## Required deliverables

1. `FEATURE_AUDIT.md`: source-by-source eligibility decision, coverage, temporal cutoffs, excluded fields, missing-season routing, and source limitations.
2. `FEATURE_PROVENANCE_MANIFEST.csv`: source URLs/queries, providers, raw hashes, versions, observation/publication times, aggregation rules, coverage, and team-resolution counts.
3. `cfb_power_ratings_v5.R`: separately versioned implementation. Do not modify v4.
4. A v5 operations script with build, weekly update, validation, feature-ingestion validation, and prospective-archive commands.
5. `CALIBRATION_DECISION.md`: predeclared candidates, objective functions, point-scale/HFA parameterization, calibration safeguard, advancement rule, and candidate dispositions.
6. Candidate ledger with formulas, feature availability, training seasons, matched universe, parameter values, optimizer status, development metrics, paired uncertainty, and selection reason.
7. Development results clearly separated from the 2023–2025 secondary conditional test.
8. Calibration and distribution diagnostics: global and conditional slopes/intercepts, rating SD, reliability bins, early-period diagnostics, and ratings/component contributions for Indiana, Ohio State, James Madison, South Florida, and Old Dominion.
9. Conference/network diagnostics with bias and MAE by conference, connectivity, FBS-opponent count, cross-conference count, graph component size, FCS exposure, and information-state bucket.
10. Matched market benchmark report containing source/provider, timestamp semantics, closing-line verification status, coverage, model MAE, market MAE, delta MAE, and paired seasonal differences. Market data must remain read-only benchmark data.
11. Feature ablations with coverage regime, season-level variation, and uncertainty. State explicitly when an effect is unestimable because vintage coverage is insufficient.
12. Immutable prospective archives containing prediction time, information cutoff, feature snapshot IDs/hashes, design hash, team IDs, neutral status, and predictions, but no outcome or market columns.
13. Exact reproducible commands and input/source manifests.

## Required tests

Port and adapt all Round 3 leakage, parity, graph, FCS-clock, rank-deficiency, deterministic-cache, archive, and power/HFA identity tests. Add at least these v5 checks:

1. Reject a feature source missing URL/query, provider, source version, raw hash, or actual `available_at`.
2. Reject cache retrieval timestamps, `cfbfastR_timestamp`, transfer dates, or invented timestamps used as publication time.
3. Reject feature values available at or after the global preseason cutoff.
4. Assert derived aggregate `available_at` equals the maximum source timestamp among its raw contributors.
5. Reject target-season outcomes and forbidden coaching columns from every feature matrix.
6. Reject duplicate `season/team_id/feature_snapshot_id` rows and join row multiplication.
7. Verify all-external-feature-missing input reproduces v4 Candidate B exactly.
8. Verify portal incoming/outgoing accounting, unmatched/ambiguous team resolution, and no player double count.
9. Verify a target game, target result, future result, or future feature record cannot affect that game’s prediction.
10. Verify preprocessing and elastic-net selection use only fold-training rows.
11. Verify every candidate scores identical game IDs and coverage routing does not silently change the universe.
12. Verify power equals offense minus defensive burden after all feature, scale, and centering transformations.
13. Verify point-scale gamma affects neutral rating difference but not HFA, and preserves neutral antisymmetry.
14. Verify HFA is applied exactly once.
15. Verify zero-game and one-game behavior, including FCS exclusion from counted-FBS evidence.
16. Verify graph/connectivity logic has no hardcoded G5 penalty and excludes future edges.
17. Verify market columns cannot enter any model/preprocessing/calibration object.
18. Verify cache invalidation when raw feature hashes, source versions, preprocessing settings, or code hashes change.
19. Verify full production-versus-validation parity using the same feature snapshot IDs and cutoff.
20. Verify prospective archives refuse overwrite, past games, outcomes, market columns, and mismatched design/feature hashes.

## Final standard

Do not claim success because code runs, a feature has an intuitive sign, ratings look more plausible, a single development MAE is lower, or a conditional 2023–2025 result improves.

The successor must earn advancement through earlier-only matched development evidence, coherent point-scale mathematics, temporal feature provenance, stable uncertainty-aware diagnostics, and production/validation parity. If valid offseason snapshots cannot be obtained, complete the score-only calibration and structural work, preserve the pure-score fallback, and state that offseason feature effects are not estimable.
