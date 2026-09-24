# CFB Power Index: revised development folder

This is a clean, documented base for building the next version (V2) of the college-football power-rating model. It holds:

- the **current production model**, reproduced exactly;
- the frozen data that model needs;
- a pipeline that runs end to end;
- reusable evaluation code;
- documentation of every version tried so far.

The original working folder, `/Users/willcavender/Desktop/CFB Modeling`, is untouched. It is a complete historical archive, and the live website still deploys from it. Everything intentionally left behind is indexed in `config/legacy_paths.R` and `docs/legacy_file_manifest.md`.

**Start here**

| If you want to… | Read |
|---|---|
| Understand exactly how the current model works | [docs/MODEL_METHODOLOGY.md](docs/MODEL_METHODOLOGY.md) |
| See every version and experiment, and why each was kept or dropped | [docs/MODEL_HISTORY.md](docs/MODEL_HISTORY.md) |
| Know the data, APIs, credentials and feature engineering | [docs/DATA_SOURCES.md](docs/DATA_SOURCES.md) |
| Evaluate a new candidate the way the project always has | [docs/EVALUATION_PROTOCOL.md](docs/EVALUATION_PROTOCOL.md) |
| Know what changed in this cleanup, and the key lessons for V2 | [docs/MIGRATION_AUDIT_REPORT.md](docs/MIGRATION_AUDIT_REPORT.md) (see §4, "What You Need to Know Before Building Version 2") |
| Find a file that was not copied | [docs/legacy_file_manifest.md](docs/legacy_file_manifest.md) and `config/legacy_paths.R` |
| Know the website's JSON schema | [docs/DATA_CONTRACT.md](docs/DATA_CONTRACT.md) |

---

## 1. Purpose

The model rates every FBS team, 138 in 2026, in **points relative to an average FBS team**. It splits each rating into offense and defense. It uses those ratings to:

1. **Predict game margins:** `home margin = P_home − P_away + 3.07` (no HFA on neutral sites).
2. **Simulate the season:** 1,000 Monte Carlo seasons through `cfbseedR`, giving projected wins and conference-title, 12-team-playoff and national-title probabilities.
3. **Feed the public dashboard** at <https://whcavender14.github.io/cfb-power-index/>. The dashboard also compares model spreads with sportsbook lines, as a validation display only.

Betting lines are a **benchmark, never an input**.

## 2. Current methodology in one page

The production model is **`v5 / EB_features`**. It was selected in Round 4 using outcomes through 2022 and frozen on 2026-09-09.

1. **History.**
   - For each completed season from 2015 to 2025, a ridge regression on team-game points gives each FBS team's end-of-season offense (`o`) and defensive burden (`d`), plus a season home-field estimate.
   - The model is `points = μ + o_team + d_opponent + H·(±½)`.
2. **Preseason prior**, built separately for offense and defense.
   - Start with an OLS fit on last season's `o` and `d` plus a newly-promoted flag.
   - Improve it with a ridge regression on the features each team actually has:
     - offensive or defensive **returning production**;
     - **talent composite**, **blue-chip ratio** and **recruit count** (log transforms);
     - **coach tenure** and a **new-coach** flag.
   - Missing features are never zero-filled; each team uses the model for its own "regime" of available features.
   - Everything is fit only on earlier seasons (≤ 2022), and 2020 is excluded.
3. **Current season: one joint empirical-Bayes ridge solve.**
   - Each team's `o` and `d` are shrunk toward **1.12 × its prior** with precision **λ = 4**. Roughly, a team with *n* games gets n/(n+4) data weight, but the true weights come from the full schedule graph.
   - Only FBS-vs-FBS results that were **available before the Monday 00:00 UTC cutoff** count (a result is available 24 h after kickoff).
   - There are **no blend weights**. With zero games played, the rating equals the scaled prior.
4. **Output.**
   - `power = offense − defense`, centered on the FBS average.
   - An exact decomposition into prior and current-season contributions.
   - One global HFA of **3.07** points.

Full specification: [docs/MODEL_METHODOLOGY.md](docs/MODEL_METHODOLOGY.md).

## 3. Performance (walk-forward, no leakage)

| Split | Games | Model MAE | Notes |
|---|---|---|---|
| Development 2019, 2021, 2022 | 2,320 | **12.92** | Used to select the model; −0.317 vs the previous Round 3 model |
| Conditional 2023–2025 | 2,398 | **12.52** | Closing market 12.00 (**gap +0.52**); calibration slope 1.015; bias −0.04 |
| P4-vs-G5 games | 268 / 318 | — | **Underrates P4 by +5.6 (dev) / +3.4 (2023–25)**, the largest known defect |

Twelve rounds of challengers failed to beat it under the predeclared gates. See the history below and [docs/MODEL_HISTORY.md](docs/MODEL_HISTORY.md).

## 4. Version history (short)

