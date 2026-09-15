# Helpers for variance-driven CFP selection with cfbseedR 0.2.x.
#
# cfbseedR deliberately treats a supplied rankings table as static across every
# simulation. Its rankings = NULL fallback is dynamic, but it ranks every team
# in the standings, including FCS opponents needed for schedule coverage. This
# wrapper runs the regular season first, seeds only eligible FBS teams from each
# simulated standings table, and then uses cfbseedR's bracket simulator.

cfb_dynamic_playoff_seeds <- function(standings, eligible_teams,
                                      playoff_seeds = 12L,
                                      autobid = "2026") {
  eligible_teams <- unique(as.character(eligible_teams))
  eligible <- dplyr::filter(
    standings,
    .data$team %in% eligible_teams
  )

  if (!nrow(eligible)) {
    stop("No playoff-eligible teams appear in the simulated standings.")
  }

  cfbseedR::cfb_playoff_seeds(
    eligible,
    rankings = NULL,
    playoff_seeds = playoff_seeds,
    autobid = autobid
  )
}

cfb_dynamic_simulations <- function(games, teams, eligible_teams,
                                    compute_results,
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

  seeded <- cfb_dynamic_playoff_seeds(
    regular$standings,
    eligible_teams = eligible_teams,
    playoff_seeds = playoff_seeds,
    autobid = autobid
  )
  seed_map <- dplyr::select(seeded, "sim", "team", "seed")
  standings <- dplyr::left_join(
    dplyr::select(regular$standings, -"seed"),
    seed_map,
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
    "dynamic FBS standings: win_pct, SOV, SOS, point differential"
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
