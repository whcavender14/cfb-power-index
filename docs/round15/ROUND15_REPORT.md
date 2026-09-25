# Round 15 formal results: power rating, game prediction and market value

**Verdict (frozen rules, predeclaration v3 §8): INCUMBENT RETAINED.** No candidate passed G0–G3, so no candidate became
R. The production decision is yours; this report makes no production change and starts no forward test.

**Run facts**
- **Scoring run:** `scripts/round15/e1_score.R` at commit `749912c`, run once at 2026-09-25T14:32Z. Results frozen at commit
  `6c8593e`, tag `round15-scored`.
- **Results:** `docs/round15/eval/results/`. Every file is hashed in `results.sha256` (SHA-256 of that list:
  `0bda356c…3461`).
- **Probability scales:** each σ_X was fit, written and hashed (`sigma.csv`, `1a0ab882…2499`) before any loss was computed.
- **Frozen inputs, all verified by the run** (`provenance.csv`, 15/15):
  - predeclaration v3 and both amendments;
  - construction freeze `CONSTRUCTION_FREEZE_A02` (`32a986fa…e13a`, tag `round15-construction-final` = `fe345ed`);
  - C1–C3 prediction manifests; C3 built under Amendment 02;
  - Round 13 K prediction hashes;
  - the P5 market vintage;
  - the E0 ratings replay.
- **Samples:**
  - development: 3,868 games, 106 week blocks;
  - K's development subset (2018–2022): 3,092 games, 85 blocks;
  - 2023–2025 conditional: 2,398 games, 65 blocks.
- **Bootstrap:** flat season × week blocks, 4,000 resamples, seed 15015.

---

## 1. Formal verdict for each candidate

| Candidate | G0 | G1 (primary) | G2 (guardrails) | G3 (2023–25) | Result |
|---|---|---|---|---|---|
| **C1** richer preseason prior | PASS | **FAIL** (Δ −0.00036, interval crosses 0) | **FAIL** (G2d gp-0 slope 1.234 > 1.20; G2f 2018 +0.0043) | PASS | Not recommended |
| **C2** + success rate, FCS teams, fumble luck | PASS | **FAIL** (Δ −0.00595 clears the −0.0020 size bar; 98.33% upper +0.00054 ≥ 0) | **FAIL** (G2f 2018 +0.0055 > +0.003) | PASS | Not recommended |
| **C3** + within-season dynamics | PASS | **FAIL** (Δ −0.00551; 98.33% upper +0.00134) | **FAIL** (G2f 2018 +0.0069) | PASS | Not recommended |

**Recommendation trace** (`recommendation_trace.csv`):
1. C1 fails G0–G3.
2. C2 fails G0–G3.
3. C3 fails G0–G3.

R stays empty, so the incumbent is retained. No layer was rescued by another metric.

## 2. Every gate

Development is 2017–2022 (3,868 games); G3 uses 2023–2025 (2,398 games). Δ is model − incumbent, and negative is better
for losses.

