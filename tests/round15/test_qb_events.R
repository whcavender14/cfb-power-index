# Round 15 C3 QB-change detection (predeclaration v2 §5.4 item 2) on synthetic team seasons.
# Signed rule: a change is detected when the latest game's primary passer (>= 10 dropbacks) differs from the season-to-date
# primary passer; the allowance is added once per change. Run from the repo root: Rscript tests/round15/test_qb_events.R
suppressPackageStartupMessages({ library(data.table); library(Matrix) })
source("R/round15/candidates/c2.R"); source("R/round15/candidates/c3.R")
n <- 0L
check <- function(ok, what) { if (!isTRUE(ok)) stop("FAIL: ", what, call. = FALSE); n <<- n + 1L; cat("ok -", what, "\n") }

synth <- function(ps, db = rep(30L, length(ps)), y = 2019L) {
  k <- length(ps); t0 <- as.POSIXct("2019-09-01", tz = "UTC") + (seq_len(k) - 1) * 7 * 86400
  g <- data.table(game_id = sprintf("g%02d", seq_len(k)), kickoff = t0, available_at = t0 + 86400, final = TRUE,
                  home_team = "Team", home_id = 1L, away_team = sprintf("Opp%d", seq_len(k)), away_id = 100L + seq_len(k))
  list(games = setNames(list(g), y), pbp = data.table(season = y, game_id = g$game_id, offense = "Team", passer = ps, dropbacks = as.integer(db)))
}
events <- function(ps, db = rep(30L, length(ps))) sort(as.integer(sub("g", "", r15_qb_events(synth(ps, db), 2019L)$game_id)))
is_ev <- function(ps, want, db = rep(30L, length(ps))) identical(events(ps, db), as.integer(want))

check(is_ev(c("A", "A", "B", "B"), 3), "A A B B: one event at the change to B, not repeated while B stays primary")
check(is_ev(c("A", "B", "A"), 2, c(40, 20, 30)), "A B A (A leads season dropbacks): event at B; the return to A matches the season-to-date primary")
check(is_ev(c("A", "B", "A"), c(2, 3), c(20, 40, 30)), "A B A (B leads season dropbacks): events at B and at the return to A")
check(is_ev(c("A", "B", "C"), c(2, 3)), "A B C: events at B and at C")
check(is_ev(c("A", "B", "B", "A"), c(2, 4)), "A B B A (B leads by week 4): events at B and at the return to A")
check(is_ev(c("A", "B", "B", "A"), 2, c(60, 25, 25, 30)), "A B B A (A still leads): event at B only; the return to A matches the season-to-date primary")
check(is_ev(c(rep("A", 5), "B", "B", "A"), 6), "A x5, B, B, A: event at week 6 only (week 8 passer A is the season-to-date primary)")
check(is_ev(c(rep("A", 5), "B", "A", "B"), c(6, 8)), "A x5, B, A, B: events at weeks 6 and 8 (a second change to B is a new detection)")
check(is_ev(c("A", "B", "A"), 2) && is_ev(c("B", "A", "B"), 2), "a passer tied for the season-to-date lead is not a change, whatever the names")
check(is_ev(c("A", "B", "C"), c(2, 3)) && is_ev(c("C", "B", "A"), c(2, 3)), "a passer outside a tied lead is a change, whatever the names")
check(is_ev(c("A", "X", "B"), 3, c(30, 5, 30)), "a game without a >= 10-dropback passer is skipped")
check(is_ev(c("A"), integer()) && is_ev(c("A", "A", "A"), integer()), "no event without a change")
e <- r15_qb_events(synth(c("A", "A", "B")), 2019L)
check(nrow(e) == 1 && e$team_id == 1L && e$available_at == as.POSIXct("2019-09-15", tz = "UTC") + 86400, "event carries the team and its game's availability time")
cat(sprintf("\n%d checks passed\n", n))
