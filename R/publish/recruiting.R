# =============================================================================
# R/publish/recruiting.R: high-school recruiting for /recruiting/ and /recruiting/high-school/
# (public/data/v2/recruiting/*.json; docs/website/PLAYER_DATA.md, DATA_CONTRACT_V2.md). Display only: nothing here
# feeds the model.
#
# Sources (CollegeFootballData, whose recruiting data is the 247Sports Composite):
#   /recruiting/players  one row per high-school recruit and class: stars, rating, national ranking, commitment.
#   /recruiting/teams    CFBD's team class ranking and points. Empty for a class still being recruited (2027 in
#                        2026), so that class has no rank; the page lists its commit counts instead, unranked.
#   /talent              247Sports Team Talent Composite for the season.
# (CFBD's /recruiting/groups "All Positions" totalRating is not a plain sum of ratings and is not documented, so it is
# not used; commit counts and average ratings come from the recruit rows.)
# Calls: classes, rankings and talent up to the current season are cached in data/reference/player_cache and pulled
# once; the class still being recruited costs 2 calls a run (players, teams).
# Derived here, from those rows only: per-team counts of 5-, 4- and 3-star commits and their average rating, the mean
# CFBD rank over the last four ranked classes, and the blue-chip share (4- and 5-star recruits among the team's rated
# signees in those four classes). Each is a count or an average of CFBD rows; the page labels them.
# =============================================================================
RECRUIT_FIRST_CLASS <- 2018L

# Hand-fed classes CFBD does not carry yet: data/reference/manual_recruits/recruits_<year>.csv (columns ranking, name,
# position, stars, rating, school, state, height [in], weight [lb], committed_to [FBS team name or blank], source).
# A year CFBD already has is never overridden. Rows get ids "m<year>-<n>" and no athlete id, so they never match a player.
rbind_manual_recruits <- function(recruits, dir = file.path(PATHS$reference, "manual_recruits")) {
  have <- if (is.null(recruits)) integer() else unique(as.integer(recruits$year))
  for (f in list.files(dir, pattern = "^recruits_[0-9]{4}\\.csv$", full.names = TRUE)) {
    y <- as.integer(sub("^recruits_([0-9]{4})\\.csv$", "\\1", basename(f)))
    m <- utils::read.csv(f, stringsAsFactors = FALSE, na.strings = c("", "NA"), colClasses = "character")
    if (y %in% have || !nrow(m)) next
    n <- function(k) suppressWarnings(as.numeric(m[[k]]))
    add <- data.frame(id = sprintf("m%d-%d", y, seq_len(nrow(m))), athlete_id = NA_character_, recruit_type = "HighSchool", year = y,
      ranking = as.integer(n("ranking")), name = m$name, school = m$school, committed_to = m$committed_to, position = m$position,
      height = n("height"), weight = as.integer(n("weight")), stars = as.integer(n("stars")), rating = n("rating"),
      state_province = m$state, stringsAsFactors = FALSE)
    recruits <- if (is.null(recruits)) add else { for (k in setdiff(names(recruits), names(add))) add[[k]] <- NA; rbind(as.data.frame(recruits), add[, names(recruits)]) }
  }
  recruits
}

# Everything for classes RECRUIT_FIRST_CLASS..season+1. Needs player_profiles.R (cached_years, .quiet).
pull_recruiting <- function(season) {
  nxt <- season + 1L
  message(sprintf("Recruiting: CFBD calls this run = classes/rankings not yet cached + 2 for the %d class (players, teams)", nxt))
  recruits <- cached_years("recruits_", RECRUIT_FIRST_CLASS, nxt, season, function(y) .quiet(cfbfastR::cfbd_recruiting_player(year = y, recruit_type = "HighSchool")))
  ranks <- cached_years("recruit_teams_", RECRUIT_FIRST_CLASS, nxt, season, function(y) {
    x <- .quiet(cfbfastR::cfbd_recruiting_team(year = y))
    # An empty answer (no rankings yet) is a valid result for the open class: keep a zero-row frame.
    if (is.null(x) || !NROW(x)) data.frame(year = integer(), rank = integer(), team = character(), points = numeric()) else x
  })
  recruits <- rbind_manual_recruits(recruits)
  talent <- cached_years("talent_", season, season, season, function(y) .quiet(cfbfastR::cfbd_team_talent(year = y)))
  out <- list(recruits = as.data.frame(recruits), ranks = if (is.null(ranks)) NULL else as.data.frame(ranks),
              talent = if (is.null(talent)) NULL else as.data.frame(talent))
  attr(out, "season") <- season; attr(out, "open_class") <- nxt; attr(out, "pulled_at") <- Sys.time()
  out
}

.r_num <- function(v) suppressWarnings(as.numeric(v))

