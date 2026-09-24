# Model history: every version and experiment, and what it taught

This document reconstructs the project's history from the per-round reports. Full copies of the key reports are in `archive_reference/round_reports/`; everything else is listed in `docs/legacy_file_manifest.md`.

`archive_reference/PROJECT_CONTEXT_AND_ROUND_HISTORY.md` was recovered from git branch `codex/round13-tier-carry`. It is the project's own decision record. Where a report and that record disagree, the record wins; the Round 11 bias metric is one example.

**Conventions in this document**

- "Dev" is the development split and "cond" is the conditional split.
- **Round 4 dev** = 2019, 2021, 2022: 2,320 FBS-vs-FBS games.
- **Round 9+ dev** = 2018, 2019, 2021, 2022: 3,092 games.
- **Cond** = 2023–2025: 2,398 games. This split has been examined many times, so it is **no longer a clean test**.
- **Δ** = candidate MAE − incumbent MAE. Negative means the candidate is better.
- **P4 bias** is P4-oriented: positive means the model underrates the P4 side against G5.

---

## Timeline at a glance

| Version / round | Approx. date (2026) | Idea | Result |
|---|---|---|---|
| Legacy weekly model | Aug–early Sep | Points ridge + preseason prior from prior ratings and talent; PBP/EPA pulls | Replaced |
| v2 | early Sep | Efficiency and preseason as separate components; blend weights regressed by games played | Replaced |
| v3 | early Sep | Score ridge, OLS preseason prior, calibrated blend, nested validation | Outer 2023–25 MAE 12.947 (12.938 under the Round 3 freeze policy) |
| **Round 3 → v4 "B"** | ~Sep 8–9 | Convex blend with a calibrated preseason mean; audit of v3 | Conditional; outer MAE 12.830 (−0.108 vs v3) |
| **Round 4 → v5 `EB_features`** | Sep 9 | EB ridge toward a feature-informed prior (talent, returning production, coaching) | **Promoted. Current production.** Dev 12.920 (−0.317 vs B); cond 12.518 |
| Round 5 → v6 | ~Sep 10–13 | Position RP, QB, efficiency prior, special teams, multi-year prior | Not promoted; incumbent retained |
| Round 6 | Sep 14 | Conference/tier hierarchy (Family A), current efficiency (B), state-conditional scale (E), location + tail guard | Not promoted. Cond −0.065 MAE but failed the bias criterion when HFA drifted |
| Team HFA (side) | ~Sep 14–16 | Team-specific HFA (ridge / EB) | Rejected: −0.007 MAE |
| FCS inclusion (side) | Sep 16 | FCS games in the solve at weights 0.25–1 | Small positive (cond −0.05 to −0.08); not promoted |
| vNext EPA (side) | ~Sep 15 | EPA-based challenger | Worse MAE; rejected |
| Round 7 | Sep 15 | JP+-style PBP efficiency replaces score margin | Worse: dev +0.359, cond +0.256 |
| Round 8 | Sep 16–17 | Dispersion calibration + stronger EP + fumbles + special teams | Much worse: +1.7 to +1.8 |
| Round 9 | Sep 17–18 | Efficiency + talent + score ensemble, learned HFA | No value: dev +0.001, cond +0.012 |
| Round 10 | Sep 18 | Cross-tier correction, cleaner opponent arm, talent gate | Dev −0.101, cond −0.001; not promoted |
| v10_refined | Sep 21–22 | Shrunk post-hoc P4/G5 correction | **Open forward test (Gate 5)**; single look on or after 2028-02-01 |
| Round 11 | Sep 18 | P4/G5 tier random effect inside the ridge solve | "Failed" on a mis-oriented metric; would have passed Gate 1 on the correct one |
| Round 12 | Sep 22 | P4/G5 γ shift with a carried prior inside the solve | Dev Δ −0.064, CI [−0.175, +0.023]: failed Gate 2 |
| Round 13 | not started | Proposed: report-only tempo-normalization probe | No code or predeclaration |

---

## Early lineage: legacy weekly, v2, v3

**Legacy weekly model** (`cfb_power_ratings_functions.R` + `cfb_weekly_update.R`)

- One penalized least-squares fit on team-game points, with offense and defense dummies and one HFA term.
- Coefficients were shrunk toward a preseason prior built from prior-season ratings and recruiting talent.
- It pulled CFBD play-by-play weekly. Its caches are in the old `cfb_data/` folder: `pbp_*.rds`, `history_ratings`, `lambda_2026`.
- It fixed an earlier EPA/play ridge whose design-matrix coding put offense and defense on different scales.
- **Lesson carried forward:** build the design matrix by hand.

**v2** (`cfb_power_ratings_v2.R`)

- Estimated efficiency and preseason ratings separately.
- Combined them with weights a(g) and b(g), regressed out of sample by games played.
- This made early-season behavior an explicit design choice rather than a by-product of one λ.

