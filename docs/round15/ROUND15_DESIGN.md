# Round 15 design: a college football power-rating and ranking system

**Status: design only.** No model was built, no candidate is predeclared, and nothing in production, the incumbent or CI changed.
Branch `round15-power-rating` (from `main` at `e468b32`). Evidence here comes from four read-only probes
(`scripts/round15/01`–`04`, outputs in `docs/round15/coverage/`). No probe relates a new variable to game outcomes.
The CFBD probe used **93 calls** of the account's Academic tier (3,000 a month; 2,413 left on 2026-09-24; resets 2026-10-01).
Round 14 stays frozen at Phase 1: none of its numbers are used as evidence here, only its qualitative findings as labeled design clues.
Round 13 K is still a production candidate awaiting your decision; here it is a comparator only.

## Decisions for you before anything is predeclared

1. **Primary metric: out-of-sample winner log-loss with a fixed probit link (σ = 16 points).** The tie-break is development MAE (§9). Alternatives: Brier as primary, or MAE as primary.
2. **G1 threshold.** Pooled development Δ log-loss ≤ −0.002, with the 98.3% block upper bound < 0 (Bonferroni over three candidates). For scale, Round 13 K's development effect is −0.0037 (§2.3, §12).
3. **Development window.** Keep 2018, 2019, 2021 and 2022 (3,092 games, comparable with Rounds 13–14), or add 2017 (+776 games; about 11% smaller detectable effect). Adding 2017 needs a 2017 incumbent replay. *Recommend adding it if the replay reproduces.*
4. **Candidate set.** Three nested candidates (§11): A upgrades the prior; B adds a play-level measurement channel and FCS games; C adds within-season dynamics. Approve, trim or reorder.
5. **PBP channel source.** Success rate only, which needs no expected-points model. Vendor EPA would be a report-only sensitivity. The Round 14 vendor-EPA exception ends with Round 14 unless you extend it.
6. **Talent source.** Primary input: recruiting-class composites, dated at signing day. The vendor team-talent series was recomputed after our copy was taken (§6), so it becomes a sensitivity input only.
7. **Polls (Tier B).** Not a candidate input. They get a predeclared, report-only test of value net of the Tier A prior. Alternatively, drop them entirely.
8. **Forward evidence.** From the lock, archive hashed pre-kickoff snapshots for the incumbent, K and the frozen candidates. This is manual unless you approve automating it. One look after the 2027 season.
9. **2023–2025.** Used for non-degradation checks only (burned).

## 1. Summary

- **Most of a team's rating is prior for the first third of the season, and even season-end ranks are fuzzy.** A model-free
  variance decomposition puts true-strength SD at 12.1 points and pure game noise at 14.6 points (§2.2). After 3 games,
  data alone give reliability 0.59. After a full season it is 0.87, yet a true top-25 team still lands about 6.6 places from its
  true rank. The largest measurable gains are therefore in the prior and in how fast evidence overrides it. Exact ranks are
  not measurable; tiers and calibrated probabilities are.
- **Most Tier A roster variables can be reconstructed for 2015–2026 through CFBD player IDs.** This covers QB continuity, transfers
  with prior production, and defensive returning production. Round 5 called these "not estimable". Portal-specific fields start in
  2021, which leaves two development seasons, so they are used structurally, never tuned.
- **Two vendor series are unstable.** Team talent and offensive returning production from CFBD's current API disagree with the
  copies frozen on 2026-09-10 (talent ratio 0.79–0.81, Spearman 0.82–0.89). Historical vintages cannot be verified, so the design
  prefers inputs we can date ourselves.
- **Winner log-loss is a better primary than winner % or MAE.** It is strictly proper and ignores blowout margins. On a known real
  improvement (K vs incumbent) it detects the effect more strongly than MAE (z −3.6 vs −2.3). Winner % is too coarse: K and the
  incumbent disagree on only 82 of 3,092 winners.
- **Three nested candidates, a Bonferroni-controlled primary gate, and an explicit null outcome** (§2.5, §12).

## 2. Honest framing

### 2.1 There is no ground truth

Team strength is latent. Every metric below scores ratings against **future games**; none has access to "true" strength.
Choosing a ranking metric over MAE means choosing which feature of future games to treat as the target: the winner, the
margin, or the calibration. It does not mean getting closer to truth. AP, CFP, the market and other systems (SP+, FPI, Elo)
are descriptive comparators only, never targets or gates.

### 2.2 How much one season can reveal (probe 04, model-free)

Per season, the probe fits `margin = HFA·site + a_home − a_away + e` by REML, with random team strengths and no prior. It uses
FBS-vs-FBS games from 2014–2019, 2021 and 2022. Rank noise is simulated with 130 teams.

