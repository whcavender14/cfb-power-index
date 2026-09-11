# CFB Power Index

A public, static college-football analytics dashboard built with React, TypeScript, Vite, and Tailwind CSS. Visitors load versioned JSON and team-logo images; no database, application server, R installation, or API credentials are needed in their browser.

## Run locally

Use Node.js 22. Install pnpm 11.19.0 (the version pinned in `package.json`), then run:

```sh
pnpm install --frozen-lockfile
pnpm dev
```

Open the local URL printed by Vite. `pnpm test` checks the public data contract; `pnpm build` type-checks and produces `dist/`; `pnpm preview` serves that production build. Both views use hash navigation, so refreshes and direct `#simulations` links work on GitHub Pages without server rewrites. Relative Vite asset paths support project repositories, account sites, and custom domains.

## What the supplied data supports

- Power ratings now come from **`run_2026_rankings.R`**, which builds the selected frozen vCurrent model and writes `outputs/round4/current_2026_rankings.csv`. All **138 FBS teams** have ratings. The attached Round 5 CSV matched this output exactly by team ID across all 138 power ratings.
- The website preserves `power_rating`, `off_rating`, and `def_rating` without changing signs. **Lower defensive ratings are better**; power equals offense minus defense. Preseason movement uses this model’s `pre_power`, never the older model’s preseason CSV.
- Weekly comparisons use only `production_ratings_<season>_wk<NN>.rds` snapshots with matching candidate, design hash, and feature hash. Legacy `ratings_*.rds` snapshots are not used. No previous production week was supplied, so weekly movement remains unavailable initially.
- The supplied simulation script was run for **1,000 seasons**, producing results for all 138 FBS teams with the vCurrent / EB_features model and a September 7, 2026 information cutoff. Simulation execution time is recorded separately from the cutoff.
- No preseason simulation or preseason Vegas totals were supplied. Those columns remain `null` in JSON and display “—”. Historical game results are not treated as forecasts.
- Team IDs, names, conferences, and original HTTPS logo URLs come directly from `teams_2026.rds`. Failed images display team initials.

## GitHub Pages deployment

1. Create a GitHub repository with `main` (or `master`) as its default branch and add this project. Include `src/`, `public/`, `scripts/`, `.github/`, `pipeline_inputs/`, the package files and lockfile, the supplied R scripts, preseason CSV, and tracked team/rating snapshots. The `.gitignore` excludes large research caches and local credentials. Do not force-add credential files.
2. In **Settings → Pages → Build and deployment**, choose **GitHub Actions**. The workflow uses GitHub’s official Pages artifact and deployment actions; see [GitHub’s custom-workflow guide](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages).
3. Add an Actions repository secret named **`CFBD_API_KEY`** for CollegeFootballData access. It is injected only into the R refresh step. Never create a `VITE_` variable for credentials or put credentials in `public/`.
4. Allow the workflow to write refreshed data to the default branch. A branch protection rule that requires PRs or rejects bot commits will block the refresh commit; configure your repository policy accordingly. No personal access token is needed for the supplied workflow.
5. Push the project. A push builds and deploys the checked-in JSON without calling data providers. In **Actions → CFB Power Index → Run workflow**, leave **refresh_data** enabled to run R first, or disable it for a deployment-only run. The optional season override accepts a four-digit year.

