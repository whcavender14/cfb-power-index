# Performance

Sizes are gzip (level 9), which is what GitHub Pages sends. Measured on the Week 3, 2026 build.

## Budget (enforced by `scripts/check_budget.mjs` in `pnpm build`)

| Item | Budget | Now |
|---|---|---|
| Entry JavaScript (every page) | 90 KB | 77.0 KB |
| Any page chunk | 12 KB (legacy views 25 KB) | largest 5.3 KB (legacy 17.3 KB) |
| CSS | 20 KB | 14.9 KB (+1.5 KB on `/betting/` only) |
| Homepage data (`index.json` + `teams.json`) | 30 KB | 17.9 KB |
| `games.json` | 50 KB | 32.5 KB |
| `scenario.json` (What if only, lazy) | 250 KB | 181.5 KB |
| Largest team file | 5 KB | 2.1 KB |
| Largest small logo | 40 KB | 23.3 KB |
| Each `players/leaders/<category>.json` (lazy, one per view; added Stage 1) | 25 KB | largest 24.7 KB (defense) |
| Largest `recruiting/hs_<year>.json` (lazy, one class per view; added Stage 2) | 130 KB | 119.6 KB (2018) |
| `players/ratings/top.json` / largest `players/ratings/team/<id>.json` (lazy; added Stage 4) | 15 / 5 KB | 10.3 / 3.2 KB |
| Largest `recruiting/portal_<year>.json` (lazy, one year per view; added Stage 3) | 110 KB | 98.1 KB (2025) |
| Largest `recruiting/teams_<year>.json` / `cards.json` / `dashboard.json` (Stage 2) | 10 / 10 / 5 KB | 2.3 / 5.6 / 1.4 KB |

Player features baseline and Stage 1 deltas: `PLAYER_FEATURES_STAGE0.md`. Stage 1 added the `Players` chunk (3.5 KB) and the header's More menu (entry JS 83.0 → 83.4 KB); Stage 2 added the `Recruiting` chunk (3.9 KB) and `RecruitingCard` (1.1 KB, lazy on team pages; entry JS 83.5 KB). Stage 3 added the `Transfers` chunk (3.8 KB; `Recruiting` 4.3 KB, `RecruitingCard` 1.3 KB). Global CSS unchanged (18.2 KB).

A build that exceeds any line fails, so size regressions cannot ship unnoticed.

## Before and after (Stage 5)

| Page | Before: JS + CSS + data | After: JS + CSS + data | Logos shown (before → after) |
|---|---|---|---|
| Home | 124 + 16 + 18 = 158 KB | 77 + 15 + 18 = 110 KB | ~26 logos: ~1,140 KB → ~280 KB |
| Rankings | 124 + 16 + 18 = 158 KB | 83 + 15 + 18 = 116 KB | 138 (lazy, as scrolled): up to 6.0 MB → 1.5 MB |
| Games (one week) | 124 + 16 + 43 = 183 KB | 80 + 15 + 43 = 138 KB | ~90 per week |
| Playoff | 124 + 16 + 11 = 151 KB | 81 + 15 + 11 = 107 KB | ~40 |
| Team page | 124 + 16 + 15 = 155 KB | 87 + 15 + 15 = 117 KB | ~13: ~570 KB → ~140 KB |
| What if | 124 + 16 + 229 = 369 KB | 81 + 15 + 229 = 325 KB | ~90 |

What changed:
1. **Route splitting.** Every page except Home is `React.lazy`. The PNG renderers (`graphics.ts`, `share.ts`, `exportImage.ts`) load only when a download button is pressed. The legacy dashboards (17 KB) load only on `/simulations/` and `/betting/`.
2. **Logos.** Pages use 144 px copies (`public/logos/sm/`, average 10.8 KB) instead of the 500 px originals (43.8 KB). Originals remain for the PNG exports. All logo images are `loading="lazy"` and `decoding="async"`.
3. **Lazy data.** Each page fetches only its own files (see `URLS.md`). The homepage never loads game lists, team files or simulation data. The 181 KB What-if file loads only on `/whatif/`.

Not done (recorded for decision in `CLEANUP.md`): `src/styles.css` (legacy look) still loads on every page. Loading it only on the legacy pages would let its global `body`/`a` rules override the site after visiting `/simulations/` in the same session; it needs scoping first. It is about 7 KB of the 14.9 KB CSS.
