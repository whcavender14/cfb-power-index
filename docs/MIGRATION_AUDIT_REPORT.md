# Migration and audit report

- **Date:** 2026-09-24
- **Old folder (read-only, unchanged):** `/Users/willcavender/Desktop/CFB Modeling`
  - 1.3 GB and about 2,640 files, not counting `.git`, a 143 MB Claude worktree copy and `node_modules`.
- **Also consulted (read-only):** `/Users/willcavender/Desktop/CFB Modeling Backup`. It is the only surviving copy of the archived round code and docs.
- **New folder:** `/Users/willcavender/Desktop/Revised CFB Modeling`, about 4 MB.

Nothing in either old folder was created, modified, renamed or deleted. Every file in the new folder falls into one of these groups:

- a verbatim copy (checksums verified);
- a path-adapted copy (differences described below);
- new code or documentation written for this folder.

---

## 1. How the old project fits together

```
                     (GitHub Actions, Mondays; still the live system)
.github/workflows/site.yml
   └─ scripts/restore_pipeline_inputs.R ── pipeline_inputs/ ──► cfb_data_v2/, cfb_data_v3/, outputs/round4/
   └─ scripts/weekly_refresh.R
        ├─ run_2026_rankings.R ── cfb_vCurrent_operations.R ── cfb_power_ratings_vCurrent.R  (v3 + v4 + v5 engine)
        │        └─ writes cfb_data/production_ratings_2026_{latest,wkNN}.rds, outputs/round4/current_2026_rankings.csv
        ├─ cfb_simulation.R ── scripts/cfb_dynamic_playoffs.R ── cfbseedR ──► cfb_data/simulations_2026_latest.rds
        ├─ scripts/export_public_data.R ──► public/data/{ratings,simulations}.json
        └─ scripts/export_betting_data.R (betting_functions.R) ──► public/data/betting.json
   └─ pnpm build (src/*.tsx React dashboard) ──► GitHub Pages

Research (run by hand, one "round" at a time):
   run_roundN.R / report_roundN.R / cfb_power_ratings_vN.R ──► outputs/roundN ─symlink─► archive/<vN-roundN>/results/artifacts
```

**Inputs, intermediates, outputs.**

- **Inputs:**
  - CFBD/SportsDataverse pulls (`cfb_data_v2/*.rds`, `cfb_data_v3/raw_schedule_*.rds`, `cfb_data/pbp_*.rds`, `teams_*.rds`);
  - the Round 4 frozen design and feature bundle.
- **Intermediates:** hashed caches (`cfb_data_v2/hist_rating_*`, `artifacts_*`, `cfb_data_v3/blend_*`, `components_*`, `outputs/roundN/cache/`).
- **Final outputs:**
  - weekly production snapshots;
  - `simulations_2026_latest.rds`;
  - the public JSON;
  - PNG graphics;
  - per-round reports and CSVs.

---

## 2. Classification of every meaningful file or group

The categories below are the ones you asked for. "→" gives the new location. Every excluded item has a key in `config/legacy_paths.R` and a row in `docs/legacy_file_manifest.md`.

### 2.1 Production model and pipeline

