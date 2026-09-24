# Round 11 report — market gap autopsy + cross-conference tier effects

**Verdict: NOT PROMOTED.** The Change 2 development gate (inner holdouts
2018–2019) fails: adding a jointly-estimated P4/G5 tier random effect to the
incumbent's ridge rating solve reduces P4-vs-G5 bias by at most 1.35 points,
short of the required ≥2-point reduction, at every shrinkage value tested.
Change 3 (feature cleanup, fixed HFA) was conditioned on Change 2 passing and
is not applied. The incumbent `v5_EB_features` (frozen at Round 4) is
unchanged.

Development = 2018, 2019, 2021, 2022 (3,092 games). Conditional = 2023–2025
(2,398 games). No new data sources; no manual tuning — the tier shrinkage
grid and the development/conditional split were fixed before results were
inspected.

## Change 1: market gap autopsy

The incumbent trails the closing line by 0.52 MAE on conditional
(12.518 vs. 12.00). Stratifying every conditional game's
`|incumbent_pred − market_line|` by cross-conference matchup, week, and
incumbent confidence:

| Stratum | Games | Mean abs. disagreement | Incumbent MAE | Market MAE | Incumbent bias (actual − pred) |
|---|---|---|---|---|---|
| P4 home vs. G5 away | 228 | 4.86 | 12.97 | 11.88 | **+3.89** |
| G5 home vs. P4 away | 62 | 4.65 | 12.93 | 11.89 | +3.89 |
| P4 vs. P4 | 947 | 3.07 | 12.26 | 11.93 | −0.52 |
| G5 vs. G5 | 868 | 3.14 | 12.63 | 12.20 | −0.40 |
| Early season (week ≤ 4) | 739 | 4.39 | 12.82 | 11.84 | — |
| Mid season (week 5–9) | 805 | 3.12 | 12.44 | 11.83 | — |
| Late season (week 10+) | 854 | 2.76 | 12.33 | 12.18 | — |

Full stratum table: [market_gap_diagnosis.csv](../../../outputs/round11/market_gap_diagnosis.csv).
Game-level detail: [market_gap_game_level.csv](../../../outputs/round11/market_gap_game_level.csv).

**Decision gate result:** P4-vs-G5 games account for only **17.2%** of total
disagreement (threshold for "structural" was >50%); early-season games
account for 40.0% (threshold for "preseason information problem" was >50%).
Neither crosses its bar, so the mechanical gate calls this **noise /
uncaptured public information** — but the one number that stands out from
every other stratum is the +3.89-point incumbent bias specifically in P4-home
vs. G5-away games (all other strata sit within ±1.6 points of zero). That
single pattern — not the overall share of disagreement — is what motivated
testing a tier effect in Change 2, even though the aggregate gate said
"noise." The result below shows that pattern doesn't survive as a
generalizable, jointly-estimable structural effect.

## Change 2: cross-conference tier effect in the core rating solve

**What was built.** The incumbent's current-season rating is a ridge solve
over team offense/defense scores shrunk toward a feature-informed preseason
prior (`v4_score_fit`, called from `v4_ratings`'s EB branch — see
`archive/v5-round4/code/cfb_power_ratings_v5.R:657,793`). `cfb_power_ratings_v11.R`
extends that exact joint solve with two additional global, ridge-shrunk
parameters, τ_G5 and τ_Other (τ_P4 = 0, reference level), estimated in the
same normal-equation system as every team's own coefficients — not fit
post-hoc, and not a separate correction step. `lambda_tier` is the "shrinkage
scale" hyperparameter. Verified to reproduce the real incumbent's predictions
exactly (max diff ~5e-14 vs. `outputs/round4/development_predictions.csv` /
`conditional_predictions.csv`) when `lambda_tier = 0`, confirming the
extension is a faithful superset of the frozen production code, not a
parallel reimplementation.

**Development gate (Step 1, inner holdouts 2018–2019).** Grid over
`lambda_tier ∈ {0,1,2,4,8,16,32,64}`, pooled across the two holdout seasons
(1,546 games):

