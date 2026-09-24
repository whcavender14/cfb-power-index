# =============================================================================
# scripts/calibrate_cfp_ranking.R — fit the simulation's CFP resume score.
#
# Usage (from the project root; offline, about 30 s):
#   Rscript scripts/calibrate_cfp_ranking.R
#
# For each season 2018-2025 (2020 excluded from the fit) the frozen EB_features
# model is rebuilt at selection day, every FBS team's regular-season resume is
# summarised with cfb_resume_features() (the same code the simulation uses),
# and a rank-ordered (Plackett-Luce) logit is fitted to the committee's final
# top 25 (data/reference/cfp_final_rankings_2018_2025.csv). Title games are
# left out of the resume and enter through conf_champ, as in the simulation.
# Prints leave-one-season-out accuracy against cfbseedR's win-pct fallback and
# the coefficients to copy into config/production.R (cfp_rank_coef).
# =============================================================================
source("config/paths.R")
source("config/production.R")
suppressPackageStartupMessages({ library(dplyr); source(PATHS$model_ops); source(PATHS$dynamic_cfp) })

committee <- read.csv(file.path(PATHS$reference, "cfp_final_rankings_2018_2025.csv"), stringsAsFactors = FALSE)
g6_confs <- c("American Athletic", "Conference USA", "Mid-American", "Mountain West", "Sun Belt")

season_resumes <- function(season) {
  g <- v4_schedule(season) %>% filter(season_type == "regular", final %in% TRUE, home_fbs | away_fbs,
                                      !is.na(home_points), !is.na(away_points))
  same_conf <- g %>% filter(home_conference == away_conference, home_conference != "FBS Independents")
  noted <- same_conf %>% filter(grepl("Championship", coalesce(notes, "")))
  # Older schedules lack notes: a conference's lone game in its final week (week 13+) is its title game.
  structural <- same_conf %>%
    filter(conference_game %in% TRUE, !home_conference %in% noted$home_conference,
           !(home_team %in% c("Army", "Navy") & away_team %in% c("Army", "Navy"))) %>%
    slice_max(week, n = 1, by = home_conference) %>% filter(week >= 13, n() == 1L, .by = home_conference)
  ccg <- bind_rows(noted, structural)
  last_ccg <- max(ccg$kickoff)
  r <- v5_build(season = season, as_of = last_ccg + 25 * 3600, candidate = PRODUCTION$candidate)

  reg <- g %>% filter(kickoff <= last_ccg, !game_id %in% ccg$game_id)
  power <- setNames(r$power_rating, r$team_id)
  opp_power <- function(id, fbs) ifelse(fbs & id %in% r$team_id, power[as.character(id)], PRODUCTION$sim_fcs_power)
  tg <- bind_rows(
    reg %>% transmute(team_id = home_id, conf_game = conference_game %in% TRUE, opp_power = opp_power(away_id, away_fbs),
                      loc = ifelse(neutral, 0, 1), margin = home_points - away_points),
    reg %>% transmute(team_id = away_id, conf_game = conference_game %in% TRUE, opp_power = opp_power(home_id, home_fbs),
                      loc = ifelse(neutral, 0, -1), margin = away_points - home_points)) %>%
    filter(team_id %in% r$team_id) %>% mutate(sim = season, team = r$team[match(team_id, r$team_id)])
  feats <- cfb_resume_features(tg, sort(r$power_rating, decreasing = TRUE)[PRODUCTION$cfp_rank_benchmark],
                               PRODUCTION$sim_resid_sd, PRODUCTION$sim_hfa, PRODUCTION$cfp_rank_margin_cap)
  rec <- tg %>% summarise(win_pct = mean(margin > 0), pd = sum(margin),
                          conf_pct = if (any(conf_game)) mean(margin[conf_game] > 0) else 0, .by = "team")

  # Champion: title-game winner, else best conference record (conferences of 6+ teams).
  out <- r %>% select(team, conf, power_rating) %>% inner_join(feats, by = "team") %>% inner_join(rec, by = "team")
  big <- out %>% count(conf) %>% filter(n >= 6, conf != "FBS Independents") %>% pull(conf)
  champs <- ccg %>% transmute(conf = home_conference, champ = ifelse(home_points > away_points, home_team, away_team)) %>%
    filter(conf %in% big)
  champs <- bind_rows(champs, out %>% filter(conf %in% setdiff(big, champs$conf)) %>%
                        arrange(desc(conf_pct), desc(win_pct), desc(power_rating)) %>%
                        slice(1, .by = conf) %>% transmute(conf, champ = team))
  out %>% mutate(season = season, conf_champ = as.numeric(team %in% champs$champ),
                 g6 = conf %in% g6_confs | (conf == "Pac-12" & season >= 2024)) %>%
    left_join(committee %>% transmute(season, team = school, cfp_rank = rank), by = c("season", "team"))
}

d <- bind_rows(lapply(setdiff(2018:2025, 2020), season_resumes))
stopifnot(sum(!is.na(d$cfp_rank)) == 25 * n_distinct(d$season))
vars <- c("wab", "adj_margin", "conf_champ")

pl_loglik <- function(beta, dat) {
  ll <- 0
  for (yy in split(dat, dat$season)) {
    s <- as.vector(as.matrix(yy[, vars]) %*% beta); left <- rep(TRUE, nrow(yy))
    for (i in order(yy$cfp_rank, na.last = NA)) {
      m <- max(s[left]); ll <- ll + s[i] - m - log(sum(exp(s[left] - m))); left[i] <- FALSE
    }
  }
  ll
}
fit <- function(dat) {
  o <- optim(rep(0.1, length(vars)), function(b) -pl_loglik(b, dat), method = "BFGS", hessian = TRUE)
  list(beta = setNames(o$par, vars), se = setNames(sqrt(diag(solve(o$hessian))), vars))
}
evaluate <- function(dat, score) {
  dat$score <- score
  dat %>% mutate(pred = rank(-score, ties.method = "first"), .by = season) %>%
    summarise(top12_overlap = sum(pred <= 12 & coalesce(cfp_rank, 99L) <= 12),
              spearman = cor(pred[!is.na(cfp_rank)], cfp_rank[!is.na(cfp_rank)], method = "spearman"),
              g6_top12_model = sum(pred <= 12 & g6), g6_top12_committee = sum(coalesce(cfp_rank, 99L) <= 12 & g6), .by = season)
}

loso <- bind_rows(lapply(unique(d$season), function(yy) {
  f <- fit(d %>% filter(season != yy)); te <- d %>% filter(season == yy)
  evaluate(te, as.vector(as.matrix(te[, vars]) %*% f$beta))
}))
# cfbseedR's fallback orders by win pct, then conference SOV/SOS, then point differential; SOV/SOS omitted here.
fb <- d %>% arrange(season, desc(win_pct), desc(pd), team) %>% mutate(fb_rank = row_number(), .by = season)
fallback <- evaluate(fb, -fb$fb_rank)
report <- function(x, label) cat(sprintf("%-28s top-12 overlap %.2f/12 | Spearman %.3f | G6 in top 12 %.2f (committee %.2f)\n", label,
                                         mean(x$top12_overlap), mean(x$spearman), mean(x$g6_top12_model), mean(x$g6_top12_committee)))
cat("Seasons:", paste(unique(d$season), collapse = ", "), "\n")
report(loso, "Resume score (held out)")
report(fallback, "Win-pct-first fallback")
f <- fit(d)
cat("\nFull-sample coefficients (paste into PRODUCTION$cfp_rank_coef):\n")
print(signif(rbind(beta = f$beta, se = f$se), 5))
