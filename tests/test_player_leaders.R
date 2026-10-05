# /players/ leaderboards (R/publish/player_leaders.R) on a small synthetic season. Run from the project root:
#   Rscript tests/test_player_leaders.R
source("config/paths.R")
source(file.path(PATHS$root, "R", "publish", "player_leaders.R"))

teams <- data.frame(team = c("Alpha", "Beta"), team_id = c("1", "2"), stringsAsFactors = FALSE)
games <- data.frame(week = c(1, 2, 3, 4, 5), status = c("final", "final", "final", "final", "scheduled"),
                    home_id = c("1", "1", "2", "1", "2"), away_id = c("2", "9", "8", "7", "1"),
                    kickoff = c("2026-09-05T19:00:00Z", "2026-09-12T19:00:00Z", "2026-09-19T19:00:00Z", "2026-09-26T19:00:00Z", "2026-10-03T19:00:00Z"),
                    stringsAsFactors = FALSE)
blank <- setNames(as.list(rep(0, length(unique(unlist(lapply(LEADER_CATS, `[[`, "stats")))))), unique(unlist(lapply(LEADER_CATS, `[[`, "stats"))))
row <- function(id, team, name, pos, ...) { x <- modifyList(blank, list(...)); data.frame(c(list(athlete_id = id, team = team, player = name, position = pos), x), stringsAsFactors = FALSE) }
stats <- rbind(
  row("10", "Alpha", "Qb One", "QB", passing_att = 42, passing_completions = 40, passing_yds = 500, passing_td = 4, passing_int = 1),   # Alpha: 3 games -> needs 42
  row("11", "Alpha", "Qb Two", "QB", passing_att = 41, passing_completions = 30, passing_yds = 300),
  row("20", "Beta", "Rb One", "RB", rushing_car = 10, rushing_yds = 40),                                                                # Beta: 2 games -> qualifies at 10
  row("21", "Beta", "Rb Two", "RB", rushing_car = 3, rushing_yds = 90),                                                                 # under the 2-per-game floor
  row("30", "Gamma", "Fcs Guy", "WR", receiving_rec = 50, receiving_yds = 900),                                                         # not FBS
  row("40", "Alpha", "Lb One", "LB", defensive_tot = 12),
  row("41", "Alpha", "Edge One", "DE", defensive_sacks = 2))                                                                            # 2 sacks in 3 games: over 0.5 per game
ppa <- list(ppa = data.frame(id = c("10", "20"), team = c("Alpha", "Beta"), avg_pass = c(0.31, NA), total_pass = c(18.6, NA), avg_rush = c(NA, 0.05), total_rush = c(NA, 0.5)),
            success = data.frame(id = "20", team = "Beta", pass_plays = 0L, pass_successes = 0L, rush_plays = 10L, rush_successes = 4L))
attr(ppa, "end_week") <- 4L; attr(ppa, "pulled_at") <- as.POSIXct("2026-09-29 12:00:00", tz = "UTC")

b <- build_leaderboards(stats, teams, games, week = 4L, ppa = ppa)
col <- function(board, k) vapply(board$rows, function(r) { v <- r[[match(k, board$columns)]]; if (is.null(v) || is.na(v)) NA_real_ else as.numeric(v) }, 0)
ids <- function(board) vapply(board$rows, function(r) r[[1]], "")
stopifnot(identical(ids(b$passing), c("10", "11")),                       # sorted by attempts
          identical(col(b$passing, "q"), c(1, 0)),                         # 14 per team game x 3 games
          abs(col(b$passing, "rating")[1] - round((8.4 * 500 + 330 * 4 + 100 * 40 - 200) / 42, 1)) < 1e-9,
          identical(col(b$passing, "ppa_avg"), c(0.31, NA)),
          identical(ids(b$rushing), "20"), identical(col(b$rushing, "q"), 1), identical(col(b$rushing, "sr_successes"), 4),
          length(b$receiving$rows) == 0L,                                  # FCS players never listed
          identical(sort(ids(b$defense)), c("40", "41")), all(is.na(col(b$defense, "q"))),
          isTRUE(b$passing$ppa$available), b$team_games[["1"]] == 3L, b$team_games[["2"]] == 2L)

# A season-to-date PPA pull made after week-5 kickoffs is not published; success (cut at the week) still is.
attr(ppa, "pulled_at") <- as.POSIXct("2026-10-04 12:00:00", tz = "UTC")
late <- build_leaderboards(stats, teams, games, week = 4L, ppa = ppa)
stopifnot(!late$passing$ppa$available, grepl("week 5", late$passing$ppa$reason), all(is.na(col(late$passing, "ppa_avg"))),
          identical(col(late$rushing, "sr_successes"), 4))
# A pull for another week publishes neither.
attr(ppa, "end_week") <- 3L
other <- build_leaderboards(stats, teams, games, week = 4L, ppa = ppa)
stopifnot(!other$rushing$ppa$available, all(is.na(col(other$rushing, "sr_plays"))))
cat("player leaders tests: OK\n")
