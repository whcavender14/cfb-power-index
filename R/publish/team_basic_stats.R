# =============================================================================
# R/publish/team_basic_stats.R — standard team stats for the team and matchup pages (added to efficiency.json).
#
# Display only: nothing here feeds the model. Source: CollegeFootballData game team stats
# (cfbfastR::cfbd_game_team_stats, one call per regular-season week), which carry both sides of every game.
# Per-game averages over the regular-season games that entered the ratings (FCS opponents included):
#   points / points allowed, total / passing (net) / rushing yards and the same allowed, pass share of plays
#   (pass attempts / (pass + rush attempts)), third-down conversion %, turnover margin (opponent turnovers minus own:
#   a season total, not per game), penalty yards.
# Ranks among FBS teams, 1 = best: lower is better for everything "allowed" and for penalty yards; the pass share is
# ranked from most passing (1) and is descriptive, not better or worse.
# =============================================================================
suppressPackageStartupMessages(library(data.table))

# One file per season in output/state (same place as the other weekly inputs); weeks already pulled are reused
# unless refresh = TRUE for the latest week. Failures keep what exists and warn.
pull_game_team_stats <- function(season, weeks, state_dir) {
  f <- file.path(state_dir, sprintf("game_team_stats_%d.rds", season))
  have <- if (file.exists(f)) readRDS(f) else NULL
  got <- list()
  for (w in weeks) {
    if (!is.null(have) && w %in% have$week && w != max(weeks)) { got[[length(got) + 1L]] <- have[have$week == w, ]; next }
    x <- tryCatch(suppressWarnings(suppressMessages(cfbfastR::cfbd_game_team_stats(year = season, week = w, season_type = "regular"))),
                  error = function(e) { warning("Game team stats week ", w, ": ", conditionMessage(e), call. = FALSE); NULL })
    if (is.null(x) || !NROW(x)) { if (!is.null(have) && w %in% have$week) got[[length(got) + 1L]] <- have[have$week == w, ]; next }
    x <- as.data.frame(x); x$week <- as.integer(w); got[[length(got) + 1L]] <- x
  }
  out <- if (length(got)) as.data.frame(rbindlist(got, fill = TRUE)) else have
  if (!is.null(out)) saveRDS(out, f)
  out
}

team_basic_stats <- function(gts, teams, game_ids) {
  g <- as.data.table(gts)[as.character(game_id) %in% game_ids]
  pair <- function(x, i) suppressWarnings(as.numeric(vapply(strsplit(ifelse(is.na(x), "", as.character(x)), "-"), function(v) if (length(v) >= i) v[i] else NA_character_, "")))
  num <- function(x) suppressWarnings(as.numeric(x))
  g[, `:=`(pass_att = pair(completion_attempts, 2), third_conv = pair(third_down_eff, 1), third_att = pair(third_down_eff, 2),
           pen_yds = pair(total_penalties_yards, 2), team_id = as.character(NA))]
  g[, school := as.character(school)]
  x <- g[, .(games = .N, ppg = mean(num(points)), papg = mean(num(points_allowed)),
             ypg = mean(num(total_yards)), pass_ypg = mean(num(net_passing_yards)), rush_ypg = mean(num(rushing_yards)),
             ya_pg = mean(num(total_yards_allowed)), pass_ya_pg = mean(num(net_passing_yards_allowed)), rush_ya_pg = mean(num(rushing_yards_allowed)),
             pass_share = sum(pass_att, na.rm = TRUE) / (sum(pass_att, na.rm = TRUE) + sum(num(rushing_attempts), na.rm = TRUE)),
             third_pct = sum(third_conv, na.rm = TRUE) / sum(third_att, na.rm = TRUE),
             to_margin = sum(num(turnovers_allowed), na.rm = TRUE) - sum(num(turnovers), na.rm = TRUE),
             pen_ypg = mean(pen_yds, na.rm = TRUE)), by = school]
  out <- merge(data.table(team_id = as.character(teams$team_id), school = teams$school), x, by = "school", all.x = TRUE)
  higher <- c("ppg", "ypg", "pass_ypg", "rush_ypg", "third_pct", "to_margin", "pass_share")
  lower <- c("papg", "ya_pg", "pass_ya_pg", "rush_ya_pg", "pen_ypg")
  for (k in higher) out[, (paste0(k, "_rank")) := ifelse(is.na(get(k)), NA_integer_, rank(-get(k), ties.method = "min", na.last = "keep"))]
  for (k in lower) out[, (paste0(k, "_rank")) := ifelse(is.na(get(k)), NA_integer_, rank(get(k), ties.method = "min", na.last = "keep"))]
  num_cols <- c(higher, lower)
  out[, (num_cols) := lapply(.SD, function(v) round(v, 4)), .SDcols = num_cols]
  out[, school := NULL]
  out[order(team_id)]
}
