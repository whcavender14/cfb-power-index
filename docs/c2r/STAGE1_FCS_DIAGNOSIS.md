# C2 Refinement Research: Stage 1, FCS Calibration Diagnosis

**Date:** 2026-09-25. **Branch:** `c2-refinement`. **Status:** diagnosis only.
- No FCS treatment was changed.
- No correction was fitted, selected or applied.
- No candidate was scored.

**Scripts:** `scripts/c2r/s1a_capture.R`, `s1b_analysis.R`, `s1c_presnap.R`. **Tables:** `docs/c2r/stage1/*.csv`.

> **Governance.**
> - Nothing here is pre-validated.
> - Two kinds of numbers below are **measurements, not candidate corrections**, and neither is applied to any
>   prediction:
>   - the one-parameter in-sample offsets in §3;
>   - the exact prior-pool counterfactuals in §4.
> - The 2023–25 FBS-vs-FCS games were read descriptively here, as Round 15 already did. Stage 3 must select on
>   development seasons only.

## Summary

**The main problem is the FCS level, not the FCS ordering.** C2 places the whole FCS distribution about 10–11 points too
high on the FBS scale:
- development: implied FCS level −28.3 vs C2's −17.5;
- 2023–25: −30.4 vs −19.1.

Within FCS, C2 orders teams about as well as it orders FBS teams. There are two secondary deviations:
- conference-level compression inside FCS;
- a flatter-than-1 response to FBS strength in these games.

The level error comes from **ridge shrinkage of the FCS block toward the FBS-centred scale, applied twice:**
1. **End-of-season fits.** The fits that produce μ_FCS and each team's `last_eos` keep only about half of the FCS level.
   - FCS mean: −14.5, where the same fit with the level left free gives −28.4.
   - These fits leave **+12 points** of FBS margin unexplained in-sample on FBS-vs-FCS games.
2. **In-season.** 63–86% of the FCS block's level is set by that too-high prior. Only about 100 FBS-vs-FCS games link the
   block to FBS.

**C2's own data already contain the signal.** At every weekly cutoff, freeing the level direction would move the FCS
level **9.9 points lower in development and 10.6 lower in 2023–25**. The out-of-sample offset is 10.7 and 11.3.

**Lower-division contamination works in the opposite direction.**
- It currently pulls the FCS prior *down* by about 1.4 points.
- Removing it alone would make the FBS-vs-FCS bias **worse**.
- The lower-division teams themselves are over-rated by about 17 points relative to FCS.

