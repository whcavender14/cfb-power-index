# Current model methodology: `v5 / EB_features`

This document describes exactly what the production model computes. Everything here was checked against the code in `R/model/cfb_power_ratings_vCurrent.R` (the engine) and `R/model/production_operations.R` (the operations layer), and against the frozen design `data/frozen/outputs/round4/design_frozen.rds`.

- **Selected:** Round 4. Selection used outcomes through 2022 only.
- **Frozen:** 2026-09-09 14:15.
- **Status:** production incumbent. Nothing since has beaten it under the project's promotion rules.

> **Correction to the old public README.** That README describes a "90% prior / 10% data → 20% / 80%" blend table with a tuned handoff rate. That is the **Round 3 "B" model**, not the production model. `EB_features` has **no blend weights and no handoff parameter**. It solves one penalized regression where the preseason prior is the ridge target (§4). The `k` values stored in the design are unused comparator diagnostics.

---

## 1. What the model produces

For each FBS team at an information cutoff (a Monday 00:00 UTC), the model produces:

| Output | Meaning |
|---|---|
| `off_rating` (O) | Points the team's offense scores above an average FBS offense against an average defense |
| `def_rating` (D) | Points the team's defense **allows** above average. **Lower is better.** |
| `power_rating` (P) | `P = O − D`: points better than an average FBS team on a neutral field |
| `pre_power` | Preseason prior power, before any current-season game |
| `prior_contribution`, `current_contribution`, `centering_contribution` | Exact additive decomposition of P (§4.4) |

**Game prediction:**

```
predicted home margin = P_home − P_away + HFA × (not neutral)       HFA = 3.0685 points
```

A team has one rating at a cutoff, regardless of its opponent. The model predicts margins only. It does not predict totals, and there is no separate win-probability model; the simulation turns margins into outcomes (§7).

---

## 2. Data flow

```
data/frozen/cfb_data_v3/raw_schedule_YYYY.rds  (2015-2026, CFBD game info)
        │  read_schedule(): alias columns, validate, derive kickoff/period/available_at/final
        ▼
schedules 2015-2025 ──► v4_history(): end-of-season score ratings + HFA per season  (§3)
                                   │
data/frozen/cfb_data_v2/{talent,returning,coaches,portal}.rds
        │  v5_ingest() (run once at freeze) ──► data/frozen/outputs/round4/features.rds
        ▼                                   │
        v5_validate_features() ◄────────────┘   provenance/leakage screen
                                   │
                                   ▼
                    v5_prior(): preseason O/D prior per team  (§4.1-4.2)
                                   │
2026 schedule (frozen or live) ──► team_games(): FBS-vs-FBS results with available_at < cutoff
                                   │
                                   ▼
                    v4_score_fit(): joint ridge solve shrunk toward s × prior  (§4.3)
                                   │
                                   ▼
                    ratings (O, D, P, decomposition) ──► predictions, simulation, JSON
```

---

## 3. Data handling and time discipline

### 3.1 Schedules (`read_schedule`)

- **Source:** CollegeFootballData (CFBD) game info via `cfbfastR::cfbd_game_info()`, regular season and postseason. Without an API key the code falls back to `cfbfastR::load_cfb_schedules()`.
- **Column normalization:** provider aliases are mapped to one set of names (`id` → `game_id`, `home_classification` → `home_division`, and so on).
- **The code stops rather than guessing** when it finds:
  - a duplicate `game_id`;
  - an unknown kickoff time or unknown neutral-site flag;
  - an unknown division;
  - a wrong season.
- **Derived fields:**
  - `kickoff`: UTC.
  - `period`: the Monday that starts the game's calendar week. This replaces provider week numbers.
  - `available_at = kickoff + 24 h`: an assumed rule for when a result is "known".
  - `final`: both scores are present and `completed` is true.
- **FBS membership** comes from the per-game `home_division`/`away_division`. It is season-specific; the code never uses current membership for past seasons.

### 3.2 Cutoffs and leakage rules

- **Information cutoff:** Monday 00:00 UTC. It is set by `period_start()`.
- **Training rows:** a game enters the current-season fit only if `available_at < cutoff`.
- **Walk-forward validation:** each week's games are predicted from games available before that Monday.
- **Fold audit:** `audit_fold()` asserts four things:
  - no target game appears in training;
  - all training results were available before the cutoff;
  - every test game kicks off at or after the cutoff;
  - the preseason model was trained only on earlier seasons.