**v3** (`cfb_power_ratings_v3.R`)

- Scores-based ridge with candidate caps and λ (6 or 12), plus FCS pooling.
- OLS preseason prior on previous offense/defense and a promotion flag.
- Calibrated blend and nested validation.
- **Defect (confirmed in Round 3):** later candidate selection reused earlier outer years. There was also an FCS clock-counting bug in its pooled candidate.
- Its helper functions still live inside the production engine (`fit_efficiency`, `read_schedule`, `team_games`, …).

---

## Round 3 → v4 (Candidate "B")

**Candidates**

- A: 3-parameter blend.
- **B: convex blend `w = n/(n+k)` of a current-season ridge-1 fit and a scaled preseason prior.**
- C and D: EB shrink-to-prior at λ = 8; D also had "structural" connectivity shrinkage.
- Plus ablations.

**Results**

- **Selected B:** dev MAE 13.297. Locked outer 2023–25: **12.830 vs 12.938** for a reconstructed frozen v3 (−0.108; improved in all 3 seasons). Market MAE was 12.019.

**Findings that persisted**

- **Early-season bias and compression.** In periods 2–4, B's slopes were 1.43–1.65 and its biases −4.5 to −0.8.
- **Weak-schedule residuals.** SEC and Big Ten were underrated; C-USA, MAC and the Sun Belt were overrated.
- **Heavy dependence on last season.** Ratings correlated 0.96 with the prior-year finish.
- A broader season/period bootstrap interval included zero.
- The optional features (talent, etc.) were ineligible under the Round 3 provenance rules, which required verified publication dates.
- **Motivation for Round 4:** external features.

---

## Round 4 → v5 `EB_features` (production)

**Twelve predeclared candidates, in simplicity order**

- B and B_scale
- C4 (EB at λ = 4)
- RP, RP_off and RP_def (returning production)
- Talent_RP and Coach
- Full
- **EB_features** (the Full feature prior combined with the C4 EB solve)
- Uncertainty (graph-connectivity shrinkage)
- Conference (partially pooled conference offsets)

**Key rule change:** the user allowed features with *unverified* historical publication vintage. They are flagged `historical_vintage_unverified` and are never zero-filled.

**Advancement rule**, all fixed before fitting:

- at least 0.05 MAE gain;
- the calibration-slope distance from 1 worsens by no more than 0.05;
- at least 2 of 3 seasons improve;
- both paired 95% upper bounds (season cluster, and season-then-Monday-block) are below 0.

**Development results** (2019, 2021, 2022; 2,320 games)

| Candidate | MAE | Δ vs B | Block 95% CI | Passed |
|---|---|---|---|---|
| B | 13.238 | — | — | ref |
| C4 | 13.154 | −0.083 | [−0.173, +0.017] | no |
| Talent_RP | 13.023 | −0.215 | [−0.425, −0.031] | yes |
| Full | 13.042 | −0.195 | [−0.346, −0.060] | yes |
| **EB_features** | **12.920** | **−0.317** | **[−0.520, −0.103]** | **yes: selected** |
| Conference | 13.146 | −0.092 | [−0.201, +0.011] | no |
| Uncertainty | 13.206 | −0.032 | [−0.128, +0.068] | no |
| RP alone | 13.218 | −0.020 | [−0.096, +0.058] | no (inconclusive) |
| Coach alone | 13.232 | −0.006 | — | no |

The Δ values are rounded from the per-candidate estimates. They can differ from the difference of the rounded MAE columns by 0.001.

**Conditional check (2023–25)**

- EB_features scored **12.518**; B scored 12.830 (−0.312, block CI [−0.497, −0.139]).
- Bias −0.043; slope 1.015; market MAE 12.019, so the market gap was **+0.499**.

**What the gain is**

- Most of it comes from feature-informed priors (talent is the strongest block) combined with the EB solve.
- RP alone, coaching alone and portal each added little or nothing measurable.
- It is a pipeline comparison, not a causal feature effect.

**Implementation correction:** an R precedence bug (`H * !neutral - actual`) invalidated the first development run. It was fixed before conditional scoring and disclosed in `IMPLEMENTATION_CORRECTION.md`.

---

## Round 5 → v6 challengers (not promoted)

**Families tested on top of the incumbent**

- position-level returning production;
- QB continuity/quality;
- prior-season efficiency (success rate, line yards, stuff rate);
- special teams and field position;
- multi-year score history (L ∈ {2,3,4}, half-life h ∈ {1,2,3});
- current-season efficiency (25% of the score evidence replaced by a success-rate mapping).

**Results**

