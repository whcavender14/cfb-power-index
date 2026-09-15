# =============================================================================
# Simulate the 2026 CFB season using v5 power ratings (EB_features) as the
# results generator for cfbseedR::cfb_simulations()
# =============================================================================

library(dplyr)
library(cfbseedR)
suppressPackageStartupMessages(source("cfb_vCurrent_operations.R"))
suppressPackageStartupMessages(source("scripts/cfb_dynamic_playoffs.R"))

# ---------------------------------------------------------------------------
# 1. Load production ratings
# ---------------------------------------------------------------------------
season <- as.integer(Sys.getenv("CFB_SEASON", "2026"))
as_of <- period_start(Sys.time())
live_schedule <- NULL
if (identical(Sys.getenv("CFB_REFRESH_SCHEDULE"), "true")) {
  live_cfg <- v4_config()
  live_cfg$cache_dir <- file.path(Sys.getenv("CFB_DATA_DIR", "cfb_data"), "simulation_live")
  live_schedule <- read_schedule(season, live_cfg, refresh=TRUE)
}
ratings <- v5_build(season = season, as_of = as_of, candidate = "EB_features", schedule=live_schedule)

hfa <- attr(ratings, "hfa")            # 3.06853968902663
resid_sd <- 15.7874822415908           # v5_calibration() rmse, EB_features, n=2398

# Keep the original ratings object, including all its attributes.
model_metadata <- attributes(ratings)[
  setdiff(names(attributes(ratings)), c("names", "row.names", "class"))
]

cutoff <- attr(ratings, "as_of")
stopifnot(
  inherits(cutoff, "POSIXct"), length(cutoff) == 1L, !is.na(cutoff),
  !anyDuplicated(ratings$team_id),
  !anyDuplicated(ratings$team),
  all(is.finite(ratings$power_rating))
)

# Explicit simulation assumption; NOT an estimated v5 constant.
fcs_power <- -25
resid_sd <- 15.7874822415908
simulation_hfa <- 3.0685

# Use the same normalization / result-availability policy as the model.
g <- if (is.null(live_schedule)) v4_schedule(season) else live_schedule

# Retain FBS-v-FBS and FBS-v-FCS games, excluding the separate FCS season.
g <- g[g$home_fbs | g$away_fbs, ]

stopifnot(
  !anyNA(g$home_fbs), !anyNA(g$away_fbs),
  !anyNA(g$kickoff), !anyNA(g$available_at),
  !anyDuplicated(g$game_id)
)

# Resolve FBS schedule names by ID; preserve verified FCS names.
opponents <- bind_rows(
  transmute(g, team_id = home_id, team = home_team, fbs = home_fbs),
  transmute(g, team_id = away_id, team = away_team, fbs = away_fbs)
) %>%
  distinct()

stopifnot(!anyNA(opponents$team), !anyNA(opponents$team_id))
stopifnot(!anyDuplicated(opponents$team_id))

rating_index <- match(opponents$team_id, ratings$team_id)
if (any(opponents$fbs & is.na(rating_index))) {
  stop("An FBS opponent lacks a rating: fix membership/ID coverage.")
}

opponents$power_rating <- fcs_power
opponents$power_rating[opponents$fbs] <-
  ratings$power_rating[rating_index[opponents$fbs]]

# Canonical names also match cfbseedR's generated playoff games.
opponents$team[opponents$fbs] <-
  ratings$team[rating_index[opponents$fbs]]

stopifnot(!anyDuplicated(opponents$team))
g$home_team <- opponents$team[match(g$home_id, opponents$team_id)]
g$away_team <- opponents$team[match(g$away_id, opponents$team_id)]

games <- cfb_games_from_schedule(g)

# Games played before the cutoff are observed when final. Late Saturday games
# (kickoff after 00:00 UTC Sunday) fall inside the ratings' 24h availability
# buffer, so they are excluded from training but their results are real and
# must not be re-simulated. Later games are always simulated.
pre_cutoff <- g$kickoff < cutoff
known <- g$final %in% TRUE & pre_cutoff
games$result[!known] <- NA_real_

