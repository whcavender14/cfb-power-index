# Opening sportsbook spread for every 2026 game, from CollegeFootballData (cfbfastR::cfbd_betting_lines spreadOpen).
# One provider per game (DraftKings, ESPN Bet, Bovada, Caesars, consensus, then the first other provider) whose
# opening spread is finite. Home perspective, same convention as betting.json: negative = the home team is favored.
# Evaluation and display only: never a model input. Needs CFBD_API_KEY. Writes public/data/<season>/opening_lines.json.
# Usage: Rscript R/publish/export_opening_lines.R   (env: CFB_SEASON, CFB_OPENING_WEEKS e.g. "1:5")
suppressPackageStartupMessages(library(jsonlite))
if (!exists("PATHS")) source(file.path(Sys.getenv("CFB_PROJECT_ROOT", "."), "config", "paths.R"))
season <- as.integer(Sys.getenv("CFB_SEASON", "2026"))
weeks <- eval(parse(text = Sys.getenv("CFB_OPENING_WEEKS", "1:15")))
stopifnot(nzchar(Sys.getenv("CFBD_API_KEY")))
priority <- c("DraftKings", "ESPN Bet", "Bovada", "Caesars", "consensus")
rows <- list()
for (w in weeks) {
  x <- tryCatch(as.data.frame(suppressMessages(cfbfastR::cfbd_betting_lines(year = season, week = w, season_type = "regular"))), error = function(e) NULL)
  if (is.null(x) || !nrow(x) || !all(c("id", "homeTeam", "awayTeam", "provider", "spreadOpen") %in% names(x))) next
  x <- x[!is.na(x$provider) & is.finite(suppressWarnings(as.numeric(x$spreadOpen))), , drop = FALSE]
  if (!nrow(x)) next
  p <- match(x$provider, priority); p[is.na(p)] <- 99L
  x <- x[order(x$id, p, x$provider), , drop = FALSE]
  x <- x[!duplicated(x$id), , drop = FALSE]
  for (i in seq_len(nrow(x))) rows[[length(rows) + 1L]] <- list(
    game_id = as.character(x$id[i]), week = as.integer(w), home_team = x$homeTeam[i], away_team = x$awayTeam[i],
    opening_spread = as.numeric(x$spreadOpen[i]), provider = x$provider[i])
  cat(sprintf("week %d: %d games with an opening spread\n", w, nrow(x)))
}
doc <- list(schema_version = 1L, season = season, source = "CollegeFootballData via cfbfastR::cfbd_betting_lines (spreadOpen)",
            convention = "home perspective; negative = home team favored", retrieved_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
            games = rows)
dir <- file.path(PATHS$public_data, season); dir.create(dir, recursive = TRUE, showWarnings = FALSE)
write_json(doc, file.path(dir, "opening_lines.json"), auto_unbox = TRUE, na = "null", null = "null", pretty = TRUE, digits = 8)
