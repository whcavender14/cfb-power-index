# Round 15 predeclaration — DRAFT for user sign-off

**Status: DRAFT. Not hashed, not in force.** No candidate has been built or run, and no Round 15 outcome has been read.
After your sign-off this file is hashed (SHA-256 into `predeclaration.sha256`) and becomes binding. From then on, any change
is a dated amendment made before the affected step runs, never after its results.

Inputs to this draft:
- `ROUND15_DESIGN.md` (design);
- `DECISIONS.md` (your decisions);
- `docs/round15/coverage/` and `docs/round15/replay/` (read-only probes);
- `docs/forward/FORWARD_SNAPSHOTS.md` (forward evidence).

---

## 1. Objectives and the three-part scorecard

Round 15 asks one question: **do increasingly rich information sets measure underlying team strength better than the
incumbent?** Three nested candidates answer it layer by layer. Every model is judged on three separate objectives, which
are never merged into a single number:

| Part | Question | Metrics (§7) |
|---|---|---|
| **A. Power rating** | Does the rating order teams by strength with calibrated separation? | **Winner log-loss (primary)**, Brier (secondary, tie-break), calibration slope overall and by stage, rating spread, tier separation, stability and update efficiency |
| **B. Game prediction** | Does it predict game margins and winners? | MAE (guardrail), RMSE, bias, margin calibration, winner %, predicted-margin distribution; by season, games played and tier/conference slices |
| **C. Market value** | Does it contain information the betting market lacks? | Three distinct tests (§7.3): outcome prediction relative to the market, prediction of market movement, and beating the spread |

The model never sees market data (§4.4). Market metrics are computed only after predictions are frozen and hashed.

## 2. Samples and splits

| Split | Seasons | FBS-vs-FBS games | Use | Status |
|---|---|---|---|---|
| History | 2013–2016 (2013 schedule only) | — | Prior training, calibration, channel parameters | Inputs only; never scored |
| **Development** | **2017, 2018, 2019, 2021, 2022** | **3,868** (776/772/774/770/776) | Gates G1–G2; nested-layer comparisons | Used for selection in earlier rounds (2018–2022); 2017 newly scored |
| Development, Round 13 K subset | 2018, 2019, 2021, 2022 | 3,092 | All comparisons against K | K is not defined for 2017, since its frozen predictions start at 2018 |
| Conditional | 2023, 2024, 2025 | 2,398 | Non-degradation gate G3 only | **Burned**: examined in Rounds 4–14. Contaminated, descriptive |
| Forward | 2026 games kicking off after the Round 15 freeze, plus all of 2027 | ~1,300 expected | Forward checks F1–F3 (§9) | **Pristine**. The only clean evidence |

- **2020** is never a target or a response season. Its results feed only "previous season" inputs for 2021, as in the incumbent.
- **Incumbent development predictions** are the replay of v5 EB_features with history from 2013. It reproduces Round 6's
  replay exactly for all five folds (max |Δ| 5×10⁻¹⁴) and equals Round 13's development incumbent for 2018–2022 (see `docs/round15/replay/`).
- **2017 limitation:** it has the thinnest history. Its prior trains on 2014–2016, and its scale and HFA are calibrated on
  2016 alone. Its fold HFA of 3.94 is the highest of any fold; the others run 3.28–3.48.
  - **Why 2017 still qualifies:** every fold uses the same code and the same rules; 2018 has the same structure with one more season.
  - **How 2017 is handled:** it is kept, and per-season results show it separately.

## 3. Comparators

- **Incumbent (I).** v5 EB_features, the frozen production model.
  - Development: its walk-forward replay with history from 2013 (§2).
  - 2023–2025: its frozen production predictions (`data/reference/incumbent_predictions/eb_features_conditional_predictions.csv`),
    identical game for game to Round 13's conditional incumbent. That file uses the production history (from 2015); the
    development replay uses history from 2013. Round 13 had the same asymmetry.
