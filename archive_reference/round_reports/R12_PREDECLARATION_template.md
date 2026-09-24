# Round 12 Predeclaration — P4/G5 tier term inside the incumbent's ridge solve

**Status: FINAL. Signed off by the user 2026-09-22 (chat: "I approve the Round 12
predeclaration"). Hashed 2026-09-22T15:01Z together with `tier_map.csv` in
`predeclaration.sha256`, before any Round 12 code was written or any fit run.**
Revision history: r1 draft; r2 (same day, user instruction) completed Step 0's
F12 reconciliation (B3.1) and fixed the γ prior mean to `carry` (B2, B4). This folds the "v11
Prompt Refinement Notes" (supplied in chat, 2026-09-22) into a binding
declaration. Every repo fact below was checked against the repo before this
draft was written. Where the notes conflict with the repo, this document
follows the repo and says so in B1. After the user signs off, hash this file
(B11 step 0) before any code or fit. After that, changes need a hashed
amendment (B12).

**Naming.** The brief calls this model "v11". `archive/v11-round11/` already
holds Round 11 (NOT PROMOTED), including `cfb_power_ratings_v11.R` and
`cfb_v11_forward.R`, the same file names the notes propose. To avoid a
collision, this work is **Round 12**. It uses the prefix `v12_`, results go to
`outputs/round12` → `archive/v12-round12/results/artifacts/`, and the
candidate is called `v12_candidate`.

---

# Part A — Brief as supplied (summary)

- **Draft v11 prompt:** a "natively integrated tier hierarchy (ridge
  regularization with group penalty)". The cross-tier shift is estimated
  inside the joint ridge solve instead of as v10_refined's post-hoc OLS × 0.65.
  The draft also proposes turnover-weighted (TAR) decay and Gates 1–5.
- **Refinement notes, items 1–11:**
  1. an explicit margin formula;
  2. a precise TAR definition;
  3. binary gates only, with no mid-stream re-tuning;
  4. a justified threshold for each gate;
  5. TAR moved to a Phase B that is reported but not gated;
  6. a clear Gate 5 rule;
  7. an explicit promotion tree;
  8. a decision on whether talent is in or out;
  9. detailed execution steps;
  10. an honest framing of what is new;
  11. an honest-limitations section.

# Part B — Binding resolutions

## B0. Repo facts this declaration relies on

