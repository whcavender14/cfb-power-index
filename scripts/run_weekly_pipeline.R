# =============================================================================
# scripts/run_weekly_pipeline.R — the whole weekly production run, end to end.
#
# Equivalent of the old scripts/weekly_refresh.R that GitHub Actions runs:
#   0. seed output/state with the committed 2026 production snapshots (once)
#   1. build ratings                    (scripts/01_build_ratings.R)
#   2. simulate the season              (failure => explicit "unavailable")
#   3. export JSON                      (scripts/03_export_public_data.R)
#
# Usage (from the project root):
#   CFB_REFRESH_SCHEDULE=true CFBD_API_KEY=... Rscript scripts/run_weekly_pipeline.R
#   CFB_SIM_COUNT=50 Rscript scripts/run_weekly_pipeline.R        # offline smoke test
# The prospective snapshot (scripts/04_...) is deliberately a separate step.
# =============================================================================
source("config/paths.R")
source("config/production.R")
ensure_output_dirs()
season <- as.integer(Sys.getenv("CFB_SEASON", "2026"))

# 0. Seed runtime state with earlier weekly snapshots so weekly_change works.
for (f in list.files(PATHS$snapshot_seed, pattern = sprintf("^production_ratings_%d_(wk[0-9]+|latest)[.]rds$", season), full.names = TRUE)) {
  dest <- file.path(PATHS$state, basename(f))
  if (!file.exists(dest)) file.copy(f, dest)
}

# 1. Ratings: a failure stops the run; stale data is never stamped as fresh.
rscript <- file.path(R.home("bin"), "Rscript")
if (system2(rscript, "scripts/01_build_ratings.R") != 0L) stop("Production ratings build failed.")

# 2. Simulation: failure publishes real ratings with an explicit unavailable state.
status <- tryCatch({
  if (season != PRODUCTION$supported_season) stop("Simulation assumptions support 2026 only.")
  e <- new.env(parent = globalenv())
  suppressPackageStartupMessages(sys.source(PATHS$simulate, envir = e))
  e$run_season_simulation(season = season)
  list(status = "available", attempted_at = Sys.time())
}, error = function(e) {
  message("Simulation unavailable: ", conditionMessage(e))
  list(status = "unavailable", attempted_at = Sys.time())
})
saveRDS(status, file.path(PATHS$state, sprintf("simulation_status_%d.rds", season)))

# 3. Export.
if (system2(rscript, "scripts/03_export_public_data.R") != 0L) stop("Export failed.")
cat("Weekly pipeline complete. Outputs in", PATHS$output, "\n")
