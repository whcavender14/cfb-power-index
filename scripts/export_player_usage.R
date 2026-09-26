# Writes public/data/v2/usage/<slug>.json on its own (players by usage + roster details for the depth-chart graphic),
# from the committed site data and fresh CFBD pulls. The full export (R/publish/export_site_data.R) writes the same
# files; this refreshes them without re-exporting anything else.  Rscript scripts/export_player_usage.R
suppressPackageStartupMessages(library(jsonlite))
if (!exists("PATHS")) source(file.path(Sys.getenv("CFB_PROJECT_ROOT", "."), "config", "paths.R"))
source(file.path(PATHS$root, "R", "publish", "player_usage.R"))
source(file.path(PATHS$root, "R", "publish", "depth_charts.R"))
v2 <- file.path(PATHS$public_data, "v2")
index <- fromJSON(file.path(v2, "index.json"), simplifyVector = FALSE)
teams <- fromJSON(file.path(v2, "teams.json"))$teams
season <- index$meta$season; week <- index$meta$ratings_week
usage <- pull_player_usage(season); rosters <- pull_rosters(season)
ps_file <- file.path(PATHS$state, sprintf("player_stats_%d.rds", season))
ps <- if (file.exists(ps_file)) readRDS(ps_file) else NULL
dfile <- file.path(PATHS$state, sprintf("depth_charts_%d.rds", season))
depth <- if (file.exists(dfile)) readRDS(dfile) else NULL
if (!is.null(depth) && !is.data.frame(depth)) depth <- NULL
stats <- if (!is.null(ps) && identical(as.integer(attr(ps, "end_week")), as.integer(week))) ps else NULL
if (is.null(stats)) message("No player stats for week ", week, ": defense omitted.")
unlink(file.path(v2, "usage"), recursive = TRUE); dir.create(file.path(v2, "usage"))
n <- 0L
for (k in seq_len(nrow(teams))) {
  u <- team_player_usage(teams$team[k], usage, stats, rosters)
  dr <- if (!is.null(depth)) depth_rows(depth, teams$team_id[k]) else NULL
  d <- if (!is.null(dr)) enrich_depth(dr, if (!is.null(rosters)) rosters[rosters$team == teams$team[k], , drop = FALSE] else NULL) else NULL
  if (is.null(u) && is.null(d)) next
  if (is.null(u)) u <- list(offense = NULL, defense = NULL)
  u$depth <- d
  u$depth_source <- if (!is.null(d)) list(name = "TWO\u00b7DEEP", url = paste0(TWODEEP_BASE, if (teams$slug[k] %in% names(TWODEEP_SLUG)) TWODEEP_SLUG[[teams$slug[k]]] else teams$slug[k]),
                                          fetched_at = format(max(depth$fetched_at[depth$team_id == teams$team_id[k]]), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                                          week = max(depth$week[depth$team_id == teams$team_id[k]])) else NULL
  write_json(c(list(meta = index$meta, team_id = teams$team_id[k], offense_source = "CollegeFootballData player usage, season to date",
                    offense_pulled_at = if (!is.null(usage)) format(attr(usage, "pulled_at"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC") else NA,
                    defense_through_week = if (!is.null(stats)) week else NA), u),
             file.path(v2, "usage", paste0(teams$slug[k], ".json")), auto_unbox = TRUE, na = "null", null = "null", digits = 6)
  n <- n + 1L
}
cat(sprintf("usage: %d teams\n", n))
