# =============================================================================
# R/simulation/simulate_season.R — Monte Carlo season simulation.
#
# Adapted from the old folder's cfb_simulation.R. Same logic and constants;
# changes: paths come from config/paths.R, constants from config/production.R,
# the simulation count can be lowered with CFB_SIM_COUNT for quick smoke tests,
# and the interactive print/View calls were removed.
#
# How it works:
#   1. Build the production model's ratings at the current Monday cutoff
#      (R/production/production_model.R: Current C2 since 2026-09-26).
#   2. Every FBS team gets its power rating. Non-FBS opponents get the
#      model's own treatment: Current C2 rates them (Stage 3 group levels;
#      first-game rating before their first game). The former incumbent
#      EB_features put every FCS opponent at -25.
#   3. Games already final before the cutoff keep their real result; every
#      other game is drawn as margin ~ Normal(home - away + hfa, sd), rounded,
#      with ties forbidden. C2: hfa 3.0685, sd = C2's frozen Round 16 sigma
#      15.650. EB_features: hfa 3.0685, sd 15.787.
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
if (!exists("production_build")) source(PATHS$production_model)
source(PATHS$dynamic_cfp)

# ---- Execution helpers: progress logging + parallel plan (no model logic) ----
# cfbseedR::cfb_simulations() splits `simulations` into `chunks` and maps them with
# furrr::future_map(seed = TRUE): every chunk gets its own L'Ecuyer-CMRG stream derived
# from set.seed(PRODUCTION$sim_seed), so results depend on the chunk layout only, never on
# the number of workers or the future plan. Sequential and parallel runs are identical.
sim_clock <- function(t = Sys.time()) format(t, "%H:%M:%S")
sim_mins <- function(secs) sprintf("%.1f min", secs / 60)
sim_log <- function(...) { message(...); flush.console() }   # message() -> stderr, unbuffered in Actions

# Conservative worker count: available cores (cgroup/CI aware), capped at 4 and at the chunk count.
# CFB_SIM_WORKERS overrides (1 = sequential).
sim_worker_count <- function(chunks, cap = 4L) {
  override <- suppressWarnings(as.integer(Sys.getenv("CFB_SIM_WORKERS", NA)))
  if (!is.na(override) && override >= 1L) return(as.integer(min(override, chunks)))
  as.integer(max(1L, min(future::availableCores(), cap, chunks)))
}

# progressr handler: cfbseedR signals once per finished chunk; log it with timing and ETA.
sim_progress_handler <- function(state) {
  progressr::make_progression_handler("cfb_sim_log", reporter = list(
    update = function(config, state_, progression, ...) {
      if (!identical(progression$type, "update") || is.null(progression$amount) || progression$amount == 0) return(invisible())
      st <- state
      st$done <- st$done + 1L
      now <- Sys.time()
      elapsed <- as.numeric(difftime(now, st$start, units = "secs"))
      chunk_secs <- as.numeric(difftime(now, st$last, units = "secs"))
      sims_done <- sum(st$sizes[seq_len(st$done)])
      rem <- (elapsed / sims_done) * (st$total - sims_done)
      sim_log(sprintf("\n[%s] Chunk %d/%d complete\n%s / %s simulations complete (%.1f%%)\nChunk time: %s\nTotal elapsed: %s\nEstimated remaining: %s",
                      sim_clock(now), st$done, st$chunks, format(sims_done, big.mark = ","), format(st$total, big.mark = ","),
                      100 * sims_done / st$total, sim_mins(chunk_secs), sim_mins(elapsed), sim_mins(rem)))
      st$last <- now
      if (st$done + st$workers - 1L < st$chunks && st$done < st$chunks)
        sim_log(sprintf("[%s] Chunk %d/%d started - %s simulations", sim_clock(now), st$done + st$workers, st$chunks,
                        format(st$sizes[st$done + st$workers], big.mark = ",")))
      list2env(as.list(st), envir = state)   # persist updated counters
      invisible()
    }), interval = 0, intrusiveness = 0, target = "terminal", enable = TRUE)
}

# Runs cfb_dynamic_simulations() with a parallel plan (restored afterwards), chunk logging and failure context.
run_logged_simulations <- function(chunks = 8L, ...) {
  args <- list(...)
  n <- args$simulations
  chunks <- min(as.integer(chunks), n)
  sizes <- tabulate(sort(rep_len(seq_len(chunks), n)), chunks)   # same split as cfbseedR
  workers <- sim_worker_count(chunks)
  old_plan <- if (workers > 1L) future::plan(future::multisession, workers = workers) else future::plan()
  on.exit(future::plan(old_plan), add = TRUE)   # restoring the plan also shuts down the multisession workers
  weeks <- length(unique(args$games$week[is.na(args$games$result)]))
  t0 <- Sys.time()
  sim_log(sprintf("Simulation started at %s\n%s seasons | %d weeks | %d chunks | %d worker%s%s", sim_clock(t0),
                  format(n, big.mark = ","), weeks, chunks, workers, if (workers == 1L) "" else "s",
                  if (workers == 1L) " (sequential)" else ""))
  for (i in seq_len(min(workers, chunks)))
    sim_log(sprintf("[%s] Chunk %d/%d started - %s simulations", sim_clock(t0), i, chunks, format(sizes[i], big.mark = ",")))
  old_opt <- options(progressr.enable = TRUE)   # non-interactive (CI) sessions disable progressr by default
  on.exit(options(old_opt), add = TRUE)
  state <- new.env()
  list2env(list(done = 0L, start = t0, last = t0, sizes = sizes, total = n, chunks = chunks, workers = workers), state)
  handler <- sim_progress_handler(state)
  sim <- tryCatch(
    progressr::with_progress(do.call(cfb_dynamic_simulations, c(args, list(chunks = chunks))), handlers = handler),
    error = function(e) {
      sim_log(sprintf("\nSIMULATION FAILED after %s: %d/%d chunks complete (%s / %s simulations)\nError: %s",
                      sim_mins(as.numeric(difftime(Sys.time(), t0, units = "secs"))), state$done, chunks,
                      format(sum(sizes[seq_len(state$done)]), big.mark = ","), format(n, big.mark = ","), conditionMessage(e)))
      stop(e)
    })
  secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  sim_log(sprintf("\nSimulation complete\n%s seasons simulated\nWorkers used: %d\nTotal simulation runtime: %s\nAverage throughput: %.1f simulations/sec",
                  format(n, big.mark = ","), workers, sim_mins(secs), n / secs))
  sim
}

