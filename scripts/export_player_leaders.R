# Writes public/data/v2/players/leaders/<category>.json (the /players/ leaderboards; R/publish/player_leaders.R) from the
# committed site data (index, teams, games) and the pulls kept in output/state: season player stats
# (pull_player_stats.R), player PPA and success (pull_player_ppa.R), usage and roster (export_site_data.R).
# No CFBD calls. Run after export_site_data.R (scripts/03_export_public_data.R does), or alone:
#   Rscript scripts/export_player_leaders.R
suppressPackageStartupMessages(library(jsonlite))
if (!exists("PATHS")) source(file.path(Sys.getenv("CFB_PROJECT_ROOT", "."), "config", "paths.R"))
source(file.path(PATHS$root, "R", "publish", "player_leaders.R"))
source(file.path(PATHS$root, "R", "publish", "class_flags.R"))
v2 <- file.path(PATHS$public_data, "v2")
index <- fromJSON(file.path(v2, "index.json"), simplifyVector = FALSE)
teams <- fromJSON(file.path(v2, "teams.json"))$teams
games <- fromJSON(file.path(v2, "games.json"))$games
season <- index$meta$season; week <- index$meta$ratings_week
state <- function(f) { p <- file.path(PATHS$state, sprintf(f, season)); if (file.exists(p)) readRDS(p) else NULL }
stats <- state("player_stats_%d.rds")
out_dir <- file.path(v2, "players", "leaders")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)   # files are overwritten in place (deleting the folder makes iCloud keep conflict copies)
source_text <- "CollegeFootballData (season player stats, player PPA, player success, player usage, roster)"
if (is.null(stats) || is.null(week) || !identical(as.integer(attr(stats, "end_week")), as.integer(week))) {
  # Never show season stats that cover different weeks from the ratings: publish empty boards that say why.
  why <- if (is.null(stats)) "no season player stats pulled" else sprintf("player stats cover week %s, ratings week %s", attr(stats, "end_week"), week)
  write_empty_boards(out_dir, index$meta, why, source_text)
  message("Player leaders: ", why, "; empty boards written.")
} else {
  boards <- build_leaderboards(stats, teams, games, week, ppa = state("player_ppa_%d.rds"), usage = state("player_usage_%d.rds"), roster = state("rosters_%d.rds"), rs_lookup = recruit_class_lookup(season))
  for (cat in names(boards)) {
    write_json(c(list(meta = index$meta), boards[[cat]], list(source = source_text)), file.path(out_dir, paste0(cat, ".json")),
               auto_unbox = TRUE, na = "null", null = "null", digits = 6)
    b <- boards[[cat]]
    cat(sprintf("Player leaders %-9s %4d players, %4d qualified%s\n", cat, length(b$rows), sum(vapply(b$rows, function(r) isTRUE(r[[6]]), TRUE)),
                if (!is.null(b$ppa) && !b$ppa$available) paste0(" (PPA omitted: ", b$ppa$reason, ")") else ""))
  }
}
file.remove(setdiff(list.files(out_dir, pattern = "\\.json$", full.names = TRUE), file.path(out_dir, paste0(names(LEADER_CATS), ".json"))))
