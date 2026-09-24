# =============================================================================
# scripts/diagnose_cfp_selection.R — who makes the simulated CFP, and why.
#
# Usage (from the project root, after scripts/02_simulate_season.R):
#   Rscript scripts/diagnose_cfp_selection.R [path/to/simulations_<season>_latest.rds]
#
# Prints expected CFP bids by conference and by group (P4 / G6 / independent),
# the distribution of G6 teams per field, and the ranking around the cut line
# for the simulations with the most G6 teams.
# =============================================================================
source("config/paths.R")
source("config/production.R")
suppressPackageStartupMessages({ library(dplyr); source(PATHS$dynamic_cfp) })

args <- commandArgs(TRUE)
path <- if (length(args)) args[1] else file.path(PATHS$state, sprintf("simulations_%s_latest.rds", Sys.getenv("CFB_SEASON", "2026")))
sim <- readRDS(path)
p4 <- c("ACC", "Big 12", "Big Ten", "SEC")
g6 <- c("American Athletic", "Conference USA", "Mid-American", "Mountain West", "Pac-12", "Sun Belt")
group_of <- function(conf) case_when(conf %in% p4 ~ "P4", conf %in% g6 ~ "G6", TRUE ~ "Independent")

st <- sim$standings %>% filter(!is.na(cfp_rank)) %>%
  left_join(sim$ratings %>% select(team, power_rating), by = "team") %>%
  mutate(group = group_of(conference))
seeded <- st %>% filter(!is.na(seed))
stopifnot(all(count(seeded, sim)$n == PRODUCTION$playoff_seeds), all(seeded$team %in% sim$ratings$team))
if (identical(PRODUCTION$playoff_autobid, "2026")) assert_cfp_autobids_2026(sim$standings, unique(st$team))

cat(sprintf("%d simulations, as of %s. Ranking: %s\n\n", n_distinct(sim$standings$sim),
            format(sim$as_of, "%Y-%m-%d"), sim$sim_params$ranking_mode))
cat("Expected CFP bids by conference\n")
print(sim$overall %>% filter(!is.na(conference)) %>% group_by(conference) %>%
        summarise(expected_bids = round(sum(playoff), 3)) %>% arrange(desc(expected_bids)), n = Inf)
cat("\nExpected CFP bids by group\n")
print(sim$overall %>% filter(!is.na(conference)) %>% group_by(group = group_of(conference)) %>%
        summarise(expected_bids = round(sum(playoff), 3)))

g6_per_sim <- seeded %>% summarise(n = sum(group == "G6"), .by = sim)
cat("\nG6 teams per field\n")
print(g6_per_sim %>% mutate(g6_teams = ifelse(n >= 4, "4+", as.character(n))) %>%
        count(g6_teams, name = "sims") %>% mutate(share = sims / sum(sims)))

focus <- g6_per_sim %>% filter(n >= 3) %>% arrange(desc(n), sim) %>% head(3)
if (!nrow(focus)) focus <- g6_per_sim %>% arrange(desc(n), sim) %>% head(1)
cat("\nCut line (ranks 1-16) in the simulations with the most G6 teams\n")
for (s in focus$sim) {
  x <- st %>% filter(sim == s) %>% arrange(cfp_rank)
  top_g6 <- x$team[x$group == "G6"][1]
  print(x %>% filter(cfp_rank <= 16) %>%
          transmute(sim, rank = cfp_rank, team, conference, record = paste0(wins, "-", losses), conf_champ,
                    power = round(power_rating, 1), wab = round(wab, 2), adj_margin = round(adj_margin, 1),
                    score = round(resume_score, 2), seed,
                    bid = case_when(is.na(seed) ~ "",
                                    group == "P4" & conf_champ ~ "auto: P4 champion",
                                    team == top_g6 ~ "auto: top G6",
                                    team == "Notre Dame" & cfp_rank <= PRODUCTION$playoff_seeds ~ "auto: Notre Dame",
                                    TRUE ~ "at-large")), n = Inf, width = Inf)
}