| Old path | Classification | Decision and reasoning |
|---|---|---|
| `cfb_power_ratings_vCurrent.R` | **Retained** (verbatim, MD5 `711d01aa…`) | → `R/model/`. The engine: annotated v5, code-identical to `cfb_power_ratings_v5.R`. Kept byte-identical so its hash stays meaningful. |
| `cfb_vCurrent_operations.R` | **Replaced** | → `R/model/production_operations.R`. Same math, with paths from `config/paths.R`. Adds `v5_verify_frozen_inputs()`; drops `v5_weekly_update()`. Proven identical: diff 0 against the old code, and it reproduces the committed wk01 snapshot exactly. |
| `run_2026_rankings.R` | **Replaced / reorganized** | → `scripts/01_build_ratings.R` + `R/publish/rankings_graphic.R`. Fixed the `png_dir` global-variable bug. Added a guard against writing stale weekly state. The graphic is now opt-in. |
| `cfb_simulation.R` | **Replaced** | → `R/simulation/simulate_season.R`. Same logic. Constants moved to `config/production.R`. Added `CFB_SIM_COUNT` / `CFB_AS_OF` for smoke tests. Removed an unused standings/seeds calculation and `View()`. |
| `scripts/cfb_dynamic_playoffs.R`, `scripts/betting_functions.R` | **Retained** (verbatim) | → `R/simulation/`, `R/publish/`. |
| `scripts/export_public_data.R`, `scripts/export_betting_data.R` | **Reorganized** | → `R/publish/`. Path-only changes. Team metadata now comes from `data/reference`. The `source` field reads `scripts/01_build_ratings.R`. |
| `scripts/weekly_refresh.R` | **Replaced** | → `scripts/run_weekly_pipeline.R`. |
| `scripts/restore_pipeline_inputs.R`, `prepare_simulation_inputs.R` | **Excluded: obsolete** | `data/frozen/` already mirrors the manifest layout. |
| `pipeline_inputs/` (minus `weekly_seed/`) | **Retained** as `data/frozen/` | 18 files, all MD5-verified against `design_frozen.rds`. `weekly_seed/` (legacy-model state) is **excluded: obsolete**. |
| `tests/test_public_export.R`, `test_betting_export.R`, `test_simulation_playoff_variance.R` | **Reorganized** | → `tests/`, with path changes only. All pass. |
| `docs/DATA_CONTRACT.md` | **Retained** (verbatim) | → `docs/`. |
| — | **New** | `config/paths.R`, `config/production.R`, `config/legacy_paths.R`, `config/tier_map.csv` (copied from Round 12), `R/evaluation/evaluation_helpers.R`, `scripts/04_archive_prospective_snapshot.R`, `scripts/verify_frozen_inputs.R`, `scripts/build_legacy_manifest.R`, `tests/test_reproduce_incumbent.R`, `tests/test_evaluation_helpers.R`, and all documentation. |

### 2.2 Data

| Old path | Classification | Decision and reasoning |
|---|---|---|
| `cfb_data_v3/raw_schedule_2015–2026.rds` | **Retained** → `data/frozen/cfb_data_v3/` | Required frozen inputs. |
| `cfb_data_v2/{talent,returning,coaches,portal}` | **Retained** → `data/frozen/cfb_data_v2/` | Required frozen inputs. |
| `outputs/round4/design_frozen.rds`, `features.rds` | **Retained** → `data/frozen/outputs/round4/` | Required frozen inputs. |
| `cfb_data/teams_2025.rds`, `teams_2026.rds`, `cfb_data_v2/team_directory.rds` | **Retained** → `data/reference/` | Membership and logos for export. |
| `cfb_data/betting_lines_2023_2025.rds` | **Retained** → `data/reference/market/` | The benchmark every round compares to. |
| `cfb_data/production_ratings_2026_*.rds` | **Retained** → `data/reference/production_snapshots_2026/` | This season's record; seeds `weekly_change`. The wk01 snapshot doubles as the reproduction fixture. |
| `outputs/round4/prospective/predictions_20260909T142134.csv` (+ .md5) | **Retained** → `data/prospective/` | Only pre-kickoff evidence. Read-only. |
| `outputs/round4/{development,conditional}_predictions.csv` | **Reorganized** | EB_features rows only → `data/reference/incumbent_predictions/` (0.9 MB vs 20 MB). The all-candidate files are **excluded: legacy/reference only**. |
| `outputs/round4/{development,conditional}_results.rds` (46 MB) | **Excluded: legacy/reference only** | Walk-forward snapshots. Reachable via `v5_validation()` → `legacy_path()`. |
| `cfb_data/pbp_2023–2025.rds`, `pbp_live_2026.rds` (≈ 320 MB) | **Excluded: legacy/reference only** | PBP has repeatedly added little. Needed only for PBP or tempo work. |
| `cfb_data_v2/` other caches (`schedule_*`, `epa_tg_*`, `hist_rating_*`, `artifacts_*`) | **Excluded: generated output / obsolete** | v2/v3-era caches. |
| `cfb_data_v3/blend_*`, `components_*`, `production_2026.rds` | **Excluded: generated output** | v3 caches. |
| `cfb_data/games_*`, `history_ratings_*`, `lambda_2026`, `ratings_2026_*`, `report_2026_wk01.html`, `talent_*` | **Excluded: obsolete** | Legacy weekly model state. |
| `cfb_data/simulations_2026_latest.rds`, `betting_schedule_2026.rds`, `betting_raw/`, `cfp_bracket_2026_latest.png` | **Excluded: generated output** | Regenerated by the pipeline. |
| `cfb_preseason_2026.csv`, `pbp_sample.csv`, `predictionsummaryphoto.png` | **Excluded: obsolete / unknown provenance** | Nothing reads them. |
| `ratings/` (PNG graphics, logos) | **Excluded: generated output** | Regenerate with `CFB_CREATE_GRAPHIC=true`. |
| Round 3/4 market export (`~/Documents/Codex/2026-09-09/.../market_predictions.csv`) | **Excluded: legacy/reference only** (external) | Superseded by the closing-line file. |