| Version | Idea | Outcome |
|---|---|---|
| Legacy weekly, v2, v3 | Points ridge; component blends; nested validation | Superseded |
| v4 (Round 3) | Convex prior/current blend "B" | −0.108 vs v3; superseded |
| **v5 `EB_features` (Round 4)** | **EB ridge toward a talent/returning/coaching prior** | **Production** |
| v6 (Round 5) | Position RP, QB, efficiency/special-teams priors, multi-year prior | Not promoted |
| Round 6 | Conference/tier hierarchy, efficiency, state-conditional scale | −0.065 on 2023–25, but failed bias when HFA drifted |
| Rounds 7–10, vNext | Play-by-play efficiency (replace, recalibrate, ensemble) | Worse or no value; **efficiency exhausted** |
| Round 10 / v10_refined | Post-hoc P4/G5 correction | **Forward Gate 5 open; single look ≥ 2028-02-01** |
| Rounds 11–12 | P4/G5 tier term inside the solve | Big bias cut; MAE gain not significant |
| Side tests | Team HFA (rejected), FCS games in solve (small +), EPA challenger (rejected) | — |

## 5. Folder layout

```
Revised CFB Modeling/
├── README.md                     ← this file
├── config/
│   ├── paths.R                   ← EVERY file location (env-var overridable). Source first.
│   ├── production.R              ← frozen incumbent constants (hashes, λ, scale, HFA, simulation settings)
│   ├── legacy_paths.R            ← registry of files left in the old folders: legacy_path("key")
│   └── tier_map.csv              ← season-indexed P4/G5 map (Pac-12 = G5 from 2026)
├── R/
│   ├── model/
│   │   ├── cfb_power_ratings_vCurrent.R   ← model engine, VERBATIM from production (MD5 711d01aa…)
│   │   └── production_operations.R        ← v5_build(), prospective archiving, input verification
│   ├── simulation/               ← simulate_season.R (+ cfb_dynamic_playoffs.R, verbatim)
│   ├── publish/                  ← JSON exporters, betting-line helpers, top-30 graphic
│   └── evaluation/
│       └── evaluation_helpers.R  ← paired MAE, block bootstrap, P4-oriented bias, tier map
├── scripts/                      ← runnable entry points (run from the project root)
│   ├── 01_build_ratings.R
│   ├── 02_simulate_season.R
│   ├── 03_export_public_data.R
│   ├── 04_archive_prospective_snapshot.R
│   ├── run_weekly_pipeline.R
│   ├── verify_frozen_inputs.R
│   └── build_legacy_manifest.R
├── tests/                        ← 5 R test files; all pass
├── data/
│   ├── frozen/                   ← checksummed production inputs (DO NOT EDIT)
│   ├── reference/                ← teams, logos, market lines, incumbent predictions, 2026 snapshots
│   └── prospective/              ← write-once pre-kickoff prediction archives (evidence)
├── output/                       ← generated; safe to delete
├── docs/                         ← methodology, history, data, evaluation, audit, legacy manifest
└── archive_reference/            ← key historical reports + the locked Gate 5 materials
```

## 6. How the pieces interact

```
config/paths.R ─┬─► R/model/production_operations.R ──sources──► R/model/cfb_power_ratings_vCurrent.R
                │         reads data/frozen/* (MD5-checked)            (v3 helpers, v4 score solver, v5 prior)
                │
scripts/01_build_ratings.R ──► v5_build() ──► output/rankings/*.csv, output/state/production_ratings_*.rds
scripts/02_simulate_season.R ─► v5_build() + cfbseedR ─► output/state/simulations_2026_latest.rds
scripts/03_export_public_data.R ─► output/public_data/{ratings,simulations}.json   (schema: docs/DATA_CONTRACT.md)
scripts/04_archive_prospective_snapshot.R ─► data/prospective/predictions_<time>.csv (+ .md5, read-only)
R/evaluation/evaluation_helpers.R ─► compares any candidate with data/reference/incumbent_predictions/
```

**Key functions**

- `v5_build()`: ratings at a cutoff.
- `v5_prior()`: preseason prior.
- `v4_score_fit()`: the joint ridge solve.
- `v4_ratings()` / `v5_ratings()`: assembly and decomposition.
- `v4_predict()`: game margin.
- `v5_archive_upcoming()`: prospective archive.
- `v5_verify_frozen_inputs()`: input verification.
- `compare_to_incumbent()`, `block_bootstrap()`, `p4_oriented_bias()`: evaluation.

## 7. How to run it, start to finish

**Requirements**

- **R** 4.3 or later. CI uses R 4.4.3.
- **Packages:** `dplyr tidyr purrr tibble rlang Matrix quantreg jsonlite cfbfastR cfbseedR`.
  - Install `cfbseedR` from GitHub: `remotes::install_github("sportsdataverse/cfbseedR@4a1c78e184773c22da43c40a9eb999d23283297f")`.
  - The graphic also needs `ggplot2 ggimage magick`.