- **No family passed.** The best was `multi_year_prior_EB`: dev Δ −0.074, but its block upper bound was +0.027.
- **Not estimable:** position RP, QB and coordinator features. No player-ID-resolved historical state existed.
- **Lesson:** multi-year history looked promising but was not locked early enough to test cleanly.

---

## Round 6 (not promoted): hierarchy, efficiency, state-conditional scale

This round ran in five phases. Its code is in `CFB-Modeling-round6/` in the old folder and on branch `codex/round6-claude`.

**Phase 1: Family A, conference/tier hierarchical reparameterization of the current-season solve.**

- Dev Δ −0.013 to −0.030; all variants underpowered.
- Calibration improved.
- Absolute bias worsened by +0.17, beyond the 0.10 allowance.

**Phase 2: Family B, current-season efficiency; plus an A+B composite.**

- Composite Δ −0.051, block upper bound +0.0013.
- Failed the bias criterion (+0.148).

**Phase 3: Family E, information-state-conditional scaling.**

- Removed the early-season compression. The gp = 0 slope went from 1.21 to 0.98.

**Phase 4: a location term and a tail guardrail.**

- Frozen by **manual override**: `P4_E3AB_state_mean_tail`.

**Conditional result (2023–25)**

- MAE 12.454 vs 12.518: −0.065, improved in 3/3 seasons.
- The Big Ten–MAC gap fell in every season.
- **Failed C2 (bias):** the frozen location term set HFA' = 2.43, estimated on 2017–22. Realized HFA then rose (2.19, 2.95, 3.08), and the model underpredicted home margins.

**Phase 5: drift-aware HFA shadow design.**

- Expanding precision-weighted HFA level, 2.56 for 2026.
- Frozen 2026-09-14. There is no evidence its shadow stream was ever archived.

**Lessons**

- Early-season compression and the conference gap *can* be reduced.
- A static location/HFA term is fragile when HFA drifts between seasons.

---

## Side experiments

**Team-specific HFA**

- Common ridge: dev −0.007 MAE, which failed the 0.05 minimum.
- The EB variant pooled completely: estimated between-team variance was 0.
- **Rejected.** Keep one global HFA.

**FCS games in the solve** (reused the Round 4 snapshots)

| Weight | Dev Δ | Cond Δ | Round 4 rule on cond |
|---|---|---|---|
| 0.25 | −0.024 [−0.070, +0.012] | −0.052 [−0.087, −0.023] | pass |
| 0.50 | −0.021 | −0.082 | pass |
| 1.00 | +0.037 | −0.082 | fail |

- No variant passed on development. Because every variant was then inspected on cond, 2023–25 cannot confirm the idea.
- **Cheap and promising.** A candidate for a properly predeclared V2 test.

**vNext EPA challenger**

- Paired 2023–25 MAE 13.446 vs the incumbent's 12.530.
- **Rejected.**

---

## Rounds 7–10: play-by-play efficiency, tested four ways

| Round | Design | Dev Δ | Cond Δ | Key finding |
|---|---|---|---|---|
| 7 | JP+-style SR/EPA-per-play ratings from in-house EP models (1.06M plays) replace the score signal | +0.359 | +0.256 | Under-dispersed: predicted SD 9.3 vs actual 20.7, slope about 1.33. Accuracy got *worse* as efficiency took over. The hyperparameter grid did not matter (0.19 spread). Cross-tier bias widened. |
| 8 | Variance-matching recalibration, stronger EP, fumble recovery, special teams | +1.73 | +1.77 | Forcing the SD ratio to 1 amplified noise. With correlation ≈ 0.60, Round 7's compression had been useful shrinkage. The special-teams component had a scoping bug and contributed zero. |
| 9 | Ensemble: incumbent + opponent-adjusted efficiency + talent deviation, learned HFA | +0.001 | +0.012 | Efficiency's partial correlation given the incumbent was 0.025–0.051, incremental R² ≤ 0.0016, and residual correlation with the incumbent 0.87–0.90. The zeroing rule set its weight to 0. **The SD-ratio gate is unattainable for any calibrated forecast, including the market (0.648).** Learned HFA was 2.6–3.0 and tied a fixed 3.0. |
| 10 | Cleaner opponent arm (no home term), post-hoc cross-tier correction, talent September gate | −0.101 | −0.001 | The correction learned on dev (≈ 5.5 points) overshot the cond-era bias (3.4). Talent add-on hurt September twice, so it was dropped. |

**Data-quality lessons from Round 7**

- CFBD's scoreboard rows on administrative plays are stale. The naive reader discarded 30–58% of games.
  - **Fix:** reconstruct the running scoreboard as a cumulative maximum, and require the reconstructed final to equal the official final.
- The 2013 play-type vocabulary differs from later years.
- Fumble rows lack the underlying play type. Round 8 recovered 94–99% of them from play text, but only 68% in 2025.

**Later post-mortem (2026-09-22; source file not found on disk, recorded from session notes)**