### 2.3 Historical models and research

| Old path | Classification | Reasoning |
|---|---|---|
| `cfb_power_ratings_v2.R`, `_v3.R`, `cfb_power_ratings_functions.R`, `cfb_weekly_update.R` | **Excluded: obsolete** | Superseded. The v3 helpers are already inside the engine. |
| `cfb_power_ratings_v4.R`, `cfb_v4_operations.R`, `*_round3.*`, `README_v4.md` | **Excluded: legacy/reference only** | Round 3. Its functions are embedded in the engine. |
| `cfb_power_ratings_v5.R` | **Excluded: duplicate** | Code-identical to vCurrent. |
| `run_round4.R`, `report_round4.R`, `supplemental_round4.R`, `write_round4_report.py`, `validate_v5_public.R`, `README_v5.md`, `ROUND4_DEVELOPMENT_PROMPT.md` | **Excluded: legacy/reference only** | Needed only to rerun the Round 4 selection. The reports' substance is in `docs/` and `archive_reference/`. |
| `cfb_power_ratings_v6.R`, `cfb_v6_operations.R`, `*_round5.*`, `validate_v6_public.R`, `port_legacy_tests_round5.py`, `ROUND5_DEVELOPMENT_PROMPT.md` | **Excluded: obsolete** (not promoted) | Summarized in MODEL_HISTORY. |
| `team_hfa_experiment.R`, `run_team_hfa.R`, `report_team_hfa.R`, `rank_team_hfa_diagnostic.R` | **Excluded: obsolete** (rejected) | Summarized. |
| `tests/test_v4*`, `test_v5*`, `test_v6*`, `test_team_hfa.R` | **Excluded: legacy/reference only** | Test archived code. Several were already broken in the old folder because `cfb_v5_operations.R` is missing there. |
| `CFB-Modeling-round6/` (155 MB: a full worktree copy plus Round 6 code and outputs) | **Excluded: legacy/reference only** | Round 6. `CONDITIONAL_REPORT.md` was copied to `archive_reference/`. |
| `archive/` (727 MB of per-round `results/artifacts`) | **Excluded: generated output** | The key reports were copied from the Backup to `archive_reference/round_reports/`. |
| `outputs/` (symlinks, plus a 12 MB duplicate `round11/`) | **Excluded: duplicate** | — |
| `archive/uncertain/` | **Excluded: obsolete** | Build snapshots, RData, caches. |
| Backup `gate5_2026.R` + v10_refined docs | **Retained (reference)** → `archive_reference/forward_validation_gate5/` | The locked forward test must stay runnable. The script is verbatim, and its hash is verified. |
| Git branch `codex/round13-tier-carry:docs/PROJECT_CONTEXT_AND_ROUND_HISTORY.md` | **Retained (reference)** → `archive_reference/` | The project's decision record. It existed only on a branch. |

### 2.4 Web, deployment and tooling

| Old path | Classification | Reasoning |
|---|---|---|
| `src/`, `index.html`, `package.json`, `pnpm-lock.yaml`, `pnpm-workspace.yaml`, `vite.config.ts`, `tsconfig.json`, `scripts/*.mjs`, `scripts/verify-clean-build.sh`, `tests/*.mjs`, `public/` | **Excluded: legacy/reference only** | The React dashboard consumes the JSON contract but is not model code. The live site keeps running from the old repo. |
| `.github/workflows/` | **Excluded: legacy/reference only** | The live CI. It must be updated in the old repo when V2 is promoted. |
| `cfb-power-index-deployment/` | **Excluded: duplicate** (older) | — |
| `README.md` | **Replaced** | Contains inaccuracies; see §3. |
| `CFB Modeling.Rproj`, `LICENSE` | **Replaced / retained** | New `Revised CFB Modeling.Rproj`. `LICENSE` (MIT, 2026, whcavender14) was copied verbatim. |
| `.Rproj.user/`, `.pnpm-store/`, `.DS_Store`, `.claude/` | **Excluded: obsolete** | Local tool state. `.pnpm-store/v11/index.db` is even tracked in git. |

---

## 3. Problems found in the old folder

None of these were fixed in the old folder: it is read-only by instruction.