- **Live data:** a CollegeFootballData key in `CFBD_API_KEY`. Put it in `~/.Renviron`; never commit it.

Always run from this folder:

```bash
cd "/Users/willcavender/Desktop/Revised CFB Modeling"
```

1. Check that the frozen inputs are intact (about 5 s):

```bash
Rscript scripts/verify_frozen_inputs.R
```

2. Run the test suite:

```bash
for t in tests/*.R; do Rscript "$t" || break; done
```

3. Run the weekly production pipeline with live results (ratings → simulation → JSON):

```bash
CFB_REFRESH_SCHEDULE=true Rscript scripts/run_weekly_pipeline.R
```

4. Archive pre-kickoff predictions. Do this **every week, before the first kickoff**:

```bash
CFB_REFRESH_SCHEDULE=true Rscript scripts/04_archive_prospective_snapshot.R
```

The steps can also be run on their own:

```bash
CFB_REFRESH_SCHEDULE=true Rscript scripts/01_build_ratings.R
```

```bash
CFB_REFRESH_SCHEDULE=true CFB_CREATE_GRAPHIC=true Rscript scripts/01_build_ratings.R
```

```bash
CFB_REFRESH_SCHEDULE=true Rscript scripts/02_simulate_season.R
```

```bash
Rscript scripts/03_export_public_data.R
```

Offline smoke test: no API key, 20 simulations, and a cutoff inside the frozen schedule's horizon.

```bash
CFB_SIM_COUNT=20 CFB_AS_OF=2026-09-07T00:00:00Z Rscript scripts/02_simulate_season.R
```

**Notes**

- **Always refresh for current results.** Without `CFB_REFRESH_SCHEDULE=true`, the model uses the frozen 2026 schedule, which only has results through 2026-09-09. The build script then refuses to write weekly state, and the simulation refuses to run for later cutoffs. This is deliberate.
- **The live website is not deployed from here.** It still runs from the old repo's GitHub Actions workflow (`.github/workflows/site.yml`, Mondays at 09:00 UTC).

## 8. Assumptions and known limitations

- **The model sees only score margins.** It has no injuries, weather, QB news, line movement or play-by-play. This is the most likely source of the 0.5-point market gap.
- **One global λ = 4.** Early-season predictions are compressed: held-out slopes are above 1 in weeks 2–4.
- **One fixed HFA of 3.07.** Realized HFA drifts between seasons (2.2–3.1 in 2023–25).
- **FCS games are ignored in the ratings.** The simulation plays FCS opponents at a flat −25.
- **Feature history is "vintage unverified".** Portal and QB data are not used.
- **The P4-vs-G5 bias of +3 to +6 points** is uncorrected in production.
- **The simulation treats ratings as known and fixed**, with constant σ = 15.79. Season-outcome distributions are therefore too narrow.
- **The frozen design is 2026-only.** Rating 2027 needs a new feature pull and freeze.
- **The evaluation base is thin:** three or four development seasons, and a conditional period that has been examined repeatedly. Only prospective data is a clean test.

## 9. Recommended areas for improvement (V2)

Ranked by evidence versus cost; details in the audit report, §4.

1. **Start the forward record now.** Archive weekly pre-kickoff snapshots, and settle how the locked Gate 5 finds them.
2. **Plan the 2027 extension.** Pull 2027 features and teams, and keep the 2026 design reproducible.
3. **Add a P4/G5 tier term inside the ridge solve** (Rounds 11–12). Evaluate it on a longer development window, 2016–2022, with the oriented metric and the season-indexed map.
4. **Drift-aware HFA** (Round 6 Phase 5 design) and **early-season information-state scaling** (Round 6 Family E).
5. **FCS games in the solve** at weight 0.25–0.5, and a **multi-year score prior**.
6. **Re-examine the feature ridge grid.** Every 2026 regime picked λ = 0.1, the lowest value in the grid.
7. **Simulation:** draw ratings from their posterior each simulated season; estimate the FCS level; make σ depend on game state.
8. **New information sources** (QB status, injuries) only with dated, player-ID-resolved provenance.

Do **not** revisit, without a new idea:

- play-by-play efficiency as a replacement or big ensemble weight;
- variance matching or dispersion fixes;
- team-specific HFA;
- talent-deviation add-ons;
- flat post-hoc tier offsets.

## 10. Rules of the road

These rules kept the project honest.

- **Predeclare and hash before fitting.** Tune on development seasons only, then freeze.
- **Pair on identical game IDs.** Use season × week block bootstraps with text keys.
- **Stop at the first failed gate.** Do not retune after a failure.
- **Keep the market out of every model input.**
- **Never edit `data/frozen/`.** A new model gets a new design file and a new freeze.
- **New code gets its paths from `config/paths.R`.** Old files are located through `legacy_path()`.