- **Frozen Round 13 K.** `incumbent + w·SRnet`, with predictions from the frozen files (hashes in `docs/round13/freeze_manifest.csv`). It is never refit.
- Every table shows Δ vs I, Δ vs K (on K's games) and K vs I.

---

## 4. Inputs (exact definitions)

Notation: target season *y*; team *i*; weekly information cutoff *t* (Monday 00:00 UTC).

### 4.1 Preseason inputs (all known before season *y* starts)

| Input | Definition | Source | Knowledge date |
|---|---|---|---|
| `last_off`, `last_def` | End-of-season score ratings of *y*−1: the incumbent's `v4_history` fit (joint points ridge, penalty 1, own-season HFA, FBS-vs-FBS) | Our results | January of *y* |
| `two_off`, `two_def` | Same for *y*−2; missing for teams not in FBS in *y*−2 | Our results | January of *y*−1 |
| `last_sr_off`, `last_sr_def` | End-of-season opponent-adjusted success rate of *y*−1. Round 13 instrument: eligible plays, R13 garbage filter, FBS+FCS plays, ridge λ 0.5/0.5, **no decay**, all games | Our play-by-play | January of *y* |
| `cont_pass` | Share of *y*−1 pass attempts (team total) thrown by players on team *i*'s *y* roster, excluding players drafted in April *y* | CFBD player stats + roster + draft | Stats January; draft April; roster (vintage unknown, §4.3) |
| `cont_skill` | Same share for *y*−1 rushing yards + receiving yards | Same | Same |
| `cont_def` | Same share for *y*−1 total tackles | CFBD defensive stats (2016+) | Same; missing for *y* ≤ 2016 |
| Transfers (structural) | Players on the *y* roster who produced at **another** FBS team in *y*−1 add that production to the numerator of `cont_*`. Denominator is team *i*'s own *y*−1 total. Each `cont_*` is capped at 1.5 | Roster IDs + stats | As above |
| `qb_xfer_in` | 1 if the *y* roster includes a player with ≥ 100 pass attempts at a different FBS team in *y*−1 | Roster IDs + stats | As above |
| `talent4` | Mean of 247 team recruiting-class points for classes *y*−3 … *y* (≥ 2 classes required), standardized within season | CFBD `/recruiting/teams` | Signing day (Feb) of each class |
| `bluechip4` | Share of 4- and 5-star signees among the team's recruits in classes *y*−3 … *y* | CFBD `/recruiting/players` | Same |
| `new_hc`, `log_tenure` | Incumbent definitions: *y*'s head coach hired on or after Aug 1 of *y*−1; log1p(years since hire) | CFBD coaches (frozen) | Hire date |
| `conf_off`, `conf_def` | Mean `last_off` / `last_def` of the team's season-*y* conference members, excluding the team | Our results + season-*y* membership | Preseason |
| `promoted` | 1 if the team was not FBS in *y*−1 | Schedules | Preseason |

**Not used anywhere:**
- vendor talent composite (a sensitivity input only, report-only, §7.4);
- CFBD PPA-based returning production (vendor EPA, decision 4);
- polls;
- portal ratings (report-only);
- coordinators (no source);
- any market or vendor rating.

### 4.2 In-season inputs (only games with kickoff + 24 h < *t*)

- **Score rows (all candidates).** Points for, per team-game, with the site indicator. C1 uses FBS-vs-FBS games only, as the
  incumbent does. C2 and C3 add FBS-vs-FCS and FCS-vs-FCS games.
- **Success-rate rows (C2, C3).** Game-level success rate of offense A against defense B, using the Round 13 instrument
  (eligibility, garbage filter and Round 8 fumble recovery), frozen and not retuned. FBS-involved games only.
- **Fumble luck (C2, C3).** From play-by-play: fumbles by each offense and fumbles lost (recovered by the defense).
- **Primary passer per team-game (C3).** From play text: the passer with the most dropbacks, with ≥ 10 dropbacks required.

### 4.3 Data prerequisites (engineering steps with pass/fail rules; no outcomes read)

| # | Step | Pass rule | If it fails |
|---|---|---|---|
| P1 | Pull rushing and receiving player stats 2013–2026, passing 2013, roster 2013, and FCS schedules 2013–2025 (about 45–60 calls; 2,395 left this month) | Every FBS team present in each season. FCS-vs-FCS schedule coverage reported | Stop and report |
| P2 | Extend the fumble parser to the 2025+ text format | 2025 recovery ≥ 90% **and** every 2013–2024 fumble classification unchanged | Use the Round 8 parser and disclose 2025–26 recovery (68%, 38%) |
| P3 | Passer parsing in both text formats | ≥ 97% of dropbacks parsed in every season | C3's QB-shock term is disabled (q_QB = 0) and disclosed |
| P4 | Reconstruction tables (`cont_*`, `qb_xfer_in`, `talent4`, `bluechip4`, conference levels) with unit tests | Tests pass. Coverage reported by season. Defensive continuity agrees with the vendor figure where both exist (r ≥ 0.8) | Stop and report |
| P5 | Market lines, fixed vintage: the 2026-09-25 pull (§7.3) | Probe results already recorded (`coverage/market_line_*`) | — |

**Roster vintage risk.** CFBD rosters have no snapshot date. A roster may include players who arrived mid-season, or may
omit players who left during the season. Roster presence is used only to mean "not departed". A report-only sensitivity
rebuilds continuity from dated departures alone: drafted in April, portal entry before Aug 1 with another destination, or
absent from the *y* roster after a class ≥ 4 season.

### 4.4 Market data isolation

- **Storage.** Market lines are stored only under `output/dev/round15/market*` and read only by `R/round15/market_lines.R`
  and the evaluation scripts.
- **Enforcement.** A test (L4) fails if any file under `R/model/`, `R/round15/candidates/` or `R/forward/` references
  market modules or paths. Trip-wires also reject any market-named or vendor-rating column (spread, odds, Elo, SP+, FPI,
  pregame WP) in every candidate input matrix.

---

## 5. Candidates (exact specifications)

### 5.1 Shared rating model (the incumbent's, unchanged)

- **Strengths.** Each team has offense *o* and defense *d* in points per game against an average FBS team (*d* = points
  allowed above average). Power P = *o* − *d*, centered over FBS teams at every cutoff.
- **Solve.** A score row for team *i* against *j* is `PF = μ + o_i + d_j + H·hx + ε` (hx = +½ home, −½ away, 0 neutral), solved
  by weighted ridge toward the prior (`v4_score_fit`, no margin cap). `P_i` is the team's rating.
- **Prediction.** Predicted home margin `m = P_home − P_away + H·site`. Ratings are in points.
- **H (prediction HFA) is shared with the incumbent.** It is the incumbent fold's walk-forward HFA from `v4_scale` on
  earlier seasons; the frozen 3.0685 is used for 2023+. Candidates therefore differ from the incumbent only in their declared layers.
- **Prior scale a_X.** As in the incumbent, each candidate's prior is multiplied by a fold-specific scale a_X fitted by least
  absolute deviation on earlier seasons' games (`v5_fit_parameters` logic applied to the candidate's own prior).

