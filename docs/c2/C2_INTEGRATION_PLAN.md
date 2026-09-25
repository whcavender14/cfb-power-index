# C2 Integration Plan (consolidating Stages 0–4)

**Date:** 2026-09-25. **Branch:** `c2-refinement`. **Base:** tag `round15-scored` (`d6fd3d3`).

**Research commits:** `c7cc05c` (S0), `c8c97a9` (S1), `21c83a2` (S2), `51c241f` + `29f39de` (S3), `47739dd` + `275a75c` (S4).

**Scope.** This is consolidation, not research:
- no new arms, no hyperparameter change, no selection on 2023–25;
- the frozen Round 15 implementation (`R/round15/**`, tags `round15-*`) is not modified.

**Sources audited** (the files, not the conversation):
- `docs/c2r/STAGE0_DATA_PIPELINE_CHECK.md`, `STAGE1_FCS_DIAGNOSIS.md`, `STAGE2_GARBAGE_TIME.md`;
- `STAGE3_PLAN.md`, `STAGE3_FCS_LEVEL.md`, `STAGE4_PLAN.md`, `STAGE4_PRESEASON.md`;
- the selection records `output/c2r/stage3/selection_final.rds` and `docs/c2r/stage3/s3_selection_final.csv`;
- `docs/c2r/stage4/s4_selection_final.csv` and the selected arm object `output/c2r/stage3/arms/L_last_n20.rds`;
- the research code `scripts/c2r/lib_c2r.R`, `lib_s3.R`, `s3a`–`s3d`, `s4a`–`s4d`;
- the frozen code `R/round15/candidates/{data,c1,c2,tune}.R` and `scripts/round15/{c1,c2}_build.R`.

## 1. Audit: every finding and whether it enters C2

| Research item | Stage | Result | Incorporate? | Reason |
|---|---|---|---|---|
| PBP has quarter, clock and score fields at 0% missing; one play source feeds SR, fumbles and passers | 0 | Confirmed | DIAGNOSTIC ONLY | No change needed. |
| C2's SR already drops garbage time (Q2 > 38, Q3 > 28, Q4 > 22, OT dropped) | 0 | Confirmed | ALREADY PRESENT | Kept unchanged (Stage 2). |
| No FCS-vs-FCS play-by-play; FCS SR comes only from FBS games | 0 | Known limitation | DIAGNOSTIC ONLY | No data to change it; not addressed. |
| Frozen C2 had no FBS-vs-FCS prediction path (R15 rebuilt it in the scorer) | 0 | Confirmed | **ACCEPT** | Current C2 outputs non-FBS ratings and FBS-vs-FCS predictions using C2's own home field. This is how every Stage 1–4 evaluation of C2L built them. |
| Stage 0 count of FCS first games (207 / 141) | 0→1 | Corrected to 226 / 153 | DIAGNOSTIC ONLY | A reporting erratum. |
| FCS error is a level (intercept) error, not an ordering error | 1 | Established | DIAGNOSTIC ONLY | Motivates Stage 3. |
| Double shrinkage: end-of-season fits and an in-season prior-dominated level | 1 | Established | DIAGNOSTIC ONLY | Motivates Stage 3. |
| Excluding lower divisions from the FCS pool alone worsens the bias | 1 | Established | REJECT (as a standalone fix) | Only valid with a level fix, which Stage 3 supplies. |
| Conference-level compression within FCS | 1 | Established | DIAGNOSTIC ONLY | Left as a known residual (S3 §9). |
| FCS level error leaks into FBS ratings (about 0.5-point credit) | 1 | Established | DIAGNOSTIC ONLY | Removed as a consequence of the Stage 3 fix. |
| Pre-snap margin distribution flags | 1 | Flagged | DIAGNOSTIC ONLY | Input to Stage 2. |
| Garbage-time treatment A (frozen: > 38/28/22, per play, OT dropped) | 2 | No measurable effect vs A0 or B | ALREADY PRESENT | Kept. Stages 3–4 held A fixed. |
| A0: no garbage filter | 2 | Indistinguishable | REJECT | No benefit. The user directed A to be kept. |
| B: Connelly 3 Sep 2019 rule (≥ 44 Q1, ≥ 38 / 28 / 22) | 2 | Indistinguishable from A | REJECT | Same reason. |
| SR evidence is not what inflates FCS teams; β does not transfer 1:1 to mismatches | 2 | Established | DIAGNOSTIC ONLY | No change. |
| M(X): margin-only +X on FBS-vs-FCS predictions | 3 | Benchmark (X = 10 best) | REJECT | Benchmark only by plan; it fixes no rating. |
| G(δ): fixed downward shift of the non-FBS prior | 3 | Eligible; honest J 0.48503 | REJECT | L was better by 0.0016, beyond the 0.0005 tolerance. |
| **L: in-model group levels Δ_FCS (non-FBS vs FBS) and Δ_low (lower divisions vs FCS)** | 3 | **Selected** (honest J 0.48348) | **ACCEPT** | Predeclared rule. `L_last_n20` in every fold. |
| **Level prior strength n0 = 20 games** (λ_L = 2·n0 + 1e-4) | 3 | **Selected** | **ACCEPT** | n0 = 0 (free) lost by 0.0038. |
| **Anchor "last"**: previous season's end-of-season FCS level and lower gap, from a points-only fit with both levels free, 2020 excluded | 3 | **Selected** | **ACCEPT** | Chosen by the leave-one-season-out selection in all five folds. |
| Anchors fixed, expanding, rolling3 | 3 | Within 0.0002 of "last" | REJECT | Not selected. Kept only as documented alternatives. |
| **Division-specific prior pools** (μ from FCS / D-II / D-III + unknown end-of-season means) | 3 | Part of the selected arm (`divmu = TRUE`) | **ACCEPT** | Part of the selected specification. |
| "Pooled μ" and "expanding anchor" simplifications | 3 | Post hoc attribution (P_noDiv) and an observation; not selected | DIAGNOSTIC ONLY | Adopting them would change C2L. The report marks them "for a future predeclaration, not applied here". Preserved as selected. |
| **First-game rule** (prior deviation + current solved group level) | 3 | Part of the selected arm | **ACCEPT** | Defined in the plan. Used by C2L. |
| S(k): stronger FCS shrinkage (k = 2, 4) | 3 | Fails the FCS-vs-FCS calibration guardrail (1.30) | REJECT | Predeclared guardrail. |
| FLAT: every FCS team at the group level | 3 | Much worse | REJECT | |
| SR-only level column | 3 | Sensitivity arm | REJECT | Not selectable by plan. |
| No drift in the FCS level (p = 0.66) | 3 | Established | DIAGNOSTIC ONLY | Supports the anchor design; no trend term. |
| Preseason mechanism: mean a × C1 prior, turnover-scaled λ, constant precision | 4 | Measured | ALREADY PRESENT | Unchanged. |
| gp = 0 predictions mildly compressed (2017–22 only) | 4 | Did not replicate | DIAGNOSTIC ONLY | |
| S(s): global preseason scale | 4 | Within the 0.0003 tolerance; worse in 2023–25 | REJECT | The rule keeps 1.0. |
| O(s_off): offense-only scale | 4 | Same | REJECT | |
| D(h): exponential decay, h = 1–5 | 4 | All worse | REJECT | |
| F: flexible games-played multipliers | 4 | Optimum at the current setting | DIAGNOSTIC ONLY | Not selectable by plan. |
| Post hoc scale + decay; gp = 0-only scale | 4 | Worse or not replicated | REJECT | |
| **All-games games-played count** (includes FCS games) | 4 | Frame gp agrees only 19% of the time | **ACCEPT (evaluation layer only)** | See the note below. |

