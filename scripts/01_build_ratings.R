# =============================================================================
# scripts/01_build_ratings.R — build the current production power ratings.
#
# Replaces the old folder's run_2026_rankings.R (same model call, same
# outputs), with paths from config/paths.R.
#
# Usage (from the project root):
#   Rscript scripts/01_build_ratings.R
#   Rscript scripts/01_build_ratings.R 2026-09-21T00:00:00Z            # explicit UTC cutoff
#   Rscript scripts/01_build_ratings.R 2026-09-21T00:00:00Z EB_features
#
# Environment:
#   CFB_SEASON=2026               only 2026 is supported by the frozen design
#   CFB_REFRESH_SCHEDULE=true     pull the live schedule/results from CFBD
#                                 (needs CFBD_API_KEY). Without it the frozen
#                                 2026 schedule is used, which only contains
#                                 results through 2026-09-09.
#   CFB_CREATE_GRAPHIC=true       also draw the top-30 PNG (downloads logos)
#
# Writes:
#   output/rankings/current_<season>_rankings.csv (+ _metadata.csv)
#   output/state/production_ratings_<season>_latest.rds and _wkNN.rds
# =============================================================================

source("config/paths.R")
source("config/production.R")
suppressPackageStartupMessages(source(PATHS$model_ops))
ensure_output_dirs()

args <- commandArgs(trailingOnly = TRUE)
as_of <- if (length(args) >= 1L) utc(args[[1L]]) else period_start(Sys.time())
candidate <- if (length(args) >= 2L) args[[2L]] else NULL
assert(!is.na(as_of), "Invalid UTC cutoff. Example: 2026-09-09T00:00:00Z")

season <- as.integer(Sys.getenv("CFB_SEASON", "2026"))
assert(identical(season, PRODUCTION$supported_season),
       "The frozen EB_features design only supports the 2026 season (see docs/MIGRATION_AUDIT_REPORT.md).")

schedule <- NULL
if (identical(Sys.getenv("CFB_REFRESH_SCHEDULE"), "true")) {
  live_cfg <- v4_config()
  live_cfg$cache_dir <- file.path(PATHS$state, "production_live")
  schedule <- read_schedule(season, live_cfg, refresh = TRUE)
} else {
  message("Using the frozen ", season, " schedule (results through 2026-09-09 only). ",
          "Set CFB_REFRESH_SCHEDULE=true for current results.")
}

ratings <- v5_build(season = season, as_of = as_of, candidate = candidate, schedule = schedule)

ranking <- ratings %>%
  arrange(desc(power_rating), team_id) %>%
  mutate(rank = row_number()) %>%
  rename(conference = conf) %>%
  select(rank, team, team_id, conference, power_rating, off_rating, def_rating,
         games_played, pre_power, prior_contribution, current_contribution,
         centering_contribution, feature_snapshot_id)

csv_file <- file.path(PATHS$rankings, sprintf("current_%d_rankings.csv", season))
write.csv(ranking, csv_file, row.names = FALSE)
write.csv(data.frame(season = season, candidate = attr(ratings, "candidate"),
                     information_cutoff_utc = format(as_of, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                     hfa_points = attr(ratings, "hfa"), design_hash = attr(ratings, "design_hash"),
                     feature_hash = attr(ratings, "feature_hash"), stringsAsFactors = FALSE),
          file.path(PATHS$rankings, sprintf("current_%d_rankings_metadata.csv", season)), row.names = FALSE)

print(ranking %>% select(rank, team, conference, power_rating, games_played), n = 25)
cat("\nWrote", csv_file, "\n")

# Snapshot consumed by the exporter (weekly_change needs the previous week's file).
frozen_schedule <- is.null(schedule)
if (frozen_schedule) schedule <- v4_schedule(season)
observed <- schedule$final %in% TRUE & schedule$available_at < as_of
week <- if (any(observed)) max(schedule$week[observed]) else 0L
# Guard (new): with the frozen schedule, a cutoff past its data horizon would
# silently mislabel stale ratings as the current week and overwrite that week's
# real snapshot. Keep the CSV above, but do not write weekly state in that case.
horizon <- max(schedule$available_at[schedule$final %in% TRUE])
stale <- frozen_schedule && as_of > horizon + 7 * 86400 && !identical(Sys.getenv("CFB_FORCE_STATE"), "true")
if (stale) {
  message("Frozen schedule ends ", format(horizon, "%Y-%m-%d"), "; NOT writing weekly state snapshots for cutoff ",
          format(as_of, "%Y-%m-%d"), ". Use CFB_REFRESH_SCHEDULE=true (or CFB_FORCE_STATE=true).")
} else {
  snapshot <- list(season = season, week = as.integer(week), updated_at = Sys.time(), hfa = attr(ratings, "hfa"),
                   as_of = as_of, candidate = attr(ratings, "candidate"),
                   design_hash = attr(ratings, "design_hash"), feature_hash = attr(ratings, "feature_hash"),
                   ratings = ranking)
  saveRDS(snapshot, file.path(PATHS$state, sprintf("production_ratings_%d_latest.rds", season)))
  saveRDS(snapshot, file.path(PATHS$state, sprintf("production_ratings_%d_wk%02d.rds", season, week)))
  cat("Wrote production snapshot for week", week, "to", PATHS$state, "\n")
}

if (identical(Sys.getenv("CFB_CREATE_GRAPHIC"), "true")) {
  source(PATHS$graphic)
  cat("Wrote", create_rankings_graphic(ranking, as_of, PATHS$graphics), "\n")
}
