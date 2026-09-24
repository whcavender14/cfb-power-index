# Data sources, credentials, cleaning and feature engineering

## 1. External sources and APIs

| Source | Access | Used for | Credential |
|---|---|---|---|
| **CollegeFootballData (CFBD)** game info | `cfbfastR::cfbd_game_info(year, season_type)` | Schedules, scores, neutral site, FBS/FCS division, conference labels | `CFBD_API_KEY`. Without a key, `cfbfastR::load_cfb_schedules()` is used for schedules only. |
| CFBD betting lines | `cfbfastR::cfbd_betting_lines(year, week, season_type)` | Market benchmark; betting.json | `CFBD_API_KEY` |
| CFBD coaches | `cfbfastR::cfbd_coaches()` | Coach hire date and tenure | `CFBD_API_KEY` |
| CFBD transfer portal | `cfbfastR::cfbd_recruiting_transfer_portal()` | Audited but **not used** in the model | `CFBD_API_KEY` |
| CFBD team info | cfbfastR team metadata | `teams_<season>.rds`: FBS membership, names, logos for export | `CFBD_API_KEY` |
| SportsDataverse releases | `cfbfastR::load_cfb_team_talent()`, `load_cfb_returning_production()` (parquet on GitHub releases) | Talent composite, blue-chip ratio, recruit count; offensive/defensive returning production | none |
| CFBD play-by-play / drives | `cfbd_plays()`, `cfbd_drives()`, `load_cfb_pbp()` | Rounds 5–10 and vNext research only (not production) | `CFBD_API_KEY` |
| ESPN logo CDN | `https://a.espncdn.com/i/teamlogos/ncaa/500/<id>.png` | Graphic fallback only | none |

**Credentials.** No credentials are stored in either folder.

- The live site's GitHub Actions uses the repository secret `CFBD_API_KEY`.
- To use live data locally, set the key in `~/.Renviron` or the shell. Never commit it; `.Renviron` and `.env*` are git-ignored.

**Packages.**

- R 4.4.3 in CI; R 4.3.2 locally.
- dplyr, tidyr, purrr, tibble, rlang, Matrix, quantreg, jsonlite, cfbfastR, cfbseedR (CI pins sportsdataverse/cfbseedR@`4a1c78e184773c22da43c40a9eb999d23283297f`).
- Optional:
  - ggplot2, ggimage and magick for the graphic;
  - digest (Round 5);
  - xgboost (Rounds 7–8 EP models).

## 2. Local data in this folder

| Path | What | Origin | Size |
|---|---|---|---|
| `data/frozen/cfb_data_v3/raw_schedule_2015…2026.rds` | Frozen CFBD schedules/results; 2026 pulled 2026-09-09 | old `cfb_data_v3/` (= `pipeline_inputs/`) | 1.4 MB |
| `data/frozen/cfb_data_v2/talent_2014_2026.rds` | Talent composite, blue-chip ratio, n recruits, rank | SportsDataverse | small |
| `data/frozen/cfb_data_v2/returning_2014_2026.rds` | off/def/overall returning production shares | SportsDataverse | small |
| `data/frozen/cfb_data_v2/coaches_1989_2026.rds` | Coach seasons with hire dates (plus outcome fields that are **excluded**) | CFBD | small |
| `data/frozen/cfb_data_v2/portal_2014_2026.rds` | Transfer events (2021+) | CFBD | small |
| `data/frozen/outputs/round4/features.rds` | Feature bundle built by `v5_ingest()`: team-season features + provenance flags + portal ledger | Round 4 | 0.97 MB |
| `data/frozen/outputs/round4/design_frozen.rds` | Frozen design: candidate specs, fitted parameters, manifests | Round 4 | 16 KB |
| `data/reference/teams_2025.rds`, `teams_2026.rds` | CFBD team metadata (FBS membership, school, conference, logo) | old `cfb_data/` | 24 KB each |
| `data/reference/team_directory.rds` | Team directory with logo URLs (graphic only) | old `cfb_data_v2/` | 24 KB |
| `data/reference/market/betting_lines_2023_2025.rds` | Closing-line benchmark, 2,613 games: provider consensus or derived multi-book median; `home_spread`; no spread prices | Round 7+ ingest of CFBD `/lines` | 40 KB |
| `data/reference/incumbent_predictions/*.csv` | EB_features walk-forward predictions: dev 2019/21/22 (2,320) and cond 2023–25 (2,398) | Extracted from Round 4 `*_predictions.csv` (source MD5 `2f40c181…` dev, `4d8e7bbb…` cond) | ~0.9 MB |
| `data/reference/production_snapshots_2026/` | Committed weekly production snapshots, 2026 wk01–wk03 + latest (built by CI with live schedules) | old `cfb_data/` | 0.4 MB |
| `data/prospective/predictions_20260909T142134.csv` | The only pre-kickoff incumbent archive (+ `.md5`), read-only | old `outputs/round4/prospective/` | 0.2 MB |

