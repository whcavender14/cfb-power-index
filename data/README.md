# data/

| Folder | What | Rules |
|---|---|---|
| `frozen/` | Exact inputs of the frozen production model: `cfb_data_v3/raw_schedule_2015-2026.rds`, `cfb_data_v2/{talent,returning,coaches,portal}*.rds`, `outputs/round4/{design_frozen,features}.rds` | **Never edit.** The layout copies the relative paths stored in `design_frozen.rds`, and every file is MD5-checked on each build (`scripts/verify_frozen_inputs.R`). Files are read-only. A new model gets a new design, frozen in a new folder. |
| `reference/` | `teams_2025/2026.rds` (FBS membership, names, logos), `team_directory.rds` (logo URLs), `market/betting_lines_2023_2025.rds` (closing-line benchmark), `incumbent_predictions/` (EB_features walk-forward predictions: dev 2019/21/22 and cond 2023-25), `production_snapshots_2026/` (weekly production snapshots committed by CI, wk01-wk03) | Read-mostly. Add `teams_2027.rds` here next season. |
| `prospective/` | Write-once, read-only pre-kickoff prediction archives + `.md5` (currently only 2026-09-09) | Written only by `scripts/04_archive_prospective_snapshot.R`. **Never edit or delete**: this is the forward-evaluation evidence. |

Sources, transforms and provenance: `docs/DATA_SOURCES.md`. Large data left in the old folder (play-by-play, round caches): `docs/legacy_file_manifest.md`.

`incumbent_predictions/*.csv` were extracted from the old `outputs/round4/{development,conditional}_predictions.csv` (MD5 `2f40c181…` / `4d8e7bbb…`), keeping only `candidate == "EB_features"` rows and 21 columns. MAE: 12.9203 dev, 12.5177 cond.