1. **Archived round code and docs are missing from the old folder.** `archive/<round>/code/` and `archive/<round>/docs/` exist only in `CFB Modeling Backup`, and 77 documentation symlinks are broken. The old root's round files (for example `cfb_power_ratings_v2–v6.R`) were restored by git at 08:46 on 2026-09-24, but the untracked archive code was not.
2. **Broken references.**
   - `outputs/round6` points to `/Users/willcavender/Desktop/CFB-Modeling-round6/…`, which no longer exists; the folder was moved inside `CFB Modeling`.
   - `README.md` links to `archive/README.md`, which exists only in the Backup.
   - `tests/test_v5*.R` and `cfb_power_ratings_v6.R` source `cfb_v5_operations.R`, which is missing from the old root.
   - `git worktree list` shows two prunable worktrees.
3. **The public README is inaccurate in several places:**
   - It describes a 90/10 → 20/80 prior/data blend with a tuned handoff rate. That is Round 3's B model; production is the EB joint solve.
   - It says the "top 4 seeds are P5 champions ranked by power rating". The simulation actually seeds a 12-team field from simulated standings.
   - It quotes "calibration slope 0.97, SD ratio 0.80". The measured values for 2023–25 are 1.015 and 0.614.
4. **Hard-coded absolute paths.**
   - The engine's legacy `cfb_config()` default points to `/Users/willcavender/Desktop/CFB Modeling/cfb_data_v2`. Production never reaches it, because `v4_config()` overrides it; it was left verbatim to preserve the engine hash.
   - `gate5_2026.R` calls `setwd()` into the old folder. It was left verbatim because it is hash-locked.
   - The Round 3/4 market file lives under `~/Documents/Codex/`.
5. **The design's code-manifest check is disabled.** Its recorded MD5 for `cfb_power_ratings_v5.R` predates a refactor. The schedule and feature checks still run.
6. **No prospective snapshots since 2026-09-09.** Nothing automates them, and CI cannot write them. Forward evaluation is starving (see §4).
7. **The frozen 2026 schedule ends at 2026-09-09.** An offline rebuild silently produces week-1 ratings labelled as the current week, and overwrites that week's snapshot. The new `01_build_ratings.R` guards against this.
8. **A Gate 5 amendment copy differs from its hash.** The signed text (sha256 `2f0c6064…`) survives only in `.claude/worktrees/objective-margulis-d74d1b/…`. The Backup and branch copies have the hash line filled in afterwards. The signed copy is in `archive_reference/`.
9. **Duplicates:** about 540 duplicate-content groups, mostly `archive/v5↔v6` artifacts, `archive/uncertain` web builds, and `CFB-Modeling-round6` copies of root files.

---

## 4. What You Need to Know Before Building Version 2

1. **The production model is simple, and it has been hard to beat.**
   - It is one sparse ridge regression on points, with each team's offense and defense shrunk (λ = 4) toward a scaled (×1.12) preseason prior. That prior comes from last season plus talent, returning production and coaching.
   - Twelve rounds of alternatives produced no promotion.
   - **Any V2 should be an extension of this solve that reproduces it exactly when switched off (Gate 0)**, not a rebuild.
2. **Honest headroom is small.**
   - Incumbent MAE is 12.52 on 2023–25; the closing line is 12.00.
   - Game-level residual SD is about 16. A well-calibrated forecast is limited to a correlation of about 0.62–0.66.
   - Realistic structural gains are 0.02–0.10 MAE. The minimum detectable effect on about 2,300 games is roughly 0.08–0.11.
   - **Design evaluations with enough data:** more dev seasons, pooled forward seasons, and pre-specified effect sizes.
3. **The largest fixable defect is P4-vs-G5 bias.**
   - The incumbent underrates P4 teams against G5 by +3.4 (2023–25) to +5.6 (dev), and by +5.6 in the 2026 interim. The market does not share this bias.
   - Terms inside the solve work mechanically. Round 12 cut bias from 5.6 to 0.8, and Round 11 on the corrected metric cut it by 2.6–3.2.
   - MAE gains so far are not significant. Post-hoc flat offsets overshoot because the bias drifts.
   - **Always use the P4-oriented metric and the season-indexed tier map (Pac-12 = G5 from 2026).**
4. **Play-by-play efficiency is exhausted as a replacement or a big ensemble weight** (Rounds 7–10, vNext).
   - At most, it is a cheap additive term worth about 0.03.
   - If PBP is reused, reuse Round 7's scoreboard repair and the Round 8 fumble parser.