| Gate | Threshold | C1 | C2 | C3 |
|---|---|---|---|---|
| G0 | integrity (G0a, G0b L1–L6, G0c) | PASS | PASS | PASS |
| **G1** | ΔLL ≤ −0.0020 **and** 98.33% upper < 0 | −0.00036 [−0.00450, +0.00357] **FAIL** | −0.00595 [−0.01276, +0.00054] **FAIL** | −0.00551 [−0.01268, +0.00134] **FAIL** |
| G2a | ΔMAE ≤ +0.020 and 95% lower ≤ 0 | −0.100 [−0.177, −0.027] PASS | −0.138 [−0.268, −0.013] PASS | −0.134 [−0.273, +0.001] PASS |
| G2b | ΔRMSE ≤ +0.030 | −0.092 PASS | −0.144 PASS | −0.140 PASS |
| G2c | ΔBrier ≤ 0 | −0.00039 PASS | −0.00282 PASS | −0.00275 PASS |
| G2d | raw slope pooled in [0.90, 1.10]; each gp bucket in [0.80, 1.20] | pooled 1.037; gp-0 **1.234** **FAIL** | pooled 0.999; buckets 0.858–1.191 PASS | pooled 0.979; buckets 0.840–1.186 PASS |
| G2e | \|P4-vs-G5 bias\| ≤ the incumbent's (5.768) | 4.928 PASS | 4.570 PASS | 4.544 PASS |
| **G2f** | every development season ΔLL ≤ +0.003 | 2018 **+0.0043** **FAIL** | 2018 **+0.0055** **FAIL** | 2018 **+0.0069** **FAIL** |
| G2g | gp 0–3 and gp 4+ ΔLL ≤ +0.001 | +0.0009 / −0.0011 PASS | −0.0074 / −0.0051 PASS | −0.0071 / −0.0045 PASS |
| G2h | market safety: β_E ≥ β_E(I) − 0.10 and 95% upper ≥ 0 | −0.032 vs −0.008 PASS | −0.023 PASS | −0.019 PASS |
| G3 ΔLL | ≤ +0.001 | −0.00182 PASS | −0.00576 PASS | −0.00647 PASS |
| G3 ΔMAE | ≤ +0.030 | −0.109 PASS | −0.252 PASS | −0.257 PASS |
| G3 slope | pooled in [0.90, 1.10] | 0.998 PASS | 0.985 PASS | 0.974 PASS |
| G3 tier | \|P4-vs-G5 bias\| ≤ the incumbent's (3.441) | 0.586 PASS | 0.485 PASS | 0.496 PASS |
| G3 market | β_E ≥ β_E(I) − 0.10 (close) | −0.008 vs 0.017 PASS | 0.226 PASS | 0.232 PASS |

Per-season ΔLL for G2f:

| | 2017 | 2018 | 2019 | 2021 | 2022 |
|---|---|---|---|---|---|
| C1 | −0.0002 | **+0.0043** | −0.0037 | −0.0002 | −0.0020 |
| C2 | −0.0052 | **+0.0055** | −0.0115 | −0.0069 | −0.0115 |
| C3 | −0.0020 | **+0.0069** | −0.0115 | −0.0081 | −0.0128 |

**Layer values** (95% upper bound < 0 **and** the upper layer passes G2):

| Layer | ΔLL, development | 95% interval | Upper < 0 | Upper layer passes G2 | Established |
|---|---|---|---|---|---|
| C2 over C1 | −0.00558 | [−0.01049, −0.00075] | yes | no (G2f) | **no** |
| C3 over C2 | +0.00043 | [−0.00073, +0.00170] | no | no | **no** |
| C3 over C1 | −0.00515 | [−0.01056, +0.00012] | no | no | **no** |

## 3. Absolute metrics for every model

**Development, 2017–2022 (3,868 games).**
- K is not defined for 2017; see the K table below.
- σ is the mean of the leave-one-season-out values.
- "Slope" is the raw calibration slope, with its 95% interval.

| Model | Log-loss | Brier | MAE | RMSE | Bias | Winner % | AUC | Slope | σ_X | σ/RMSE | Pred SD |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Incumbent | 0.53207 | 0.17963 | 12.972 | 16.350 | +0.639 | 72.18 | 0.7981 | 1.075 [1.03, 1.12] | 14.94 | 0.914 | 12.44 |
| C1 | 0.53171 | 0.17924 | 12.872 | 16.258 | +0.732 | 72.21 | 0.7988 | 1.037 [0.99, 1.08] | 15.51 | 0.954 | 12.98 |
| C2 | **0.52613** | **0.17681** | **12.834** | **16.207** | +0.638 | 72.52 | **0.8052** | 0.999 [0.95, 1.04] | 15.72 | 0.970 | 13.52 |
| C3 | 0.52656 | 0.17687 | 12.838 | 16.210 | +0.633 | **72.85** | 0.8051 | 0.979 [0.93, 1.02] | 16.05 | 0.990 | 13.78 |
| Closing line (reference) | 0.51209 | 0.17135 | 12.302 | 15.613 | | | | | | | |

**K's development games, 2018–2022 (3,092 games).**

