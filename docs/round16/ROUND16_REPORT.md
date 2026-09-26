# Round 16 Report: Qualification of Current C2

**Formal run:** once, 2026-09-26 00:01:57Z → 00:04:23Z UTC, exit 0 (log: `docs/round16/r16_run.log`).

**Frozen inputs:**
- predeclaration `9868031f…` (commit `6170d66`, tag `round16-predeclared`);
- scorer `8752d204…` (commit `9aca068`, tag `round16-scorer-frozen`);
- Current C2 `6a187ea` (tag `c2-post-stage4-baseline`).

**Results:** `docs/round16/results/` (27 files), hashed in `results.sha256` (sha256 of that file:
`1f035c41eaca2a581d1fd4c0db9ca23767384e780f2799f592968b44d1f7db07`).

**Nothing** was tuned, repaired or reinterpreted after scoring.
- The two items labelled **exploratory** (§12) have no decision power.
- One defect in a report-only table is disclosed there.

## 1. Formal verdict

> **QUALIFIED (historical): PRODUCTION CANDIDATE.** Current C2 satisfied every predeclared historical qualification
> standard (G0–G7) and may advance to independent forward confirmation. **This is not independent proof that the model is
> superior:** the historical seasons influenced its development (predeclaration §0). Independent confirmation can only
> come from the forward test (§9 of the predeclaration), which has **not** been activated.

**Stage 3 secondary claim (fixed sequence after G1): CONFIRMED.**

## 2. Every gate

C = Current C2, I = incumbent, C2f = frozen Round 15 C2. Development means 2017–19 and 2021–22 unless stated.

| Gate | Threshold | Observed | Interval | Result |
|---|---|---|---|---|
| **G0** integrity | All of G0a–G0e | 17 checks: hashes, rebuild byte-identical, `run_all.R`, leakage, identical universes | — | **PASS** |
| **G1** primary | Δ log-loss(C − I) ≤ −0.0020 **and** 95% upper < 0 | **−0.00729** | 95% [−0.01283, −0.00207] | **PASS** |
| G2a Brier | Δ Brier ≤ 0 | −0.00327 | 95% [−0.00570, −0.00100] | **PASS** |
| G2b probability calibration | Recalibration slope in [0.90, 1.10]; \|CITL\| ≤ 0.02 | slope 1.006; CITL +0.0052 | — | **PASS** |
| G3a MAE | Δ ≤ +0.020, and 95% lower ≤ 0 | −0.156 | 95% [−0.283, −0.027] | **PASS** |
| G3b RMSE | Δ ≤ +0.030 | −0.179 | 95% [−0.324, −0.039] | **PASS** |
| G3c bias | \|bias(C)\| ≤ \|bias(I)\| + 0.50 | \|0.687\| vs \|0.639\| + 0.50 | — | **PASS** |
| G3d raw calibration | Pooled slope in [0.90, 1.10] | 0.998 | 90% [0.962, 1.035] | **PASS** |
| G4 gp buckets (all games) | No bucket outside [0.80, 1.20] **and** 90% interval wholly outside on that side | 0: 1.225; 1: 1.195; 2–3: 1.032; 4–6: 0.855; 7+: 0.993 | gp 0 90% [1.134, 1.311] | **PASS** |
| G5a FBS-vs-FCS bias | \|bias\| ≤ 3.0 | +1.515 | 95% [+0.11, +3.08] | **PASS** |
| G5b FBS-vs-FCS MAE | ≤ C2f, and ≤ I(−25) + 0.25 | 13.595 vs C2f 15.912, I 15.354 | — | **PASS** |
| G5c first games | \|bias\| ≤ 4.0 | +2.689 | 95% [−0.24, +5.91] | **PASS** |
| G5d FCS vs FCS | Slope [0.90, 1.10]; MAE ≤ C2f + 0.10; Spearman ≥ C2f − 0.02 | 1.064; 13.034 vs 13.261; 0.608 vs 0.583 | — | **PASS** |
| G5e FCS level | Each dev season: \|final − anchor\| ≤ 4.0; mean \|Δ\| from cutoff 4 ≤ 0.50 | gaps +0.56, −2.88, +0.78, +1.48, −2.30; mean \|Δ\| 0.08–0.14 | — | **PASS** |
| G6a seasons | No season with Δ > +0.003 **and** 90% lower > 0 | none > +0.003 (§4) | — | **PASS** |
| G6b stage | Fail only if Δ > +0.001 **and** 90% lower > 0 | gp 0–3: −0.0074; gp 4+: −0.0072 | 90% [−0.0176, +0.0031]; [−0.0120, −0.0028] | **PASS** |
| G6c P4 vs G5 | \|bias(C)\| ≤ \|bias(I)\| | 4.420 vs 5.768 | — | **PASS** |
| G6d stability | Mean \|ΔP\| and top-25 Kendall ≤ 1.25 × I | \|ΔP\| 0.943 vs 0.799 (ratio 1.18); Kendall 0.0767 vs 0.0734 (1.04) | — | **PASS** |
| G6e market safety | β_E(C) ≥ β_E(I) − 0.10 and 95% upper ≥ 0 (close) | −0.006 vs −0.008 | 95% [−0.131, +0.114] | **PASS** |
| G7-ll | 2023–25 Δ log-loss ≤ +0.001 | −0.00664 | 95% [−0.01382, +0.00039] | **PASS** |
| G7-mae | Δ MAE ≤ +0.030 | −0.250 | 95% [−0.393, −0.109] | **PASS** |
| G7-slope | Pooled slope [0.90, 1.10] | 0.982 | — | **PASS** |
| G7-tier | \|P4-vs-G5\| ≤ I's | 0.338 vs 3.441 | — | **PASS** |
| G7-market | β_E(C) ≥ β_E(I) − 0.10 (close) | 0.232 vs 0.017 | — | **PASS** |
| G7-seasons | No 2023–25 season failing the §7 rule | none > +0.003 | — | **PASS** |
| G7-G5a / G5c / G5d / G5e | As G5 on 2023–25 | bias +0.382; first −0.138; FCS-vs-FCS 1.074 / 12.441 vs 12.744 / 0.614 vs 0.591; gaps +0.79, −2.88, −2.14 | — | **PASS** |