### 5.2 Candidate 1 (C1): information-rich preseason prior

C1 is the incumbent's in-season solve with a new prior mean, a new team-specific prior precision, and FBS-vs-FBS score rows only.

**Prior mean.** Offense and defense each get a ridge regression.
- **Target:** end-of-season `eff_off` / `eff_def` of season *y* (the `v4_history` rating).
- **Training rows:** FBS team-seasons from 2014 to *y*−1, excluding 2020 as a response.
- **Predictors:**
  - Offense: `last_off, last_def, two_off, two_def, last_sr_off, last_sr_def, cont_pass, cont_skill, cont_pass×last_off,
    cont_skill×last_off, qb_xfer_in, talent4, bluechip4, new_hc, log_tenure, conf_off, promoted`.
  - Defense: the same with `cont_def, cont_def×last_def` in place of the passing and skill terms, `conf_def` in place of
    `conf_off`, and no `qb_xfer_in`.
- **Standardization:** training-fold means and SDs; the intercept is not penalized.
- **Ridge λ:** chosen by forward-chaining CV within the training seasons over {0.01, 0.03, 0.1, 0.3, 1, 3, 10}. Ties go
  to the larger λ; grid-edge picks are disclosed.
- **Missing values** follow the incumbent's regime rule. Each team uses the regression fit on training rows that share its
  exact non-missing predictor set, and a regime needs ≥ 80 rows. Nothing is ever zero-filled. Example: no `cont_def` before
  2017 means those rows fall in the no-`cont_def` regime.
- **Centering:** the prior is centered over FBS teams; `pre_power = pre_off − pre_def`.