| Stage | Median FBS games | Posterior SD, no prior | Reliability | True top-25: mean rank error | …ranked top 25 | True top-12 ranked top 12 | Kendall τ |
|---|---|---|---|---|---|---|---|
| ~Week 4 | 3 | 7.8 pts | 0.59 | 12.4 | 68% | 60% | 0.64 |
| Mid-season | 6 | 5.8 | 0.77 | 9.1 | 74% | 68% | 0.72 |
| Full season | 12 | 4.3 | 0.87 | 6.6 | 80% | 75% | 0.78 |

- **Scale.** True-strength SD is 12.1 points (season range 10.9–13.5). Game noise is 14.6 points (14.1–15.6).
- **Room for improvement.** The incumbent's out-of-sample residual SD is 16.3. That implies about √(16.3² − 14.6²) ≈ 7 points of rating error per game, compared with about 15 points of irreducible noise.
- **Early season.** A preseason prior matters most while reliability is low. With 12 games a season, no rating system can separate teams a few places apart.
- **Target.** The design aims at tiers and calibrated probabilities, not exact ordinal ranks.

### 2.3 Power: what each metric can detect

The reference pair is the incumbent versus Round 13 K, on 3,092 development games, using flat season×week block bootstrap
standard errors.

| Metric | Incumbent level | Δ K − incumbent | SE | z | 80%-power detectable effect | as % of level |
|---|---|---|---|---|---|---|
| MAE | 12.970 | −0.067 | 0.030 | −2.25 | 0.083 | 0.64% |
| Squared error | 266.9 | −2.38 | 0.90 | −2.65 | 2.51 | 0.94% |
| **Winner log-loss (σ 16)** | 0.5353 | −0.0037 | 0.0010 | **−3.56** | 0.0029 | 0.54% |
| Brier | 0.1808 | −0.0016 | 0.0004 | −3.74 | 0.0012 | 0.66% |
| Winner miss rate | 28.3% | −0.71 pp | 0.30 pp | −2.36 | 0.84 pp | 3.0% |

- **By season stage.** At gp 0–3 (971 games), z is −1.80 for log-loss and −2.34 for MAE. At gp 4+ (2,121 games), it is −3.17 for log-loss and −1.39 for MAE. Log-loss is the more sensitive metric from week 4 on.
- **Winner disagreement.** The two models disagree on only 82 winners (25 of them at gp 0–3).
- **Forward power.** A forward test on about 1,300 post-lock games (2026 from the lock, plus 2027) would detect a K-sized log-loss effect with about 64% power. With MAE, power would be about 31%.

### 2.4 How far each metric can diverge from MAE

| Metric | Ignores / emphasizes | Evidence |
|---|---|---|
| Winner log-loss, Brier (fixed σ) | Ignores margin beyond the winner. Weights close and mid-range matchups. Penalizes a wrong spread through σ. | Across Round 4's 12 candidates, rank agreement with MAE is Spearman 0.83 and 0.84, with the same best model. On K it has the same sign as MAE and a stronger signal. |
| Winner % (pairwise ordering) | Improper and scale-free. Only games where the models disagree (≈ 3%) count. | Spearman 0.78 with MAE. It would have picked Talent_RP (71.8%) over EB_features (70.9%), although EB_features is better on MAE, RMSE, log-loss and Brier. |
| Rank correlation with future results | Invariant to any monotone rescaling, so blind to spread and HFA. | It can diverge completely: halving every rating keeps the ranking and ruins MAE. It must be paired with calibration. |
| Calibration slope | Measures spread, not ordering. | Orthogonal to ordering metrics. |
| Cross-tier bias | Covers about 100 P4-vs-G5 games per season. | Round 12 cut the bias from 5.62 to 0.79, but its MAE interval crossed 0. |
| Stability / volatility | Not an accuracy metric. | Can move opposite to accuracy. |

### 2.5 The null outcome

If no candidate passes G0–G3, the verdict is **INCUMBENT RETAINED**:
- **What the report says.** It gives the smallest effect each metric could have detected ("no gain ≥ X detected"), not "no effect".
- **What is kept.** The reconstructed data tables are kept for later rounds.
- **What does not happen.** No Round 15 forward test starts.
- **Round 13 K** is unaffected either way.

## 3. What an excellent system contains, and what we have

