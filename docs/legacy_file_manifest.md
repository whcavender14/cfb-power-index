# Legacy file manifest

_Generated 2026-09-24 by `scripts/build_legacy_manifest.R` from `config/legacy_paths.R`. Edit the registry, not this file._

Everything below was **intentionally not copied** into this folder. Nothing was deleted: the old folders are
read-only archives. In code, never hard-code these paths; use `legacy_path("<key>")` from `config/legacy_paths.R`.

| Root | Location |
|---|---|
| `old` | `/Users/willcavender/Desktop/CFB Modeling` (original working folder; git repo) |
| `backup` | `/Users/willcavender/Desktop/CFB Modeling Backup` (2026-09-22 copy; the **only** place the archived round `code/` and `docs/` folders survive) |
| `external` | absolute path given in the table |

**Important:** in the old folder, `archive/<round>/code/` and `archive/<round>/docs/` are missing and 77 documentation symlinks
under `archive/*/results/artifacts/*.md` are broken. The copies in the Backup folder are intact.
Also, `outputs/round6` in the old folder is a broken symlink; the real files are in `CFB-Modeling-round6/outputs/round6`.

## Replaced production code

| Key | Root | Path | Contains | Why excluded | When a future model might need it | Status |
|---|---|---|---|---|---|---|
| `old_vcurrent_operations` | old | `cfb_vCurrent_operations.R` | Production operations API (v5_build, v5_archive_upcoming) with working-directory-relative paths. | Replaced by R/model/production_operations.R (identical math; configurable paths). | To diff against the new layer, or to run the unmodified production path. | present |
| `old_run_2026_rankings` | old | `run_2026_rankings.R` | Weekly ratings entrypoint + top-30 PNG function (contains a png_dir global-variable bug). | Replaced by scripts/01_build_ratings.R and R/publish/rankings_graphic.R. | It is still what GitHub Actions runs for the live site. | present |
| `old_cfb_simulation` | old | `cfb_simulation.R` | cfbseedR season simulation (1,000 sims, sigma 15.79, HFA 3.0685, FCS -25). | Replaced by R/simulation/simulate_season.R. | Still used by the live site's CI. | present |
| `old_weekly_refresh` | old | `scripts/weekly_refresh.R` | CI orchestration: ratings -> simulation (fail-soft) -> export. | Replaced by scripts/run_weekly_pipeline.R. | Still used by the live site's CI. | present |
| `old_restore_prepare_inputs` | old | `scripts/restore_pipeline_inputs.R` | Copies pipeline_inputs/ into the paths the model expects (also prepare_simulation_inputs.R builds that bundle). | Unnecessary: data/frozen/ already uses the manifest layout. | Only for the live CI job. | present |
| `old_pipeline_inputs` | old | `pipeline_inputs` | Portable CI bundle: frozen design, features, schedules, feature caches (+ unused weekly_seed/). | Copied (minus weekly_seed/) to data/frozen/; byte-identical. | If data/frozen is ever damaged. | present |
| `old_exporters` | old | `scripts/export_public_data.R` | JSON exporters (also scripts/export_betting_data.R, scripts/betting_functions.R). | Copied with path changes to R/publish/. | Diffing; live CI. | present |

## Live site & deployment