**Closest margins:**
- **G6d stability:** Current C2's ratings move 18% more week to week than the incumbent's; the limit is 25%.
- **G4 gp 0:** point estimate 1.225, above 1.20; it passes only because its 90% interval is not wholly above 1.20 (the
  approved rule).
- **G5e:** 2018 and 2024 end about 2.9 points from their anchors; the limit is 4.
- **G5c:** first-game bias +2.7, whose 95% interval reaches +5.9.

## 3. Primary comparison: Current C2 vs the incumbent (FBS vs FBS)

| | Development: I | Development: C | 2023–25: I | 2023–25: C |
|---|---|---|---|---|
| Games | 3,868 | 3,868 | 2,398 | 2,398 |
| **Log-loss** | 0.53207 | **0.52478** | 0.53616 | **0.52952** |
| Brier | 0.17963 | 0.17636 | 0.18202 | 0.17972 |
| MAE | 12.972 | 12.817 | 12.518 | 12.268 |
| RMSE | 16.350 | 16.171 | 15.787 | 15.427 |
| Bias (mean pred − actual) | +0.639 | +0.687 | −0.043 | +0.169 |
| Winner accuracy | 72.18% | 72.65% | 71.89% | 72.10% |
| Raw calibration slope | 1.075 | 0.998 | 1.015 | 0.982 |
| σ (probability scale) | 14.94 | 15.65 | 14.94 | 15.65 |
| Recalibration slope / CITL | 1.013 / +0.010 | 1.006 / +0.005 | 1.009 / +0.003 | 1.025 / +0.001 |

**Δ (C − I), development, 95%:**
- log-loss **−0.00729 [−0.01283, −0.00207]**;
- Brier −0.00327 [−0.00570, −0.00100];
- MAE −0.156 [−0.283, −0.027];
- RMSE −0.179 [−0.324, −0.039].

**Report-only sensitivities:**
- Fixed σ = 14 / 16 / 18 gives Δ log-loss −0.0062 / −0.0078 / −0.0088, each with a 95% upper bound below 0.
- AUC: I 0.7981, C 0.8062.

**The result does not depend on the probability scale.**

## 4. Season robustness (development, C − I log-loss)

| Season | Δ | 90% interval | Above +0.003? | Formal veto? |
|---|---|---|---|---|
| 2017 | −0.0075 | [−0.0197, +0.0043] | no | no |
| 2018 | **+0.0024** | [−0.0059, +0.0100] | no (below materiality) | no |
| 2019 | −0.0127 | [−0.0245, −0.0019] | no | no |
| 2021 | −0.0073 | [−0.0181, +0.0036] | no | no |
| 2022 | −0.0113 | [−0.0186, −0.0037] | no | no |

- **No development season exceeds the +0.003 materiality threshold,** so nothing is flagged or vetoed.
- 2018 is the only season where C is nominally worse than the incumbent.
- **Cochran Q = 5.42 on 4 df, p = 0.247:** no evidence the seasonal effects differ beyond noise.
- **Round 15's old G2f would also have passed:** 2018's +0.0024 is below +0.003. Frozen C2 had +0.0055 in 2018; the Stage
  3 fix moved 2018 by −0.0030.
- **2023–25 seasons:** −0.0045, −0.0057, −0.0097. None flagged.

