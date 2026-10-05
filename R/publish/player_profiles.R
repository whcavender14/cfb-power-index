# =============================================================================
# R/publish/player_profiles.R: player detail files for the site's player modal
# (public/data/v2/player/<athlete_id>.json; docs/website/PLAYER_DATA.md).
#
# Display only: nothing here feeds the model. Every value is a CFBD value or a sum of CFBD box-score rows.
#   Game log:   CFBD game player stats (cfbfastR::cfbd_game_player_stats), one all-teams call per week and season
#               type, joined to CFBD game info for week, date, opponent and score. Cached in data/reference/player_cache
#               (completed seasons, and each completed week of the current season), so each is pulled once.
#   Seasons:    sums of the game log by season and team (so the season and game views always agree).
#   Bio:        CFBD roster (jersey, position, height, weight, hometown, class year) for the current season.
#   Recruiting: CFBD high-school recruiting rows (stars, national ranking, class, high school), joined by athlete_id.
#   Transfers:  CFBD transfer portal rows matched to the athlete id by name at the destination roster, else the origin
#               roster and box scores (R/publish/transfers.R; the portal has no athlete id).
# Not available in the box scores: air yards (so no ADOT), snaps, targets. The modal says so.
# =============================================================================
PROFILE_FIRST_SEASON <- 2021L

# Box-score columns kept per game, in this order (the JSON stores game rows as arrays against this list).
PROFILE_STATS <- c(
  pass_cmp = "passing_completions", pass_att = "passing_attempts", pass_yds = "passing_yds", pass_td = "passing_td",
  pass_int = "passing_int", rush_car = "rushing_car", rush_yds = "rushing_yds", rush_td = "rushing_td",
  rec = "receiving_rec", rec_yds = "receiving_yds", rec_td = "receiving_td",
  tkl = "defensive_tot", tfl = "defensive_tfl", sacks = "defensive_sacks", int = "interceptions_int",
  pd = "defensive_pd", qbh = "defensive_qb_hur", fum_lost = "fumbles_lost")

.quiet <- function(expr) tryCatch(suppressWarnings(suppressMessages(expr)), error = function(e) { message("  ", conditionMessage(e)); NULL })

# Committed cache (data/reference/player_cache/, refreshed and committed by the weekly workflow): completed seasons
# games_<season>.rds; current-season weeks games_<season>_wk<NN>.rds; recruiting classes recruits_<year>.rds and portal
# years portal_<year>.rds up to the current season. Anything cached is never pulled again.
PROFILE_CACHE <- file.path(PATHS$reference, "player_cache")
.cache_file <- function(...) file.path(PROFILE_CACHE, paste0(..., ".rds"))

# CFBD game info for a season (week, date, teams, score), used to place box-score rows. One call.
season_game_info <- function(season) {
  info <- .quiet(cfbfastR::cfbd_game_info(year = season, season_type = "both"))
  if (is.null(info) || !NROW(info)) return(NULL)
  info <- as.data.frame(info); info$game_id <- as.character(info$game_id); info
}

# Box-score rows for one week (all teams, one call), with game context from `info`.
pull_week_games <- function(season, week, type, info) {
  rows <- .quiet(cfbfastR::cfbd_game_player_stats(year = season, week = week, season_type = type))
  if (is.null(rows) || !NROW(rows)) return(NULL)
  rows <- as.data.frame(rows)
  rows <- rows[, intersect(c("game_id", "team", "athlete_id", "athlete_name", unname(PROFILE_STATS)), names(rows)), drop = FALSE]
  rows$game_id <- as.character(rows$game_id)
  rows <- rows[!is.na(rows$athlete_id) & rows$athlete_id != "" & !grepl("^-", rows$athlete_id), , drop = FALSE]
  rows$athlete_id <- as.character(rows$athlete_id)
  g <- info[match(rows$game_id, info$game_id), ]
  home <- g$home_team == rows$team
  rows$season <- as.integer(season); rows$week <- as.integer(g$week); rows$post <- g$season_type == "postseason"
  rows$date <- substr(as.character(g$start_date), 1, 10)
  rows$team_id <- as.character(ifelse(home, g$home_id, g$away_id))
  rows$opp_id <- as.character(ifelse(home, g$away_id, g$home_id)); rows$opp <- ifelse(home, g$away_team, g$home_team)
  rows$loc <- ifelse(g$neutral_site %in% TRUE, "N", ifelse(home, "H", "A"))
  rows$pts <- as.integer(ifelse(home, g$home_points, g$away_points)); rows$opp_pts <- as.integer(ifelse(home, g$away_points, g$home_points))
  rows <- rows[!is.na(rows$week), , drop = FALSE]
  for (k in unname(PROFILE_STATS)) rows[[k]] <- if (k %in% names(rows)) { v <- suppressWarnings(as.numeric(rows[[k]])); ifelse(is.na(v), 0, v) } else 0
  # CFBD occasionally repeats a player row within a game; keep one.
  rows <- rows[!duplicated(rows[, c("game_id", "athlete_id")]), , drop = FALSE]
  attr(rows, "pulled_at") <- Sys.time(); rows
}