| Component | Why it measures strength | Incumbent (`v5 EB_features`) | Rounds 13–14 | Missing |
|---|---|---|---|---|
| Opponent-adjusted game evidence | Results against measured opponents | Points model, FBS-vs-FBS only, constant λ = 4 | K adds an SR net at gp ≥ 1 | FCS games; turnover luck |
| Play-level efficiency | Many plays per game give more observations than one score | None | K: additive SR; R14 explored | A measurement channel with its own noise level |
| Informative prior | Early ratings are mostly prior (reliability 0.59 at 3 games) | Last season, talent, returning production, coach tenure; λ picked at grid edge 0.1 | R14 clue: carrying the prior forward helped most | Multi-year history, QB, transfers, reliable defensive continuity |
| Team-specific prior uncertainty | High-turnover teams should update faster | Constant λ | None | Turnover-scaled prior precision |
| Calibrated spread at each stage | Slope 1 at every games-played level | Slopes > 1 in weeks 2–4 (compressed) | K slope 0.98 dev, 0.95 cond | Variance model by stage (R6 Family E clue) |
| Real change vs noise | QB changes are real; fumble recoveries are luck | Static within season | R13/14: 56-day half-life | Evolution variance; QB-change shock; turnover luck |
| Tier and conference structure | Only about 245 non-conference games a season identify levels (2/3 before October) | No term; P4-vs-G5 bias +3.4 to +5.6 | R11/R12 | Hierarchical conference level in the prior |
| FCS handling | About 0.85 FCS games per FBS team | Dropped; the simulation uses −25 | R14 clue: inclusion helps | FCS teams as parameters with a subdivision prior |
| HFA | Venue effect | Fixed 3.07 | R9: a learned HFA ≈ fixed | Keep fixed |
| Datable inputs | Honest backtests | Every feature is `historical_vintage_unverified` | None | Own reconstructions plus prospective vintage capture |

## 4. Data we hold and what the CFBD probe added

| Source | Seasons | Coverage (FBS teams or games) | Notes |
|---|---|---|---|
| Schedules and results | 2013–2026 | 125–138 teams | Frozen 2026 schedule stops at 2026-09-09; later results need the live refresh |
| Plays (Round 6 raw pull) | 2013–2025 | FBS-vs-FBS games 98–100%; FBS-vs-FCS 94–100% | Vendor `ppa` finite on 99.6–99.9% of plays (2013: 95%); 2026 weeks 1–3 in Round 14's live pull |
| Drives | 2013–2025 | 98–100% | Start field position on every drive |
| CFBD advanced game stats (Round 5) | 2015–2024 | All FBS teams | Vendor aggregates |
| Talent composite (frozen SportsDataverse copy) | 2014–2026 | 98–99% of FBS; 95–100% of FCS opponents | Vintage unverified; recomputed since (§6) |
| Returning production (frozen) | 2014–2026 | Offense 99–100% | Defense: 0% in 2014–16, 32–56% in 2017–21, 86% in 2022, 57% in 2023, 99–100% in 2024–26 |
| Coaches | 1989–2026 | 100% of FBS | Hire date 97–100%; 4–25 FBS teams a season had 2+ coaches |
| Portal (no player IDs) | 2021–2026 | 1,770–4,499 entries a season | Destination 60–84%; 247 rating 18–65%; stars 85–97% |
| **Rosters with player IDs** *(new)* | 2014–2026 | 100% of FBS | Synthetic negative IDs: 46% of rows in 2014, 16% in 2018, 0 from 2020. Class year known 8% (2014), 60% (2017), ≥96% (2019+) |
| **Player season stats** *(new)* | Passing 2014–26; defense 2016–26 | 100% of FBS; IDs 100% | CFBD has no defensive player stats for 2014–15 |
| **Recruits and team classes** *(new)* | Recruits 2010–26; classes 2000–26 | 2,445–4,710 recruits a year | Recruit-to-athlete ID link 33–79%; 34–64% of roster players match a recruit |
| **NFL draft** *(new)* | 1967–2026 | College athlete ID 98–100% | Departures known by late April |
| **Returning production, CFBD API** *(new)* | 2014–2026 | 98–100% | Includes the returning share of passing PPA |
| **Polls** *(new)* | 2014–2026 | AP top 25 only | No "others receiving votes"; preseason poll = week 1 |
| **Havoc with pass breakups** *(new, sampled)* | 2014 partial; 2019 and 2025 full | — | Pass breakups are not in play-by-play |
| Market lines, CFP top 25 | 2023–25; 2018–25 | — | Comparators only |

**Not available.**
- *Not on our API tier:* weather, opponent-adjusted metrics (WEPA) and live play-by-play.
- *No CFBD endpoint:* coordinators.
- *Endpoints that return HTTP 400 without a filter:* coach tenures and seasons, SP+ and FPI (they need a year).
- *Not used:* scraping 247Sports, On3 or ESPN pages. Their site terms restrict it, and scraping would not recover historical vintages anyway.

## 5. Variable inventory and classification

**Class.** FC = football content: it describes the roster, performance or staff. EE = expectation-encoding: it records what
people *expect*, which may already include market information.

**Dev sample.** Development target seasons with the input available, and training seasons available before the first target.