**Note on games played.**
- The C2 rating system has never read a games-played field. The ridge simply contains every final game before the
  cutoff, including FCS games, and the prior precision is constant.
- The Stage 4 correction concerns **how evaluation slices are bucketed**: R15 used the incumbent frame's `gp_home` /
  `gp_away`. It also concerns the research-only precision multipliers, which were rejected.
- It therefore enters **only** the evaluation and reporting helper `c2_games_played()`. **The model is unchanged.**

## 2. Integrated C2 specification (data to prediction)

| # | Component | Status | Canonical implementation |
|---|---|---|---|
| 1 | Data inputs | Unchanged | `r15_build_data()` cache: schedules and final scores 2013–2025 (FBS-involved plus P1 FCS-involved games); play-derived SR, fumble counts; C1 inputs. Frozen construction outputs: `c1_components.rds` (priors, variance models, scale a, λ0) and `c2_components.rds` (β, κ, FCS moments, ω, end-of-season fits). |
| 2 | Play filtering | Unchanged | Round 13 instrument (`R/forward/vendor/round13_sr_stack.R`) with the P2 fumble parser and the A3 2020 patch: scrimmage plays only. |
| 3 | Garbage time | Unchanged (S2) | Drop a play if the pre-snap \|margin\| exceeds 38 in Q2, 28 in Q3 or 22 in Q4. Q1 never. OT always dropped. |
| 4 | Success rate | Unchanged | Per game × offense mean. SR row y = SR/β at weight ω with its own intercept. β is pooled OLS on FBS-vs-FBS training rows. |
| 5 | Offense and defense estimation | Unchanged core; extended by S3 | One joint ridge per weekly cutoff. Points rows are luck-adjusted with home field removed. SR rows. Per-entity offense and defense. Plus the two group-level columns (row 12). |
| 6 | Preseason priors (FBS) | Unchanged (S4) | Mean = a × C1 prior (off, def). No additional scale. |
| 7 | Prior strength and decay (FBS) | Unchanged (S4) | λ_i = λ0 · exp(−b(u_i − ū)) per side, constant through the season. No games-played multiplier. |
| 8 | FBS treatment | Unchanged | Every FBS team (from the frozen schedule) is an entity at every cutoff. |
| 9 | FCS treatment | **Changed (S3)** | A non-FBS team becomes an entity once it has a final game before the cutoff. Its prior mean is μ_div + ρ·(last season's end-of-season rating − μ_div), or μ_div with no previous rating. μ_div is its **division's** pool mean; ρ is pooled. λ_FCS = λ0 · v̄_FBS / v_FCS per side (unchanged). |
| 10 | Lower divisions | **Changed (S3)** | D-II is its own pool. D-III and unknown share a pool. They are shifted jointly by Δ_low relative to FCS. A non-FBS team counts as FCS only if it carries the CFBD "fcs" label that season. |
| 11 | Games played | Model unchanged; evaluation corrected (S4) | See the note above. `c2_games_played()` counts all final games before the cutoff. |
| 12 | **Group levels** | **New (S3)** | Two unpenalized-in-spirit columns, each with a ridge prior. **Δ_FCS** = X·t, t = +1 on every non-FBS offense and −1 on every non-FBS defense; only FBS-vs-non-FBS rows (points and SR) inform it. **Δ_low** is the same over lower-division entities; only FCS-vs-lower rows inform it. Precision λ_L = 2·20 + 1e-4 each. |
| 13 | **Anchors** | **New (S3)** | Prior mean of Δ_FCS = (A_FCS − prior FCS-division mean power) / 2, where A_FCS is the **previous available season's** (2020 excluded) end-of-season FCS-division mean power. That fit is points only, penalty 1 on teams, season home field, and both group levels free. Δ_low uses the same rule with the lower-minus-FCS gap. |
| 14 | Normalization | Unchanged | Ratings are centred on the FBS mean of offense and of defense. A non-FBS team's power = (o − ō_FBS) − (d − d̄_FBS) + 2Δ_FCS (+ 2Δ_low if lower division). Reported offense and defense carry ±Δ each. |
| 15 | Predictions | Unchanged formula; FCS path new | Margin = power_home − power_away + H·(not neutral). H is C2's own home field (`r15_H`; 3.0685 for 2023–25). FBS-vs-non-FBS games use the non-FBS team's rating, or, **before its first game**, its prior deviation plus the current group level (first-game rule, S3). |
| 16 | Probability conversion | Unchanged, downstream | P(win) = Φ(margin / σ), with σ fitted by maximum likelihood on development FBS-vs-FBS games, leave-one-season-out (the R15 scorer rule). Evaluation only; not part of the rating system. |
| 17 | Everything else | Unchanged | κ (fumble luck), ω and β selection, C1 prior construction, λ0 selection, prior scale a, 2020 handling, snapshot cutoffs, the FBS centring, and the "prediction at the latest cutoff before kickoff" timing. |

## 3. Implementation plan

1. **Canonical code.** `R/c2/c2_current.R` implements the specification directly, with no experimental switches.
   - It reuses the frozen Round 15 helpers read-only (`r15_luck`, `r15_sr_rows`, `r15_rows`, `r15_H`, `r15_c1_lambda`,
     `fbs_ids`).
   - The generic ridge core, `c2_ridge_solve()`, takes a list of group columns. Production always passes the two Stage 3
     groups. The frozen system is the special case with no groups, which is used only as a regression test.
   - `R/c2/c2_diagnostics.R` holds the prior-influence diagnostic (Stage 4).
2. **Build.** `scripts/c2/c2_build_current.R` writes `output/c2/current/`: predictions (frozen C2 schema), FBS and
   non-FBS ratings by cutoff, group levels, first-game ratings, FBS-vs-FCS predictions, anchors and a manifest.
3. **Tests:**
   - `tests/c2/test_c2_equivalence.R` compares current C2 with research C2L (`lib_s3.R`, `L_last_n20`), both freshly
     run and against the stored Stage 3 artifact.
   - `tests/c2/test_c2_regression.R` compares current C2 with frozen R15 C2.
4. **Performance.** `scripts/c2/c2_verify_performance.R` re-derives the Stage 3/4 metrics from the integrated output and
   checks them against the stored research tables.
5. **Documentation and tagging.** `docs/c2/C2_CURRENT_SPEC.md`, then a commit and the tag `c2-post-stage4-baseline`.

**Naming.**
- **C2_frozen_round15:** `R/round15/candidates/c2.R` (`r15_predict_season_c2`), untouched.
- **Current C2:** `R/c2/c2_current.R` (`c2_run`, `c2_predict_season`).
- **C2L:** the research arm (`scripts/c2r/lib_s3.R`), kept only for reproducibility.