**Prior precision** (how turnover enters as uncertainty):
- **Variance regression.** For each side, CV residuals `r` of the prior regression are regressed on the turnover index:
  `log r² = a + b·u_i`. The index `u_i = (1 − cont_skill) + (1 − cont_pass) + new_hc + promoted` for offense; for defense,
  `(1 − cont_def) + new_hc + promoted`. Components missing for a team are set to their training mean in u only.
- **Precision per team:** `λ_i = λ0 · exp(−b·(u_i − ū))`, where ū is the FBS mean in season *y*. A team with more turnover
  gets a weaker pull toward its prior, so its games move it faster. b is estimated, never searched.
- **λ0** comes from inner walk-forward CV over {2, 3, 4, 6, 8, 12} (§6). Ties go to 4, the incumbent's value.

**How each input enters:**

| Input | Prior mean | Prior uncertainty |
|---|---|---|
| Prior team strength (1 and 2 seasons back, scores and SR) | Yes | — |
| Recruiting (`talent4`, `bluechip4`) | Yes | — |
| Returning production (`cont_*`, transfers included) | Yes, and it scales last season's carry-over | Yes |
| QB continuity (`cont_pass`), transfer QB | Yes (offense) | Yes (offense) |
| Coaching change (`new_hc`, tenure) | Yes | Yes |
| Conference strength (`conf_*`) | Yes | — |
| FCS | Not in C1 | — |

**Nesting switch (G0).** With the prior set to the incumbent's `v5_prior`, λ_i ≡ 4 and a_X set to the incumbent's fold
scale, C1 must reproduce the incumbent replay to ≤ 1e-9.

### 5.3 Candidate 2 (C2): C1 + success-rate measurement channel + FCS teams + fumble luck

C2 inherits every C1 parameter unchanged and adds four things:

1. **SR channel.**
   - **Mapping to points.** Each FBS-involved game gives one SR row per offense. It is mapped to points with
     `s′ = (SR_AB − α)/β`, where α and β come from regressing game SR on end-of-season `(o_A + d_B)` in the training seasons.
   - **Weight.** The mapped row enters the same ridge as a score row with weight ω. SR therefore updates the same *o* and
     *d* as scores; it is not a separate rating.
   - **How much SR counts.** ω is chosen from {0, 0.25, 0.5, 1, 2} by inner walk-forward CV (§6); ties go to the smaller ω.
   - **SR's weight against games played is not tuned.** It emerges from accumulated precision. SR adds most when few games
     have been played; Round 13's gp 1–3 finding is not built in.
2. **FCS teams.**
   - All FBS-vs-FCS and FCS-vs-FCS games enter the score channel at full weight. FCS teams become parameters.
   - FCS prior mean: `μ_FCS + ρ_FCS·(last-season FCS rating − μ_FCS)`. Prior precision: `λ_FCS = λ0·v̄_FBS / v_FCS`.
     μ_FCS, ρ_FCS and v_FCS all come from training seasons' end-of-season fits.
   - This replaces the engine's default, which shrinks FCS opponents toward 0, i.e. an average FBS team.
3. **Fumble luck.**
   - For team A in a game: `L_A = (fumbles lost by A − 0.5·fumbles by A) − (same for the opponent)`.
   - The score row uses `PF_A + 2·L_A`, and the opponent's row uses `PF_B − 2·L_A`. The margin moves by 4 points per
     unlucky lost fumble.
   - The constant 4 is fixed a priori, roughly the expected-points swing of a turnover, and is **not tuned**.
4. **Nesting switch (G0).** With ω = 0, no FCS games and L ≡ 0, C2 must equal C1 to ≤ 1e-9.

### 5.4 Candidate 3 (C3): C2 + within-season dynamics

C3 inherits every C2 parameter and adds:

1. **Random walk.** *o* and *d* follow a random walk across weekly cutoffs, `x_{w+1} = x_w + η`, with
   η ~ N(0, q·Δweeks) on each side. The model is solved exactly by a Kalman filter over weekly steps.
   - Initial state: the prior mean.
   - Initial variance: σ²_row/λ_i.
   - Observations: score rows (noise σ²_row) and SR rows (noise σ²_row/ω).
   - μ has a diffuse prior.
   - Ratings are then centered as in C1.
