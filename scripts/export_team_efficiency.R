# Writes public/data/v2/efficiency.json on its own, from the committed site data (games.json: which games entered the
# ratings; teams.json: FBS ids and names; index.json: meta) and cached play-by-play. The full export
# (R/publish/export_site_data.R) writes the same file; this script refreshes it without re-exporting anything else.
#   CFB_PLAYS_FILE=path/to/plays.rds Rscript scripts/export_team_efficiency.R
suppressPackageStartupMessages(library(jsonlite))
if (!exists("PATHS")) source(file.path(Sys.getenv("CFB_PROJECT_ROOT", "."), "config", "paths.R"))
source(file.path(PATHS$root, "R", "publish", "team_efficiency.R"))
source(file.path(PATHS$root, "R", "publish", "team_basic_stats.R"))
v2 <- file.path(PATHS$public_data, "v2")
index <- fromJSON(file.path(v2, "index.json"), simplifyVector = FALSE)
teams <- fromJSON(file.path(v2, "teams.json"))$teams
games <- fromJSON(file.path(v2, "games.json"))$games
ids <- games$game_id[games$in_ratings %in% TRUE]
plays <- read_site_plays(PATHS$state)
if (is.null(plays)) stop("No cached play-by-play: set CFB_PLAYS_FILE.")
missing <- setdiff(ids, as.character(plays$game_id))
if (length(missing)) message(length(missing), " rated game(s) have no plays in the cache: ", paste(head(missing, 10), collapse = ", "))
eff <- team_efficiency(plays, data.frame(team_id = teams$team_id, school = teams$team), ids)
gts <- pull_game_team_stats(index$meta$season, seq_len(index$meta$ratings_week), PATHS$state)
basic <- if (!is.null(gts)) team_basic_stats(gts, data.frame(team_id = teams$team_id, school = teams$team), ids) else NULL
write_json(efficiency_doc(eff, index$meta, length(ids), index$meta$ratings_week, basic), file.path(v2, "efficiency.json"),
           auto_unbox = TRUE, na = "null", null = "null", digits = 6)
cat(sprintf("efficiency.json: %d teams (%d with plays), %d games\n", nrow(eff), sum(!is.na(eff$plays)), length(ids)))
