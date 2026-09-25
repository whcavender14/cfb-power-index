# C2 Refinement Research: Stage 2, Garbage-Time Treatment

**Date:** 2026-09-25. **Branch:** `c2-refinement`. **Status:** development research.
- No threshold was searched or tuned.
- The FCS treatment is unchanged: no offset and no prior change.
- Nothing is pre-validated.

**Scripts:** `scripts/c2r/s2a_sr_rebuild.R`, `s2b_rebuild.R`, `s2c_evaluate.R`, `lib_c2r.R`. **Tables:**
`docs/c2r/stage2/*.csv`.

> **Governance.**
> - The arms are defined by the published source, not by fitting.
> - Each arm re-runs the frozen Round 15 construction procedure unchanged. That includes C2's own re-selection of β, ω
>   and λ0, which is part of the frozen method.
> - 2023–25 outcomes were read descriptively, as in Stage 1.

## Summary

**The garbage-time rule does not matter for C2's accuracy, and it explains none of the FCS discrepancy.**

**Removing the filter (A0):**
- It changes the success-rate input a lot:
  - 10% of scrimmage plays come back;
  - about a third of FBS-vs-FBS game rows and two thirds of FBS-vs-FCS game rows change;
  - β falls about 10%.
- It moves C2's predictions by 0.5 point on average (maximum 4.8).
- Yet no accuracy measure changes detectably on development or 2023–25:
  - development log-loss −0.0002 [−0.0016, +0.0011];
  - 2023–25 log-loss +0.0008 [−0.0004, +0.0020].
- **The FBS-vs-FCS bias moves by 0.02 points:** −10.74 vs −10.73.

**The published SP+ definition (B)** differs slightly from frozen C2's rule (A). It gives the same results as A within
noise.

**The success-rate evidence is not what over-rates FCS teams.** Under every treatment, the SR rows from FBS-vs-FCS games
say FCS teams are *weaker* than C2 rates them, and by more than the scoreboard says. The FCS problem remains the
level/anchor problem found in Stage 1.

### Your six questions

| # | Question | Answer |
|---|---|---|
| 1 | Is the existing filter helping C2? | **No detectable effect either way.** Development favors no filter by a hair; 2023–25 favors the filter by a hair. Every overall CI straddles 0 (§4). |
| 2 | How much worse or better does the FCS level problem get with no filter? | **Unchanged.** Bias −10.74 vs −10.73 (development) and −11.31 vs −11.31 (2023–25). The mean FCS rating moves by +0.04 points (§6). |
| 3 | Does garbage time explain any portion of the ~10–11-point FCS discrepancy? | **No:** ≤ 0.2% of it. The whole SR channel contributes only −1.2 to −1.3 points to FCS ratings, and in the right direction (down). |
| 4 | Does the filter improve FBS-vs-FBS predictions, or mainly blowouts and FBS-vs-FCS? | **Neither measurably.** FBS-vs-FBS: no overall difference. Blowout-predicted games (\|pred\| 21+): −0.0006 [−0.0032, +0.0018]. FBS-vs-FCS: no difference. A few slice CIs exclude 0, with inconsistent signs across periods (§4.3). |
| 5 | Are FCS teams accumulating misleading SR information even after the filter? | **Not information that flatters them.** In C2's own fit, SR rows from FBS-vs-FCS games put the FBS margin about 13 points above the fit, against about 7 for points rows. SR says FCS teams are weaker than rated. Two limitations remain (§7): FCS SR comes only from FBS games, and the SR-to-points scale is calibrated on FBS-vs-FBS games. |
| 6 | Does the treatment alter only SR, or the downstream system? | **It propagates, but the effects are small and accuracy-neutral** (§5). β changes 10%, the C1 prior moves (SD ≤ 0.3), FBS ratings move (SD 0.47) and predictions move (mean \|0.53\|). ω, λ0, the prior scale and the FCS level do not change. About 93% of the prediction movement comes through the in-season SR rows. |

## 1. The published SP+ definition (B): source verification