| # | Fact | Source |
|---|---|---|
| F1 | **Production is `v5_EB_features`.** `v10_refined` is a *pending candidate*: Gates 1–4 pass and Gate 5 is open. It is not production. | `archive/README.md`; `v10_refined_2026_forward_validation_prompt.md` ("if not, v5_EB_features remains in production") |
| F2 | The PBP efficiency arm had **ensemble weight 0 in all 10 Round 10 fits** (incremental R² 0.0013–0.0026). Round 10 says efficiency is exhausted and should not be revisited. | `archive/v10-round10/docs/REPORT.md` §1 and "What this implies" |
| F3 | The "56-day decay" is the **play-recency half-life of the efficiency solve** (`v9_half_life <- 56`, locked in Round 7). It is not a talent decay. The talent decay is k = 4. Talent failed the conditional September gate in both Round 9 and Round 10 and was retired. | `archive/v9-round9/code/cfb_power_ratings_v9.R:10`; R10 predeclaration B2, B5; R10 report §3 |
| F4 | **Round 11 already put a tier term into the incumbent's ridge solve.** That was a two-level opponent-tier effect with no venue term, a zero prior mean, grid λ_tier ∈ {1,…,64}, and "0" meaning off. The best 2018–19 inner-holdout result was at **λ = 1, the lowest nonzero grid value**. Round 11 reported bias 4.32 → 2.97 (−1.35 pts) with MAE −0.042, and −1.76 pts with MAE −0.033 on full development. **Those bias figures use Round 11's un-oriented metric (B3.1).** On the P4-oriented metric the same predictions give **4.88 → 2.25 (−2.63) on the inner holdouts** (Round 11's own pooling) and **5.76 → 2.52 (−3.24) on full development** (pooled over the 366 P4-vs-G5 games). Round 11's Step-1 gate (reduction ≥ 2 and MAE Δ ≤ 0) **would therefore have passed at λ = 1**. The extension reproduces the incumbent to ~5e-14 when the tier term is off. | `archive/v11-round11/docs/REPORT.md`; `tier_inner_pooled_selection.csv`; re-scored 2026-09-22 from `outputs/round11/cache` (B3.1) |
| F5 | v10_refined's development Δ −0.094 is **in-sample**: the correction was fit on the same games. Its 0.65 factor was chosen knowing the conditional bias, so the conditional −0.23 **is not independent**. | `v10_refined_interim_report.md` §3a, §3c |
| F6 | P4-vs-G5 games per season: 98, 99, 83, 86 (dev) and 99, 109, 110 (cond). Residual SD on them is **≈16, not 13**. SE of the bias: 1.21 (2018–19), 1.20 (2021–22), 0.91 (2023–25). | computed from `outputs/round10/game_table.csv` + `v10_refined_predictions.csv` |
| F7 | P4-vs-G5 timing, 2018–25 (n = 684): **week 1 32%, week 2 20%, weeks 3–4 34%, week 5+ 14%**. | same |
| F8 | **Oracle ceiling.** A perfect *in-sample* flat correction `s(a + b·p4_home)` improves MAE by only −0.111 on {2019, 2021, 2022} and **−0.024 on 2023–25**. v10_refined on {2019, 2021, 2022} scores −0.089 [−0.167, −0.022]. Bootstrap half-width is ≈0.073 (season×week blocks, seed 7007). | same |
| F9 | **2026 P4-vs-G5 supply.** 76 scheduled under the season-indexed map (B3); 77 under the old map. Through 2026-09-20, 62 have been played; **14 remain** (weeks 4–9). The prospective archive starts 2026-09-09, so the 28 week-1 games have no pre-kickoff incumbent prediction. **N ≥ 100 cannot be reached in 2026.** Expected supply after a lock is ≈ 84 a season (≈ 76 regular season plus ≈ 8 bowls). | `archive/v10-round10/results/2026_schedule_refreshed.csv`; `v10_refined_amendment_02_gate5.md` §4.3 |
| F10 | The **2026 Pac-12** is Boise St, Colorado St, Fresno St, Oregon St, San Diego St, Texas St, Utah St and Washington St. Every current tier map (`gate5_2026.R`, `v10_refined.py`, `v11_p4`) labels it P4. That puts 6 of the 34 games in the v10_refined 2026 interim check into the wrong class. Without them: n = 28, v10_refined bias +0.49 (reported +1.56), incumbent +4.61 (reported +5.64). Under the season-indexed map the played-and-predicted set is still 34: 6 P4-vs-2026-Pac-12 games enter, and their residuals have not been computed. | `2026_gate5_results.csv`; `v10_refined_amendment_02_gate5.md` §2.2 |
| F11 | Portal data (`cfb_data_v2/portal_2014_2026.rds`) **covers 2021–2026 only**. Its fields are player, position, origin, destination, date, rating, stars and eligibility; there are **no snap counts**. Returning production covers 2014–2026 and is **already an incumbent preseason-prior feature** (`v5_terms`: `off_returning`, `def_returning`). Portal activity is also an incumbent feature (`v5_portal`). | file inspection; `cfb_power_ratings_vCurrent.R:1474,1596` |
| F12 | **Round 10 and Round 11 disagreed on the incumbent's P4-vs-G5 bias** for the same seasons: 2018 4.35 vs 5.23; 2019 4.15 vs 3.41; 2021 7.74 vs 4.67; 2022 6.49 vs 4.04. **Resolved 2026-09-22 (B3.1).** Round 11's `v11_p4g5_bias` omits the ×s orientation, which accounts for 2.82 of the 3.07-pt gap in 2021. The rest comes from development-prediction differences. The tier map and game sets are identical. | B3.1 |

## B1. Corrections to the refinement notes (recorded; the resolution is in the cited section)

1. **Margin formula (note 1).** The replacement `home_margin = (θ^off_home − θ^def_away) + …` models only home scoring; it drops the away offense vs. home defense term. The draft's double difference `(θ^off_i − θ^def_j) − (θ^off_j − θ^def_i)` was already correct. The formula is kept, with the tier term made explicit (B2).
2. **γ vs. λ_γ (note 9, steps 2 and 4).** "Apply γ fixed from Step 1c" mixes up the coefficient and the hyperparameter. γ is re-estimated at every snapshot from the data available at that cutoff. Only **λ_γ** (and the prior-mean choice) is frozen (B4).
3. **Host component (note 9, step 1a).** A tier term inside the efficiency arm cannot move predictions when that arm's ensemble weight is 0 (F2). Its host is the **incumbent's EB ridge solve**, the one that produces predictions (B2). The efficiency arm and ensemble step are dropped.
4. **TAR (notes 2, 5).** Not feasible as specified (B10):
   - there are no snap counts and no portal data before 2021 (F11);
   - `(departures + arrivals)/snaps` can exceed 1;
   - `56·(1 − TAR)` lies in [0, 56], so the 70-day cap can never bind, and every TAR > 0.5 pins at 28;
   - the 56-day half-life it modulates belongs to the retired efficiency arm (F3).
5. **Gate 1 (note 4).** The rationale is inverted: −0.085 is *weaker* than v10_refined's −0.094, not "an improvement over" it. Also, the comparator (F5) is in-sample while v12 is walk-forward. Against the oracle (F8), −0.085 on full development is 76% of a perfect in-sample fix. The paired Gate 2 bound (≤ −0.025) needs a point estimate ≲ −0.098, which is 88% of the oracle. Both are effectively unreachable out of sample (B7).
6. **Gate 3 per-era thresholds (note 4).** With the SEs in F6, a model with **zero true bias** passes each era with probability 0.79 (≤1.5), 0.90 (≤2.0) and 0.42 (≤0.5). **It passes all three only 30% of the time.** The draft's "≤1.00 in every era" gives 25%. Replaced in B7.
7. **Gate 5 (note 6).**
   - Criterion (a), "|bias| lower than 0.23 by ≥ 0.3", requires |bias| ≤ −0.07, which is **impossible**.
   - N ≥ 100 **cannot be reached in 2026** (F9).
   - "Mid-October" is wrong because P4-vs-G5 games cluster in weeks 1–4 (F7).
   - Replaced in B8.
8. **Fallback (note 7).** "Stay on v10_refined" is wrong: production is `v5_EB_features` (F1). Replaced in B9.
9. **Bootstrap.** Round 10 used season blocks (10,000 reps, seed 7007). v10_refined used season×week blocks (2,000 reps, seed 42). The notes mix the two. B6 pins one specification and recomputes v10_refined's interval under it.
10. **Pre-existing v10_refined inconsistency: resolved outside this round.** Its predeclaration set the Gate 5 band at [−1.60, +1.14] from σ = 13, and its forward-validation prompt used |bias| < 0.23. Both are superseded by `v10_refined_amendment_02_gate5.md` (locked 2026-09-22T14:31:18Z). That amendment sets one rule (|bias_ref| < |bias_inc|), uses the season-indexed map, and pools post-lock 2026 with 2027.
11. **Framing (note 10), accepted.** This round moves the P4/G5 shift from a post-hoc OLS × 0.65 step into the incumbent's joint ridge solve. It is the same linear adjustment, estimated in-season and shrunk by a penalty selected on data, instead of a hand-set factor. It is **not** a new model class. It is the Round 11 test plus a venue term, a wider grid and a carry-over prior (B2, B4).

## B2. Model

For game g with home team h and away team a:

```
home_margin_g = [(θ^off_h − θ^def_a) − (θ^off_a − θ^def_h)]
              + HFA · (1 − neutral_g)
              + s_g · (γ0 + γ1 · p4home_g)
              + ε_g
```

- **θ, HFA:** the incumbent's EB ridge solve and HFA, unchanged: the `v4_score_fit` EB branch, offense/defense shrunk toward the feature-informed preseason prior.
- **s_g** = +1 if the home team is P4 and the away team is G5; −1 if the home team is G5 and the away team is P4; 0 otherwise. Tiers come from B3.
- **p4home_g** = 1 if s_g = +1 and the site is not neutral; 0 otherwise.
- **γ0** is the P4-side shift when the P4 team is away or at a neutral site. **γ0 + γ1** is the shift when the P4 team hosts. This matches v10_refined's (a, b), so the coefficients compare directly.
- **Estimation.** γ0 and γ1 are appended to the same normal equations as θ, with penalty λ_γ·[(γ0 − μ0)² + (γ1 − μ1)²]. They are re-solved at every weekly snapshot from in-season games before the cutoff. There is no post-hoc step and no shrink factor.
- **Prior mean μ: `carry`, fixed (not selected).** For season T, μ = (γ̂0, γ̂1) from the final snapshot of the most recent *included* season before T, computed under the same λ_γ. That value exists before season T's first kickoff, so there is no leakage.
  - **Chain:** 2017 (the bootstrap season) starts from μ = (0, 0). 2018 carries 2017 and 2019 carries 2018. **2021 carries 2019**, because 2020 is excluded. 2022 carries 2021, 2023 carries 2022, and so on. The forward run carries 2025 into 2026 and 2026 into 2027.
  - **Why:** the week-1 snapshot has no in-season cross-tier games, so γ = μ exactly. Under a zero prior, v12 would equal the incumbent on the **32% of P4-vs-G5 games played in week 1** (F7). `carry` lets those predictions use last season's estimate, which in-season data then updates.
  - **Limits:** as λ_γ → ∞ this becomes pure cross-season extrapolation (v10's approach, which overshot); as λ_γ → 0 it becomes pure in-season estimation. λ_γ is selected in B4.
  - **`zero` (μ = (0, 0), Round 11's behavior) is an ablation only.** It is reported at the selected λ_γ and is never selected or gated.
- **Identification.** γ is identified only through cross-tier games and because θ is shrunk toward its prior. The report must show γ̂ by week.
- **Implementation.** Extend `archive/v11-round11/code/cfb_power_ratings_v11.R` by `source()`. The solve uses team-score rows, so the γ columns enter with ±½ weights chosen so that the implied home-margin shift equals s_g(γ0 + γ1·p4home_g) exactly. This is tested.

## B3. Tier map (season-indexed, frozen as `tier_map.csv`)

- **P4:** ACC, Big Ten, Big 12 and SEC in every season. Pac-12 through 2025. The 2024–25 two-team Pac-12 stays P4 to keep existing baselines comparable; a sensitivity run with it as Other is reported but not gated.
- **G5:** American, C-USA, MAC, Mountain West and Sun Belt. **Pac-12 from 2026 on** (F10).
- **Other** (s = 0): FBS independents, including Notre Dame, and non-FBS teams.
- **Step 0 (F12 reconciliation): done, see B3.1.** `tier_map.csv` is still written and hashed together with this file (B11 step 0).

### B3.1 Step 0 reconciliation (completed 2026-09-22; nothing fit)

**Cause.** `v11_p4g5_bias()` (`archive/v11-round11/code/cfb_power_ratings_v11.R:238`) returns `mean(actual_margin − pred_margin)` over P4-vs-G5 games. That is a *home-oriented* residual. Round 10, v10_refined and this declaration (B6) use the *P4-oriented* residual `(actual − pred) × s`.

G5 teams host 18–26% of P4-vs-G5 games. In those games Round 11 counts an under-rated P4 visitor as a negative residual, so part of the bias cancels.

**Ruled out:**
- **Tier assignment.** Round 11's team-level lookup (`v5_membership` on each season's schedule) and Round 10's per-game conference labels classify every 2018–25 game identically (0 disagreements).
- **Game set.** Identical: 3,092 development games with the same outcomes.

**Decomposition.** Per season, P4-vs-G5 games only. Both rounds' predictions are reproduced from their own artifacts and code; Round 11's reported values are matched to three decimals.

| Season | n | R10 reported (oriented, R10 preds) | Same preds, R11 formula | R11 reported (R11 formula, R11 preds) | **R11 preds, oriented** |
|---|---|---|---|---|---|
| 2018 | 98 | 4.35 | 3.68 | 5.23 | **6.14** |
| 2019 | 99 | 4.15 | 3.72 | 3.41 | **3.62** |
| 2021 | 83 | 7.74 | 4.92 | 4.67 | **7.34** |
| 2022 | 86 | 6.49 | 4.19 | 4.04 | **6.25** |

- **2021:** orientation accounts for 2.82 of the 3.07-pt gap. The development-prediction difference accounts for the other 0.25.
- **2018 is the exception.** Round 11 builds 2018 from its own bootstrap components (`cc_boot`, with an 80-row preseason minimum). Its predictions sit 1.79 pts lower on the P4 side than Round 10's. In the other development seasons the two rounds' predictions differ by 0.2–0.5 pts on the P4 side (game-level correlation ≥ 0.998).
- **Conditional 2023–25:** the Round 11 pipeline and Round 10 give identical incumbent predictions on all 318 P4-vs-G5 games (mean oriented difference 0.00). The 3.44 baseline is reproduced exactly.

**Round 12 baselines (binding).** Round 12's incumbent is the Round 11 pipeline with γ off (B2). Its baselines therefore come from the last column, all on the oriented metric of B6:

| Split | Incumbent P4-vs-G5 bias | n | SE |
|---|---|---|---|
| Development 2018–19 | 4.87 | 197 | — |
| Development 2021–22 | 6.79 | 169 | — |
| Development pooled | 5.76 | 366 | 0.86 |
| Conditional 2023–25 | **3.44** | 318 | 0.91 |

Round 10's development figures (era means 4.25 and 7.10) remain correct for Round 10's own predictions. They are not used here.

**Consequence for Round 11 (outside this round; flagged for the user).** On the oriented metric Round 11's Step-1 gate passes at λ = 1 (F4). Its NOT PROMOTED record rests on the metric, not the model. Whether to revisit Round 11 is the user's decision; this declaration does not do so.

**Guard.** `test_v12.R` includes a regression test that the bias function applies ×s. A synthetic G5-home game in which the P4 visitor wins by more than predicted must contribute a positive residual.

## B4. Hyperparameter selection (nested, forward)

- **Grid:** λ_γ ∈ {0.03, 0.1, 0.3, 1, 3, 10, 30}, with μ = `carry` fixed (B2): 7 configurations. `off` is the reference. The grid extends 1.5 decades below Round 11's edge optimum (F4). If the smallest value is selected, it is reported as a grid-edge hit and the grid is **not** extended.
- **Nested selection:**
  - For development target T ∈ {2019, 2021, 2022}, select on pooled inner-holdout MAE over development seasons earlier than T.
  - 2018 is used for selection only and is not scored.
  - The **conditional lock** selects on 2018, 2019, 2021 and 2022, then applies unchanged to 2023–2025 and to every forward prediction.
- **Rule:** the lowest inner MAE, with a 0.01 tolerance. Ties break toward larger λ_γ (the Round 9 house rule).
- **Arm rule (binary):** if the selected configuration does not strictly beat `off` on inner MAE for a target, γ is off for that target. If γ is off at the lock, v12 is the incumbent: **NOT PROMOTED**, stop.
- **Not blind.** Round 11 already scored the venue-less, `zero`-prior version of this grid on 2018–19. On 2026-09-22 the Step 0 reconciliation also re-scored Round 11's λ = 1 development predictions on the oriented bias metric (B3.1). Both are disclosed here.
- **Choice of `carry`.** The user fixed `carry` on 2026-09-22, in the same instruction that asked for the reconciliation, before that re-scoring was computed and before any Round 12 fit. It was not chosen from Round 11's results.

## B5. Everything else: inherited or excluded

- **Inherited unchanged:** the incumbent's specification, features, preseason prior, HFA, snapshot cadence, data files, and the 2018 bootstrap window (Round 11 `v11_pre80`).
- **Excluded:**
  - the efficiency arm and the ensemble (F2);
  - the talent add-on (F3), so there is **no Gate 6**;
  - TAR (B10).
- **No new data** except `tier_map.csv`, which uses conference labels only and no outcomes.

## B6. Splits, metrics, bootstrap

- **Splits:**
  - Development scored: 2019, 2021, 2022 (n ≈ 2,320).
  - Conditional: 2023–2025 (n = 2,398).
  - Forward: games after the lock timestamp (B8).
- **Full four-season development** is reported alongside, for comparison with v10_refined. It is not gated.
- **Bootstrap:** paired Δ = MAE(model) − MAE(incumbent); blocks are season×week; 10,000 reps; seed 7007. v10_refined's intervals are **recomputed** with this bootstrap for every comparison table.
- **Bias:** the mean P4-oriented residual `(actual − pred) × s` over P4-vs-G5 games, with SE = sd/√n. Round 11's `v11_p4g5_bias` is **not** this metric (B3.1); every Round 11 comparison is recomputed on this one.

## B7. Gates 0–4 (binary; thresholds fixed here)

| # | Split | Metric | PASS iff | Rationale |
|---|---|---|---|---|
| 0 | all | Integrity | Both test suites PASS; γ-off reproduces incumbent predictions to ≤ 1e-10 on every dev and cond game; adversarial checks unchanged (permute outcomes ≥ 2022 → the 2021 selection and predictions are identical; ≥ 2023 → the lock and 2022 predictions; ≥ 2024 → 2023 predictions); `tier_map.csv` hash matches | House standard (R10 B7) |
| 1 | Dev {2019, 21, 22} | Paired Δ MAE | **≤ −0.055** | Half of the in-sample oracle (−0.111, F8). An honest walk-forward model must capture at least half of what a perfect in-sample fix could. The notes' −0.085 needs 76% (B1.5). |
| 2 | Dev {2019, 21, 22} | 95% bootstrap upper bound of Δ | **≤ 0** | House standard. With a half-width of ≈0.073 (F8), **this gate binds**: it effectively needs Δ ≲ −0.073, about 2/3 of the oracle. The notes' ≤ −0.025 needs 88% (B1.5). |
| 3 | Cond 2023–25 | \|P4-vs-G5 bias\| | **≤ 1.72** | Half of the incumbent's 3.44, which the Round 11 pipeline reproduces exactly (B3.1). SE is 0.91, so a truly unbiased model passes ≈94% of the time and a model that removes only half the bias passes ≈50%. Absolute value, so overshoot fails too. Per-era development biases (with CIs) are reported but not gated, because development drives selection (B1.6). |
| 4 | Cond 2023–25 | Calibration slope | **∈ [0.92, 1.08]** | Kept from the notes. SE ≈ 0.025, so this is a ±3 SE sanity check (v10_refined: 0.972), not a discriminating test. |

**Reported, not gated:**
- conditional paired Δ MAE, which is capped near −0.024 by the oracle (F8), so no tier fix can show a conditional MAE gain;
- a head-to-head with v10_refined and with the Round 11 λ = 1 series, all on the oriented metric (B3.1);
- the `zero`-prior ablation at the selected λ_γ (B2);
- γ̂ by week and season;
- the Pac-12 2024–25 sensitivity run;
- the market benchmark.

## B8. Gate 5 — forward test

- **Sample:** P4-vs-G5 games under the season-indexed map (B3) that kick off after the lock timestamp. Each must be predicted by the locked v12 from a pre-kickoff snapshot, with the snapshot archived append-only and timestamped before kickoff. Games already played in 2026 are excluded: they have been seen (the interim check).
- **Prerequisite:** n ≥ 100. The forward sample starts only once Gates 0–4 pass and v12 is locked (B9). At ≈ 84 eligible games a season (F9), the earliest realistic date is **2028 weeks 1–2**, provided the lock comes before 2027 week 1. It is evaluated **once**, at the first weekly run with n ≥ 100.
- **Rule: PASS iff both hold:**
  - (a) |bias_v12| ≤ 1.72, the same bar as Gate 3;
  - (b) |bias_v12| ≤ |bias_incumbent| on the same games.
- **Power, stated before any data (σ ≈ 16):**

  | n | SE | P(pass \| v12 truly unbiased) | P(pass \| v12 no better than incumbent, bias 3.44) |
  |---|---|---|---|
  | 100 | 1.62 | 0.71 | 0.14 |
  | 150 | 1.32 | 0.81 | 0.10 |

  This gate catches gross misses. It cannot certify fine calibration.
- **Criterion (b)** is nearly determined by the size of the correction. It fails only if v12 overshoots by more than twice the realized incumbent bias. It is a safety check.
- **Deadline:** if n < 100 on 2028-10-01, Gate 5 is **NOT REACHED**.
- **v10_refined on the same games:** reported, not gated.

## B9. Promotion tree

```
Gate 0 FAIL                       → fix code; no gate is computed; no result is read
Arm rule: γ off at the lock       → NOT PROMOTED; production stays v5_EB_features
Gate 1 or 2 FAIL                  → NOT PROMOTED (stop; do not run conditional)
Gate 3 or 4 FAIL                  → NOT PROMOTED
Gates 0–4 PASS                    → "conditional candidate": v12 locked; weekly prospective predictions start
Gate 5 PASS                       → PROMOTE v12 (replaces v5_EB_features)
      if v10_refined also passes its own forward gate on the same games → v12 is preferred (no post-hoc/circular step)
Gate 5 FAIL or NOT REACHED        → NOT PROMOTED; production = v5_EB_features,
                                    or v10_refined if it was promoted meanwhile under its own amended rules
```

No threshold, grid, tier map or λ_γ changes after any Round 12 result is read. Any change is a new round.

## B10. Deferred: TAR / turnover-weighted prior (Phase B, not run in Round 12)

Nothing in Round 12 depends on this. A future round needs its own declaration with:
- **Host:** the incumbent's *preseason-prior strength*, meaning how quickly the EB solve moves off the prior. It is not the 56-day recency half-life, which belongs to the retired efficiency arm (F3).
- **Measure:** portal departures and arrivals, weighted by count and rating (2021 onward), combined with returning production (2014 onward). It must be bounded by construction to [0, 1].
- **Incremental test:** returning production and portal activity are **already in the prior's mean** (F11), so the test is whether turnover should also change the prior's *variance*.
- **Windows:** portal coverage limits development to 2022 (2021 needs a prior season), with conditional 2023–25. Two arms, `fixed` vs `adaptive`; adopt only if `adaptive` wins development by ≥ 0.01 MAE with a bootstrap upper bound ≤ 0.

## B11. Execution order

| Step | File | Output / guard |
|---|---|---|
| 0 | this file + `tier_map.csv` | F12 reconciled (B3.1). Write `tier_map.csv` and `predeclaration.sha256` |
| 1 | `archive/v12-round12/code/tests/test_v12.R` | Synthetic checks: γ-off = incumbent; recovery of known (γ0, γ1); the ±½ rows give the exact margin shift; s/p4home encoding; 2026 Pac-12 → G5; λ_γ → ∞ with μ = 0 reproduces off; `carry` uses only the final snapshot of the previous *included* season (2021 ← 2019); the chain starts at 0 in 2017; the bias function applies ×s (B3.1 guard). → `test_results_core.txt` |
| 2 | `archive/v12-round12/code/cfb_power_ratings_v12.R` | Core. Sources the Round 11 core; no edits to frozen files |
| 3 | `archive/v12-round12/code/cfb_v12_forward.R`, `code/tests/test_v12_forward.R` | Real-input checks with no outcome fits → `test_results_forward.txt` |
| 4 | `archive/v12-round12/code/scripts/run_round12_forward.R` | Refuses to run unless both test files start with PASS and the hash matches. Runs nested selection, dev predictions, the lock, conditional predictions and adversarial checks, then writes the freeze manifest. **Computes no gate.** |
| 5 | `archive/v12-round12/code/scripts/report_round12.R` | Verifies the freeze; Gates 0–4 → `promotion_gates.csv`, `REPORT.md` |
| 6 | `archive/v12-round12/code/scripts/prospective_round12.R` | Only if Gates 0–4 PASS: weekly pre-kickoff predictions, append-only, timestamped |
| 7 | `archive/v12-round12/code/scripts/gate5_round12.R` | Runs only when n ≥ 100 (B8) |
| 8 | `archive/v12-round12/code/scripts/market_benchmark_round12.R` | Post-freeze only; reads `cfb_data/betting_lines_2023_2025.rds`; never an input to any fit or gate |

## B12. Honest limitations and expected outcome (stated before any fit)

- **Expected outcome: NOT PROMOTED, most likely at Gate 2.**
  - **Bias looks reachable.** On the oriented metric, Round 11's venue-less, `zero`-prior version already removed −2.63 pts (inner 2018–19) and −3.24 pts (full development), with MAE −0.042 and −0.033 (F4, B3.1). Gate 3 (conditional |bias| from 3.44 down to ≤ 1.72) therefore looks reachable.
  - **MAE is the binding gate.** Gate 2 effectively needs about −0.073 MAE, roughly twice what Round 11 reached. Passing depends on the venue term and the `carry` prior adding MAE gain, mostly on week-1 games.
- **MAE is the wrong primary lens for this defect.** Even a perfect in-sample tier fix gains only −0.024 on 2023–25 (F8). The case for any tier fix is removing a known bias the market does not share (closing-line P4-vs-G5 residual +0.29, R10), not improving MAE.
- **Data scarcity.** γ is identified from 11–14% of games, 86% of them in weeks 1–4. The week-1 predictions rely entirely on μ.
- **Selection is not blind.** It sits on the same development eras as Round 10, Round 11 and v10_refined, and the incumbent was itself selected on 2019–22 evidence.
- **Gate 5 is weak.** It detects only gross misses (B8), and it cannot report before late 2027.
- **Metric definitions moved the headline numbers by up to 2.8 pts** in some seasons (F12, B3.1). Round 11 used a home-oriented residual. Every bias in this round is P4-oriented.

## B13. Amendments

None yet. Any amendment is appended here, dated and re-hashed, before the forward run.
