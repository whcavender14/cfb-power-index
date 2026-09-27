# =============================================================================
# R/publish/player_usage.R — "Players by usage" for the team pages (public/data/v2/usage/<slug>.json).
#
# Display only: nothing here feeds the model. Not an official depth chart; CFBD publishes none.
#   Offense: CFBD player usage (cfbfastR::cfbd_player_usage, one call for the season): the share of the team's
#            plays on which the player was the passer, rusher or target. QB, RB (incl. FB), WR, TE.
#   Defense: CFBD season player stats (the same pull as the statistical leaders, cut at the ratings week),
#            ordered by total tackles within DL, LB and DB.
#   Roster:  CFBD team roster (cfbfastR::cfbd_team_roster, one call): jersey, height, finer position (EDGE vs DL) and
#            the headshot URL CFBD supplies, joined by athlete_id, for the team page's depth-chart graphic.
# Offensive linemen and special teams are not ranked: the data has no snap counts (only the roster count is given).
# =============================================================================
USAGE_GROUPS <- list(
  offense = list(QB = "QB", RB = c("RB", "FB"), WR = "WR", TE = "TE"),
  defense = list(DL = c("DL", "DE", "DT", "NT", "EDGE"), LB = c("LB", "ILB", "OLB", "MLB"), DB = c("DB", "CB", "S", "SAF", "FS", "SS"))
)
USAGE_MAX <- c(QB = 3, RB = 5, WR = 6, TE = 3, DL = 6, LB = 5, DB = 7)

pull_player_usage <- function(season) {
  x <- tryCatch(suppressWarnings(suppressMessages(cfbfastR::cfbd_player_usage(year = season))),
                error = function(e) { message("Player usage pull failed: ", conditionMessage(e)); NULL })
  if (is.null(x) || !NROW(x)) return(NULL)
  x <- as.data.frame(x); attr(x, "pulled_at") <- Sys.time(); x
}

pull_rosters <- function(season) {
  x <- tryCatch(suppressWarnings(suppressMessages(cfbfastR::cfbd_team_roster(year = season))),
                error = function(e) { message("Roster pull failed: ", conditionMessage(e)); NULL })
  if (is.null(x) || !NROW(x)) return(NULL)
  x <- as.data.frame(x); x$athlete_id <- as.character(x$athlete_id); x
}

# usage: CFBD usage rows; stats: season player stats rows; roster: CFBD roster rows (each may be NULL); school: CFBD name.
team_player_usage <- function(school, usage, stats, roster = NULL) {
  num <- function(v) { v <- suppressWarnings(as.numeric(v)); ifelse(is.na(v), 0, v) }
  group_rows <- function(df, groups, order_col, keep) {
    out <- lapply(names(groups), function(g) {
      d <- df[toupper(df$position) %in% groups[[g]], , drop = FALSE]
      d <- d[order(-d[[order_col]], d$name), , drop = FALSE]
      d <- d[d[[order_col]] > 0, , drop = FALSE]
      head(d[, keep, drop = FALSE], USAGE_MAX[[g]])
    })
    setNames(out, names(groups))
  }
  off <- NULL
  if (!is.null(usage)) {
    u <- usage[usage$team == school, , drop = FALSE]
    if (nrow(u)) {
      u$athlete_id <- as.character(u$athlete_id)
      for (k in c("usg_overall", "usg_pass", "usg_rush")) u[[k]] <- round(num(u[[k]]), 3)
      off <- group_rows(u, USAGE_GROUPS$offense, "usg_overall", c("athlete_id", "name", "position", "usg_overall", "usg_pass", "usg_rush"))
    }
  }
  def <- NULL
  if (!is.null(stats)) {
    s <- stats[stats$team == school, , drop = FALSE]
    if (nrow(s)) {
      d <- data.frame(athlete_id = as.character(s$athlete_id), name = s$player, position = s$position,
                      tackles = num(s$defensive_tot), tfl = num(s$defensive_tfl), sacks = num(s$defensive_sacks),
                      int = num(s$interceptions_int), pd = num(s$defensive_pd), stringsAsFactors = FALSE)
      def <- group_rows(d, USAGE_GROUPS$defense, "tackles", names(d))
    }
  }
  if (is.null(off) && is.null(def)) return(NULL)
  r <- if (!is.null(roster)) roster[roster$team == school, , drop = FALSE] else NULL
  add_roster <- function(groups) if (is.null(groups)) NULL else lapply(groups, function(d) {
    if (!nrow(d)) return(d)
    k <- if (is.null(r)) rep(NA_integer_, nrow(d)) else match(d$athlete_id, r$athlete_id)
    d$jersey <- if (is.null(r)) NA_integer_ else suppressWarnings(as.integer(r$jersey[k]))
    d$height <- if (is.null(r)) NA_integer_ else suppressWarnings(as.integer(r$height[k]))
    d$roster_pos <- if (is.null(r)) NA_character_ else r$position[k]
    d$headshot <- if (is.null(r) || !"headshot_url" %in% names(r)) NA_character_ else r$headshot_url[k]
    d
  })
  list(offense = add_roster(off), defense = add_roster(def),
       ol_on_roster = if (is.null(r)) NA_integer_ else sum(r$position %in% "OL"))
}

