# Player features spec

## Goal
Add three sections to CFPi+: Players (leaderboards + ratings), and Recruiting (top-level). Display-only.

## Existing base (do not rebuild)
- public/data/v2/player/<athlete_id>.json (5,554 players: bio, game log, season sums, HS recruiting row, portal history).
- players.json search index; PlayerModal; team-page usage depth chart and 12 team leaders.
- Frozen: data/frozen/cfb_data_v2/portal_2014_2026.rds (18.9k transfers), talent_2014_2026.rds (talent composite, blue-chip ratio).
- CFBD via cfbfastR: cfbd_stats_season_player, cfbd_player_usage, cfbd_recruiting_player, cfbd_recruiting_team, cfbd_recruiting_position, cfbd_recruiting_transfer_portal, cfbd_stats_player_success, cfbd_team_roster.
- No cfbfastR wrapper for player PPA: call CFBD /ppa/players/season (and games if needed) directly with httr2.

## Stages (stop after each)
**Stage 0: Audit.** Confirm endpoints and field names against live CFBD responses; count calls per weekly run and per one-time backfill; measure coverage (players with stats, usage, PPA); report current build sizes. Propose file layout and budget lines.

**Stage 1: Leaderboards.** /players/ with categories Passing, Rushing, Receiving, Defense (+ Kicking if data allows). Full-league season pull cut at the ratings week. Qualifiers for rate stats (e.g. 15 pass att per team game). Filters: conference, team, position, class year, qualified toggle. Sortable; rows open PlayerModal. Include EPA/play from the player PPA pull. Lazy per-category JSON (top ~100 each, ~15-25 KB gz). Filters and sort live in query params (existing useQueryParam).

**Stage 2: Recruiting, high school.** /recruiting/ dashboard and /recruiting/high-school/ with tabs: Team rankings, Players, Commitments; class-year selector (include the incoming 2027 class). Uses cfbd_recruiting_player/team/position and talent data. Team page gets a Recruiting card (class rank, 4-yr avg, blue-chip %).

**Stage 3: Recruiting, transfers.** /recruiting/transfers/ with tabs: Team rankings (net), Incoming, Outgoing, By position. Portal has no athlete id: match by first+last name and origin school (existing method), report match rate, show unmatched rows honestly. Team ranks are OUR metric (sum/net of ratings in and out): label as derived.

**Stage 4: Ratings (beta).** Player overall 30-99, modelled. Design, predeclare and validate BEFORE any UI: see DECISIONS doc. Ship as Beta with confidence bands and a methodology section on /model/ or its own page. UI: rating badge in PlayerModal, Ratings tab on /players/ (top by position, best by team, risers), roster strip on team pages.

## Routes and nav
Add /players/, /recruiting/, /recruiting/high-school/, /recruiting/transfers/ to the pages map in Site.tsx. Nav gets Players and Recruiting as top-level items; fold Conferences and Model under a "More" menu so the header stays usable on mobile. Prerender and sitemap follow routes.

## Data files (proposed; confirm in Stage 0)
- players/leaders/<category>.json
- players/ratings.json (id, overall, band, position, provisional flag) separate from profile files
- recruiting/hs_<year>.json, recruiting/teams_<year>.json, recruiting/portal_<year>.json, recruiting/dashboard.json
Every file: schema_version, meta stamp, validator checks, budget line.

## Constraints
- Budgets in scripts/check_budget.mjs; CSS 19.9/20 KB. Keep JS chunks under 12 KB gz per page.
- Pulls that rarely change (recruiting classes, portal) are cached like player_games_<season>.rds; weekly job only refreshes current-season data.
- Attribute CollegeFootballData, and credit 247 Sports Composite where CFBD's recruiting data comes from it.
- Headshots and logos: reuse existing URLs/assets only.