run_season_simulation <- function(season = as.integer(Sys.getenv("CFB_SEASON", "2026")),
                                  simulations = as.integer(Sys.getenv("CFB_SIM_COUNT", PRODUCTION$sim_count)),
                                  refresh_schedule = identical(Sys.getenv("CFB_REFRESH_SCHEDULE"), "true"),
                                  out_dir = PATHS$state,
                                  as_of = if (nzchar(Sys.getenv("CFB_AS_OF"))) utc(Sys.getenv("CFB_AS_OF")) else period_start(Sys.time())) {
  # CFB_AS_OF (new) lets an offline smoke test use a cutoff inside the frozen
  # schedule's horizon; production always uses the current Monday.
  live_schedule <- NULL; schedule_dir <- NULL
  if (refresh_schedule) {
    live_cfg <- v4_config()
    live_cfg$cache_dir <- file.path(out_dir, "simulation_live")
    live_schedule <- read_schedule(season, live_cfg, refresh = TRUE)
    schedule_dir <- live_cfg$cache_dir
  }
  model <- production_model_id()
  ratings <- production_build(season = season, as_of = as_of, schedule = live_schedule, schedule_dir = schedule_dir,
                              candidate = if (model == "EB_features") PRODUCTION$candidate, model = model)

  model_metadata <- attributes(ratings)[setdiff(names(attributes(ratings)), c("names", "row.names", "class"))]
  cutoff <- attr(ratings, "as_of")
  stopifnot(inherits(cutoff, "POSIXct"), length(cutoff) == 1L, !is.na(cutoff),
            !anyDuplicated(ratings$team_id), !anyDuplicated(ratings$team), all(is.finite(ratings$power_rating)))

  # Explicit simulation assumptions of the model that produced `ratings` (R/production/production_model.R).
  sim_params <- production_sim_params(ratings)
  fcs_power <- sim_params$fcs_power
  resid_sd <- sim_params$resid_sd
  simulation_hfa <- sim_params$hfa

  g <- if (is.null(live_schedule)) v4_schedule(season) else live_schedule
  g <- g[g$home_fbs | g$away_fbs, ]   # FBS-v-FBS and FBS-v-FCS only
  stopifnot(!anyNA(g$home_fbs), !anyNA(g$away_fbs), !anyNA(g$kickoff), !anyNA(g$available_at), !anyDuplicated(g$game_id))

  opponents <- bind_rows(transmute(g, team_id = home_id, team = home_team, fbs = home_fbs),
                         transmute(g, team_id = away_id, team = away_team, fbs = away_fbs)) %>% distinct()
  stopifnot(!anyNA(opponents$team), !anyNA(opponents$team_id), !anyDuplicated(opponents$team_id))
  rating_index <- match(opponents$team_id, ratings$team_id)
  if (any(opponents$fbs & is.na(rating_index))) stop("An FBS opponent lacks a rating: fix membership/ID coverage.")
  opponents$power_rating <- NA_real_
  opponents$power_rating[!opponents$fbs] <- production_nonfbs_power(ratings, opponents$team_id[!opponents$fbs])
  opponents$power_rating[opponents$fbs] <- ratings$power_rating[rating_index[opponents$fbs]]
  stopifnot(all(is.finite(opponents$power_rating)))
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
  sim <- run_logged_simulations(games = games, teams = teams, eligible_teams = cfp_eligible,
                                 simulations = simulations, playoff_seeds = PRODUCTION$playoff_seeds,
                                 compute_results = cfb_power_results, ranking_spec = cfp_ranking,
                                 autobid = PRODUCTION$playoff_autobid, tiebreaker_depth = "POINTS")
  assert_dynamic_playoff_output(sim, eligible_teams = cfp_eligible)
  if (identical(PRODUCTION$playoff_autobid, "2026")) assert_cfp_autobids_2026(sim$standings, cfp_eligible)

  sim$model_metadata <- model_metadata
  sim$ratings <- ratings
  # Saved for the site exporter (R/publish/export_site_data.R), which never sources the model: the exact
  # schedule and the per-team power (FBS and non-FBS) this simulation used. Nothing above reads them.
  sim$schedule <- g
  sim$team_power <- team_power
  sim$simulation_assumptions <- list(hfa = simulation_hfa, resid_sd = resid_sd, fcs_power = fcs_power,
                                     nonfbs_power_source = sim_params$nonfbs_power_source,
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