# Key players for the matchup page, by season production (CFBD season player stats through the ratings week): the
# depth-chart QB1 (else the passing-yards leader), the leading rusher, the top two receivers, the top two tacklers and
# the sack leader. Raw season totals; the page formats them. qb_name: TWO·DEEP QB1, when known.
key_players <- function(school, stats, roster = NULL, qb_name = NA_character_) {
  if (is.null(stats)) return(NULL)
  s <- stats[stats$team == school, , drop = FALSE]
  if (!nrow(s)) return(NULL)
  num <- function(v) { v <- suppressWarnings(as.numeric(v)); ifelse(is.na(v), 0, v) }
  s$athlete_id <- as.character(s$athlete_id)
  r <- if (!is.null(roster)) roster[roster$team == school, , drop = FALSE] else NULL
  pick <- function(i, role) {
    if (!length(i) || is.na(i)) return(NULL)
    x <- s[i, ]; k <- if (!is.null(r)) match(x$athlete_id, r$athlete_id) else NA
    list(athlete_id = x$athlete_id, name = x$player, position = x$position, role = role,
         jersey = if (!is.na(k)) suppressWarnings(as.integer(r$jersey[k])) else NA_integer_,
         headshot = if (!is.na(k) && "headshot_url" %in% names(r)) r$headshot_url[k] else NA_character_,
         pass_cmp = num(x$passing_completions), pass_att = num(x$passing_att), pass_yds = num(x$passing_yds), pass_td = num(x$passing_td), pass_int = num(x$passing_int),
         rush_car = num(x$rushing_car), rush_yds = num(x$rushing_yds), rush_td = num(x$rushing_td),
         rec = num(x$receiving_rec), rec_yds = num(x$receiving_yds), rec_td = num(x$receiving_td),
         tackles = num(x$defensive_tot), tfl = num(x$defensive_tfl), sacks = num(x$defensive_sacks), int = num(x$interceptions_int))
  }
  top <- function(v, n = 1L, min = 0) { o <- order(-num(v)); o <- o[num(v)[o] > min]; head(o, n) }
  qb <- if (!is.na(qb_name)) which(tolower(s$player) == tolower(qb_name))[1] else NA
  if (is.na(qb) || num(s$passing_att[qb]) == 0) qb <- top(s$passing_yds)[1]
  out <- list(pick(qb, "passing"))
  used <- if (length(qb) && !is.na(qb)) s$athlete_id[qb] else character()
  add <- function(idx, role) for (i in idx) if (!s$athlete_id[i] %in% used) { out[[length(out) + 1L]] <<- pick(i, role); used <<- c(used, s$athlete_id[i]) }
  add(top(s$rushing_yds), "rushing")
  add(head(setdiff(top(s$receiving_yds, 3L), match(used, s$athlete_id)), 2L), "receiving")
  add(top(s$defensive_tot, 2L), "defense")
  add(setdiff(top(s$defensive_sacks, 1L), match(used, s$athlete_id)), "defense")
  Filter(Negate(is.null), out)
}