| Model | Log-loss | Brier | MAE | RMSE | Winner % | AUC | Slope | σ_X |
|---|---|---|---|---|---|---|---|---|
| Incumbent | 0.53542 | 0.18091 | 12.970 | 16.338 | 71.73 | 0.7939 | 1.073 | 14.94 |
| **Round 13 K** | 0.53231 | 0.17942 | 12.903 | 16.265 | 72.45 | 0.7978 | 0.979 | 16.15 |
| C1 | 0.53501 | 0.18040 | 12.852 | 16.228 | 72.02 | 0.7951 | 1.029 | 15.51 |
| C2 | 0.52929 | 0.17793 | 12.809 | 16.178 | 72.57 | 0.8019 | 0.999 | 15.72 |
| C3 | **0.52903** | **0.17789** | **12.807** | **16.166** | 72.74 | 0.8020 | 0.986 | 16.05 |

**2023–2025 conditional (2,398 games; contaminated, used for non-degradation only).**
- σ was fit once on each model's development predictions.
- The closing line is shown for reference.

| Model | Log-loss | Brier | MAE | RMSE | Bias | Winner % | AUC | Slope | σ_X |
|---|---|---|---|---|---|---|---|---|---|
| Incumbent | 0.53616 | 0.18202 | 12.518 | 15.787 | −0.043 | 71.89 | 0.7920 | 1.015 | 14.94 |
| Round 13 K | 0.53297 | 0.18086 | 12.477 | 15.704 | −0.013 | 72.19 | 0.7947 | 0.947 | 16.14 |
| C1 | 0.53434 | 0.18147 | 12.409 | 15.634 | +0.216 | 71.93 | 0.7935 | 0.998 | 15.50 |
| C2 | 0.53040 | 0.18003 | 12.266 | 15.440 | +0.122 | 72.02 | 0.7968 | 0.985 | 15.72 |
| C3 | **0.52969** | **0.17969** | **12.261** | **15.431** | +0.116 | 72.31 | 0.7977 | 0.974 | 16.05 |
| Closing line (reference) | 0.52129 | 0.17613 | 12.003 | 15.195 | | | | | |

## 4. Incremental layers: C1 → C2 → C3 (Δ with 95% interval)

| Layer | Split | ΔLog-loss | ΔBrier | ΔMAE | ΔRMSE |
|---|---|---|---|---|---|
| C1 − I | development | −0.00036 [−0.00372, +0.00290] | −0.00039 [−0.00168, +0.00088] | **−0.100 [−0.177, −0.027]** | **−0.092 [−0.177, −0.012]** |
| C1 − I | 2023–25 | −0.00182 [−0.00808, +0.00385] | −0.00055 [−0.00279, +0.00151] | **−0.109 [−0.214, −0.016]** | **−0.154 [−0.284, −0.035]** |
| **C2 − C1** | development | **−0.00558 [−0.01049, −0.00075]** | **−0.00243 [−0.00450, −0.00043]** | −0.038 [−0.136, +0.061] | −0.052 [−0.159, +0.054] |
| C2 − C1 | 2023–25 | −0.00394 [−0.00875, +0.00080] | −0.00144 [−0.00335, +0.00040] | **−0.143 [−0.248, −0.041]** | **−0.194 [−0.302, −0.102]** |
| C3 − C2 | development | +0.00043 [−0.00073, +0.00170] | +0.00007 [−0.00046, +0.00063] | +0.003 [−0.026, +0.035] | +0.004 [−0.027, +0.037] |
| C3 − C2 | 2023–25 | −0.00071 [−0.00171, +0.00020] | −0.00034 [−0.00072, +0.00003] | −0.005 [−0.027, +0.017] | −0.009 [−0.034, +0.015] |

**Plain English.**
- **C1 (the richer preseason prior).** It improves margins, by about 0.10 points of MAE, but not win-probability quality.
- **C2 (success rate, FCS teams and fumble luck).** This is where the information gain is. Its gain over C1 on log-loss and
  Brier is the only layer increment whose development interval excludes zero.
- **C3 (week-to-week dynamics).** It adds nothing measurable on development and only a small, uncertain improvement on
  2023–25.

## 5. Comparison with the incumbent (Δ = X − I, 95% interval; G1 also shows the 98.33% interval)

