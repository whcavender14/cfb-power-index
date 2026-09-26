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
