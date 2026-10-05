# =============================================================================
# R/publish/transfers.R: the transfer portal for /recruiting/transfers/, the team-page Recruiting card and the player
# modal's career path (public/data/v2/recruiting/portal_<year>.json; docs/website/PLAYER_DATA.md). Display only:
# nothing here feeds the model. The frozen model input data/frozen/cfb_data_v2/portal_2014_2026.rds is never read.
#
# Source: CollegeFootballData /player/portal (one call per year; years up to the current season cached in
# data/reference/player_cache, the year whose window is open pulled every run). CFBD's portal rows carry no athlete id.
#
# Matching (Stage 3; replaces the box-score-only rule): a portal row of year Y is matched to a CFBD athlete id by
# normalized name (lower case, accents and punctuation removed, Jr./Sr./II-V dropped) at
#   1. the destination team's roster in Y (CFBD /roster, cached per year), then
#   2. the origin team's roster in Y-1 and the origin team's box scores in Y-1.
# A name that fits two players on one roster is "ambiguous"; destination and origin answers that disagree are a
# "conflict"; no fit is "unmatched". Only a single, consistent id counts as a match. Every row is published either way.
#
# CFPi+ Star Churn (derived, methodology v2; replaces the rating-sum Net Transfer Value of v1; layout after The Slate Index's
# portal table). For each FBS team and portal year: In and Out (transfers; Withdrawn entries count for neither side,
# departures without a destination count as Out), Churn = In - Out, Star2 In / Star2 Out = the average of stars squared
# (5 = 25, 4 = 16, 3 = 9, 2 = 4) over the incoming / outgoing transfers that have a star rating (unrated transfers are
# left out of the averages and counted separately), and Star Churn = Star2 In - Star2 Out, the ranking metric (ties: Churn,
# then team id). A team with no star-rated transfer on one side has no Star Churn and is ranked last. Stars are the
# 247Sports Composite's, via CollegeFootballData; not CFBD's or 247Sports' ranking.
# =============================================================================
PORTAL_FIRST <- 2021L

norm_name <- function(x) {
  x <- tolower(stringi::stri_trans_general(x, "Latin-ASCII"))
  x <- gsub("[ ,]+(jr|sr|ii|iii|iv|v)\\.?$", "", x)
  gsub("[^a-z]", "", x)
}

# Compact CFBD rosters for the given seasons (cached; one call per season not cached). The current season's roster
# comes from the site export's pull (output/state/rosters_<season>.rds) when present.
roster_years <- function(years, season) {
  cur <- file.path(PATHS$state, sprintf("rosters_%d.rds", season))
  keep <- c("athlete_id", "first_name", "last_name", "team", "position", "year")
  out <- lapply(years, function(y) {
    if (y == season && file.exists(cur)) { r <- as.data.frame(readRDS(cur)) }
    else r <- cached_years("roster_", y, y, season, function(yy) { x <- .quiet(cfbfastR::cfbd_team_roster(year = yy)); if (is.null(x)) NULL else { x <- as.data.frame(x); x[, intersect(keep, names(x)), drop = FALSE] } })
    if (is.null(r) || !nrow(r)) return(NULL)
    r <- r[, intersect(keep, names(r)), drop = FALSE]; r$athlete_id <- as.character(r$athlete_id); r$season <- y; r
  })
  do.call(rbind, Filter(Negate(is.null), out))
}

