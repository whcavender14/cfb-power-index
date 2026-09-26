# Player data sourcing ("Statistical leaders")

| | |
|---|---|
| Source | CollegeFootballData `/stats/player/season`, via `cfbfastR::cfbd_stats_season_player(year, season_type = "regular", end_week = <ratings week>)`. One call per weekly run covers every team. |
| Where it runs | `R/publish/pull_player_stats.R`, called by `scripts/03_export_public_data.R` (skip with `CFB_PULL_PLAYERS=false`). Needs `CFBD_API_KEY`, which CI already provides to that step. |
| Stored as | `output/state/player_stats_<season>.rds` (not committed), with the week it covers. |
| Published as | `leaders` in each `public/data/v2/team/<slug>.json` (see `DATA_CONTRACT_V2.md`). |
| Week alignment | `end_week` = the ratings week, so the stats cover exactly the weeks in "Ratings through Week N". If the stored pull covers a different week, the exporter omits leaders rather than show mismatched numbers. |
| Selection rules | Passing: 1 player by passing yards. Rushing: top 2 by rushing yards. Receiving: top 3 by receiving yards. Sacks: top 3 by sacks. Interceptions: 1 player by interceptions. A player needs a positive value in the ranking stat. Ties: the second stat listed (TDs, TFL or return yards), then name. No player ratings, projections or weights. |
| What it is not | CFBD has no depth charts, starters or snap counts, so these are statistical leaders, not "key" or starting players. The page says so. |
| Checks | The exporter asserts every published value equals the pulled row. The validator checks the week stamp, list sizes and sort order (yardage may be negative, e.g. an interception returned for a loss). Stage 4 spot-check: Georgia, Boise State and Notre Dame against separate per-team CFBD calls, total difference 0. |
| Model impact | None. Player data is display-only and never enters the ratings or simulation. |
| EPA / success rate | Not shown. Neither is in the production model output (see `LIMITATIONS.md`). |