2. **QB-change shock.** A detected QB change adds q_QB to the offense's state variance once, at the cutoff after the game
   where it is detected. A change is detected when a team's primary passer in its latest game (≥ 10 dropbacks) differs from
   its season-to-date primary passer.
3. **Choosing q and q_QB.** q ∈ {0, 0.25, 0.5, 1, 2} and then, given q, q_QB ∈ {0, 4, 16, 36}, both in points² and both by
   inner walk-forward CV (§6). Ties go to 0.
4. **Nesting switch (G0).** With q = q_QB = 0, C3 must equal C2 to ≤ 1e-6 (the Kalman path versus the direct solve).

### 5.5 What each candidate answers

| | C1 | C2 | C3 |
|---|---|---|---|
| Question | Does a richer preseason information set beat the incumbent? | Does play-level success rate add information as a measurement of the same strength? | Does modeling real in-season change (injuries, QB changes) beat a static season? |
| New estimated parameters | Prior coefficients and ridge λ (per side and regime), b, λ0, a_X | α, β, ω, μ_FCS, ρ_FCS, v_FCS | q, q_QB |
| New fixed constants | Grids, turnover index, `cont` cap 1.5 | Fumble constant 4 | QB ≥ 10 dropbacks |

**Excluded from every candidate:** vendor EPA and win probability, vendor ratings, polls, market data, team-specific HFA,
post-hoc tier offsets, tuned portal weights, coordinators and special teams.

---

## 6. How parameters are estimated without leakage

| Parameter | Candidate | Data used for target season *y* | Method | Target-season data? |
|---|---|---|---|---|
| Prior coefficients, ridge λ | C1–C3 | Team-seasons 2014 … *y*−1 (not 2020 as response) | Ridge with forward-chaining CV | No |
| b (turnover to variance) | C1–C3 | CV residuals from those seasons | OLS of log r² | No |
| λ0 | C1–C3 | Seasons 2016 … *y*−1 | Inner walk-forward CV: each season's games predicted weekly from its own past only; minimize winner log-loss | No |
| a_X (prior scale) | C1–C3 | Games of seasons 2016 … *y*−1 | LAD (incumbent procedure) | No |
| H | All | Incumbent fold value | Shared | No |
| α, β | C2–C3 | Training-season games and end-of-season ratings | OLS | No |
| ω | C2–C3 | Seasons 2016 … *y*−1 | Inner walk-forward CV, log-loss | No |
| μ_FCS, ρ_FCS, v_FCS | C2–C3 | Training-season end-of-season fits | Moments and OLS | No |
| q, then q_QB | C3 | Seasons 2016 … *y*−1 | Inner walk-forward CV, log-loss | No |

- **Order of estimation.** Estimation is sequential and nested: C1's parameters first; C2 estimates only its own given C1's;
  C3 estimates only its own given C2's.
- **Fold 2017.** Inner CV uses 2016 only, the same thin history the incumbent has.
- **Conditional seasons (2023–2025).** All parameters are frozen at the values estimated through 2022, like the incumbent,
  whose selection ended in 2022. Only the data inputs roll forward.
- **Forward.** At the freeze, every parameter is re-estimated once through 2025 with the same procedure (Round 13 precedent
  for w_2026), then frozen for 2026–2027.

---

## 7. Metrics (exact)

**Universe.** Completed FBS-vs-FBS games, regular season and postseason. Each game is predicted at its week's cutoff from
information available before that cutoff. All models are scored on identical game IDs.

**Bootstrap.** Paired Δ = model − reference; negative is better for losses. Intervals use a flat season×week block
bootstrap: 4,000 resamples, seed 15015, with blocks keyed on the cutoff as text. That gives 106 development blocks, 85 on
K's subset, and 65 conditional.

### 7.1 Part A: power rating

**Converting a rating to a win probability.** The model's predicted home margin is `m = P_home − P_away + H·site`, and
`p = Φ(m / 16)`, where Φ is the standard normal CDF.
- **Why σ = 16:** it is the incumbent's out-of-sample residual SD (16.3 development, 15.8 conditional), fixed for every
  model so that a rating point means the same thing everywhere.