| Date | Source | Definition as written |
|---|---|---|
| Before 2017 | Connelly, Football Study Hall, "Fun with game states" (20 Oct 2017), describing his long-standing rule | Garbage time is "anything that takes place when a team is up by more than 28 in the first quarter, up by more than 24 in the second, up by more than 21 in the third, or up by more than 16 in the fourth." |
| 20 Oct 2017 | Same post, a proposal ("I'm going to tinker with this definition") | All Q1 plays count. Garbage time "doesn't kick in until a team is up 36 in the second quarter … 26 in the third … 20 in the fourth." |
| 2018 season | Football Outsiders 2018 S&P+ offense ratings page (official S&P+ host; archived capture 10 May 2020) | "a game is not within 38 points in the second quarter, 28 points in the third quarter, or 22 points in the fourth quarter." |
| **3 Sep 2019** | **Connelly, @ESPN_BillC** (archived capture 13 Sep 2019), replying to "When does garbage time engage?" | **"Lead of 44+ in Q1, 38+ in Q2, 28+ in Q3, 22+ in Q4. I expanded the definition a bit a year or two ago."** Same thread: "The garbage time plays still don't count even if the game gets de-garbaged." |
| Oct 2020 | Daily Nebraskan (secondary) | 43+ / 37+ / 29+ / 22+. This is inconsistent with the author's own statement and was not used. |

**Choosing B.** Connelly's 2019 statement is the most explicit and most authoritative dated source:
- it comes from the author;
- it gives numbers and an inclusive boundary ("+");
- it postdates the 2018 change.

So **B = drop a play when the pre-snap |margin| is ≥ 44 in Q1, ≥ 38 in Q2, ≥ 28 in Q3 or ≥ 22 in Q4.**

**Frozen A is not identical to B.** A is the Football Outsiders 2018 wording read literally: margin > 38/28/22, with no
Q1 rule. The differences:
- B drops plays at exactly 38, 28 or 22, and adds a Q1 rule.
- B removes 11% more plays than A (61,415 vs 55,435 in development).
- So B was run as a separate arm, not a redundant one.

**Common to all three arms:**
- **Per-play filtering.** A "de-garbaged" game's later plays count again. Only plays during garbage time are dropped.
- **Overtime is dropped in every arm,** as frozen C2 does. No source addresses overtime; it is about 0.2% of plays.
- **Margin means the pre-snap score margin.** The FO text also says "possessions"; for play-level success rate, the
  play-level reading is the natural one.

## 2. Method

**1. SR inputs (s2a).**
- The frozen Round 13 instrument was re-run for 2013–2025 under each treatment. This includes the P2 fumble parser and
  the A3 2020 patch; only the garbage vector changes.
- **Arm A reproduces the frozen inputs exactly:** all 20,010 game × offense SR rows (0 difference) and all 1,691
  end-of-season SR rows (5e-16).

