# C2: Current Specification (integrated post-Stage-4 baseline)

**Status:** the canonical C2 on branch `c2-refinement`, tag `c2-post-stage4-baseline`.
- **Future research compares against this model.**
- It is a research baseline, not a production promotion. None of its changes has been through a predeclared formal round.

**Code:** `R/c2/c2_current.R` (model), `R/c2/c2_diagnostics.R` (diagnostics), `scripts/c2/c2_build_current.R` (build),
`tests/c2/` (validation).

**Historical reference:** frozen Round 15 C2, `R/round15/candidates/c2.R` (`r15_predict_season_c2`), tag `round15-scored`.
It is unmodified.

## 1. Model philosophy

C2 is a **play-by-play-centred, opponent-adjusted rating model**. Every team has an offense rating and a defense rating.
They are re-estimated every week from everything known before that week's cutoff, in **one joint ridge regression**.

**Scoreboard evidence.**
- Each team-game contributes a points row: points scored = intercept + own offense + opponent's defense + home field.
- Points are adjusted for fumble luck: recovered-fumble outcomes are treated as coin flips.

**Play-by-play evidence.**
- Each game × offense contributes a success-rate row. Success is 50% of the distance on 1st down, 70% on 2nd and 100% on
  3rd/4th.
- SR is computed on competitive scrimmage plays only: garbage time and overtime are removed.
- SR is translated to points by β and down-weighted by ω relative to points rows.
- SR is the model's play-level signal of efficiency, which is steadier than the scoreboard.

**Opponent adjustment** is automatic: every row involves both teams' parameters, so each rating is measured relative to
the opposition faced.

**Preseason information** enters as a prior on each FBS team's offense and defense.
- The prior mean comes from C1's information-rich preseason model: returning production, recruiting, coaching, last
  season, last season's SR.
- The prior's strength depends on roster turnover.
- **Its influence fades only because game evidence accumulates.** About half of a team's rating is still preseason after
  three games, and about a quarter after six.

**Games accumulate** in the same system. Each new game adds rows, and the ridge automatically rebalances prior against
data.

**FCS and lower-division teams** are rated inside the same system when they have played.
- Their overall level relative to FBS is a **separate, explicitly estimated group level**, learned from FBS-vs-FCS games.
- Their order within FCS comes from their own games and priors.
- This separation is the Stage 3 change.

**Normalization.** All ratings are centred on the FBS average. A predicted margin is the difference of two power ratings
plus home field.

## 2. Current specification

