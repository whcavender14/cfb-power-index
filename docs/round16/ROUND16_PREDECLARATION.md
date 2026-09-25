# Round 16 Predeclaration: Qualification of Current C2

**Status: APPROVED and FROZEN (binding).** You approved it on 2026-09-25, including the two flagged changes (§11 items 1
and 4).
- The text is committed and hashed in `docs/round16/predeclaration.sha256` before any scoring code runs.
- No Round 16 score was computed before the freeze.
- Changes after approval: dated, hashed amendments only, and only before the step they affect.
- A failed gate is never "fixed" inside Round 16.

**Date:** 2026-09-25. **Branch:** `c2-refinement`. **Model manifest:** `docs/round16/ROUND16_MODEL_MANIFEST.csv` (sha256
of every model artifact).

## 0. The question, and an honest statement of what is already known

**Round 16 asks:**
1. **Primary.** Does Current C2 (`c2-post-stage4-baseline`) show strong, robust, reproducible improvement over the
   incumbent, enough to advance toward production?
2. **Secondary.** Does the Stage 3 FCS architecture add genuine value over frozen Round 15 C2?

It is a **confirmation round**. No feature, parameter, prior, garbage-time rule, FCS treatment, probability mapping or
evaluation criterion changes after approval.

**What is already known (disclosure).** Every historical season, 2017–2025, has been examined.
- Development (2017–22) was used to select the Stage 3 and Stage 4 variants.
- 2023–25 was viewed descriptively in Rounds 4–15 and in Stages 1–4.
- The integration step also computed these Current C2 results (95%, seed 15015):

| Known result | Development | 2023–25 |
|---|---|---|
| Δ log-loss vs incumbent | −0.0073 [−0.0128, −0.0021] | −0.0066 [−0.0139, +0.0006] |
| Δ Brier / Δ MAE vs incumbent | −0.0033 / −0.156 [−0.284, −0.035] | −0.0023 / −0.250 |
| Δ log-loss vs frozen C2, FBS vs FBS | −0.0013 [−0.0028, +0.0001] | −0.0009 [−0.0021, +0.0003] |
| Δ whole-system log-loss vs frozen C2 (FBS-vs-FBS plus FBS-vs-FCS) | −0.0079 [−0.0124, −0.0035] | −0.0129 [−0.0200, −0.0066] |
| FBS-vs-FCS bias / MAE (all games); first-game bias | +1.52 / 13.60; +2.69 | +0.38 / 12.31; −0.14 |
| FCS-vs-FCS MAE; calibration slope | 13.03; 1.064 | 12.44; 1.074 |
| Pooled raw calibration slope; P4-vs-G5 bias (incumbent) | 0.998; 4.42 (5.77) | 0.982; 0.34 (3.44) |
| Log-loss by all-games gp (Stage 4), Current C2 vs incumbent | better in every bucket (0, 1, 2, 3, 4–6, 7+) | mixed (gp 1 and 3 worse) |
| Raw slope, all-games gp bucket 0 | 1.225 (incumbent 1.273; frozen C2 1.218) | 1.110 |

**Not yet computed for Current C2:**
- per-season Δ vs the incumbent;
- rating stability relative to the incumbent;
- probability-scale calibration;
- market tests;
- comparisons against K;
- the gate outcomes defined below.

**Consequences.**
1. **The historical part of Round 16 is not a blind test.** It checks a fixed model against fixed standards, with results
   partly known. Development results also carry some selection optimism.
   - Stage 3's leave-one-season-out procedure picked the same arm in all five folds, so its honest development
     log-loss equals the in-sample value (0.52478). That limits, but does not remove, the optimism.
2. **Genuinely independent evidence** can only come from games not yet played. Round 16 therefore ends in a predeclared
   **forward confirmation** (§9).
3. **Every threshold below is either inherited unchanged from Round 15 or derived from a stated statistical principle.**
   - §11 lists every change from Round 15 and its effect on known outcomes.
   - That includes two changes that flip a known outcome in the candidate's favour, flagged for your explicit approval.

