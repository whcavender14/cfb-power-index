# =============================================================================
# R/publish/player_leaders.R: league-wide statistical leaderboards for /players/
# (public/data/v2/players/leaders/<category>.json; docs/website/PLAYER_DATA.md, DATA_CONTRACT_V2.md).
#
# Display only: nothing here feeds the model. Every published number is a CFBD value, or one fixed formula of CFBD values:
#   Box scores: CFBD season player stats through the ratings week (output/state/player_stats_<season>.rds, the same
#               pull as the team-page leaders).
#   PPA:        CFBD player Predicted Points Added (/ppa/players/season; R/publish/pull_player_ppa.R), average per play
#               and total, as CFBD reports them. Published only when the pull lines up with the ratings week (below).
#   Success:    CFBD player success (/stats/player/success, through the ratings week): plays and successful plays.
#   Usage:      CFBD player usage (share of the team's pass or rush plays), from the usage-file pull.
#   Class:      CFBD roster `year` (1-4).
#   Rating:     the NCAA passer efficiency formula, (8.4 Yds + 330 TD + 100 Cmp - 200 Int) / Att.
# Players are FBS players above a small activity floor (LEADER_CATS$floor), so team and conference filters have
# depth while each file stays near 25 KB gzipped. `q` marks players who meet the rate-stat qualifier (a minimum per team game, games from games.json).
# =============================================================================
LEADER_CATS <- list(
  passing = list(key = "passing_att", qual = 14, floor = function(s) s$passing_att > 0,
                 floor_text = "At least one pass attempt.", qual_text = "14 pass attempts per team game.",
                 stats = c("passing_completions", "passing_att", "passing_yds", "passing_td", "passing_int", "rushing_car", "rushing_yds", "rushing_td"),
                 ppa = "pass", success = "pass"),
  rushing = list(key = "rushing_car", qual = 5, floor = function(s, g) s$rushing_car >= 2 * g,
                 floor_text = "At least 2 carries per team game.", qual_text = "5 carries per team game.",
                 stats = c("rushing_car", "rushing_yds", "rushing_td", "rushing_long", "fumbles_lost"),
                 ppa = "rush", success = "rush", usage = "usg_rush"),
  receiving = list(key = "receiving_rec", qual = 2.5, floor = function(s, g) s$receiving_rec >= 1.25 * g,
                   floor_text = "At least 1.25 catches per team game.", qual_text = "2.5 catches per team game.",
                   stats = c("receiving_rec", "receiving_yds", "receiving_td", "receiving_long"),
                   ppa = "pass", usage = "usg_pass"),
  defense = list(key = "defensive_tot", qual = NA, floor = function(s, g) s$defensive_tot >= 3.25 * g | s$defensive_sacks + s$interceptions_int >= 0.5 * g,
                 floor_text = "At least 3.25 tackles, or 0.5 sacks plus interceptions, per team game.", qual_text = NA,
                 stats = c("defensive_tot", "defensive_solo", "defensive_tfl", "defensive_sacks", "defensive_qb_hur", "defensive_pd",
                           "interceptions_int", "interceptions_yds", "interceptions_td", "fumbles_rec")),
  kicking = list(key = "kicking_fga", qual = 0.75, floor = function(s) s$kicking_fga > 0 | s$kicking_xpa > 0,
                 floor_text = "At least one field goal or extra point attempt.", qual_text = "0.75 field goal attempts per team game.",
                 stats = c("kicking_fgm", "kicking_fga", "kicking_long", "kicking_xpm", "kicking_xpa", "kicking_pts")),
  punting = list(key = "punting_no", qual = 3.6, floor = function(s) s$punting_no > 0,
                 floor_text = "At least one punt.", qual_text = "3.6 punts per team game (the NCAA standard).",
                 stats = c("punting_no", "punting_yds", "punting_long", "punting_in_20", "punting_tb"))
)

.num0 <- function(v) { v <- suppressWarnings(as.numeric(v)); ifelse(is.na(v), 0, v) }