## 5. Calibration by games played (approved all-games definition)

| gp bucket (min of the two teams) | n | C slope [90%] | I slope | Δ log-loss C − I |
|---|---|---|---|---|
| 0 | 289 | 1.225 [1.134, 1.311] | 1.273 | −0.0083 |
| 1 | 262 | 1.195 [1.101, 1.270] | 1.287 | −0.0170 |
| 2–3 | 615 | 1.032 [0.942, 1.130] | 1.123 | −0.0029 |
| 4–6 | 950 | 0.855 [0.797, 0.911] | 0.936 | −0.0092 |
| 7+ | 1,752 | 0.993 [0.948, 1.037] | 1.062 | −0.0061 |
| **gp 0–3 vs 4+** | 1,166 / 2,702 | — | — | −0.0074 [90% −0.0176, +0.0031] / −0.0072 [−0.0120, −0.0028] |

**Reading.**
- **Early-season predictions are compressed in every model:** slopes above 1 at gp 0–1, and larger for the incumbent.
- **gp 4–6 is mildly over-spread** (0.855).
- **Current C2 beats the incumbent in every bucket.**

**Sensitivity, R15's FBS-only gp count (no decision power).**
- C slopes: 1.194, 1.144, 1.004, 0.859, 0.981.
- Δ log-loss: −0.0119, −0.0084, −0.0080, −0.0102, −0.0035.
- Under R15's literal point rule with R15's gp count, all five buckets would pass. Under the literal point rule with the
  all-games count, gp 0 (1.225) would fail, as would the incumbent's 1.273.

2023–25 buckets and slopes are in `calibration_slopes.csv` and `slice_deltas.csv`.

## 6. FCS guardrails

| | Development: C | Development: C2f | Development: I (−25) | 2023–25: C | 2023–25: C2f |
|---|---|---|---|---|---|
| FBS-vs-FCS bias (all) | **+1.52** | −10.17 | −1.74 | **+0.38** | −11.73 |
| FBS-vs-FCS MAE | **13.60** | 15.91 | 15.35 | **12.31** | 15.53 |
| RMSE / log-loss | 16.86 / 0.199 | 19.71 / 0.252 | 18.91 / 0.217 | 15.30 / 0.116 | 19.33 / 0.208 |
| First games: bias / MAE | +2.69 / 14.72 | −9.36 / 16.08 | −0.53 / 15.80 | −0.14 / 12.18 | −12.32 / 15.49 |
| Later games: bias / MAE | +0.72 / 12.83 | −10.72 / 15.80 | −2.56 / 15.05 | +0.76 / 12.41 | −11.31 / 15.56 |
| FCS vs FCS: MAE / slope / Spearman | 13.03 / 1.064 / 0.608 | 13.26 / 1.001 / 0.583 | — | 12.44 / 1.074 / 0.614 | 12.74 / 1.020 / 0.591 |

**FCS level stability.**
- Final-cutoff level minus anchor, by season: 2017 +0.56, 2018 −2.88, 2019 +0.78, 2021 +1.48, 2022 −2.30, 2023 +0.79,
  2024 −2.88, 2025 −2.14.
- The level is steady within each season (mean |Δ| per cutoff 0.08–0.14 from cutoff 4).

**FBS credit** (final cutoff, change vs C2f):
- teams with 0 / 1 / 2 FCS opponents: +0.65 / −0.11 / −0.70 (development) and +0.59 / −0.06 / −0.74 (2023–25).

## 7. Stage 3 increment: Current C2 vs frozen Round 15 C2

| C − C2f | Development [95%] | 2023–25 [95%] |
|---|---|---|
| **Whole-system log-loss (J)** | **−0.0079 [−0.0125, −0.0036]** (0.48348 vs 0.49140) | −0.0129 [−0.0201, −0.0064] |
| FBS-vs-FBS log-loss | −0.00134 [−0.00283, +0.00008] | −0.00088 [−0.00211, +0.00029] |
| FBS-vs-FBS Brier | −0.00045 [−0.00105, +0.00011] | −0.00031 [−0.00078, +0.00015] |
| FBS-vs-FBS MAE | −0.018 [−0.043, +0.007] | +0.002 [−0.023, +0.029] |
| FBS-vs-FBS RMSE | −0.035 [−0.065, −0.008] | −0.013 [−0.038, +0.012] |
| FBS-vs-FCS absolute error | −2.32 [−3.20, −1.49] | −3.22 [−4.10, −2.17] |
| FBS-vs-FCS log-loss | −0.053 [−0.085, −0.021] | −0.092 [−0.116, −0.066] |

