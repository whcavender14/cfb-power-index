# Evaluation protocol: how the model has been judged, and how to judge V2

## 1. Principles

These rules were followed from Round 3 onward. They are the main reason the reported numbers can be trusted.

1. **Walk-forward only.**
   - Every prediction uses games available before that week's Monday 00:00 UTC cutoff, with results assumed known at kickoff + 24 h.
   - The preseason model trains only on earlier seasons.
   - `audit_fold()` asserts all of this.
2. **Frozen before scoring.**
   - Candidate definitions, grids and gates are written down (predeclared) and hashed before fitting.
   - Selection uses development seasons only. The design is frozen (`design_frozen.rds` plus MD5 manifests) before any later split is scored.
3. **Paired comparisons on identical game IDs.** A candidate and the incumbent are always scored on exactly the same games.
4. **The market is a benchmark, never an input.**
   - Lines are read only after predictions are saved and hashed.
   - `v5_no_market()` blocks market columns in every model input.
5. **Stop at the first failed gate.**
   - Do not compute or read later gates.
   - Do not retune after a failure. A new idea means a new predeclared round.
6. **Disclose grid-edge selections, execution errors and reruns.**
   - An execution error is a "Gate 0" integrity problem: fix the root cause and rerun the prescribed step.
   - Do not patch around an error to get a result.
7. **Preserve provenance.** Unknown historical feature values stay missing. They are never zero-filled.

The full governance text is in `archive_reference/PROJECT_CONTEXT_AND_ROUND_HISTORY.md`. `archive_reference/round_reports/R12_PREDECLARATION_template.md` is the most complete predeclaration to copy from.

## 2. Data splits

| Split | Seasons | Games | Status |
|---|---|---|---|
| Round 4 development | 2019, 2021, 2022 | 2,320 | Used to select the incumbent (optimistic for the incumbent) |
| Rounds 9–12 development | 2018, 2019, 2021, 2022 | 3,092 | 2018 needs an 80-row prior bootstrap (Round 11 note) |
| Conditional | 2023, 2024, 2025 | 2,398 | **Exposed repeatedly.** Only a calibration check, not a clean test. |
| Forward / prospective | 2026 onward | grows weekly | **The only untouched evidence.** Needs pre-kickoff snapshots. |

Universe: all completed FBS-vs-FBS games, regular season and postseason, overtime included. 2020 is excluded as an outcome season.

## 3. Metrics

These are implemented once, in `R/evaluation/evaluation_helpers.R`.

| Metric | Definition | Incumbent: dev (R4 split) | Incumbent: cond |
|---|---|---|---|
| MAE | mean \|pred − actual\| (home margin) | **12.920** | **12.518** |
| RMSE | | 16.268 | 15.787 |
| Bias | mean(pred − actual) | +0.517 | −0.043 |
| Correlation | cor(pred, actual) | 0.630 | 0.622 |
| Calibration slope | `lm(actual − HFA·site ~ pred − HFA·site)`; diagnostic only, **never force it to 1** | 1.054 | 1.015 |
| SD ratio | sd(pred) / sd(actual) | 0.598 | 0.614 |
| Straight-up | sign agreement (ties excluded) | 0.709 | 0.719 |
| P4-oriented bias | mean((actual − pred)·s); s = +1 for P4 home vs G5, −1 for G5 home vs P4 | **+5.62** (n = 268) | **+3.44** (n = 318) |
| Market MAE | closing median/consensus | — | **12.00** (model gap **+0.52**) |

**Uncertainty:** a paired Δ with a two-level bootstrap (`block_bootstrap()`).

- It resamples seasons (the "season" interval), then whole Monday-cutoff blocks within each sampled season (the "block" interval).
- Seed 9041, 2,000 replicates.
- Blocks are keyed on the cutoff as text.
- With 3–4 seasons, only 10–35 distinct season resamples exist, so the intervals are coarse and descriptive.

**Retired metrics:**

- **SD-ratio gate [0.85, 1.15].** For a calibrated forecast, the SD ratio equals the correlation (about 0.62–0.66, even for the market), so this gate can never pass (Round 9).
- **"Share of market disagreement" gates** (Round 11). They proved uninformative.

## 4. Gates used in recent rounds (template)