# All box-score rows for one completed season (regular weeks 1..16 plus postseason): 18 calls, then cached for good.
pull_season_games <- function(season) {
  info <- season_game_info(season)
  if (is.null(info)) return(NULL)
  calls <- c(lapply(1:16, function(w) list(week = w, type = "regular")), list(list(week = 1L, type = "postseason")))
  rows <- do.call(rbind, Filter(Negate(is.null), lapply(calls, function(k) pull_week_games(season, k$week, k$type, info))))
  if (!is.null(rows)) attr(rows, "pulled_at") <- Sys.time()
  rows
}

# Past seasons and completed current-season weeks come from the cache; only missing ones are pulled
# (weekly: one game-info call plus one call for the new week).
career_games <- function(season, current_week) {
  dir.create(PROFILE_CACHE, recursive = TRUE, showWarnings = FALSE)
  out <- list()
  for (s in PROFILE_FIRST_SEASON:(season - 1L)) {
    f <- .cache_file("games_", s)
    if (!file.exists(f)) { message(sprintf("Player games %d: pulling (18 CFBD calls)", s)); x <- pull_season_games(s); if (!is.null(x)) saveRDS(x, f) }
    if (file.exists(f)) out[[as.character(s)]] <- readRDS(f)
  }
  weeks <- seq_len(current_week)
  missing <- weeks[!file.exists(.cache_file(sprintf("games_%d_wk%02d", season, weeks)))]
  if (length(missing)) {
    message(sprintf("Player games %d: pulling week(s) %s (%d CFBD calls)", season, paste(missing, collapse = ", "), length(missing) + 1L))
    info <- season_game_info(season)
    if (!is.null(info)) for (w in missing) { x <- pull_week_games(season, w, "regular", info); if (!is.null(x) && nrow(x)) saveRDS(x, .cache_file(sprintf("games_%d_wk%02d", season, w))) }
  }
  for (w in weeks) { f <- .cache_file(sprintf("games_%d_wk%02d", season, w)); if (file.exists(f)) out[[sprintf("%d-%d", season, w)]] <- readRDS(f) }
  do.call(rbind, out)
}

# One CFBD call per year not yet cached. Years up to `season` are final once the season is under way (that class has
# signed and enrolled; that portal year's windows have closed), so they are cached; later years (next year's class,
# the portal year that opens in December) are pulled every run.
cached_years <- function(prefix, first, last, season, pull) {
  dir.create(PROFILE_CACHE, recursive = TRUE, showWarnings = FALSE)
  x <- lapply(first:last, function(y) {
    f <- .cache_file(prefix, y)
    if (y <= season && file.exists(f)) return(readRDS(f))
    message(sprintf("  %s %d: 1 CFBD call", prefix, y))
    r <- pull(y)
    if (!is.null(r) && NROW(r)) { r <- as.data.frame(r); attr(r, "pulled_at") <- Sys.time(); if (y <= season) saveRDS(r, f) } else if (file.exists(f)) r <- readRDS(f)
    if (!is.null(r)) attr(r, "year") <- y
    r
  })
  do.call(rbind, Filter(function(d) !is.null(d) && NROW(d), x))
}