| | Split | ΔLog-loss | ΔBrier | ΔMAE | ΔRMSE |
|---|---|---|---|---|---|
| C1 | development | −0.00036 [−0.00372, +0.00290] | −0.00039 [−0.00168, +0.00088] | −0.100 [−0.177, −0.027] | −0.092 [−0.177, −0.012] |
| C2 | development | −0.00595 [−0.01150, −0.00066]; 98.33% [−0.01276, +0.00054] | −0.00282 [−0.00524, −0.00053] | −0.138 [−0.268, −0.013] | −0.144 [−0.279, −0.012] |
| C3 | development | −0.00551 [−0.01131, +0.00002]; 98.33% [−0.01268, +0.00134] | −0.00275 [−0.00519, −0.00036] | −0.134 [−0.273, +0.001] | −0.140 [−0.285, +0.003] |
| C1 | 2023–25 | −0.00182 [−0.00808, +0.00385] | −0.00055 [−0.00279, +0.00151] | −0.109 [−0.214, −0.016] | −0.154 [−0.284, −0.035] |
| C2 | 2023–25 | −0.00576 [−0.01356, +0.00213] | −0.00199 [−0.00496, +0.00098] | −0.252 [−0.397, −0.113] | −0.348 [−0.514, −0.190] |
| C3 | 2023–25 | −0.00647 [−0.01402, +0.00139] | −0.00233 [−0.00521, +0.00062] | −0.257 [−0.400, −0.116] | −0.357 [−0.517, −0.205] |

## 6. Comparison with Round 13 K (on K's games)

| | Split | ΔLog-loss vs K | ΔBrier vs K | ΔMAE vs K | ΔRMSE vs K |
|---|---|---|---|---|---|
| I − K | 2018–22 | **+0.00311 [+0.00108, +0.00510]** | **+0.00149 [+0.00060, +0.00237]** | **+0.067 [+0.009, +0.126]** | **+0.073 [+0.021, +0.126]** |
| C1 − K | 2018–22 | +0.00270 [−0.00183, +0.00705] | +0.00098 | −0.051 [−0.145, +0.043] | −0.038 |
| C2 − K | 2018–22 | −0.00302 [−0.00801, +0.00209] | −0.00149 | −0.093 [−0.208, +0.018] | −0.087 |
| C3 − K | 2018–22 | −0.00328 [−0.00839, +0.00178] | −0.00153 | −0.095 [−0.213, +0.019] | −0.099 |
| I − K | 2023–25 | **+0.00319 [+0.00078, +0.00559]** | **+0.00116** | +0.041 [−0.015, +0.097] | **+0.084** |
| C2 − K | 2023–25 | −0.00257 [−0.00982, +0.00443] | −0.00083 | **−0.211 [−0.337, −0.086]** | **−0.264** |
| C3 − K | 2023–25 | −0.00328 [−0.01030, +0.00364] | −0.00117 | **−0.216 [−0.340, −0.090]** | **−0.273** |

- **K against the incumbent.** K beats the incumbent with a small, precise gain, reproducing Round 13 under Round 15's
  metric (SE 0.0010).
- **C2 and C3 against K.** On point estimates they beat K on every metric, but only their 2023–25 MAE gain is outside
  noise.
- **C1 against K.** C1 is behind K on log-loss.

## 7. Development versus 2023–2025 evidence

| | Development (selection) | 2023–25 (non-degradation only; contaminated) |
|---|---|---|
| Direction vs I | C2/C3 better on every loss; C1 better on MAE only | Same ordering, with larger MAE gains (C2 −0.25, C3 −0.26; intervals exclude 0) |
| Log-loss significance | C2's 95% interval excludes 0; the Bonferroni 98.33% interval does not | No interval excludes 0 |
| G2f / 2018 | All three candidates are worse than I in 2018 | No season worse for C2/C3; C1 2025 +0.0007 |
| Tier bias | \|bias\| 5.77 → 4.54–4.93 | \|bias\| 3.44 → 0.49–0.59 |

The 2023–25 evidence agrees with development in direction and never contradicts it. By the predeclared design it can
only veto, never advance, a candidate.

## 8. The three-part scorecard

### A. Power rating (win-probability quality; primary)