| # | Variable | Class | Tier | Source | Seasons | Dev sample | Decision |
|---|---|---|---|---|---|---|---|
| 1 | Previous-season strength (scores and SR) | FC | A | Our reconstruction | 2013– | All targets; ≥ 3 training seasons | Prior mean |
| 2 | Multi-year strength (2 seasons back) | FC | A | Our reconstruction | 2013– | All | Prior mean (R5 clue: dev −0.074, CI crossed 0) |
| 3 | Recruiting-class composite (4 classes, fixed weights) and blue-chip share | FC | A | `/recruiting/teams`, `/recruiting/players` | 2000– | All | **Primary talent input** |
| 4 | Team talent composite (roster-based) | FC | A | `/talent`; SportsDataverse copy | 2014– | All, vintage unknown | Sensitivity only (§6) |
| 5 | Returning production, offense | FC | A | Our ID-based rebuild (≈ 13 calls to `/ppa/players/season`); CFBD as a cross-check | 2014– | All | Prior mean and precision |
| 6 | Returning production, defense | FC | A | Our tackle-share rebuild by ID | 2017– (from 2016 stats) | All targets; 1 training season before 2018 | Prior mean and precision (r 0.86–0.996 with the vendor figure) |
| 7 | QB continuity: leader returns, drafted, transferred or gone | FC | A | Stats + roster + draft | 2015– | All; ≥ 3 training seasons | Prior mean and precision (offense) |
| 8 | Incoming QB's prior production | FC | A | Same, by ID | 2015– | 3–45 QBs with ≥ 100 attempts moved per season | Structural: counted inside returning production |
| 9 | Transfers in and out, with quality | FC | A | Roster-ID moves (2015–); portal (2021–) | 2015– / 2021– | Portal: 2021 and 2022 only | **Structural only.** Transfer production counts as returning production. Portal ratings: report only |
| 10 | Head-coach change, tenure, interim | FC | A | CFBD coaches | 1989– | All; 16–35 new head coaches a season | Prior precision; small mean term |
| 11 | Coordinator changes | FC | A | None | — | 0 | Not estimable; record as a gap |
| 12 | Conference strength | FC | A | Derived from games | 2013– | ≈ 245 non-conference games a season | Hierarchical prior level |
| 13 | Strength of schedule | Derived | A | Derived | — | — | Falls out of opponent adjustment; reported, not an input |
| 14 | FCS games | FC | A | Schedules, plays | 2013– | ≈ 110 games a season | In B and C |
| 15 | Preseason AP poll | EE | B | `/rankings` | 2014– | Top 25 only | Report-only test of value net of Tier A |
| 16 | Program trajectory | FC | B | Derived | 2013– | All | Only through the multi-year weights |
| 17 | Returning starters | FC | B | No reliable free source | — | 0 | Proxied by production-weighted continuity |
| 18 | Betting lines, win totals, pregame WP (`/metrics/wp/pregame` is spread-derived) | EE | Excluded | — | — | — | Comparators only |
| 19 | Vendor ratings: SP+, FPI, Elo (also in schedule files as `*_pregame_elo`), SRS, CORE | EE | Excluded | — | — | — | Comparators; the Elo columns get a trip-wire |
| 20 | Turnover luck (fumble recovery ≈ 50%) | FC | Other | Plays | 2013– | All | In B and C; needs the parser fix for 2025–26 |
| 21 | In-season QB change (primary passer) | FC | Other | Play text | 2013– | All | In C, as a variance shock |
| 22 | Special teams; field position; finishing drives | FC | Other | Plays, drives | 2013– | All | Diagnostics (special teams never correctly tested, R8) |
| 23 | Travel, rest; non-QB injuries; weather | — | Other | Not held, or not on our tier | — | — | Deferred or not obtainable |

**Play-level measures (the PBP evidence).** Each measure below is judged by how it measures team strength. Round 14's
findings are clues only.

| Measure | What it measures | R14 clue | Round 15 role |
|---|---|---|---|
| Success rate (50/70/100%) | Per-play efficiency; many observations; needs no expected-points model | Carries the PBP value | **Core of the B/C channel** |
| Vendor EPA (with or without turnovers) | Size of gains, valued by a vendor EP curve that may be fit on later seasons | Redundant with SR (corr 0.85) | Sensitivity only |
| Explosiveness; early-down, pass/rush and passing-down splits | Parts of efficiency, noisier than the total | No added value | Diagnostics |
| Havoc (pass breakups need the vendor endpoint) | Defensive disruption | No added value from the play-level version | Diagnostic |
| Finishing drives; field position | Red-zone conversion; hidden yardage | Not tested | Diagnostics (small samples) |
| Turnovers | Mostly luck (fumble recovery), partly skill (interceptions) | Turnover rate added nothing | Luck adjustment, not a signal |
| Garbage time | Plays that no longer reflect effort | Filter slightly hurt EPA | Keep Round 13's rule (frozen, no search) |
| Opponent adjustment, recency, FCS plays | — | FCS plays helped | Joint solve; recency via C's dynamics; FCS plays included |

## 6. Knowledge dates, revisions and leakage (probe 03)

- **Team talent was recomputed.**
  - For 2024–2026, CFBD's current `/talent` values average 0.79–0.81 times the SportsDataverse copy frozen on 2026-09-10. Pearson correlation is 0.79–0.90 and Spearman 0.82–0.89.
  - They are not the same series, and neither is a dated historical vintage.
  - The incumbent uses the frozen copy, so a 2027 re-pull cannot reproduce its inputs. This matters for the 2027 incumbent extension as well.