# Regular-season games each FBS team has played through the ratings week (final games in games.json, FCS opponents included).
team_games_played <- function(games, week) {
  g <- games[games$status == "final" & games$week <= week, , drop = FALSE]
  table(c(as.character(g$home_id), as.character(g$away_id)))
}

# Does a season-to-date pull (no week filter at CFBD) cover exactly weeks 1..week? Only if no game after `week`
# had kicked off when it was pulled. Returns NULL when it lines up, else the reason.
pull_misaligned <- function(pulled_at, games, week) {
  if (is.null(pulled_at) || is.na(pulled_at)) return("no pull time recorded")
  later <- games[games$week > week, , drop = FALSE]
  k <- as.POSIXct(later$kickoff, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  if (any(!is.na(k) & k < as.POSIXct(pulled_at, tz = "UTC"))) return(sprintf("pulled after week %d games had started", week + 1L))
  NULL
}

# stats: CFBD season player stats (cfbfastR wide format); teams: teams.json rows (team, team_id); games: games.json rows;
# ppa: list(ppa, success) from pull_player_ppa.R or NULL; usage: player usage rows or NULL; roster: CFBD roster or NULL.
build_leaderboards <- function(stats, teams, games, week, ppa = NULL, usage = NULL, roster = NULL, rs_lookup = NULL) {
  s <- as.data.frame(stats)
  s <- s[s$team %in% teams$team, , drop = FALSE]
  s$athlete_id <- as.character(s$athlete_id)
  s <- s[!is.na(s$athlete_id) & !grepl("^-", s$athlete_id), , drop = FALSE]
  if (anyDuplicated(s[, c("team", "athlete_id")])) stop("Player leaders: duplicate player rows for a team.")
  for (k in unique(unlist(lapply(LEADER_CATS, `[[`, "stats")))) s[[k]] <- .num0(s[[k]])
  s$team_id <- as.character(teams$team_id[match(s$team, teams$team)])
  tg <- team_games_played(games, week)
  s$team_games <- as.integer(ifelse(is.na(tg[s$team_id]), 0L, tg[s$team_id]))
  s$class <- NA_integer_
  if (!is.null(roster)) {
    r <- as.data.frame(roster); r$athlete_id <- as.character(r$athlete_id)
    y <- suppressWarnings(as.integer(r$year[match(paste(s$athlete_id, s$team), paste(r$athlete_id, r$team))]))
    s$class <- ifelse(!is.na(y) & y >= 1L & y <= 6L, y, NA_integer_)
  }
  s$rs <- if (is.null(rs_lookup)) FALSE else rs_flag(s$athlete_id, s$class, rs_lookup, as.integer(stats$year[1]))
  # Season-to-date pulls are used only when they line up with the ratings week.
  ppa_why <- if (is.null(ppa)) "not pulled" else if (!identical(as.integer(attr(ppa, "end_week")), as.integer(week))) "covers a different week" else pull_misaligned(attr(ppa, "pulled_at"), games, week)
  usage_why <- if (is.null(usage)) "not pulled" else pull_misaligned(attr(usage, "pulled_at"), games, week)
  pp <- if (is.null(ppa_why)) ppa$ppa else NULL
  sc <- if (!is.null(ppa) && identical(as.integer(attr(ppa, "end_week")), as.integer(week))) ppa$success else NULL   # cut at the week by CFBD
  us <- if (is.null(usage_why)) usage else NULL
  key <- paste(s$athlete_id, s$team)
  pick <- function(df, id_col, col) {
    if (is.null(df) || !col %in% names(df)) return(rep(NA_real_, nrow(s)))
    suppressWarnings(as.numeric(df[[col]][match(key, paste(as.character(df[[id_col]]), df$team))]))
  }
  out <- list()
  for (cat in names(LEADER_CATS)) {
    d <- LEADER_CATS[[cat]]
    keep <- if (length(formals(d$floor)) == 2L) d$floor(s, s$team_games) else d$floor(s)
    x <- s[keep, , drop = FALSE]
    xk <- paste(x$athlete_id, x$team)
    cols <- c("athlete_id", "player", "team_id", "position", "class", "q", "rs", d$stats)
    body <- x[, c("athlete_id", "player", "team_id", "position", "class"), drop = FALSE]
    body$q <- if (is.na(d$qual)) rep(NA, nrow(body)) else x[[d$key]] >= d$qual * x$team_games & x$team_games > 0
    body$rs <- as.integer(x$rs)   # 0/1 keeps the file small
    for (k in d$stats) body[[k]] <- x[[k]]
    if (cat == "passing") { body$rating <- round(ifelse(x$passing_att > 0, (8.4 * x$passing_yds + 330 * x$passing_td + 100 * x$passing_completions - 200 * x$passing_int) / x$passing_att, NA), 1); cols <- c(cols, "rating") }
    if (!is.null(d$ppa)) {
      sel <- match(xk, paste(pp$id, pp$team))
      body$ppa_avg <- if (is.null(pp)) rep(NA_real_, nrow(body)) else suppressWarnings(as.numeric(pp[[paste0("avg_", d$ppa)]][sel]))
      body$ppa_total <- if (is.null(pp)) rep(NA_real_, nrow(body)) else suppressWarnings(as.numeric(pp[[paste0("total_", d$ppa)]][sel]))
      cols <- c(cols, "ppa_avg", "ppa_total")
    }
    if (!is.null(d$success)) {
      sel <- match(xk, paste(sc$id, sc$team))
      body$sr_plays <- if (is.null(sc)) rep(NA_integer_, nrow(body)) else sc[[paste0(d$success, "_plays")]][sel]
      body$sr_successes <- if (is.null(sc)) rep(NA_integer_, nrow(body)) else sc[[paste0(d$success, "_successes")]][sel]
      cols <- c(cols, "sr_plays", "sr_successes")
    }
    if (!is.null(d$usage)) {
      sel <- match(xk, paste(as.character(us$athlete_id), us$team))
      body$usage <- if (is.null(us)) rep(NA_real_, nrow(body)) else round(suppressWarnings(as.numeric(us[[d$usage]][sel])), 3)
      cols <- c(cols, "usage")
    }
    body <- body[order(-x[[d$key]], x$player), cols, drop = FALSE]
    # Every box-score value must be the pulled value for that player.
    chk <- match(paste(body$athlete_id, body$team_id), paste(s$athlete_id, s$team_id))
    for (k in d$stats) stopifnot(identical(as.numeric(body[[k]]), as.numeric(s[[k]][chk])))
    out[[cat]] <- list(category = cat, through_week = as.integer(week), rank_stat = d$key, columns = cols, team_games = as.list(tg[names(tg) %in% as.character(teams$team_id)]),
                       qualifier = if (is.na(d$qual)) NULL else list(stat = d$key, per_team_game = d$qual, text = d$qual_text),
                       floor = d$floor_text,
                       ppa = if (is.null(d$ppa)) NULL else list(available = is.null(ppa_why), reason = ppa_why %||% NA,
                                                                 pulled_at = if (is.null(ppa)) NA else format(as.POSIXct(attr(ppa, "pulled_at"), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")),
                       success = if (is.null(d$success)) NULL else list(available = !is.null(sc), through_week = as.integer(week)),
                       usage = if (is.null(d$usage)) NULL else list(available = is.null(usage_why), reason = usage_why %||% NA),
                       rows = unname(lapply(seq_len(nrow(body)), function(i) unname(as.list(body[i, , drop = FALSE])))))
  }
  out
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# Empty boards that say why (stats missing, for another week, or the export failed): the page shows the reason instead
# of numbers that do not match "Ratings through Week N".
write_empty_boards <- function(out_dir, meta, why, source_text) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  for (cat in names(LEADER_CATS)) jsonlite::write_json(list(meta = meta, category = cat, through_week = NULL, unavailable = why, source = source_text, rows = list()),
                                                       file.path(out_dir, paste0(cat, ".json")), auto_unbox = TRUE, na = "null", null = "null")
}