| Model | Log-loss (dev / cond) | Brier (dev / cond) | AUC (dev / cond) | Raw slope (dev / cond) | σ/RMSE (dev) | Rating SD per cutoff (dev) | Week-to-week \|ΔP\| (dev) | Top-25 Kendall distance (dev) | Update efficiency β_upd (dev) |
|---|---|---|---|---|---|---|---|---|---|
| Incumbent | 0.5321 / 0.5362 | 0.1796 / 0.1820 | 0.7981 / 0.7920 | 1.075 / 1.015 | 0.914 | 10.71 | 0.80 | 0.073 | +0.10 [−0.15, +0.35] |
| K (2018–22) | 0.5323* / 0.5330 | 0.1794* / 0.1809 | 0.7978* / 0.7947 | 0.979* / 0.947 | 0.993 | n/a | n/a | n/a | n/a |
| C1 | 0.5317 / 0.5343 | 0.1792 / 0.1815 | 0.7988 / 0.7935 | 1.037 / 0.998 | 0.954 | 11.23 | 0.84 | 0.075 | +0.02 [−0.21, +0.25] |
| C2 | **0.5261** / 0.5304 | **0.1768** / 0.1800 | **0.8052** / 0.7968 | **0.999** / 0.985 | 0.970 | 11.66 | 0.97 | 0.079 | −0.02 [−0.23, +0.18] |
| C3 | 0.5266 / **0.5297** | 0.1769 / **0.1797** | 0.8051 / **0.7977** | 0.979 / 0.974 | 0.990 | 11.89 | 1.15 | 0.093 | −0.13 [−0.31, +0.05] |

\* K on its 3,092 development games. Compare it with the incumbent's 0.5354 on the same games.

Notes:
- **Raw-rating spread.** The incumbent's raw ratings are the most compressed (slope 1.075, interval above 1). Its σ_X
  (14.94) is the furthest below its raw RMSE (ratio 0.914): its probability mapping is doing the most compensating.
  C2 has the best-calibrated raw spread (0.999).
- **Rating-level diagnostics** come from the E0 replay, which reproduced every frozen prediction to 5.7×10⁻¹⁴. They are not
  available for K, whose frozen files hold game margins only. They are also not available for the incumbent's 2023–25
  production file, which uses history from 2015 and cannot be replayed exactly (difference up to 1.4 points).
- **Stability and responsiveness.** C3 is the most volatile: week-to-week change 1.15 vs 0.80, and top-25 Kendall distance
  0.093 vs 0.073. No model's update-efficiency slope differs from 0.
- **Tier means (development).** P4 − G5 gap: I 11.7, C1 12.6, C2 13.1, C3 13.3 points.

### B. Game prediction (margins)

| Model | MAE (dev / cond) | RMSE (dev / cond) | Bias (dev / cond) | Winner % (dev / cond) | Pred-margin SD (dev) | Winner calls differing from I (dev) |
|---|---|---|---|---|---|---|
| Incumbent | 12.972 / 12.518 | 16.350 / 15.787 | +0.64 / −0.04 | 72.18 / 71.89 | 12.44 | — |
| K | 12.903* / 12.477 | 16.265* / 15.704 | +0.59* / −0.01 | 72.45* / 72.19 | 13.62* | 82* |
| C1 | 12.872 / 12.409 | 16.258 / 15.634 | +0.73 / +0.22 | 72.21 / 71.93 | 12.98 | 201 |
| C2 | **12.834** / 12.266 | **16.207** / 15.440 | +0.64 / +0.12 | 72.52 / 72.02 | 13.52 | 323 |
| C3 | 12.838 / **12.261** | 16.210 / **15.431** | +0.63 / +0.12 | **72.85** / **72.31** | 13.78 | 332 |

- **Slices.** They are in `slices.csv` and `slice_deltas.csv`, covering season, gp bucket, stage, conference game and
  matchup. See sections 9–11.
- **Predicted-margin quantiles.** They are in `pred_distribution.csv`.
- **Oriented P4-vs-G5 bias.** Development: I 5.77, C1 4.93, C2 4.57, C3 4.54. 2023–25: I 3.44, C1 0.59, C2 0.49, C3 0.50.
  Positive means the P4 side is under-rated.

### C. Market value (evaluation only; never an input)

**1. Market-safety gate (M-S, veto only).** Every candidate passes G2h (development) and the G3 market check (2023–25).
No candidate's relation to the closing line is worse than the incumbent's.

**2. Historical market signal (M-H; descriptive, no decision power).**

