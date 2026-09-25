# Round 15 C3 QB-change detection (predeclaration v3 §5.4 item 2; Amendment 02 core rule, A4, A5) on synthetic team seasons.
# Rule: a game is an event when its primary passer differs from the team's primary in its preceding game with a primary;
# co-primaries (tied games) differ only if the games share no passer. Run from the repo root:
# Rscript tests/round15/test_qb_events.R
suppressPackageStartupMessages({ library(data.table); library(Matrix) })
source("R/round15/candidates/c2.R"); source("R/round15/candidates/c3.R")
n <- 0L
check <- function(ok, what) { if (!isTRUE(ok)) stop("FAIL: ", what, call. = FALSE); n <<- n + 1L; cat("ok -", what, "\n") }

# ps: one entry per game; NA = no primary passer that game; "A|B" = co-primaries A and B
synth <- function(ps, y = 2019L) {
  k <- length(ps); t0 <- as.POSIXct("2019-09-01", tz = "UTC") + (seq_len(k) - 1) * 7 * 86400
  g <- data.table(game_id = sprintf("g%02d", seq_len(k)), kickoff = t0, available_at = t0 + 86400, final = TRUE,
                  home_team = "Team", home_id = 1L, away_team = sprintf("Opp%d", seq_len(k)), away_id = 100L + seq_len(k))
  list(games = setNames(list(g), y), qb = data.table(season = y, game_id = g$game_id, offense = "Team", primary = ps, dropbacks = 30L)[!is.na(primary)])
}
events <- function(ps) sort(as.integer(sub("g", "", r15_qb_events(synth(ps), 2019L)$game_id)))
is_ev <- function(ps, want) identical(events(ps), as.integer(want))

check(is_ev(c("A", "A", "B", "B"), 3), "A A B B: one event at A -> B, not repeated while B stays primary")
check(is_ev(c("A", "B", "A"), c(2, 3)), "A B A: events at A -> B and B -> A")
check(is_ev(c("A", "B", "C"), c(2, 3)), "A B C: events at A -> B and B -> C")
check(is_ev(c("A", "B", "B", "A"), c(2, 4)), "A B B A: events at A -> B and B -> A")
check(is_ev(c(rep("A", 5), "B", "B", "A"), c(6, 8)), "A x5, B, B, A: events when B replaces A and when A replaces B")
check(is_ev(c(rep("A", 5), "B", "A", "B"), c(6, 7, 8)), "A x5, B, A, B: every change of primary is an event")
check(is_ev(c("A"), integer()) && is_ev(c("A", "A", "A"), integer()), "the first game is not an event; no event without a change")
check(is_ev(c(NA, "A", "A"), integer()), "the first game with a primary is not an event, even after a game without one")
check(is_ev(c("A", NA, "B"), 3) && is_ev(c("A", NA, "A"), integer()), "a game without a primary is skipped; comparison is with the latest earlier primary")
check(is_ev(c("A", "A|B", "B"), integer()) && is_ev(c("B", "A|B", "A"), integer()), "co-primaries sharing a passer with the neighbouring game are not a change")
check(is_ev(c("A", "B|C", "B"), 2) && is_ev(c("A", "B|C", "C"), 2), "co-primaries sharing no passer with the preceding game are one change")
check(is_ev(c("Zed", "Abe|Bo"), 2) && is_ev(c("Abe", "Bo|Zed"), 2) && is_ev(c("Bo", "Abe|Bo"), integer()) && is_ev(c("Zed", "Abe|Zed"), integer()), "tie handling does not depend on names")
e <- r15_qb_events(synth(c("A", "A", "B")), 2019L)
check(nrow(e) == 1 && e$team_id == 1L && e$available_at == as.POSIXct("2019-09-15", tz = "UTC") + 86400, "event carries the team and its game's availability time")
cat(sprintf("\n%d checks passed\n", n))
