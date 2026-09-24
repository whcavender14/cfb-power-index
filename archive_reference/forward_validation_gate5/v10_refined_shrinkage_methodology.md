# v10 Refined: Empirical-Bayes Shrinkage Methodology (v10_refined_v2, candidate)

**Date:** 2026-09-22 · **Data used:** development only (2018–19, 2021–22). No conditional (2023–25) or 2026 data touched. **Status: parallel candidate, not a replacement.** The frozen `v10_refined` parameters (a=2.356, b=1.831) and the predeclaration are unmodified.

## Motivation

The flat 0.65 shrink was chosen so the applied correction (~3.6) would roughly match the observed conditional bias (~3.4) — fitting to data it was meant to be validated against, even though the constant itself was fixed before refitting. This replaces it with a shrinkage factor derived only from how much the two development eras agree with each other, via a James-Stein / empirical-Bayes estimator.

## Method

For each coefficient (intercept `a`, home slope `b`) separately, with era A = 2018–19 and era B = 2021–22:

1. Between-era variance: `τ² = max(0, (est_A − est_B)² / 2 − mean(SE_A², SE_B²))`
2. Per-era shrinkage weight: `λ_era = τ² / (τ² + SE_era²)`
3. Pooled (inverse-variance-weighted) mean: `pooled = (est_A/SE_A² + est_B/SE_B²) / (1/SE_A² + 1/SE_B²)`
4. Each era's estimate shrunk toward pooled: `shrunk_era = λ_era·est_era + (1−λ_era)·pooled`
5. Final: mean of the two shrunk-era estimates

## Inputs (OLS on P4-oriented incumbent residual ~ 1 + p4_home, same specification as the flat-0.65 fit)

| Era | a | SE(a) | b | SE(b) | n |
|---|---|---|---|---|---|
| 2018–19 | 2.007 | 2.245 | 3.158 | 2.663 | 197 |
| 2021–22 | 5.241 | 2.420 | 2.477 | 2.792 | 169 |

## EB computation

For both `a` and `b`, `τ² = 0`: the gap between the two eras' point estimates is smaller than the sampling noise implies (e.g. for `a`: (5.241−2.007)²/2 = 5.23, vs. mean SE² = 5.44 — the observed spread is fully explained by noise). With τ²=0, `λ_A = λ_B = 0` for both coefficients: the EB estimator pools completely rather than partially. This means, under this method with only two eras and these sample sizes, empirical Bayes cannot statistically distinguish the eras from each other and applies **no differential shrinkage between the two fits** — it just takes their inverse-variance-weighted average.

| Coefficient | Pooled value | Unshrunk simple era average |
|---|---|---|
| a (intercept) | 3.503 | 3.624 |
| b (P4-home slope) | 2.834 | 2.818 |

**Resulting parameters: a_EB = 3.503, b_EB = 2.834.**

## Comparison to the flat-0.65 rule

| | a | b | Applied, P4 home (a+b) | Applied, P4 away/neutral (a) |
|---|---|---|---|---|
| Flat 0.65 (frozen, unchanged) | 2.356 | 1.831 | 4.187 | 2.356 |
| EB (this candidate) | 3.503 | 2.834 | 6.336 | 3.503 |
| Unshrunk era average (τ²=0 reference point) | 3.624 | 2.818 | 6.442 | 3.624 |

Implied effective shrink relative to the raw unshrunk average: **a: 0.966, b: 1.006** — i.e. essentially no shrinkage at all (≈ 1.0), not close to 0.65.

**This is the opposite of what step 7 anticipated.** The EB-derived factor is not "close to 0.65"; it applies a *larger* correction than the original frozen v10_candidate ever did (5.50 mean applied on P4-vs-G5 games), which Round 10 rejected for overshooting. Read plainly: given only two development-era point estimates and their standard errors, there isn't enough information to detect that 2021–22 behaves differently from 2018–19 — the apparent 7.10-vs-4.25 bias gap (from the earlier diagnostic, computed directly on residual means rather than regression coefficients) is, under this SE-based method, statistically consistent with a single shared effect. EB has no mechanism here to encode the outside prior belief that 2021–22 is an outlier; it only sees two noisy point estimates that don't clear the bar for "significantly different," so it pools them fully rather than discounting either one.

## Gates 1–2 (development only; conditional and 2026 not touched)

Same specification, seasons, and 2,000-replicate season+week block bootstrap (seed 42) as the flat-0.65 run.

| | Flat 0.65 (`v10_refined`) | EB (`v10_refined_v2`) |
|---|---|---|
| Dev MAE, incumbent | 12.970 | 12.970 |
| Dev MAE, candidate | 12.876 | 12.858 |
| Paired Δ MAE | −0.094 | −0.111 |
| 95% CI | [−0.155, −0.033] | [−0.198, −0.028] |
| Gate 1 (Δ ≤ −0.08) | PASS | PASS |
| Gate 2 (CI upper ≤ 0) | PASS | PASS |

`v10_refined_v2` passes gates 1–2 with a larger point-estimate improvement on development than the flat-0.65 version, and a wider CI (expected — its correction magnitude is larger and less constrained).

## Assessment

This is being staged as `v10_refined_v2`, **not** as a replacement, for three reasons:

1. **It differs meaningfully from 0.65** — per the task's own branching instruction (step 6), that means staging it as a separate candidate for its own gate 5 test, not treating it as confirmation of the existing frozen parameters (step 7 does not apply here).
2. **It moves in the direction the diagnostic warned against.** The whole reason 0.65 shrinkage exists is the belief that 2021–22 (7.10 bias) is an outlier relative to 2018–19 (4.25) and 2023–25 (3.44), and that applying the full averaged effect overshoots. EB, using only the two-era point estimates and their standard errors with no outside information about which era is atypical, cannot see that pattern — it sees two estimates whose difference doesn't clear statistical significance at n≈170–200 each, and pools them fully. The result (6.34 applied on P4-home games) is larger than even the original frozen `v10_candidate`'s 5.50, which conditional data already showed overshooting toward zero net effect. This is a real methodological tension, not a bug: EB is the statistically principled answer to "how much do these two eras agree," but it is silent on the substantive prior (a plausible generational/COVID-era anomaly in 2021–22) that motivated distrusting era B in the first place.
3. **Passing gates 1–2 doesn't discriminate between the two candidates.** Both pass; development data alone can't tell them apart, because development is exactly the data both were fit to. The two candidates make sharply different predictions about 2023–25/2026 magnitude (3.6 vs. 6.3+ applied), which is precisely what conditional/2026 data would distinguish — and precisely what this step was told not to touch.

## Disposition

- **Frozen parameters unchanged:** `v10_refined` stays at a=2.356, b=1.831. No predeclaration edited.
- **`v10_refined_v2` staged, not evaluated against 2023–25 or the 34 already-seen 2026 games.** Its coefficients: a=3.503, b=2.834.
- **When n≈100–150 P4-vs-G5 games are reached** (per the existing re-check cadence in `v10_refined_2026_interim_check.md`), run the same gate 5 forward test on both `v10_refined` and `v10_refined_v2` side by side. Given the EB variant's much larger applied correction, expect it to be more exposed to overshoot risk if 2021–22-style bias doesn't recur, and correspondingly better if the true current bias is closer to the higher end of the observed development range. This is exactly the open question gate 5 was designed to answer, and it should not be prejudged from development-only fit quality.
- No action needed on the interim check's HFA finding or re-check cadence; both stand as previously documented.
