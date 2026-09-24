suppressPackageStartupMessages({
  library(dplyr)
  library(cfbseedR)
})
# Run from the project root: Rscript tests/test_cfp_resume_ranking.R
source("config/paths.R")
source("config/production.R")
source(PATHS$dynamic_cfp)

# ---- Part 1: the resume ranking responds to schedule, not just W/L or power ----
# Opponent strengths are on the 2026 scale: average SEC ~ +15, average P4 ~ +8,
# Sun Belt/MWC ~ -6 to -9, FCS -25; the 60th-best FBS team ~ +0.7.
game <- function(opp, power, where, margin) tibble(opp, power, where, margin)
reps <- function(n, opp, power, where, margin) game(rep(opp, n), power, where, margin)
seasons <- list(
  "G6 Star 11-1" = bind_rows(game("FCS", -25, "home", 30), game("P4 Road", 5, "away", -7),
                             reps(5, "G6 Opp", -9, "home", 14), reps(5, "G6 Opp", -9, "away", 14)),
  "P4 Grinder 10-2" = bind_rows(game("FCS", -25, "home", 30),
                                reps(5, "SEC Opp", 15, "home", 7), game("SEC Opp", 15, "home", -7),
                                reps(4, "SEC Opp", 15, "away", 7), game("SEC Opp", 15, "away", -7)),
  "Elite G6 12-0" = bind_rows(game("FCS", -25, "home", 30), game("SEC Road", 15, "away", 10),
                              reps(5, "G6 Opp", -6, "home", 24), reps(5, "G6 Opp", -6, "away", 24)),
  "P4 Three-Loss 9-3" = bind_rows(game("FCS", -25, "home", 30),
                                  reps(5, "P4 Opp", 8, "home", 10), game("P4 Opp", 8, "home", -3),
                                  reps(3, "P4 Opp", 8, "away", 7), reps(2, "P4 Opp", 8, "away", -7)),
  "Record Team 11-1" = bind_rows(game("FCS", -25, "home", 30), reps(10, "P4 Opp", 8, "home", 7),
                                 game("P4 Opp", 8, "away", -3)),
  "Talent Team 8-4" = bind_rows(game("FCS", -25, "home", 30), reps(7, "P4 Opp", 8, "home", 21),
                                reps(4, "P4 Opp", 8, "away", -3))
)
champions <- c("G6 Star 11-1", "Elite G6 12-0")

# Every contender plays its own uniquely named opponents so the games table is a valid slate.
games <- bind_rows(lapply(names(seasons), function(tm) {
  s <- seasons[[tm]] %>% mutate(opp = paste(tm, opp, row_number()))
  tibble(sim = 1L, week = seq_len(nrow(s)), game_type = "REG",
         home_team = ifelse(s$where == "away", s$opp, tm),
         away_team = ifelse(s$where == "away", tm, s$opp),
         result = ifelse(s$where == "away", -s$margin, s$margin), neutral = 0L)
}))
team_power <- setNames(rep(0, length(seasons)), names(seasons))
team_power[c("Talent Team 8-4", "Record Team 11-1")] <- c(25, 5)
for (tm in names(seasons)) {
  s <- seasons[[tm]] %>% mutate(opp = paste(tm, opp, row_number()))
  team_power[s$opp] <- s$power
}
contenders <- names(seasons)
standings <- tibble(
  sim = 1L, team = contenders, conference = "Test",
  conf_champ = contenders %in% champions,
  win_pct = sapply(seasons, function(s) mean(s$margin > 0)),
  sov = 0, sos = 0, pd = sapply(seasons, function(s) sum(s$margin))
)
spec <- list(coef = PRODUCTION$cfp_rank_coef, benchmark_rating = 0.7, sigma = PRODUCTION$sim_resid_sd,
             hfa = PRODUCTION$sim_hfa, margin_cap = PRODUCTION$cfp_rank_margin_cap, team_power = team_power)
ranked <- cfb_dynamic_cfp_ranking(standings, games, contenders, spec)
rk <- setNames(ranked$cfp_rank, ranked$team)
print(ranked %>% select(team, win_pct, wab, adj_margin, conf_champ, resume_score, cfp_rank), width = Inf)

fallback <- cfbseedR::cfb_playoff_seeds(standings %>% mutate(conference = "FBS Independents"), rankings = NULL,
                                        playoff_seeds = length(contenders), autobid = "2026")
