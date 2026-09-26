# CFPi+ website: architecture

## Current architecture (final, Stage 5)

**What it is.** A static React 19 + TypeScript + Vite site on GitHub Pages at `/cfb-power-index/`, rebuilt every Monday by `.github/workflows/site.yml`. The model is untouched; R computes every number and the browser only displays and filters them.

```
CFBD API ─► R pipeline (scripts/run_weekly_pipeline.R)
            ├─ 01 ratings: Current C2 (frozen, hash-checked)        → output/state/production_ratings_*.rds
            └─ 02 simulation: 1,000 seasons + cfbseedR CFP          → output/state/simulations_*.rds
          ► export (scripts/03_export_public_data.R)
            ├─ v1 files (legacy views)                               → public/data/{ratings,simulations,betting}.json
            ├─ player stats pull (display only)                      → output/state/player_stats_*.rds
            └─ R/publish/export_site_data.R                          → public/data/v2/*.json (+ week archives)
          ► validate (scripts/validate_site_data.mjs) ► type-check ► vite build (route-split)
          ► budget (scripts/check_budget.mjs) ► prerender every route (scripts/prerender_routes.mjs) ► Pages
```

| Topic | Document |
|---|---|
| Every page and its URL, data and parameters | `URLS.md` |
| Dataset dictionary (every field of every published file) | `DATA_CONTRACT_V2.md` (v1 legacy files: `../DATA_CONTRACT.md`) |
| Derived metrics (formulas, inputs, caveats) | `DERIVED_METRICS.md` |
| Weekly update and what to do when it fails | `RUNBOOK.md` |
| Player data sourcing | `PLAYER_DATA.md` |
| Performance budget and before/after | `PERFORMANCE.md` |
| Accessibility checks and conventions | `ACCESSIBILITY.md` |
| What the site cannot show, and why | `LIMITATIONS.md` |
| Cleanup done and open items for decision | `CLEANUP.md`, `TODO.md` |
| Approved proposals and gate reports | `RESUME_PROPOSAL.md`, `STAGE4_FEASIBILITY.md` |

**Code map.**
- `src/site/`: the site. `Site.tsx` is the shell, nav and routes (pages lazy-loaded). `router.tsx` does History-API paths and query state. `components.tsx` holds shared UI. `data.ts` has the dataset types and loader. `pages/*` are the pages. `HistoryChart.tsx` draws rating history. `scenario.ts` is the What-if filter. `share.ts` + `graphics.ts` + `ShareButton.tsx` produce the PNG downloads. `site.css` is the design system (`cf-` prefix).
- `src/SeasonSimulations.tsx`, `src/BettingAnalysis.tsx`, `src/exportImage.ts`, `src/exportPlayoff.ts`, `src/styles.css`: the original dashboard views, served at `/simulations/` and `/betting/`, including the two playoff PNG downloads.
- `R/publish/`: `export_site_data.R` (all site datasets and their internal checks) and `pull_player_stats.R`.
- `scripts/history/reconstruct_c2_history.R`: labelled reconstructions of past weeks (guarded; run by hand).

**Teams vs Conferences.** `/teams/` is a single searchable, sortable table of every team, centred on the CFPi+ power rating (rank, rating bar, offense, defense, schedule strength, strength of record, conference filter). `/conferences/` is about groups: one card per conference with average and median rating, top-25 count and expected playoff teams, each linking to a detail page with the member table, a strength chart on the full FBS scale, group schedule strength and non-conference record. Each page's lede says what it is for and links to the other.

**Design system.** System font with size-specific tracking and leading; one accent (blue); grouped surfaces; one translucent layer (the header, plus the What-if bar on phones); school colours only for the team-page header rule and logo fallbacks. Light and dark themes (a toggle, defaulting to the OS setting). Reduced motion, reduced transparency and increased contrast are honoured. Touch targets are at least 44 pt on touch screens.

---

*Sections 1–8 below are the Stage 1 audit (snapshot at `9b0efb3`, 2026-09-26), kept as written. Sections 9–12 record each stage's additions.*

## 1. Build and deployment