**2. Full C2 rebuild (s2b).** For each treatment, the frozen construction was re-run:
- C1: priors (which use last season's SR), variance models, scale and λ0 selection;
- C2: β, κ, the FCS moments, ω selection, predictions for 2017–25 and the full rating capture.
- **Arm A reproduces frozen C1 and C2 exactly:** priors 1e-14; all 6,266 predictions to 1.6e-10.
- For A0 and B, the captured ratings reproduce `r15_predict_season_c2` to 1e-9.

**3. Attribution arms "A0rows" and "Brows".** These take the treatment's in-season SR rows and β, with every other frozen
component kept (prior, λ0, scale, ω). The difference between the full and rows arms is the prior channel.

**4. Scoring (s2c)** is the Round 15 scorer's rules:
- σ fitted leave-one-season-out on development, and on all of development for 2023–25;
- FBS-vs-FBS universe of 3,868 development and 2,398 2023–25 games;
- season × cutoff block bootstrap, 4,000 draws;
- **arm A reproduces Round 15's C2 metrics exactly:** log-loss 0.526127 and 0.530401.

## 3. The success-rate input under each treatment

**Scrimmage plays** (passing every non-garbage rule), development 2017–19 and 2021–22:

| | Scrimmage plays | Removed: A | Removed: B | Removed: A0 |
|---|---|---|---|---|
| All | 542,853 | 55,435 (10.2%) | 61,415 (11.3%) | 0 |
| FBS vs FBS | 478,114 | 40,831 (8.5%) | 45,793 (9.6%) | 0 |
| FBS vs FCS | 64,739 | 14,604 (22.6%) | 15,622 (24.1%) | 0 |

2023–25 (316,476 plays):
- all: A 9.9%, B 10.8%;
- FBS vs FBS: A 7.9%, B 8.7%;
- FBS vs FCS: A 23.3%, B 24.8%.

Overtime removes a further 1,160 plays (development) in every arm.

**Offensive success rate of kept plays** (development, play-weighted):

| | A | A0 | B |
|---|---|---|---|
| FBS vs FBS | 0.396 | 0.395 | 0.396 |
| FBS offense vs FCS | 0.464 | 0.466 | 0.463 |
| FCS offense vs FBS | 0.318 | 0.315 | 0.319 |

**Pooled play-weighted rates mislead here.** They mix games of different strength. The model uses one SR value per game
and offense, and within a game the effect runs the other way.

**Game × offense SR rows** (the in-season input), A0 − A:
- **FBS-vs-FBS rows:** 34% change, with a mean |ΔSR| of 1.2 SR points and a mean Δ of about 0.
- **FBS-vs-FCS games:**
  - 67–69% of rows change;
  - FBS offense −1.1 SR points and FCS offense +1.2 in development (−1.2 and +0.8 in 2023–25);
  - so garbage time (backups on both sides) **narrows the FBS–FCS SR gap within a game by about 2.3 SR points.**
- **B − A:** about 10% of rows change, by 0.2–0.5 SR points.

## 4. Construction outputs and FBS-vs-FBS accuracy

### 4.1 Construction outputs

| Parameter key | 2017 | 2018 | 2019 | 2021 | 2022 | 2023 |
|---|---|---|---|---|---|---|
| β (SR per point), A | 0.00534 | 0.00523 | 0.00531 | 0.00536 | 0.00544 | 0.00549 |
| β, A0 | 0.00483 | 0.00471 | 0.00474 | 0.00477 | 0.00485 | 0.00488 |
| β, B | 0.00540 | 0.00530 | 0.00537 | 0.00542 | 0.00550 | 0.00555 |
| Points per SR point: A / A0 / B | 1.87 / 2.07 / 1.85 | 1.91 / 2.12 / 1.89 | 1.88 / 2.11 / 1.86 | 1.87 / 2.10 / 1.85 | 1.84 / 2.06 / 1.82 | 1.82 / 2.05 / 1.80 |

**Unchanged across arms:**
- ω (0.5, then 0.25);
- λ0 (3, 3, 4, 4, 4);
- the C1 prior scale (changes ≤ 0.012).

**C1 prior power ratings,** difference from A:
- A0: SD 0.08–0.30, maximum 1.44;
- B: SD 0.02–0.12.

### 4.2 Overall (FBS vs FBS)

| | Log-loss | Brier | MAE | RMSE | Bias | Calibration slope | σ |
|---|---|---|---|---|---|---|---|
| **Development, A (= R15 C2)** | 0.52613 | 0.17681 | 12.834 | 16.207 | +0.64 | 0.999 [0.953, 1.042] | 15.72 |
| Development, A0 | 0.52595 | 0.17678 | 12.836 | 16.191 | +0.64 | 1.009 | 15.58 |
| Development, B | 0.52613 | 0.17680 | 12.834 | 16.210 | +0.64 | 0.999 | 15.71 |
| **2023–25, A** | 0.53040 | 0.18003 | 12.266 | 15.440 | +0.12 | 0.985 [0.940, 1.032] | 15.72 |
| 2023–25, A0 | 0.53117 | 0.18040 | 12.281 | 15.451 | +0.13 | 0.988 | 15.57 |
| 2023–25, B | 0.53052 | 0.18008 | 12.269 | 15.442 | +0.13 | 0.983 | 15.71 |

**Paired deltas vs A** (95% CI; negative = better):

| | Development log-loss | Development MAE | 2023–25 log-loss | 2023–25 MAE |
|---|---|---|---|---|
| A0 − A | −0.00018 [−0.00155, +0.00107] | +0.002 [−0.027, +0.030] | +0.00077 [−0.00039, +0.00198] | +0.015 [−0.011, +0.043] |
| B − A | +0.000001 [−0.00041, +0.00043] | −0.001 [−0.009, +0.008] | +0.00012 [−0.00018, +0.00042] | +0.004 [−0.004, +0.011] |
| A0rows − A | −0.00020 [−0.00153, +0.00101] | +0.002 | +0.00054 [−0.00057, +0.00166] | +0.007 |
| C1 rebuilt, A0 − A (prior channel alone) | −0.00002 [−0.00031, +0.00028] | −0.003 | +0.00024 [−0.00022, +0.00069] | +0.009 |

The full tables, including Brier and RMSE, are in `stage2/s2_fbs_deltas.csv`.

### 4.3 Slices (A0 − A log-loss; full table in `stage2/s2_fbs_slice_deltas.csv`)

| Slice | Development | 2023–25 |
|---|---|---|
| Seasons | 2017 −0.0003, 2018 −0.0012, 2019 −0.0001, 2021 −0.0012, 2022 +0.0019 (all CIs include 0) | 2023 −0.0005, 2024 +0.0023, 2025 +0.0005 (all include 0) |
| Games played (min of the two teams): 0 / 1 / 2–3 / 4–6 / 7+ | **−0.0023** / **+0.0047** / +0.0019 / −0.0017 / −0.0006 | +0.0028 / −0.0016 / **+0.0041** / +0.0016 / −0.0012 |
| P4-P4 / P4-G5 / G5-G5 | +0.0003 / +0.0006 / −0.0007 | **+0.0022** / +0.0020 / −0.0016 |
| \|Predicted margin\| < 7 / 7–14 / 14–21 / 21+ | +0.0001 / +0.0001 / −0.0009 / −0.0006 | +0.0020 / −0.0005 / +0.0012 / −0.0006 |

**Bold** marks a 95% CI that excludes 0. There are about 130 slice comparisons.
- Games played 0 and 1 reverse sign between periods.
- Games played 2–3 and P4-P4 lean against A0 in both periods but are significant only in 2023–25.
- This is consistent with multiplicity, not a coherent filter effect.
- Games predicted to be blowouts show no effect.

**Calibration slope** by games played (A / A0 / B) is within 0.02 in every bucket. For example, development at 4–6 games
played is 0.858 / 0.875 / 0.859.

**Oriented P4-vs-G5 error** (P4 under-prediction):
- development: 4.57 / 4.68 / 4.60;
- 2023–25: 0.49 / 0.51 / 0.45.

## 5. Downstream movement (question 6)

| vs A | FBS ratings: SD of difference (maximum) | FBS-vs-FBS predictions: mean \|Δ\| / SD / maximum |
|---|---|---|
| A0 (full rebuild) | 0.47 (3.6) | 0.53 / 0.71 / 4.8 |
| A0rows (in-season SR rows + β only) | 0.45 (3.3) | 0.49 / 0.68 / 4.8 |
| B (full) | 0.16 (2.5) | 0.16 / 0.25 / 2.6 |
| Brows | 0.15 (2.5) | 0.14 / 0.23 / 2.6 |
| C1 only (prior channel), A0 / B | | 0.16 / 0.06 mean \|Δ\| |

**Rating stability:**

| | A | A0 | B |
|---|---|---|---|
| Mean absolute week-to-week change, development | 0.968 | 0.957 | 0.967 |
| Top-25 Kendall distance, development | 0.079 | 0.079 | 0.081 |
| Mean absolute week-to-week change, 2023–25 | 0.827 | 0.823 | 0.827 |

**Reading.**
- The treatment really does change the fitted system, almost entirely through the in-season SR rows.
- The changes behave like noise with respect to accuracy.

## 6. FBS-vs-FCS games and the FCS level (questions 2 and 3)

Margins are FBS-oriented, and bias = predicted − actual.

| | n | Bias A / A0 / B | MAE | RMSE | Log-loss | Brier |
|---|---|---|---|---|---|---|
| Development, rated FCS team | 335 | −10.73 / −10.74 / −10.74 | 15.80 / 15.77 / 15.80 | 19.51 / 19.50 / 19.51 | 0.229 / 0.228 / 0.229 | 0.064 / 0.063 / 0.064 |
| Development, first game (prior mean) | 226 | −9.36 / −9.38 / −9.35 | 16.1 all | 20.0 all | 0.286 / 0.283 / 0.285 | 0.078 / 0.077 / 0.077 |
| 2023–25, rated | 212 | −11.31 / −11.31 / −11.32 | 15.56 all | 19.35 / 19.39 / 19.36 | 0.223 / 0.221 / 0.223 | 0.061 / 0.061 / 0.061 |
| 2023–25, first game | 153 | −12.32 / −12.31 / −12.32 | 15.49 all | 19.29 all | 0.188 / 0.186 / 0.187 | 0.045 all |

- **FCS level on rated games:**
  - C2 FCS rating −17.53 / −17.49 / −17.51;
  - implied by outcomes −28.26 / −28.23 / −28.25.
- **Change in the mean FCS rating vs A:**
  - A0: +0.04 (development), −0.01 (2023–25);
  - B: +0.02 / +0.01.
- **Season offsets change by at most 0.13,** and so does the bias by FCS games played.
- **Contribution of the FBS-vs-FCS SR rows to the FCS rating:** −1.27 / −1.22 / −1.25.
- **Relative FCS ranking is unchanged:**
  - slope of implied strength on the FCS rating: 1.10 / 1.10 / 1.11;
  - FCS-vs-FCS MAE 13.3 in every arm, calibration slope 1.001 / 0.999 / 1.003.

**Why so small?**
- A0 narrows the within-game FBS–FCS SR gap by about 2.3 SR points. But β also falls about 10%, so the SR margin in
  *points* moves only about 1 point: 33.4 → 32.4.
- SR rows carry weight ω = 0.25 against weight 1 for points rows.
- 63–86% of the FCS level is set by the prior (Stage 1).
- Together these reduce the net effect to a few hundredths of a point.

## 7. Is SR evidence misleading about FCS teams? (question 5)

**In-sample FBS-margin residual on FBS-vs-FCS games** (points units; > 0 means the FBS team did better than C2's fit):

| Development, all cutoffs | A | A0 | B |
|---|---|---|---|
| Points rows | +6.6 | +6.7 | +6.7 |
| SR rows | **+13.6** | +12.6 | +13.2 |

2023–25 gives the same picture: points +7.6, SR +13.3 to +14.0.

**Model-free check at season's end** (development):
- **SR margin in points** (the arm's β) in FBS-vs-FCS games averages 33.4 / 32.4 / 32.9.
- **The actual points margin net of home field** is 26.3.
- In 2023–25 the figures are 35.3 / 35.7 / 34.9 against 28.5.

**Reading.**
- **The SR evidence is directionally right and not flattering to FCS teams.** It says they are weaker than C2 rates them,
  more strongly than the scoreboard does.
- **The garbage filter is not what keeps it that way:** A0 has the same sign and nearly the same size.
- **Two real limitations remain, neither of which currently inflates FCS ratings:**
  1. FCS teams' SR comes only from their FBS games, because there is no FCS-vs-FCS play-by-play (Stage 0).
  2. The SR-to-points scale β is estimated on FBS-vs-FBS games. In mismatches, SR implies FBS margins about 25% larger
     than the points do. If SR rows were weighted more heavily or used to anchor the FCS level, that mismatch would
     matter.

## 8. What this means for the next stages

- **The FCS level problem remains unexplained by garbage time** after Stage 2: 10.7 points in development and 11.3 in
  2023–25. It is the Stage 1 level/anchor problem, unchanged.
- **Hold the SR instrument at A for Stage 3 and Stage 4,** so those comparisons change one thing at a time.
- **Whether a future predeclared round adopts B** (fidelity to the published rule) **or A0** (simplicity) is a free
  choice on this evidence. Neither has a measurable accuracy cost or benefit.
- **If a Stage 3 variant uses SR to anchor the FCS level,** the FBS-vs-FBS-calibrated β does not transfer 1:1 to
  mismatches (§7). That would need its own check.

## Sources

- Connelly, "Fun with game states in college football," Football Study Hall, 20 Oct 2017:
  https://www.footballstudyhall.com/2017/10/20/16507348/college-football-analytics-game-states (archived capture:
  https://web.archive.org/web/20181230110853/https://www.footballstudyhall.com/2017/10/20/16507348/college-football-analytics-game-states)
- Football Outsiders, 2018 College Football Offensive S&P+ Ratings (archived capture of 10 May 2020):
  https://web.archive.org/web/20200510225948/https://www.footballoutsiders.com/stats/ncaa/sp/overalloff/2018
- Bill Connelly (@ESPN_BillC), 3 Sep 2019: https://x.com/ESPN_BillC/status/1168948789052346368 (archived capture:
  https://web.archive.org/web/20190913073905/https://twitter.com/ESPN_BillC/status/1168948789052346368)
- Daily Nebraskan, 26 Oct 2020 (secondary, not used):
  https://www.dailynebraskan.com/sports/herz-52-17-loss-hides-strides-made-by-the-husker-offensive-line/article_66076256-1730-11eb-b90e-abfa71c218c3.html