pull_recruits <- function(first, last, season = last) {
  x <- cached_years("recruits_", first, last, season, function(y) .quiet(cfbfastR::cfbd_recruiting_player(year = y, recruit_type = "HighSchool")))
  if (is.null(x)) return(NULL)
  x$athlete_id <- as.character(x$athlete_id); x$id <- as.character(x$id); x
}

pull_portal <- function(first, last, season = last) {
  x <- cached_years("portal_", first, last, season, function(y) .quiet(cfbfastR::cfbd_recruiting_transfer_portal(year = y)))
  if (is.null(x)) return(NULL)
  x$key <- tolower(paste(x$first_name, x$last_name)); x
}

# One player's JSON body. games: that player's box-score rows; r: roster row (or NULL); rec: recruiting row (or NULL);
# portal: that player's portal rows (name-matched); team_id_of: CFBD school name -> team id.
player_profile <- function(id, games, r, rec, portal, team_id_of, season) {
  games <- games[order(games$season, games$post, games$week, games$date), , drop = FALSE]
  cols <- names(PROFILE_STATS)
  stat_mat <- as.matrix(games[, unname(PROFILE_STATS), drop = FALSE]); colnames(stat_mat) <- cols
  log <- lapply(seq_len(nrow(games)), function(i) c(list(games$season[i], games$week[i], games$post[i], games$date[i], games$team_id[i],
                                                         games$opp_id[i], games$opp[i], games$loc[i], games$pts[i], games$opp_pts[i]),
                                                    as.list(unname(stat_mat[i, ]))))
  key <- paste(games$season, games$team_id, sep = "|")
  seasons <- lapply(unique(key), function(k) {
    w <- key == k
    c(list(season = games$season[w][1], team_id = games$team_id[w][1], team = games$team[w][1], gp = sum(w)),
      as.list(colSums(stat_mat[w, , drop = FALSE])))
  })
  name <- if (!is.null(r)) paste(r$first_name, r$last_name) else games$athlete_name[nrow(games)]
  class_year <- if (!is.null(rec)) as.integer(rec$year) else if (!is.null(r) && !is.na(r$year)) as.integer(season - r$year + 1L) else NA_integer_
  transfers <- if (!is.null(portal) && nrow(portal)) lapply(seq_len(nrow(portal)), function(i) list(
    season = portal$season[i], from = portal$origin[i], from_id = team_id_of(portal$origin[i]),
    to = if (is.na(portal$destination[i])) NA else portal$destination[i], to_id = team_id_of(portal$destination[i]),
    date = substr(as.character(portal$transfer_date[i]), 1, 10))) else list()
  list(
    athlete_id = id, name = name,
    team = if (!is.null(r)) r$team else games$team[nrow(games)],
    team_id = if (!is.null(r)) team_id_of(r$team) else games$team_id[nrow(games)],
    jersey = if (!is.null(r)) r$jersey else NA, position = if (!is.null(r)) r$position else if (!is.null(rec)) rec$position else NA,
    class = if (!is.null(r)) r$year else NA, height = if (!is.null(r)) r$height else NA, weight = if (!is.null(r)) r$weight else NA,
    hometown = if (!is.null(r) && !is.na(r$home_city)) list(city = r$home_city, state = r$home_state, country = r$home_country)
               else if (!is.null(rec)) list(city = rec$city, state = rec$state_province, country = rec$country) else NULL,
    headshot = if (!is.null(r)) r$headshot_url else NA,
    recruiting = if (!is.null(rec)) list(year = rec$year, stars = rec$stars, rating = rec$rating, ranking = rec$ranking,
                                         school = rec$school, city = rec$city, state = rec$state_province, committed_to = rec$committed_to,
                                         committed_id = team_id_of(rec$committed_to)) else NULL,
    hs_class = class_year, hs_class_estimated = is.null(rec),
    # NFL rule: eligible once three seasons have passed since high school.
    draft_year = if (!is.na(class_year)) class_year + 3L else NA,
    transfers = transfers,
    seasons = seasons, game_cols = c("season", "week", "post", "date", "team_id", "opp_id", "opp", "loc", "pts", "opp_pts", cols), games = log)
}