The Vite configuration follows the [static deployment documentation](https://vite.dev/guide/static-deploy.html). No GitHub repository has been created or published by this local implementation; the deployment workflow runs after you put these files in your repository and enable Pages.

## Weekly refresh

### Betting lines and reproducible installs

The third tab, **Betting Line Analysis** (`#betting`), uses the current production ratings and the HFA saved by `run_2026_rankings.R`. Both the calculator and matchup table use `away power − home power − HFA`; neutral sites use zero HFA. Negative lines favor the home team. Signed discrepancy is model minus market: negative suggests the home side, positive the away side. This is a model comparison, not an estimated probability of covering.

`scripts/export_betting_data.R` selects the provider week containing the next uncompleted scheduled game and retrieves CollegeFootballData sportsbook spreads through `cfbfastR::cfbd_betting_lines`. It prefers DraftKings, then ESPN Bet, Bovada, Caesars, and consensus. Other available providers follow alphabetically. It publishes the selected provider and retrieval time for each quote. The source does not supply a sportsbook update timestamp, so that field remains unavailable. Quotes refresh with the weekly/manual pipeline, not continuously; the browser flags quotes older than 24 hours. Games without quotes or rated opponents remain explicitly unavailable for the affected metrics.

Run `CFB_SEASON=2026 CFB_REFRESH_SCHEDULE=true Rscript scripts/export_betting_data.R` to refresh this feed after exporting matching ratings. It uses the existing `CFBD_API_KEY` environment secret only in R. `pnpm export:data` exports both the rating/simulation snapshots and betting feed. Run `Rscript tests/test_betting_export.R` for schedule-selection and quote-normalization checks.

For pnpm **11.19.0**, commit the root `pnpm-workspace.yaml` with `allowBuilds: { esbuild: true }`. Configuration under `package.json`'s `pnpm` field is not used by this version. Both workflows validate the supported configuration before running `pnpm install --frozen-lockfile`; no interactive approval or blanket script permission is needed. Dependency versions and the lockfile are unchanged. `bash scripts/verify-clean-build.sh` verifies installation with a fresh dependency directory and fresh pnpm store, then runs the tests and production build. This ensures a cached esbuild binary cannot hide an installation failure.

`.github/workflows/site.yml` runs on Mondays at **09:00 UTC from August through January**, with manual dispatch available throughout the year. January uses the prior calendar year’s season. GitHub may delay scheduled jobs; the displayed timestamp always comes from the actual source result.

The workflow:

1. Installs Node, pnpm, R 4.4.3, and the R packages used by the supplied models. `cfbseedR` is pinned to the same GitHub revision used locally: `4a1c78e184773c22da43c40a9eb999d23283297f`. R dependencies use [r-lib’s dependency action](https://github.com/r-lib/actions/tree/v2/setup-r-dependencies).
2. Restores weekly caches and the small `pipeline_inputs/` bundle. The bundle holds the production freeze, feature artifact, verified historical source files, frozen weekly history, and initial lambda. It does not contain raw play-by-play or credentials. Mutable caches remain in `cfb_data/`; the older weekly history/lambda seeds are unused by the production rankings entrypoint.
3. Runs `run_2026_rankings.R` headlessly with a fresh current-season schedule and the frozen selected production candidate. It saves its regular CSV plus dedicated production snapshots under `CFB_DATA_DIR`. Graphic generation remains enabled for normal local runs but is disabled in CI.
4. Runs `cfb_simulation.R` with a fresh current-season schedule in a separate cache. Frozen training sources are preserved. The script retains its membership, unresolved-result, and postseason checks. It preserves only completed results available before its Monday cutoff. Future years require an intentional update to the supplied 2026 playoff/model assumptions; unsupported simulations produce an unavailable state.
5. Exports allowlisted browser data, validates it, builds the static site, and commits `public/data/` plus team/production-rating RDS comparison snapshots. Simulation RDS and PBP stay in the Actions cache; lightweight simulation JSON is versioned in Git.
6. Deploys in the same workflow. This avoids relying on a new push event from a `GITHUB_TOKEN` commit.

If a **ratings refresh fails**, the workflow stops and the previously published site retains its true timestamp. If **simulations fail**, the workflow publishes valid ratings with an explicit simulation “Data unavailable” state and no stale current forecasts. Missing individual metrics always remain null. A missing team metadata file or a malformed data contract fails the export rather than fabricating membership or values.

### Local R commands

Install the corresponding R packages once:

```r
install.packages(c("dplyr", "tidyr", "purrr", "tibble", "rlang", "ggplot2",
                   "jsonlite", "Matrix", "quantreg", "cfbfastR", "remotes"))
remotes::install_github("sportsdataverse/cfbseedR@4a1c78e184773c22da43c40a9eb999d23283297f")
```

Run from the repository root. Supply the API key through your shell environment or an untracked local `.Renviron` file.

```sh
# Export supplied snapshots only; no provider calls or model fitting.
CFB_SEASON=2026 Rscript scripts/export_public_data.R

# Restore production artifacts after a fresh clone.
Rscript scripts/restore_pipeline_inputs.R

# Full current-data refresh.
CFB_SEASON=2026 CFB_REFRESH_SCHEDULE=true Rscript scripts/weekly_refresh.R

# Optional: validate exporter behavior in isolated temporary directories.
Rscript tests/test_public_export.R
```

The production schedule loader can fall back to published schedules without a key; provider access and current-season availability determine whether a refresh succeeds. A cold cache can take substantially longer than a normal weekly update. Run `Rscript scripts/prepare_simulation_inputs.R` only when intentionally provisioning a revised production freeze; commit the resulting bundle with its corresponding model code. Do not replace frozen training sources with live data.

## Public data contract

See [docs/DATA_CONTRACT.md](docs/DATA_CONTRACT.md) for field definitions, units, null handling, source mappings, and optional input formats.

`public/data/ratings.json` and `public/data/simulations.json` are schema-version-1 envelopes with `season`, `week`, `updated_at`, `status`, `model`, and a `teams` array. Every team row repeats season/week/timestamp so it can be extracted independently. Probabilities use fractions in `[0,1]`; the UI converts them to percentages. Missing values are JSON `null`, never zero or strings. Latest successful datasets also live under `public/data/<season>/week-<NN>/`; reruns of a week are preserved by Git history.

## Layout and accessibility

The navy/lime interface includes searchable and conference-filtered tables, stable numeric sorting with nulls always last, global rating ranks, pagination, sticky table headers, keyboard-focus indicators, screen-reader labels, metric-definition tooltips, and a skip link. Mobile layouts keep the page within the viewport and allow horizontal scrolling inside the tables. Search and conference choices persist between views; each view resets to its default numeric sort. Logo failure never removes the visible team name.
