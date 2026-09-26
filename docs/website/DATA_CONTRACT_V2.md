# CFPi+ page datasets: `public/data/v2` (schema version 2)

Written by `R/publish/export_site_data.R`, called from `scripts/03_export_public_data.R` in the weekly pipeline (same CI step as the version-1 files, and committed with them). The exporter reads only pipeline outputs: the production ratings snapshot, the simulation result, `data/reference/teams_<season>.rds`, and the committed week archives. It never sources the model. The browser only displays these values.

The version-1 files (`public/data/{ratings,simulations,betting}.json`, `docs/DATA_CONTRACT.md`) are unchanged and still feed `/simulations/`, `/betting/` and the PNG exports.

Validation: the R exporter stops on inconsistent data (for example, if its aggregates disagree with cfbseedR's own `overall` summary). `scripts/validate_site_data.mjs` then runs as the first step of `pnpm build` and in `pnpm test`, so bad data fails the build and nothing deploys.

## Common `meta` block (every file)

| Field | Type | Meaning |
|---|---|---|
| `schema_version` | 2 | |
| `season` | int | |
| `model` | string/null | `vCurrent / <candidate>` from the ratings snapshot (e.g. `vCurrent / C2_current`) |
| `ratings_week` | int/null | Latest completed week in the ratings. Shown as "Ratings through Week X" (0 = preseason) |
| `ratings_as_of` | UTC string/null | Model information cutoff (Monday 00:00 UTC) |
| `ratings_updated_at` | UTC string/null | When the ratings were built. Shown as "Last updated" |
| `sim_status` | `available` \| `unavailable` | `unavailable` if the simulation failed, is missing, or came from a different model than the ratings |
| `sim_count`, `sim_updated_at`, `sim_as_of` | | null when unavailable |
| `current_week` | int/null | Earliest week with an unplayed game (the default week on the Games page) |
| `movement_compared_to_week` | int/null | Week that rank and rating changes compare against (the previous point in `history.json`), or null when none exists |
| `movement_source` | `published` \| `reconstructed` \| null | Where that comparison week's ratings come from (see `history.json`) |
| `hfa`, `sigma` | number/null | Home field and the simulation's margin SD, as used by the simulation |
| `exported_at` | UTC string | Identical in every file of one export. The validator rejects mixed exports |

## `index.json`: homepage and rankings

`teams[]`, one row per FBS team:

| Field | Source |
|---|---|
| `team_id`, `slug` | metadata. `slug` is the URL key (`/teams/<slug>/`) |
| `rank` | Order by power, ties by team id (the same order as `scripts/01_build_ratings.R`) |
| `rank_prev`, `rank_change` | From the previous week in `history.json` (published CFPi+ archive, else the labelled reconstruction). `rank_change = rank_prev − rank`, so positive means up |
| `power`, `off`, `def`, `preseason_power`, `games_played` | Production snapshot `power_rating`, `off_rating`, `def_rating`, `pre_power`, `games_played` |
| `rating_change` | `power − previous archive power` (same rule as `rank_change`) |
| `off_rank`, `def_rank` | National rank of off (desc) and def (asc; lower is better) |
| `wins`, `losses`, `conf_wins`, `conf_losses` | Final games the simulation treated as known (kickoff before the cutoff), including FCS opponents |
| `proj_wins`, `p_playoff`, `p_conf`, `p_champ` | Per-sim means (below) |
| `resume_rank`, `sos_played` | Résumé rank (strength of record; ties: fewer losses, harder schedule played, team id) and mean opponent rating so far. See `resume.json` |
| `sos`, `sos_rank`, `sor`, `sor_rank` | Full-season schedule strength and strength of record (`DERIVED_METRICS.md`); ranks among FBS, 1 = hardest / best |

`top_games[]`: up to 6 scheduled games of `current_week`, ordered by `quality` (same row shape as `games.json`).

## `teams.json`

`teams[]`: `team_id, slug, team, mascot, abbreviation, conference, color, alt_color, logo, logo_dark` (from `teams_<season>.rds`). The site tries the mirrored logo `logos/<team_id>.png` first, then `logo`, then a monogram.

## `games.json`

`games[]`, every game the simulation used (FBS vs FBS and FBS vs non-FBS):
`game_id, week, kickoff (UTC), time_tbd, neutral, conference_game, home_id, away_id, home_team, away_team, home_fbs, away_fbs, home_conference, away_conference, status ('final' | 'scheduled'), home_points, away_points, spread_home, win_prob_home, sim_home_win, quality, in_ratings`.

`in_ratings` = the result had entered the ratings (final and available, i.e. kickoff + 24 h, before the ratings cutoff). A game can be `final` (kickoff before the cutoff, so the simulation treats it as known) but not yet `in_ratings`.

- `final` means final with kickoff before the ratings cutoff (what the model has seen). Scores are only set for final games.
- Projections (`spread_home`, `win_prob_home`, `sim_home_win`, `quality`) are only set for scheduled games. A completed game never shows today's ratings as if they were a pregame prediction.
- Definitions are in `DERIVED_METRICS.md`.

## `playoff.json`

- `format`: text of the implemented rules (auto bids, ranking, seeding, source function).
- `teams[]`: `team_id, proj_wins, p_conf, p_playoff, p_auto, p_at_large, p_bye (seed 1–4), p_host (seed 5–8), p_qf, p_sf, p_final, p_champ, mean_seed (among seasons in the field), seed_dist[12]`.
- `representative_field`: `{sim, sims_with_identical_field, seeds:[{seed, team_id, bid:'auto'|'at-large', conf_champ}]}`.

## `team/<slug>.json`

`{meta, team (teams.json row), summary (index.json row), schedule (games.json rows for the team), wins_dist, record_dist, resume, seed_dist, playoff}`

- `wins_dist[w]` is the share of simulations ending with `w` regular-season wins. Conference title games are not simulated: cfbseedR names the conference standings leader champion, and `sim$games` holds only regular-season and CFP games. (`sim$wins_scope` says the wins include conference championships; the simulation output shows they do not.)
- `record_dist`: `[{wins, losses, count}]`, raw simulation counts of each final regular-season record. The exporter and the validator both check that the counts sum to `sim_count` and that the mean of `wins` equals `proj_wins`.
- `resume`: `sos_played, sos_all, sos_remaining, sor` with FBS ranks, and `best_win` / `worst_loss` (`{game_id, opp_id, opp, opp_fbs, opp_rank, loc, pts, opp_pts}` or null), judged by the opponent's current rating.
- `leaders` (or null): `{through_week, source: "CollegeFootballData", passing[≤1], rushing[≤2], receiving[≤3], sacks[≤3], interceptions[≤1]}`. Each entry is `{athlete_id, player, position}` plus the raw season totals: passing `passing_completions, passing_att, passing_yds, passing_td, passing_int`; rushing `rushing_car, rushing_yds, rushing_td`; receiving `receiving_rec, receiving_yds, receiving_td`; sacks `defensive_sacks, defensive_tfl, defensive_tot`; interceptions `interceptions_int, interceptions_yds, interceptions_td`. Ranked by the first stat (must be > 0), ties by the second, then name. Source: `R/publish/pull_player_stats.R` (one `cfbd_stats_season_player(year, "regular", end_week = ratings week)` call per weekly run, saved as `output/state/player_stats_<season>.rds`). Leaders are published only when that file covers exactly the ratings week; the exporter asserts every value equals the pulled row, and the validator checks the week stamp, the category sizes and the order. Display only, never a model input.
- `playoff` is the team's `playoff.json` row, without `seed_dist`.

## `history.json`: CFPi+ rating history

- `points[]`: `{week, label, as_of, source}` in order. `source` is `preseason` (the snapshot's `pre_power`: C2's no-games rating from the frozen prior), `reconstructed`, or `published`. The last point is always the published current week.
- `teams{team_id}`: `{power[], rank[], off[], def[]}`, aligned with `points` (null where a value does not exist, e.g. preseason offense/defense). Ranks are recomputed within each point, ordered by power then team id.
- Sources, for each week before the current one: a committed v2 week archive published by the same model wins; otherwise a row from `data/history/c2_reconstructed_<season>.csv` whose `design_hash` and `feature_hash` equal the live snapshot's. A week with neither is absent. Nothing is interpolated.
- Reconstruction (`scripts/history/reconstruct_c2_history.R`): re-runs the unchanged production entry point `c2_production_build()` at a past Monday cutoff on the cached schedule and play-by-play of the live run. C2 only uses games whose result was available before the cutoff, so this is the rating it would have published then, apart from any later CFBD data corrections. The script first rebuilds the latest published cutoff and refuses to write unless every team matches exactly (week 3, 2026: 138 teams, max difference 0). The CSV also holds each cutoff's non-FBS ratings, needed for the "What changed" projections.
- 2026: preseason and weeks 1–2 reconstructed (CFPi+ went live at week 3; weeks 1–2 were published by EB_features and are never mixed in), week 3 published.

## `changes.json`: what changed

`{meta, compared_to_week, compared_to_source, window_start, window_end, teams[]}`. Each team: `{team_id, off_change, def_change, games[]}`. A game is listed when its result entered the ratings in the window (available at or after the previous cutoff and before this one). Each game has `{opp_id, opp, opp_fbs, opp_rank_prev, loc, pts, opp_pts, proj_margin, vs_projection, text}`. `proj_margin` is from the comparison week's ratings (team − opponent + home field, 0 at neutral sites); `text` is a fixed template filled in R. Rank and rating changes are in `index.json`.

## `resume.json`: résumé ranking

`{meta, method{metric, benchmark, tiebreaks, proposal}, teams[]}`; each team `{team_id, resume_rank, sor, sos_played, sos_played_rank, wins, losses, games, predictive_rank, best_win, worst_loss}`. The validator checks that ranks are 1..N, that consecutive ranks follow the approved order (SOR desc, losses asc, schedule played desc, team id asc), and that both ranks agree with `index.json`. The predictive rank is carried only for side-by-side display; the two are never combined.

## `scenario.json`: What-if data (lazy-loaded on `/whatif/` only)

`{meta, n, game_ids[], team_ids[], team_games[], layout, data}`. `data` is base64 of: for each remaining game (`game_ids` order, = the `scheduled` games in `games.json`), `ceil(n/8)` bytes with one bit per simulation, 1 = home team won (sim s is bit `s % 8` of byte `s / 8`, lowest bit first); then three blocks of `n_teams × n` bytes: seed (0 = not in the field), regular-season wins, flags (8 = conference title; low 3 bits = CFP exit round, 5 = champion). `team_games` is each team's regular-season game count (11, 12 or 13), used for expected losses. Week 3, 2026: 684 KB, 186 KB gzipped. The validator decodes it and requires the no-pick aggregates to equal `playoff.json` (playoff, conference title, title, projected wins) and each game's home-win share to equal `sim_home_win`.

## `conferences.json`

`conferences[]`: `{slug, name, kind ('Power 4' | 'Group of 6' | 'Independents'), is_conference, team_ids[], n, avg_power, median_power, top25, best_rank, avg_rank (among real conferences), exp_playoff, sos_avg, nonconf_wins, nonconf_losses, nonconf_fbs_wins, nonconf_fbs_losses}`. Membership is `teams_<season>.rds` `conference`, never a hard-coded list. `exp_playoff` = sum of the members' `p_playoff` (checked by the exporter and the validator; all groups sum to 12). FBS independents form one group, flagged `is_conference: false`.

## `<season>/week-NN/index.json`

A weekly copy of `index.json` plus `nonfbs[]` (`{team_id, team, power}`, the model's non-FBS ratings that week). It is the published source for `history.json`. As with the v1 archives, a week already published by a different model is kept.

## Sizes (week 3, 2026; raw / gzip)

| File | Size |
|---|---|
| `index.json` | 61 KB / 12 KB (homepage, rankings, teams, changes, conferences) |
| `teams.json` | 42 KB / 6 KB (every page, for names and logos) |
| `games.json` | 398 KB / 33 KB (Games, What if) |
| `playoff.json` | 34 KB / 5 KB |
| `history.json` | 20 KB / 8 KB (grows ~5 KB a week) |
| `changes.json` | 50 KB / 8 KB |
| `resume.json` | 52 KB / 8 KB |
| `conferences.json` | 5 KB / 1 KB |
| `scenario.json` | 684 KB / 182 KB (What if only, lazy) |
| `team/*.json` | ~9 KB / ~2 KB each |

Budgets: `PERFORMANCE.md`. Per-simulation data is published only in `scenario.json`, packed, for the What-if page.
