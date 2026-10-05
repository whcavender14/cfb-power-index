# URL structure

All paths are under the GitHub Pages base `/cfb-power-index/` (set in `vite.config.ts`; `CFPI_BASE` overrides). Every path below has its own prerendered `index.html`, so direct loads and refreshes return 200. Unknown paths get `404.html`, which renders the site's "Page not found".

| Path | Page | Data loaded | Query parameters |
|---|---|---|---|
| `/` | Home: four questions (best teams, games that matter, playoff, what changed) | `index.json`, `teams.json` | none |
| `/rankings/` | CFPi+ (predictive) rankings table | `index.json` | `q` search, `conf`, `sort`, `dir` |
| `/rankings/resume/` | Résumé ranking (strength of record) | `resume.json` | `sort`, `dir` |
| `/changes/` | What changed this week | `index.json`, `changes.json` | `sort`, `dir` |
| `/compare/`, `/history/` | Retired (Round 18); redirect to Home. Each team page keeps its rating-history chart | | |
| `/games/` | Every game: results and projections | `games.json` (+ `betting.json` for lines) | `week` (number or `all`), `conf`, `team` (slug), `sort`, `dir` |
| `/playoff/` | Playoff odds, projected field, seed probabilities | `playoff.json` | `show=all`, sort keys |
| `/whatif/` | Pick winners; odds from matching simulated seasons | `scenario.json` (lazy), `games.json`, `playoff.json` | `pick=<game_id>:home,<game_id>:away`, `week` |
| `/teams/` | All teams, searchable, sortable by power rating | `index.json` | `q`, `conf`, `sort`, `dir` |
| `/players/` | Player statistical leaders (six categories) | `players/leaders/<category>.json` (lazy, one category), `player/<id>.json` on selection | `cat` (a stat category or `ratings`), `conf`, `team` (team id), `pos` (group), `class` (1-4), `all=1` (include unqualified), `sort`, `dir` |
| `/players/ratings/` | CFPi+ Player Ratings beta: methodology, validation, limits | `players/ratings/top.json` | none |
| `/recruiting/` | Recruiting overview | `recruiting/dashboard.json` | none |
| `/recruiting/high-school/` | High-school classes: Team Rankings, Players, Commitments | `recruiting/dashboard.json`, `recruiting/teams_<year>.json`, `recruiting/hs_<year>.json` (Players/Commitments) | `year`, `tab` (`teams`/`players`/`commits`), `conf`, `team` (team id), `pos`, `state`, `stars` (minimum), `commit` (`yes`/`no`), `sort`, `dir` |
| `/recruiting/transfers/` | Transfer portal: Team Rankings (CFPi+ derived), Incoming, Outgoing, By Position | `recruiting/dashboard.json`, `recruiting/portal_<year>.json` | `year`, `tab` (`teams`/`in`/`out`/`position`), `conf`, `team` (team id), `pos`, `stars`, `sort`, `dir` |
| `/teams/<slug>/` | Team page | `team/<slug>.json`, `history.json` | none |
| `/conferences/` | Conference cards (group aggregates) | `conferences.json`, `index.json` | none |
| `/conferences/<slug>/` | One conference: members, strength chart, group stats | `conferences.json`, `index.json` | `sort`, `dir` |
| `/model/` | How the model works | `index.json` | none |
| `/simulations/` | Original simulation dashboard (legacy view) | v1 `ratings.json`, `simulations.json` | none |
| `/betting/` | Original model-vs-market lines (legacy view) | v1 `ratings.json`, `betting.json` | none |

Slugs: lower-case school name, accents removed, `&` → `and`, other characters → `-` (e.g. `san-jose-state`, `hawaii`, `texas-a-and-m`). Transliteration uses stringi, so slugs are identical on macOS and Linux. Conference slugs follow the same rule (`fbs-independents`).

Old single-page links still work: `#ratings` → `/rankings/`, `#simulations` → `/simulations/`, `#betting` → `/betting/`, `#methodology` → `/model/`.

| `/games/<game_id>/` | Matchup breakdown: model forecast, sportsbook line and total when quoted (evaluation only), head-to-head ratings and stats, key players | `games.json`, `index.json`, `efficiency.json`, `usage/<slug>.json`, `betting.json` | |
