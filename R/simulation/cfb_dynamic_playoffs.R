# Helpers for variance-driven CFP selection with cfbseedR 0.2.x.
#
# cfbseedR treats a supplied rankings table as static across every simulation,
# and its rankings = NULL fallback orders teams by win pct first, with only
# conference-scoped SOV/SOS as tiebreakers, so high-record G6 teams outrank
# P4 teams with better national resumes. This wrapper runs the regular season
# first, ranks the eligible FBS teams separately in every simulation by a
# national resume score, and passes each simulation's ranking to cfbseedR's
# seeding (2026 automatic bids) and bracket simulator.

# team_games: one row per team per game with columns sim, team, opp_power,
# loc (+1 home, -1 away, 0 neutral) and margin (team points minus opponent's).
cfb_resume_features <- function(team_games, benchmark_rating, sigma, hfa, margin_cap) {
  dplyr::summarise(
    dplyr::mutate(
      team_games,
      win = as.numeric(.data$margin > 0),
      bench_win_prob = stats::pnorm((benchmark_rating - .data$opp_power + hfa * .data$loc) / sigma),
      game_rating = pmin(pmax(.data$margin, -margin_cap), margin_cap) + .data$opp_power - hfa * .data$loc
    ),
    wab = sum(.data$win - .data$bench_win_prob),
    adj_margin = mean(.data$game_rating),
    .by = c("sim", "team")
  )
}

# Conference title games are excluded: their outcome enters through conf_champ,
# matching how the coefficients were calibrated.
cfb_sim_team_games <- function(games, team_power) {
  g <- dplyr::filter(games, .data$game_type == "REG", !is.na(.data$result))
  tg <- dplyr::bind_rows(
    dplyr::transmute(g, .data$sim, team = .data$home_team, opp = .data$away_team,
                     loc = ifelse(.data$neutral == 1, 0, 1), margin = .data$result),
    dplyr::transmute(g, .data$sim, team = .data$away_team, opp = .data$home_team,
                     loc = ifelse(.data$neutral == 1, 0, -1), margin = -.data$result)
  )
  tg$opp_power <- unname(team_power[tg$opp])
  if (anyNA(tg$opp_power)) stop("Missing opponent power for the CFP ranking.")
  tg
}

# ranking_spec: list(coef, benchmark_rating, sigma, hfa, margin_cap, team_power),
# where team_power is named by team and covers every FBS and FCS team.
cfb_dynamic_cfp_ranking <- function(standings, games, eligible_teams, ranking_spec) {
  tg <- dplyr::filter(cfb_sim_team_games(games, ranking_spec$team_power),
                      .data$team %in% eligible_teams)
  feats <- cfb_resume_features(tg, ranking_spec$benchmark_rating, ranking_spec$sigma,
                               ranking_spec$hfa, ranking_spec$margin_cap)
  b <- ranking_spec$coef
  ranked <- dplyr::mutate(
    dplyr::inner_join(
      dplyr::select(dplyr::filter(standings, .data$team %in% eligible_teams),
                    "sim", "team", "conf_champ", "win_pct"),
      feats,
      by = dplyr::join_by("sim", "team")
    ),
    resume_score = b[["wab"]] * .data$wab + b[["adj_margin"]] * .data$adj_margin +
      b[["conf_champ"]] * .data$conf_champ
  )
  ranked <- dplyr::arrange(ranked, .data$sim, dplyr::desc(.data$resume_score),
                           dplyr::desc(.data$win_pct), .data$team)
  dplyr::mutate(ranked, cfp_rank = dplyr::row_number(), .by = "sim")
}

# ranking: per-simulation ranks with columns sim, team, cfp_rank.
cfb_dynamic_playoff_seeds <- function(standings, ranking, eligible_teams,
                                      playoff_seeds = 12L,
                                      autobid = "2026") {
  eligible_teams <- unique(as.character(eligible_teams))
  eligible <- dplyr::filter(standings, .data$team %in% eligible_teams)
  if (!nrow(eligible)) {
    stop("No playoff-eligible teams appear in the simulated standings.")
  }

  ranks <- split(dplyr::select(ranking, "team", rank = "cfp_rank"), ranking$sim)
  dplyr::bind_rows(lapply(split(eligible, eligible$sim), function(st) {
    cfbseedR::cfb_playoff_seeds(
      st,
      rankings = ranks[[as.character(st$sim[1])]],
      playoff_seeds = playoff_seeds,
      autobid = autobid
    )
  }))
}