- **Offensive returning production differs between sources.** The SportsDataverse copy and the CFBD API correlate 0.55 (2021) to 0.96, and 40–60% of teams differ by more than 0.05. The definitions or computations were revised.
- **Portal entries are dated; destinations are not.**
  - No entry is dated after August 1 of its season. December and January dominate, and 84% of 2026 entries came in January (the new single window).
  - Destinations carry no commitment date, and 16–40% of entries never show one.
  - Between the two pulls (2026-09-10 and 09-24) nothing changed for 2024–25; 2026 gained 5 rows and lost 3.
- **Rosters have no snapshot date.** They may reflect later-season membership. Roster presence is therefore used only to mean "not departed". Departures come from dated sources (the April draft, portal entries before August 1). The predeclaration adds a sensitivity check that uses dated departures only.
- **QB continuity can be reconstructed** for every FBS team from 2015. Status of the previous season's attempts leader:

  | Status | Share of FBS teams |
  |---|---|
  | Back on the same roster | 58–66% through 2022; 52% in 2023; 38–43% in 2024–26 |
  | On another FBS roster | 2–6% before 2021; 13–28% from 2021 |
  | Drafted | 6–12% |
  | Gone | 14–32%; where class is known, 63–95% of these were seniors |

- **Transfers from roster IDs** closely track portal counts from 2021 (668 vs 732; 1,070 vs 964; … 2,281 vs 2,261). Before 2019 they are undercounted because of synthetic IDs, but they reach back to 2015, where the portal data cannot.
- **Vendor EPA** carries Round 14's accepted leakage risk: CFBD's EP curve may be fit on later seasons. A success-rate channel avoids it.
- **Play text changed format in 2025.** From week 9, and in part of week 1, plays use a stat-crew style ("#16 A.Kaliakmanis pass …").
  - Passer parsing drops to 57% with the old pattern and returns to 99% with both patterns.
  - Fumble-play recovery by the Round 8 parser falls to 68% in 2025 and 37.5% in 2026 weeks 1–3 (Round 14).
  - Parser drift on live data is a production risk for **any** PBP channel, Round 13 K included.

## 7. Prospective obtainability, 2026–2027

- **Weekly in season.** Results, plays and drives cost about 3–5 calls a week and are obtainable. The fumble and passer parsers must be fixed first.
- **Preseason inputs.** Rosters, recruits, team classes, returning production, draft, portal, coaches and polls cost about 40 calls per capture.
  - Capture them now, again after each portal window (January, April–May) and in August 2027.
  - Store each capture with its pull timestamp and hash. This gives 2027 its first **verified vintages** and builds a revision record.
- **Budget.** A few hundred calls a month in season, well under 3,000.
- **Two blockers apply whatever Round 15 finds:**
  1. The frozen incumbent design runs 2026 only; 2027 needs a feature ingest (MIGRATION_AUDIT_REPORT).
  2. Pre-kickoff snapshots are still manual.

  Round 15's ingest should be the vintage-stamped 2027 ingest for the incumbent and for the candidates.

## 8. What Rounds 7–14 leave us

| Round | Finding | Use in Round 15 |
|---|---|---|
| 7 | Efficiency as a *replacement* for scores is under-dispersed (SD 9.3 vs 20.7) and worse (+0.26 to +0.36) | Never replace the score channel; the scoreboard-repair reader is reusable |
| 8 | Variance matching amplifies noise (+1.7); fumble text parser; special teams never correctly built | No forced spread; calibration is a diagnostic; special teams untested |
| 9 | Efficiency's partial correlation given the incumbent was 0.03–0.05; SD-ratio gate unattainable; learned HFA ≈ fixed 3.0 | Keep HFA fixed; weight PBP by its measured noise, not by a zeroing rule |
| 10 | Post-hoc tier correction overshot (5.5 vs 3.4); talent add-on hurt September; v10_refined Gate 5 still open | Tier structure goes in the prior, not in post-hoc offsets |
| 11–12 | Tier term inside the solve: R11 would have passed on the correct metric; R12 cut bias 5.62 → 0.79 but MAE CI crossed 0 | Bias fixes don't show in MAE; cross-tier becomes a guardrail |
| 13 | SR stack K: dev −0.067, cond −0.041, gain mostly at gp 1–3; production candidate | Comparator in every table; evidence that SR measures something scores miss |
| 14 (clues only) | Prior carry-over is the biggest lever; vendor EPA redundant with SR; standalone PBP trails by 0.55–0.78 MAE; FCS inclusion helps | Shapes candidates A/B; no numbers reused |
| 5, 6, side | Multi-year prior −0.074 (CI crossed 0); Family E removed early compression (gp 0 slope 1.21 → 0.98); FCS at weight 0.25–0.5 positive on cond | Multi-year in the prior; stage-aware variance; FCS modeled, not down-weighted |

## 9. Evaluation design

