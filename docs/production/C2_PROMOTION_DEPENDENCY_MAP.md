# Current C2 production promotion: dependency map (pre-edit audit)

- **Written:** 2026-09-26, before any production file was edited.
- **Audited revision:** `main` = `origin/main` = `e468b32`. This is the deployed production commit. There are no bot
  data commits after it, and no scheduled refresh has run in GitHub Actions yet: the repository's first workflow run
  was 2026-09-24, and all runs since then were push builds without the R refresh.
- **Model being promoted:** Current C2, research tag `c2-post-stage4-baseline` = `6a187ea`, file `R/c2/c2_current.R`
  with sha256 `8b4d9d41…`, used unchanged.

## 1. How production runs today

The job is `.github/workflows/site.yml` on `main`. It runs on a schedule (Monday 09:00 UTC, Aug–Jan) or on
`workflow_dispatch` with `refresh_data`. **A push only rebuilds and deploys the committed `public/data`; it does not
run R.**

1. `scripts/verify_frozen_inputs.R`: MD5 of the incumbent's frozen artifacts.
2. `scripts/run_weekly_pipeline.R`:
   - seeds `output/state` from `data/reference/production_snapshots_2026`;
   - runs `scripts/01_build_ratings.R`;
   - runs `run_season_simulation()`;
   - runs `scripts/03_export_public_data.R`.
3. `scripts/03_export_public_data.R` with `CFB_EXPORT_BETTING=true`, which also writes `betting.json`.
4. `pnpm test`, `pnpm logos`, `pnpm build`.
5. The bot commits `public/data`, and the site deploys to GitHub Pages.

## 2. Every place the incumbent (EB_features v5) is consumed

"Build" means the code calls the model. "Consume" means it reads model outputs.

| # | Location | Kind | What it takes from the incumbent | Promotion action |
|---|---|---|---|---|
| 1 | `scripts/01_build_ratings.R` | build | `v5_build()` → ratings tibble (power/off/def, `games_played`, `pre_power`, contribution columns, `feature_snapshot_id`); attrs `candidate`, `hfa`, `design_hash`, `feature_hash` → rankings CSV + metadata CSV + `production_ratings_<s>_{latest,wkNN}.rds` | **Route** through the model-selection layer; same schema. Add a guard so a week snapshot written by a different model is never overwritten. |
| 2 | `R/simulation/simulate_season.R` | build + consume | `v5_build()` ratings; attrs `as_of`, `training_ids` (leakage check); every FCS opponent at `PRODUCTION$sim_fcs_power` = −25; `sim_resid_sd` = 15.787 (incumbent RMSE); `sim_hfa`; the CFP resume spec (benchmark = 60th-best rating, σ, hfa, `team_power` including FCS) | **Route:** ratings from the selected model. Under C2, non-FBS teams get C2's own Stage 3 ratings instead of −25, σ = C2's frozen Round 16 σ, and hfa = C2's H. The logic is otherwise unchanged. |
| 3 | `scripts/run_weekly_pipeline.R` | orchestration | Seeds incumbent week snapshots and calls 01, the simulation and 03 | Unchanged. It is model-agnostic once 01 and the simulation route. |
| 4 | `R/publish/export_public_data.R` | consume | Snapshot `power_rating`, `off_rating`, `def_rating`, `pre_power`; previous-week compatibility on `candidate`/`design_hash`/`feature_hash`; `ratings.json` model = `"vCurrent / " + candidate`; **`simulations.json` model hard-coded `"vCurrent / EB_features + cfbseedR"`** | Take the simulation model name from the simulation's own metadata. Guard week archives against being overwritten by a different model. |
| 5 | `R/publish/export_betting_data.R` | consume | `snapshot$hfa` | Unchanged. C2's H is 3.06853968902663, identical to the incumbent's. |
| 6 | `R/publish/rankings_graphic.R` | consume (optional) | rank/team/power/off/def | Unchanged. |
| 7 | `src/PowerRatings.tsx`, `src/SeasonSimulations.tsx` (site copy) | consume | Methodology text names "vCurrent / EB_features", "15.7875 residual SD", "−25 FCS power" | Update the text to describe production C2. |
| 8 | `src/playoff.ts` `DEFAULT_MODEL` | consume (fallback) | `{hfa 3.0685, sigma 15.7875}`, used only if `simulations.json` lacks assumptions | Set to production C2's values, so a missing field never falls back to the incumbent's σ. |
| 9 | `docs/DATA_CONTRACT.md` | doc | "simulations identify EB_features" | Update the doc. |
| 10 | `.github/workflows/site.yml` | CI | R packages lack `data.table` and `httr2`, which C2 needs | Add both packages. No other workflow change. |
| 11 | `scripts/verify_frozen_inputs.R` | CI check | Incumbent frozen MD5s | Also verify the frozen C2 bundle and the C2 code files. |
| 12 | `config/production.R` | constants | Incumbent identity, simulation and CFP conventions | **Unchanged.** It stays the incumbent's identity record. Production model selection lives in a new `config/production_model.R`. |
| 13 | `scripts/04_archive_prospective_snapshot.R` | build (evidence) | `v5_build` + `v5_archive_upcoming` → `data/prospective` (locked incumbent Gate 5 evidence) | **Unchanged.** This is the incumbent benchmark's own forward record. |
| 14 | `R/forward/forward_models.R`, `scripts/forward/snapshot.R` | build (evidence) | Incumbent and Round 13 K plugins | **Add plugins** for Current C2 and frozen R15 C2. Rules, timing, guards, probability scale and incumbent/K plugins are unchanged. |
| 15 | `scripts/calibrate_cfp_ranking.R` | offline calibration | `v5_build` 2018–25 + −25 FCS → `cfp_rank_coef` | **Unchanged.** It is not part of production; the coefficients are kept (listed as debt). |
| 16 | `scripts/diagnose_cfp_selection.R` | offline | Simulation output | Unchanged (model-agnostic). |
| 17 | `tests/test_reproduce_incumbent.R` | test | `v5_build` reproduces the committed week-1 snapshot | **Unchanged.** It proves the incumbent stays reproducible. |
| 18 | `tests/test_public_export.R` | test | Incumbent seed snapshot schema | Unchanged. The new production test covers the C2 snapshot schema. |
| 19 | `tests/test_cfp_resume_ranking.R` | test | `PRODUCTION$sim_resid_sd` in a unit test of the resume math | Unchanged. |
| 20 | `data/reference/production_snapshots_2026/*_wk01–03,latest` | historical record | Incumbent weekly snapshots, seeded into CI state | **Unchanged.** These are historical publications. |
| 21 | `public/data/2026/week-01..03/*.json`, `public/data/*.json` | historical record / live | Published incumbent output | Historical week archives are **preserved** by the item-4 guard. The top-level files become C2 at the first refresh. |
| 22 | `R/evaluation/*`, Round 13–16 scripts, `data/reference/incumbent_predictions` | research/eval | Incumbent predictions as the comparator | Unchanged. |