| Test | Development (close; open for 2021–22 only) | 2023–25 (close / open) |
|---|---|---|
| T1 edge calibration β_E vs close | I −0.01, K +0.02, C1 −0.03, C2 −0.02, C3 −0.02; every interval includes 0 | I +0.02, K +0.08, C1 −0.01, **C2 +0.23 [0.05, 0.41]**, **C3 +0.23 [0.06, 0.41]** |
| T1 vs open | all 0.01–0.07, intervals include 0 | I +0.09, **K +0.18**, C1 +0.12, **C2 +0.37**, **C3 +0.38** |
| T2 trend γ (close) | all −0.08 to −0.16, intervals include 0 | all include 0 |
| T3 line moves toward the model (β_mv, open → close) | **I +0.03, K +0.06, C1 +0.04, C2 +0.09 [0.04, 0.15], C3 +0.09 [0.04, 0.16]** | **I +0.10, K +0.12, C1 +0.17, C2 +0.19, C3 +0.20** (all intervals > 0) |
| T3 share of moves ≥ 0.5 toward the model | I 51.2%, K 55.0%, C1 52.1%, **C2 55.5%, C3 57.4%** | I 54.1%, K 55.6%, C1 55.5%, C2 57.0%, **C3 58.0%** |
| T4 ATS pooled vs close | I 49.9%, K 50.3%, C1 49.7%, C2 49.8%, C3 49.9% (±1.6 pp) | I 50.5%, K 50.8%, C1 48.5%, C2 51.6%, C3 51.7% (±2 pp) |
| T4 ATS pooled vs open | I 51.1%, K 51.4%, C1 49.7%, C2 51.1%, C3 51.8% (n = 1,508) | I 50.8%, K 50.4%, C1 49.4%, C2 51.9%, C3 51.3% |
| T5 ATS trend slope (close) | all −0.017 to −0.026; I and C1 intervals just below 0 (larger disagreements did slightly *worse* ATS) | all include 0 |
| Encompassing b_m (close) | all ≈ 0 (−0.02 to +0.02), intervals include 0 | I 0.04, K 0.09, C1 0.00, **C2 0.24 [0.06, 0.42], C3 0.24 [0.06, 0.41]** |

- **Reference.** The closing line is more accurate than every model: development MAE 12.30 vs 12.83–12.97, log-loss 0.512
  vs 0.526–0.532.
- **Bucket detail.** ATS by edge bucket is in `market_T4.csv`. Per the predeclaration it is descriptive at every stage:
  bucket intervals are ±4–8 points.
- **Buckets disagree across periods.** 2023–25's ≥ 7 bucket shows C2 at 59.6% vs close, but development's shows C2 at
  47.9%. That kind of contradiction is why buckets carry no weight.

**3. Prospective claims (M-P) need the 2026–27 forward test.**
- None can be made.
- Under the INCUMBENT RETAINED verdict, the predeclaration starts no Round 15 forward test, so F3a–c are "not demonstrated".
- **Nothing here shows that any model beats Vegas.**
  - Development ATS is about 50% for every model.
  - The 2023–25 edge-calibration signal for C2 and C3 is in the contaminated period and is absent on development.

## 9. Where each candidate is materially better

"Materially" here means the 95% interval of the predeclared slice excludes 0. With ~30 slices per comparison, a few such
results are expected by chance; treat single slices as descriptive.

- **C1.**
  - Margin accuracy early in the season: gp 0 ΔMAE −0.46; gp 0–3 −0.24.
  - Non-conference games: −0.24 dev, −0.27 cond.
  - P4-G5 games: −0.30.
  - Games involving independents: MAE −0.53 and LL −0.015.
  - 2019 MAE; 2024 MAE.
  - Tier bias sharply reduced in 2023–25 (3.44 → 0.59).
- **C2.**
  - Overall: log-loss −0.0060, Brier −0.0028, MAE −0.14 and RMSE −0.14 on development (95%); MAE −0.25 and RMSE −0.35 on
    2023–25.
  - Best-calibrated raw spread: slope 0.999, gp buckets 0.86–1.19.
  - P4-G5 MAE −0.65 (dev); gp 0 MAE −0.57; gp 1 MAE −0.44.
  - P4-P4 LL −0.0077; G5-G5 LL −0.014 (cond); 2022 LL −0.012.
  - The C2 − C1 layer is significant on dev log-loss and Brier. It is strongest at gp 1 (LL −0.019) and in P4-G5 and P4-P4
    games.
