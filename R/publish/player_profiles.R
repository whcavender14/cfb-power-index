# =============================================================================
# R/publish/player_profiles.R: player detail files for the site's player modal
# (public/data/v2/player/<athlete_id>.json; docs/website/PLAYER_DATA.md).
#
# Display only: nothing here feeds the model. Every value is a CFBD value or a sum of CFBD box-score rows.
#   Game log:   CFBD game player stats (cfbfastR::cfbd_game_player_stats), one all-teams call per week and season
#               type, joined to CFBD game info for week, date, opponent and score. Past seasons are cached in
#               output/state/player_games_<season>.rds and pulled once; the current season is pulled every run.
#   Seasons:    sums of the game log by season and team (so the season and game views always agree).
#   Bio:        CFBD roster (jersey, position, height, weight, hometown, class year) for the current season.
#   Recruiting: CFBD high-school recruiting rows (stars, national ranking, class, high school), joined by athlete_id.
#   Transfers:  CFBD transfer portal, matched by first + last name and origin school (the portal has no athlete id).
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

# All box-score rows for one season (regular weeks 1..max_week, plus postseason when include_post), with game context.
pull_season_games <- function(season, max_week = 16L, include_post = TRUE) {
  info <- .quiet(cfbfastR::cfbd_game_info(year = season, season_type = "both"))
  if (is.null(info) || !NROW(info)) return(NULL)
  info <- as.data.frame(info); info$game_id <- as.character(info$game_id)
  calls <- c(lapply(seq_len(max_week), function(w) list(week = w, type = "regular")),
             if (include_post) list(list(week = 1L, type = "postseason")))
  rows <- lapply(calls, function(k) {
    x <- .quiet(cfbfastR::cfbd_game_player_stats(year = season, week = k$week, season_type = k$type))
    if (is.null(x) || !NROW(x)) return(NULL)
    x <- as.data.frame(x)
    x <- x[, intersect(c("game_id", "team", "athlete_id", "athlete_name", unname(PROFILE_STATS)), names(x)), drop = FALSE]
    x$game_id <- as.character(x$game_id); x
  })
  rows <- do.call(rbind, Filter(Negate(is.null), rows))
  if (is.null(rows)) return(NULL)
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

# Past seasons come from the cache (pulled once); the current season is always pulled fresh.
career_games <- function(season, current_week) {
  out <- list()
  for (s in PROFILE_FIRST_SEASON:season) {
    f <- file.path(PATHS$state, sprintf("player_games_%d.rds", s))
    if (s < season && file.exists(f)) { out[[as.character(s)]] <- readRDS(f); next }
    message(sprintf("Player games %d: pulling", s))
    x <- if (s < season) pull_season_games(s) else pull_season_games(s, max_week = current_week, include_post = FALSE)
    if (is.null(x)) { if (file.exists(f)) x <- readRDS(f) else next }
    else saveRDS(x, f)
    out[[as.character(s)]] <- x
  }
  do.call(rbind, out)
}

pull_recruits <- function(first, last) {
  x <- lapply(first:last, function(y) .quiet(cfbfastR::cfbd_recruiting_player(year = y, recruit_type = "HighSchool")))
  x <- do.call(rbind, lapply(Filter(Negate(is.null), x), as.data.frame))
  if (is.null(x)) return(NULL)
  x$athlete_id <- as.character(x$athlete_id); x$id <- as.character(x$id); x
}

pull_portal <- function(first, last) {
  x <- lapply(first:last, function(y) .quiet(cfbfastR::cfbd_recruiting_transfer_portal(year = y)))
  x <- do.call(rbind, lapply(Filter(Negate(is.null), x), as.data.frame))
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