| Step | Specification | Origin |
|---|---|---|
| **Data** | Final scores and schedules 2013–2025: FBS-involved games from the frozen schedules, plus FCS-involved games (P1 pull). Play-by-play: CFBD `/plays` (Round 6 pull). C1 inputs. All read from the frozen `r15_build_data()` cache. | frozen |
| **Play filtering** | Round 13 SR instrument: scrimmage plays only. Excluded: kneels, spikes, penalties, no-plays, special teams, invalid states and games whose scoreboard cannot be rebuilt. P2 fumble parser; A3 2020 patch. | frozen |
| **Garbage time** | Drop a play when the pre-snap \|margin\| is > 38 in Q2, > 28 in Q3 or > 22 in Q4. Q1 never. OT always. | frozen; confirmed by Stage 2 |
| **Success rate** | One row per game × offense: y = SR / β, weight ω, own SR intercept. β = pooled OLS of game SR on end-of-season (o_A + d_B), FBS-vs-FBS training rows (about 0.0053 per point). ω selected by the frozen inner walk-forward (0.5 for 2017, then 0.25). | frozen |
| **Points rows** | pf + (κ/2)·L − H·hx, where L is the fumble-luck differential, hx = ±0.5 for home/away (0 neutral), and κ is estimated jointly. | frozen |
| **FBS preseason prior** | Mean = a × C1 prior (offense, defense). a is an LAD scale of prior-only predictions on earlier seasons (1.05–1.17). **No further scale** (Stage 4 kept 1.0). | frozen; confirmed by Stage 4 |
| **FBS prior strength** | λ_i = λ0 · exp(−b(u_i − ū)) per side, from the turnover index u. λ0 is chosen by the frozen inner walk-forward (3 for 2017–18, 4 from 2019). **Constant through the season, no games-played decay** (Stage 4). | frozen; confirmed by Stage 4 |
| **Non-FBS entities** | Every non-FBS team with a final game before the cutoff. Its group is **FCS** if CFBD labels it "fcs" that season. Otherwise it is **D-II** ("ii") or **D-III / unknown** (pooled). | Stage 3 (groups) |
| **Non-FBS prior** | Mean = μ_group + ρ·(last season's end-of-season rating − μ_group), or μ_group if unrated last season. μ_group is **that group's** mean end-of-season offense/defense over the training seasons (FCS about −14.6 power, D-II −24.7, D-III/unknown about −33). ρ (about 0.63) and λ_FCS = λ0·v̄_FBS / v_FCS (about 2.5–3.4) are unchanged. | Stage 3 (pools); frozen (ρ, λ_FCS) |
| **Group levels** | Two extra coefficients in the ridge. **Δ_FCS** shifts every non-FBS team's power by 2Δ_FCS; its column is non-zero only on FBS-vs-non-FBS rows (points and SR). **Δ_low** shifts D-II, D-III and unknown teams by 2Δ_low relative to FCS; its column is non-zero only on FCS-vs-lower rows. **Each has a ridge prior of precision 2·20 + 1e-4, worth about 20 games.** | **Stage 3** |
| **Anchors** | Δ_FCS's prior mean places the FCS-group mean prior power at **A_FCS** = the previous available season's end-of-season FCS level. Δ_low's prior mean places the lower-minus-FCS gap at the previous season's measured gap. **2020 is never used**, so 2021 uses 2019. The measurement is a points-only end-of-season fit (penalty 1 on teams, season home field) with both group levels free. Values for 2017–2025 are about −27.0 to −30.4 (FCS) and −29 to −36 (gap). | **Stage 3** |
| **Identification** | Ratings are centred on the FBS mean offense and mean defense. Intercept and SR intercept are unpenalized. Non-FBS reported offense = o − ō_FBS + Δ_FCS (+ Δ_low); defense = d − d̄_FBS − Δ_FCS (− Δ_low); power = offense − defense. | frozen, extended by Stage 3 |
| **Season opening** | Before any game, every FBS rating equals its prior. The group levels sit at their prior means. | frozen |
| **Predictions** | At the latest weekly cutoff before kickoff: margin = power_home − power_away + H·(not neutral). H is C2's home field (`r15_H`: 3.94, 3.31, 3.37, 3.48, 3.28 for 2017–22; 3.0685 for 2023–25). | frozen |
| **FBS vs non-FBS** | Same formula, using the non-FBS team's rating. **Before its first game** it uses its prior deviation plus the current solved group level(s) (`c2_fbs_vs_nonfbs`). | **Stage 3** (frozen C2 had no such path) |
| **Win probability** (downstream, evaluation only) | Φ(margin / σ). σ is fitted by maximum likelihood on development FBS-vs-FBS games, leave-one-season-out, and on all development seasons for 2023–25 (the R15 scorer rule). | frozen evaluation rule |
| **Games played** (reporting only) | `c2_games_played()` counts all final games before the cutoff, including FCS games. The rating system never reads games played. | Stage 4 (evaluation layer) |
| **Construction** | C1 priors, variance models, scale and λ0, and C2's β, κ, FCS moments, ω and end-of-season fits come from the frozen construction (`scripts/round15/c{1,2}_build.R`), reused as `output/dev/round15/cand/c{1,2}_components.rds`. The only new constructed quantities are the group pools and the anchors, computed in `c2_run()`. | frozen + Stage 3 |

## 3. Research history (Stages 0–4, `docs/c2r/`)

| Stage | What it established |
|---|---|
| **0**: data and pipeline check | The play-by-play supports any quarter-and-margin rule. C2 already filtered garbage time. There is no FCS-vs-FCS play-by-play. Frozen C2 had no FBS-vs-FCS prediction path. 28% of the FCS prior pool was lower-division. |
| **1**: FCS diagnosis | C2 rated the FCS group about 10.7 (development) / 11.3 (2023–25) points too high, while ordering FCS teams correctly. Cause: ridge shrinkage of the FCS block toward the FBS-centred scale, twice: end-of-season fits kept about half the level, and the in-season prior set 63–86% of it. Removing lower divisions from the pool alone would have worsened the bias. |
| **2**: garbage time | No filter (A0), the frozen rule (A) and Connelly's published 2019 rule (B) are indistinguishable in accuracy. Garbage time explains none of the FCS gap. **A kept.** |
| **3**: FCS level | Predeclared arms. The selection rule chose **in-model group levels** with 20-game anchor priors on last season's level, plus division pools (`L_last_n20`). Rejected: margin-only +X, fixed prior shift G(δ) (beaten by 0.0016), stronger FCS shrinkage (breaks calibration), a flat FCS level and a free level. The FCS level shows no drift. |
| **4**: preseason | Predeclared arms. gp = 0 ratings are mildly compressed in 2017–22 only. No preseason scale (global, offense-only, gp = 0-only) or faster decay (half-life 1–5) beat the current prior. A flexible probe put the optimum at the current strength. **Preseason prior kept unchanged.** |

## 4. Frozen Round 15 C2 vs current C2

### Behavior that changed (all from Stage 3)

1. **The non-FBS level relative to FBS is estimated in-model** (Δ_FCS), anchored at last season's measured FCS level
   (20-game prior).
   - Frozen C2 left the level to the ridge prior, which pulled it about 10 points toward FBS.
   - FCS mean rating: about −17.5 → about −28.5.
2. **Lower divisions are a separate group.**
   - They have their own prior pools (D-II; D-III/unknown) and their own level relative to FCS (Δ_low).
   - They no longer share the FCS pool mean. Their ratings drop about 31 points.
3. **FCS prior pools are division-specific.** The FCS mean is from FCS teams only.
4. **Non-FBS ratings and FBS-vs-non-FBS predictions are outputs.** That includes the first-game rule.
5. **FBS ratings change only through FBS-vs-FCS games.**
   - FBS teams no longer get credit for beating over-rated FCS opponents: +0.65 (no FCS opponent), −0.11 (one), −0.70
     (two), relative to frozen at season's end.
   - At early cutoffs with only FCS-vs-FCS games played, the shared scoring intercept moves FBS ratings by at most 0.02.
     That channel also exists in frozen C2.
6. **FBS-vs-FBS predictions** change by 0.52 points on average (maximum 4.45) once FBS-vs-FCS games exist. Before that
   they are identical.

### Results

| Metric | Development: frozen C2 | Development: current C2 | 2023–25: frozen C2 | 2023–25: current C2 |
|---|---|---|---|---|
| FBS-vs-FBS log-loss | 0.52613 | **0.52478** | 0.53040 | **0.52952** |
| FBS-vs-FBS MAE | 12.834 | **12.817** | 12.266 | 12.268 |
| Whole-system log-loss (FBS-vs-FBS + FBS-vs-FCS) | 0.49140 | **0.48348** | 0.48782 | **0.47487** |
| FBS-vs-FCS bias / MAE (all games) | −10.17 / 15.91 | **+1.52 / 13.60** | −11.73 / 15.53 | **+0.38 / 12.31** |
| FCS-vs-FCS MAE | 13.26 | **13.03** | 12.74 | **12.44** |

**Paired Δ log-loss, current − frozen** (R15 block bootstrap): development −0.0013 [−0.0028, +0.0001]; 2023–25 −0.0009
[−0.0021, +0.0003].

**Current − incumbent:** development −0.0073 [−0.0128, −0.0021]; 2023–25 −0.0066 [−0.0139, +0.0006].

### Deliberately not incorporated

| Idea | Stage | Why not |
|---|---|---|
| No garbage filter (A0); Connelly's 2019 rule (B) | 2 | Indistinguishable from A. |
| Margin-only FBS-vs-FCS +X | 3 | Benchmark only; fixes no rating. |
| Fixed FCS prior shift G(δ) | 3 | Beaten by the in-model level. |
| Free (unanchored) FCS level; fixed, expanding and rolling anchors | 3 | Not selected. The anchor type was immaterial; "last" was selected. |
| Pooled-μ and expanding-anchor simplifications | 3 | Post hoc or observational; would change the selected model. Left for a future predeclared round. |
| Stronger FCS shrinkage; a flat FCS level; an SR-only level column | 3 | Failed guardrails or not selectable. |
| Conference-level FCS anchoring | 1/3 | Identified residual; never tested. |
| Preseason scale (global, offense-only, gp = 0-only) | 4 | Not robust; rule kept 1.0. |
| Faster preseason decay (half-life 1–5) and scale + decay combinations | 4 | All worse. |
| Subgroup-specific decay | 4 | Descriptive only. |
| Any fix for the development first-game FBS-vs-FCS residual (+2.7) or blowout compression | 3/4 | Out of scope; left open. |

## 5. Validation (tag `c2-post-stage4-baseline`)

Run `Rscript tests/c2/run_all.R` from the worktree root. It needs `output/dev/round15`, a symlink to the frozen Round 15
caches.

- **Equivalence with C2L** (`validation/equivalence.csv`): 24 quantities are compared against the research code (re-run)
  and the stored Stage 3/4 artifacts.
  - FBS offense, defense and power; group levels; first-game ratings; all 6,266 predicted margins; win probabilities;
    anchors; the influence diagnostic: **identical (difference 0)**.
  - Non-FBS ratings: ≤ 2.8e-14, floating-point order of adding the group shift.
- **Regression vs frozen** (`validation/regression_*.csv`): 13 checks. There are **no unexpected differences**.
  - The ridge core without group columns reproduces frozen `r15_solve2` exactly at all 163 solved cutoffs.
  - These are all identical: the SR instrument, garbage thresholds, C1 prior, λ, scale a, β, κ, ω and H; the season
    openers.
- **Performance reproduction** (`validation/performance_reproduction.csv`): 272 stored Stage 3/4 numbers are re-derived.
  - Margin metrics match to about 1e-14.
  - Probability metrics match to ≤ 1.3e-9. That is the σ optimizer's tolerance: row order alone moves σ by 5e-7.

## 6. File map

| Path | Role |
|---|---|
| `R/c2/c2_current.R` | Current C2: `c2_run`, `c2_predict_season`, `c2_ridge_solve`, `c2_fbs_vs_nonfbs`, anchors, pools, divisions, `c2_games_played`. |
| `R/c2/c2_diagnostics.R` | Preseason-influence diagnostic (Stage 4). |
| `scripts/c2/c2_build_current.R` | Builds `output/c2/current/`: predictions (frozen schema + `model`), ratings, group levels, first-game ratings, FBS-vs-non-FBS predictions, anchors, divisions, manifest. |
| `scripts/c2/c2_verify_performance.R`, `tests/c2/*.R` | Validation. |
| `R/round15/candidates/*.R`, `scripts/round15/*` | Frozen Round 15 (historical; read-only helpers reused by current C2). |
| `scripts/c2r/*`, `docs/c2r/*` | Stage 0–4 research (reproducibility only; not on the model path). |