| Item | Current state | Evidence |
|---|---|---|
| Framework | React 19 + TypeScript 5.8, Vite 6, Tailwind 4 (via `@tailwindcss/vite`) plus hand-written CSS (`src/styles.css`, `src/betting.css`), `lucide-react` icons. No router and no state library. | `package.json` |
| Entry | `index.html` → `src/main.tsx` → `src/App.tsx` | |
| Routing | Hash-based tabs: `#ratings`, `#simulations`, `#betting` (`App.tsx` `tabFromHash`). These are the site's only "URLs" and must stay working. | `src/App.tsx` |
| Base path | `base: './'` (relative assets), so the build works at `/cfb-power-index/` without hard-coding it. Data is fetched as `${import.meta.env.BASE_URL}data/<name>.json`. | `vite.config.ts`, `src/data.ts` |
| Build | `pnpm build` = `tsc -b && vite build` → `dist/`. `public/` (data + logos) is copied through verbatim. | |
| Tests | `pnpm test` runs Node's test runner on `tests/{web-data,betting,export,playoff}.test.mjs` (schema validation of `public/data`, plus the client-side betting and playoff logic). R tests live in `tests/*.R`, but CI does not run them. | |
| CI / Pages | One workflow, `.github/workflows/site.yml` ("CFB Power Index"). Triggers: a push to the default branch, a Monday 09:00 UTC cron (Aug–Jan), and a manual dispatch. With `REFRESH=true` (cron or dispatch) it installs R 4.4.3 and cfbseedR (pinned SHA), then runs `verify_frozen_inputs.R` → `run_weekly_pipeline.R` → `03_export_public_data.R` (betting on). Every run then does `pnpm test` → `pnpm logos` → `pnpm build`, **commits only `public/data`** back to the default branch, and deploys `dist/` with `actions/deploy-pages@v4` in the same run. | `site.yml` |
| Repo | `origin` = `github.com/whcavender14/cfb-power-index`, the repo that serves the site. (The README's claim that "the live website still deploys from the old folder" is stale.) | `git remote -v` |

**Important CI property:** `output/` is git-ignored, and the job starts from a clean checkout. Every `.rds` file the pipeline writes (production snapshots, per-simulation results) is therefore **lost when the job ends**. Only `public/data/**` persists, because it is committed.

## 2. Pipeline, hop by hop

```
CFBD API (schedule/results, PBP)  +  data/frozen/**  (checksummed)
        │  scripts/verify_frozen_inputs.R
        ▼
[1] Ratings      scripts/01_build_ratings.R
                 → R/production/production_model.R  (dispatch; config/production_model.R: default C2_current)
                 → R/production/c2_production.R → R/c2/c2_current.R (+ R/round15/**, R/forward/vendor/round13_sr_stack.R)
                   [EB_features path: R/model/production_operations.R → R/model/cfb_power_ratings_vCurrent.R]
                 writes output/rankings/current_2026_rankings{,_metadata}.csv
                        output/state/production_ratings_2026_{latest,wkNN}.rds
        ▼
[2] Game projections — NOT a pipeline step. Spread = P_home − P_away + HFA (0 if neutral) is
                 computed inside the simulation (per game, per sim) and, separately, in the BROWSER
                 (src/betting.ts) for the betting tab. No per-game projection file is exported.
        ▼
[3] Season sims  scripts/02_simulate_season.R / run_weekly_pipeline.R step 2
                 → R/simulation/simulate_season.R::run_season_simulation()
                   margin ~ Normal(μ, σ=15.650), 1,000 sims, seed 1434 (config/production.R)
                 → R/simulation/cfb_dynamic_playoffs.R::cfb_dynamic_simulations() (cfbseedR REG season + CCGs)
        ▼
[4] Playoff sims same call: per-sim resume ranking (cfb_dynamic_cfp_ranking) → cfbseedR 2026 auto-bid
                 seeding (cfb_dynamic_playoff_seeds) → cfbseedR:::sims_simulate_playoffs
                 writes output/state/simulations_2026_latest.rds (+ simulation_status_2026.rds)
        ▼
[5] Export       scripts/03_export_public_data.R
                 → R/publish/export_public_data.R   → public/data/{ratings,simulations}.json
                 → R/publish/export_betting_data.R  → public/data/betting.json   (CFB_EXPORT_BETTING=true)
                 each also copied to public/data/<season>/week-NN/<name>.json
        ▼
[6] Website      src/data.ts fetchDataset('ratings'|'simulations'); BettingAnalysis.tsx fetches betting.json
                 scripts/sync_logos.mjs mirrors logos → public/logos/<team_id>.png (for PNG export)
```

### What the site consumes and what is dev-only

| Consumed by the site / CI | Dev-only, research, or evidence (do not touch; not the site's concern) |
|---|---|
| `scripts/run_weekly_pipeline.R`, `01_build_ratings.R`, `03_export_public_data.R`, `verify_frozen_inputs.R` | `scripts/02_simulate_season.R` (standalone; CI calls the same function through the runner) |
| `R/production/*`, `R/c2/c2_current.R`, `R/round15/{candidates,prep}/*`, `R/round15/cfbd_client.R`, `R/forward/vendor/round13_sr_stack.R`, `R/model/*` (C2's hashes and the EB rollback) | `scripts/round15/`, `scripts/c2r/`, `scripts/round16/`, `scripts/c2/`, `docs/round15/`, `docs/round16/`, `docs/c2r/`, `archive_reference/` |
| `R/simulation/*`, `R/publish/export_public_data.R`, `export_betting_data.R`, `betting_functions.R` | `R/publish/rankings_graphic.R` (runs only with `CFB_CREATE_GRAPHIC=true`, never in CI) |
| `config/{paths,production,production_model}.R`, `data/frozen/**`, `data/reference/{teams_2026.rds, production_snapshots_2026/}` | `scripts/04_archive_prospective_snapshot.R` (manual, write-once evidence), `scripts/forward/*` (launchd forward test, not activated), `scripts/live/c2_vs_incumbent_week.R` (one-off, hard-codes a local path) |
| `src/**`, `public/data/**`, `public/logos/**`, `scripts/sync_logos.mjs`, `scripts/check-pnpm-config.mjs` | `package.json` script `export:data` points at `scripts/export_public_data.R` and `scripts/export_betting_data.R`, **which do not exist** (the real files are under `R/publish/`). It is stale and unused by CI. Listed for fixing, not deleted. |

## 3. Where things live

| Data | Location | Notes |
|---|---|---|
| **Current ratings** | `public/data/ratings.json` (from `production_ratings_2026_latest.rds`) | 138 teams; power/off/def, `weekly_change`, `preseason_change`. **No rank is exported**: the browser ranks the teams (`App.tsx`). Internal columns that are not exported: `games_played`, `pre_power`, `prior_contribution`, `current_contribution`. |
| **Weekly rating history** | `public/data/2026/week-01..03/ratings.json` (committed); `data/reference/production_snapshots_2026/wk01–03.rds` | **All three archives are EB_features (the former incumbent).** The week-03 archive was kept as EB by the model guard, while `ratings.json` (the latest) is now C2 at week 3. **No C2 weekly history exists.** |
| — reliable reconstruction? | Partly | (a) The JSON archives are an honest per-week record, but of *whatever model published that week*. A mixed EB→C2 line is a model change, not movement, and must never be plotted as one series. (b) C2 history for weeks 1–3 could be *backfilled* by running the unchanged C2 at past cutoffs (`01_build_ratings.R <cutoff>` supports this). That would be a retroactive recomputation, not a record of what was published, and needs your decision. (c) **Going forward the history breaks:** CI does not persist `output/state`, so each run's `wkNN.rds` vanishes. The only seeds are the EB wk01–03 files, so `weekly_change` will stay `null` for C2 every week (`weekly_comparison_week` is already `null`). The committed JSON archives *do* persist, so history can be built from `public/data/<season>/week-NN/ratings.json` if every future week is archived. |
| **Schedules / results** | `data/frozen/cfb_data_v3/raw_schedule_2026.rds` (888 FBS-involved regular-season games; results through 2026-09-09); the live pull goes to `output/state/production_live/` (ephemeral) | **Not exported.** `betting.json` holds only the *upcoming* week's matchups (no scores). No field for TV network (CFBD `/games/media` is not pulled). Venue, `conference_game` and `excitement_index` exist in the raw schedule. |
| **Team metadata** | `data/reference/teams_2026.rds` (43 cols: school, mascot, abbreviation, conference, **color, alt_color**, logo + dark logos at several sizes, venue/city/state/capacity); `public/logos/<id>.png` (138 mirrored) | Only `team_id, team, conference, logo_url` are exported. Colors, abbreviations and dark logos are available but unused. |
| **Simulation outputs** | `public/data/simulations.json`, **aggregate only**: mean overall wins (includes CCGs), P(playoff), P(conf title), P(national title). The `.rds` also holds `overall$seed1` (unexported), **per-sim `standings`** (sim × team: wins, conf_champ, seed, cfp_rank, resume_score, wab, adj_margin, exit), **per-sim `games`** (every game's margin in every sim, including CCGs and CFP) and `game_summary` (per-game home win %). | The per-sim objects exist only for the life of the CI job. `projected_wins_preseason` and `vegas_win_total_preseason` are `null`: no archived preseason sim or Vegas CSV exists. |
| **CFP format / seeding (as implemented)** | `R/simulation/cfb_dynamic_playoffs.R` + `config/production.R` | 12 teams, cfbseedR `autobid="2026"`: every P4 champion (ACC, Big 12, Big Ten, SEC) plus the highest-ranked G6 champion-eligible team (Pac-12 counts as G6), with Notre Dame handled by cfbseedR's rule. At-large teams fill by the **per-sim resume ranking**: `1.9887·WAB + 0.14943·adj_margin + 1.7923·conf_champ`, with benchmark = the 60th-best power rating and margins capped at 35, fitted to committee top 25s 2018–25 (`scripts/calibrate_cfp_ranking.R`). Ties go by win pct, then name. Bracket and home field come from cfbseedR's playoff simulator. Checked each run by `assert_cfp_autobids_2026`. |
| — client-side replica | `src/playoff.ts` | The "most likely bracket" PNG **re-implements** selection in the browser on aggregate odds (playoff prob stands in for rank, and each conference's likeliest champion is used). This is a proxy, not a model output (see §7). |
| **Betting lines** | `public/data/betting.json` + `2026/week-02..04/betting.json` | One quoted line per game at retrieval time (a provider-priority list, CFBD). Not a verified opening or closing line; no line history within a week. Historical closing lines 2023–25 are in `data/reference/market/betting_lines_2023_2025.rds` (evaluation only). Model spreads are computed **in the browser**. |
| **Model performance** | `docs/round16/results/*.csv` (C2 walk-forward: `metrics_overall`, `reliability_deciles`, `calibration_slopes`, `market_*`), `data/reference/incumbent_predictions/*.csv` (EB), `data/prospective/predictions_20260909*.csv` (one EB pre-kickoff snapshot), `docs/c2/live_2026_wk04/*.csv` (one-off C2 vs EB) | None of this is exported to the site. There is **no live 2026 C2 prediction log**: prospective archiving is manual and has one EB snapshot. |

## 4. Support matrix

SUPPORTED = the exported public data already carries it. PARTIAL = the data exists in the pipeline or repo but needs a new export or a documented derived metric (no model change). NOT SUPPORTED = the data does not exist.

| Feature | Status | Evidence / what is missing |
|---|---|---|
| **Team pages** | PARTIAL | Ratings, sims and metadata exist (colors too, in `teams_2026.rds`). Missing: the team's schedule with results, per-game spreads and win probs, and the record. The schedule and results are in the live pull, but no export exists. |
| **Games page + matchup quality** | PARTIAL | Spreads can be derived from ratings + HFA (currently in the browser, which breaks Rule 2). Win prob = Φ(spread/σ) with the model's σ = 15.650, a documented derived metric that the sim already uses. Per-game sim win % exists in `game_summary`. "Matchup quality" needs a new, documented metric (e.g. combined power + closeness). TV network: **NOT SUPPORTED**. |
| **Playoff dashboard** | PARTIAL | P(playoff), P(conf), P(title) are exported. Seed distribution, P(bye), P(reach each round), P(host) and at-large vs auto-bid split all exist in per-sim `standings` (seed, exit), but none are exported. |
| **Final-record distributions** | PARTIAL | Only the mean is exported. Per-sim `standings$wins` gives the full distribution. It needs a small export (138 × ≤16 bins). Note: wins include CCG and CFP games per cfbseedR's `wins_scope`; a regular-season-only distribution needs the REG games from per-sim `games`. |
| **Rating history** | PARTIAL | Weekly JSON archives exist, but only EB for weeks 1–3; C2 starts at week 4. See §3 for the persistence gap, which must be fixed first. |
| **Weekly movers** | NOT SUPPORTED (today) | `weekly_change` is null and will stay null under CI (§3). It becomes supported once the exporter compares against the previous committed week archive from the same model. |
| **Conference dashboards** | PARTIAL | Ratings, projected wins and conf-title odds by conference are supported. Standings and records need the results export. Divisions: none in 2026. |
| **Model performance / calibration** | PARTIAL | Historical C2 walk-forward calibration exists as CSVs (publishable as static JSON). A live 2026 track record needs (a) a weekly **pre-kickoff** prediction archive and (b) results. The archives of `ratings.json` + `betting.json` allow a reconstruction only for weeks whose ratings were archived before kickoff, and weeks 1–3 are EB. |
| **Resume ranking** | PARTIAL | The resume formula exists (`cfb_resume_features` + `cfp_rank_coef`). Per-sim `cfp_rank` / `resume_score` exist for simulated full seasons. A to-date resume ranking on actual results means calling the *existing* function on played games only: a derived output, documented, kept out of model code. |
| **Scenario simulator** | NOT SUPPORTED | Per-sim results are not preserved (§5). |
| **Shareable PNGs** | SUPPORTED (exists) | `src/exportImage.ts` (rankings), `src/exportPlayoff.ts` (playoff hunt, bracket), same-origin logos. The bracket PNG relies on the client-side selection proxy (§7). |

## 5. Can simulations be filtered client-side by game outcome?

**Not today.** Only aggregates are published, and the per-sim `.rds` is discarded when the CI job ends. The data needed is produced every run (`sim$games`, `sim$standings`), so this is purely an export question. No model or simulation change is needed.

Proposed lightweight export `data/public/sims/2026-wkNN.bin` (+ small JSON index), lazy-loaded **only** on the scenario page:

| Block | Encoding | Size (1,000 sims) |
|---|---|---|
| Unplayed REG games (≈ 600–700 from week 4 on; 888 total) | 1 bit per game per sim (home win) | ≈ 85 KB |
| Per team per sim: wins (4 bits), conf_champ (1), seed 0–12 (4), exit round (3) | 2 bytes × 138 teams | ≈ 276 KB |
| CCG participants (optional, for "who plays in the title game") | 2 × 1 byte per conference per sim | ≈ 20 KB |
| **Total** | | **≈ 380 KB raw, ≈ 150–250 KB gzipped** (Pages gzips it) |

Margins (int8 per game) would add ≈ 650 KB and are only needed for margin-based filters, so leave them out.

**Statistical caveat to surface on the page:** with 1,000 sims, conditioning on one coin-flip game leaves ~500 sims, and three such games leave ~125. The page must show the matching-sim count and suppress or flag probabilities below a minimum n (e.g. show "—" under 100 sims). Raising `sim_count` would be a simulation-setting change, which is your call and outside the site's remit.

## 6. Proposed public-data contract (`data/public/*.json`)

Keep `public/data/{ratings,simulations,betting}.json` and the week archives **exactly as they are** (existing URLs and the existing site keep working). Add new files next to them under `public/data/v2/` (served at `data/v2/…`). A literal `data/public/` folder outside `public/` would not be served by Vite. All files use the existing envelope: `schema_version, season, week, updated_at, as_of, model, status`. Everything is computed in R by a new `R/publish/export_site_data.R` that only reads model outputs.

| File | Loaded by | Schema (per row) | Approx. size |
|---|---|---|---|
| `v2/index.json` | homepage | `{teams:[{team_id, rank, rank_prev, rank_change, power, off, def, off_rank, def_rank, playoff_p, title_p, proj_wins}], leaders, meta:{sim_count, sigma, hfa, weeks_available[]}}` | ~30 KB |
| `v2/teams.json` | all pages | `{teams:[{team_id, team, short, abbreviation, mascot, conference, color, alt_color, logo, logo_dark, logo_local}]}` | ~25 KB |
| `v2/team/<team_id>.json` | team page | `{ratings:{…current, games_played, pre_power, prior_contribution, current_contribution}, history:[{week, power, rank, model}], schedule:[{game_id, week, kickoff, opp_id, site:'home'|'away'|'neutral', result:{pts_for, pts_against}|null, spread, win_prob, sim_win_prob}], record_dist:{overall:[p0..p15], reg:[...]}, playoff:{seed_dist:[p1..p12], bye, reach:{qf,sf,final}, champ}}` | ~5 KB × 138 |
| `v2/games/<season>-wkNN.json` | games page | `{games:[{game_id, kickoff, time_tbd, home_id, away_id, neutral, conference_game, spread, win_prob_home, sim_win_prob_home, quality, market_spread|null, result|null}]}` | ~20 KB/week |
| `v2/playoff.json` | playoff dashboard | `{teams:[{team_id, p_playoff, p_auto, p_at_large, p_bye, p_host, seed_dist[12], p_qf, p_sf, p_final, p_champ}], bubble:[…], format:{…from assumptions}}` | ~25 KB |
| `v2/conferences.json` | conference pages | `{conferences:[{name, tier:'P4'|'G6'|'Ind', teams:[team_id], title_p:{team_id:p}, standings:[{team_id, conf_w, conf_l, w, l}]}]}` | ~15 KB |
| `v2/history/<season>.json` | history, movers | `{weeks:[{week, as_of, model, ratings:{team_id:[power, rank]}}]}` built only from committed week archives. `model` is per week so the UI can break the line at a model change. | ~10 KB/week |
| `v2/resume.json` | resume page | `{teams:[{team_id, resume_rank, resume_score, wab, adj_margin, conf_champ_to_date}]}` using the existing `cfb_resume_features` | ~10 KB |
| `v2/performance.json` | model page | `{historical:{…round16 metrics, reliability deciles, calibration slope}, live:{weeks:[{week, n, mae, bias, ats_vs_line?}] }` with `live` empty until a pre-kickoff archive exists | ~10 KB |
| `v2/sims/<season>-wkNN.bin` + `.json` index | scenario page only | binary layout in §5; the index maps bit offsets → `game_id`, team order | ~200 KB gz |

Rules baked into the contract: ranks are exported (not derived in the browser); every probability carries its sim count; a probability of 0/1000 is exported as `0` with `sim_count`, so the UI can render "<0.1%" and not a hard 0; unavailable fields are `null`, never `0`.

## 7. Conflicts with your rules and staged plan

1. **Rule 2 (single source of truth) is already violated in three places:** the browser computes model spreads (`src/betting.ts`), ranks (`App.tsx`), and a most-likely bracket via a re-implemented CFP selection on aggregate proxies (`src/playoff.ts`, which also uses `conference_title_probability ?? 0`, a misleading-zero pattern). Recommendation: export these from R and keep the browser code only as a fallback reader until the switch.
2. **Weekly history / movers depend on fixing persistence first.** Until the exporter reads the previous committed week archive (or CI commits `output/state` snapshots), movers and history cannot be built for C2. This is a pipeline/export change, not a model change.
3. **C2 has no weeks 1–3.** A history chart either starts at week 4 or shows EB weeks 1–3 labelled as the former model. Backfilling C2 is possible but retroactive. Your decision.
4. **Rule 4 says "URL query params for state"**, while existing routing is hash-based (`#ratings`). Both can coexist (`?team=…#ratings`); the hash routes must stay as redirects.
5. **The "CFPi+" rename** touches `index.html` title/meta, the header/footer brand (`App.tsx`), and the PNG exports (`exportImage.ts`, `exportPlayoff.ts`). The repo and the Pages URL (`cfb-power-index`) stay as they are.
6. **A scenario simulator on 1,000 sims** gives small conditional samples (§5). It is usable with n-disclosure, but not precise.
7. **Live model performance** needs a weekly pre-kickoff archive. `04_archive_prospective_snapshot.R` exists but is manual and EB-oriented, and nothing in CI runs it. Any live calibration page will be thin in 2026.
8. **TV network, line movement and opening/closing lines** are not available. They go to `LIMITATIONS.md` (to be created in Stage 2).
9. Minor: the `package.json` `export:data` script points at non-existent paths, and the README and `DATA_CONTRACT.md` still describe EB_features in places. Both are for fixing, not deletion.

## 8. Recommended stage plan

1. **Stage 2 — Data layer (no UI).** Add `R/publish/export_site_data.R` and the `v2/*` files. Fix weekly persistence by comparing against the committed archive. Export rank, spreads, win probs, results and schedule. Add JS schema tests and create `LIMITATIONS.md`. The old JSON stays untouched.
2. **Stage 3 — Shell + design system.** Apply the CFPi+ brand, Apple-design tokens (type scale, spacing, materials, motion with reduced-motion), query-param routing that keeps the hash routes, and move the existing three tabs onto the new data with no visual regressions.
3. **Stage 4 — Team pages + games page** (schedule, spreads, win probs, matchup quality).
4. **Stage 5 — Playoff dashboard + record distributions + conference dashboards.**
5. **Stage 6 — History, movers, resume ranking** (history begins at the first C2 week unless you approve a backfill).
6. **Stage 7 — Model page + performance/calibration** (historical now; live once pre-kickoff archiving is automated).
7. **Stage 8 — Scenario simulator** (binary per-sim export, lazy-loaded).
8. **Stage 9 — Shareable PNG refresh** for the new pages, then remove the client-side proxy bracket.

## 9. Current build (Stage 2)

| Piece | Where | Notes |
|---|---|---|
| Page datasets | `R/publish/export_site_data.R` → `public/data/v2/*` | Run by `scripts/03_export_public_data.R`. `R/simulation/simulate_season.R` now also saves `sim$schedule` and `sim$team_power` (the exact inputs it already used; no logic change) so the exporter never sources the model. |
| Validation | `scripts/validate_site_data.mjs` | First step of `pnpm build` and part of `pnpm test` (`tests/site-data.test.mjs`, including broken-data cases). A bad export fails CI before deploy. |
| Routing | `src/site/router.tsx` | History API paths: `/`, `/rankings/`, `/games/`, `/playoff/`, `/teams/`, `/teams/<slug>/`, `/conferences/`, `/model/`, plus the preserved `/simulations/` and `/betting/`. Old `#ratings`, `#simulations`, `#betting` and `#methodology` links redirect. Filters and sorts live in query params (`/games/?week=5&team=alabama`). |
| Base path | `vite.config.ts` | `base` = `/cfb-power-index/` for builds (`CFPI_BASE` overrides), `/` in dev. Replaces the old relative `./`, which cannot work for nested routes. |
| Direct loads | `scripts/prerender_routes.mjs` (last step of `pnpm build`) | Writes `dist/<route>/index.html` for every page and each of the 138 team pages, with route-specific `<title>` and description, plus `dist/404.html` (the app renders "not found"). No server rewrite is needed on Pages. |
| UI | `src/site/` (`Site.tsx` shell, `components.tsx`, `games.tsx`, `pages/*`, `site.css`) | The design system is prefixed `cf-`. The old views (`src/SeasonSimulations.tsx`, `src/BettingAnalysis.tsx`, PNG exporters) are unchanged apart from the CFPi+ name and render inside the new shell. `src/App.tsx` and `src/PowerRatings.tsx` were no longer mounted (deleted in Stage 5). |
| Homepage payload | `index.json` + `teams.json` (~92 KB raw) | No game list, team files or simulation-level data. |

## 10. Stage 3 additions

| Piece | Where | Notes |
|---|---|---|
| Rating history | `history.json`; pages `/compare/?teams=a,b` (2–5 teams, colour stays with the team, shareable URL) and a chart on each team page | Sources and the reconstruction method: `DATA_CONTRACT_V2.md`. Reconstruction script: `scripts/history/reconstruct_c2_history.R` → committed `data/history/c2_reconstructed_2026.csv`. It is run by hand, not in CI; CI only reads the CSV. |
| Movement | `index.json` `rank_change`, `rating_change` | Now read from `history.json` (the same source as the chart and the What-changed page). The rankings PNG uses it too. |
| Team pages | Résumé panel (SOS played/full/remaining, strength of record, best win, worst loss), rating-history chart, final-record distribution (bars + table of raw counts) | EPA and success rate are not in the model output; see `LIMITATIONS.md`. |
| What changed | `/changes/`, `changes.json` | Rank movement and rating change in separate sections; fixed R sentence templates only. |
| Teams vs Conferences | `/teams/`: a searchable, sortable table of every team by power rating and its parts (off, def, SOS, SOR), with a rating bar and conference filter. `/conferences/`: one card per conference with group aggregates, linking to `/conferences/<slug>/` (member table, strength chart, SOS, non-conference record, expected playoff teams) | Teams is about individual teams' ratings. Conferences is about the group. Each page links to the other and says which is which. |
| Layout fix | `site.css` | Below 1200 px, wide tables scroll inside their card and definitions open as a pinned card, so no page scrolls sideways at any width (checked at 375, 780, 900, 1100, 1300 px). Also fixed: screen-reader-only labels in tables widened the page by 18 px. |

Correction found in Stage 3: the simulation does not play conference title games. cfbseedR names each conference's standings leader champion, `sim$games` holds only regular-season and CFP games, and every team's simulated record has exactly its regular-season game count. `sim$wins_scope` says the wins include conference championships, which is wrong. The site text now says "regular season"; the model code is unchanged.

## 11. Stage 4

- Feasibility reports: `STAGE4_FEASIBILITY.md` (player data, scenario simulator); résumé proposal: `RESUME_PROPOSAL.md`. All three approved and built.
- What if? (`/whatif/`, `src/site/pages/WhatIf.tsx`, `src/site/scenario.ts`): lazy-loads `scenario.json`, filters the stored simulations by the picks and aggregates them. Picks are in the URL: `?pick=<game_id>:home|away,...`. Linked from the Playoff page (not in the top nav, which is full).
- Résumé ranking (`/rankings/resume/`, `resume.json`): reached through the "CFPi+ (predictive) | Résumé" switch on Rankings. The predictive and résumé ranks are separate, labelled columns wherever both appear (Résumé page, team page).
- Statistical leaders (built): the weekly export step pulls CFBD season player stats through the ratings week (`R/publish/pull_player_stats.R` → `output/state/player_stats_<season>.rds`); the exporter adds fixed-rule leaders to each `team/<slug>.json`; the team page shows them in a "Statistical leaders" panel. CI already passes `CFBD_API_KEY` to that step, so the workflow file is unchanged.
- Shareable graphics (built): `src/site/share.ts` (frame, table, logos; site styling) and `src/site/graphics.ts` (Top 25, game projections, CFP odds, projected playoff field, weekly movers, rating-history comparison), triggered by `src/site/ShareButton.tsx`, which shows a plain failure message if the browser cannot export a canvas. They are drawn from the data the page already loaded, with a "Ratings through Week X · Updated <date>" stamp and a small CFPi+ mark. Buttons: Rankings (Top 25, All teams), Games (current filters, up to 30 upcoming games), Playoff (CFP odds, Projected field), What changed, History.
- The existing downloads are unchanged: "Playoff Hunt" and "Projected Playoff" on `/simulations/`, and the all-teams rankings PNG (now "All teams PNG" on Rankings). All three were re-tested after the change.
- Logo loading for every export now waits for the image load event with a 5-second limit instead of `decode()`, which can stay pending in a hidden page. A logo that doesn't load is drawn as a monogram.

## 12. Stage 5

- Homepage rebuilt around four questions: who is best, which games matter this week, who is making the playoff, and what changed. Each is a short preview linking to its page, and the page loads `index.json` + `teams.json` only.
- Routes are lazy-loaded, and the PNG code loads on click. Entry JS went from 124 KB to 77 KB gzipped. Small 144 px logos (`public/logos/sm/`) replace the 500 px originals on pages: 10.8 KB vs 43.8 KB average. The originals stay for PNG exports. Budget enforced in the build (`PERFORMANCE.md`).
- Accessibility: axe-core (WCAG 2.1 A/AA + best practice) on 16 pages in light and dark; all real issues fixed (`ACCESSIBILITY.md`).
- Fixes found in testing:
  - team slugs were OS-dependent (now `stringi`)
  - stale team files are now removed on rename
  - the history chart and the compare PNG now show gaps for missing early weeks
  - sticky table headers covered the first row on tablets
  - the legacy Betting page showed "0 games" when its data was missing
  - removed the unused `src/App.tsx`, `src/PowerRatings.tsx`
