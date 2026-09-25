# C2 Refinement Research: Stage 3 Plan (fixed before any Stage 3 result is computed)

**Date:** 2026-09-25. **Branch:** `c2-refinement`.
- This file is committed before any Stage 3 arm is run.
- Every grid, arm and selection rule below is fixed here. Nothing is searched continuously or added after results are
  seen. The one exception is a clearly labelled "post hoc" item in the report.

**What stays fixed.** The garbage-time rule is treatment A (frozen). Every non-FCS part of C2 is frozen:
- the C1 prior, λ, scale, ω, β, κ and home field;
- the end-of-season points fits.

**Only the treatment of non-FBS teams changes.**

## 1. Arms

| Family | Arms | What changes |
|---|---|---|
| **C0** | frozen C2 | Nothing. First game: C2's own prior mean (the Stage 1 rule). |
| **M(X)**, matchup benchmark | X ∈ {0, 4, 6, 8, 10, 12, 14} | Add X to every predicted FBS margin in FBS-vs-FCS games, including first games. No rating changes. **Benchmark only; not eligible for selection.** |
| **G(δ)**, global rating-level offset | δ ∈ {4, 6, 8, 10, 12, 14} | Every non-FBS prior mean moves down by δ power points (off −δ/2, def +δ/2), in-season and for first games, and the whole system is re-solved. Relative priors are unchanged. See note (a). |
| **L(anchor, n0)**, data-derived group levels | anchor ∈ {fixed, expanding, rolling3, last}; n0 ∈ {0, 20} | Two group-level parameters are added to C2's ridge (defined below). Division-specific prior means replace the pooled mean (no lower-division contamination). Team priors, λ_FCS and ρ are unchanged. |
| **S(k)**, FCS shrinkage after the level is corrected | k ∈ {1, 2, 4} × λ_FCS, on the selected L and on the selected G; plus a **flat** reference (ρ = 0, λ × 10⁴: every team equals its group level) on the selected L | Stronger pull of each team toward its (corrected) prior. |
| **L-sr** (sensitivity, not selectable) | selected L plus a free SR-only level column | Lets FBS-vs-FCS SR rows carry their own level. Stage 2 found β does not transfer 1:1 to mismatches. |

**Note (a).**
- With the prior setting 63–86% of the level, a prior shift of δ moves the in-season level by roughly 0.65–0.9 δ.
- "δ" is the correction to the prior level, the only way to shift the level inside the rating system without new
  parameters.
- The realized level shift is reported.

### The L structure (the principled anchor)

**Two group-level coefficients are added to C2's ridge system.**
- **Δ_FCS** shifts every non-FBS team's power by the same amount. Its column is X·t, where t = +1 on non-FBS offense and
  −1 on non-FBS defense.
  - It is non-zero only on FBS-vs-non-FBS rows, points and SR, so only linking games inform it.
  - FCS-vs-FCS games inform the relative ratings only.
- **Δ_low** shifts D-II, D-III and unknown teams relative to FCS.
  - It is non-zero only on FCS-vs-lower-division rows. FBS teams never play these teams: 0 such games in 2014–2025
    except 2 in 2020.

**Team power is the group level plus the team deviation.** A team's power = its group level + its own penalized
deviation. The deviation is shrunk toward its relative prior, **ρ·(last season − its division's mean)**, with C2's λ_FCS.

**Prior means use division pools.** μ comes from FCS teams only for FCS, from D-II teams for D-II, and from D-III and
unknown teams pooled. Nothing else in the pool rule changes.

**Level priors:**
- Δ_FCS is penalized toward the value that puts the FCS-division mean power at the **anchor**, with a precision
  equivalent to **n0 FBS-vs-FCS games** (λ_L = 2·n0).
- Δ_low is penalized toward the historical lower-vs-FCS gap, with the same n0.
- **n0 = 0** means free: a 10⁻⁴ ridge keeps the solve defined when a cutoff has no linking game, and then returns the
  anchor.

**First game** (an FCS team not yet in the solve): its prior deviation plus the current solved group level(s). This is
exactly what the system gives a team with no games yet.

**Anchors** (FCS-division mean power relative to the FBS mean) come from **end-of-season fits with both level columns
free**, penalty 1 on teams, using only seasons before the target. 2020 is excluded from every anchor window.
- **fixed:** the mean of 2013–2016, one constant for all seasons;
- **expanding:** the mean of 2013 .. y−1;
- **rolling3:** the mean of the last three seasons before y;
- **last:** the last season before y.

## 2. Evaluation (every arm)

| Game set | Metrics |
|---|---|
| **FBS vs FBS** (R15 universe: 3,868 development, 2,398 in 2023–25) | Log-loss, Brier (σ fitted leave-one-season-out per arm, R15 rule), MAE, RMSE, winners, calibration slope, P4-vs-G5 bias, slices by games played and season, rating stability. Paired Δ vs C0 with R15's block bootstrap. |
| **FBS vs FCS** (all 561 development / 365 2023–25 games after the first cutoff) | Bias, MAE, RMSE, winners, log-loss and Brier (the arm's σ), predicted-margin distribution, by season, by FCS and FBS strength, first game vs later. |
| **FCS vs FCS** (both teams rated) | MAE, RMSE, bias, calibration slope, rank correlation. |
| **Ratings** (final cutoff of each season) | FCS mean and SD; Spearman correlation of FCS ranks vs C0; FBS rating change, split by number of FCS opponents; strength of schedule (mean end-of-season opponent power); FBS win probability vs FCS opponents (simulation input). |

## 3. Selection (development 2017–19 and 2021–22 only; 2023–25 is descriptive)

1. **Objective J** = log-loss over all development games involving an FBS team: the FBS-vs-FBS universe plus every
   FBS-vs-FCS game, with first games under each arm's own first-game rule. Each arm uses its own FBS-vs-FBS σ.
2. **Within a family,** the grid value is chosen **leave-one-season-out** over the five development seasons. The
   held-out season is scored with the value chosen on the other four, and that honest J is the family's score. The value
   carried forward, to 2023–25 and into S(k), is the one chosen on all five seasons.
3. **Eligibility.** An arm must:
   - **(a)** improve J vs C0;
   - **(b)** not worsen FBS-vs-FBS log-loss by more than +0.0005 (point estimate);
   - **(c)** keep the FCS-vs-FCS MAE within +0.10 of C0, with a calibration slope in [0.90, 1.10].
4. **Choosing between families.** Among eligible families (G, L, S), the order of simplicity is G < L < S. Choose the
   simplest family whose honest J is within **0.0005** of the best eligible honest J. M(X) is reported as the benchmark.
5. **Also reported for judgment, not used as a hard rule:**
   - the season-by-season stability of the FBS-vs-FCS bias;
   - whether the correction lives in the ratings (G, L, S) or only in the predictions (M).

## 4. The FCS level over time (analysis, not an arm)

1. **Per-season level.** The end-of-season FCS level (both columns free) for 2013–2025, with an analytic SE.
2. **Is there a trend?** A weighted test for linear trend, and a heterogeneity test against a constant.
3. **Composition:**
   - a fixed panel of FCS teams present in every season;
   - teams entering and leaving FCS (from D-II, or to FBS);
   - the strength of the FCS teams FBS programs schedule;
   - the lower-division share.
4. **Two level measures.** The Stage 1 in-slice "implied level" is compared with the end-of-season level.

The anchor comparison in §1 (fixed / expanding / rolling3 / last) is the prospective test. Every anchor uses only
seasons before the target, so none needs the current season's results.
