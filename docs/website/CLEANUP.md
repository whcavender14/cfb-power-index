# Cleanup (Stage 5)

## Fixed

| Item | What was wrong | Fix |
|---|---|---|
| `src/App.tsx`, `src/PowerRatings.tsx` | The old single-page app shell and ratings view, unreachable since Stage 2 | Deleted (confirmed unreachable by an import-graph walk from `src/main.tsx`) |
| Team URL slugs | Built with `iconv` transliteration, which differs by OS (macOS gave `san-jos-e-state`, `hawai-i`) | `stringi` Latin-ASCII, apostrophes dropped: `san-jose-state`, `hawaii` on every OS |
| Stale team files | A renamed slug left its old `team/<slug>.json` behind | Exporter deletes orphans; validator rejects them |
| Model page | Named "Week 3 of 2026" in running text | Wording no longer tied to a season or week |
| `LIMITATIONS.md` | Said scenario filtering was unavailable | Replaced with what What-if cannot do |
| Hard-coded "all 12 games" | 8 teams play 11, one plays 13 | Uses each team's real game count |

## For your decision

| Item | Where | Why it is still there | Options |
|---|---|---|---|
| Conference lists `P4_CONFS`, `G6_CONFS` and the Notre Dame rule | `R/publish/export_site_data.R` (bid type and "Power 4 / Group of 6" labels) | They replicate cfbseedR's `autobid = "2026"` rule, which does not export its lists. Membership itself comes from metadata. | Keep (documented), or read the lists from cfbseedR internals if it ever exposes them. Must be revisited if the CFP format changes. |
| "2026 rules" in the Playoff PNG caption and Model page | `src/site/graphics.ts`, `src/site/pages/Model.tsx` | It names the CFP format (cfbseedR's `"2026"` autobid rule), not the season | Keep, or rename to "12-team format". |
| `data/reference`-driven season 2026 defaults | `CFB_SEASON` default in R scripts and exporter | Frozen C2 inputs exist for 2026 only (a new season needs a new freeze anyway) | Keep until the next season's freeze. |
| Legacy views and their CSS | `src/SeasonSimulations.tsx`, `src/BettingAnalysis.tsx`, `src/styles.css`, `src/betting.css`, `src/exportPlayoff.ts`, `src/TeamBoard.tsx`, `src/ui.tsx` | They serve `/simulations/` and `/betting/`, including the two playoff downloads you asked to keep | Keep. Or retire them once the new Playoff page covers them: the Playoff Hunt PNG has no new equivalent yet. Scoping `styles.css` would save ~7 KB of CSS on other pages (`PERFORMANCE.md`). |
| Two versions of the rankings PNG | Rankings: "Top 25 PNG" (new style) and "All teams PNG" (legacy style) | Both work; the legacy one is the original 138-team graphic | Keep both, or restyle the all-teams graphic in the new look. |
| Model-vs-market computed in the browser | `src/betting.ts` on `/betting/` | Legacy feature kept (known exception to "R computes, browser displays") | Export it from R and drop the browser calculation. |
| v1 data files | `public/data/{ratings,simulations,betting}.json` + week archives | Still feed the legacy views and the PNG exports | Keep while the legacy views exist. |
| `sim$wins_scope` text | `R/simulation/simulate_season.R` | Says wins include conference championships; they do not | Model-code fix; see `TODO.md`. |
| Logo small copies | `public/logos/sm/` made with macOS `sips` | CI mirrors originals only (no image library in the Node toolchain) | Keep (new teams fall back to originals), or add a resize step to `scripts/sync_logos.mjs` with a small dependency. |