5. **Do not rescale dispersion.**
   - The ratio sd(pred)/sd(actual) ≈ 0.6 is correct shrinkage, not a defect.
   - Variance matching added +1.7 MAE.
   - The SD-ratio gate is retired.
6. **HFA drifts between seasons:** 2.19, 2.95 and 3.08 realized in 2023–25; the strength-adjusted value is about 2.6–3.0.
   - A static location term failed Round 6's out-of-sample bias test.
   - A drift-aware (expanding-window) HFA is designed but untested (Round 6 Phase 5).
   - Team-specific HFA is worthless (−0.007).
7. **Early-season behavior is the other weak spot.**
   - Held-out slopes are above 1 in weeks 2–4: the model is compressed early.
   - Round 6's state-conditional scale fixed this out of sample.
   - The feature regressions all chose the lowest ridge λ in the grid (0.1): a grid-edge result worth re-examining.
8. **Cheap candidates with some evidence behind them:**
   - FCS games in the solve at weight 0.25–0.5 (cond −0.05 to −0.08);
   - a multi-year score prior (Round 5, dev −0.074);
   - drift-aware HFA;
   - an early-season scale;
   - a tier term inside the solve.
   - Each needs a fresh predeclaration, because 2023–25 has already been inspected for most of them.
9. **2023–25 is no longer a clean test.** Only prospective data is.
   - Start writing weekly pre-kickoff snapshots now (`scripts/04_archive_prospective_snapshot.R`, with a live schedule).
   - Without them, the locked v10_refined Gate 5 will score stale week-2 ratings and have no 2027 evidence.
   - Also decide how Gate 5's locked script will find snapshots written in this folder (EVALUATION_PROTOCOL §6).
10. **The frozen design cannot rate 2027.**
    - Features, schedules and assertions stop at 2026.
    - Before next August, plan a 2027 feature pull (`v5_ingest` logic), a documented extension of the frozen incumbent (needed for Gate 5 continuity), and a new `teams_2027.rds`.
11. **Feature provenance is "historical vintage unverified".**
    - Talent and returning-production history may contain revisions made after the fact.
    - Portal and QB data were not usable.
    - A V2 that wants QB or portal signals needs a player-ID-resolved, dated source first.
12. **Process rules that saved the project from false positives. Keep them:**
    - predeclare and hash before fitting;
    - pair on identical game IDs;
    - use season × week block bootstraps keyed on text cutoffs;
    - stop at the first failed gate;
    - disclose grid-edge selections;
    - never let market data touch the model.
    - The two worst mistakes on record were a mis-oriented bias metric (Round 11) and `as.numeric()` on text dates (Round 12). `R/evaluation/evaluation_helpers.R` now encodes the correct versions, with tests.
13. **Operational must-knows:**
    - The live site still runs from the **old** repo's GitHub Actions: `run_2026_rankings.R` → `cfb_simulation.R` → exporters.
    - Promoting a V2 means porting it there, or pointing CI at a new repo built from this folder.
    - The simulation holds ratings fixed within a season and uses a constant σ = 15.79 and FCS = −25. It ignores rating uncertainty, so season-outcome spreads are too narrow. That is a separate, easy improvement.

---

## 5. Verification performed for this migration

| Check | Result |
|---|---|
| MD5 of all 19 frozen inputs (18 data files + the engine) vs `design_frozen.rds` manifests and production constants | all match (`scripts/verify_frozen_inputs.R`) |
| New operations layer vs old code, `v5_build(2026)` at 2026-09-07 and 2026-09-14 (old code run on a scratch copy) | identical: max abs diff 0 over 27 numeric columns; identical attributes |
| New layer vs committed wk01 production snapshot (built by CI) | identical (diff 0) |
| Evaluation helpers vs published numbers (MAE, slope, P4 bias, Round 4 bootstrap intervals) | exact reproduction |
| `tests/` (5 R test files) | all pass |
| Offline end-to-end pipeline (ratings → 20-sim simulation at a 2026-09-07 cutoff → JSON export) | runs; the simulation correctly refuses a stale schedule at today's cutoff |
| Prospective snapshot script (written to a scratch directory) | writes a read-only CSV + MD5 in the same schema as the 2026-09-09 archive |
| Gate 5 script and signed amendment sha256 | match `v10_refined_amendment_02.sha256` |
| All 68 legacy-registry paths | present (git entries resolve on branches) |