cfb_dynamic_simulations <- function(games, teams, eligible_teams,
                                    compute_results, ranking_spec,
                                    simulations = 10000L,
                                    playoff_seeds = 12L,
                                    tiebreaker_depth = "SOS",
                                    autobid = "2026",
                                    tiebreaker_data = NULL,
                                    chunks = 8L,
                                    verbosity = "MIN",
                                    ...) {
  regular <- cfbseedR::cfb_simulations(
    games = games,
    teams = teams,
    simulations = simulations,
    playoff_seeds = playoff_seeds,
    compute_results = compute_results,
    rankings = NULL,
    autobid = autobid,
    tiebreaker_depth = tiebreaker_depth,
    tiebreaker_data = tiebreaker_data,
    chunks = chunks,
    verbosity = verbosity,
    sim_include = "REG",
    ...
  )

  ranking <- cfb_dynamic_cfp_ranking(regular$standings, regular$games,
                                     eligible_teams, ranking_spec)
  seeded <- cfb_dynamic_playoff_seeds(
    regular$standings,
    ranking = ranking,
    eligible_teams = eligible_teams,
    playoff_seeds = playoff_seeds,
    autobid = autobid
  )
  seed_map <- dplyr::select(seeded, "sim", "team", "seed")
  standings <- dplyr::left_join(
    dplyr::left_join(
      dplyr::select(regular$standings, -"seed"),
      seed_map,
      by = dplyr::join_by("sim", "team")
    ),
    dplyr::select(ranking, "sim", "team", "wab", "adj_margin", "resume_score", "cfp_rank"),
    by = dplyr::join_by("sim", "team")
  )

  seed_counts <- dplyr::summarise(
    standings,
    seeded = sum(!is.na(.data$seed)),
    .by = "sim"
  )
  if (any(seed_counts$seeded != playoff_seeds)) {
    stop("Dynamic CFP selection did not produce exactly ", playoff_seeds,
         " teams in every simulation.")
  }
  if (any(!is.na(standings$seed) &
          !standings$team %in% eligible_teams)) {
    stop("An ineligible team received a CFP seed.")
  }

  sim_ids <- sort(unique(standings$sim))
  n_teams <- nrow(teams)
  sim_teams <- dplyr::mutate(
    teams[rep(seq_len(n_teams), times = length(sim_ids)), ],
    sim = rep(sim_ids, each = n_teams)
  )

  simulate_playoffs <- getFromNamespace(
    "sims_simulate_playoffs",
    "cfbseedR"
  )
  post <- simulate_playoffs(
    sim_games = regular$games,
    sim_teams = sim_teams,
    standings = standings,
    compute_results = compute_results,
    playoff_seeds = playoff_seeds,
    ...
  )

  standings <- dplyr::mutate(
    dplyr::left_join(
      standings,
      post$exits,
      by = dplyr::join_by("sim", "team")
    ),
    exit = dplyr::coalesce(.data$exit, 0L)
  )

  regular$standings <- dplyr::arrange(
    standings,
    .data$sim,
    .data$conference,
    .data$conf_rank,
    .data$team
  )
  regular$games <- post$games
  regular$overall <- dplyr::arrange(
    dplyr::summarise(
      standings,
      wins = mean(.data$wins),
      conf_champ = mean(.data$conf_champ),
      playoff = mean(!is.na(.data$seed)),
      seed1 = mean(!is.na(.data$seed) & .data$seed == 1L),
      won_natty = mean(.data$exit == post$champ_exit),
      .by = c("conference", "team")
    ),
    .data$conference,
    .data$team
  )
  regular$game_summary <- dplyr::arrange(
    dplyr::mutate(
      dplyr::summarise(
        post$games,
        away_wins = sum(.data$result < 0),
        home_wins = sum(.data$result > 0),
        ties = sum(.data$result == 0),
        result = mean(.data$result),
        .by = c("game_type", "week", "away_team", "home_team")
      ),
      games_played = .data$away_wins + .data$home_wins + .data$ties,
      away_percentage = (.data$away_wins + 0.5 * .data$ties) /
        .data$games_played,
      home_percentage = (.data$home_wins + 0.5 * .data$ties) /
        .data$games_played
    ),
    .data$week,
    .data$away_team
  )
  regular$sim_params$sim_include <- "POST"
  regular$sim_params$ranking_mode <-
    "dynamic resume ranking per simulation: wins above benchmark, adjusted margin, conference title"
  regular$sim_params$finished_at <- Sys.time()
  regular
}

assert_dynamic_playoff_output <- function(sim, eligible_teams,
                                           low_win_cutoff = 9.5) {
  if (any(!is.na(sim$standings$seed) &
          !sim$standings$team %in% eligible_teams)) {
    stop("An ineligible team received a CFP seed.")
  }

  low_win_locks <- dplyr::filter(
    sim$overall,
    .data$wins < low_win_cutoff,
    .data$playoff >= 1 - .Machine$double.eps
  )
  if (nrow(low_win_locks)) {
    stop(
      "Implausible static CFP allocation: 100% playoff probability below ",
      low_win_cutoff, " projected wins for ",
      paste(low_win_locks$team, collapse = ", "), "."
    )
  }
  invisible(sim)
}

# Per-simulation checks of the 2026 automatic bids: every eligible P4
# champion and the highest-ranked eligible G6 team must be in the field.
assert_cfp_autobids_2026 <- function(standings, eligible_teams) {
  p4 <- c("ACC", "Big 12", "Big Ten", "SEC")
  g6 <- c("American Athletic", "Conference USA", "Mid-American", "Mountain West", "Pac-12", "Sun Belt")
  el <- dplyr::filter(standings, .data$team %in% eligible_teams)
  missing_champs <- dplyr::filter(el, .data$conference %in% p4, .data$conf_champ, is.na(.data$seed))
  top_g6 <- dplyr::slice_min(dplyr::filter(el, .data$conference %in% g6), .data$cfp_rank, n = 1, by = "sim")
  if (nrow(missing_champs) || any(is.na(top_g6$seed))) {
    stop("A 2026 automatic qualifier (P4 champion or top-ranked G6 team) was left out of the CFP.")
  }
  invisible(TRUE)
}