- R9/R10's "efficiency weight = 0" came from the zeroing *rule*, which required ΔR² ≥ 0.01, not from a measured zero.
- An unconstrained walk-forward stack gains about 0.03 MAE on both dev and cond.
- The closing line's partial correlation with outcomes given the incumbent is 0.27. PBP's is 0.10, and 0.036 once the market is also controlled for.
- **Treat PBP as at most a cheap additive component, never a rebuild.**

---

## The P4-vs-G5 bias thread (Rounds 9–12)

The largest systematic defect: the incumbent **underrates P4 teams against G5 opponents**.

| Split | P4-oriented bias |
|---|---|
| 2019 / 2021 / 2022 | +3.62 / +7.34 / +6.25 |
| Dev pooled (2019, 2021, 2022) | +5.62 |
| Cond 2023–25 | +3.44 |
| 2026 interim (n = 34) | +5.64 |

The closing line's own bias on these games is only +0.29, so this is a model defect, not a feature of the games. The bias is not stationary, and per-stratum SEs are 1–3 points.

**v10_refined** (post-hoc refinement)

- Correction `s × (a + b·p4_home)`, with a = 2.356 and b = 1.831. These came from a 0.65 shrink of era-averaged fits.
- Gates 1–4 passed:
  - dev Δ −0.094 [−0.155, −0.033];
  - cond Δ −0.022 [−0.074, +0.024];
  - cond bias 3.44 → −0.23.
- The 0.65 factor was informed by conditional data, so only a forward test is clean.
- **Gate 5 was locked under Amendment 2 at 2026-09-22T14:31:18Z:**
  - season-indexed tier map (Pac-12 is G5 from 2026);
  - rule |bias(v10_refined)| < |bias(incumbent)|;
  - post-lock 2026 games plus all of 2027;
  - n ≥ 60;
  - one look on or after 2028-02-01.
- An EB-shrinkage variant, `v10_refined_v2` (a = 3.503, b = 2.834), is staged but needs its own predeclaration.
- See `archive_reference/forward_validation_gate5/`.

**Round 11:** P4/G5 tier random effect inside the ridge solve (λ_tier grid).

- **Reported:** a 1.35-point bias reduction at best, which failed the ≥ 2 gate.
- **The reported bias metric was not P4-oriented.** On the correct oriented metric, λ_tier = 1 removes 2.63 points on inner 2018–19 and 3.24 on full dev. Gate 1 would have passed.
- **Do not reopen Round 11 without an explicit decision.**

**Round 12:** P4/G5 γ shift inside the solve, with a prior carried from the previous season's final snapshot.

- Gate 0 passed: γ-off reproduced the incumbent exactly.
- λ_γ = 30 was selected, at the upper edge of the grid.
- Gate 1 passed: Δ −0.0644.
- **Gate 2 failed:** 95% upper bound +0.0234.
- Bias dropped 5.62 → 0.79.
- Removing directional bias does not by itself produce a significant MAE gain, because game-level noise (SD ≈ 16) dominates.
- A bootstrap defect was found and disclosed: the text cutoff was parsed with `as.numeric()`, which collapsed the blocks.

---

## Approaches tested and abandoned

| Approach | Why abandoned |
|---|---|
| Convex prior/current blend (v3, v4 B) | EB joint solve with feature prior is 0.3 MAE better |
| Structural/connectivity shrinkage (v4 D, v5 Uncertainty) | Hurt dispersion; no stable gain |
| Conference offsets in the prior (v5 Conference, R6 Family A) | Small gains, underpowered; bias side-effects |
| Team-specific HFA | Gain 0.007; EB variance 0 |
| Play-by-play efficiency as replacement (R7, vNext) | 0.26–0.9 MAE worse; under-dispersed |
| Variance-matching dispersion fix (R8) | Amplifies noise; MAE +1.7 |
| Efficiency ensemble weight (R9, R10) | Incremental R² ≤ 0.003; residuals 0.9 correlated |
| Talent-deviation add-on (R9, R10) | Hurt conditional September twice |
| Post-hoc flat P4/G5 offset (R10) | Overshoots; non-stationary |
| SD-ratio gate [0.85, 1.15] | Mathematically unattainable for calibrated forecasts (SD ratio = correlation) |
| Position RP / QB / coordinator / portal features | Not estimable from available historical state |
| Special teams | Never correctly implemented (R8 bug); untested |

## Still open or promising

- v10_refined Gate 5 (forward).
- Tier term inside the solve: Round 11 on the corrected metric, Round 12's design with a longer dev set.
- FCS games at weight 0.25–0.5.
- Multi-year prior (Round 5).
- Drift-aware HFA (Round 6 Phase 5).
- Early-season scaling (Round 6 Family E).
- Proposed Round 13 tempo probe.