**Verdict under the frozen fixed-sequence rule: "Stage 3 adds value": CONFIRMED.**
- (i) The whole-system upper bound is −0.0036, below 0.
- (ii) The FBS-vs-FBS upper bound is +0.00008, below the +0.001 non-inferiority margin.
- **Not claimed:** FBS-vs-FBS superiority. Its interval includes 0.

## 8. 2023–2025 (non-degradation only; not qualification evidence)

These seasons have been examined repeatedly and carry only the non-degradation role (G7).
- **All G7 checks pass.**
- Δ log-loss vs the incumbent −0.0066 [−0.0138, +0.0004]; MAE −0.250 [−0.393, −0.109].
- Every season better than the incumbent; P4/G5 bias 0.34 vs 3.44; FCS guardrails met.
- **Read this as "no sign of degradation", not as additional confirmation.**

## 9. Market (evaluation only)

**Safety (the only market input to the verdict).**
- Passes on development: β_E(C) −0.006 vs I −0.008.
- Passes on 2023–25: 0.232 vs 0.017.

**Historical market evidence (M-H, descriptive, no decision power).**
- **Development:** no information beyond the closing line.
  - β_E −0.006 [−0.131, +0.114]; trend γ −0.09 (n.s.); encompassing b_m 0.003.
  - ATS vs close 50.0% [48.4, 51.6]; vs open 51.2% [48.7, 53.7].
  - C's disagreement with the opening line does anticipate line movement: β_mv 0.086 [0.040, 0.154], a 55.1% toward-model
    share [52.4, 57.8], CLV +0.23. That is similar to C2f and stronger than the incumbent (β_mv 0.031).
- **2023–25 (burned):** β_E vs close 0.232 [0.055, 0.412]; encompassing b_m 0.24 [0.06, 0.42]; line movement β_mv 0.193.
  - ATS vs close 51.3% [49.3, 53.3] and vs open 51.0%, **both below the 52.38% break-even.**

**No claim that the model beats the market is made or permitted.** Only the prospective M-P tests (forward, F3) can
support one.

## 10. Comparison references

| | Development log-loss | Δ vs I [95%] | 2023–25 log-loss | Δ vs I [95%] |
|---|---|---|---|---|
| Incumbent | 0.53207 | — | 0.53616 | — |
| Frozen R15 C2 (C2f) | 0.52613 | −0.00595 [−0.01158, −0.00074] | 0.53040 | −0.00576 [−0.01361, +0.00202] |
| **Current C2** | **0.52478** | **−0.00729 [−0.01283, −0.00207]** | **0.52952** | **−0.00664 [−0.01382, +0.00039]** |
| Round 13 K (subset: 3,092 development games) | 0.53231 | −0.00311 [−0.00508, −0.00110] | 0.53297 | −0.00319 [−0.00557, −0.00075] |

**Current C2 − K:**
- development subset: −0.0041 [−0.0091, +0.0008];
- 2023–25: −0.0035 [−0.0100, +0.0031].

## 11. What Round 16 establishes, and what it does not

**Establishes:**
- **Frozen standards passed on development.** Current C2, frozen and untuned, meets every standard predeclared before
  scoring on the development seasons:
  - a log-loss gain about 3.6× the required effect size, with its 95% interval clear of zero;
  - better margin accuracy;
  - calibrated raw spread and probabilities;
  - no demonstrable seasonal or early-season regression;
  - intact FCS behavior;
  - acceptable stability;
  - market safety.
- **2023–25** shows no degradation.
- **The Stage 3 FCS architecture** adds value over frozen Round 15 C2 at the whole-system level.

**Does not establish:**
- **Independent superiority.** The development seasons shaped the Stage 3 and Stage 4 choices, and 2023–25 had been seen.
- **Market value.**
- **That Stage 3 improves FBS-vs-FBS prediction specifically.**
- **Only the forward test can supply independent confirmation.**

## 12. Exploratory items (no decision power) and one disclosed defect

1. **Defect: `reliability_deciles.csv` (report-only).** Its `mean_p` column is the overall mean, not each decile's, due
   to a grouping bug in the frozen scorer.
   - The `win_rate` column and every gate are unaffected: G2b uses the recalibration slope and CITL from
     `metrics_overall.csv`.
   - The file is left as produced. A corrected recomputation, with the same frozen σ and predictions, is in
     `docs/round16/exploratory/reliability_deciles_corrected.csv`.
   - Mean absolute decile gap: development C 0.017 vs I 0.016; 2023–25 C 0.017 vs I 0.021.
2. **Exploratory: G1 at Round 15's 98.33% level.**
   - The scorer does not compute this interval. A normal approximation from the bootstrap SE (0.00276) gives an upper
     bound of about −0.0007, below zero.
   - So the approved change to 95% did not decide the outcome, unlike the borderline frozen-C2 case in Round 15.
   - Round 15's point-estimate season rule G2f would also have passed (§4).
