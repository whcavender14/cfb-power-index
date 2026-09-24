# =============================================================================
# scripts/02_simulate_season.R — Monte Carlo season simulation (cfbseedR).
#
# Usage (from the project root):
#   Rscript scripts/02_simulate_season.R
#   CFB_SIM_COUNT=50 CFB_AS_OF=2026-09-07T00:00:00Z Rscript scripts/02_simulate_season.R  # offline smoke test
#   CFB_REFRESH_SCHEDULE=true Rscript scripts/02_simulate_season.R
#
# Writes output/state/simulations_<season>_latest.rds. Method and assumptions:
# R/simulation/simulate_season.R and README.md ("Season simulation").
# =============================================================================
source("config/paths.R")
source("config/production.R")
ensure_output_dirs()
suppressPackageStartupMessages(source(PATHS$simulate))
sim <- run_season_simulation()
cat(sprintf("Simulated %d seasons as of %s (week %d). Saved to %s\n", sim$simulation_count,
            format(sim$as_of, "%Y-%m-%d", tz = "UTC"), sim$week, PATHS$state))
