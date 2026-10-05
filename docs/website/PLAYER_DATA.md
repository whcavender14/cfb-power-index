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

# /players/ leaderboards (Stage 1)

| | |
|---|---|
| Page | `/players/`: Passing, Rushing, Receiving, Defense, Kicking, Punting. Filters (conference, team, position group, class, qualified only), sort and category live in the query string. Selecting a row opens the player modal. |
| Files | `public/data/v2/players/leaders/<category>.json`, one per category, loaded only when that category is shown (`DATA_CONTRACT_V2.md`). Written by `scripts/export_player_leaders.R` (`R/publish/player_leaders.R`) after the site export, with no CFBD calls. |
| Box scores | The same CFBD season player stats pull as the team-page leaders (`player_stats_<season>.rds`, cut at the ratings week). |
| PPA | CFBD `/ppa/players/season` (Predicted Points Added: average per play and total, as CFBD reports them), pulled directly with httr2 by `R/publish/pull_player_ppa.R` (1 call). CFBD has PPA only for passers, rushers and receivers, and the endpoint has no week filter, so the exporter publishes it only if no game after the ratings week had kicked off when it was pulled; otherwise the column shows "—" and the page says why. Labelled "PPA/Play", never "EPA". |
| Success rate | CFBD `/stats/player/success` through the ratings week (1 call): passing and rushing plays and successful plays. No receiving success exists. |
| Usage | Rush share / pass share: CFBD player usage, from the pull `export_site_data.R` already makes for the usage files (saved as `player_usage_<season>.rds`; same kickoff check as PPA). |
| Class | CFBD roster `year` (1-4); the roster pull is saved as `rosters_<season>.rds`. CFBD does not record redshirts or fifth years. |
| Derived | Passer rating: the NCAA efficiency formula, computed in R. Rates (Cmp%, Y/A, Y/C, Y/R, FG%, punt average, success rate) are single divisions of published counts, done in the browser as in the player modal. Nothing else is derived. |
| Who is listed | FBS players above an activity floor per team game: passing any attempt; rushing 2 carries; receiving 1.25 catches; defense 3.25 tackles or 0.5 sacks plus interceptions; kicking any FG or XP attempt; punting any punt. |
| Qualified | `q` = the rate-stat qualifier per team game (team games: final games through the ratings week in `games.json`, FCS opponents included): passing 14 attempts, rushing 5 carries, receiving 2.5 catches, kicking 0.75 FG attempts, punting 3.6 punts (NCAA). The page shows qualified players by default. Defense has no qualifier. |
| Checks | The exporter asserts every published box-score value equals the pulled row. The validator checks the export stamp, the week, row shape, FBS team ids, the qualified flag against the counts, sort order, that PPA is absent when the pull does not line up, and that every listed player has a profile file. R test: `tests/test_player_leaders.R`. |
| Model impact | None. |

# Player profiles in the weekly run (Stage 1)

`scripts/export_player_profiles.R` now runs in the weekly export (`scripts/03_export_public_data.R`; skip with `CFB_PLAYER_PROFILES=false`) and covers every leaderboard player as well as the team-page leaders, usage lists and depth-chart starters. It also restores the depth-chart starters' athlete ids and stat lines, which the usage-file rewrite had dropped since 2026-09-26.

Cache: `data/reference/player_cache/` (committed by the workflow): completed seasons `games_<season>.rds` (2021-2025, copied from the earlier local pull), current-season weeks `games_<season>_wk<NN>.rds`, recruiting classes `recruits_<year>.rds`, team class rankings `recruit_teams_<year>.rds`, team talent `talent_<year>.rds` and portal years `portal_<year>.rds` up to the current season (since Stage 2: once a season is under way its class has signed and its portal windows have closed). A cached file is never pulled again. Weekly CFBD calls for profiles: game info (1) and the new week's box scores (1); the roster comes from the site export's pull.

Kickers and punters have profiles, but the box-score columns kept for the game log do not include kicking or punting, so their modal shows bio and career path only.

# Recruiting (Stage 2)