- **2020** is never used as a response or calibration season. Its completed scores do feed 2021's "previous season" inputs.
- **2015** is a burn-in year: it has no previous-season inputs.
- **Market data:** market columns are prohibited in every model input by `v5_no_market()`.

### 3.3 FCS games

The production solve uses **FBS-vs-FBS games only**. `team_games(g, ids, fcs_weight = 0)` drops every game involving an FCS team, so FCS results never affect ratings. (The simulation still plays those games; see §7.)

---

## 4. The rating model

### 4.1 Historical score ratings (inputs to next season's prior)

For every season from 2015 to 2025, `v4_history()` does two things:

1. **Estimates a season HFA.** It fits the joint score regression with ridge penalty 1. The HFA term has its own weak penalty (10) pulling it toward 3 points.
2. **Refits the season's ratings.** It refits with that HFA fixed, again at penalty 1, which gives the end-of-season `eff_off` and `eff_def` for every FBS team, plus an approximate variance.

The median of those per-season HFAs (seasons ≤ 2022) is used only for an auxiliary penalty-1 fit of the current season. That fit feeds games-played counts, the schedule-graph diagnostics and the rarely used B fallback. The EB solve itself uses the prediction HFA H = 3.0685 (§4.3).

### 4.2 Preseason prior (`v5_prior`, feature family `full`)

The prior is built in two steps. Offense and defense each get their own prior.

**Step 1: base prior (`v4_pre`).** Two OLS fits predict a team's end-of-season `eff_off` and `eff_def` from:

- `prev_off` and `prev_def`: last season's end-of-season ratings;
- `promoted`: 1 if the team has no previous FBS rating.

Details:

- Missing previous values are imputed with the training median, and each gets a missingness indicator.
- Constant or collinear columns are dropped after a QR rank check.
- The training rows are team-seasons from 2016 to min(target − 1, 2022), excluding 2020.

**Step 2: feature ridge by coverage regime.** Each side has its own external features:

- **Offense:** `off_returning`
- **Defense:** `def_returning`
- **Both sides:** `log1p(talent_composite)`, `blue_chip_ratio`, `log1p(n_recruits)`, `log1p(coach tenure)`, `new_coach`

The fitting procedure:

- Each team is assigned a **regime**: the exact subset of those features that is non-missing for that team.
- For each side and each regime, the model fits ridge regression on the earlier team-seasons that share that complete subset. The terms are `prev_off`, `prev_def`, `promoted` and the regime's features.
  - Features are standardized with training-fold means and SDs.
  - The intercept is not penalized.
- **Ridge λ** is chosen from {0.1, 1, 10, 100} by forward-chaining cross-validation on team-season MSE. Ties go to the larger λ.
- **Fallback:** a regime with fewer than 80 training rows is skipped. Teams in it keep the Step 1 base prior.
- **Missing features are never zero-filled.** A missing feature changes the team's regime; it is not imputed.
- If any feature fit was used, the offense and defense priors are re-centered across FBS teams, and `pre_power = pre_off − pre_def`.

**For 2026, every FBS team uses a feature regime.** There are two regimes per side: with talent and without talent. The cross-validation picked **λ = 0.1 for all of them, the lowest value in the grid**. This is a grid-edge selection, and the grid was never extended. It hints that the feature regressions want less shrinkage than the grid allows. That is worth testing in V2.

Portal data are ingested and audited but **not used**: there was too little forward history. QB continuity is **unknown**, and no QB feature exists.

### 4.3 The empirical-Bayes joint solve (the core)

**The regression.** Each completed FBS-vs-FBS game creates two team-game rows, one per team:

```
points_for(team i vs opponent j) = μ + o_i + d_j + H × hx        hx = +½ home, −½ away, 0 neutral
```

**The objective.** With the preseason prior as the ridge target, the model minimizes:

```
Σ_rows (PF − μ − o_i − d_j − H·hx)²  +  λ Σ_i [ (o_i − s·pre_off_i)² + (d_i − s·pre_def_i)² ]
```

The frozen values are:

| Symbol | Meaning | Frozen value |
|---|---|---|
| λ | prior precision | **4** |
| s | preseason scale | **1.12271478057756** |
| H | prediction HFA | **3.06853968902663** |