- **Clipping:** p is clipped to [10⁻⁶, 1 − 10⁻⁶].
- **Example:** a 7-point home favourite gets p = Φ(0.4375) = 0.669.

**Metrics:**
- **Winner log-loss (primary).** `L = −[w·ln p + (1 − w)·ln(1 − p)]` with w = 1 if the home team won; the game mean is reported.
- **Brier (secondary, tie-break):** `(p − w)²`.
- **Link-scale sensitivities (report only):** σ = 15 and 17, plus AUC of m for home wins.
- **Calibration slope:** `lm(actual − H·site ~ m − H·site)`, pooled and by gp bucket. gp = min(games played) of the two
  teams before the cutoff; buckets 0, 1, 2–3, 4–6, 7+. **The spread target is slope 1, not a rating SD.**
- **Rating spread:** SD of FBS power ratings at each cutoff, and predicted-margin SD by gp bucket.
- **Tier separation:**
  - mean rating by tier (P4, G5, independents);
  - log-loss and oriented P4-vs-G5 bias `mean((actual − m)·s)` on cross-tier games (season-indexed tier map; Pac-12 is G5 from 2026);
  - FBS-vs-FCS slice for models that rate FCS teams. The incumbent uses −25 for every FCS team, as the simulation does.
- **Stability:** mean |ΔP| between consecutive cutoffs per team, by gp; Kendall distance between successive top-25 lists.
- **Update efficiency:** the slope β_upd of each game's residual `actual − m` on the change in rating difference since the
  previous cutoff. 0 is efficient; > 0 means sluggish, < 0 means jumpy.

### 7.2 Part B: game prediction

- **Accuracy and bias:** MAE; RMSE; bias `mean(m − actual)`.
- **Winner %:** sign agreement, excluding zero predictions. The number of games where two models disagree is reported with it.
- **Predicted-margin distribution:** quantiles.
- **Slices:** per season; gp buckets; conference versus non-conference; P4-P4, P4-G5, G5-G5, and games with independents;
  early season (gp 0–3) versus later.

### 7.3 Part C: market value (evaluation only)

**Lines.** Per game, from CFBD `/lines` (pull vintage 2026-09-25; `R/round15/market_lines.R`):
- Validated book quotes only: home-perspective sign checked against `formattedSpread`; "consensus" rows excluded.
- `open` = median `spreadOpen` of valid books; `close` = median `spread`.
- Implied home margins: `M_o = −open`, `M_c = −close`.
- **Coverage:** close exists for 100% of games in 2017–2025. Open exists only for 2021+, i.e. 1,539 development games and
  2,398 conditional games.
- **No prices exist**, so no ROI is claimed. The break-even at −110 (52.38%) is shown for reference only.

**Edge.** `E_c = m − M_c` and `E_o = m − M_o`. The incumbent's edge SD is 4.8 points on development and 4.4 on conditional.

**Test 1: predicting outcomes relative to the market.**
- Model MAE and log-loss beside the market's own (market log-loss uses `Φ(M_c/16)`).
- **Encompassing regression:** `actual = a + b_M·M_c + b_m·m`. A positive b_m means the model carries outcome information the close lacks.
- **Edge calibration (key test):** `actual − M_c = a + β_E·E_c`. β_E is the share of the model's disagreement that is
  realized: 0 means nothing beyond the market, 1 means fully right, < 0 means worse than nothing.
- Also reported against the open.
- Planned precision (SE of β_E): about 0.06 development, 0.07 conditional, 0.10 forward.

**Test 2: predicting market movement.**
- `move = M_c − M_o`.
- Movement slope β_mv from `move = a + β_mv·E_o`.
- Share of games with |move| ≥ 0.5 that moved toward the model, i.e. sign(move) = sign(E_o).
- Mean closing-line value `CLV = sign(E_o)·move`, in points.
- Open-line seasons only.

**Test 3: beating the spread.**
- **ATS vs close:** pick sign(E_c). The pick wins if `(actual − M_c)·sign(E_c) > 0`. Pushes and zero-edge games are excluded.
- **ATS vs open:** the same rule on the opening line.
- **Edge buckets (fixed now), on |E|:** [0,1), [1,2), [2,3), [3,5), [5,7), ≥ 7 points. For each bucket: n, ATS % with a
  95% Wilson interval, mean covered margin `(actual − M)·sign(E)`, CLV.
