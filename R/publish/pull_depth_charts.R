# =============================================================================
# R/publish/pull_depth_charts.R — weekly depth-chart input (TWO·DEEP, with permission; R/publish/depth_charts.R).
#
# Run from scripts/03_export_public_data.R next to the player-stats pull. Writes
# output/state/depth_charts_<season>.rds: one row per team, spot and depth (starters and backups), keyed by season,
# week (the ratings week, as for player stats) and team_id; earlier weeks are kept. A committed copy in
# data/reference/depth_charts/ is the "last good file": the CI job starts from a clean state, so the pull seeds from
# it and, on success, updates it (the workflow commits it). If the pull fails or parses fewer than 100 teams, the last
# good file is kept and a warning is logged; the rest of the run continues. Display only: never a model input.
# =============================================================================
local({
  season <- as.integer(Sys.getenv("CFB_SEASON", "2026"))
  source(file.path(PATHS$root, "R", "publish", "depth_charts.R"), local = TRUE)
  state_file <- file.path(PATHS$state, sprintf("depth_charts_%d.rds", season))
  ref_file <- file.path(PATHS$reference, "depth_charts", sprintf("depth_charts_%d.rds", season))
  last <- if (file.exists(state_file)) readRDS(state_file) else if (file.exists(ref_file)) readRDS(ref_file) else NULL
  if (!is.null(last) && !file.exists(state_file)) saveRDS(last, state_file)          # seed the clean CI state
  snap_file <- file.path(PATHS$state, sprintf("production_ratings_%d_latest.rds", season))
  week <- if (file.exists(snap_file)) as.integer(readRDS(snap_file)$week) else NA_integer_
  if (is.na(week)) { warning("Depth charts: no ratings week; keeping the last good file.", call. = FALSE); return(invisible()) }
  teams <- tryCatch(jsonlite::fromJSON(file.path(PATHS$public_data, "v2", "teams.json"))$teams, error = function(e) NULL)
  if (is.null(teams)) { warning("Depth charts: no team directory; keeping the last good file.", call. = FALSE); return(invisible()) }
  dc <- tryCatch(pull_depth_charts(teams$slug), error = function(e) { warning("Depth charts: pull failed: ", conditionMessage(e), call. = FALSE); NULL })
  if (is.null(dc) || length(dc) < 100L) {
    warning(sprintf("Depth charts: only %d teams parsed; keeping the last good file%s.", if (is.null(dc)) 0L else length(dc),
                    if (is.null(last)) " (none yet: team pages fall back to the usage chart)" else sprintf(" (week %d)", max(last$week))), call. = FALSE)
    return(invisible())
  }
  new <- depth_long(dc, teams, season, week)
  out <- rbind(if (!is.null(last)) last[last$week != week, , drop = FALSE], new)
  saveRDS(out, state_file)
  dir.create(dirname(ref_file), recursive = TRUE, showWarnings = FALSE)
  saveRDS(out, ref_file)
  cat(sprintf("Depth charts: %d teams, %d spots, %d players listed (week %d) -> %s\n", length(unique(new$team_id)),
              nrow(unique(new[, c("team_id", "order")])), nrow(new), week, state_file))
})