Large data that stays in the old folder, such as play-by-play (≈ 320 MB) and round caches, is listed in `docs/legacy_file_manifest.md` and in `config/legacy_paths.R`.

## 3. Schedule cleaning (`read_schedule`)

1. **Normalize provider column aliases** (`id` → `game_id`, `home_team_id` → `home_id`, `home_classification` → `home_division`, `neutral` → `neutral_site`).
2. **Require these columns:** `game_id`, `season`, `week`, `season_type`, `start_date`, `neutral_site`, `home_id`, `away_id`, `home_division`, `away_division`, `home_points` and `away_points`.
3. **Derive the working fields:**
   - `kickoff` (UTC)
   - `neutral`
   - `home_fbs` / `away_fbs`
   - `period` (the Monday 00:00 UTC week bucket)
   - `available_at = kickoff + 24 h`
   - `final` (both scores finite, and `completed` if present)
4. **Stop with an error** on duplicate game IDs, unknown kickoff or neutral status, unknown division, or wrong season. **Never deduplicate silently.**
5. **Team games (`team_games`):**
   - each final game becomes two team-game rows (points for, points against, home indicator ±½);
   - FCS games are dropped for production (`fcs_weight = 0`).
6. **Conference membership** comes from the per-game schedule labels (`v5_membership`). A team with conflicting labels in one season gets `NA`.

Two conventions to remember:

- The **tier map** for P4/G5 analysis is `config/tier_map.csv`. It is season-indexed: Pac-12 is P4 through 2025 and G5 from 2026.
- The engine's `v4_graph()` has a hard-coded descriptive P4 list that includes the Pac-12. It is used only for diagnostics, never as a model input.

## 4. Feature engineering (`v5_ingest`, run once at the Round 4 freeze)

Each team-season (FBS IDs from that season's schedule) gets these features:

| Feature | Transform | Notes |
|---|---|---|
| `log_talent` | `log1p(talent_composite)` (NA if negative) | Strongest external block in Round 4 |
| `blue_chip_ratio` | raw fraction, checked to be in [0, 1] | |
| `log_recruits` | `log1p(n_recruits)` | |
| `off_returning`, `def_returning` | raw shares in [0, 1] | Defense is absent before 2017 and sparse through 2021 (47/130 FBS teams in 2021) |
| `log_tenure` | `log1p(years since hire, Aug-1 season boundary)` | Only a **unique** coach hired **before** the season's first FBS kickoff counts; ambiguous cases become NA |
| `new_coach` | 1 if hired on or after Aug 1 of the previous year | Same pre-cutoff rule |
| `unknown_QB` | always TRUE | No QB data; explicit metadata, not a predictor |

**Excluded on purpose**

- `overall_returning` and `n_returning`: ambiguous definitions.
- `is_estimated`: provenance only.
- `talent_rank`: redundant.
- **All coaching outcome fields** (wins, SRS, SP+, ranks): they would leak outcomes.
- **Portal aggregates:** only one pre-2023 forward season was available, and destination timing is unverified.

**Provenance screen (`v5_validate_features`)**

- Every row carries `feature_snapshot_id`, `vintage_status`, `leakage_risk_status`, `season_appropriate` and `known_post_cutoff`.
- **All historical rows are `historical_vintage_unverified`.** There is no verified publication date, and retrieval/file/scrape dates are never substituted.
- Rows that fail the screen keep their key, but their values become NA, so the team drops to a smaller regime or to the base prior.
- A market-column trip-wire (`v5_no_market`) and an outcome-column guard (`v5_matrix_guard`) protect every design matrix.

**Hashes**

- `features.rds` hashes to `f18013897d21334c74af3550b77842fe` (file bytes).
- `design_frozen.rds$feature_hash` is `6a7e0174…` (object hash).

## 5. Known data issues and gotchas

- **The frozen 2026 schedule stops on 2026-09-09.** Current results need `CFB_REFRESH_SCHEDULE=true` and CFBD access. Offline builds after mid-September are stale. `scripts/01_build_ratings.R` now refuses to write weekly state in that case.
- **CFBD play-by-play scoreboards are stale on administrative rows.** Rebuild them as a cumulative maximum and check the result against the official final (Round 7, Amendment 3). The 2013 play-type vocabulary differs from later years. Fumble rows need play-text parsing, and recovery is only 68% in 2025.
- **Market data:** 2,369 of 2,398 conditional "lines" are derived multi-book medians, not executable prices. There are no spread odds, so no ROI can be claimed. CFBD "latest available" does not guarantee a closing line. cfbfastR can also return a synthetic "home 0" line, which `select_market()` rejects.
- **Returning production** is season-indexed by the *entering* season. Its defensive coverage is poor before 2022.
- **Conference realignment:** 2024 had a two-team Pac-12, and the 2026 Pac-12 is a rebuilt G5 league. Always use the season-indexed tier map.
- **Datetimes read back from CSV are text.** Key on the text (`as.character`) and never on `as.numeric()`: that mistake broke Round 12's first bootstrap.
- **iCloud Desktop sync** can evict files ("dataless"). Slow first reads are rehydration, not a hang.
