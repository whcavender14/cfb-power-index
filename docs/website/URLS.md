# URL structure

All paths are under the GitHub Pages base `/cfb-power-index/` (set in `vite.config.ts`; `CFPI_BASE` overrides). Every path below has its own prerendered `index.html`, so direct loads and refreshes return 200. Unknown paths get `404.html`, which renders the site's "Page not found".

| Path | Page | Data loaded | Query parameters |
|---|---|---|---|
| `/` | Home: four questions (best teams, games that matter, playoff, what changed) | `index.json`, `teams.json` | none |
| `/rankings/` | CFPi+ (predictive) rankings table | `index.json` | `q` search, `conf`, `sort`, `dir` |
| `/rankings/resume/` | Résumé ranking (strength of record) | `resume.json` | `sort`, `dir` |
| `/changes/` | What changed this week | `index.json`, `changes.json` | `sort`, `dir` |
| `/compare/` | Rating history, 2–5 teams | `history.json` | `teams=georgia,alabama` (team slugs, commas) |
| `/games/` | Every game: results and projections | `games.json` (+ `betting.json` for lines) | `week` (number or `all`), `conf`, `team` (slug), `sort`, `dir` |
| `/playoff/` | Playoff odds, projected field, seed probabilities | `playoff.json` | `show=all`, sort keys |
| `/whatif/` | Pick winners; odds from matching simulated seasons | `scenario.json` (lazy), `games.json`, `playoff.json` | `pick=<game_id>:home,<game_id>:away`, `week` |
| `/teams/` | All teams, searchable, sortable by power rating | `index.json` | `q`, `conf`, `sort`, `dir` |
| `/teams/<slug>/` | Team page | `team/<slug>.json`, `history.json` | none |
| `/conferences/` | Conference cards (group aggregates) | `conferences.json`, `index.json` | none |
| `/conferences/<slug>/` | One conference: members, strength chart, group stats | `conferences.json`, `index.json` | `sort`, `dir` |
| `/model/` | How the model works | `index.json` | none |
| `/simulations/` | Original simulation dashboard (legacy view) | v1 `ratings.json`, `simulations.json` | none |
| `/betting/` | Original model-vs-market lines (legacy view) | v1 `ratings.json`, `betting.json` | none |

Slugs: lower-case school name, accents removed, `&` → `and`, other characters → `-` (e.g. `san-jose-state`, `hawaii`, `texas-a-and-m`). Transliteration uses stringi, so slugs are identical on macOS and Linux. Conference slugs follow the same rule (`fbs-independents`).

Old single-page links still work: `#ratings` → `/rankings/`, `#simulations` → `/simulations/`, `#betting` → `/betting/`, `#methodology` → `/model/`.
