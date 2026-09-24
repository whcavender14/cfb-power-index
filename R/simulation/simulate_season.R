# =============================================================================
# R/simulation/simulate_season.R — Monte Carlo season simulation.
#
# Adapted from the old folder's cfb_simulation.R. Same logic and constants;
# changes: paths come from config/paths.R, constants from config/production.R,
# the simulation count can be lowered with CFB_SIM_COUNT for quick smoke tests,
# and the interactive print/View calls were removed.
#
# How it works:
#   1. Build the frozen EB_features ratings at the current Monday cutoff.
#   2. Every FBS team gets its power rating; every FCS opponent gets -25.
#   3. Games already final before the cutoff keep their real result; every
#      other game is drawn as margin ~ Normal(home - away + 3.0685, 15.787),
#      rounded, with ties forbidden.
#   4. cfbseedR plays the regular season + conference title games. In every
#      simulation the eligible FBS teams are ranked by a resume score (wins
#      above a benchmark team on the same schedule, opponent-adjusted margin,
#      conference title; see config/production.R), NOT by their own power
#      ratings; cfbseedR seeds the 12-team CFP from that ranking with the 2026
#      auto-bid rules, then the bracket is simulated.
#   5. Result saved to <state>/simulations_<season>_latest.rds for the exporter.
#
# Run via scripts/02_simulate_season.R (or scripts/run_weekly_pipeline.R).
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(cfbseedR)
})
if (!exists("PATHS")) stop("Source config/paths.R first", call. = FALSE)
if (!exists("PRODUCTION")) source(file.path(PATHS$root, "config", "production.R"))
if (!exists("v5_build")) suppressPackageStartupMessages(source(PATHS$model_ops))
source(PATHS$dynamic_cfp)

