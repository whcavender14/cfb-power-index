# C2 Refinement Research: Stage 4 Plan (fixed after the 4A/4B diagnosis, before any candidate is scored)

**Date:** 2026-09-25. **Baseline C2L** = Stage 3 `L_last_n20`. Everything else is fixed:
- the FCS level model and FCS shrinkage;
- garbage-time treatment A, success rate, fumble luck and home field;
- the C1 prior coefficients, turnover-scaled λ, λ0 and ω.

Only the **FBS preseason prior** changes: the scale of its mean and its precision by games played.

## What the diagnosis showed (tables `docs/c2r/stage4/s4a_*`, `s4b_*`)

- **Pure-prior games (both teams gp = 0) are too compressed, not too extreme.**
  - Calibration slope: 1.28 in development (n = 228), 1.09 in 2023–25 (n = 132).
  - Favourites beat the predicted margin in almost every margin bucket.
  - By gp 4+, calibration is about 0.8–1.0.
- **The offense part of the prior difference is the more compressed:** coefficient 1.50 ± 0.23 against defense
  1.06 ± 0.24 (development).
- **Games played:** C2's solve is driven by all games played, including FCS games. Frame gp (R15's slices) agrees with it
  only 19% of the time, so Stage 4 buckets use **all-games gp at the cutoff**, taking the minimum of the two teams.

## Arms

| Family | Arms | Mechanism |
|---|---|---|
| **C2L** | control | |
| **NP** (reference) | FBS prior means = 0, same λ | No preseason information. Used to measure its incremental value. |
| **S(s)**, global scale | s ∈ {0.90, 1.00, 1.10, 1.20, 1.30} | FBS prior mean = s × (a × C1 prior), both sides. The grid spans the "too extreme" hypothesis (0.90) and the observed compression. |
| **O(s_off)**, offense-only scale (secondary) | s_off ∈ {1.10, 1.20, 1.30, 1.40}, s_def = 1 | Offense prior mean only. |
| **D(h)**, exponential decay (on the selected scale) | h ∈ {1, 2, 3, 4, 5} games | Native mechanism: each FBS team's prior precision is λ_i × 0.5^(gp_i / h), where gp_i is the team's games played at the cutoff. The prior mean is unchanged. |
| **F** (diagnostic only, on the selected scale) | for each bucket gp = 1, 2, 3, 4, 5+ separately, multiplier ∈ {0.25, 0.5, 2, 4}, others at 1 (one at a time; 20 arms) | Shows the shape of the ideal decay curve, in both directions. **Not selectable.** |

**Order of choice.** The scale is chosen first, from S and O. D and F are then run at the chosen scale.

## Selection (development 2017–19, 2021–22 only; 2023–25 is descriptive)

1. **Primary metric:** FBS-vs-FBS log-loss (R15 universe, σ fitted leave-one-season-out per arm).
   - Within a family, the grid value is chosen **leave-one-season-out**, giving an honest log-loss.
   - The value carried forward is the one chosen on all five seasons.
2. **Guardrails.** An arm is eligible only if, on development:
   - its log-loss in every gp bucket (0, 1, 2, 3, 4–6, 7+) is no worse than C2L's by more than **+0.003**;
   - its whole-system log-loss (FBS vs FBS plus FBS vs FCS, the Stage 3 J) is no worse than C2L's.
3. **Choosing between families.** The candidates are C2L, the best S or O, and the best S+D. Choose the simplest whose
   honest log-loss is within **0.0003** of the best eligible one. Order of simplicity: C2L < S < O < S+D.
4. **Secondary measures,** reported but not used to select: MAE and RMSE.
5. **Not an objective:** FBS-vs-FCS first-game bias is reported only.

## Reported for every scored arm

- **By gp bucket** (0, 1, 2, 3, 0–3, 4–6, 7+): log-loss, Brier, MAE, RMSE, bias, calibration slope, predicted-margin SD.
- **Incremental value vs NP** in each bucket.
- **Deltas vs C2L, frozen C2 and the incumbent** (development and 2023–25).
- **Descriptive slices, per arm:**
  - P4, G5 and independents;
  - new head coach vs returning;
  - roster continuity high vs low;
  - large preseason favourites;
  - FBS-vs-FCS first games.
- **Interaction with Stage 3:**
  - the FCS level at cutoffs 1–4;
  - FBS-vs-FCS first-game bias;
  - the FBS rating change for teams with vs without FCS opponents.