- **Monotonicity:** logistic slope of ATS win on min(|E|, 10), with a block-bootstrap interval. This answers whether larger
  disagreements are better.
- The historical incumbent has 260–860 games per bucket. Forward buckets will be much smaller, with a per-bucket ATS SE of
  about 2.5–4.5 points.

**Rule.** No other bucket, threshold or filter may be introduced after results. Any new market slice is labeled
post hoc and has no decision power.

### 7.4 Report-only sensitivities (no decision power)

- σ = 15 and 17 link scales.
- Continuity rebuilt from dated departures only (§4.3).
- Vendor talent composite added to C1's prior.
- The P4-vs-G5 bias under v10_refined's correction, for context only.

---

## 8. Gates, advancement and verdicts

All thresholds are fixed here. Each candidate X ∈ {C1, C2, C3} is tested against the incumbent I.

**G0: integrity.** This runs before any metric is read, and any failure stops the round.
- **G0a** — the nesting switches reproduce the incumbent replay, C1 and C2 exactly (§5).
- **G0b** — leakage tests:
  - L1: scrambling outcomes of seasons ≥ *y* leaves season-*y* predictions unchanged.
  - L2: no training row has available_at ≥ its cutoff.
  - L3: every preseason input is dated before its season (§4.1).
  - L4: market isolation (§4.4).
  - L5: no vendor EPA, WP or ratings columns.
  - L6: no 2023+ data in any development fit, and conditional runs use parameters frozen through 2022.
- **G0c** — all tests pass, and the input and freeze manifests verify.

**G1: power-rating primary (development, 2017–2022).** Pooled Δ log-loss(X − I) ≤ **−0.0020**, **and** the upper
bound of the **98.33%** block interval is < 0 (Bonferroni over three candidates).

**G2: guardrails (development).** All of the following must hold:

| | Guardrail | Threshold |
|---|---|---|
| G2a | Margin prediction not materially worse | Δ MAE ≤ +0.020, and the 95% interval's lower bound ≤ 0 |
| G2b | RMSE | Δ RMSE ≤ +0.030 |
| G2c | Brier consistent with the primary | Δ Brier ≤ 0 |
| G2d | Calibrated spread | Pooled slope in [0.90, 1.10]; each gp-bucket slope in [0.80, 1.20] |
| G2e | Tier separation | \|P4-vs-G5 bias\| ≤ the incumbent's |
| G2f | No season materially worse | Every development season: Δ log-loss ≤ +0.003 |
| G2g | Early and late season | gp 0–3 and gp 4+: each Δ log-loss ≤ +0.001 |
| G2h | **Market veto** (close lines, development) | β_E(X) ≥ β_E(I) − 0.10, **and** β_E(X) not significantly negative (95% upper bound ≥ 0) |

**G3: non-degradation (2023–2025, contaminated).** All of the following must hold:
- Δ log-loss ≤ +0.001;
- Δ MAE ≤ +0.030;
- pooled slope in [0.90, 1.10];
- \|P4-vs-G5 bias\| ≤ the incumbent's;
- market veto: β_E(X) ≥ β_E(I) − 0.10 on close lines.

**A layer's value is established** when both hold:
- Δ log-loss(C_{k+1} − C_k) on development has its 95% block upper bound < 0;
- C_{k+1} passes G2.

**Recommendation rule** (applied in order C1, C2, C3; R starts empty):
- C_k becomes R if it passes G0–G3 **and** either R is empty or C_k's layer value over R is established.
- **Examples:**
  - C1 fails, C2 passes → C2.
  - C1 and C2 pass but C2's layer is not established → C1.
  - Then C3 is compared against C1.
- **Ties** between candidates (when the rule needs one) go to lower Brier, then lower MAE, then the simpler candidate.

**Verdicts:**
- **PRODUCTION CANDIDATE (historical):** R exists. The full report goes to you; production is your decision.
- **INCUMBENT RETAINED** in any of these cases:
  1. no candidate passes G0–G3, market vetoes included;
  2. G0 fails in a way that cannot be fixed without changing a specification (that becomes a new round);
  3. you decline.