| lambda_tier | Pooled MAE | Pooled P4-vs-G5 bias | Bias reduction vs. incumbent | MAE Δ |
|---|---|---|---|---|
| 0 (incumbent) | 12.916 | 4.318 | — | — |
| **1 (best)** | 12.874 | 2.971 | **1.35** | −0.042 |
| 4 | 12.882 | 3.125 | 1.19 | −0.034 |
| 16 | 12.894 | 3.463 | 0.85 | −0.022 |
| 64 | 12.906 | 3.891 | 0.43 | −0.010 |

Full grid: [tier_inner_grid.csv](../../../outputs/round11/tier_inner_grid.csv),
[tier_inner_pooled_selection.csv](../../../outputs/round11/tier_inner_pooled_selection.csv).

Gate: bias reduction ≥ 2 points with no MAE increase. Every `lambda_tier`
improves MAE slightly, but the best bias reduction (1.35 points at
`lambda_tier = 1`) never reaches the 2-point bar.
[gate1_dev_inner_tier_effect.csv](../../../outputs/round11/gate1_dev_inner_tier_effect.csv):
**FAIL.**

For context only (not a gated result, since Step 1 already failed): running
the same `lambda_tier = 1` on the full 4-season development pool (3,092
games) gives a bias reduction of 1.76 points (4.336 → 2.571) and a small MAE
improvement (12.989 → 12.956) —
[tier_full_development_diagnostic_only.csv](../../../outputs/round11/tier_full_development_diagnostic_only.csv).
Consistent with the inner-holdout result: directionally real, but not large
enough to clear the predeclared bar, and note the bias never reaches zero at
any shrinkage — a two-level P4/G5 fixed effect only partially captures
whatever is driving the P4-home-vs-G5-away gap.

**Per the Round 11 fallback**, since the development gate fails, the tier
effect is not locked, not applied to conditional, and Change 3 (talent
removal, fixed HFA) is not applied since it was conditioned on Change 2
passing. The incumbent is unchanged.

## Honest limitations

- Round 4's own development split started at 2019 because `v4_pre()`'s
  preseason-feature regression needs two full prior seasons of history (2015
  is a mandatory burn-in year) and 2017 alone falls below its hardcoded
  200-row minimum. To honor this round's brief (development including 2018,
  3,092 games), 2018 was bootstrapped using the same 80-row minimum
  `v5_config()` already uses elsewhere for per-regime feature estimation
  (`v11_fit_preseason80`/`v11_pre80`/`v11_components_bootstrap` in
  `cfb_power_ratings_v11.R`), with 2017 as its sole calibration season. This
  is a disclosed deviation from Round 4's exact bootstrap window, not a new
  invented threshold.
- The tier effect is a two-level (P4/G5, with FBS Independents and other
  conferences pooled as "Other") global fixed effect on the opponent's tier,
  shared across all teams and all weeks within a season. It cannot capture
  team-specific or week-specific cross-tier effects; a richer structure
  (e.g., a tier effect that varies by season, or interacts with rest/travel)
  was out of scope for this round and is a candidate for Round 12 if the
  P4-home-vs-G5-away bias persists.
- The Change 1 decision gate is a fixed 50% share-of-disagreement rule, which
  called the pattern "noise" even though the one visibly anomalous stratum
  (P4 home vs. G5 away, +3.89 bias) motivated testing a tier effect anyway.
  Both readings are reported above rather than picking one.

## Conclusion for Round 12

Cross-conference tier structure is a real but small effect (~1.3–1.8 points
of the ~4.3-point P4-vs-G5 bias), not the dominant driver of the 0.52-point
market gap. The gap is better described as diffuse — present at low
magnitude in nearly every stratum — than concentrated in any one segment the
autopsy checked (tier, week, confidence). Round 12 should treat the market
gap as likely reflecting information the model structurally cannot see
(e.g., injury news, weather, line movement, sharp money) rather than a
fixable structural mis-specification in the rating solve.