run_season_simulation <- function(season = as.integer(Sys.getenv("CFB_SEASON", "2026")),
                                  simulations = as.integer(Sys.getenv("CFB_SIM_COUNT", PRODUCTION$sim_count)),
                                  refresh_schedule = identical(Sys.getenv("CFB_REFRESH_SCHEDULE"), "true"),
                                  out_dir = PATHS$state,
                                  as_of = if (nzchar(Sys.getenv("CFB_AS_OF"))) utc(Sys.getenv("CFB_AS_OF")) else period_start(Sys.time())) {
  # CFB_AS_OF (new) lets an offline smoke test use a cutoff inside the frozen
  # schedule's horizon; production always uses the current Monday.
  live_schedule <- NULL
  if (refresh_schedule) {
    live_cfg <- v4_config()
    live_cfg$cache_dir <- file.path(out_dir, "simulation_live")
    live_schedule <- read_schedule(season, live_cfg, refresh = TRUE)
  }
  ratings <- v5_build(season = season, as_of = as_of, candidate = PRODUCTION$candidate, schedule = live_schedule)

  model_metadata <- attributes(ratings)[setdiff(names(attributes(ratings)), c("names", "row.names", "class"))]
  cutoff <- attr(ratings, "as_of")
  stopifnot(inherits(cutoff, "POSIXct"), length(cutoff) == 1L, !is.na(cutoff),
            !anyDuplicated(ratings$team_id), !anyDuplicated(ratings$team), all(is.finite(ratings$power_rating)))

  # Explicit simulation assumptions; NOT estimated v5 constants.
  fcs_power <- PRODUCTION$sim_fcs_power
  resid_sd <- PRODUCTION$sim_resid_sd
  simulation_hfa <- PRODUCTION$sim_hfa

  g <- if (is.null(live_schedule)) v4_schedule(season) else live_schedule
  g <- g[g$home_fbs | g$away_fbs, ]   # FBS-v-FBS and FBS-v-FCS only
  stopifnot(!anyNA(g$home_fbs), !anyNA(g$away_fbs), !anyNA(g$kickoff), !anyNA(g$available_at), !anyDuplicated(g$game_id))

  opponents <- bind_rows(transmute(g, team_id = home_id, team = home_team, fbs = home_fbs),
                         transmute(g, team_id = away_id, team = away_team, fbs = away_fbs)) %>% distinct()
  stopifnot(!anyNA(opponents$team), !anyNA(opponents$team_id), !anyDuplicated(opponents$team_id))
  rating_index <- match(opponents$team_id, ratings$team_id)
  if (any(opponents$fbs & is.na(rating_index))) stop("An FBS opponent lacks a rating: fix membership/ID coverage.")
  opponents$power_rating <- fcs_power
  opponents$power_rating[opponents$fbs] <- ratings$power_rating[rating_index[opponents$fbs]]
  opponents$team[opponents$fbs] <- ratings$team[rating_index[opponents$fbs]]   # canonical names
  stopifnot(!anyDuplicated(opponents$team))
  g$home_team <- opponents$team[match(g$home_id, opponents$team_id)]
  g$away_team <- opponents$team[match(g$away_id, opponents$team_id)]

  games <- cfb_games_from_schedule(g)

  # Final games before the cutoff are observed (including late-Saturday games
  # inside the ratings' 24h availability buffer). Later games are simulated.
  pre_cutoff <- g$kickoff < cutoff
  known <- g$final %in% TRUE & pre_cutoff
  games$result[!known] <- NA_real_

  # Drop a few unresolved pre-cutoff games (cancellations); many means the
  # schedule fetch is broken, so refuse to simulate.
  unresolved <- pre_cutoff & !known
  dropped_game_ids <- g$game_id[unresolved]
  if (any(unresolved)) {
    if (sum(unresolved) > max(3L, ceiling(0.05 * sum(pre_cutoff)))) {
      stop("Unresolved pre-cutoff games (", sum(unresolved), " of ", sum(pre_cutoff), "): schedule fetch looks incomplete.")
    }
    message("Dropping unresolved pre-cutoff games: ", paste(dropped_game_ids, collapse = ", "))
    games <- games[!unresolved, ]; g <- g[!unresolved, ]; known <- known[!unresolved]
  }
  stopifnot(!any(g$game_id[is.na(games$result)] %in% attr(ratings, "training_ids")))
  if (any(games$game_type == "POST")) {
    stop("Separate bowls/CFP rows; classify actual conference title games as CONF_CHAMP before running.")
  }
  stopifnot(!anyNA(games$week), !anyNA(g$neutral), all(games$neutral %in% c(0L, 1L)))

  teams <- ratings %>% transmute(team_id, team, conference = conf, division = "fbs")
  fbs_teams <- teams$team
  if (!all(PRODUCTION$cfp_ineligible_teams %in% fbs_teams)) stop("cfp_ineligible_teams lists a team that is not FBS this season.")
  cfp_eligible <- setdiff(fbs_teams, PRODUCTION$cfp_ineligible_teams)
  teams <- bind_rows(teams, opponents %>% filter(!fbs) %>%
                       transmute(team_id, team, conference = NA_character_, division = "fcs"))

  team_power <- setNames(opponents$power_rating, opponents$team)
  cfp_ranking <- list(coef = PRODUCTION$cfp_rank_coef,
                      benchmark_rating = sort(ratings$power_rating, decreasing = TRUE)[PRODUCTION$cfp_rank_benchmark],
                      sigma = resid_sd, hfa = simulation_hfa, margin_cap = PRODUCTION$cfp_rank_margin_cap,
                      team_power = team_power)

  cfb_power_results <- local({
    power <- team_power
    hfa <- simulation_hfa
    sigma <- resid_sd
    function(teams, games, week_num, ...) {
      i <- which(games$week == week_num & is.na(games$result))
      if (!length(i)) return(list(teams = teams, games = games))
      hp <- unname(power[as.character(games$home_team[i])])
      ap <- unname(power[as.character(games$away_team[i])])
      neutral <- games$neutral[i]
      if (any(!is.finite(hp)) || any(!is.finite(ap))) stop("Missing team power: check canonical names and coverage.")
      if (length(neutral) != length(i) || anyNA(neutral) || any(!neutral %in% c(0, 1))) stop("Missing or invalid neutral-site flag.")
      mu <- hp - ap + ifelse(neutral == 1, 0, hfa)
      draw <- rnorm(length(i), mean = mu, sd = sigma)
      # Preserve the continuous draw's winner; prohibit zero margins.
      games$result[i] <- ifelse(draw >= 0, pmax(1, round(draw)), pmin(-1, round(draw)))
      list(teams = teams, games = games)
    }
  })

  simulations_verify_fct(cfb_power_results, games = games, teams = teams)

  set.seed(PRODUCTION$sim_seed)
  sim <- cfb_dynamic_simulations(games = games, teams = teams, eligible_teams = cfp_eligible,
                                 simulations = simulations, playoff_seeds = PRODUCTION$playoff_seeds,
                                 compute_results = cfb_power_results, ranking_spec = cfp_ranking,
                                 autobid = PRODUCTION$playoff_autobid, tiebreaker_depth = "POINTS")
  assert_dynamic_playoff_output(sim, eligible_teams = cfp_eligible)
  if (identical(PRODUCTION$playoff_autobid, "2026")) assert_cfp_autobids_2026(sim$standings, cfp_eligible)

  sim$model_metadata <- model_metadata
  sim$ratings <- ratings
  sim$simulation_assumptions <- list(hfa = simulation_hfa, resid_sd = resid_sd, fcs_power = fcs_power,
                                     selection = "dynamic resume ranking per simulation (wins above benchmark, adjusted margin, conference title)",
                                     cfp_ranking = list(coef = as.list(cfp_ranking$coef),
                                                        benchmark_rating = cfp_ranking$benchmark_rating,
                                                        margin_cap = cfp_ranking$margin_cap),
                                     cfp_ineligible_teams = PRODUCTION$cfp_ineligible_teams,
                                     dropped_game_ids = dropped_game_ids)
  sim$season <- season
  sim$updated_at <- Sys.time()
  sim$as_of <- cutoff
  sim$week <- if (any(known)) max(g$week[known]) else 0L
  sim$simulation_count <- simulations
  sim$playoff_format <- "12 teams; 2026 automatic bids; dynamic resume-based selection"
  sim$wins_scope <- "Overall wins as returned by cfbseedR (includes conference championships)"
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  saveRDS(sim, file.path(out_dir, sprintf("simulations_%d_latest.rds", season)))
  invisible(sim)
}