## 3. What Current C2 needs that production lacks

- **Code** (all on `c2-refinement`; `main` is its ancestor with 0 commits of its own, so this is a fast-forward):
  - `R/c2/c2_current.R`;
  - the frozen helpers `R/round15/candidates/{data,c1,c2}.R`;
  - the play parsers `R/round15/prep/{fumble_parser,sr_history,passer_parser}.R`;
  - `R/round15/cfbd_client.R`.
- **Frozen 2026 season inputs.** These are the C1 2026 prior, the scale, the prior precisions, and C2's construction
  components (β, κ, FCS moments, ω, end-of-season fits through 2025, division pools, and the 2025 anchor).
  - Today they exist only in untracked caches: `output/dev/round15/cand/*.rds`, 14 MB `data.rds`, and Round 6 raw plays
    outside the repository.
  - Round 16 §9 requires that "The 2026 C1 prior and 2025 end-of-season inputs are computed by the frozen code. The
    forward build is committed and hashed before its first snapshot."
  - → Compute them once with the canonical code and commit them as `data/frozen/c2/`, with a checksum manifest.
- **Live 2026 data each week:**
  - the FBS schedule (already pulled);
  - the FCS-involved schedule, via CFBD `/games classification=fcs` with the Round 15 P1 mapping;
  - play-by-play for every completed week, via `cfbfastR::cfbd_plays`, the same source as the forward tool.
- **CI packages:** `data.table`, `httr2`.

## 4. Model-specific differences the adapter must handle

| Item | Incumbent | Current C2 (production) |
|---|---|---|
| FBS rating | `power_rating` | `power` (FBS-mean centred), `eff_off`, `eff_def` (higher def = worse: same convention) |
| Non-FBS teams | Not rated; −25 in the simulation | Rated by the Stage 3 system; first-game rating before a team's first game |
| Home field | 3.06853968902663 | Same value (`R15C$frozen_hfa`) |
| Win-probability σ | 14.94 (Round 16 all-development) / simulation 15.787 | 15.6500874177702 (Round 16 frozen `sigma.csv`, model C, all development), used for both the simulation and probabilities |
| `pre_power` | EB prior | C2's preseason rating: the no-games branch, `a`·C1 prior, FBS-centred |
| `prior/current/centering_contribution`, `feature_snapshot_id` | EB decomposition | Not defined for C2 → NA (the columns are kept for schema compatibility) |
| `games_played` | FBS games in fit | All games in the solve, FBS and non-FBS (C2 Stage 4 count) |
| `candidate` / `design_hash` / `feature_hash` | `EB_features` / design MD5 / feature hash | `C2_current` / bundle-manifest MD5 / `c2_current.R` MD5 |

## 5. Consequences decided in advance

- **Weekly change at cutover.** The first C2 week's `weekly_change` is null. The exporter refuses to compare snapshots
  from different models; this is existing behaviour, tested in `tests/test_public_export.R`.
- **Historical week archives are never replaced.** Past weeks are neither rebuilt nor re-labelled.