## 1. Sample periods

| Split | Seasons | Universe | Role | Status |
|---|---|---|---|---|
| History | 2013–2016 | | Inputs only | Never scored |
| **Development** | 2017, 2018, 2019, 2021, 2022 | FBS vs FBS: **3,868** (R15 game IDs). FBS vs FCS: **561** (after each season's first cutoff; first games included). FCS vs FCS: every game where both teams are FCS-division and rated at the cutoff | **Primary gates** (G1–G6) and the secondary claim | Examined; used for Stage 3/4 selection |
| **2023–2025** | 2023, 2024, 2025 | FBS vs FBS **2,398**; FBS vs FCS **365**; FCS vs FCS as above | **Non-degradation only** (G7) | Burned: contaminated, descriptive |
| **Forward** | 2026 games kicking off after forward activation, plus all of 2027 | Same universes | **Forward confirmation** (§9) | Pristine: the only independent evidence |

- **2020** is never a target season.
- **Round 13 K** is scored only as a descriptive reference, on its own subset (development 2018–22: 3,092 games; 2023–25).

## 2. Models (exact artifacts; hashes in `ROUND16_MODEL_MANIFEST.csv`)

| Model | Role | Definition |
|---|---|---|
| **I: incumbent** | Comparator | v5 EB_features. Development: walk-forward replay (`output/dev/round15/incumbent_replay_2017_2022.csv`). 2023–25: frozen production predictions (`data/reference/incumbent_predictions/eb_features_conditional_predictions.csv`). FBS-vs-FCS: every FCS team at −25 (R15 §7.1). |
| **C2f: frozen Round 15 C2** | Secondary comparator (Stage 3 increment) | Tag `round15-construction-final` (`fe345ed`), `R/round15/candidates/c2.R`. Predictions `output/dev/round15/cand/c2_predictions.csv` (sha256 `6a38ef01…`, equal to the R15 construction manifest). FCS ratings from the E0 replay. |
| **C: Current C2** | **The single advancement candidate** | Commit `6a187ea`, tag `c2-post-stage4-baseline`, `R/c2/c2_current.R` (sha256 `8b4d9d41…`). Predictions `output/c2/current/c2_predictions.csv` (`b5cadd23…`) and `c2_fbs_vs_nonfbs_predictions.csv` (`15d3c7d4…`). Spec: `docs/c2/C2_CURRENT_SPEC.md`. |
| **K: Round 13** | Descriptive only | Frozen files; hashes equal `docs/round13/freeze_manifest.csv`. |

## 3. Metric definitions (inherited from R15 §7 unless stated)

- **Predictions:** at the latest weekly cutoff before kickoff; m = home margin.
- **Probability:** p = Φ(m / σ_X), clipped to [10⁻⁶, 1 − 10⁻⁶].
  - σ_X is fitted separately per model by maximum likelihood on its own development FBS-vs-FBS predictions,
    leave-one-season-out for development seasons, and on all development seasons for 2023–25 and forward.
  - All σ values are computed in one step, written and hashed before any loss is computed.
- **Log-loss (primary), Brier, MAE, RMSE, bias** = mean(m − actual), winner %.
- **Raw calibration slope:** `lm(actual − H·site ~ m − H·site)`. No probability rescaling.
- **Games played (changed; see §11 item 4):** gp = the minimum over the two teams of **all completed games before the
  cutoff, including games against FCS teams.**
  - Buckets: 0, 1, 2–3, 4–6, 7+.
  - Stages: gp 0–3 vs 4+.
  - R15's count (FBS-vs-FBS games only, the incumbent frame's `gp_home`/`gp_away`) is reported as a sensitivity with no
    decision power.
- **Probability-scale calibration (new):**
  - logistic recalibration slope of w on logit(p);
  - calibration-in-the-large, mean(p) − mean(w);
  - a reliability table by predicted-probability decile (report).