- **C3.**
  - Essentially the same as C2 against the incumbent: dev MAE −0.13 (interval touches 0); 2023–25 MAE −0.26 and RMSE −0.36.
  - Highest winner % (72.85 dev, 72.31 cond) and lowest 2023–25 log-loss.
  - Against C2 it is better only in a few 2023–25 slices: conference games, P4-P4 and 2024, each about −0.001 to −0.002 LL.

## 10. Where each candidate is materially worse

- **All three: 2018.**
  - Development ΔLL: C1 +0.0043 [+0.0002, +0.0088], C2 +0.0055, C3 +0.0069. This is what fails G2f.
  - The 2018 deficit comes from the **C1 prior layer**: C1 − I +0.0043; C2 − C1 +0.0012 and C3 − C2 +0.0014, both inside
    noise.
  - K was not worse than the incumbent in 2018 (0.5071 vs 0.5079).
- **C1.**
  - Its gp-0 raw slope of 1.234 is outside the [0.80, 1.20] band, which fails G2d. Preseason margins are too compressed.
  - Late-season games in 2023–25: gp 7+ ΔLL +0.0068 [+0.0023, +0.0107].
- **C2 and C3.**
  - **FBS-vs-FCS games** (outside the scoring universe; descriptive): they over-rate FCS teams.
    - Development: bias −10.5 points vs the incumbent's −2.4 under the flat −25 rule; MAE 15.80 vs 15.05; log-loss
      0.229 vs 0.189 (n = 335).
    - 2023–25: bias −11.3 vs C1's −4.5 (n = 212).
    - **This matters for simulation use.**
- **C3.**
  - The most volatile ratings: week-to-week change 1.15 vs 0.80; top-25 Kendall distance 0.093 vs 0.073.
  - A small gp-0 cost against C2 (+0.0011 LL).
  - It adds no development value over C2.

## 11. Surprising subgroup and seasonal behaviour (descriptive; no effect on the verdict)

1. **2018 alone decides G2f for all three candidates.** Each candidate is better than the incumbent in 4 of 5 development
   seasons, often by 0.007–0.013, and worse only in 2018. The per-season rule is a point threshold. C2's 2018 interval
   [−0.006, +0.017] includes 0, so a noisy single season can block a pooled gain. That is how the rule was written, and it
   is applied as written.
2. **The incumbent itself would fail G2d's gp-0 band.** Its gp-0 slope is 1.267 [1.18, 1.38]. Preseason ratings are
   compressed in every model. C2 and C3 reduce this (1.19) and pass; C1 (1.234) does not. This is reported, not used to
   rescue C1.
3. **2023–25 edge calibration turns positive for C2 and C3** (β_E ≈ 0.23 vs close, 0.37 vs open) but is ≈ 0 on
   development. **The market moves toward C2 and C3 more than toward the incumbent in both periods** (T3). Of the market
   tests, T3 is the most consistent. It remains historical evidence without decision power.
4. **Sensitivity to the probability scale (§7.1 requires this to be stated prominently).**
   - Under a common fixed σ, G1 changes:
     - C2 would pass at σ = 16 (98.33% upper −0.00006) and σ = 18 (−0.00189);
     - C3 would pass at σ = 18 (−0.00151);
     - C1 fails at every σ.
   - The binding model-specific-σ result fails.
   - The verdict is unchanged, and G2f fails C2 and C3 regardless of σ.
5. **The candidates move predictions far more than K does**, so their comparisons are noisier.
   - Winner calls differing from the incumbent: C2 323 games, C3 332, K 82 (on 3,092).
   - SE of ΔLL vs I: C2 0.0028 and C3 0.0029, against K's 0.0010.
   - The predeclaration warned of this: at twice K's SE, a K-sized gain passes G1 only about 28% of the time.

## 12. Smallest detectable effects (required for an incumbent-retained report)

The effect detectable with 80% power, given the observed SE:

| Comparison (development) | ΔLL SE | Detectable ΔLL (G1, α = 0.0167) | ΔMAE SE | Detectable ΔMAE (α = 0.05) |
|---|---|---|---|---|
| C1 − I | 0.00170 | 0.0055 | 0.038 | 0.106 |
| C2 − I | 0.00276 | 0.0089 | 0.065 | 0.181 |
| C3 − I | 0.00289 | 0.0094 | 0.070 | 0.195 |
| C2 − C1 (layer) | 0.00251 | 0.0070 | 0.051 | 0.141 |
| C3 − C2 (layer) | 0.00061 | 0.0017 | 0.016 | 0.043 |

- **What these numbers mean.** Development could reliably confirm a C2-type change only if it improved log-loss by about
  0.009. That is roughly 1.5 times C2's observed −0.0060 and 4.5 times the G1 size bar.
- **The rest.** All other metrics and the 2023–25 figures are in `deltas.csv` (`mde80`).

## 13. Process disclosures

- **L3 was missing from the construction G0 tests.** The predeclared L3 test (preseason inputs dated before their season)
  was not in `test_g0.R`, and my construction report's "all G0 pass" did not cover it. It was run before scoring
  (`scripts/round15/e0b_l3_check.R`, 8/8 pass). Its first run failed because of a bug in the check itself, a missing FBS
  flag; it was fixed and rerun. No outcome was read.
- **E0 replay.** To compute the predeclared rating-level diagnostics, the frozen predictions were replayed with the frozen
  selected parameters and capture-only patches. Every prediction reproduced exactly (5.7×10⁻¹⁴); no parameter was
  re-estimated.
- **Smoke tests.** The scorer was debugged only in smoke mode, where every actual result was replaced by a synthetic draw.
  Two structural bugs were fixed there: a date-typed join key, and duplicate C1 − I rows. The real run happened once.
- **K's development figures cover 2018–2022 only.** In the slice tables, K's "development" values are on its own 3,092
  games; compare them against the K-subset rows.
- **Unavailable rating-level diagnostics:**
  - for K;
  - for the incumbent in 2023–25.
  - The FBS-vs-FCS slice uses FCS teams that had played at least once before the cutoff, where C2 and C3 have a rating
    (n = 335 dev, 212 cond).
- **Market data** entered only here, after every prediction was frozen and hashed (P5 vintage verified).

## 14. Final recommendation dictated by the frozen rules

**INCUMBENT RETAINED.**
- C1, C2 and C3 all fail G1 and G2 on development.
- No layer's value is established.
- No Round 15 forward test starts.
- The snapshot job stays inactive.
- The reconstructed data tables are kept.

## 15. What Round 15 learned, in plain English

1. **The play-level measurement channel is the real gain; the preseason prior on its own is not.**
   - Adding game-level success rate, rating FCS opponents properly and discounting fumble luck (C2) made the ratings
     better at picking winners. Log-loss −0.006 is about twice Round 13 K's gain.
   - Margins also improved, by about 0.14 points (development) and 0.25 points (2023–25).
   - Better-informed preseason ratings (C1) mostly helped margins early in the season, not win-probability quality.
   - Letting ratings drift week to week (C3) added volatility and no measurable accuracy.
2. **The gain is not proven to the standard set in advance.**
   - The candidates change many more predictions than K did, so their measured gain is noisier.
   - C2's gain clears the size bar but not the strict three-candidate significance bar.
   - All three candidates are worse than the incumbent in 2018. That breaks the "no season materially worse" rule, whatever
     the pooled gain.
   - Under the rules you signed, that means no promotion, and nothing was adjusted after seeing it.
3. **The newer models fix known incumbent defects:**
   - raw ratings that are too compressed (C2 slope 0.999 vs 1.075);
   - under-rating of P4 teams against G5 (2023–25 bias 3.4 → 0.5 points).
   - They also introduce one of their own: FCS teams are over-rated by about 10 points. That would matter for simulation.
4. **The market.**
   - The closing line is still clearly better than every model.
   - Historically, no model beats the spread: development ATS is about 50%.
   - The one consistent market signal is that lines tend to move toward C2 and C3 before kickoff. That is a hint of real
     information, not proof of value.
   - Any such claim needs the untouched 2026–27 forward test, which the rules start only for a promoted candidate.
5. **Where this leaves the production decision.** Round 13 K beats the incumbent precisely but by a small amount. C2 and
   C3 beat K on point estimates, and on 2023–25 MAE beyond noise, but fail the frozen gates. The formal result is that the
   incumbent stays; the production decision is yours.
