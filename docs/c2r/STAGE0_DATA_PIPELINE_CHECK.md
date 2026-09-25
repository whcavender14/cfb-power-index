# C2 Refinement Research: Stage 0, Data and Pipeline Check

**Date:** 2026-09-25. **Branch:** `c2-refinement`, from `d6fd3d3` (tag `round15-scored`). **Status:** read-only check.
No model was changed, refit, tuned or scored. Probes are in `scripts/c2r/s0_*.R`.

> **Governance.** Nothing in this research phase is pre-validated. Any numeric choice it reaches, such as an FCS
> constant, a garbage-time rule or a decay half-life, is a development-period choice. Before any of it could be formally
> scored, it would need its own predeclaration and frozen construction.

## Summary

| Question | Answer |
|---|---|
| PBP has quarter, score margin and clock? | **Yes.** `period`, `clock_minutes`, `clock_seconds`, `offense_score`, `defense_score` are all present, with 0% missing in every season from 2014 to 2025. |
| Same PBP source as C2's success rate? | **Yes.** One file set, `plays_{y}.rds` from the Round 6 CFBD pull, feeds success rate (SR), fumble luck and the passer parser. |
| SR aggregation level | **Per play → per game × offense mean.** Each team-game gives one SR row in the joint ridge. A garbage-time change can therefore be done exactly: re-filter the raw plays and recompute the game means. |
| **Is garbage time already filtered?** | **Yes. This changes Stage 2.** C2 already drops plays when the pre-snap margin is above 38 in Q2, above 28 in Q3 or above 22 in Q4. Q1 is never filtered, and overtime is always dropped. |
| FCS code path | Confirmed in code (§5). Four structural facts matter for Stage 1 (§6). |

## 1. Play-by-play fields and coverage

- **Source.** `~/Desktop/CFB Modeling Backup/CFB-Modeling-round6/outputs/round6/raw/plays_{2013..2025}.rds`, pulled
  from the CFBD `/plays` endpoint. Each file has 31 columns.
- **Fields relevant here:**
  - `period`, `clock_minutes`, `clock_seconds`, `wallclock`;
  - `offense_score`, `defense_score`, `home`, `away`, `offense`, `defense`;
  - `down`, `distance`, `yards_to_goal`, `yards_gained`, `play_type`, `play_text`;
  - `drive_number`, `play_number`.
- **Vendor columns.** The vendor `ppa` column is dropped when the file is read.
- **Missing values.** In weighted play counts, `clock_*`, `offense_score`/`defense_score` and `period` are 0% missing in
  every season.
- **Pre-snap margin.** It is **reconstructed**, not read directly. `r13_states` treats `offense_score`/`defense_score`
  as post-play values. It rebuilds a running scoreboard and shifts it one play back.
- **Dropped games.** A game is dropped from SR entirely (`bad_game`) when:
  - the rebuilt scoreboard does not end at the final score; or
  - the game has duplicate plays, invalid teams, or impossible scoring jumps.

| Game type | Games per season | With plays | With SR rows | Play rows per season |
|---|---|---|---|---|
| FBS vs FBS | 760–808 | 98–100% | 92–99% (2021–25: 92–96%, mostly failed scoreboard rebuilds) | ≈139–144k |
| FBS vs FCS | 98–126 | 97–100% | 88–100% | ≈17–22k |
| FCS vs FCS | 666–753 | **0%** | **0%** | 0 |

**The raw PBP files contain no FCS-vs-FCS games.** The schedule builder only requested FBS-involved games. As a result:
- An FCS team's SR comes only from its FBS games. The average FCS team plays 0.59–0.70 of those per season.
- An FCS team's fumble luck is 0 in FCS-vs-FCS games.

These fields are enough to apply any definition based on quarter and margin exactly. This includes every SP+ variant I
am aware of. Checking the published source is Stage 2 work.

## 2. How C2's success rate is aggregated

C2 uses the Round 13 SR instrument, vendored byte-for-byte in `R/forward/vendor/round13_sr_stack.R`, with the P2
fumble parser. It runs in five steps:

1. **Eligibility** (`r13_eligible`): scrimmage plays only.
   - Excluded: kneels, spikes, penalties, no-plays, punts, kicks and field goals.
   - Excluded: ambiguous play types, invalid down/distance, and incomplete states.
   - Excluded: the garbage/overtime rule.
2. **Success:** gain ≥ 50% of the distance on 1st down, ≥ 70% on 2nd, and 100% on 3rd and 4th.
3. **Game means** (`r13_game_means`): mean success per (game, offense, defense). Each game-offense gets one row, whatever
   its play count.