fb <- setNames(fallback$seed, fallback$team)
stopifnot(
  # The old fallback ranks by win pct first; the resume ranking lets schedule overcome one loss.
  fb[["G6 Star 11-1"]] < fb[["P4 Grinder 10-2"]],
  rk[["P4 Grinder 10-2"]] < rk[["G6 Star 11-1"]],
  # Winning still matters: an elite unbeaten G6 champion outranks a three-loss P4 team.
  rk[["Elite G6 12-0"]] < rk[["P4 Three-Loss 9-3"]],
  # A team's own power rating is not a ranking input: same schedule, better record wins.
  team_power[["Talent Team 8-4"]] > team_power[["Record Team 11-1"]],
  rk[["Record Team 11-1"]] < rk[["Talent Team 8-4"]]
)

# ---- Part 2: 2026 seeding rules applied to per-simulation rankings ----------
confs <- c(rep("SEC", 6), rep("Big Ten", 6), rep("ACC", 5), rep("Big 12", 5),
           rep("Sun Belt", 3), rep("Mountain West", 3), "FBS Independents", "FBS Independents")
fbs <- c(paste0("SEC ", 1:6), paste0("B1G ", 1:6), paste0("ACC ", 1:5), paste0("B12 ", 1:5),
         paste0("SBC ", 1:3), paste0("MWC ", 1:3), "Notre Dame", "UConn")
base <- tibble(team = c(fbs, "FCS Team"), conference = c(confs, NA_character_), win_pct = 0.5, sov = 0, sos = 0, pd = 0)
order_for <- function(...) { top <- c(...); c(top, setdiff(fbs, top)) }
# sim 1: two G6 teams rank inside the top 12; ND is 10th; ACC and Big 12 champions rank 20th and 15th.
o1 <- order_for("SEC 1", "SEC 2", "B1G 1", "B1G 2", "SBC 1", "SEC 3", "B1G 3", "SEC 4", "MWC 1", "Notre Dame",
                "SEC 5", "B1G 4", "B12 2", "B12 3", "B12 1", "ACC 2", "ACC 3", "ACC 4", "SEC 6", "ACC 1")
# sim 2: the best G6 team is 25th, ND is 14th, and ineligible UConn is 2nd.
o2 <- order_for("SEC 1", "UConn", "B1G 1", "ACC 1", "B12 1", "SEC 2", "SEC 3", "B1G 2", "B1G 3", "SEC 4",
                "ACC 2", "B12 2", "B1G 4", "Notre Dame", "SEC 5", "SEC 6", "B1G 5", "B1G 6", "ACC 3", "ACC 4",
                "ACC 5", "B12 3", "B12 4", "B12 5", "MWC 2")
champs <- list(`1` = c("SEC 1", "B1G 1", "ACC 1", "B12 1", "SBC 1", "MWC 1"),
               `2` = c("SEC 1", "B1G 1", "ACC 1", "B12 1", "SBC 2", "MWC 2"))
sims <- bind_rows(lapply(1:2, function(s) base %>% mutate(sim = s, conf_champ = team %in% champs[[s]])))
ranking <- bind_rows(tibble(sim = 1L, team = o1, cfp_rank = seq_along(o1)),
                     tibble(sim = 2L, team = o2, cfp_rank = seq_along(o2)))
eligible <- setdiff(fbs, "UConn")
seeded <- cfb_dynamic_playoff_seeds(sims, ranking, eligible, playoff_seeds = 12L, autobid = "2026") %>%
  left_join(ranking, by = c("sim", "team"))
field <- function(s) seeded$team[seeded$sim == s & !is.na(seeded$seed)]

stopifnot(
  all(table(seeded$sim[!is.na(seeded$seed)]) == 12L),
  !"FCS Team" %in% seeded$team,
  !"UConn" %in% field(2),
  # sim 1: P4 champions ranked 15th/20th, ND at 10th, and BOTH top-12 G6 teams get in (no G6 cap);
  # the 11th and 12th-ranked teams are displaced by automatic bids.
  setequal(field(1), o1[c(1:10, 15, 20)]),
  # sim 2: the highest-ranked G6 team (25th) gets the guaranteed bid; ND at 14th has no bid.
  "MWC 2" %in% field(2), !"Notre Dame" %in% field(2),
  # Seeds follow the ranking order within the field.
  identical(seeded %>% filter(sim == 1, !is.na(seed)) %>% arrange(seed) %>% pull(team), o1[c(1:10, 15, 20)])
)
assert_cfp_autobids_2026(seeded, eligible)

broken <- seeded %>% mutate(seed = ifelse(sim == 2 & team == "MWC 2", NA_integer_, seed))
stopifnot(inherits(try(assert_cfp_autobids_2026(broken, eligible), silent = TRUE), "try-error"))

cat("PASS: resume ranking weighs schedule over raw record, still rewards winning, ignores own power;",
    "2026 auto-bids, ND rule, eligibility and uncapped G6 at-large bids hold.\n")
