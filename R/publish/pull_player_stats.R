# =============================================================================
# R/publish/pull_player_stats.R: season player statistics for the site's
# "Statistical leaders" section (docs/website/DATA_CONTRACT_V2.md).
#
# One CFBD call (/stats/player/season via cfbfastR::cfbd_stats_season_player)
# for the whole season, cut at the ratings week so the stats cover the same
# weeks as "Ratings through Week X". Written to
# output/state/player_stats_<season>.rds with the week it covers. Display only:
# nothing here feeds the model. If the pull fails, the previous file is kept
# only when it covers the same week; the exporter shows no leaders otherwise.
# =============================================================================
local({
  season <- as.integer(Sys.getenv("CFB_SEASON", "2026"))
  snap_file <- file.path(PATHS$state, sprintf("production_ratings_%d_latest.rds", season))
  if (!file.exists(snap_file)) { message("Player stats: no ratings snapshot; skipped."); return(invisible()) }
  week <- as.integer(readRDS(snap_file)$week)
  out <- file.path(PATHS$state, sprintf("player_stats_%d.rds", season))
  if (is.na(week) || week < 1L) { message("Player stats: preseason; skipped."); return(invisible()) }
  x <- tryCatch(suppressWarnings(suppressMessages(
         cfbfastR::cfbd_stats_season_player(year = season, season_type = "regular", end_week = week))),
       error = function(e) { message("Player stats pull failed: ", conditionMessage(e)); NULL })
  if (is.null(x) || !NROW(x)) { message("Player stats: nothing pulled; leaders will be omitted unless a week-", week, " file exists."); return(invisible()) }
  x <- as.data.frame(x)
  if (anyDuplicated(x[, c("team", "athlete_id")])) stop("Player stats: duplicate player rows for a team; refusing to publish.")
  attr(x, "season") <- season; attr(x, "end_week") <- week; attr(x, "pulled_at") <- Sys.time()
  saveRDS(x, out)
  cat(sprintf("Player stats: %d players, %d teams, weeks 1-%d -> %s\n", nrow(x), length(unique(x$team)), week, out))
})