- **P4-vs-G5:** the oriented bias `mean((actual − m)·s)` on cross-tier games (season-indexed tier map).
- **Stability:** the mean |ΔP| between consecutive cutoffs per FBS team; the Kendall distance of successive top-25 lists.
- **FBS vs FCS:** FBS-oriented margin; bias = mean(pred − actual).
  - Current C2 uses its own non-FBS rating, or its first-game rating before an FCS team's first game (`c2_fbs_vs_nonfbs`).
  - C2f uses its E0 FCS ratings, with the C2 prior mean for first games (the Stage 1 rule). The incumbent uses −25.
- **FCS level:** the mean rating of FCS-division entities at each cutoff (`c2_group_levels.csv`) and the season's anchor
  (`c2_anchors.csv`).

**Uncertainty.** Paired Δ = C − reference. A flat season × week block bootstrap: blocks keyed on the cutoff text (106
development, 65 conditional), **4,000 resamples, seed 16016**, percentile intervals.
- **"95% interval"** = two-sided 95%.
- **"90% interval"** = two-sided 90%, used only for the one-sided regression tests in G5 and G6.

## 4. Why these confidence levels (fixed before any Round 16 result)

- **Round 15** tested three candidates against the incumbent and split α = 0.05 three ways: Bonferroni, 98.33%.
- **Round 16 has one advancement candidate and one primary hypothesis** (C vs I on development log-loss). The
  family-wise error rate is kept at **the same 0.05**, which with one comparison is a **two-sided 95% interval**.
  - Keeping 98.33% would not be "stricter at the same standard". It would be a different standard: α = 0.0167 for a
    single test.
- **The secondary claim** (C vs C2f) uses **fixed-sequence (hierarchical) testing**. It is tested at α = 0.05 **only if G1
  passes**, which keeps the family-wise rate for confirmatory claims at 0.05 without further splitting.
- **What the historical 95% interval means (approved wording).** The historical seasons influenced model development
  (§0). The historical 95% interval is therefore a **qualification standard**, not pristine independent confirmation.
  **Independent confirmation comes from the forward test (§9).**
- **Guardrails are not claims.** Each is an additional condition to pass (an intersection–union structure), so they can
  only lower the probability of wrongly advancing. They need no α adjustment.
- **Effect size.** R15's G1 size requirement, **Δ log-loss ≤ −0.0020**, is kept unchanged. The R15 disclosure (§10)
  explains it.
- **Power.** With the variability seen for C2-type changes (R15 published SE ≈ 0.0028), the 95% condition needs roughly
  Δ ≤ −0.0054, so it binds before −0.0020 does. A true −0.0073 passes about 75% of the time; a true −0.0050 about 45%.

## 5. Formal gates (historical)

**G0: integrity.** Runs before any metric is read; any failure stops the round.
- **G0a:** every hash in `ROUND16_MODEL_MANIFEST.csv` verifies.
- **G0b:** `scripts/c2/c2_build_current.R` rebuilds Current C2's outputs with identical sha256.
- **G0c:** `tests/c2/run_all.R` passes: equivalence with C2L, regression vs frozen C2, reproduction.
- **G0d:** leakage.
  - R15 L1–L6 apply to the shared inputs.
  - Current C2: no training row at or after its cutoff; every anchor uses only seasons before its target.
  - Construction parameters are frozen through 2022 for 2023–25. Last-season inputs (end-of-season ratings, anchors,
    C1 features) roll forward exactly as in frozen C2.
  - Market data are never read by any model.
- **G0e:** identical FBS-vs-FBS game IDs for I, C2f and C.

**G1: primary (development, FBS vs FBS).** Pooled Δ log-loss(C − I) ≤ **−0.0020** **and** the 95% interval's upper
bound < 0.

**G2: probability quality (development).**
- **G2a:** Δ Brier(C − I) ≤ 0 (R15 G2c; 95% interval reported).
- **G2b:** logistic recalibration slope of C in [0.90, 1.10], and |calibration-in-the-large| ≤ 0.02.

