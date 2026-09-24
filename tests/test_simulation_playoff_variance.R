suppressPackageStartupMessages({
  library(dplyr)
  library(cfbseedR)
})
# Adapted from the old folder: only the source() path changed. Run from the project root.
source("config/paths.R")
source(PATHS$dynamic_cfp)

teams <- paste0("Team ", sprintf("%02d", 1:14))
base <- tibble::tibble(
  sim = rep(1:2, each = length(teams) + 1L),
  team = rep(c(teams, "FCS Upset"), times = 2L),
  conference = "Independent",
  conf_champ = FALSE,
  win_pct = c(
    c(seq(0.99, 0.89, length.out = 11), 0.88, 0.98, 0.10), 1.00,
    c(seq(0.99, 0.88, length.out = 12), 0.20, 0.19), 1.00
  ),
  sov = 0,
  sos = 0,
  pd = 0
)

ranking <- base %>%
  filter(team %in% teams) %>%
  mutate(cfp_rank = rank(-win_pct, ties.method = "first"), .by = sim)

seeded <- cfb_dynamic_playoff_seeds(
  base,
  ranking = ranking,
  eligible_teams = teams,
  playoff_seeds = 12L,
  autobid = "2026"
)

stopifnot(
  !"FCS Upset" %in% seeded$team,
  !is.na(seeded$seed[seeded$sim == 1 & seeded$team == "Team 13"]),
  is.na(seeded$seed[seeded$sim == 2 & seeded$team == "Team 13"]),
  all(table(seeded$sim[!is.na(seeded$seed)]) == 12L)
)

mock_sim <- list(
  standings = seeded,
  overall = tibble::tibble(
    team = teams,
    wins = c(rep(10, 13), 8),
    playoff = c(rep(0.5, 13), 0.8)
  )
)
assert_dynamic_playoff_output(mock_sim, eligible_teams = teams)

bad_sim <- mock_sim
bad_sim$overall$playoff[14] <- 1
stopifnot(inherits(
  try(assert_dynamic_playoff_output(bad_sim, eligible_teams = teams),
      silent = TRUE),
  "try-error"
))

cat("PASS: CFP seeds vary by simulated resume, exclude FCS, and reject low-win locks.\n")