- An **incumbent-retained** report states, for each metric, the smallest effect it could have detected. It keeps the
  reconstructed data tables and starts no Round 15 forward test.

## 9. Forward test and snapshots

- **Mechanism:** `docs/forward/FORWARD_SNAPSHOTS.md`, built and tested; activation awaits your approval.
- **At freeze:** R (or all passing candidates, if you prefer) is frozen with parameters re-estimated through 2025. Its code
  is committed and hashed, and its plugin is added to the snapshot tool. The freeze manifest is signed.
- **Forward window:** games kicking off after the freeze timestamp. Each is scored by the rule in FORWARD_SNAPSHOTS §4.
  Games with no snapshot are reported missing, never imputed. The incumbent and K are archived alongside.
- **Forward market lines** are pulled after each season into the evaluation-only store, with vintage and hash recorded.
- **2027** needs the incumbent's 2027 extension. If none exists by 2027-08-15, the forward test uses post-freeze 2026 only
  and its best verdict is "forward-consistent, underpowered".
- **One look on or after 2028-02-01.** No interim result carries decision power.

| | Forward check | Rule |
|---|---|---|
| F1 | Power rating | Δ log-loss vs I ≤ 0 (point estimate). Interval reported |
| F2 | Game prediction | Δ MAE ≤ +0.05 |
| F3 | Market value | Claimed **only** under these conditions:<br>• outcome information beyond the close: β_E lower 95% bound > 0<br>• predicts movement: β_mv lower bound > 0<br>• beats the spread: pooled ATS vs close lower 95% Wilson bound > 52.38%<br>Otherwise the report says "not demonstrated". Each claim is reported separately |

## 10. Where Rounds 13 and 14 influenced this design (disclosure)

1. **Success rate as the only play-level measure, and vendor EPA excluded.** From Round 13's SR result and Round 14 Phase 1's qualitative finding that EPA was redundant with SR (your decision 4).
2. **Last season's success rate and the multi-year score history in the prior.** From Round 14 Phase 1's clue that the prior carry-over was the biggest lever. Its numbers are not used.
3. **FCS games in C2/C3.** From the FCS side experiment and Round 14's clue. The weight is not tuned; FCS teams are modeled instead.
4. **The G1 threshold of −0.0020.** The Round 13 development pair gives an exchange rate: Δ log-loss −0.0037 corresponded to Δ MAE −0.067. At that rate, −0.0020 corresponds to about −0.036 MAE, slightly stricter than Rounds 13–14's G1 bar of −0.030 MAE. This sets how large a gain counts as meaningful. It makes passing **harder** than a significance test alone.
5. **Log-loss as primary, and the power estimates.** From the incumbent-versus-K development pair (probe 04).
6. **Round 13's SR instrument** (eligibility, garbage filter, fumble recovery, λ 0.5) is reused frozen, not retuned.
7. **Round 13's gp 1–3 pattern is not built in.** SR's weight against games played emerges from precision accumulation.

No threshold, grid or definition here was chosen after seeing any Round 15 result. None exist.

## 11. Reporting

- **Scorecards.** Three separate scorecards (Power Rating, Game Prediction, Market Value) for I, K, C1, C2 and C3. Each
  row gives the absolute value, Δ vs I, Δ vs K (on K's games) and the layer increment (C1 − I, C2 − C1, C3 − C2), each
  with n and its interval.
- **Other tables:** per-season, gp buckets and tier/conference slices; every gate with its value and pass/fail; every area
  where a candidate is worse; development, conditional and forward evidence kept separate.
- **Stop rule.** Stop after the full historical evaluation. No write-up beyond the numbers, no production plan and no
  production change until you approve (standing rule).

## 12. Stop points and amendments

1. **Sign-off of this draft** (with any edits) → hash.
2. **P1–P5** run. The coverage and test report is shared. Only a stop condition halts the round, and no outcomes are read.
3. **Build C1–C3 and G0.** Any G0 failure stops the round and is reported.
4. **Development and conditional evaluation, gates and three-part scorecard.** Stop, report, and await your decision.
5. **At your approval:** freeze and forward plugin.

**Amendments:** dated and hashed, and only before the step they affect. A failed gate is never "fixed" inside Round 15.

**Sign-off:** ______________________  **Date:** __________