# portal: CFBD portal rows (season, first_name, last_name, origin, destination, ...); rosters: roster_years();
# games: box-score rows (season, team, athlete_id, athlete_name). Adds athlete_id and match.
match_portal <- function(portal, rosters, games) {
  p <- as.data.frame(portal)
  p$season <- as.integer(p$season)
  key <- norm_name(paste(p$first_name, p$last_name))
  rk <- paste(rosters$season, rosters$team, norm_name(paste(rosters$first_name, rosters$last_name)))
  ids_at <- split(rosters$athlete_id, rk)
  gk <- paste(games$season, games$team, norm_name(games$athlete_name))
  gids_at <- split(as.character(games$athlete_id), gk)
  one <- function(lookup, k) vapply(k, function(z) { v <- unique(lookup[[z]]); if (is.null(v)) "" else if (length(v) == 1L) v else "*" }, "", USE.NAMES = FALSE)
  dest <- ifelse(is.na(p$destination), "", one(ids_at, paste(p$season, p$destination, key)))
  ro <- one(ids_at, paste(p$season - 1L, p$origin, key)); go <- one(gids_at, paste(p$season - 1L, p$origin, key))
  orig <- ifelse(ro == "*" | go == "*" | (nzchar(ro) & nzchar(go) & ro != go), "*", ifelse(nzchar(ro), ro, go))
  p$match <- ifelse(dest == "*" | orig == "*", "ambiguous",
             ifelse(nzchar(dest) & nzchar(orig) & dest != orig, "conflict",
             ifelse(nzchar(dest), "destination", ifelse(nzchar(orig), "origin", "unmatched"))))
  p$athlete_id <- ifelse(p$match == "destination", dest, ifelse(p$match == "origin", orig, NA_character_))
  p
}

# Per-year documents: every portal row with an FBS program on either side, the derived team table and the match counts.
build_transfers <- function(p, teams, has_profile, season) {
  tid <- function(name) { i <- match(name, teams$team); ifelse(is.na(i), NA_character_, as.character(teams$team_id[i])) }
  r <- .r_num
  lapply(setNames(sort(unique(p$season)), sort(unique(p$season))), function(y) {
    x <- p[p$season == y, , drop = FALSE]
    total <- nrow(x)
    x <- x[x$origin %in% teams$team | x$destination %in% teams$team, , drop = FALSE]   # FBS programs on at least one side
    x <- x[order(is.na(r(x$rating)), -r(x$rating), x$last_name, x$first_name), , drop = FALSE]
    o <- tid(x$origin); d <- tid(x$destination)
    prof <- ifelse(!is.na(x$athlete_id) & has_profile(x$athlete_id), x$athlete_id, NA_character_)
    rows <- lapply(seq_len(nrow(x)), function(i) list(paste(x$first_name[i], x$last_name[i]), x$position[i], o[i], if (is.na(o[i])) x$origin[i] else NA,
      d[i], if (is.na(d[i]) && !is.na(x$destination[i])) x$destination[i] else NA, substr(as.character(x$transfer_date[i]), 1, 10),
      r(x$stars[i]), r(x$rating[i]), x$eligibility[i], x$match[i], x$athlete_id[i], !is.na(prof[i])))
    live <- x$eligibility != "Withdrawn" | is.na(x$eligibility)
    st <- r(x$stars)
    avg2 <- function(m) { v <- st[m & !is.na(st)]; if (length(v)) round(mean(v^2), 2) else NA_real_ }
    tm <- lapply(as.character(teams$team_id), function(t) {
      i <- live & d %in% t; o_ <- live & o %in% t
      if (!any(i) && !any(o_)) return(NULL)
      si <- avg2(i); so <- avg2(o_)
      list(t, sum(i), sum(o_), sum(i) - sum(o_), sum(i & !is.na(st)), sum(o_ & !is.na(st)), si, so, if (is.na(si) || is.na(so)) NA_real_ else round(si - so, 2))
    })
    tm <- Filter(Negate(is.null), tm)
    sc <- vapply(tm, function(z) z[[9]], 0); ch <- vapply(tm, function(z) as.numeric(z[[4]]), 0)
    tm <- tm[order(is.na(sc), -ifelse(is.na(sc), 0, sc), -ch, vapply(tm, function(z) as.numeric(z[[1]]), 0))]
    tm <- lapply(seq_along(tm), function(k) c(tm[[k]][1], list(k), tm[[k]][-1]))
    counts <- as.list(table(factor(x$match, levels = c("destination", "origin", "ambiguous", "conflict", "unmatched"))))
    list(year = y, open = y > season, rows_total = total, fbs_rows = nrow(x), match = counts,
         columns = c("name", "position", "origin_id", "origin_other", "dest_id", "dest_other", "date", "stars", "rating", "eligibility", "match", "athlete_id", "profile"),
         rows = rows,
         team_columns = c("team_id", "rank", "in", "out", "churn", "in_stars", "out_stars", "star2_in", "star2_out", "star_churn"),
         teams = tm)
  })
}