4. **The C2 solve** (`r15_sr_rows`, `r15_solve2`):
   - Each game-offense SR row enters the same ridge as the points rows as `y = SR / β`, at weight ω. It has its own
     unpenalized intercept.
   - β is pooled OLS of game SR on end-of-season (o_A + d_B), fit on FBS-vs-FBS training rows only. β ≈ 0.0053 SR per point, so
     1 SR percentage point ≈ 1.9 scoring points.
   - The selected ω is 0.5 for 2017 and 0.25 afterwards.
5. **The same instrument also builds:**
   - the prior input `last_sr_off/def` (end-of-season opponent-adjusted SR of y−1, FBS and FCS plays);
   - β's training rows.

**What a garbage-time change would touch.** Changing the filter means re-running `r15_sr_season` from the raw plays.
That would change:
- (a) in-season SR rows;
- (b) β;
- (c) `last_sr` and therefore C1's prior coefficients, **unless the experiment deliberately holds the prior fixed.**

The points rows (final scores) and fumble-luck counts, which use all plays, are **not** filtered today.

## 3. The existing garbage-time filter

`R13$garbage = c(Inf, 38, 28, 22)`. A play is dropped when `abs(pre-snap margin) > threshold[period]`, and overtime is
always dropped.

- **Provenance.** The thresholds came from the archived vNext-EPA predeclaration ("garbage cutoffs >38 Q2, >28 Q3, >22
  Q4"). They passed through Round 13 and into Round 15, which reused the instrument frozen (predeclaration v3 §4.1, §9
  item 6). **No source is cited anywhere I found.** I have not yet checked them against any published Connelly
  definition.
- **Boundaries.** Whatever the published wording ("more than" vs "at least", and whether Q1 has a threshold) turns out
  to be, it will need to be matched exactly.

**Share of all play rows dropped as "garbage_or_overtime"** (sample seasons):

| Season | FBS vs FBS | FBS vs FCS |
|---|---|---|
| 2017 | 6.2% | 14.0% |
| 2019 | 6.7% | 15.4% |
| 2022 | 5.1% | 14.7% |
| 2024 | 5.2% | 14.4% |

As expected, FBS-vs-FCS games lose about 2.5× as many plays. These shares are of all play rows, not of scrimmage plays.
Stage 2 will report both.

### Consequence for Stage 2 (your decision)

The brief defines Treatment A as "current C2, all plays as-is", but current C2 is not unfiltered. I propose these
treatments instead:

- **A0: no garbage filter.** All eligible scrimmage plays; overtime is still dropped, as SP+ does.
- **A: current frozen C2.** The R13 thresholds above.
- **B: the published SP+ definition,** checked against a dated source. If it matches A exactly, B = A. Stage 2 then
  answers "does the filter matter, and in which direction for FCS" by comparing A0 with A, plus an optional
  down-weighting variant.
- **Round 15's −10.5 FCS bias** was produced **with** the filter on. So garbage time can only explain it if the current
  filter is too loose, or if the leak is through a channel the filter doesn't touch. Stage 1's decomposition will show
  which.

## 4. How the incumbent handles FCS

- **Game prediction.** The incumbent never rates FCS teams. `v4_score_fit` uses FBS-vs-FBS points rows only.
- **The −25 constant** comes from production simulation: `config/production.R` `sim_fcs_power = -25`, used in
  `R/simulation/simulate_season.R`. The Round 15 predeclaration (§7.2) adopted it for the incumbent in the FBS-vs-FCS
  slice, and the scorer also applied it to C1.
- **Earlier research.** An archived experiment, `fcs-inclusion` (legacy registry), put FCS games in the solve at weight
  0.25/0.5/1. It was "positive but small; not promoted."

## 5. How C2 rates FCS teams (confirmed in code)

