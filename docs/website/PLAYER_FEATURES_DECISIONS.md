# Player features: decisions and ratings design

## Decisions (user, 2026-09-29)
1. Ratings are MODELLED, not official. Labelled as such everywhere. OL and special teams are rated too but flagged "Estimated".
2. Player PPA comes from a direct httr2 pull of CFBD player PPA; within the user's API limit (still log call counts).
3. Recruiting is a top-level nav item, separate from Players.

## Stage 0 decisions (user, 2026-10-04: "use your recommendations")
4. Leaderboards list every FBS player above a small activity floor (not a national top 100), so team and conference filters work; files stay near 25 KB gzipped.
5. Rate-stat qualifiers, per team game (games from games.json through the ratings week): passing 14 attempts (user, 2026-10-05; was 15), rushing 5 carries, receiving 2.5 catches, kicking 0.75 FG attempts; punting 3.6 punts (NCAA standard, added in Stage 1). Defense has no rate stats and no qualifier.
6. Player profiles move into the weekly CI export with a committed cache (data/reference/player_cache) and cover every leaderboard player.
7. 2027 team recruiting: CFBD has none yet; Stage 2 shows CFBD's position-group commit totals unranked until CFBD publishes rankings.
8. Rating calibration target: the brief's (above).

## Ratings design (predeclare before scoring; follow the project's round/gate style)
- Scale 30-99, one overall per player. Fixed, documented, monotonic mapping curve; calibration target (user, 2026-10-04, replacing the earlier "median around 60-65"): mean about 70, SD about 10; 95-99 1.2%, 90-94 2.6%, 85-89 5.4%, 80-84 11.1%, 75-79 15.9%, 70-74 21.7%, 65-69 21.5%, 60-64 17.5%, <60 3.1%. Targets, not quotas: no forced percentile buckets, and positions are NOT forced into identical distributions (inputs are normalized within position; the final scale is common; Stage 4 tests for positional inflation/compression).
- Inputs by position group:
  - QB/RB/WR/TE: production per opportunity, usage share, player EPA/PPA, success rate.
  - DL/LB/DB: tackles, TFL, sacks, PD, INT, QB hurries, player PPA.
  - OL: no individual data exists. Prior (recruit rating, size, class) plus a unit adjustment from team sack rate and rush success. Always "Estimated".
  - K/P: box stats only, Estimated.
- Shrinkage: small samples pulled toward a prior built from recruiting rating, class year and last season's production. Early season = wide bands, "Provisional".
- Output: overall, confidence band (e.g. 82 +/- 6), flag (Provisional / Estimated).
- Validation before UI: does the rating (built from data through season N-1) predict season N production, and draft round, better than recruit stars alone? Use cutoff-safe data only (no leakage; watch the CSV cutoff-to-numeric pitfall). Report improvement with confidence intervals; if it does not beat stars, say so and stop for my decision.
- Must not feed the team model, ratings, or simulations.

## Known limits to state in the UI/docs
CFBD has no snap counts, blocking grades, pressure allowed, or depth charts beyond what the app already uses. Portal data has no athlete id (fuzzy join). CFBD publishes no portal team ranking; ours is derived.

## Process
Stop after each stage with full numbers. I decide what ships. Ask before raising any budget or changing CI.

## Stage 1-4 decisions (user: "use your recommendations", 2026-10-05)
9. Profiles refresh weekly in CI (repo growth ~80 MB a season accepted for now).
10. What If? joins Conferences and Model under More; high-school class files may be up to 130 KB gzipped (lazy).
11. Transfers: CFPi+ Net Transfer Value v1 (sum of 247 transfer ratings in minus out), labelled derived. Replaced 2026-10-05 (user) by Star Churn v2: In, Out, Churn, Star² In/Out (average stars squared), Star Churn = Star² In - Star² Out as the ranking metric, after The Slate Index's format.
12. Ratings v1 approved as a labelled Beta; the scale is kept (mean 73.8 vs target 70 noted, a v2 matter). First UI: player-modal badge, Ratings view on /players/, methodology page /players/ratings/. TE left out of rating lists. Roster strip on team pages and risers deferred.