- **How s and H were fit:** by least absolute deviation (LAD) on earlier, forward (out-of-time) game margins, using seasons ≤ 2022.
- **Solver:** this is a sparse linear system. It is solved exactly in closed form (`Matrix::solve`), with no iterative optimizer.
- **Centering:** `o` and `d` are centered over FBS teams, and `P = O − D`.

**How to read λ = 4.** Suppose the opponents and the intercept were known. Then a team with *n* games would put roughly `n/(n+4)` weight on this season's data and `4/(n+4)` on its prior. This is only an illustration: the real weights come from the full matrix and depend on the schedule graph. Opponent information also flows between teams, so a game against a well-measured opponent teaches more.

**What happens at the edges.**

- **Zero games played** (league-wide): the solution is exactly the centered, scaled prior.
- **After one game:** the coupled system updates the team, its opponent and, indirectly, everyone connected to them.

**Graceful fallback.** If no external feature is usable for a snapshot, `v5_ratings()` falls back to the fully validated Round 3 "B" model (a convex prior/current blend, `k = 2.42`, `s = 0.90`). This never triggers for 2026: its features are present.

### 4.4 Exact contribution decomposition

The solve is linear in its right-hand side, so the code re-solves with the prior set to zero:

- `current_contribution` = power from the zero-prior solve (the data alone, still under shrinkage);
- `prior_contribution` = full power − zero-prior power;
- `centering_contribution` ≈ 0.

`P = prior + current + centering` is asserted to 1e-7.

### 4.5 HFA

- **Structure:** one global constant, the same for every team, with no team-specific terms.
  - A team-specific HFA was tested and rejected (`archive_reference/round_reports/side_team_HFA_REPORT.md`).
- **Value:** the prediction HFA is 3.0685. It was estimated jointly with the prior scale by LAD on the walk-forward predictions for 2018, 2019, 2021 and 2022, the earlier-only calibration used for the freeze. The same H is used inside the solve and in predictions, so it is never added twice.
- **Neutral sites** get zero HFA.
- **Stability over time:** the strength-adjusted HFA was about 2.6–3.0 in Rounds 9–10, and realized residual HFA was 2.19, 2.95 and 3.08 in 2023, 2024 and 2025. A static value is a known limitation (see MIGRATION_AUDIT_REPORT, "What you need to know").

---

## 5. Frozen design and reproducibility controls

`design_frozen.rds` (MD5 `0f876d73…`) stores:

- the selected candidate;
- all 12 Round 4 candidate specs with their fitted parameters, including the fallback;
- `max_selection_year = 2022`;
- the feature-bundle hash;
- source manifests.

At every build:

- **`v5_frozen()`** checks the MD5 of all 16 source files: 12 schedules and 4 feature caches.
- **`v5_frozen_features()`** checks the MD5 of `features.rds` (`f1801389…`).
- **`v5_build()`** asserts that the feature bundle's hash equals the design's.

`scripts/verify_frozen_inputs.R` runs all of these checks. `tests/test_reproduce_incumbent.R` shows that the week-1 production snapshot built by GitHub Actions with the old code is reproduced **exactly** (difference 0).

**The design's code manifest check is disabled** in production, and was already disabled in the old folder. It recorded an MD5 for `cfb_power_ratings_v5.R` taken before v4 was inlined into v5. The code is identical once comments and whitespace are removed, but the bytes differ.

The frozen design supports **2015–2026 only**:

- the feature bundle and frozen schedules end at 2026;
- `v5_build` validates features against the 2015–2026 schedules;
- the entrypoints assert `season == 2026`.

Rating 2027 needs a new feature pull, a new `features.rds` and a new design freeze. See the audit report.

---

## 6. Weekly operation

1. `scripts/01_build_ratings.R`:
   - With `CFB_REFRESH_SCHEDULE=true`, it pulls the live 2026 schedule and results. The frozen 2026 schedule stops at 2026-09-09.
   - It builds the ratings at the current Monday cutoff.
   - It writes the rankings CSV and the weekly snapshot `production_ratings_2026_wkNN.rds`.
