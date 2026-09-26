# Weekly update runbook

The site refreshes itself. This page says what happens each week, what to check, and what to do when something fails.

## What runs, and when

GitHub Actions workflow `.github/workflows/site.yml`, every Monday 09:00 UTC from August to January (and on demand from the Actions tab: "Run workflow").

| Step | Command | Produces | Notes |
|---|---|---|---|
| 1. Verify frozen inputs | `Rscript scripts/verify_frozen_inputs.R` | pass/fail | Checks the 29 frozen model files against their recorded checksums. |
| 2. Ratings and simulation | `Rscript scripts/run_weekly_pipeline.R` (with `CFB_REFRESH_SCHEDULE=true`, `CFBD_API_KEY`) | `output/state/production_ratings_<season>_latest.rds`, `simulations_<season>_latest.rds` | Current C2, cutoff = the most recent Monday 00:00 UTC. Pulls schedule, FCS games and play-by-play from CFBD. |
| 3. Export | `Rscript scripts/03_export_public_data.R` (with `CFB_EXPORT_BETTING=true`) | `public/data/*.json` (v1), `public/data/v2/*` (site), week archives | Also pulls season player stats (one CFBD call; skip with `CFB_PULL_PLAYERS=false`) and betting lines. |
| 4. Validate | `pnpm test` | pass/fail | 37 tests, including `scripts/validate_site_data.mjs`: probabilities, ranks, playoff sums, history, record distributions, conference sums, scenario file, résumé order, player leaders. |
| 5. Logos | `pnpm logos` | `public/logos/<team_id>.png` | Mirrors missing logos only. |
| 6. Build | `pnpm build` | `dist/` | Validates again, type-checks, bundles, prerenders every route (161 + `404.html`). |
| 7. Commit and deploy | workflow | commit "data: refresh CFB model output" on `public/data`; Pages deploy | Only `public/data` is committed by CI. |

If any step fails, nothing is deployed and last week's site stays up.

## After the run: two-minute check

1. Open the site. The homepage line says "Ratings through Week N" (N = the week just completed) and today's "Last updated" date.
2. Rankings: movement arrows show numbers (not "—"). From week 4 on, the comparison week is published, not "(reconstructed)".
3. Playoff: the projected field shows 12 teams; odds look sensible.
4. A team page: schedule shows last week's results; "Statistical leaders" says "Weeks 1–N".
5. `/simulations/`: both downloads ("Playoff Hunt", "Projected Playoff") produce images.

## When something fails

| Symptom | Likely cause | Action |
|---|---|---|
| Workflow fails at step 1 | A frozen model file changed | Do not bypass. Find the change (`git log -- <file>`); the model must not change without a new promotion. |
| Step 2 fails with a CFBD error | API outage, rate limit, or key problem | Re-run the workflow later ("Run workflow"). Check the `CFBD_API_KEY` secret if it keeps failing. |
| Step 2 fails: "final FBS-vs-FBS games … missing from the play-by-play pull" | CFBD has not posted play-by-play yet | Re-run later in the day. |
| Site shows "Simulation results are unavailable" | The simulation failed or came from another model | Ratings are still correct. Re-run the workflow; check the step 2 log. |
| Step 4 fails ("validation failed") | The export produced inconsistent data | Read the listed problems. The previous site stays live. Fix the cause; never edit JSON by hand. |
| No "Statistical leaders" on team pages | Player-stats pull failed, or it covers a different week | Re-run; the section returns when the pull covers the ratings week. |
| Movement shows "—" | No CFPi+ ratings for the previous week | Expected only if a week was skipped or the model changed. |

## Manual run (local)

```bash
CFB_REFRESH_SCHEDULE=true CFBD_API_KEY=... Rscript scripts/run_weekly_pipeline.R
```

```bash
CFB_EXPORT_BETTING=true Rscript scripts/03_export_public_data.R
```

```bash
pnpm test && pnpm build
```

Preview the production build with the Pages base path: serve the folder that contains `dist/` renamed to `cfb-power-index/` (for example `python3 -m http.server`) and open `/cfb-power-index/`.

## Occasional tasks

- **New season:** the frozen C2 inputs support 2026 only. A new season needs its own freeze (`scripts/production/c2_freeze_season_inputs.R`) and a new `data/reference/teams_<season>.rds`; realignment is picked up from that file.
- **Rebuilding past weeks' ratings** (only if a published week is ever missing): `scripts/history/reconstruct_c2_history.R <cutoffs>`. It refuses to write unless it first reproduces the latest published week exactly. Commit `data/history/c2_reconstructed_<season>.csv`.
- **New logos:** `pnpm logos` mirrors originals. The site prefers 144 px copies in `public/logos/sm/` (made with `sips -Z 144` on macOS); teams without one fall back to the original automatically.