| Element | Implementation (`R/round15/candidates/c2.R`) |
|---|---|
| **Entities** | Every non-FBS team with a final game before the cutoff: `setdiff(teams, fbs_ids) ∩ teams with rows`. This includes FCS teams' D-II, D-III and unknown-division opponents (§6c). |
| **Data** | All final games (FBS-FBS, FBS-FCS, FCS-FCS, FCS vs lower division) enter the points channel at weight 1. SR rows exist only for FBS-involved games. Fumble luck is 0 where there is no PBP. |
| **Prior mean** | `μ + ρ·(last_eos − μ)` per side. `last_eos` is team z−1 from `r15_eos_full`: a one-season ridge over all FBS and non-FBS teams, points only, penalty 1, season HFA, **centered on the FBS mean**. Teams without a z−1 rating get μ. |
| **FCS moments** | μ, ρ and v come from training seasons' `r15_eos_full` fits over **all non-FBS entities**. μ_power = μ_off − μ_def ≈ **−18.2** in every season; ρ ≈ 0.61–0.64; v ≈ 33–35 per side. |
| **Prior precision** | λ_FCS = λ0·v̄_FBS / v_FCS ≈ **2.5–3.4 per side**. The FBS λ0 is 3–4 and is team-specific through the turnover index. FCS teams get no regime or turnover adjustment. |
| **Link to the FBS scale** | One joint ridge with a shared intercept and shared HFA H(z), FBS HFA applied to FCS games. Ratings are centered on the **FBS mean only**. The only direct link between the FBS and FCS blocks is the ≈100–125 FBS-vs-FCS games per season. |
| **Output** | `r15_solve2` returns FBS ratings only. The frozen C2 prediction file contains **FBS-vs-FBS games only**, because the base frame has no FCS games. Production C2 has **no code path that outputs an FBS-vs-FCS prediction.** |

## 6. Structural facts Stage 1 must account for

These are observations from the code and data. They are **leads, not diagnoses**: none has been tested for its effect
on the bias.

**a. The Round 15 FBS-vs-FCS numbers are a reconstruction.**
- They are not frozen C2 output. E1 rebuilt them from the E0 rating replay: FBS rating − FCS rating + H.
- The report labels them descriptive, and they never entered a gate.
- The replay reproduced every FBS prediction to 5.7e-14, so the FCS ratings are C2's own. But the "C2 FBS-vs-FCS
  prediction" formula is the scorer's, not a frozen spec.

**b. The slice excludes the FCS team's first game.**
- C2 has no rating for an FCS team that has not yet played, because it is not yet an entity.
- In development: 561 FBS-vs-FCS games, 207 with the FCS team on 0 games played, 335 in the slice.
- 2023–25: 365 games, 141 at 0 games played, 212 in the slice.
- So the −10.5 / −11.3 biases describe FCS teams that have already played, which is **mostly FCS-vs-FCS evidence**.
- A future C2 spec needs a defined rule for the gp-0 FCS game. The obvious one is the prior mean.

**c. The FCS pool includes lower-division teams.** Across the 2014–22 end-of-season fits:

| Division | Entities | Mean power |
|---|---|---|
| FCS | 1,029 | −14.6 |
| D-II | 264 | −24.7 |
| D-III | 24 | −30.8 |
| Unknown | 110 | −34.0 |

- About 28% of the pool that sets μ_FCS is not FCS.
- These teams also enter C2's in-season solve as "FCS" entities under the FCS prior (μ_FCS, ρ_FCS, λ_FCS).

**d. The FCS block is anchored by very few games.**
- About 170 FCS entities play about 700 FCS-vs-FCS games, but only about 110 games per season link them to FBS.
- Ridge penalties on every FCS parameter act together on the block's overall level, pulling it toward the FBS-centered
  prior or toward 0.
- **Lead for Stage 1:** measure how much the block level is shrunk, compared with the level the FBS-vs-FCS results
  alone imply. The end-of-season FCS mean of about −14.6 against the incumbent's well-calibrated −25 suggests this may
  be where much of the 10 points enters.

**e. No FCS-vs-FCS PBP.** An FCS team's SR rows come only from the FBS games it has already played, which are
blowout-heavy. That is the same subset the garbage filter trims most.

## 7. Stage 1 plan (for your approval; not started)

Diagnosis only, with no fix:

1. **Decompose the prediction.** Split each predicted FBS-vs-FCS margin into:
   - FBS rating;
   - FCS prior mean (μ and ρ·last);
   - in-season update, split into points channel, SR channel and luck;
   - HFA.

   Rebuild each FCS rating under the frozen parameters with one channel switched off at a time. These are
   counterfactual ablations for diagnosis, not candidates.
2. **Measure the block-level shrinkage.** Compare the FCS block level against a level estimated from FBS-vs-FCS games
   alone.
3. **Check μ_FCS for lower-division contamination.**
4. **Cut the bias by:**
   - season, week and games played;
   - FCS and FBS strength;
   - home, away and neutral;
   - predicted-margin size;
   - FCS team's FBS games played to date.
5. **Report the gp-0 FCS games separately.**
6. **Pre-snap margins.** Report the distribution for FBS-vs-FCS against FBS-vs-FBS, as flagged input for Stage 2 (no
   fix).

Stage 1 would read the development seasons' FBS-vs-FCS games, which Round 15 has already scored descriptively. The
2023–25 slice would be reported alongside, as Round 15 did.