| | |
|---|---|
| Pages | `/recruiting/` (overview: the class in progress, best uncommitted recruits, the latest final class rankings, roster talent next to the CFPi+ rank) and `/recruiting/high-school/` (class selector 2018 to next year's class; views Team Rankings, Players, Commitments). Recruiting is a top-level nav item; What If?, Conferences and Model moved under More so the header fits on one line at 1024 px. |
| Team page | A Recruiting card: latest class rank, the three before it, 4-year average rank, blue-chip share, commits so far in the open class, roster talent rank. |
| Files | `public/data/v2/recruiting/`: `hs_<year>.json`, `teams_<year>.json`, `cards.json`, `dashboard.json` (`DATA_CONTRACT_V2.md`). Written by `scripts/export_recruiting.R` (`R/publish/recruiting.R`) after the player profiles in the weekly export (skip with `CFB_RECRUITING=false`). |
| Sources | CollegeFootballData `/recruiting/players` (high-school recruits), `/recruiting/teams` (team class rank and points), `/talent` (247Sports Team Talent Composite). All of CFBD's recruiting data is the 247Sports Composite; every page credits both. |
| Open class | CFBD publishes no team rankings for a class still being recruited (2027 returned 0 rows on 2026-09-30 and 2026-10-05). That class is shown unranked, ordered by 4- and 5-star commits, then average rating, then commits, and the page says the order is not a ranking. CFBD's `/recruiting/groups` "All Positions" `totalRating` is not a plain sum of ratings (Florida 2027: 6.34 for 25 commits) and is undocumented, so it is not used. |
| Derived (counts and averages of CFBD rows, done in R) | Per team and class: commits, 5/4/3-star commits, average rating of rated commits. 4-year average rank: mean of the four latest CFBD class ranks (blank unless all four exist). Blue-chip share: 4- and 5-star recruits among the team's rated commits in those four classes; it counts commitments in the recruiting data, not the current roster, and excludes transfers. |
| Calls | One-time: 14 (recruits 2026 and 2027, team rankings 2018-2027, the groups probe, talent 2026). Weekly: 2 (the open class's recruits and team rankings), plus 1 for the open portal year (Stage 3). Finished classes, rankings and talent are cached in `data/reference/player_cache`. |
| Checks | The validator checks export stamps, columns, star and rating ranges, national-rank order, FBS team ids, a profile file for every linked recruit, that each team's class counts equal the recruit rows, that the open class is unranked, and that every team card agrees with the class files. If the weekly export fails, the previous files are kept and restamped (their `pulled_at` shows the pull time). |
| Limits | Commitments carry no dates in CFBD, so there is no "recent commitments" feed; a commitment is not a signing. Only FBS programs are listed. Recruits link to the player modal only when they have a profile on the site. |
| Model impact | None. |

# Transfers (Stage 3)

| | |
|---|---|
| Page | `/recruiting/transfers/`: portal year 2021-2026 (the year whose window is open appears once CFBD has rows), views Team Rankings, Incoming, Outgoing, By Position. The overview gains a portal panel; the team-page Recruiting card gains an in / out tile. |
| Files | `public/data/v2/recruiting/portal_<year>.json` (`DATA_CONTRACT_V2.md`), written by `scripts/export_recruiting.R` with `R/publish/transfers.R`. |
| Source | CollegeFootballData `/player/portal` (247Sports transfer ratings and stars). One call per year; years up to the current season are cached, the open year costs 1 call a run. The frozen model input `portal_2014_2026.rds` is not read. |
| Rows | Every portal entry with an FBS program on at least one side, matched or not. Entries between two non-FBS programs are counted (`rows_total`) but not listed. |
| Matching (replaces the old rule) | The portal has no athlete id. An entry for year Y is matched by normalized name (lower case, accents and punctuation removed, Jr./Sr./II-V dropped) on the destination team's CFBD roster for Y, else on the origin team's roster or box scores for Y-1 (rosters cached per year, 2020-2025). Two players fitting one roster = ambiguous; destination and origin pointing at different players = conflict; neither = unmatched. Only a single consistent id is a match. The player modal's career path now uses the same matches (before: box scores only, so offensive linemen and non-playing transfers never matched). |
| Match rate (FBS-involved entries) | 2021 85.7% (1,504 of 1,754), 2022 88.2%, 2023 91.5%, 2024 92.6%, 2025 94.9%, 2026 97.1% (4,080 of 4,204: 3,170 by destination roster, 910 by origin; 15 ambiguous, 12 conflicting, 97 unmatched). The old box-score rule matched about 48-60% of all entries. Check: among matched 2026 entries, 96.3% have the same position group on the portal and the roster (most of the rest are EDGE-vs-LB labels or real position changes); 2021 88.1% (2021 portal labels QBs as DUAL/PRO). |
| CFPi+ Star Churn (derived, methodology v2; layout after The Slate Index's portal table; replaces v1's Net Transfer Value, a sum of transfer ratings) | For each FBS team and portal year: **In** and **Out** (withdrawn entries count for neither side; departures without a destination count as Out), **Churn** = In - Out, **Star² In** / **Star² Out** = the average of stars squared (5★ = 25, 4★ = 16, 3★ = 9, 2★ = 4) over the incoming / outgoing transfers that have a star rating, and **Star Churn** = Star² In - Star² Out, the ranking metric (ties: Churn, then team id). Stars are the 247Sports Composite's, via CollegeFootballData (the Slate Index uses On3's), so values will differ from theirs. Unrated transfers are left out of the averages. A team with no star-rated transfer on one side has no Star Churn (3 teams in 2026) and is ranked last. Labelled "Modelled, not official" wherever shown. Averages over a few players swing a lot: in 2026 the leader, Notre Dame, has 7 in and 15 out. Not comparable across years with different rated shares. |
| Checks | The validator recomputes every team's In, Out, Churn, star-rated counts, Star² In and Out, Star Churn and rank order from the published rows, checks match counts, that matched rows (and only they) carry an athlete id, that linked profiles exist, and that the team-card tile agrees with the latest portal file. |
| Model impact | None. |

# CFPi+ Player Ratings beta (Stage 4)

**Modelled, not official.** Method, gates and results: `PLAYER_RATINGS_PREDECLARATION.md`, `PLAYER_RATINGS_VALIDATION.md` (all four gates passed on the holdout), freeze and amendment A1: `PLAYER_RATINGS_FREEZE.json`.

| | |
|---|---|
| Where | Player modal badge (OVR ± band, Provisional / Estimated, Beta); `/players/?cat=ratings` (top players overall and by position, or every rated player on one team); `/players/ratings/` (methodology, validation numbers read from `top.json`). Team-page roster strip and risers are not built (deferred for review). |
| What is published | v1 rating of each 2026 FBS roster player in QB, RB, WR, TE, OL, DL, LB, DB, K, P, from evidence through the 2025 season (the validated use: a rating through a completed season for the next). 2026 games are not used in this beta. |
| Files | `players/ratings/top.json` (TE left out: its gain was +0.04, CI -0.09 to +0.16) and `players/ratings/team/<team_id>.json` (every rated player). Written by `scripts/export_player_ratings.R` (code `R/ratings/`) before the profiles; the profile export adds every top-list player; the weekly export then refreshes each row's `profile` flag. |
| Band | Half the OVR distance between mu - 1 SD and mu + 1 SD, measured before the scale's 30/99 limits (a display rule). |
| Calls | None in season. Once a year, when a new season starts, last season's history (5 calls) is pulled and cached. |
| Known properties | 85.7% Provisional on 2026 rosters (newcomers and backups have no production). 3,347 players (21.6%) share 65 ± 25: no production and no recruiting record give the same prior (a v1 property; changing it is v2). 18 players at the 99 cap (11 DL). Top end leans defensive: of 112 players at 95+, 92 are DL, LB or DB; WR and RB reach it least often per player. The G4 check compared group means only. |
| Checks | Validator: columns, 30-99, flags against the published rules, TE absent from the lists, every list row identical to its team file, counts matching, profile flags matching files. |
| Model impact | None. |

# Redshirt tag (inferred)

CFBD's roster has a class year 1-4 and no redshirt flag. On the 2026 rosters the class year behaves like eligibility years used (the 2025 high-school class splits 1,288 at year 1, which redshirted in 2025, and 1,669 at year 2). A player is tagged **RS** (shown "RS FR", "RS SO", ... and "Redshirt freshman" in the player card) when seasons since the recruiting class exceed the class year minus one, only for players with a high-school recruiting record (about 68% of rosters) and a class year of 1-4; everyone else gets no tag. Computed in R (`R/publish/class_flags.R`) for the leaderboards (`rs` column) and the ratings (`rs` field), and in the browser for the player card. Counts, 2026 rosters: 4,540 tagged of 15,473 rated players (1,172 RS FR). Limits: an inference from one season's data, not a CFBD fact; not checked for older cohorts against an outside source; JUCO players, walk-ons and most transfers have no recruiting record and get no tag; players with a changed or extra year of eligibility can be mislabelled.