# Per team and class, from recruit rows: commits, 5/4/3-star counts, average rating of rated commits.
class_counts <- function(rec) {
  r <- rec[!is.na(rec$committed_to) & nzchar(rec$committed_to), , drop = FALSE]
  if (!nrow(r)) return(data.frame(year = integer(), team = character(), commits = integer(), five = integer(), four = integer(), three = integer(), avg_rating = numeric()))
  s <- .r_num(r$stars); rt <- .r_num(r$rating)
  k <- split(seq_len(nrow(r)), paste(r$year, r$committed_to, sep = "\r"))
  do.call(rbind, lapply(k, function(i) data.frame(year = as.integer(r$year[i[1]]), team = r$committed_to[i[1]], commits = length(i),
    five = sum(s[i] %in% 5), four = sum(s[i] %in% 4), three = sum(s[i] %in% 3),
    avg_rating = if (any(!is.na(rt[i]))) round(mean(rt[i], na.rm = TRUE), 4) else NA_real_, stringsAsFactors = FALSE)))
}

# Builds every recruiting document. x: pull_recruiting() result; teams: teams.json rows; index: index.json rows (CFPi+ rank);
# has_profile(ids): logical, TRUE where public/data/v2/player/<id>.json exists.
build_recruiting <- function(x, teams, index_rows, has_profile) {
  season <- attr(x, "season"); open <- attr(x, "open_class")
  tid <- function(name) { i <- match(name, teams$team); ifelse(is.na(i), NA_character_, as.character(teams$team_id[i])) }
  rec <- x$recruits
  rec$year <- as.integer(rec$year)
  counts <- class_counts(rec)
  ranks <- x$ranks; if (!is.null(ranks)) { ranks$year <- as.integer(ranks$year); ranks$rank <- as.integer(ranks$rank) }
  years <- sort(unique(rec$year))
  ranked_years <- if (is.null(ranks)) integer() else sort(unique(ranks$year))

  # hs_<year>: every high-school recruit in the class, in CFBD's national ranking order (unranked last).
  hs <- lapply(setNames(years, years), function(y) {
    r <- rec[rec$year == y, , drop = FALSE]
    r <- r[order(is.na(.r_num(r$ranking)), .r_num(r$ranking), -.r_num(r$rating), r$name), , drop = FALSE]
    aid <- as.character(r$athlete_id); prof <- ifelse(!is.na(aid) & has_profile(aid), aid, NA_character_)
    ct <- tid(r$committed_to)
    rows <- lapply(seq_len(nrow(r)), function(i) list(as.character(r$id[i]), prof[i], .r_num(r$ranking[i]), r$name[i], r$position[i],
      .r_num(r$stars[i]), .r_num(r$rating[i]), r$school[i], r$state_province[i], .r_num(r$height[i]), .r_num(r$weight[i]),
      ct[i], if (is.na(ct[i]) && !is.na(r$committed_to[i]) && nzchar(r$committed_to[i])) r$committed_to[i] else NA))
    list(year = y, open = y > season, columns = c("id", "profile_id", "ranking", "name", "position", "stars", "rating", "school", "state",
                                                    "height", "weight", "team_id", "committed_other"), rows = rows)
  })

  # teams_<year>: FBS teams' classes. Ranked classes carry CFBD's rank and points, in rank order. A class without
  # CFBD rankings (the open class) has no rank and is listed by 4- and 5-star commits, then average rating, then commits.
  team_docs <- lapply(setNames(years, years), function(y) {
    cc <- counts[counts$year == y, , drop = FALSE]
    rk <- if (y %in% ranked_years) ranks[ranks$year == y, , drop = FALSE] else NULL
    rows <- lapply(seq_len(nrow(teams)), function(k) {
      nm <- teams$team[k]; c1 <- cc[cc$team == nm, , drop = FALSE]; r1 <- if (!is.null(rk)) rk[rk$team == nm, , drop = FALSE] else NULL
      if (!nrow(c1) && (is.null(r1) || !nrow(r1))) return(NULL)
      list(as.character(teams$team_id[k]), if (!is.null(r1) && nrow(r1)) r1$rank[1] else NA, if (!is.null(r1) && nrow(r1)) .r_num(r1$points[1]) else NA,
           if (nrow(c1)) c1$commits else 0L, if (nrow(c1)) c1$five else 0L, if (nrow(c1)) c1$four else 0L, if (nrow(c1)) c1$three else 0L,
           if (nrow(c1)) c1$avg_rating else NA)
    })
    rows <- Filter(Negate(is.null), rows)
    v <- function(j) vapply(rows, function(r) if (is.na(r[[j]])) NA_real_ else as.numeric(r[[j]]), 0)
    rows <- rows[order(is.na(v(2)), v(2), -(v(5) + v(6)), -ifelse(is.na(v(8)), 0, v(8)), -v(4))]
    list(year = y, ranked = y %in% ranked_years && any(!vapply(rows, function(r) is.na(r[[2]]), TRUE)),
         columns = c("team_id", "rank", "points", "commits", "five", "four", "three", "avg_rating"), rows = rows)
  })

  # Team card: latest ranked class, mean rank over the last four ranked classes, blue-chip share of those four
  # classes' rated signees, the open class so far, and the 247Sports talent composite.
  last4 <- tail(ranked_years[ranked_years <= season], 4)
  tal <- x$talent
  tal_rank <- if (!is.null(tal)) rank(-.r_num(tal$talent), ties.method = "min") else NULL
  cards <- lapply(seq_len(nrow(teams)), function(k) {
    nm <- teams$team[k]
    r4 <- ranks[ranks$year %in% last4 & ranks$team == nm, , drop = FALSE]
    signees <- rec[rec$year %in% last4 & rec$committed_to %in% nm & !is.na(.r_num(rec$stars)), , drop = FALSE]
    oc <- counts[counts$year == open & counts$team == nm, , drop = FALSE]
    ti <- if (!is.null(tal)) match(nm, tal$school) else NA
    list(team_id = as.character(teams$team_id[k]),
         classes = lapply(last4, function(y) { j <- which(r4$year == y); list(year = y, rank = if (length(j)) r4$rank[j[1]] else NA) }),
         avg_rank_4yr = if (nrow(r4) == length(last4) && length(last4) == 4L) round(mean(r4$rank), 1) else NA,
         blue_chip = list(share = if (nrow(signees)) round(mean(.r_num(signees$stars) >= 4), 4) else NA,
                          blue = sum(.r_num(signees$stars) >= 4), rated = nrow(signees)),
         open_class = list(year = open, commits = if (nrow(oc)) oc$commits else 0L, five = if (nrow(oc)) oc$five else 0L,
                           four = if (nrow(oc)) oc$four else 0L, avg_rating = if (nrow(oc)) oc$avg_rating else NA),
         talent = if (!is.na(ti)) list(value = round(.r_num(tal$talent[ti]), 2), rank = as.integer(tal_rank[ti])) else NULL)
  })

  # Dashboard: the open class's top 20 teams (in the teams-file order, unranked), its top 10 players, the latest
  # ranked class's top 20, and talent next to the CFPi+ rank.
  od <- team_docs[[as.character(open)]]; ld <- if (length(last4)) team_docs[[as.character(max(last4))]] else NULL
  oh <- hs[[as.character(open)]]
  cfpi <- setNames(index_rows$rank, index_rows$team_id)
  tal_rows <- if (!is.null(tal)) {
    i <- which(tal$school %in% teams$team); i <- i[order(tal_rank[i])][seq_len(min(30L, length(i)))]
    lapply(i, function(j) { id <- tid(tal$school[j]); list(team_id = id, talent = round(.r_num(tal$talent[j]), 2), talent_rank = as.integer(tal_rank[j]), cfpi_rank = unname(cfpi[id])) })
  } else list()
  open_top <- if (!is.null(od)) head(od$rows, 20) else list()
  dashboard <- list(open_class = open, latest_ranked_class = if (length(last4)) max(last4) else NA,
                    open_top = lapply(open_top, function(r) list(team_id = r[[1]], commits = r[[4]], five = r[[5]], four = r[[6]], avg_rating = r[[8]])),
                    open_players = lapply(head(oh$rows, 10), function(r) list(id = r[[1]], ranking = r[[3]], name = r[[4]], position = r[[5]], stars = r[[6]], rating = r[[7]], school = r[[8]], state = r[[9]], team_id = r[[12]], committed_other = r[[13]])),
                    latest_top = if (!is.null(ld)) lapply(head(Filter(function(r) !is.na(r[[2]]), ld$rows), 20), function(r) list(team_id = r[[1]], rank = r[[2]], points = r[[3]], commits = r[[4]], five = r[[5]], four = r[[6]])) else list(),
                    talent_season = season, talent = tal_rows)
  list(hs = hs, teams = team_docs, cards = list(season = season, last4 = last4, open_class = open, teams = cards), dashboard = dashboard)
}

# Fallback when a run's recruiting export fails: keep the previous files, restamped with this export's meta (their
# pulled_at still says when the data was pulled), so the site stays consistent.
restamp_recruiting <- function(dir, meta) {
  for (f in list.files(dir, pattern = "\\.json$", full.names = TRUE)) {
    d <- jsonlite::fromJSON(f, simplifyVector = FALSE); d$meta <- meta
    jsonlite::write_json(d, f, auto_unbox = TRUE, na = "null", null = "null", digits = 6)
  }
}