**G3: margin quality (development).**
- **G3a:** Δ MAE ≤ +0.020, and the 95% lower bound ≤ 0 (R15 G2a).
- **G3b:** Δ RMSE ≤ +0.030 (R15 G2b).
- **G3c:** |bias(C)| ≤ |bias(I)| + 0.50 (new).
- **G3d:** pooled raw calibration slope in [0.90, 1.10] (R15 G2d, pooled).

**G4: calibration by games played (development).** Changed; see §11.

A gp bucket **fails** if both:
- its raw slope point estimate lies outside [0.80, 1.20];
- **its 90% interval lies entirely outside [0.80, 1.20]** on the same side. The miscalibration must be material and
  distinguishable from noise.

**G5: FCS guardrails (new; Current C2; development and 2023–25 separately).**
- **G5a:** |FBS-vs-FCS bias| ≤ **3.0** over all FBS-vs-FCS games.
- **G5b:** FBS-vs-FCS MAE(C) ≤ MAE(C2f), and MAE(C) ≤ MAE(I at −25) + 0.25.
- **G5c:** first-game FCS matchups: |bias| ≤ **4.0**.
- **G5d:** FCS vs FCS:
  - calibration slope in [0.90, 1.10];
  - MAE(C) ≤ MAE(C2f) + 0.10;
  - Spearman correlation of prediction with outcome ≥ C2f's − 0.02 (ordering). These are the Stage 3 guardrail values.
- **G5e:** FCS level stability. In every season:
  - the final-cutoff FCS-division level lies within ±4.0 points of that season's anchor;
  - the mean |change| in that level between consecutive cutoffs from cutoff 4 on is ≤ 0.50.

**Where the G5 bounds come from.** Frozen C2's FCS error was 10–11 points, which is what G5 exists to prevent. The
bounds are sized to sampling noise, not to known results:
- the SE of an all-games FBS-vs-FCS bias is about 0.8 over 561 games, and about 1.3–1.6 for about 226 first games;
- 3.0 and 4.0 are about 3.7 and about 3 SE.

**G6: robustness (development).**
- **G6a: seasons** (replaces R15 G2f; see §7).
- **G6b: season stage** (replaces R15 G2g). gp 0–3 and gp 4+ each fail only if Δ log-loss > **+0.001** **and** the 90%
  interval's lower bound > 0.
- **G6c:** |P4-vs-G5 bias(C)| ≤ |P4-vs-G5 bias(I)| (R15 G2e).
- **G6d:** rating stability (new). Mean |ΔP| ≤ 1.25 × the incumbent's, and top-25 Kendall distance ≤ 1.25 × the
  incumbent's.
- **G6e:** market safety veto (R15 G2h, close lines). β_E(C) ≥ β_E(I) − 0.10, and β_E(C) not significantly negative.

**G7: non-degradation on 2023–25 (R15 G3 kept, plus the season rule and FCS guardrails).**
- Δ log-loss(C − I) ≤ +0.001, and Δ MAE ≤ +0.030;
- pooled raw slope in [0.90, 1.10];
- |P4-vs-G5 bias| ≤ the incumbent's;
- market veto;
- no season failing the §7 rule;
- G5a, G5c and G5d on 2023–25.

## 6. The Stage 3 increment (secondary confirmatory claim; fixed sequence after G1)

**Always reported,** C − C2f with 95% intervals, on development and on 2023–25:
- log-loss, Brier, MAE and RMSE, on FBS-vs-FBS games and on all FBS-involved games (whole system);
- FBS-vs-FCS bias, MAE and log-loss, including first games;
- FCS-vs-FCS MAE, slope and Spearman;
- FBS rating change by number of FCS opponents.

**Claim "Stage 3 adds value: CONFIRMED"** is made only if G1 has passed **and**, on development:
- **(i)** whole-system Δ log-loss(C − C2f) has its 95% upper bound < 0. This is the Stage 3 objective J, predeclared in
  `STAGE3_PLAN.md` before any Stage 3 result;
