# Writes public/data/v2/player/<athlete_id>.json (the player detail modal) for every player the site lists
# (statistical leaders and players by usage), from the committed site data and CFBD pulls (R/publish/player_profiles.R).
# The first run pulls and caches past seasons (~5 minutes); later runs pull only the current season.
#   Rscript scripts/export_player_profiles.R
suppressPackageStartupMessages(library(jsonlite))
if (!exists("PATHS")) source(file.path(Sys.getenv("CFB_PROJECT_ROOT", "."), "config", "paths.R"))
source(file.path(PATHS$root, "R", "publish", "player_profiles.R"))
source(file.path(PATHS$root, "R", "publish", "player_usage.R"))
v2 <- file.path(PATHS$public_data, "v2")
index <- fromJSON(file.path(v2, "index.json"), simplifyVector = FALSE)
teams <- fromJSON(file.path(v2, "teams.json"))$teams
season <- index$meta$season; week <- index$meta$ratings_week
dir.create(PATHS$state, recursive = TRUE, showWarnings = FALSE)

# Players the site shows: leaders in team files, players in usage files.
ids <- character()
for (f in list.files(file.path(v2, "team"), full.names = TRUE)) {
  l <- fromJSON(f, simplifyVector = FALSE)$leaders
  if (!is.null(l)) for (k in c("passing", "rushing", "receiving", "sacks", "interceptions")) ids <- c(ids, vapply(l[[k]], function(p) as.character(p$athlete_id), ""))
}
for (f in list.files(file.path(v2, "usage"), full.names = TRUE)) {
  u <- fromJSON(f, simplifyVector = FALSE)
  for (side in list(u$offense, u$defense)) for (g in side) ids <- c(ids, vapply(g, function(p) as.character(p$athlete_id), ""))
  ids <- c(ids, vapply(u$key_players, function(p) as.character(p$athlete_id), ""))
}
roster <- pull_rosters(season)
# Depth-chart (TWO-DEEP) starters carry names only: match them to the team roster by name to get an athlete id.
name_key <- function(x) gsub("[^a-z]", "", tolower(x))
depth_id <- function(name, school) {
  if (is.null(roster)) return(NA_character_)
  k <- which(roster$team == school & name_key(paste(roster$first_name, roster$last_name)) == name_key(name))
  if (length(k) == 1L) roster$athlete_id[k] else NA_character_
}
usage_files <- list.files(file.path(v2, "usage"), full.names = TRUE)
depth_ids <- list()
for (f in usage_files) {
  u <- fromJSON(f, simplifyVector = FALSE)
  school <- teams$team[teams$team_id == u$team_id]
  if (!length(school) || is.null(u$depth)) next
  depth_ids[[f]] <- lapply(u$depth, function(r) if (length(r$players)) depth_id(r$players[[1]]$name, school) else NA_character_)
  ids <- c(ids, unlist(depth_ids[[f]]))
}
ids <- unique(ids[!is.na(ids) & nzchar(ids)])
cat(sprintf("players listed on the site: %d\n", length(ids)))

all_games <- career_games(season, week)
games <- all_games[all_games$athlete_id %in% ids, , drop = FALSE]
recruits <- pull_recruits(PROFILE_FIRST_SEASON - 3L, season)
portal <- pull_portal(PROFILE_FIRST_SEASON + 1L, season)

# CFBD school name -> team id, from every game row we have (covers FCS and past opponents too).
name_ids <- c(setNames(games$team_id, games$team), setNames(teams$team_id, teams$team))
name_ids <- name_ids[!duplicated(names(name_ids))]
team_id_of <- function(x) if (is.null(x) || is.na(x) || !x %in% names(name_ids)) NA_character_ else unname(name_ids[[x]])

out_dir <- file.path(v2, "player")
unlink(out_dir, recursive = TRUE); dir.create(out_dir)
by_id <- split(games, games$athlete_id)
n <- 0L
for (id in ids) {
  g <- by_id[[id]]
  r <- if (!is.null(roster)) roster[roster$athlete_id == id, , drop = FALSE] else NULL
  r <- if (!is.null(r) && nrow(r)) r[1, ] else NULL
  if (is.null(g) && is.null(r)) next
  if (is.null(g)) g <- games[0, ]
  rec <- NULL
  if (!is.null(recruits)) {
    rid <- if (!is.null(r)) as.character(unlist(r$recruit_ids)) else character()
    k <- which(recruits$athlete_id == id | recruits$id %in% rid)
    if (length(k)) rec <- recruits[k[order(-recruits$year[k])][1], ]
  }
  p <- NULL
  if (!is.null(portal)) {
    nm <- tolower(if (!is.null(r)) paste(r$first_name, r$last_name) else g$athlete_name[1])
    p <- portal[portal$key == nm & portal$origin %in% unique(g$team), , drop = FALSE]
    p <- p[order(p$season), , drop = FALSE]
  }
  body <- player_profile(id, g, r, rec, p, team_id_of, season)
  write_json(list(meta = index$meta, source = "CollegeFootballData (box scores, roster, recruiting, transfer portal)",
                  through_week = week, player = body),
             file.path(out_dir, paste0(id, ".json")), auto_unbox = TRUE, na = "null", null = "null", digits = 6)
  n <- n + 1L
}
cat(sprintf("player profiles: %d\n", n))

# Depth-chart stat lines: each starter's current-season box-score totals (NULL when none; offensive linemen usually).
cur <- games[games$season == season & !games$post, , drop = FALSE]
m <- 0L
for (f in names(depth_ids)) {
  u <- fromJSON(f, simplifyVector = FALSE)
  for (i in seq_along(u$depth)) {
    id <- depth_ids[[f]][[i]]
    if (!length(u$depth[[i]]$players)) next
    g <- if (is.na(id)) cur[0, ] else cur[cur$athlete_id == id, , drop = FALSE]
    u$depth[[i]]$players[[1]]$athlete_id <- if (is.na(id)) NULL else id
    u$depth[[i]]$players[[1]]$season <- if (nrow(g)) c(list(gp = nrow(g)), as.list(setNames(colSums(as.matrix(g[, unname(PROFILE_STATS), drop = FALSE])), names(PROFILE_STATS)))) else NULL
    m <- m + (nrow(g) > 0)
  }
  write_json(u, f, auto_unbox = TRUE, na = "null", null = "null", digits = 6)
}
cat(sprintf("depth-chart starters with stats: %d\n", m))

# Search index for the header search box: one compact row per player profile, [athlete_id, name, team_id, position, jersey].
files <- list.files(out_dir, pattern = "\\.json$", full.names = TRUE)
rows <- lapply(files, function(f) { p <- fromJSON(f, simplifyVector = FALSE)$player
  list(p$athlete_id, p$name, if (is.null(p$team_id)) NA else p$team_id, if (is.null(p$position)) NA else p$position, if (is.null(p$jersey)) NA else p$jersey) })
write_json(list(meta = index$meta, columns = c("athlete_id", "name", "team_id", "position", "jersey"), players = rows),
           file.path(v2, "players.json"), auto_unbox = TRUE, na = "null", null = "null")
cat(sprintf("player search index: %d\n", length(rows)))