### 9.1 Methods survey (what each approach offers)

- **Proper scoring rules** (Brier 1950; Gneiting & Raftery 2007). Log-loss and Brier are strictly proper: a forecaster cannot improve its score by distorting probabilities. Hit rate is improper.
- **Paired forecast comparison under dependence** (Diebold & Mariano 1995). The same idea is implemented here as a paired Δ with a season×week block bootstrap.
- **Calibration regression** (Mincer & Zarnowitz 1969). Actual on predicted; the slope measures spread.
- **Rating models for sports.**
  - Linear least-squares ratings (Harville 1980; Stefani 1980), and Bradley–Terry/Elo.
  - Dynamic state-space ratings (Glickman & Stern 1998).
  - Margins are roughly normal around the rating difference (Stern 1991), which justifies the probit link.
- **Retrodictive vs predictive evaluation.** How well ratings explain past games vs how well they predict future ones (the distinction runs through Massey's rating comparisons). Round 15 uses predictive only.
- **Rank correlation** (Kendall τ). Useful descriptively, but scale-invariant, so it cannot judge spread.
- **Forecast efficiency** (Nordhaus 1987). Revisions of an efficient forecast are unpredictable. This gives a ground-truth-free test of over- or under-reaction.

### 9.2 Primary metric and tie-break (fixed before any result)

**Primary: out-of-sample winner log-loss.**

L = −[w·log p + (1 − w)·log(1 − p)], with p = Φ(m / 16), where:
- m is the model's predicted home margin (rating difference plus its site term);
- w = 1 if the home team won.

Scope and comparison:
- **Universe:** FBS-vs-FBS games, walk-forward, Monday cutoffs.
- **Comparison:** paired Δ against the incumbent and against K.
- **Uncertainty:** flat season×week block bootstrap, 4,000 draws.

Why this metric:
- **Criterion 1, ordering, and criterion 3, spread.** It is strictly proper and scores both: σ is fixed, so over- or under-spread ratings lose.
- **Criterion 4, quality not scores.** The outcome is the winner, so blowout margins and running up the score have no leverage.
- **Criterion 5, predictiveness.** It is scored only on future games.
- **Evidence.** It detects a real improvement more strongly than MAE (§2.3) and picks the same best Round 4 model as MAE.
- **σ = 16.** This is the incumbent's out-of-sample residual SD (16.3 dev, 15.8 cond). Fixing it avoids a fitted parameter per model. σ = 15 and 17 are reported as sensitivities.

**Not chosen:**
- **Winner %:** improper and coarse.
- **Importance-weighted ordering:** arbitrary weights shrink the effective sample. Top-25 and P4-vs-P4 slices are reported instead, defined by the incumbent's pre-game rank so both models are scored on the same games.
- **Rating vs future opponent-adjusted margin:** it needs an adjuster, which is circular or favors models shaped like the adjuster. It is reported descriptively, using a neutral no-prior REML adjuster fit on post-cutoff games.
- **Brier:** nearly equivalent to log-loss; reported.

**Tie-break: development MAE.** It applies only between candidates whose primary Δ interval includes 0. If the MAE difference is also within ±0.02, the simpler candidate wins. The incumbent wins every tie against it.

### 9.3 Guardrails and diagnostics (vs the incumbent and K everywhere)

| Metric | Role | Definition and target |
|---|---|---|
| MAE, RMSE | Guardrail; tie-break | Δ MAE ≤ +0.02 (dev) |
| Calibration slope | Guardrail | `lm(actual − H·site ~ pred − H·site)`, in [0.90, 1.10] pooled. Reported by gp bucket (0, 1, 2–3, 4–6, 7+). **The spread target is slope 1, not an SD** |
| Predicted-margin SD by gp | Report | Compared with its calibrated expectation (§2.2) |
| P4-vs-G5 oriented bias | Guardrail | \|bias\| ≤ the incumbent's (season-indexed tier map). G5-vs-FCS and P4-vs-FCS reported for models that rate FCS teams (incumbent: −25) |
| Early season (gp 0–3) | Guardrail | Δ log-loss ≤ +0.001 |
| Within- vs cross-conference | Report | Δ log-loss and bias separately |
| Stability | Report | Weekly mean \|ΔR\| by gp; Kendall distance between successive top-25 lists |
| Update efficiency | Report | Slope β of each game's residual on the latest weekly rating change (home minus away). Target 0; β > 0 means sluggish, β < 0 means jumpy |
| Winner %, per season, by gp, top-25 slice | Report | — |
| ATS vs the **opening** line | Report only | 2023–25 only; lines exist for no other seasons |
| Descriptive agreement with AP, CFP, SP+/FPI | Report only | Never a target |

## 10. Holdouts, effective sample and overfitting controls

- **Burned: 2023–2025.** These seasons were examined in Rounds 4–14. Round 15 uses them only for a non-degradation gate (G3), labeled contaminated.
- **2026 is partly seen.** Weeks 1–3 went into production snapshots, the v10 interim bias check (n = 34) and Round 14's live coverage checks. The forward window is games that kick off **after the predeclaration's hash timestamp**.
- **Pristine: 2026 post-lock and all of 2027.** One predeclared look in February 2028.
- **Development: 2018, 2019, 2021, 2022** (optionally 2017). 2020 is never a target season.
- **Minimum training history.** A source needs at least 3 training seasons before the first development target to get a tuned coefficient; otherwise it enters structurally or not at all.
  - Portal fields have 0 training seasons before 2021 and 1 before 2022, so they are **structural only**.
  - Defensive returning production has 1 training season before 2018. It enters through the fixed continuity form (§11.2), with its coefficient pooled with offense's until enough seasons accrue.
- **Tuning.** All tuning happens inside training seasons, by inner walk-forward CV or marginal likelihood.
  - There is no outer search over recruiting × PBP × decay × weight combinations.
  - Each candidate lists its estimated parameters (≤ 6 hyperparameters each), and any grid-edge selection is disclosed.
  - No changes after results; a new idea means a new round.
- **Multiplicity.** G1 uses 98.3% intervals (Bonferroni over three candidates).

## 11. Architecture

### 11.1 Shared rating model

- Each team has an offense o and a defense d in points against an average FBS team; power P = o − d.
- Predicted home margin = P_home − P_away + 3.07·site. HFA stays fixed, following Rounds 6 and 9.
- Ratings stay on the points scale so they can be calibrated.

### 11.2 Preseason prior (A, shared by B and C)

**Prior mean.** Separate ridge regressions for offense and defense. The target is the end-of-season score rating, fit on earlier
team-seasons; λ is chosen by forward-chaining CV over {0.01, 0.03, 0.1, 1, 10}, which extends past the incumbent's grid edge.
The structural form is carry-over scaled by continuity:
`prior = a + (b + c·continuity)·last_rating + e·rating_two_back + f·recruiting + g·QB + h·coach + conference level`.

**Prior precision** varies by team: λ_i = λ0·exp(−κ·u_i), where u_i is a turnover index (1 − continuity, new QB, new head
coach). λ0 and κ come from walk-forward marginal likelihood. The incumbent uses a constant λ = 4.

| Input | Prior mean | Prior precision | Justification |
|---|---|---|---|
| Last season's rating; the one before | Yes | — | Strength persists; two seasons reduce noise from one season |
| Recruiting composite (4 classes), blue-chip share | Yes | — | Roster quality persists and is dated at signing |
| Returning production O/D, transfers-in included | Scales the carry-over | Yes | Continuity decides how much of last season carries |
| QB returning / transfer QB | Yes (offense) | Yes | Highest-leverage position |
| New head coach, tenure | Small term | Yes | Scheme change: the direction is uncertain, the variance is not |
| Conference level (last season) | Shrink target for low-information teams | — | Few cross-conference games identify levels |
| FCS (B, C) | Subdivision offset, previous FCS rating, FCS talent | Wide | Little FCS information |

### 11.3 How evidence updates the prior

**B adds two things to A's solve:**
1. **An SR measurement channel.** Game-level SR for offense against defense observes the same latent strength: SR = α + β·(o + d) + e_SR. α, β and σ_SR are estimated on training seasons. A game then adds precision from points and from SR. **The weight on PBP versus games played is not tuned.** It falls out of accumulated precision: SR matters most when few games exist, which fits Round 13's gp 1–3 clue without building that clue in.
2. **Turnover luck and FCS games.**
   - Points are corrected for fumble luck: ±4 × (fumbles lost − 0.5 × fumbles). The constant is fixed, not tuned.
   - FCS teams become parameters with their own priors, and their games carry full weight. Down-weighting was a crude stand-in for FCS-team uncertainty, which the prior now models.

**C adds within-season dynamics.** O and D follow a weekly random walk with variance q. A detected change of primary passer adds a one-time offensive variance shock q_QB. q and q_QB are estimated by marginal likelihood on training seasons, and a Kalman filter gives the cutoff ratings. This replaces fixed decay with an estimated split between real change (q) and noise (σ). With q ≈ 0, C reduces to B.

**Compression and over-dispersion** are controlled by estimating the variance components: prior variance by turnover, noise per channel, and evolution variance. There is no post-hoc scaling and no variance matching. If training seasons show gp-bucket slopes away from 1, the variance model is fixed before the lock.

**Deliberately excluded from every candidate:** vendor ratings, polls, the market, team HFA, post-hoc tier offsets, tuned portal weights, coordinators and special teams.

### 11.4 Candidates

| | A: prior upgrade | B: A + SR channel + FCS + turnover luck | C: B + dynamics |
|---|---|---|---|
| Prior | §11.2 | Same | Same |
| Game evidence | FBS-vs-FBS points (incumbent solve) | + SR channel, FCS teams, fumble-luck points | Same |
| Within season | Static | Static | Random walk + QB shock |
| Estimated walk-forward | Prior coefficients, ridge λ, λ0, κ | + α, β, σ_SR, FCS level | + q, q_QB |
| Question answered | Does better preseason information beat the incumbent? | Does play-level evidence add as a measurement? | Does modeling change beat a static season? |

## 12. Success criteria, gates and predeclaration structure

**Gates.** Thresholds are decision 2.
- **G0, integrity.**
  - A, set to the incumbent's inputs with κ = 0 and λ0 = 4, reproduces the incumbent's development predictions exactly.
  - Knowledge-date guards per source: no field dated after the cutoff.
  - Trip-wires for market and vendor ratings, including `*_pregame_elo`.
  - No 2023+ rows in development fits; hashes verified.
- **G1, primary (development).** Δ log-loss ≤ −0.002 and the 98.3% block upper bound < 0.
- **G2, guardrails (development).**
  - Δ MAE ≤ +0.02.
  - Pooled slope in [0.90, 1.10].
  - \|P4-vs-G5 bias\| ≤ the incumbent's.
  - No development season with Δ log-loss > +0.002.
  - gp 0–3 Δ log-loss ≤ +0.001.
- **G3, non-degradation (2023–25, contaminated).** Δ log-loss ≤ 0, Δ MAE ≤ +0.03, slope in [0.90, 1.10].
- **G4, forward (one look, February 2028).** Δ log-loss ≤ 0 on post-lock games, reported with its interval. Power is about 64% for a K-sized effect.

**Verdicts.**
- **PRODUCTION CANDIDATE** (G0–G3 pass). The result goes to you with the full Round 13 analytics plus the ranking tables. Production is your decision.
- **INCUMBENT RETAINED** (§2.5).

If several candidates pass: take the highest primary; within its interval, the tie-break decides; then the simpler candidate.

**Tradeoff table format.** Every results table uses these rows and columns.

| Model | Δ log-loss vs incumbent [98.3% CI] | vs K | Δ MAE [CI] | Slope: all / gp 0–3 / 4+ | P4-G5 bias | gp 0–3 Δ log-loss | Winner % | Weekly \|ΔR\| | β | Gates |
|---|---|---|---|---|---|---|---|---|---|---|
| Incumbent (ref) / K / A / B / C | … | … | … | … | … | … | … | … | … | ✓ ✗ |

**Predeclaration contents:**
1. Scope, and frozen inputs with pull timestamps and hashes.
2. Reconstruction specifications (QB, transfers, defensive returning production, recruiting classes) with unit tests.
3. Full candidate formulas, and each parameter's estimation procedure.
4. Metric definitions (σ, universe, cutoffs, buckets) and the bootstrap (flat season×week blocks, 4,000 draws, seed).
5. Gates and multiplicity rule; comparators (incumbent, K).
6. Reporting tables; stop rules; amendment policy; sign-off.

## 13. Transition architecture

1. **Now.**
   - Start vintage-stamped captures of the preseason sources.
   - Automate pre-kickoff snapshot archiving (with your approval).
   - Fix the 2025–26 fumble and passer parsers.
2. **Build.** Reconstruction tables for 2014–2026, with tests; code for A, B and C, with G0. Nothing is looked at outside training folds.
3. **Predeclare** (your sign-off), then run development, gates and G3. Report, then you decide.
4. **If promoted.**
   - The candidate runs in shadow beside the incumbent, with published hashed snapshots, until you approve a switch.
   - The 2027 design freeze uses verified vintages.
   - The live site still deploys from the old repository, so a switch means porting.

## Appendix: probe files (`docs/round15/coverage/`)

| Probe | Outputs |
|---|---|
| 01 local inventory | `local_coverage_matrix.csv`, `local_inventory_long.csv` (coverage, game types, passer parsing) |
| 02 CFBD coverage | `cfbd_coverage_matrix.csv`, `cfbd_probe_long.csv`, `cfbd_probe_budget.csv`, `cfbd_probe_calls.csv`. Raw responses are cached in `output/dev/round15/raw/` (git-ignored) |
| 03 reconstruction | `reconstruction_matrix.csv`, `reconstruction_long.csv`, `plays_2025_unparsed_passer_{patterns,by_week}.csv` |
| 04 metric power | `metric_power_incumbent_vs_r13K_dev.csv`, `metric_agreement_round4_candidates_dev.csv`, `metric_rank_agreement_round4_candidates_dev.csv`, `strength_variance_components_by_season.csv`, `team_rating_noise.csv` |

**References.** Brier (1950), *Monthly Weather Review*; Diebold & Mariano (1995), *JBES*; Glickman & Stern (1998), *JASA*;
Gneiting & Raftery (2007), *JASA*; Harville (1980), *JASA*; Mincer & Zarnowitz (1969), NBER; Nordhaus (1987), *REStat*;
Stefani (1980), *IEEE Trans. SMC*; Stern (1991), *The American Statistician*.