- **(ii)** FBS-vs-FBS Δ log-loss(C − C2f) has its 95% upper bound < **+0.001** (non-inferiority, R15's materiality).

**Disclosure.**
- From the integration step, (i) is about −0.0079 [−0.0124, −0.0035] and (ii)'s upper bound is about +0.0001.
- **An FBS-vs-FBS superiority claim for Stage 3 would not be confirmed**, since its interval includes 0. Round 16 does
  not make that claim.
- The secondary claim **does not affect the advancement verdict.** Frozen C2 is not a candidate, and G5 already guards
  the FCS behavior.

## 7. Season-level regressions (replaces R15 G2f; fixed before any Round 16 per-season result)

**The R15 weakness.** G2f vetoed if any development season's Δ log-loss exceeded +0.003 **as a point estimate**. A
season has about 770 games. Its Δ has an SE of about 0.006 (the R15 pooled SE of 0.0028 × √5).
- A candidate that is truly better by 0.005 in **every** season would exceed +0.003 in at least one of five seasons
  about **38%** of the time: a noise veto.
- R15's C1, C2 and C3 were all vetoed by one season, 2018.

**Round 16 rule.** A season **fails** only if **both**:
- its Δ log-loss(C − I) > **+0.003** (R15's materiality threshold, kept);
- its **90% interval's lower bound > 0**, i.e. the regression is significant one-sided at 5%.

| Operating characteristics (season SE 0.006; 5 seasons) | R15 G2f | Round 16 |
|---|---|---|
| False veto of a model truly better by 0.005 in every season | about 38% | about 3% |
| Detecting a true single-season regression of +0.010 | about 88% | about 50% |
| Detecting +0.015 | about 98% | about 80% |
| Detecting +0.020 | ≈ 100% | about 95% |

- **What the new rule protects against:** a model that gains overall by being **materially and demonstrably** worse in
  some season.
- **What it no longer does:** veto on a regression of noise size.
- **Mandatory flag.** Any season with a point estimate > +0.003 is listed with its interval and discussed in the report,
  but is not a veto. A Cochran Q heterogeneity test of the seasonal Δs is also reported.
- **Scope.** The same rule applies to each 2023–25 season (G7), and in form to the stage and bucket tests (G4, G6b).

## 8. Advancement rule and verdicts

Gates are evaluated in this order: G0 → G1 → G2–G6 → G7 → secondary claim.

| Outcome | Verdict |
|---|---|
| G0 fails | **STOPPED.** Integrity failure; a new round is needed. |
| G1 fails | **INCUMBENT RETAINED.** The primary improvement is not established. |
| G1 passes, any of G2–G7 fails | **INCUMBENT RETAINED.** The failing guardrail is named. |
| All of G0–G7 pass | **QUALIFIED (historical): PRODUCTION CANDIDATE.** Advances to forward confirmation (§9). |

- **Meaning of a historical pass (approved wording).** A Round 16 historical pass means **QUALIFIED (historical):
  PRODUCTION CANDIDATE**. Current C2 has satisfied the predeclared historical qualification standards and may advance to
  independent forward confirmation. **It does not constitute independent proof that the model is superior, because the
  historical data have already influenced model development.**
- **Production is your decision.**
- **Recommendation built into this design:** because the historical data are contaminated, **do not replace the
  incumbent before the forward look.** If earlier use is wanted, run Current C2 in shadow alongside the incumbent.
- The secondary claim is reported as CONFIRMED or NOT CONFIRMED beside the verdict. It does not change the verdict.
- An INCUMBENT RETAINED report states, for each failed gate, the smallest effect it could have detected.

## 9. Forward confirmation (the independent evidence)

**Build.**
- Current C2 runs forward exactly as its 2023–25 predictions were produced: construction parameters frozen through
  2022, with last-season inputs (C1 features, end-of-season ratings, anchors) rolling forward.
- The 2026 C1 prior and 2025 end-of-season inputs are computed by the frozen code.
- The forward build is committed and hashed before its first snapshot.
- Nothing is re-tuned.

**Mechanism.**
- The existing snapshot tool (`docs/forward/FORWARD_SNAPSHOTS.md`) with a Current C2 plugin.
- The incumbent and frozen C2 are archived alongside.
- **Activation needs your separate approval.** The window starts at activation; games with no snapshot are reported
  missing, never imputed.

**Window and look.**
- Window: 2026 games after activation, plus all of 2027. The incumbent needs its 2027 extension, as in R15 §9.
- **One look on or after 2028-02-01.** Interim results carry no decision power.

**Forward checks.**
- **F1:** Δ log-loss(C − I) ≤ 0 (point estimate; interval reported).
- **F2:** Δ MAE ≤ +0.05.
- **F-FCS:** |FBS-vs-FCS bias| ≤ 3.0; first games |bias| ≤ 4.0.
- **F3:** market claims, exactly as R15 §9, each claimed only by its own interval rule.
- **Expected forward size:** about 1,300–1,500 FBS-vs-FBS games (SE of Δ log-loss about 0.0045). F1 is therefore a
  consistency check, not a significance test. With only post-activation 2026, the best verdict is
  "forward-consistent, underpowered".

## 10. Market evaluation (unchanged from Round 15)

- **Market data never enter a model.** They are read only after the manifests verify.
- **M-S (safety):** the only market input to a decision, as a veto (G6e, G7).
- **M-H (historical signal: T1–T5, encompassing regression):** descriptive, per split.
- **M-P (prospective):** forward only, and the only basis for any claim of market value.
- **No ATS result gates, advances or tunes anything.** The 52.38% break-even is a reference line only.

## 11. Changes from Round 15, and their effect on known outcomes

| # | Change | Why | Direction | Effect on a known Current C2 outcome |
|---|---|---|---|---|
| 1 | G1 at 95% instead of 98.33% | One primary comparison; family-wise α unchanged at 0.05 (§4) | Same standard, correct for one test | Known development interval [−0.0128, −0.0021] passes at 95%. The 98.33% bound has not been computed. **Flip:** R15's published C2f interval (upper 95% −0.00066, 98.33% +0.00054) shows that this change alone can decide a borderline case. Approve deliberately. |
| 2 | G2f becomes a material and significant season rule (§7) | The R15 point veto fires about 38% of the time on a uniformly better model | Less noise-prone; still vetoes demonstrable regressions | Current C2's per-season Δs have **not** been computed. R15's published C2f 2018 value (+0.0055) would be flagged, not vetoed. |
| 3 | G2g (stage) and G2d (buckets) use the same material-and-distinguishable logic | Consistency with #2 | As #2 | Stage Δs known favorable (§0). Bucket slopes: see #4. |
| 4 | gp counts all completed games, not FBS-vs-FBS games only | The stage of the season (and C2's evidence) includes FCS games. Stage 4 established the count | Neutral definition | **Flip:** the known all-games gp-0 slope is 1.225. Under R15's literal point rule [0.80, 1.20] it fails; so do the incumbent (1.273) and C2f (1.218). Under #3 it passes unless its 90% interval lies wholly above 1.20. R15's FBS-only count is reported as a sensitivity. **Approve deliberately.** |
| 5 | New: G2b probability calibration, G3c bias, G5 FCS guardrails, G6d stability, season rule on 2023–25 | Your requested coverage. Makes the Stage 3 gain unable to regress silently | **Stricter** | G5a–d known values pass their bounds (§0). G2b, G5e and G6d have not been computed. |
| 6 | Secondary claim by fixed-sequence testing on the predeclared Stage 3 objective J | Isolates Stage 3 without splitting α | New | Known to pass (i) and (ii). FBS-vs-FBS superiority, known to fail, is not claimed. |
| 7 | New bootstrap seed 16016 | New round | Neutral | |
| 8 | Forward build as conditional-style (parameters through 2022); R15 re-estimated through 2025 | Keeps "no parameter change after approval" literally true | Stricter | None. |

**Unchanged from Round 15:**
- the effect size −0.0020;
- the σ procedure;
- MAE, RMSE and Brier guardrails;
- the pooled slope band;
- P4/G5;
- the 2023–25 non-degradation thresholds;
- market isolation and the veto;
- the forward F1–F3 rules.

**Nothing was loosened except items 1–4.** Items 1–4 answer structural weaknesses identified in Round 15 (wrong
multiplicity for one candidate; point estimates used as vetoes; a games-played count that ignored FCS games). They are
shown with their known consequences so you can approve or reject each one explicitly.

## 11a. Pre-freeze clarifications (added with the approval edits; driven by data availability, not by any result)

1. **Where each G5 check is evaluated.**
   - G5a–G5d are evaluated on development.
   - On 2023–25 (G7): G5a, G5c and G5d.
   - G5e ("in every season") covers development seasons under G5 and 2023–25 seasons under G7.
   - **G5b's incumbent comparison is development only.** Incumbent FBS ratings exist only in the development replay
     (E0, model I); the 2023–25 incumbent file has game predictions only.
2. **Sources for the reference FBS-vs-FCS predictions.**
   - C2f: FBS and FCS ratings from the E0 replay (`output/dev/round15/eval/ratings_replay.csv`, model C2). For an FCS
     team's first game, C2's prior-mean rating (`output/c2r/stage1/capture.rds`, `fcs_prior$prior_power_c`, which ties out
     to the R15 slice exactly).
   - Incumbent: E0 FBS ratings (model I) with every FCS team at −25.
   - The scorer verifies both files' sha256 as it reads them.
3. **G6d** (stability vs the incumbent) is development only, for the same reason as item 1.
4. **G4 and G6** gate Current C2. The incumbent's, C2f's and K's slopes and deltas are reported alongside.
5. **Definitions:**
   - G5d's Spearman correlation is between predicted and actual margin on FCS-vs-FCS games.
   - G2b's recalibration slope is `glm(w ~ qlogis(p), binomial)` on development.
   - Every 90% interval (G4, G6a, G6b and the G7 season rule) comes from the same block bootstrap as the 95% intervals.
6. **G0c.** The full `tests/c2/run_all.R` runs in the real scoring run. During scorer construction and smoke testing,
   only the checks that read no game outcome run (hashes, rebuild, `test_c2_regression.R`). The equivalence and
   reproduction tests read real outcomes.

## 12. Scoring procedure (exact)

1. **Approval.** You approve this text, with or without striking items 1–4. It is committed, and its sha256 is recorded
   in `docs/round16/predeclaration.sha256`.
2. **Scorer.** `scripts/round16/r16_score.R` implements §3–§8 exactly. It reuses the R15 scorer's functions where the
   rule is unchanged.
   - It refuses to run if `docs/round16/results/` exists (single run).
   - **Smoke mode** replaces every outcome with a synthetic draw, to exercise the code with no real outcome read.
   - After a successful smoke run, the scorer is committed and hashed. That is the freeze.
3. **Real run, once.** In this order:
   - G0;
   - σ for I, C2f, C and K, written and hashed;
   - per-game losses;
   - bootstrap (seed 16016);
   - G1 → G2–G6 → G7 → secondary claim → market M-S, then M-H (descriptive);
   - verdict.
   - Every table and every gate's value and pass/fail is written to `docs/round16/results/` with a hash file.
4. **Report and stop.** `docs/round16/ROUND16_REPORT.md` gives:
   - the verdict and each gate;
   - the secondary claim;
   - per-season, stage, bucket and slice tables;
   - the sensitivities (R15 gp count, fixed σ ∈ {14, 16, 18}, AUC);
   - K for reference.
5. **Then wait for your decision** on production or shadow use and on forward activation. No step after the report
   starts without you.
