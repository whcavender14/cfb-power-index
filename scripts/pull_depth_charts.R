# Pulls TWO·DEEP depth charts for every FBS team into output/state/depth_charts_<season>.rds (R/publish/depth_charts.R).
# Keeps the previous file when the new pull covers fewer than 100 teams (site changes, outage).
#   Rscript scripts/pull_depth_charts.R
if (!exists("PATHS")) source(file.path(Sys.getenv("CFB_PROJECT_ROOT", "."), "config", "paths.R"))
source(file.path(PATHS$root, "R", "publish", "depth_charts.R"))
season <- as.integer(Sys.getenv("CFB_SEASON", "2026"))
teams <- jsonlite::fromJSON(file.path(PATHS$public_data, "v2", "teams.json"))$teams
dc <- pull_depth_charts(teams$slug)
out <- file.path(PATHS$state, sprintf("depth_charts_%d.rds", season))
if (length(dc) < 100L) { message("Depth charts: only ", length(dc), " teams parsed; keeping the previous file."); quit(status = 0) }
dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
saveRDS(dc, out)
cat(sprintf("Depth charts: %d of %d teams -> %s\n", length(dc), nrow(teams), out))