| Gate | Typical requirement |
|---|---|
| 0: integrity | Tests pass; the candidate with its new term turned off reproduces the incumbent exactly; adversarial leakage checks are unchanged; hashes verified |
| Arm rule | The selected hyperparameter strictly beats "off" on inner folds; grid edges disclosed |
| 1: effect size | Dev paired Δ ≤ a threshold (historically −0.25, then −0.08, then −0.055) |
| 2: uncertainty | Dev 95% upper bound (season × week blocks) ≤ 0 |
| 3–4: conditional | Only if 1–2 pass: calibration slope within [0.9, 1.1]; P4 bias no worse; season stability |
| 5: forward | Prospective, untouched data |

**Power reality.**

- The paired-Δ standard error on about 2,300 games is roughly 0.03–0.05 MAE.
- The minimum detectable effect at 80% power is about 0.08–0.11 (Round 6 power analysis).
- Most honest improvements available to this architecture (0.02–0.10) sit at or below that detection floor. **Plan V2 evaluations around this.** Options:
  - use more development seasons (add 2016–2018, rebuilding priors as Round 11 did);
  - use a forward test that pools seasons;
  - pre-specify a smaller effect together with a longer horizon.

## 5. Evaluating a V2 candidate with this folder

```r
source("config/paths.R"); source(PATHS$eval_helpers)
cand <- my_candidate_predictions            # data.frame(game_id, pred_margin), same 2,320 dev games
res  <- compare_to_incumbent(cand, "development")
res$candidate; res$incumbent               # MAE, RMSE, bias, slope, SD ratio, ...
res$paired                                  # Δ estimate + season and block 95% intervals
res$p4_bias                                 # P4-oriented bias for both models
```

- To generate walk-forward predictions, reuse the engine's machinery: `v4_components()`, then `v5_components()`, then `v5_fit_parameters()`, then `v5_evaluate()`.
- Or load the Round 4 snapshots with `v5_validation("development")`. They live in the old folder and are located through `config/legacy_paths.R`.
- A candidate that *extends* the incumbent should include a Gate 0 test showing it reproduces `data/reference/incumbent_predictions/` exactly when its new term is switched off.

## 6. Forward validation and Gate 5 (v10_refined)

**What is locked** (`archive_reference/forward_validation_gate5/`):

- **Candidate:** v10_refined = incumbent + `s·(2.356 + 1.831·p4_home)`.
- **Rule:** PASS if and only if |bias(v10_refined)| < |bias(incumbent)|.
- **Sample:** P4-vs-G5 games under the season-indexed map; kickoff at or after 2026-09-22T14:31:18Z; the 2026 and 2027 seasons pooled.
- **Minimum sample:** n ≥ 60. An extension into 2028 weeks 1–4 is allowed if n is short.
- **Timing:** one look, on or after **2028-02-01**. Before then the script prints counts only.
- **Evidence:** only md5-verified incumbent snapshots written **before kickoff**, taking the latest such snapshot for each game.
- **Consequence:** PASS promotes v10_refined; FAIL keeps the incumbent.
- **Hashes:** `gate5_2026.R` (sha256 `69bf5372…`) and the signed amendment (sha256 `2f0c6064…`) are verified by `v10_refined_amendment_02.sha256`.

**Operational problems to solve (not decided here):**

1. **Snapshots are not being written.**
   - The only incumbent snapshot is the one from 2026-09-09. With nothing newer, every Gate 5 game would be scored on week-2 ratings, and 2027 games would have no snapshot at all.
   - Run `scripts/04_archive_prospective_snapshot.R` every week before kickoffs, with `CFB_REFRESH_SCHEDULE=true`.
2. **The locked script reads snapshots from the old folder.**
   - `gate5_2026.R` hard-codes `setwd("/Users/willcavender/Desktop/CFB Modeling")` and `SNAPSHOT_DIR <- "outputs/round4/prospective"`.
   - Snapshots written here go to `data/prospective/`. Before the final look, either copy them (with their `.md5` files) into the directory the locked script reads, or write a documented amendment that changes only the location.
   - Changing the script changes its hash, so choose deliberately.
3. **The 2027 season needs a runnable incumbent.** The frozen design is 2026-only (see `docs/MIGRATION_AUDIT_REPORT.md`). Gate 5 requires the *same* frozen incumbent, so 2027 predictions need the 2026 design extended to 2027 without changing it. That means a documented feature/schedule ingest for 2027.
