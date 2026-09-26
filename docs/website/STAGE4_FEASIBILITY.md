# Stage 4 feasibility: player data and the scenario simulator

Both gates were checked before writing any UI. Nothing described here is built yet.

## 1. Player analysis ("Key players" on team pages)

**Status: built (approved 2026-09-26) as "Statistical leaders" on team pages, as recommended below.** Spot-check against separate per-team CFBD calls for Georgia, Boise State and Notre Dame: every displayed value equal (total difference 0). Pipeline: `R/publish/pull_player_stats.R`, run by `scripts/03_export_public_data.R` (skip with `CFB_PULL_PLAYERS=false`).

**Original verdict: not buildable from current project data. Buildable with one new pipeline pull (needs your approval).**

| | |
|---|---|
| **Data available** | Nothing structured. The project has no player statistics, rosters, snap counts or starter flags. Player names appear only inside play-by-play text (`plays_*.rds`, `play_text`), which the C2 success-rate code reads. Parsing names and stats from that text is unreliable: an earlier parser recovered only 38% of fumbles. The transfer-portal file (`data/frozen/cfb_data_v2/portal_2014_2026.rds`) has names, positions and star ratings for transfers only, with no statistics. |
| **Data missing** | Season player statistics; team rosters; any "starter" or "important player" designation; snap counts. |
| **What the source offers** | CFBD `/stats/player/season` (cfbfastR `cfbd_stats_season_player`): per player, per team, cumulative passing (comp/att/yds/TD/INT), rushing, receiving, defensive (tackles, TFL, sacks, QB hurries, passes defended), interceptions, kicking, punting and returns. Probe on 2026-09-26: Alabama returned 49 players, e.g. QB Keelon Russell 57/83, 764 yds, 4 TD; DL Devan Thompkins 3 sacks. `/roster` (cfbfastR `cfbd_team_roster`) gives position, jersey, class. `/player/usage` gives play-share usage. **CFBD has no depth charts, no starters and no snap counts**, so "important" can only mean "statistical leader". |
| **Export changes needed** | (a) A new pull in the weekly pipeline: one `cfbd_stats_season_player(year, end_week = <ratings week>)` call for the season (the site already needs `CFBD_API_KEY` in CI). `end_week` keeps the stats aligned with "Ratings through Week X"; without it the stats include games played after the cutoff. (b) The exporter picks leaders per team with fixed rules and writes them into `team/<slug>.json`. (c) The validator checks each shown number against the pulled table. This is a data pull outside the model; the model code is unchanged. |
| **Recommended approach** | Call the section **"Statistical leaders"**, not "Key players", because the data cannot say who starts or matters most. Fixed rules only: offense = passing-yards leader (with comp/att, yds, TD, INT), top 2 rushers (car, yds, TD), top 3 receivers (rec, yds, TD); defense = top 3 by sacks (with TFL, tackles), top by interceptions (INT only if ≥ 1). Show the "through Week X" stamp and "Source: CollegeFootballData". No rankings or projections. Verification when built: spot-check 3 teams against CFBD's own team pages and assert every displayed value equals the pulled row. |

## 2. Scenario simulator ("What if?")

**Status: approved and built at `/whatif/` (2026-09-26)** with the thresholds below. Checks after building: no picks = published odds (also enforced by the validator); two pick sets compared against a direct filter of the simulation in R. Texas/Illinois/UCLA road wins leave 28 seasons, and one Oklahoma win at Georgia leaves 264. Every displayed figure matched in both.

**Original verdict: feasible and light. Recommended to build after your review.**

Measured on the live week-3 simulation (1,000 seasons) with a prototype export (scratch only, not committed):

| | |
|---|---|
| **Data available** | `sim$games` holds every simulated game result per simulation (888 regular-season games × 1,000, plus CFP games). `sim$standings` holds per simulation and team: seed, wins, conference title, CFP exit round. Everything the page needs already exists in the simulation output. |
| **Data missing** | Nothing for the listed outputs (CFP odds, conference title, bye, seed distribution, expected record). Not possible: conditions on a margin ("wins by 10+"), on a conference title game (none is simulated), or on real-world results after the ratings cutoff that change ratings. |
| **Export changes needed** | New file `public/data/v2/scenario.json`, written by the exporter, lazy-loaded only on the What-if page. Layout: for each of the 628 remaining games, one bit per simulation (home team won); for each of 138 FBS teams and 1,000 sims, one byte each for seed (0 = out), wins, and conference title + exit round packed together. |
| **Size** | 492,500 bytes of packed data (78.5 KB game bits + 414 KB team block). Gzipped 155 KB; Brotli 136 KB. GitHub Pages may not compress a `.bin` file, so the plan is base64 inside JSON: 657 KB on disk, **172 KB gzipped over the wire**. It shrinks each week as games are played. |
| **Filter time** (Node 26, full recompute of all 138 teams) | No conditions: 0.78 ms; 1 condition: 0.40 ms (453 qualifying sims); 3 conditions: 0.28 ms (279); 5 conditions: 0.08 ms (85). Parsing the file is the only visible cost, well under 100 ms. |
| **Correctness checks already run** | No conditions: all playoff, bye, conference, title and projected-win values equal the published `playoff.json` exactly (max difference 0). Five conditions: the browser filter selected the same 49 simulations as a direct filter in R, and every playoff probability matched (differences only from 4-decimal rounding). The prototype caught a bit-order mismatch (R's `packBits` puts the first sim in the lowest bit), which the real reader will use. |
| **Recommended approach** | Build it as specified: pick winners of any remaining games (by week or team); recompute CFP, conference title, bye, seed distribution and expected record from qualifying sims only; state the count of qualifying sims; shareable URL `?pick=<game_id>:<home|away>,...`. No simulation engine in JS; the page only filters stored outcomes. |
| **Reliability threshold (proposed)** | With 1,000 sims each condition roughly halves the pool (five coin-flip games leave ~31). Proposal: **warn below 100 qualifying sims** (a 50% estimate is then ±10 points at 95%) and **show counts only, no percentages, below 25**. Zero qualifying sims: say the scenario never happened in the simulation. Raising the simulation count to 5,000 would cut noise but touches the production simulation config (your decision; the file would grow about 5×). |

## 3. What to approve

1. Player data: add the CFBD season-stats pull to the pipeline and build "Statistical leaders"? (Changes CI and uses the API key; the model is untouched.)
2. Scenario simulator: build it with the thresholds above?
3. Résumé rankings: see `RESUME_PROPOSAL.md`.