# Do not silently replay an earlier unresolved game with later ratings. A few
# non-final pre-cutoff games (cancellations, provider gaps) are dropped; many
# indicates a broken schedule fetch, so refuse to simulate.
unresolved <- pre_cutoff & !known
dropped_game_ids <- g$game_id[unresolved]
if (any(unresolved)) {
  if (sum(unresolved) > max(3L, ceiling(0.05 * sum(pre_cutoff)))) {
    stop("Unresolved pre-cutoff games (", sum(unresolved), " of ",
         sum(pre_cutoff), "): schedule fetch looks incomplete.")
  }
  message("Dropping unresolved pre-cutoff games: ",
          paste(dropped_game_ids, collapse = ", "))
  games <- games[!unresolved, ]
  g <- g[!unresolved, ]
  known <- known[!unresolved]
}
stopifnot(!any(
  g$game_id[is.na(games$result)] %in% attr(ratings, "training_ids")
))

# cfb_simulations generates its own CFP bracket.
# Conference championships require deliberate classification/participants.
if (any(games$game_type == "POST")) {
  stop("Separate bowls/CFP rows; classify actual conference title games ",
       "as CONF_CHAMP before running.")
}
stopifnot(
  !anyNA(games$week),
  !anyNA(g$neutral),
  all(games$neutral %in% c(0L, 1L))
)

teams <- ratings %>%
  transmute(team_id, team, conference = conf, division = "fbs")

fbs_teams <- teams$team

teams <- bind_rows(
  teams,
  opponents %>%
    filter(!fbs) %>%
    transmute(
      team_id, team,
      conference = NA_character_,
      division = "fcs"
    )
)

# Capture constants locally for chunked/future execution.
cfb_power_results <- local({
  power <- setNames(opponents$power_rating, opponents$team)
  hfa <- simulation_hfa
  sigma <- resid_sd
  
  function(teams, games, week_num, ...) {
    i <- which(games$week == week_num & is.na(games$result))
    if (!length(i)) return(list(teams = teams, games = games))
    
    hp <- unname(power[as.character(games$home_team[i])])
    ap <- unname(power[as.character(games$away_team[i])])
    neutral <- games$neutral[i]
    
    if (any(!is.finite(hp)) || any(!is.finite(ap))) {
      stop("Missing team power: check canonical names and coverage.")
    }
    if (length(neutral) != length(i) ||
        anyNA(neutral) || any(!neutral %in% c(0, 1))) {
      stop("Missing or invalid neutral-site flag.")
    }
    
    mu <- hp - ap + ifelse(neutral == 1, 0, hfa)
    draw <- rnorm(length(i), mean = mu, sd = sigma)
    
    # Preserve the continuous draw's winner; prohibit zero margins.
    # This is a margin approximation, not an overtime scoring model.
    games$result[i] <- ifelse(
      draw >= 0, pmax(1, round(draw)), pmin(-1, round(draw))
    )
    
    list(teams = teams, games = games)
  }
})

simulations_verify_fct(
  cfb_power_results, games = games, teams = teams
)

set.seed(1434)
sim <- cfb_dynamic_simulations(
  games = games,
  teams = teams,
  eligible_teams = fbs_teams,
  simulations = 1000L,
  playoff_seeds = 12L,
  compute_results = cfb_power_results,
  autobid = "2026",
  tiebreaker_depth = "POINTS"
)

assert_dynamic_playoff_output(sim, eligible_teams = fbs_teams)

sim$model_metadata <- model_metadata
sim$ratings <- ratings
sim$simulation_assumptions <- list(
  hfa = simulation_hfa,
  resid_sd = resid_sd,
  fcs_power = fcs_power,
  selection = "dynamic FBS standings (win pct, SOV, SOS, point differential)",
  dropped_game_ids = dropped_game_ids
)

# Current standings use observed games only.
standings <- cfb_standings(
  games[!is.na(games$result), ],
  teams,
  tiebreaker_depth = "POINTS"
)

seeds <- cfb_dynamic_playoff_seeds(
  standings,
  eligible_teams = fbs_teams,
  playoff_seeds = 12L,
  autobid = "2026"
)

sim$overall

if (interactive()) View(sim[["overall"]])

# Persist a self-describing result for the static-site exporter.
sim$season <- season
sim$updated_at <- Sys.time()
sim$as_of <- cutoff
sim$week <- if (any(known)) max(g$week[known]) else 0L
sim$simulation_count <- 1000L
sim$playoff_format <- "12 teams; 2026 automatic bids; dynamic standings-based selection"
sim$wins_scope <- "Overall wins as returned by cfbseedR (includes conference championships)"
out_dir <- Sys.getenv("CFB_DATA_DIR", "cfb_data")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
saveRDS(sim, file.path(out_dir, sprintf("simulations_%d_latest.rds", season)))