| Key | Root | Path | Contains | Why excluded | When a future model might need it | Status |
|---|---|---|---|---|---|---|
| `old_github_workflows` | old | `.github/workflows` | site.yml (Monday 09:00 UTC Aug-Jan refresh + GitHub Pages deploy) and check.yml (PR checks). | Deployment config for the live repo, not model code. | When V2 is promoted: update the live repo's workflow. | present |
| `old_web_dashboard_src` | old | `src` | React + TypeScript + Tailwind dashboard (Power Ratings, Season Simulations, Betting Analysis tabs; PNG export). | Front end, not model development; consumes docs/DATA_CONTRACT.md JSON. | Any change to what the site displays. | present |
| `old_web_build_config` | old | `package.json` | Web build files: package.json, pnpm-lock.yaml, pnpm-workspace.yaml, vite.config.ts, tsconfig.json, index.html, scripts/*.mjs, scripts/verify-clean-build.sh, tests/*.mjs. | Front-end tooling. | Building/deploying the site. | present |
| `old_public_data` | old | `public/data` | Published ratings/simulations/betting JSON, with week-01..04 archives for 2026. | Generated output (also in git history). | Historical record of what the site showed each week. | present |
| `old_deployment_copy` | old | `cfb-power-index-deployment` | An older snapshot of the whole site repo (fewer src files, older workflow). | Obsolete duplicate of the repo root. | Probably never. | present |
| `old_git_repo` | old | `.git` | Git history (23 commits on main), remotes origin + newrepo (github.com/whcavender14/cfb-power-index), research branches. | Version control of the old project. | Recovering any committed file version; see branch entries below. | present |
| `old_readme` | old | `README.md` | Public-facing overview. Several statements are inaccurate (see docs/MIGRATION_AUDIT_REPORT.md). | Superseded by README.md here. | Updating the live repo's README. | present |

## Historical models

| Key | Root | Path | Contains | Why excluded | When a future model might need it | Status |
|---|---|---|---|---|---|---|
| `v2_model` | old | `cfb_power_ratings_v2.R` | v2: component blend a(g)*efficiency + b(g)*preseason with games-played-bucketed regression weights. | Obsolete; superseded by v3/v4/v5. | Historical reference only. | present |
| `v3_model` | old | `cfb_power_ratings_v3.R` | v3: scores-based ridge + OLS preseason prior + calibrated blend; nested validation. Its helpers are embedded in vCurrent. | Obsolete as a model; functions already live in R/model/cfb_power_ratings_vCurrent.R. | Historical reference. | present |
| `legacy_weekly_functions` | old | `cfb_power_ratings_functions.R` | Older separate weekly workflow: points ridge with preseason prior from prior ratings + talent (also used EPA/PBP). | Not the production lineage. | Only if revisiting the pre-Round-3 weekly model. | present |
| `legacy_weekly_update` | old | `cfb_weekly_update.R` | run_sunday_update(): cached trailing-season fits + weekly PBP pulls for the legacy model. | Not the production lineage. | Same as above. | present |
| `v4_round3_code` | old | `cfb_power_ratings_v4.R` | Round 3 study code (also cfb_v4_operations.R, run_round3.R, report_round3.R, supplemental_round3.R, secondary_audit_round3.R, write_round3_report.py, README_v4.md). | Superseded; v4 functions are embedded in vCurrent. | Reproducing Round 3 exactly. | present |
| `v5_round4_code` | old | `cfb_power_ratings_v5.R` | Unannotated v5 (code-identical to vCurrent after whitespace/comment removal). Round 4 runners: run_round4.R, report_round4.R, supplemental_round4.R, write_round4_report.py, validate_v5_public.R. | Duplicate of R/model/cfb_power_ratings_vCurrent.R. | Re-running the Round 4 selection (run_round4.R develop/conditional). | present |
| `v5_round4_code_backup` | backup | `archive/v5-round4/code` | Archived Round 4 code incl. cfb_v5_operations.R shim (missing from the old root; tests/test_v5*.R and cfb_power_ratings_v6.R source it). | Historical. | Running old v5/v6 tests or Round 5 code. | present |
| `v6_round5_code` | old | `cfb_power_ratings_v6.R` | Round 5 challenger families (position RP, QB, efficiency prior, special teams, multi-year prior); runners run_round5.R, audit_round5.R, ablations_round5.R, acquire_round5.R, report_round5.R, validate_v6_public.R, port_legacy_tests_round5.py. | Not promoted. | Multi-year prior idea (best Round 5 dev MAE, -0.074) if revisited. | present |
| `old_version_tests` | old | `tests` | test_v4*.R, test_v5*.R, test_v6*.R, test_team_hfa.R (need the archived code on the search path). | Test historical code, not the production path. | Re-validating archived versions. | present |
| `round_dev_prompts` | old | `ROUND4_DEVELOPMENT_PROMPT.md` | Round 4 and Round 5 briefs (ROUND5_DEVELOPMENT_PROMPT.md). | Historical instructions. | Understanding why a round was designed as it was. | present |
| `team_hfa_code` | old | `team_hfa_experiment.R` | Team-specific HFA experiment (run_team_hfa.R, report_team_hfa.R, rank_team_hfa_diagnostic.R). | Rejected (gain 0.007 MAE). | If team HFA is ever revisited. | present |

## Research rounds

| Key | Root | Path | Contains | Why excluded | When a future model might need it | Status |
|---|---|---|---|---|---|---|
| `round6_workspace` | old | `CFB-Modeling-round6` | Round 6 worktree copy: v7* model files, run_round6*.R, freeze scripts, tests/test_v7*.R, outputs/round6/ (reports, frozen designs). | Not promoted (tier/conference hierarchy; +HFA-drift bias failure). | Revisiting hierarchical conference/tier shrinkage or Family E scaling. | present |
| `round6_reports` | old | `CFB-Modeling-round6/outputs/round6` | CONDITIONAL_REPORT.md, CALIBRATION_DECISION.md, DEVELOPMENT_REPORT*.md, ROUND6_PREDECLARATION.md, PHASE5_PREDECLARATION.md. | Historical. NOTE: the old outputs/round6 symlink is broken; this is the real location. | Round 6 details. | present |
| `round7_code` | backup | `archive/v7-round7/code` | JP+-style PBP efficiency challenger: EP models, SR/EPA opponent adjustment, forward scripts, tests. | Not promoted (+0.26 to +0.36 MAE worse). | Any PBP ingestion work (reuses the repaired scoreboard reader). | present |
| `round7_docs` | backup | `archive/v7-round7/docs` | REPORT.md, MODEL_SPEC.md, EPA_PROVENANCE.md, predeclaration + addendum. | Historical. | PBP data-quality lessons. | present |
| `round8_code` | backup | `archive/v8-round8/code` | Dispersion calibration, stronger EP, fumble text recovery, special teams (buggy). | Not promoted. | Fumble recovery parser if turnovers are revisited. | present |
| `round8_docs` | backup | `archive/v8-round8/docs` | REPORT.md, ROUND8_PREDECLARATION.md. | Historical. | Why variance matching fails. | present |
| `round9_code` | backup | `archive/v9-round9/code` | Efficiency + talent + score ensemble; learned HFA. | Not promoted. | Ensemble/stacking code. | present |
| `round9_docs` | backup | `archive/v9-round9/docs` | REPORT.md, ROUND9_PREDECLARATION.md. | Historical. | SD-ratio gate argument; HFA estimates. | present |
| `round10_code` | backup | `archive/v10-round10/code` | Cross-tier correction, opponent arm without home term, talent gate. | Not promoted. | Cross-tier corrections. | present |
| `round10_docs` | backup | `archive/v10-round10/docs` | REPORT.md, ROUND10_PREDECLARATION.md, v10_refined_* docs and Gate 5 amendment. | Historical (key docs copied to archive_reference/). | Gate 5 administration. | present |
| `round11_code` | backup | `archive/v11-round11/code` | P4/G5 tier random effect inside the ridge solve; market-gap autopsy. | Not promoted (on an unoriented bias metric; see docs). | If Round 11 is reopened under the oriented metric. | present |
| `round11_docs` | backup | `archive/v11-round11/docs` | REPORT.md. | Historical. | Same. | present |
| `round12_code` | backup | `archive/v12-round12/code` | P4/G5 gamma shift with carried prior inside the solve. | Not promoted at Gate 2. | Tier-term design; its test_v12.R design-matrix identity tests. | present |
| `round12_docs` | backup | `archive/v12-round12/docs` | REPORT.md, ROUND12_PREDECLARATION.md (+ sha256), tier_map.csv. | Historical (tier map copied to config/). | Template for the next predeclaration. | present |
| `vnext_epa` | backup | `archive/vnext-epa` | EPA challenger (code, docs, data incl. pbp_sample.csv and v10_refined python/CSVs). | Not promoted (worse MAE). | EPA ingestion code. | present |
| `fcs_inclusion` | backup | `archive/fcs-inclusion` | FCS games in the solve at weight 0.25/0.5/1 (code + REPORT.md). | Positive but small; not promoted. | A cheap V2 candidate (w = 0.25 passed the Round 4 rule on 2023-25). | present |
| `team_hfa_archive` | backup | `archive/team-hfa` | Team-HFA experiment code/tests/docs. | Rejected. | Team HFA. | present |
| `round_results_all` | old | `archive` | results/artifacts for every round (CSVs, RDS caches, logs). The code/ and docs/ subfolders that belong beside them are MISSING here (77 broken doc symlinks) and survive only in the Backup. | Generated research outputs (~700 MB). | Any numeric detail from a past round. | present |
| `round_outputs_links` | old | `outputs` | Compatibility symlinks outputs/roundN -> archive/.../results/artifacts (round6 link is broken; round11 is a real duplicate folder). | Links/duplicates. | Old scripts that expect outputs/roundN paths. | present |
| `uncertain_archive` | old | `archive/uncertain` | Web build snapshots, pnpm cache, .RData/.Rhistory, tsbuildinfo, DS_Store. | Junk / unknown provenance. | Never. | present |

## Git branches

| Key | Root | Path | Contains | Why excluded | When a future model might need it | Status |
|---|---|---|---|---|---|---|
| `git_round_history_doc` | old | `git:codex/round13-tier-carry:docs/PROJECT_CONTEXT_AND_ROUND_HISTORY.md` | Authoritative round decision record and governance rules (copied to archive_reference/). | Exists only on a branch. | git -C <old> show codex/round13-tier-carry:docs/PROJECT_CONTEXT_AND_ROUND_HISTORY.md | git object |
| `git_round6_branch` | old | `git:codex/round6-claude` | 13 Round 6 commits (phases 0-5). | Branch only. | Round 6 provenance. | git object |
| `git_round7_branch` | old | `git:codex/round7-pbp-efficiency` | v10_refined docs + Gate 5 amendment commits. | Branch only. | Gate 5 provenance. | git object |
| `signed_gate5_amendment` | old | `.claude/worktrees/objective-margulis-d74d1b/archive/v10-round10/docs/v10_refined_amendment_02_gate5.md` | The byte-exact SIGNED Amendment 2 (sha256 2f0c6064...). Backup/branch copies had the hash line filled in afterwards. | Copied to archive_reference/forward_validation_gate5/. | Verifying the Gate 5 hash chain. | present |

## Data

| Key | Root | Path | Contains | Why excluded | When a future model might need it | Status |
|---|---|---|---|---|---|---|
| `round4_development_results` | old | `archive/v5-round4/results/artifacts/development_results.rds` | Round 4 walk-forward component snapshots, 2019/2021/2022, all candidates (25 MB). | Large; regenerable with run_round4.R. | Re-scoring a new prior/solve on exactly the Round 4 snapshots (as the FCS study did). | present |
| `round4_conditional_results` | old | `archive/v5-round4/results/artifacts/conditional_results.rds` | Same for 2023-2025 (21 MB). | Large. | Same. | present |
| `round4_all_candidate_predictions` | old | `archive/v5-round4/results/artifacts/development_predictions.csv` | All 12 Round 4 candidates' game predictions (also conditional_predictions.csv). | EB_features rows extracted to data/reference/incumbent_predictions/. | Comparing to other Round 4 candidates (B, C4, Full...). | present |
| `round4_feature_provenance` | old | `archive/v5-round4/results/artifacts/FEATURE_PROVENANCE_MANIFEST.csv` | Row-level provenance of every raw feature record (+ team_features.csv, prior_coefficients.csv, nested_penalty_validation.csv, portal_event_ledger.csv, coaching_resolution.csv). | Large diagnostics. | Auditing or rebuilding the feature bundle. | present |
| `round4_prospective_dir` | old | `outputs/round4/prospective` | Where the LOCKED gate5_2026.R looks for incumbent pre-kickoff snapshots (only the 2026-09-09 file exists). | Copied to data/prospective/. | Gate 5 final look (on/after 2028-02-01). | present |
| `round9_10_dev_baseline` | old | `archive/v10-round10/results/artifacts/predictions.csv` | Rounds 9-10 game predictions incl. the incumbent on the 3,092-game 2018-2022 development set (+ game_table.csv). | Large; different development split from Round 4. | Matching a later round's 2018-inclusive development universe. | present |
| `v10_refined_outputs` | old | `archive/v10-round10/results/refined` | v10_refined predictions/corrections, python script, bootstrap and bias reports. | Research output. | Gate 5. | present |
| `pbp_2023` | old | `cfb_data/pbp_2023.rds` | Full CFBD play-by-play 2023 (87 MB; also pbp_2024.rds 97 MB, pbp_2025.rds 104 MB, pbp_live_2026.rds 32 MB). | Large; PBP has repeatedly failed to add value. | Any PBP/EPA/tempo feature work (e.g. the proposed Round 13 tempo probe). | present |
| `legacy_weekly_state` | old | `cfb_data/history_ratings_2023_2025.rds` | Legacy weekly-model state: games_20xx.rds, history_ratings, lambda_2026, ratings_2026_*, report_2026_wk01.html, talent_*. | Belongs to the non-production legacy model. | Only with the legacy weekly model. | present |
| `old_runtime_state` | old | `cfb_data` | Runtime cache: production_ratings_2026_*.rds (copied), simulations_2026_latest.rds, betting_schedule_2026.rds, betting_raw/, cfp_bracket_2026_latest.png. | Generated. | Last local simulation result. | present |
| `cfb_data_v2_caches` | old | `cfb_data_v2` | Raw source caches: schedule_2015-2026.rds, epa_tg_*, hist_rating_*, artifacts_*, team_directory (copied), talent/returning/coaches/portal (copied to data/frozen). | Mostly v2/v3-era caches. | Rebuilding features from raw provider pulls; 2014 data. | present |
| `cfb_data_v3_caches` | old | `cfb_data_v3` | raw_schedule_2015-2026.rds (copied to data/frozen) + v3 blend_/components_ caches and production_2026.rds. | v3 caches are obsolete. | Rarely. | present |
| `market_round3_4` | external | `/Users/willcavender/Documents/Codex/2026-09-09/i-have-attached-an-r-script/outputs/local_validation/market_predictions.csv` | CFBD latest-available lines export used for the Round 3/4 market benchmark (MAE 12.019). Outside both project folders. | Superseded by data/reference/market/betting_lines_2023_2025.rds (closing medians; MAE 12.00). | Reproducing the Round 4 market table exactly. | present |
| `preseason_csv_2026` | old | `cfb_preseason_2026.csv` | Unreferenced 2026 preseason table (no code reads it). | Unknown provenance. | Unknown. | present |
| `pbp_sample_csv` | old | `pbp_sample.csv` | 500-row PBP sample used by early vNext tests. | Superseded by full PBP files. | Rarely. | present |
| `talent_full_csv` | backup | `talent_full.csv` | 320-row talent table (2025-2026) present only in the Backup root. | Unreferenced. | Unknown. | present |
| `rating_graphics` | old | `ratings` | Top-30 PNGs (2026-09-07, 09-09) and cached team logos. | Generated output. | Never (regenerate with CFB_CREATE_GRAPHIC=true). | present |
| `prediction_summary_png` | old | `predictionsummaryphoto.png` | Unreferenced image. | Unknown purpose. | Never. | present |
| `backup_zip` | external | `/Users/willcavender/Desktop/CFB Modeling Backup.zip` | 1.2 GB zip (50,570 entries) made 2026-09-22. | Archive. | Disaster recovery. | present |