2. `scripts/02_simulate_season.R`: simulation (§7).
3. `scripts/03_export_public_data.R`: JSON files per `docs/DATA_CONTRACT.md`.
4. `scripts/04_archive_prospective_snapshot.R`: write-once pre-kickoff predictions. **This step is manual; nothing automates it** (see EVALUATION_PROTOCOL.md).

The live site still runs from the **old** repository's GitHub Actions workflow. That workflow runs every Monday at 09:00 UTC, August through January. Nothing in this folder is deployed.

---

## 7. Season simulation

`R/simulation/simulate_season.R` wraps `cfbseedR`, pinned at SHA `4a1c78e1…` in CI; version 0.2.0 is installed locally.

**Inputs**

- **Ratings:** every FBS team gets its current power rating. **Ratings stay fixed within a simulated season.**
- **FCS opponents:** all get power −25. This is an assumption, not an estimate.

**Game model**

- Each unplayed game's margin is drawn as `Normal(P_home − P_away + 3.0685·(not neutral), sd = 15.787)`. It is rounded, and ties are forbidden.
  - `sd = 15.787` is the conditional 2023–25 RMSE of EB_features.
- **Played games:** final games before the cutoff keep their real results.
- **Data check:** too many unresolved pre-cutoff games (more than max(3, 5%)) makes the run fail loudly. The pipeline then publishes an explicit "unavailable" simulation state.

**Playoff**

- `cfbseedR` simulates the regular season, including conference championship games.
- `cfb_dynamic_cfp_ranking()` ranks the eligible FBS teams **separately in every simulation** by a resume score:
  - `1.989 × WAB + 0.149 × adjusted margin + 1.792 × conference champion`;
  - **WAB** (wins above benchmark) = wins minus the wins the 60th-best FBS team would expect against the same schedule, using the game model's win probabilities. Opponent strength is national (power ratings, FCS = −25), so a loss to a strong team costs little and a win over a weak team earns little;
  - **adjusted margin** = mean of (margin capped at ±35 + opponent power − home-field adjustment);
  - title games are left out of WAB and adjusted margin; they count through the champion term.
- The coefficients are a rank-ordered logit fitted to the committee's final top 25, 2018–2025 excluding 2020 (`scripts/calibrate_cfp_ranking.R`). Held out by season, the score matches 10.9 of the committee's top 12 on average. cfbseedR's default win-%-first order matches 8.4, and on those real seasons it would have put 3.4 G6 teams in the top 12 per year against the committee's 0.4.
- `cfb_dynamic_playoff_seeds()` hands each simulation's ranking to cfbseedR, which applies the 2026 automatic-bid rules: P4 champions, the highest-ranked G6 team, and Notre Dame if ranked in the top 12. There is no G6 cap and no conference-specific adjustment.
- FBS only; teams listed in `PRODUCTION$cfp_ineligible_teams` are excluded from selection, but their games still count.
- The bracket is then simulated.
- **The CFP field is not chosen by power rating.** A team's own rating never enters its ranking; ratings only measure opponent strength.
- `scripts/diagnose_cfp_selection.R` prints expected bids by conference, the number of G6 teams per field, and the ranking around the cut line.

**Run settings and output**

- 1,000 simulations, seed 1434.
- Output: mean wins (including conference title games), conference-title probability, playoff probability, #1-seed probability and national-title probability per team.

---

## 8. Assumptions and known limitations (summary)

| Assumption | Consequence |
|---|---|
| Score margins only; no play-by-play, injuries, weather, QB or motivation | Information the market has and the model lacks. This is the likely source of the ~0.5 MAE market gap. |
| Constant λ = 4 for all teams and both units | Early-season compression persists: held-out slopes are above 1 in weeks 2–4. |
| One global HFA fixed at 3.07 | Cannot follow HFA drift across seasons. |
| FCS games ignored | Loses information for about 80 of 138 teams each September. |
| Features are "historical vintage unverified" | Historical talent/returning values may include later revisions. |
| No tier or conference term | The P4-vs-G5 bias is +3.4 (2023–25) to +5.6 (2019–22) points. Positive means the model underrates the P4 side. |
| Normal, static-rating simulation | Ignores rating uncertainty, so season-outcome spreads are too narrow. |
| Frozen 2026-only design | Cannot run 2027 without a new ingest and freeze. |

Evidence for each item is in `docs/MODEL_HISTORY.md` and `docs/EVALUATION_PROTOCOL.md`.
