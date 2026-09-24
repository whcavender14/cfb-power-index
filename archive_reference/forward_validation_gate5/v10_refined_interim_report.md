# v10 Refined: Interim Results Report (Gates 1–4)

**Report date:** 2026-09-21 · **Executed by:** Claude Code · **Results:** `archive/v10-round10/results/refined/`

## Executive Summary

v10_refined passes all four development and calibration gates. Development improvement is robust and the P4-vs-G5 bias reduction is large, but the conditional 2023–25 gain is not statistically significant. 2026 forward validation is the final decision point.

## 1. Gate Results Summary

| Gate | Threshold | Result | Status |
|---|---|---|---|
| 1. Dev MAE improvement | Δ ≤ −0.08 | −0.094 | PASS |
| 2. Dev bootstrap CI upper | ≤ 0 | −0.033 | PASS |
| 3. P4-vs-G5 bias reduction (cond.) | ≥ 0.5 points | 3.67 (3.44 → −0.23) | PASS |
| 4. Calibration slope (cond.) | [0.90, 1.10] | 0.972 | PASS |
| 5. 2026 forward test | TBD | Pending | PENDING |

## 2. Detailed Results

**Development (2018–19, 2021–22; n = 3,092):**
- Incumbent MAE 12.970; v10_refined 12.876
- Paired Δ −0.094 [−0.155, −0.033] (2,000-rep season+week block bootstrap, seed 42)
- P4-vs-G5 bias: 4.25 → 0.59 (2018–19); 7.10 → 3.37 (2021–22)

**Conditional (2023–25, calibration check only; n = 2,398):**
- Incumbent MAE 12.518; v10_refined 12.495
- Paired Δ −0.022 [−0.074, +0.024]
- P4-vs-G5 bias 3.44 → −0.23 (n = 318 games)
- Calibration slope 0.972 (incumbent 1.014)

**Coefficients (0.65 shrink, era-averaged):** a = 2.356, b = 1.831 → applied 4.19 (P4 home), 2.36 (P4 away/neutral); mean applied on 2023–25 P4-vs-G5 games 3.67 (frozen v10_candidate: 5.50).

## 3. Caveats & Limitations

**a) Circularity in gates 3–4.** The 0.65 factor was chosen so the applied correction (~3.6) matches the observed conditional bias (~3.4). It was fixed before refitting, but it was informed by the conditional data, so gates 3–4 are not independent tests. Gate 5 (2026) is the only clean validation.

**b) Conditional CI crosses zero.** [−0.074, +0.024] means the −0.022 MAE gain is not distinguishable from zero. The conditional set was heavily examined in diagnostics and is a calibration check, not an advancement gate.

**c) Development is in-sample.** The correction was fit on 2018–22 and evaluated on the same games. This confirms the fit was recovered; it is not evidence of generalization.

**d) Slight over-correction.** Conditional bias is −0.23. This is small relative to noise (318 games, residual SD ≈ 13 implies SE ≈ 0.7), so it is not evidence of a real over-correction, but neither does it show over-correction is "safe"; it is simply consistent with zero.

## 4. What the Results Mean

- ✓ Development improvement is present (−0.094, CI excludes 0), though in-sample.
- ✓ The correction removes the P4-vs-G5 bias on 2023–25 (partly by construction; see 3a).
- ✓ Calibration slope 0.972 is within [0.90, 1.10].
- ✗ No statistically significant MAE gain on recent data.
- ⏳ 2026 forward test required before promotion.

## 5. Next Steps

Run `v10_refined_2026_forward_validation_prompt.md` once 2026 results and v10_refined 2026 predictions exist (`v10_refined_predictions.csv` currently covers 2018–25 only; 2026 predictions must be generated with the frozen coefficients a = 2.356, b = 1.831, applied as `s × (a + b × p4_home)` to the 2026 incumbent). Decision rule as stated in that document.