**First-game matchups need a rule.** 40% of FBS-vs-FCS games are an FCS team's first game, with no C2 rating. The natural
rule (C2's prior mean) carries the same level error: bias −9.4 in development, −12.3 in 2023–25.

**FCS errors leak only slightly into FBS ratings.** An FBS team with one FCS game is currently credited about 0.5 point
more than a team with none. FBS-vs-FBS predictions change by about 0.035 point for each point the FCS level moves.

### The five separations you asked for

| # | Question | Finding |
|---|---|---|
| 1 | Overall FCS level/anchor | **Primary problem.** The offset is +10.7 [8.8, 12.2] in development and +11.3 [9.4, 13.2] in 2023–25. It appears in every season (+7.9 to +13.6), every FCS-rating quintile, both FBS tiers and every week. |
| 2 | Relative ranking within FCS | **Largely sound.** The slope of implied FCS strength on C2's rating is 1.10 ± 0.10 (development) and 0.92 ± 0.13 (2023–25). FCS-vs-FCS games have bias ≈ 0, calibration slope 1.00/1.02 and MAE 13.3/12.7, against 12.8/12.3 for C2's FBS-vs-FBS reference. **Exception:** conference-level compression (§3.4). |
| 3 | Prior composition (D-II/D-III/unknown) | The all-division pool mean is −18.2, against −14.6 for FCS alone. The contamination *lowers* FCS ratings by 1.1–1.7 points, which partly offsets the level error. Lower-division teams are about 17 points over-rated relative to FCS. |
| 4 | Shrinkage toward the FBS-centred system | **The mechanism.** End-of-season fits keep about 50% of the FCS level. In-season, the prior sets 63–86% of it. The in-sample data imply a level about 10 points lower (§5). |
| 5 | First-game FCS matchups | 226 of 561 development games and 153 of 365 in 2023–25. The prior-mean rule gives −9.4 [−12.3, −6.2] and −12.3 [−13.7, −10.4]. The flat −25 with C2's FBS ratings gives −0.8 and −4.3. |

## 1. Method and tie-outs

**Replay (s1a).**
- Frozen C2 is replayed at every weekly cutoff. Parameters are read from the construction files and nothing is
  re-estimated.
- The full ridge system is captured at each cutoff: `Q b = X'Wy + Λp`.
- `b` is linear in `y` and `p`, and Q does not depend on either. So the following are exact linear algebra on C2's own
  system:
  - every rating splits exactly into contributions from each data block and each prior;
  - the "level" measurements;
  - the prior-pool counterfactuals.

**Checks, all passed:**
- Replayed predictions equal all 6,266 frozen C2 predictions to 5.7e-14.
- The captured FCS ratings equal the E0 ratings replay to 6.4e-14.
- The end-of-season fits equal the frozen `eos_full` to 1.4e-14.
- The block decomposition sums to each rating to 1.6e-13.
- π_prior + π_data = 1 to 4e-16.
- The Round 15 FBS-vs-FCS slice is reproduced exactly: −10.4960 (n = 335) and −11.3138 (n = 212). Both are
  home-oriented.

**Sign convention.**
- Here margins are **FBS-oriented**, and bias = predicted − actual. **Negative bias means the FCS team was rated too high.**
- The development bias is −10.72 FBS-oriented, against Round 15's −10.50 home-oriented. The gap comes from the 8 games
  that were not FBS home games (7 neutral, 1 FCS home).
- Confidence intervals use a cluster bootstrap over season × cutoff blocks, with 2,000 draws.

**Correction to Stage 0.** Stage 0 counted 207 development and 141 2023–25 FCS first games, using games played before
kickoff. The right definition is "not rated at the cutoff":
- **226 development and 153 in 2023–25.**
- The extra games involve FCS teams whose previous game finished after that week's cutoff.
- 226 + 335 = 561 and 153 + 212 = 365.

## 2. Where the predicted margin comes from (rated games, means)

| Component | Development (n = 335) | 2023–25 (n = 212) |
|---|---|---|
| Actual FBS margin | 30.7 | 31.3 |
| Predicted (C2) | 20.0 | 20.0 |
| FBS rating | −0.9 | −2.1 |
| Home field | +3.3 | +3.0 |
| **FCS rating** | **−17.5** | **−19.1** |
| … prior mean (μ + ρ·(last − μ)) | −17.9 | −18.6 |
| … in-season update | +0.4 | −0.5 |
| Implied FCS strength (FBS rating + home field − actual) | **−28.3** | **−30.4** |
| FCS rating with the level direction unpenalized (in-sample) | −27.5 | −29.7 |

**Exact block contributions to the FCS rating** (development / 2023–25):
- FCS priors: −13.4 / −14.0
- FBS-vs-FCS points rows: −4.3 / −4.9
- FBS-vs-FCS SR rows: −1.3 / −1.3
- FCS-vs-FCS points rows: +1.4 / +1.0
- FBS priors: −0.2 / −0.2
- HFA removal: +0.3 / +0.4
- Fumble luck and FBS-vs-FBS rows: ≈ 0

**Reading.**
- In-season updating leaves the average FCS opponent's rating where its prior put it.
- The FBS-vs-FCS evidence pulls down by about 5.5 points, but only after the prior has been weighted at about 75%.

## 3. Level vs ordering

### 3.1 The FCS-wide offset with C2's relative ratings held fixed

This is the constant that, added to every FCS rating, would make the mean error zero (= −bias).

| Season | 2017 | 2018 | 2019 | 2021 | 2022 | Dev | 2023 | 2024 | 2025 | 2023–25 |
|---|---|---|---|---|---|---|---|---|---|---|
| Offset | 7.9 | 13.1 | 11.4 | 8.1 | 12.2 | **10.7** [8.8, 12.2] | 9.3 | 10.9 | 13.6 | **11.3** [9.4, 13.2] |
| n | 48 | 65 | 72 | 72 | 78 | 335 | 76 | 60 | 76 | 212 |

### 3.2 Is the ordering right?

Regress implied FCS strength u on C2's FCS rating.

| | Development | 2023–25 |
|---|---|---|
| Slope on C2 FCS rating (1 = spread correct) | 1.10 (SE 0.10) | 0.92 (0.13) |
| … prior-mean part | 1.36 (0.14) | 0.99 (0.17) |
| … in-season-update part | 0.84 (0.16) | 0.82 (0.22) |
| Free regression of actual margin: FBS-rating coefficient | 0.81 (0.08) | 0.83 (0.09) |
| Free regression: FCS-rating coefficient | −1.07 (0.10) | −0.88 (0.13) |

**Bias by quintile of C2's FCS rating:**
- Development: Q1 −11.1, Q2 −10.6, Q3 −12.7, Q4 −9.5, Q5 −9.8.
- 2023–25: −8.8, −9.7, −15.4, −10.8, −11.7.
- There is no trend: the error is a shift, not a stretch.

**Ordering information.** Each column below has its own in-sample mean removed (1 degree of freedom each). This measures
the ordering, not a correction.

| | Development | 2023–25 |
|---|---|---|
| Residual SD with C2's FCS ratings | **16.3** | **15.7** |
| … with prior mean only (no in-season update) | 16.9 | 16.2 |
| … with one constant for every FCS team | 18.8 | 17.4 |
| MAE with C2's ordering vs constant, offset removed | 12.8 vs 14.9 | 12.5 vs 13.8 |

**Secondary deviation on the FBS side.**
- The FBS-rating coefficient is 0.81–0.83.
- The bias is largest for the weakest FBS teams: Q1 −14.7 vs Q5 −8.8 in development.
- It is also largest for small predicted margins: < 14 gives −14.6, while 42+ gives −3.0 (n = 16).
- In these games, actual margins respond less to FBS strength than predicted, which fits blowout compression. This is
  flagged for Stage 2 and not diagnosed further here.

### 3.3 FCS-vs-FCS games: a test of relative ratings that ignores the level

| Games | n (dev / 2023–25) | Bias | MAE | Calibration slope | Correlation |
|---|---|---|---|---|---|
| FCS vs FCS, C2 | 2,958 / 1,878 | +0.7 / −0.1 | 13.3 / 12.7 | 1.00 / 1.02 | 0.60 / 0.61 |
| FCS vs FCS, prior mean only | same | | 14.8 / 14.1 | 1.14 / 1.17 | |
| FBS vs FBS, C2 (reference) | 3,868 / 2,398 | +0.6 / +0.1 | 12.8 / 12.3 | 1.00 / 0.98 | 0.64 / 0.64 |
| **FCS vs lower division** (FCS-oriented) | 44 / 38 | **−16.9 / −17.7** | 19.5 / 21.5 | | |

### 3.4 Is one FCS-wide offset enough?

Mostly, but not entirely.

**Conference spread in the FBS-vs-FCS error:**
- Development: F = 1.51, p = 0.14. 2023–25: F = 2.61, **p = 0.007**.
- Most over-rated: SWAC and MEAC, −14 to −22.
- Least over-rated:
  - Big Sky, −4.5 to −9.1;
  - MVFC, −6.9 to −10.9;
  - UAC, −1.3.

**The same pattern inside FCS.** In cross-conference FCS-vs-FCS games, weak, isolated conferences do worse than C2
predicts and strong ones do better.

| Conference | Development | 2023–25 |
|---|---|---|
| Pioneer | −20.1 | −18.1 |
| SWAC | −5.8 | −11.8 |
| NEC | −4.9 | −3.6 |
| Patriot | −4.9 | 0.0 |
| CAA (Coastal Athletic from 2023) | +7.7 | +1.3 |
| MVFC | +5.8 | +6.9 |
| Big Sky | +5.4 | +3.4 |
| UAC | | +4.9 |

This is the same shrinkage mechanism acting on thinly linked conference sub-blocks. It is a real but second-order
ordering problem: the SD of conference means is 3.6–5.7, including noise, against a 10.7–11.3 common offset.

## 4. Prior composition

**FCS prior-mean pools** (power = off − def, over entity-seasons in each parameter key's training window):

| Key | All non-FBS (used) | FCS only | D-II | D-III | Unknown | FCS share |
|---|---|---|---|---|---|---|
| 2017 | −18.2 | −14.6 | −24.2 | −24.0 | −33.0 | 70% |
| 2019 | −18.1 | −14.4 | −24.7 | −29.4 | −33.0 | 71% |
| 2022 | −18.2 | −14.5 | −24.6 | −30.3 | −33.6 | 72% |
| 2023 (for 2023–25) | −18.3 | −14.7 | −24.8 | −30.8 | −34.0 | 72% |

**Exact attributions (counterfactuals on C2's own system, ρ unchanged):**

| Change | FCS ratings (dev rated / dev first game / 2023–25 rated / 2023–25 first game) | Effect on bias |
|---|---|---|
| cf1: FCS teams use the FCS-only pool mean | +1.37 / +1.72 / +1.09 / +1.39 | **worse** by 1.2–1.7 |
| cf2: every division uses its own pool mean | +1.12 / +1.72 / +0.91 / +1.39 | worse by 1.0–1.7 |

- **The difference between cf1 and cf2** is about 0.25 point. That is how much the lower-division teams' too-high priors
  currently inflate FCS ratings through FCS-vs-lower-division games.
- **Lower-division entities** in each season's solve at the season's end:
  - 27–36 D-II, 1–5 D-III and 10–17 unknown, alongside about 125–130 FCS teams;
  - they appear in 46–67 of about 700 non-FBS games;
  - the PBP and schedule data have no D-II-vs-D-II games, so their ratings rest on about one game plus the FCS prior;
  - FCS teams beat them by about 17 points more than C2 predicts (§3.3).
- **FBS teams play no lower-division opponents** in the evaluation set: every FBS-vs-non-FBS game after the first cutoff
  is against an FCS team.

## 5. Shrinkage toward the FBS-centred system

### 5.1 End-of-season fits (the source of μ_FCS and `last_eos`)

The fits apply penalty 1 toward 0 (the FBS mean) for every team. "Free" below means the same fit plus one unpenalized
column that shifts every non-FBS team's power by a common amount; that column is informed only by FBS-vs-non-FBS rows.

| Season | FCS mean, penalized | FCS mean, free level | D-II penalized / free | Level share set by prior (FCS) | In-sample FBS-margin residual, FBS-vs-FCS |
|---|---|---|---|---|---|
| 2014 | −14.1 | −29.1 | −23.5 / −42.8 | 0.43 | +13.0 |
| 2017 | −13.3 | −27.5 | −23.6 / −41.7 | 0.44 | +12.4 |
| 2019 | −14.5 | −28.4 | −24.5 / −42.6 | 0.41 | +12.3 |
| 2022 | −15.9 | −29.3 | −26.5 / −45.1 | 0.39 | +12.2 |
| 2025 | −16.6 | −30.3 | −27.5 / −46.4 | 0.38 | +12.6 |

The full table for 2013–2025 is in `stage1/s1_eos_level_shrinkage.csv`. μ_FCS and ρ·`last_eos` are built from the
penalized column, so the C2 prior starts about 14 points too high for FCS teams.

### 5.2 In-season C2 (development seasons, averaged by weekly cutoff)

Cutoff # is the season's n-th weekly cutoff. #1 precedes any game, and #3 is typically after the first full weekend.

| Cutoff # | 3 | 4 | 5 | 6 | 8 | 10 | 12 | 14 | Final |
|---|---|---|---|---|---|---|---|---|---|
| FCS-division entities | 102 | 118 | 125 | 127 | 127 | 127 | 127 | 127 | 127 |
| FBS-vs-FCS games so far | 36 | 70 | 89 | 97 | 101 | 103 | 105 | 110 | 112 |
| Level share set by prior, π_prior | 0.86 | 0.75 | 0.70 | 0.67 | 0.66 | 0.65 | 0.64 | 0.63 | 0.63 |
| Free-level gap (in-sample) | −9.4 | −9.8 | −9.9 | −9.6 | −9.5 | −9.5 | −9.5 | −9.3 | −9.2 |
| In-sample FBS-margin residual on FBS-vs-FCS games | +5.0 | +6.1 | +6.7 | +6.7 | +6.8 | +6.9 | +7.0 | +6.9 | +6.9 |

### 5.3 The level chain (rated games)

| Season | Prior level | C2 level | Implied | Prior error | C2 error | Free-level gap | Offset |
|---|---|---|---|---|---|---|---|
| 2017 | −18.1 | −16.8 | −24.7 | 6.6 | 7.9 | −6.9 | 7.9 |
| 2018 | −18.0 | −17.4 | −30.5 | 12.5 | 13.1 | −14.2 | 13.1 |
| 2019 | −17.5 | −17.1 | −28.5 | 11.0 | 11.4 | −10.5 | 11.4 |
| 2021 | −18.4 | −18.7 | −26.8 | 8.4 | 8.1 | −6.8 | 8.1 |
| 2022 | −17.5 | −17.4 | −29.6 | 12.2 | 12.2 | −10.4 | 12.2 |
| 2023 | −18.3 | −18.1 | −27.4 | 9.2 | 9.3 | −10.0 | 9.3 |
| 2024 | −18.4 | −19.5 | −30.4 | 12.0 | 10.9 | −11.1 | 10.9 |
| 2025 | −19.1 | −19.7 | −33.3 | 14.3 | 13.6 | −10.7 | 13.6 |

**Reading.**
- The out-of-sample level error is essentially the prior's level error: C2 error / prior error is 0.91–1.20.
- In every season, the in-sample data at the cutoff put the level about as far below C2 as the outcomes later do.
- The implied FCS level drifts more negative over time: −24.7 in 2017, −33.3 in 2025. The free-level end-of-season FCS
  mean goes from −27.5 to −30.3. **Any fixed constant will age.**

## 6. First-game FCS matchups (no C2 rating yet)

| | Development | 2023–25 |
|---|---|---|
| Games (share of FBS-vs-FCS) | 226 (40%) | 153 (42%) |
| Prior-mean rule: bias [95% CI], MAE | −9.4 [−12.3, −6.2], 16.1 | −12.3 [−13.7, −10.4], 15.5 |
| … teams with a last-season rating | −10.0 (n = 188) | −12.3 (n = 153) |
| … teams without (μ only) | −6.4 (n = 38) | none |
| Flat −25 with C2's FBS rating (reference) | −0.8 [−3.2, 1.5], 15.4 | −4.3 [−6.1, −3.1], 13.5 |

The first-game problem is not a separate mechanism. It is the same level error, seen without any in-season data. Every
first-game opponent in the evaluation set is FCS-division.

## 7. Bias slices (C2, rated games; the full table is in `stage1/s1_bias_slices.csv`)

| Slice | Development | 2023–25 |
|---|---|---|
| Weekly cutoff #3 / #4–5 / #6+ | −12.5 / −10.0 / −8.3 | −10.0 / −13.8 / −7.7 |
| FCS games played 1 / 2–3 / 4–6 / 7+ | −12.0 / −10.6 / −5.1 (n = 16) / −8.5 | −10.0 / −14.2 / −9.9 / −6.7 |
| FCS team's FBS games to date 0 / 1+ | −11.1 / −9.9 | −11.9 / −10.2 |
| FBS tier G5 / P4 / Independent | −11.4 / −10.6 / −8.0 | −11.8 / −10.4 / −16.0 (n = 7) |
| Site | FBS home 327, neutral 7, FCS home 1 | FBS home 210, neutral 2 |
| Predicted margin < 14 / 14–28 / 28–42 / 42+ | −14.6 / −9.0 / −10.5 / −3.0 | −12.9 / −12.7 / −9.2 / −2.3 |

The level error is broad-based. The strongest gradients are with FBS strength and predicted margin (§3.2).

## 8. Fixing margins vs fixing ratings

**A margin-only FBS-vs-FCS "+X" changes no rating:**
- FCS teams keep ratings about 10 points too high wherever they are used as opponents, including strength of schedule,
  opponent adjustment and season simulation;
- FBS ratings keep their small FCS-induced credit.

**A level fix through the FCS prior or anchor moves both.** Sensitivity of FBS ratings to the FCS level, at the season's
final cutoff in development:

| FBS team's games vs non-FBS | Team-seasons | ΔFBS rating per +1 FCS level |
|---|---|---|
| 0 | 104 | −0.043 |
| 1 | 533 | +0.007 |
| 2 | 14 | +0.049 |

- **Current credit.** With FCS about 10 points too high, a team with one FCS game is credited about 0.5 point more than
  a team with none, and a team with two games about 0.9 point more.
- **Effect on FBS-vs-FBS predictions.** They change by a mean of |0.036| (development) and |0.030| (2023–25) per point of
  FCS level; p90 is 0.10 and max 0.27. At a 10-point level change, that is a mean of about 0.3–0.4 point, p90 about 1
  and max about 2.7.

## 9. Pre-snap margins (flagged for Stage 2; no fix)

The frozen filter drops plays when the margin is above 38 in Q2, above 28 in Q3 or above 22 in Q4, and always in
overtime. Figures below are shares of *scrimmage* plays. Stage 0 gave shares of all play rows.

| | FBS-vs-FBS dev / 2023–25 | FBS-vs-FCS dev / 2023–25 |
|---|---|---|
| Dropped by the filter | 8.8% / 8.1% | **22.7% / 23.3%** |
| Kept plays in Q2 with \|margin\| > 21 | 6.0% / 5.1% | 20.7% / 19.8% |
| Kept plays in Q3 with \|margin\| > 21 | 10.7% / 9.7% | 23.4% / 22.4% |

**Where the margins are in FBS-vs-FCS games (development):**
- Q3: 34% of scrimmage plays are at |margin| > 28.
- Q4: 59% are at |margin| > 22, against 25% in FBS-vs-FBS.

**Success rate by |margin| band, FBS-vs-FCS (development):**
- FBS offense: 0.45 at 0–8, 0.49 at 17–28, 0.47 at 39+.
- FCS offense: 0.32 at 0–8, 0.28 at 39+.

In these games, success rate does not fall off sharply in blowouts. This is descriptive only.

## 10. What this implies for the Stage 3 design

These are observations for Stage 3. Nothing is selected here.

1. **Test the prior pool together with a level fix.**
   - Restricting the pool to FCS raises FCS ratings by about 1.1–1.7 points, so on its own it worsens the bias.
   - Lower-division entities need their own treatment either way (§3.3, §4).
2. **"Stronger FCS shrinkage" should target the block level, not individual teams.**
   - More shrinkage toward the *current* prior raises π_prior and holds the level where it is now.
   - The error is in the level of the prior mean (from penalized end-of-season fits) and in how little the linking
     games can move it.
   - Anchoring and offset variants act on that level direction.
3. **Run the +X grid as the margin-only benchmark and keep it separate from rating fixes (§8).**
   - Its season-by-season stability matters, because the implied level drifts from about −25 to −33.
4. **Every level fix must also apply to the first-game rule** (40% of FBS-vs-FCS games).
5. **Leave the conference-level compression as a known residual for now.**
   - An FCS-wide fix leaves SWAC, MEAC and Pioneer over-rated relative to the strong conferences.
   - Conference-level anchoring would be a separate, later question with small samples.
6. **The FBS-side slope and blowout compression (§3.2) are Stage 2 material** and may interact with any +X.
7. **Holdout hygiene.** This stage read 2023–25 outcomes descriptively. Stage 3 fits and selections must use development
   seasons only, and 2023–25 should be reported as a descriptive check.
