# =============================================================================
# CFB POINT-SPREAD POWER RATINGS
#
# Produces team ratings denominated in POINTS relative to an average FBS team
# on a neutral field, such that:
#
#     Neutral spread(A vs B) = rating_A - rating_B
#     Home spread(A vs B)    = rating_A - rating_B + HFA
#
# Core model (Section 3): a single penalized least-squares fit on TEAM-GAME
# POINTS SCORED, with a full set of offense dummies, a full set of defense
# dummies, and one home-field parameter. Team strength and opponent strength
# are estimated JOINTLY -- schedule strength is not a post-hoc correction, it
# is what the regression is doing. Coefficients are shrunk toward a preseason
# prior built from prior-season ratings and recruiting talent, which is what
# actually stabilizes small-sample and weak-schedule teams.
#
# Key differences from the prior EPA/play ridge implementation:
#   * Response is points, not EPA/play. No EPA->points conversion factor is
#     invented; EPA is *already* denominated in points, and the alignment
#     between the two response components is estimated, then checked.
#   * Design matrix is built by hand. model.matrix(~ a + b - 1) silently gives
#     FULL dummies for the first factor and REFERENCE-CODED dummies for the
#     second, which made offensive and defensive coefficients live on different
#     scales and made off - def incoherent.
#   * Shrinkage target is a preseason prior, not zero (= league average).
#   * Neutral-site games are excluded from HFA.
#   * lambda is chosen by WALK-FORWARD validation, not random k-fold CV.
#   * Explicit centering step so that 0 = average FBS team, by construction.
#
# Requires: dplyr, tidyr, purrr, tibble, rlang, ggplot2, cfbfastR
# Deliberately does NOT require glmnet -- we solve the penalized normal
# equations directly so we can (a) leave HFA and the intercept unpenalized,
# (b) shrink toward a nonzero prior, (c) recover a variance matrix.
# =============================================================================

library(dplyr)
library(tidyr)
library(purrr)
library(tibble)
library(rlang)
suppressWarnings(suppressMessages(library(ggplot2)))

# -----------------------------------------------------------------------------
# CONFIG
# -----------------------------------------------------------------------------

#' Most recent seasons for which the postseason has finished.
#' National title games land in mid-to-late January, so before Feb 1 we treat
#' the previous calendar year's season as still in progress.
get_default_seasons <- function(n = 3, as_of = Sys.Date()) {
  yr <- as.integer(format(as_of, "%Y"))
  mo <- as.integer(format(as_of, "%m"))
  last_complete <- if (mo >= 2) yr - 1L else yr - 2L
  seq(last_complete - n + 1L, last_complete)
}

default_config <- function() {
  list(
    seasons   = get_default_seasons(3),
    cache_dir = tempdir(),
    
    response = list(
      # w_epa: weight on the EPA-implied points component of the response.
      # 0 = model actual points scored only (unbiased but noisy).
      # 1 = model EPA-implied points only (stable but ignores finishing,
      #     kicking, turnover-for-score outcomes).
      # Default 0.6 leans on EPA for variance reduction while keeping real
      # scoring in the loop. TUNE THIS: tune_response() puts it on the grid.
      w_epa = 0.60,
      
      # Symmetric cap on the modeled game margin, in points. Winning by 62
      # instead of 41 carries almost no marginal information about team
      # strength (starters rest, opponent collapses) but has large leverage on
      # a squared-error fit. Capping is the primary defense against
      # blowout-driven inflation of teams with weak schedules. Inf disables.
      margin_cap = 38,
      
      # Include special-teams EPA in the EPA component. Points scored already
      # include ST points, so excluding ST EPA would make the two response
      # components measure different things.
      include_special_teams = TRUE,
      
      # Garbage-time filter applies ONLY to the per-play EPA rate diagnostics
      # (offense/defense/rush/pass EPA ratings), never to the points response.
      # Filtering the points response would truncate exactly the games the
      # model needs to see and would break the identity
      # points ~= baseline + total EPA.
      garbage_time = list(
        exclude = TRUE,
        # Score-and-time dependent, in the spirit of Connelly's definition.
        # The old fixed "21+ points and under 5:00 in Q4" rule removed
        # essentially nothing.
        q1_margin = 38, q2_margin = 28, q3_margin = 22, q4_margin = 16
      )
    ),
    
    prior = list(
      enabled = TRUE,
      # Preseason rating = intercept
      #                  + carryover * prior_season_rating
      #                  + talent_beta * talent_z
      # Coefficients are ESTIMATED from strictly earlier seasons when at least
      # two are available; these are the documented fallbacks otherwise.
      # carryover ~0.55 reflects the usual year-over-year regression to the
      # mean of team strength in FBS.
      fallback_carryover   = 0.55,
      fallback_talent_beta = 6.0,   # points per SD of recruiting composite
      fit_from_history     = TRUE,
      # Preseason strength is split evenly between offense and defense. The
      # talent composite is a single number, so there is no basis in the data
      # for an asymmetric split. STATED ASSUMPTION.
      offense_share        = 0.5
    ),
    
    fit = list(
      # Penalty grid, searched by walk-forward validation. Units: this is the
      # ridge lambda on (coef - prior)^2 in the penalized normal equations,
      # with the response in points.
      lambda_grid = c(2, 4, 8, 16, 32, 64, 128, 256, 512),
      lambda      = NULL,   # set to a number to skip lambda selection
      
      # FCS teams are rated, because losing to one is real information and
      # because their coefficients are what anchor FBS-vs-FCS games. But they
      # are shrunk much harder toward a common FCS prior: they play 0-3 games
      # against the rated graph, so a free parameter per FCS team is
      # unidentified in practice.
      fcs_lambda_multiplier = 6,
      fcs_prior_rating      = -28,  # points vs average FBS, neutral field
      fcs_game_weight       = 0.60, # relative weight of FBS-vs-FCS games
      
      # Within-season recency weighting. 0 disables. Modest by default: a
      # single-season rating is a season-long average, not a "current form"
      # estimate, and aggressive recency weighting mostly adds variance.
      recency_halflife_weeks = 0
    ),
    
    validation = list(
      first_predicted_week = 4,  # need a few weeks of graph before predicting
      exclude_fcs_games    = TRUE
    )
  )
}

# -----------------------------------------------------------------------------
# 1. CACHING / IO HELPERS
# -----------------------------------------------------------------------------

safe_cache_write <- function(obj, cache_file) {
  dir_ok <- dir.exists(dirname(cache_file)) ||
    tryCatch({
      dir.create(dirname(cache_file), recursive = TRUE, showWarnings = FALSE)
      TRUE
    }, error = function(e) FALSE)
  
  if (!dir_ok) {
    warning("Cache directory not writable (", dirname(cache_file),
            "); continuing without caching.", call. = FALSE)
    return(invisible(FALSE))
  }
  tryCatch({
    saveRDS(obj, cache_file)
    invisible(TRUE)
  }, error = function(e) {
    warning("Could not write cache file ", cache_file, " (",
            conditionMessage(e), "); continuing without caching.", call. = FALSE)
    invisible(FALSE)
  })
}

cached <- function(cache_file, use_cache, expr) {
  if (use_cache && file.exists(cache_file)) return(readRDS(cache_file))
  val <- force(expr)
  if (use_cache) safe_cache_write(val, cache_file)
  val
}

require_cfbfastR <- function() {
  if (!requireNamespace("cfbfastR", quietly = TRUE)) {
    stop("cfbfastR is not installed. install.packages('cfbfastR')")
  }
}

#' Rename the first column of `df` matching any alias to `canonical`.
apply_alias_map <- function(df, alias_map, required, what) {
  nm <- names(df)
  for (canonical in names(alias_map)) {
    if (canonical %in% nm) next
    found <- intersect(alias_map[[canonical]], nm)
    if (length(found) > 0) {
      df <- dplyr::rename(df, !!canonical := !!rlang::sym(found[1]))
      nm <- names(df)
    }
  }
  missing <- setdiff(required, names(df))
  if (length(missing) > 0) {
    stop(what, ": could not find or alias required columns: ",
         paste(missing, collapse = ", "),
         ".\nActual columns present: ", paste(names(df), collapse = ", "),
         ".\nAdd the real name to the alias map in the corresponding ",
         "standardize_* function.")
  }
  df
}

# -----------------------------------------------------------------------------
# 2. DATA PULLS
# -----------------------------------------------------------------------------

standardize_pbp_columns <- function(pbp) {
  alias_map <- list(
    offense_play  = c("offense_play", "pos_team"),
    defense_play  = c("defense_play", "def_pos_team"),
    season        = c("season", "year"),
    week          = c("week", "wk"),
    game_id       = c("game_id", "id"),
    EPA           = c("EPA", "epa"),
    play_type     = c("play_type"),
    period        = c("period", "qtr", "half"),
    clock_minutes = c("clock_minutes", "clock.minutes", "clock_min"),
    clock_seconds = c("clock_seconds", "clock.seconds", "clock_sec"),
    offense_score = c("offense_score", "pos_team_score"),
    defense_score = c("defense_score", "def_pos_team_score"),
    home          = c("home", "home_team"),
    away          = c("away", "away_team")
  )
  required <- c("offense_play", "defense_play", "season", "week", "game_id",
                "EPA", "play_type", "period", "offense_score", "defense_score",
                "home", "away")
  pbp <- apply_alias_map(pbp, alias_map, required, "standardize_pbp_columns()")
  
  # Clock columns are only needed for garbage-time flagging of the EPA rate
  # diagnostics. Degrade gracefully rather than failing the whole pull.
  if (!"clock_minutes" %in% names(pbp)) pbp$clock_minutes <- NA_real_
  if (!"clock_seconds" %in% names(pbp)) pbp$clock_seconds <- NA_real_
  if (!"season_type"   %in% names(pbp)) pbp$season_type   <- "regular"
  
  if (!all(c("rush", "pass") %in% names(pbp))) {
    pbp <- pbp %>%
      mutate(
        rush = as.integer(grepl("Rush", play_type, ignore.case = TRUE)),
        pass = as.integer(grepl("Pass|Sack|Interception", play_type,
                                ignore.case = TRUE))
      )
  }
  pbp %>%
    mutate(
      special_teams = as.integer(
        rush == 0 & pass == 0 &
          grepl("Punt|Kickoff|Field Goal|Extra Point|Blocked",
                play_type, ignore.case = TRUE)
      )
    )
}

pull_pbp_data <- function(seasons, use_cache = TRUE, cache_dir = tempdir(),
                          use_live_api = FALSE) {
  require_cfbfastR()
  pbp <- purrr::map_dfr(seasons, function(s) {
    cached(file.path(cache_dir, paste0("pbp_", s, ".rds")), use_cache, {
      if (use_live_api) cfbfastR::cfbd_pbp_data(year = s, epa_wpa = TRUE)
      else              cfbfastR::load_cfb_pbp(seasons = s)
    })
  })
  standardize_pbp_columns(pbp)
}

standardize_game_columns <- function(g) {
  alias_map <- list(
    game_id      = c("game_id", "id"),
    season       = c("season", "year"),
    week         = c("week"),
    season_type  = c("season_type"),
    home_team    = c("home_team", "home"),
    away_team    = c("away_team", "away"),
    home_points  = c("home_points", "home_score"),
    away_points  = c("away_points", "away_score"),
    neutral_site = c("neutral_site", "neutral")
  )
  required <- c("game_id", "season", "week", "home_team", "away_team",
                "home_points", "away_points")
  g <- apply_alias_map(g, alias_map, required, "standardize_game_columns()")
  
  if (!"season_type" %in% names(g)) g$season_type <- "regular"
  if (!"neutral_site" %in% names(g)) {
    warning("Game data has no neutral_site column. All games will be treated ",
            "as home/away, which biases the HFA estimate DOWNWARD and applies ",
            "a spurious home edge to bowl and championship games.",
            call. = FALSE)
    g$neutral_site <- FALSE
  }
  g %>%
    mutate(
      game_id      = as.character(game_id),
      neutral_site = as.logical(neutral_site),
      home_points  = as.numeric(home_points),
      away_points  = as.numeric(away_points)
    )
}

#' Final scores and neutral-site flags.
#'
#' Tries the no-API-key data-repo loader first, then the live API, then falls
#' back to reconstructing scores from play-by-play. The PBP fallback is
#' APPROXIMATE (play-level scores are pre-play, so a walk-off score can be
#' missed) and carries no neutral-site information -- it exists so the
#' pipeline runs, not so you can trust it. Warns loudly.
pull_game_results <- function(seasons, use_cache = TRUE, cache_dir = tempdir(),
                              pbp = NULL) {
  require_cfbfastR()
  out <- tryCatch({
    purrr::map_dfr(seasons, function(s) {
      cached(file.path(cache_dir, paste0("games_", s, ".rds")), use_cache, {
        if ("load_cfb_schedules" %in% getNamespaceExports("cfbfastR")) {
          cfbfastR::load_cfb_schedules(seasons = s)
        } else {
          cfbfastR::cfbd_game_info(year = s)
        }
      })
    }) %>% standardize_game_columns()
  }, error = function(e) {
    warning("Could not pull game results (", conditionMessage(e),
            "). Falling back to PBP-derived scores. These are APPROXIMATE and ",
            "carry no neutral-site flags -- results will be degraded.",
            call. = FALSE)
    NULL
  })
  
  if (!is.null(out)) return(out)
  if (is.null(pbp)) stop("pull_game_results(): no game source and no pbp fallback.")
  
  pbp %>%
    mutate(
      home_pts_at_play = if_else(offense_play == home, offense_score, defense_score),
      away_pts_at_play = if_else(offense_play == home, defense_score, offense_score)
    ) %>%
    group_by(game_id, season, week, season_type, home_team = home, away_team = away) %>%
    summarise(
      home_points = max(home_pts_at_play, na.rm = TRUE),
      away_points = max(away_pts_at_play, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(game_id = as.character(game_id), neutral_site = FALSE)
}

#' Team metadata: division (fbs/fcs/...) and conference. This is where the
#' division filter actually comes from -- load_cfb_pbp() does NOT carry
#' home_team_division / away_team_division, so the old fbs_only filter in
#' aggregate_team_game_epa() silently did nothing.
pull_team_metadata <- function(seasons, use_cache = TRUE, cache_dir = tempdir()) {
  require_cfbfastR()
  cache_file <- file.path(cache_dir, paste0("teams_", max(seasons), ".rds"))
  raw <- tryCatch(
    cached(cache_file, use_cache, {
      if ("load_cfb_teams" %in% getNamespaceExports("cfbfastR")) {
        cfbfastR::load_cfb_teams()
      } else {
        cfbfastR::cfbd_team_info(year = max(seasons), only_fbs = FALSE)
      }
    }),
    error = function(e) {
      warning("Could not pull team metadata (", conditionMessage(e),
              "). Division will be inferred from schedule structure instead.",
              call. = FALSE)
      NULL
    }
  )
  if (is.null(raw)) return(NULL)
  
  alias_map <- list(
    team       = c("school", "team"),
    division   = c("classification", "division", "team_division"),
    conference = c("conference"),
    team_id    = c("team_id", "id")
  )
  raw <- apply_alias_map(raw, alias_map, c("team"), "pull_team_metadata()")
  if (!"division"   %in% names(raw)) raw$division   <- NA_character_
  if (!"conference" %in% names(raw)) raw$conference <- NA_character_
  
  raw %>%
    transmute(team = as.character(team),
              division = tolower(as.character(division)),
              conference = as.character(conference)) %>%
    distinct(team, .keep_all = TRUE)
}

standardize_talent_columns <- function(df) {
  alias_map <- list(
    season  = c("season", "year"),
    team    = c("team", "school"),
    talent  = c("talent", "talent_composite", "composite", "talent_score"),
    team_id = c("team_id", "id", "school_id")
  )
  df <- apply_alias_map(df, alias_map, c("season", "team", "talent"),
                        "standardize_talent_columns()")
  if (!"team_id" %in% names(df)) df$team_id <- NA_character_
  if (!is.numeric(df$talent)) df$talent <- suppressWarnings(as.numeric(df$talent))
  df %>% mutate(team = as.character(team), team_id = as.character(team_id))
}

pull_talent_data <- function(seasons, use_cache = TRUE, cache_dir = tempdir()) {
  require_cfbfastR()
  cache_file <- file.path(cache_dir,
                          paste0("talent_", min(seasons), "_", max(seasons), ".rds"))
  # Standardization runs on every path, including cache hits -- applying it
  # only on fresh pulls meant a stale cache replayed un-canonicalized columns
  # forever.
  standardize_talent_columns(
    cached(cache_file, use_cache, cfbfastR::load_cfb_team_talent(seasons = seasons))
  )
}

#' Reconcile talent-table team names to rating-table team names.
#'
#' The talent endpoint returns "School Mascot"; PBP and schedules return
#' school only. Prefix matching alone is unsafe -- "Colorado Mesa Mavericks"
#' has "Colorado" as a prefix -- so this resolves by team_id when available
#' and only falls back to longest-prefix matching otherwise. Crucially, a
#' rating-table team may only be claimed ONCE; a second claimant is dropped
#' rather than silently overwriting.
resolve_talent_teams <- function(talent_season, rating_teams,
                                 team_id_lookup = NULL) {
  by_id <- tibble(team = character(0), talent = double(0))
  unresolved <- talent_season
  
  if (!is.null(team_id_lookup) && nrow(team_id_lookup) > 0 &&
      any(!is.na(talent_season$team_id))) {
    lk <- team_id_lookup %>%
      mutate(team_id = as.character(team_id)) %>%
      distinct(team_id, .keep_all = TRUE) %>%
      rename(team_resolved = team)
    by_id <- talent_season %>%
      filter(!is.na(team_id)) %>%
      inner_join(lk, by = "team_id") %>%
      transmute(team = team_resolved, talent)
    unresolved <- talent_season %>% filter(!(team %in% by_id$team))
  }
  
  claimed <- by_id$team
  matched <- rep(NA_character_, nrow(unresolved))
  if (nrow(unresolved) > 0) {
    nm <- unresolved$team
    exact <- nm %in% rating_teams
    matched[exact] <- nm[exact]
    for (i in which(!exact)) {
      cand <- rating_teams[startsWith(nm[i], rating_teams)]
      if (length(cand) > 0) matched[i] <- cand[which.max(nchar(cand))]
    }
  }
  by_name <- unresolved %>%
    mutate(team = matched) %>%
    filter(!is.na(team), !(team %in% claimed)) %>%
    # Longest source name wins a contested rating-table slot: given both
    # "Colorado Buffaloes" and "Colorado Mesa Mavericks" mapping to
    # "Colorado", neither is safe, so require an exact-length-ish match and
    # keep the first only after ordering by descending match quality.
    mutate(match_len = nchar(team)) %>%
    arrange(desc(match_len)) %>%
    distinct(team, .keep_all = TRUE) %>%
    select(team, talent)
  
  unmatched <- setdiff(rating_teams, c(by_id$team, by_name$team))
  if (length(unmatched) > 0) {
    message("resolve_talent_teams(): ", length(unmatched),
            " rated team(s) have no talent record and will use a ",
            "carryover-only preseason prior: ",
            paste(utils::head(unmatched, 8), collapse = ", "),
            if (length(unmatched) > 8) ", ..." else "")
  }
  bind_rows(by_id, by_name) %>% distinct(team, .keep_all = TRUE)
}

# -----------------------------------------------------------------------------
# 3. BUILD TEAM-GAME UNITS
# -----------------------------------------------------------------------------

#' Garbage time, score-and-time dependent. Used ONLY for the EPA-rate
#' diagnostics, never for the points response (see config comments).
flag_garbage_time <- function(pbp, gt) {
  pbp %>%
    mutate(
      score_diff_abs = abs(offense_score - defense_score),
      gt_threshold = case_when(
        period == 1 ~ gt$q1_margin,
        period == 2 ~ gt$q2_margin,
        period == 3 ~ gt$q3_margin,
        period == 4 ~ gt$q4_margin,
        TRUE        ~ Inf          # no garbage time in overtime
      ),
      is_garbage_time = score_diff_abs > gt_threshold
    )
}

#' One row per (game, team) with everything the model and the diagnostics need.
#'
#' Returns columns:
#'   game_id, season, week, time_index, team, opponent, division, opponent_division,
#'   is_home, neutral, hfa_x, points_for, points_against,
#'   epa_total (offense scrimmage + optional ST), off_plays,
#'   off_epa_play, def_epa_play_allowed, rush/pass rates and counts
build_team_game_units <- function(pbp, games, team_meta = NULL,
                                  cfg = default_config()) {
  
  gt <- cfg$response$garbage_time
  scrim <- pbp %>% filter(!is.na(EPA), rush == 1 | pass == 1) %>% flag_garbage_time(gt)
  st    <- pbp %>% filter(!is.na(EPA), special_teams == 1)
  
  # --- EPA totals: unfiltered, because points scored are unfiltered and the
  #     two response components must measure the same thing.
  epa_tot <- scrim %>%
    group_by(game_id = as.character(game_id), team = offense_play) %>%
    summarise(scrim_epa = sum(EPA), off_plays = n(), .groups = "drop")
  
  st_tot <- if (isTRUE(cfg$response$include_special_teams) && nrow(st) > 0) {
    # ST EPA is credited to the team listed on offense for the play (the
    # punting / kicking / field-goal team). APPROXIMATION: cfbfastR's ST
    # possession conventions are not perfectly uniform. Toggle off in config
    # if your schema disagrees; validation will tell you which is better.
    st %>%
      group_by(game_id = as.character(game_id), team = offense_play) %>%
      summarise(st_epa = sum(EPA), st_plays = n(), .groups = "drop")
  } else {
    tibble(game_id = character(0), team = character(0),
           st_epa = double(0), st_plays = integer(0))
  }
  
  # --- garbage-time-filtered per-play rates, for diagnostics only
  rates <- scrim %>%
    filter(!(isTRUE(gt$exclude) & is_garbage_time)) %>%
    group_by(game_id = as.character(game_id), team = offense_play) %>%
    summarise(
      off_epa_play      = mean(EPA),
      off_epa_rush      = if (any(rush == 1)) mean(EPA[rush == 1]) else NA_real_,
      off_epa_pass      = if (any(pass == 1)) mean(EPA[pass == 1]) else NA_real_,
      off_plays_clean   = n(),
      off_rush_plays    = sum(rush == 1),
      off_pass_plays    = sum(pass == 1),
      off_success_rate  = mean(EPA > 0),
      .groups = "drop"
    )
  
  # --- skeleton: two rows per game
  g <- games %>%
    mutate(game_id = as.character(game_id),
           neutral = coalesce(neutral_site, FALSE)) %>%
    filter(!is.na(home_points), !is.na(away_points))
  
  home_rows <- g %>% transmute(
    game_id, season, week, season_type, neutral,
    team = home_team, opponent = away_team,
    points_for = home_points, points_against = away_points,
    is_home = !neutral
  )
  away_rows <- g %>% transmute(
    game_id, season, week, season_type, neutral,
    team = away_team, opponent = home_team,
    points_for = away_points, points_against = home_points,
    is_home = FALSE
  )
  
  tg <- bind_rows(home_rows, away_rows) %>%
    mutate(
      # +0.5 / -0.5 / 0 coding. The HFA coefficient then reads directly as
      # total points of home advantage in the margin, applied exactly once,
      # and the column sums to zero within every game so it cannot become
      # collinear with the intercept.
      hfa_x = case_when(neutral ~ 0, is_home ~ 0.5, TRUE ~ -0.5),
      time_index = week + 100L * as.integer(!grepl("^reg", tolower(season_type)))
    ) %>%
    left_join(epa_tot, by = c("game_id", "team")) %>%
    left_join(st_tot,  by = c("game_id", "team")) %>%
    left_join(rates,   by = c("game_id", "team"))
  
  # Defensive rates = what this team's opponent produced in this game.
  opp_rates <- rates %>%
    select(game_id, opponent = team,
           def_epa_play_allowed = off_epa_play,
           def_epa_rush_allowed = off_epa_rush,
           def_epa_pass_allowed = off_epa_pass,
           def_plays_clean      = off_plays_clean,
           def_rush_plays       = off_rush_plays,
           def_pass_plays       = off_pass_plays)
  tg <- left_join(tg, opp_rates, by = c("game_id", "opponent"))
  
  tg <- tg %>%
    mutate(
      scrim_epa = coalesce(scrim_epa, 0),
      st_epa    = coalesce(st_epa, 0),
      epa_total = scrim_epa + st_epa,
      off_plays = coalesce(off_plays, 0L)
    )
  
  # Division. Falls back to "unknown" -> treated as FBS if metadata is
  # unavailable, with a warning, because silently dropping every team is worse.
  if (!is.null(team_meta)) {
    tg <- tg %>%
      left_join(select(team_meta, team, division, conference), by = "team") %>%
      left_join(select(team_meta, opponent = team, opponent_division = division),
                by = "opponent") %>%
      mutate(division = coalesce(division, "unknown"),
             opponent_division = coalesce(opponent_division, "unknown"))
  } else {
    warning("No team metadata: cannot distinguish FBS from FCS. All teams ",
            "will be treated as FBS, which will distort centering and SOS.",
            call. = FALSE)
    tg <- tg %>% mutate(division = "unknown", opponent_division = "unknown",
                        conference = NA_character_)
  }
  
  # Drop games where a team has no play-by-play at all AND we are leaning on
  # the EPA component; the points component alone is still usable, so keep
  # the row but flag it.
  tg %>%
    mutate(has_epa = off_plays > 0) %>%
    arrange(season, time_index, game_id, desc(is_home))
}

# -----------------------------------------------------------------------------
# 4. RESPONSE CONSTRUCTION
# -----------------------------------------------------------------------------

#' Build the modeled response in POINTS.
#'
#' pts_epa = baseline + epa_total, where baseline is set so that mean(pts_epa)
#' equals mean(points_for) over the TRAINING rows only. This is not an
#' invented conversion factor: EPA is Expected Points Added, already
#' denominated in points, so the slope of points_for on epa_total should be
#' near 1. epa_points_slope() reports the realized slope so you can check.
#'
#' The blended response is then capped at the game-margin level, symmetrically,
#' so total game points are preserved and only the margin is compressed.
build_response <- function(tg, train_idx, cfg = default_config()) {
  w   <- cfg$response$w_epa
  cap <- cfg$response$margin_cap
  
  tr <- tg[train_idx, , drop = FALSE]
  baseline <- mean(tr$points_for, na.rm = TRUE) - mean(tr$epa_total, na.rm = TRUE)
  
  tg$pts_epa <- baseline + tg$epa_total
  tg$pts_epa[!tg$has_epa] <- tg$points_for[!tg$has_epa]  # no PBP -> use actual
  tg$y_raw <- w * tg$pts_epa + (1 - w) * tg$points_for
  
  if (is.finite(cap)) {
    # Pair rows within each game and compress the implied margin.
    key <- paste(tg$game_id, tg$team)
    opp_key <- paste(tg$game_id, tg$opponent)
    j <- match(opp_key, key)
    y_opp <- tg$y_raw[j]
    m <- tg$y_raw - y_opp
    adj <- ifelse(!is.na(m) & abs(m) > cap, (sign(m) * cap - m) / 2, 0)
    tg$y <- tg$y_raw + adj
  } else {
    tg$y <- tg$y_raw
  }
  attr(tg, "epa_baseline") <- baseline
  tg
}

#' Diagnostic: regress actual points scored on total EPA. Slope should be
#' close to 1 if EPA is behaving as points. Report it; do not force it.
epa_points_slope <- function(tg) {
  d <- tg %>% filter(has_epa, !is.na(points_for))
  if (nrow(d) < 50) return(NA_real_)
  unname(coef(stats::lm(points_for ~ epa_total, data = d))[2])
}

# -----------------------------------------------------------------------------
# 5. PRESEASON PRIOR
# -----------------------------------------------------------------------------

#' Preseason expected rating, in points vs average FBS, neutral field.
#'
#' prior_i = a + carryover * prior_season_rating_i + talent_beta * talent_z_i
#'
#' Coefficients are fit on strictly EARLIER seasons when at least two seasons
#' of history are available; otherwise the documented fallbacks are used. This
#' is the only place recruiting information enters the model, and recruiting
#' composites are published before the season starts, so there is no leakage.
build_preseason_prior <- function(target_season, history_ratings, talent_data,
                                  rating_teams, team_id_lookup = NULL,
                                  cfg = default_config()) {
  
  n_teams <- length(rating_teams)
  out <- tibble(team = rating_teams, prior_rating = 0, prior_source = "flat")
  if (!isTRUE(cfg$prior$enabled)) return(out)
  
  # --- talent, z-scored within the target season across FBS teams
  talent_tbl <- tibble(team = character(0), talent_z = double(0))
  if (!is.null(talent_data)) {
    ts <- talent_data %>% filter(season == target_season)
    if (nrow(ts) > 0) {
      res <- resolve_talent_teams(ts, rating_teams, team_id_lookup)
      if (nrow(res) > 0) {
        mu <- mean(res$talent, na.rm = TRUE); sdv <- stats::sd(res$talent, na.rm = TRUE)
        if (is.finite(sdv) && sdv > 0) {
          talent_tbl <- res %>% transmute(team, talent_z = (talent - mu) / sdv)
        }
      }
    }
  }
  
  prev <- if (!is.null(history_ratings) && nrow(history_ratings) > 0) {
    history_ratings %>%
      filter(season == target_season - 1L) %>%
      select(team, prev_rating = power_rating)
  } else tibble(team = character(0), prev_rating = double(0))
  
  carry <- cfg$prior$fallback_carryover
  tbeta <- cfg$prior$fallback_talent_beta
  intercept <- 0
  
  # Estimate carryover / talent_beta from history when we have at least two
  # consecutive prior seasons. Uses only seasons strictly before target_season.
  if (isTRUE(cfg$prior$fit_from_history) && !is.null(history_ratings)) {
    hist_seasons <- sort(unique(history_ratings$season))
    fitset <- history_ratings %>%
      filter(season < target_season) %>%
      select(season, team, power_rating) %>%
      inner_join(
        history_ratings %>%
          filter(season < target_season) %>%
          transmute(season = season + 1L, team, prev_rating = power_rating),
        by = c("season", "team")
      )
    if (!is.null(talent_data)) {
      tz <- talent_data %>%
        group_by(season) %>%
        mutate(talent_z = as.numeric(scale(talent))) %>%
        ungroup() %>%
        select(season, talent_team = team, talent_z)
      # crude name join for the historical fit only; failures fall through
      fitset <- fitset %>%
        left_join(tz, by = c("season" = "season", "team" = "talent_team"))
    }
    if (nrow(fitset) >= 100) {
      fml <- if ("talent_z" %in% names(fitset) && sum(!is.na(fitset$talent_z)) > 50) {
        power_rating ~ prev_rating + talent_z
      } else power_rating ~ prev_rating
      m <- try(stats::lm(fml, data = fitset), silent = TRUE)
      if (!inherits(m, "try-error")) {
        cf <- coef(m)
        intercept <- unname(cf[1])
        carry <- unname(cf["prev_rating"])
        if ("talent_z" %in% names(cf) && !is.na(cf["talent_z"])) tbeta <- unname(cf["talent_z"])
        message(sprintf("Preseason prior fit on seasons < %d: carryover=%.2f, talent_beta=%.2f",
                        target_season, carry, tbeta))
      }
    }
  }
  
  out <- tibble(team = rating_teams) %>%
    left_join(prev, by = "team") %>%
    left_join(talent_tbl, by = "team") %>%
    mutate(
      has_prev = !is.na(prev_rating),
      has_tal  = !is.na(talent_z),
      prev_rating = coalesce(prev_rating, 0),
      talent_z    = coalesce(talent_z, 0),
      prior_rating = intercept + carry * prev_rating + tbeta * talent_z,
      prior_source = case_when(
        has_prev & has_tal ~ "carryover+talent",
        has_prev           ~ "carryover",
        has_tal            ~ "talent",
        TRUE               ~ "flat"
      )
    ) %>%
    select(team, prior_rating, prior_source)
  
  out
}

# -----------------------------------------------------------------------------
# 6. THE MODEL
# -----------------------------------------------------------------------------

#' Penalized least squares on team-game points scored.
#'
#'   y_it = mu + alpha_i + beta_j + gamma * hfa_x_it + e
#'
#' where i is the team scoring, j the opponent conceding, alpha is offensive
#' strength in points, beta is points allowed by the opponent's defense, and
#' gamma is home-field advantage in points (applied once per game because
#' hfa_x is +0.5 / -0.5).
#'
#' Objective:
#'   sum_it w_it (y_it - x_it'theta)^2 + sum_i lambda_i [ (alpha_i - p_i)^2
#'                                                     + (beta_i  + p_i)^2 ]
#'
#' mu and gamma are UNPENALIZED. p_i is the team's preseason prior split
#' evenly between offense and defense.
#'
#' Note the two identities that make this a legitimate point-spread model:
#'   E[margin | A vs B, neutral] = (alpha_A - beta_A) - (alpha_B - beta_B)
#'   E[margin | A home]          = same + gamma
#' so power_rating_i := alpha_i - beta_i (after centering) IS the expected
#' margin against an average FBS team on a neutral field.
fit_points_model <- function(tg, prior, cfg = default_config(),
                             lambda = NULL, fbs_teams = NULL) {
  
  lambda <- lambda %||% cfg$fit$lambda %||% 32
  
  teams <- sort(unique(c(tg$team, tg$opponent)))
  nT <- length(teams); n <- nrow(tg); p <- 2L * nT + 2L
  ti <- match(tg$team, teams); oi <- match(tg$opponent, teams)
  
  X <- matrix(0, n, p)
  X[, 1] <- 1
  X[cbind(seq_len(n), 1L + ti)]      <- 1     # offense of scoring team
  X[cbind(seq_len(n), 1L + nT + oi)] <- 1     # defense of conceding team
  X[, p] <- tg$hfa_x
  
  # ---- observation weights
  w <- rep(1, n)
  if (!is.null(fbs_teams)) {
    is_fcs_game <- !(tg$team %in% fbs_teams) | !(tg$opponent %in% fbs_teams)
    w[is_fcs_game] <- w[is_fcs_game] * cfg$fit$fcs_game_weight
  }
  hl <- cfg$fit$recency_halflife_weeks
  if (is.finite(hl) && hl > 0) {
    age <- max(tg$time_index) - tg$time_index
    w <- w * 0.5 ^ (age / hl)
  }
  
  # ---- penalty and prior target
  pr <- tibble(team = teams) %>%
    left_join(prior, by = "team") %>%
    mutate(prior_rating = coalesce(prior_rating, 0))
  is_fbs <- if (is.null(fbs_teams)) rep(TRUE, nT) else teams %in% fbs_teams
  
  lam_team <- ifelse(is_fbs, lambda, lambda * cfg$fit$fcs_lambda_multiplier)
  pr_vec <- pr$prior_rating
  pr_vec[!is_fbs & pr$prior_rating == 0] <- cfg$fit$fcs_prior_rating
  
  share <- cfg$prior$offense_share
  dvec <- c(0, lam_team, lam_team, 0)
  mvec <- c(0,
            share * pr_vec,             # alpha target
            -(1 - share) * pr_vec,      # beta target (negative: good = low)
            0)
  
  A <- crossprod(X * sqrt(w)) + diag(dvec, p, p)
  b <- crossprod(X, w * tg$y) + dvec * mvec
  Ainv <- tryCatch(solve(A), error = function(e)
    stop("fit_points_model(): penalized normal equations are singular. ",
         "Raise lambda or check for an empty training set."))
  theta <- as.numeric(Ainv %*% b)
  
  fitted <- as.numeric(X %*% theta)
  resid  <- tg$y - fitted
  
  intercept <- theta[1]
  alpha <- theta[2:(nT + 1)]
  beta  <- theta[(nT + 2):(2 * nT + 1)]
  gamma <- theta[p]
  
  # ---- centering: 0 = average FBS team, by construction.
  # The model is invariant to alpha_i -> alpha_i + c, beta_i -> beta_i - c
  # (predictions unchanged), so choosing c is choosing a free parameter, not
  # manipulating the fit. We choose it so the FBS means are zero.
  a_bar <- mean(alpha[is_fbs]); b_bar <- mean(beta[is_fbs])
  alpha_c <- alpha - a_bar
  beta_c  <- beta  - b_bar
  intercept_c <- intercept + a_bar + b_bar
  
  # ---- cluster-robust variance, clustered on game (the two rows of a game
  # share conditions, so naive SEs are optimistic).
  U <- (X * (w * resid))
  gid <- tg$game_id
  Ug <- rowsum(U, gid)
  V <- Ainv %*% crossprod(Ug) %*% Ainv
  
  # SE of the contrast alpha_i - beta_i
  rating_se <- vapply(seq_len(nT), function(i) {
    io <- 1L + i; id <- 1L + nT + i
    v <- V[io, io] + V[id, id] - 2 * V[io, id]
    sqrt(max(v, 0))
  }, numeric(1))
  
  # ---- approximate share of each rating driven by the prior rather than the
  # data: diagonal of Ainv %*% D. 1 = fully prior-driven, 0 = fully data-driven.
  AD <- Ainv %*% diag(dvec, p, p)
  prior_weight <- vapply(seq_len(nT), function(i)
    0.5 * (AD[1L + i, 1L + i] + AD[1L + nT + i, 1L + nT + i]), numeric(1))
  
  list(
    teams = teams,
    intercept = intercept_c,
    offensive_rating = alpha_c,
    defensive_rating = -beta_c,   # sign-flipped so POSITIVE = good defense
    power_rating = alpha_c - beta_c,
    rating_se = rating_se,
    prior_weight = pmin(pmax(prior_weight, 0), 1),
    hfa = gamma,
    lambda = lambda,
    is_fbs = is_fbs,
    sigma = sqrt(sum(w * resid^2) / max(sum(w) - p, 1)),
    n_obs = n
  )
}

#' Opponent-adjusted EPA-per-play ratings. Same joint-estimation structure,
#' but the response is EPA/play and the units are EPA/PLAY, NOT POINTS.
#' Exposed as diagnostics only; never mixed into power_rating.
fit_epa_rate_model <- function(tg, response = c("overall", "rush", "pass"),
                               lambda = 5) {
  response <- match.arg(response)
  ycol <- switch(response, overall = "off_epa_play",
                 rush = "off_epa_rush", pass = "off_epa_pass")
  wcol <- switch(response, overall = "off_plays_clean",
                 rush = "off_rush_plays", pass = "off_pass_plays")
  
  d <- tg %>% filter(!is.na(.data[[ycol]]), .data[[wcol]] > 0)
  if (nrow(d) < 20) {
    return(tibble(team = sort(unique(c(tg$team, tg$opponent))),
                  off = NA_real_, def = NA_real_))
  }
  teams <- sort(unique(c(d$team, d$opponent)))
  nT <- length(teams); n <- nrow(d); p <- 2L * nT + 2L
  ti <- match(d$team, teams); oi <- match(d$opponent, teams)
  
  X <- matrix(0, n, p); X[, 1] <- 1
  X[cbind(seq_len(n), 1L + ti)] <- 1
  X[cbind(seq_len(n), 1L + nT + oi)] <- 1
  X[, p] <- d$hfa_x
  w <- d[[wcol]]
  
  dvec <- c(0, rep(lambda, 2 * nT), 0)
  A <- crossprod(X * sqrt(w)) + diag(dvec, p, p)
  theta <- as.numeric(solve(A, crossprod(X, w * d[[ycol]])))
  
  a <- theta[2:(nT + 1)]; b <- theta[(nT + 2):(2 * nT + 1)]
  tibble(team = teams, off = a - mean(a), def = -(b - mean(b)))
}

# -----------------------------------------------------------------------------
# 7. LAMBDA SELECTION (WALK-FORWARD, NOT RANDOM K-FOLD)
# -----------------------------------------------------------------------------

#' Random k-fold CV on team-game rows leaks future information into past
#' predictions and, worse, puts the two rows of the SAME game in different
#' folds. Lambda is selected here by expanding-window walk-forward on out-of-
#' sample game margin MAE.
select_lambda_walkforward <- function(tg_season, prior, cfg = default_config(),
                                      fbs_teams = NULL, grid = NULL) {
  grid <- grid %||% cfg$fit$lambda_grid
  weeks <- sort(unique(tg_season$time_index))
  cut_weeks <- weeks[weeks >= cfg$validation$first_predicted_week]
  cut_weeks <- cut_weeks[-length(cut_weeks)]
  if (length(cut_weeks) < 2) {
    message("Not enough weeks for walk-forward lambda selection; using median of grid.")
    return(stats::median(grid))
  }
  
  score <- vapply(grid, function(lam) {
    errs <- c()
    for (k in cut_weeks) {
      train <- tg_season %>% filter(time_index <= k)
      test  <- tg_season %>% filter(time_index == min(weeks[weeks > k]))
      if (nrow(test) == 0 || n_distinct(train$team) < 20) next
      train <- build_response(train, seq_len(nrow(train)), cfg)
      fit <- try(fit_points_model(train, prior, cfg, lambda = lam,
                                  fbs_teams = fbs_teams), silent = TRUE)
      if (inherits(fit, "try-error")) next
      pr <- setNames(fit$power_rating, fit$teams)
      te <- test %>%
        filter(is_home | neutral) %>%
        distinct(game_id, .keep_all = TRUE) %>%
        mutate(
          pred = coalesce(pr[team], NA_real_) - coalesce(pr[opponent], NA_real_) +
            if_else(neutral, 0, fit$hfa),
          act = points_for - points_against
        ) %>% filter(!is.na(pred))
      if (nrow(te) > 0) errs <- c(errs, abs(te$pred - te$act))
    }
    if (length(errs) == 0) NA_real_ else mean(errs)
  }, numeric(1))
  
  if (all(is.na(score))) return(stats::median(grid))
  best <- grid[which.min(score)]
  message(sprintf("Walk-forward lambda selection: best lambda = %s (OOS MAE %.2f)",
                  best, min(score, na.rm = TRUE)))
  attr(best, "grid_scores") <- setNames(score, grid)
  best
}

# -----------------------------------------------------------------------------
# 8. ORCHESTRATION
# -----------------------------------------------------------------------------

#' Fit ratings for every season present, producing a clean points-scale table.
#'
#' Seasons are fit independently (a season's schedule is a closed graph), but
#' each season's PRIOR uses the previous season's fitted rating, so information
#' flows forward without pooling rosters across years.
#' Canonical, single source of truth for "which rated teams are FBS."
#'
#' compute_ratings() and walk_forward_validate() both need this, and having
#' two independent implementations is exactly how they drifted apart: one
#' silently fell back to "no metadata -> treat everyone as FBS" while the
#' other didn't, so walk_forward_validate()'s FCS filter could end up
#' excluding every single game with no visible error. Both now call this.
#'
#' Falls back to treating every rated team as FBS -- but WARNS loudly, with
#' the actual division values seen, rather than failing silently. If you see
#' this warning, `pull_team_metadata()`'s alias_map doesn't match your
#' cfbfastR schema and FCS shrinkage / fbs_only filtering is not happening.
resolve_fbs_teams <- function(team_meta, rating_teams) {
  if (is.null(team_meta)) {
    warning("No team metadata: cannot distinguish FBS from FCS. Treating ",
            "every rated team as FBS (disables FCS shrinkage and the ",
            "fbs_only ranking filter).", call. = FALSE)
    return(rating_teams)
  }
  fbs_all <- team_meta$team[!is.na(team_meta$division) & team_meta$division == "fbs"]
  if (length(fbs_all) == 0) {
    seen <- utils::head(sort(unique(team_meta$division)), 10)
    warning("team_meta$division has no value matching \"fbs\" (values seen: ",
            paste(seen, collapse = ", "), "). Treating every rated team as ",
            "FBS. Check pull_team_metadata()'s alias_map against your ",
            "cfbfastR schema -- run table(team_meta$division) to see the ",
            "real values and add the correct one.", call. = FALSE)
    return(rating_teams)
  }
  intersect(fbs_all, rating_teams)
}

compute_ratings <- function(tg, talent_data = NULL, cfg = default_config(),
                            team_meta = NULL) {
  
  seasons <- sort(unique(tg$season))
  history <- NULL
  out <- list(); meta <- list()
  
  for (s in seasons) {
    tgs <- tg %>% filter(season == s)
    rating_teams <- sort(unique(c(tgs$team, tgs$opponent)))
    fbs_teams <- resolve_fbs_teams(team_meta, rating_teams)
    
    prior <- build_preseason_prior(
      target_season = s, history_ratings = history, talent_data = talent_data,
      rating_teams = rating_teams, team_id_lookup = NULL, cfg = cfg
    )
    
    lam <- cfg$fit$lambda %||%
      select_lambda_walkforward(tgs, prior, cfg, fbs_teams = fbs_teams)
    
    tgs_full <- build_response(tgs, seq_len(nrow(tgs)), cfg)
    fit <- fit_points_model(tgs_full, prior, cfg, lambda = lam, fbs_teams = fbs_teams)
    
    pr <- setNames(fit$power_rating, fit$teams)
    
    # --- schedule diagnostics. These are REPORTING quantities. The opponent
    # adjustment already happened inside the regression; nothing here is
    # subtracted from power_rating.
    sched <- tgs_full %>%
      mutate(opp_rating = coalesce(pr[opponent], NA_real_),
             margin = points_for - points_against) %>%
      group_by(team) %>%
      summarise(
        games_played        = n(),
        raw_margin_pg       = mean(margin),
        avg_opponent_rating = mean(opp_rating, na.rm = TRUE),
        n_fcs_opponents     = sum(!(opponent %in% fbs_teams)),
        n_distinct_opps     = n_distinct(opponent),
        .groups = "drop"
      ) %>%
      # SOS in points, HIGHER = HARDER: the average expected margin for an
      # AVERAGE FBS team (rating 0) if it were dropped into this team's exact
      # schedule, on the actual home/away split. Playing a strong opponent on
      # the road is harder than at home, so hfa_term nets that out per game
      # before averaging.
      #   opp_rating - hfa_term  =  strength of that one game, from the
      #                             perspective of "how hard is this to win"
      # NOTE: an earlier version of this line had a stray leading "-", which
      # inverted the sign (harder schedule produced a MORE NEGATIVE number).
      # The regression itself was never affected -- this field is reporting
      # only -- but it made the "adjustment increases with difficulty" sanity
    # check fail, and read backwards anywhere it was displayed or plotted.
    left_join(
      tgs_full %>%
        mutate(opp_rating = coalesce(pr[opponent], NA_real_),
               hfa_term = if_else(neutral, 0, if_else(is_home, 1, -1)) * fit$hfa) %>%
        group_by(team) %>%
        summarise(strength_of_schedule = mean(opp_rating - hfa_term, na.rm = TRUE),
                  .groups = "drop"),
      by = "team"
    )
    
    epa_all  <- fit_epa_rate_model(tgs_full, "overall")
    epa_rush <- fit_epa_rate_model(tgs_full, "rush")
    epa_pass <- fit_epa_rate_model(tgs_full, "pass")
    
    ratings <- tibble(
      season = s,
      team = fit$teams,
      power_rating = fit$power_rating,
      offensive_rating = fit$offensive_rating,
      defensive_rating = fit$defensive_rating,
      rating_se = fit$rating_se,
      prior_weight = fit$prior_weight,
      is_fbs = fit$is_fbs
    ) %>%
      left_join(sched, by = "team") %>%
      left_join(prior, by = "team") %>%
      left_join(rename(epa_all,  off_epa_rating = off, def_epa_rating = def), by = "team") %>%
      left_join(rename(epa_rush, rush_off_epa   = off, rush_def_epa   = def), by = "team") %>%
      left_join(rename(epa_pass, pass_off_epa   = off, pass_def_epa   = def), by = "team") %>%
      mutate(
        games_played = coalesce(games_played, 0L),
        # The single most useful diagnostic in the table: how much the joint
        # opponent adjustment moved this team off its raw scoring margin.
        # Should be strongly negatively correlated with opponent quality.
        schedule_adjustment = power_rating - raw_margin_pg
      ) %>%
      filter(games_played > 0) %>%
      arrange(desc(power_rating))
    
    if (!is.null(team_meta)) {
      ratings <- left_join(ratings, select(team_meta, team, conference), by = "team")
    }
    
    out[[as.character(s)]] <- ratings
    meta[[as.character(s)]] <- list(hfa = fit$hfa, lambda = fit$lambda,
                                    sigma = fit$sigma, intercept = fit$intercept,
                                    epa_points_slope = epa_points_slope(tgs_full))
    history <- bind_rows(history, select(ratings, season, team, power_rating))
  }
  
  all_ratings <- bind_rows(out) %>%
    select(season, team, any_of("conference"), power_rating, offensive_rating,
           defensive_rating, rating_se, games_played, strength_of_schedule,
           avg_opponent_rating, raw_margin_pg, schedule_adjustment,
           n_fcs_opponents, n_distinct_opps, prior_rating, prior_source,
           prior_weight, is_fbs, off_epa_rating, def_epa_rating,
           rush_off_epa, rush_def_epa, pass_off_epa, pass_def_epa) %>%
    arrange(season, desc(power_rating))
  
  attr(all_ratings, "hfa_by_season")    <- purrr::map_dbl(meta, "hfa")
  attr(all_ratings, "lambda_by_season") <- purrr::map_dbl(meta, "lambda")
  attr(all_ratings, "sigma_by_season")  <- purrr::map_dbl(meta, "sigma")
  attr(all_ratings, "epa_points_slope") <- purrr::map_dbl(meta, "epa_points_slope")
  all_ratings
}

rank_teams <- function(ratings, n = 25, season = NULL, fbs_only = TRUE) {
  df <- ratings
  if (!is.null(season)) df <- df %>% filter(.data$season == !!season)
  if (fbs_only) df <- df %>% filter(is_fbs)
  df %>%
    group_by(season) %>%
    arrange(desc(power_rating), .by_group = TRUE) %>%
    mutate(rank = row_number()) %>%
    ungroup() %>%
    filter(rank <= n) %>%
    select(rank, season, team, power_rating, offensive_rating, defensive_rating,
           strength_of_schedule, raw_margin_pg, schedule_adjustment,
           games_played, rating_se, everything())
}

# -----------------------------------------------------------------------------
# 9. GAME PREDICTION
# -----------------------------------------------------------------------------

#' Expected point spread between two teams.
#'
#' predict_game(ratings, home_team = "Ohio State", away_team = "Michigan")
#' predict_game(ratings, home_team = NULL, away_team = "Michigan", team = "Ohio State")
#'   -> neutral site
predict_game <- function(ratings, home_team = NULL, away_team = NULL,
                         team = NULL, season = NULL, hfa = NULL, quiet = FALSE) {
  
  season <- season %||% max(ratings$season)
  r <- ratings %>% filter(.data$season == !!season)
  hfa <- hfa %||% unname(attr(ratings, "hfa_by_season")[as.character(season)]) %||% 2.5
  
  get_r <- function(tm) {
    row <- r %>% filter(team == tm)
    if (nrow(row) == 0) stop("Team not found in ratings for season ", season, ": ", tm)
    row$power_rating[1]
  }
  
  neutral <- is.null(home_team)
  a <- if (neutral) (team %||% stop("Neutral site: supply `team` and `away_team`.")) else home_team
  b <- away_team
  ra <- get_r(a); rb <- get_r(b)
  
  margin <- ra - rb + if (neutral) 0 else hfa
  fav <- if (margin >= 0) a else b
  
  res <- list(team_a = a, team_b = b, neutral = neutral,
              rating_a = ra, rating_b = rb,
              hfa_applied = if (neutral) 0 else hfa,
              projected_margin = margin,
              favorite = fav, spread = -abs(margin), season = season)
  
  if (!quiet) {
    cat(sprintf("%-22s %s\n", if (neutral) "Team A (neutral):" else "Home Team:", a))
    cat(sprintf("%-22s %s\n", if (neutral) "Team B (neutral):" else "Away Team:", b))
    cat(sprintf("%-22s %+.1f\n", paste0(a, " rating:"), ra))
    cat(sprintf("%-22s %+.1f\n", paste0(b, " rating:"), rb))
    cat(sprintf("%-22s %+.1f\n", "Home field advantage:", res$hfa_applied))
    cat(sprintf("%-22s %s %.1f\n", "Projected spread:", fav, res$spread))
  }
  invisible(res)
}

# -----------------------------------------------------------------------------
# 10. WALK-FORWARD VALIDATION
# -----------------------------------------------------------------------------

#' Expanding-window out-of-sample validation.
#'
#' For each week k >= first_predicted_week: fit on time_index <= k using ONLY
#' the preseason prior (built from strictly earlier seasons) plus games already
#' played, then predict week k+1. No full-season rating, no full-season SOS,
#' and no future-informed scaling ever touches a prediction.
walk_forward_validate <- function(tg, talent_data = NULL, cfg = default_config(),
                                  team_meta = NULL, model = "full") {
  
  seasons <- sort(unique(tg$season))
  history <- NULL
  results <- list()
  
  # Build history of completed prior seasons so priors are available.
  base_ratings <- compute_ratings(tg, talent_data, cfg, team_meta)
  
  for (s in seasons) {
    tgs <- tg %>% filter(season == s)
    rating_teams <- sort(unique(c(tgs$team, tgs$opponent)))
    fbs_teams <- resolve_fbs_teams(team_meta, rating_teams)
    
    hist_s <- base_ratings %>% filter(season < s) %>% select(season, team, power_rating)
    prior <- build_preseason_prior(s, hist_s, talent_data, rating_teams, NULL, cfg)
    
    if (model == "talent_only") {
      prior_only <- setNames(prior$prior_rating, prior$team)
    }
    
    weeks <- sort(unique(tgs$time_index))
    cut_weeks <- weeks[weeks >= cfg$validation$first_predicted_week]
    cut_weeks <- cut_weeks[-length(cut_weeks)]
    
    for (k in cut_weeks) {
      nxt <- min(weeks[weeks > k])
      train <- tgs %>% filter(time_index <= k)
      test  <- tgs %>% filter(time_index == nxt)
      if (nrow(test) == 0) next
      
      if (model == "talent_only") {
        pr <- prior_only; hfa_k <- 2.5; se <- setNames(rep(NA, length(pr)), names(pr))
        sos_k <- setNames(rep(NA_real_, length(pr)), names(pr))
        gp <- train %>% count(team, name = "n")
        gp_v <- setNames(gp$n, gp$team)
      } else {
        cfg_k <- cfg
        if (model == "no_prior")    cfg_k$prior$enabled <- FALSE
        if (model == "epa_only")    cfg_k$response$w_epa <- 1
        if (model == "points_only") cfg_k$response$w_epa <- 0
        
        prior_k <- if (model == "no_prior") {
          tibble(team = rating_teams, prior_rating = 0, prior_source = "flat")
        } else prior
        
        tr <- build_response(train, seq_len(nrow(train)), cfg_k)
        
        if (model == "no_opponent_adjustment") {
          # Unadjusted: rating = average scoring margin, centered on FBS.
          mm <- tr %>% group_by(team) %>%
            summarise(m = mean(points_for - points_against), n = n(), .groups = "drop")
          ctr <- mean(mm$m[mm$team %in% fbs_teams])
          pr <- setNames(mm$m - ctr, mm$team)
          hfa_k <- 2.5
          se <- setNames(rep(NA_real_, nrow(mm)), mm$team)
          sos_k <- setNames(rep(NA_real_, nrow(mm)), mm$team)
          gp_v <- setNames(mm$n, mm$team)
        } else {
          fit <- try(fit_points_model(tr, prior_k, cfg_k,
                                      lambda = cfg_k$fit$lambda %||% 32,
                                      fbs_teams = fbs_teams), silent = TRUE)
          if (inherits(fit, "try-error")) next
          pr <- setNames(fit$power_rating, fit$teams)
          hfa_k <- fit$hfa
          se <- setNames(fit$rating_se, fit$teams)
          # SOS as of the cutoff week, using only games already played.
          # HIGHER = HARDER (see the matching field in compute_ratings()).
          sos_tbl <- tr %>%
            mutate(oppr = coalesce(pr[opponent], NA_real_)) %>%
            group_by(team) %>%
            summarise(sos = mean(oppr, na.rm = TRUE), n = n(), .groups = "drop")
          sos_k <- setNames(sos_tbl$sos, sos_tbl$team)
          gp_v  <- setNames(sos_tbl$n, sos_tbl$team)
        }
      }
      
      pred <- test %>%
        filter(is_home | neutral) %>%
        distinct(game_id, .keep_all = TRUE) %>%
        mutate(
          season = s, cutoff_week = k, predicted_week = nxt, model = model,
          rating_home = coalesce(pr[team], NA_real_),
          rating_away = coalesce(pr[opponent], NA_real_),
          hfa = if_else(neutral, 0, hfa_k),
          pred_margin = rating_home - rating_away + hfa,
          actual_margin = points_for - points_against,
          sos_home = coalesce(sos_k[team], NA_real_),
          sos_away = coalesce(sos_k[opponent], NA_real_),
          gp_home = coalesce(gp_v[team], 0),
          gp_away = coalesce(gp_v[opponent], 0),
          se_home = coalesce(se[team], NA_real_),
          fcs_game = !(team %in% fbs_teams) | !(opponent %in% fbs_teams)
        ) %>%
        filter(!is.na(pred_margin)) %>%
        select(season, cutoff_week, predicted_week, model, game_id,
               home_team = team, away_team = opponent, neutral,
               rating_home, rating_away, hfa, pred_margin, actual_margin,
               sos_home, sos_away, gp_home, gp_away, se_home, fcs_game)
      
      results[[length(results) + 1]] <- pred
    }
  }
  
  res <- bind_rows(results)
  if (isTRUE(cfg$validation$exclude_fcs_games)) res <- filter(res, !fcs_game)
  res %>% mutate(error = pred_margin - actual_margin, abs_error = abs(error))
}

summarize_validation <- function(v, group = NULL) {
  # stats::cor() ERRORS (not warns) on zero complete pairs -- "no complete
  # element pairs" -- which previously propagated all the way up through
  # print(as.data.frame(...)) as an opaque S4-dispatch error. If v (or a
  # group of it) is empty, that almost always means an upstream filter
  # dropped everything -- most likely resolve_fbs_teams() fell back to
  # "no metadata" and every game got flagged fcs_game = TRUE. Report that
  # plainly instead of crashing.
  core <- function(d) {
    if (nrow(d) == 0) {
      return(tibble(n = 0L, mae = NA_real_, rmse = NA_real_, bias = NA_real_,
                    cor = NA_real_, calib_slope = NA_real_, ats_winrate = NA_real_))
    }
    tibble(
      n = nrow(d),
      mae = mean(d$abs_error, na.rm = TRUE),
      rmse = sqrt(mean(d$error^2, na.rm = TRUE)),
      bias = mean(d$error, na.rm = TRUE),
      cor = tryCatch(
        suppressWarnings(stats::cor(d$pred_margin, d$actual_margin, use = "complete.obs")),
        error = function(e) NA_real_),
      # Calibration slope: regress actual on predicted. 1.0 = well calibrated;
      # <1 means the model's spreads are too wide, >1 too compressed.
      calib_slope = tryCatch(
        unname(coef(stats::lm(actual_margin ~ pred_margin, data = d))[2]),
        error = function(e) NA_real_),
      ats_winrate = mean(sign(d$pred_margin) == sign(d$actual_margin), na.rm = TRUE)
    )
  }
  if (nrow(v) == 0) {
    warning("summarize_validation(): input has 0 rows. Check walk_forward_validate() ",
            "output directly (nrow, table(fcs_game) before filtering) -- this usually ",
            "means resolve_fbs_teams() fell back and every game was excluded as FCS.",
            call. = FALSE)
  }
  if (is.null(group)) return(core(v))
  v %>% group_by(across(all_of(group))) %>% group_modify(~ core(.x)) %>% ungroup()
}

#' The diagnostic that speaks directly to the Toledo problem: does the model
#' systematically over-predict teams that have played weak schedules?
#' A well-adjusted model shows bias near zero in EVERY sos bucket.
validation_by_schedule <- function(v, n_buckets = 5) {
  v %>%
    mutate(sos_diff = sos_home - sos_away,
           sos_bucket = ntile(sos_home, n_buckets),
           sosdiff_bucket = ntile(sos_diff, n_buckets),
           spread_bucket = cut(abs(pred_margin),
                               breaks = c(-Inf, 3, 7, 14, 21, 28, Inf))) %>%
    { list(
      by_sos          = summarize_validation(., "sos_bucket"),
      by_sos_diff     = summarize_validation(., "sosdiff_bucket"),
      by_spread       = summarize_validation(., "spread_bucket"),
      by_week         = summarize_validation(., "predicted_week"),
      by_games_played = summarize_validation(mutate(., gp_bucket = pmin(gp_home, 8)),
                                             "gp_bucket")
    ) }
}

#' Fit every benchmark variant and compare out-of-sample.
benchmark_models <- function(tg, talent_data = NULL, cfg = default_config(),
                             team_meta = NULL,
                             models = c("full", "no_prior", "epa_only",
                                        "points_only", "no_opponent_adjustment",
                                        "talent_only")) {
  purrr::map_dfr(models, function(m) {
    message("Validating model: ", m)
    v <- try(walk_forward_validate(tg, talent_data, cfg, team_meta, model = m),
             silent = TRUE)
    if (inherits(v, "try-error") || nrow(v) == 0) return(tibble(model = m))
    summarize_validation(v) %>% mutate(model = m, .before = 1)
  })
}

#' Optional benchmark against the closing market line. Requires CFBD_API_KEY.
pull_betting_lines <- function(seasons, use_cache = TRUE, cache_dir = tempdir()) {
  require_cfbfastR()
  purrr::map_dfr(seasons, function(s) {
    cached(file.path(cache_dir, paste0("lines_", s, ".rds")), use_cache,
           cfbfastR::cfbd_betting_lines(year = s))
  })
}

# -----------------------------------------------------------------------------
# 11. SANITY CHECKS
# -----------------------------------------------------------------------------

run_sanity_checks <- function(ratings, tg = NULL, season = NULL,
                              validation = NULL) {
  season <- season %||% max(ratings$season)
  r <- ratings %>% filter(.data$season == !!season)
  fbs <- r %>% filter(is_fbs)
  hfa <- unname(attr(ratings, "hfa_by_season")[as.character(season)])
  
  chk <- function(name, pass, detail = "") {
    tibble(check = name, pass = isTRUE(pass), detail = detail)
  }
  
  # 5. Team A - Team B reproduces the neutral spread, and HFA applies once.
  a <- fbs$team[1]; b <- fbs$team[nrow(fbs)]
  pn <- predict_game(ratings, home_team = NULL, away_team = b, team = a,
                     season = season, quiet = TRUE)
  ph <- predict_game(ratings, home_team = a, away_team = b,
                     season = season, quiet = TRUE)
  
  # SOS independence: high ratings must not be concentrated among weak schedules.
  top25 <- fbs %>% arrange(desc(power_rating)) %>% head(25)
  sos_cor_top <- suppressWarnings(stats::cor(top25$power_rating,
                                             top25$strength_of_schedule,
                                             use = "complete.obs"))
  adj_sos_cor <- suppressWarnings(stats::cor(fbs$schedule_adjustment,
                                             fbs$strength_of_schedule,
                                             use = "complete.obs"))
  
  out <- bind_rows(
    chk("Mean FBS rating ~ 0",
        abs(mean(fbs$power_rating)) < 1e-6,
        sprintf("mean = %.2e", mean(fbs$power_rating))),
    chk("Rating spread is plausible for points (SD 8-20)",
        stats::sd(fbs$power_rating) > 8 && stats::sd(fbs$power_rating) < 20,
        sprintf("SD = %.1f, range = [%.1f, %.1f]", stats::sd(fbs$power_rating),
                min(fbs$power_rating), max(fbs$power_rating))),
    chk("Top team positive, bottom team negative",
        max(fbs$power_rating) > 0 && min(fbs$power_rating) < 0,
        sprintf("%s %+.1f ... %s %+.1f", fbs$team[which.max(fbs$power_rating)],
                max(fbs$power_rating), fbs$team[which.min(fbs$power_rating)],
                min(fbs$power_rating))),
    chk("Neutral spread == rating difference",
        abs(pn$projected_margin - (pn$rating_a - pn$rating_b)) < 1e-9),
    chk("Home spread == neutral spread + HFA exactly once",
        abs((ph$projected_margin - pn$projected_margin) - hfa) < 1e-9,
        sprintf("HFA = %.2f pts", hfa)),
    chk("HFA in a plausible points range (0.5 - 5)",
        is.finite(hfa) && hfa > 0.5 && hfa < 5, sprintf("HFA = %.2f", hfa)),
    chk("No duplicated teams", !any(duplicated(r$team))),
    chk("No NA power ratings", !any(is.na(fbs$power_rating))),
    chk("No FCS teams in FBS rankings",
        !any(rank_teams(ratings, 25, season)$team %in%
               r$team[!r$is_fbs])),
    chk("Schedule adjustment increases with schedule difficulty",
        is.na(adj_sos_cor) || adj_sos_cor > 0,
        sprintf("cor(schedule_adjustment, strength_of_schedule) = %.2f (positive ",
                adj_sos_cor)),
    chk("Top-25 ratings not concentrated among weak schedules",
        is.na(sos_cor_top) || sos_cor_top > -0.5,
        sprintf("cor(rating, SOS) within top 25 = %.2f", sos_cor_top)),
    chk("Adjusted ratings differ from raw margin where opponents differ",
        stats::sd(fbs$schedule_adjustment, na.rm = TRUE) > 1,
        sprintf("SD of adjustment = %.1f pts",
                stats::sd(fbs$schedule_adjustment, na.rm = TRUE))),
    chk("Weak-schedule teams not mechanically penalized",
        {
          m <- stats::lm(power_rating ~ raw_margin_pg + strength_of_schedule, data = fbs)
          cf <- coef(m)["raw_margin_pg"]
          is.finite(cf) && cf > 0.4
        },
        "raw performance still drives the rating after controlling for SOS")
  )
  
  if (!is.null(validation)) {
    b_by_sos <- validation_by_schedule(validation)$by_sos
    out <- bind_rows(out, chk(
      "OOS bias is flat across SOS buckets (|bias| < 1.5 everywhere)",
      all(abs(b_by_sos$bias) < 1.5, na.rm = TRUE),
      paste0("max |bias| = ", round(max(abs(b_by_sos$bias), na.rm = TRUE), 2))
    ))
  }
  out
}

#' Stress test aimed squarely at the "Toledo problem".
#' Lists teams whose rating most exceeds what their opponent-adjusted evidence
#' and preseason prior would support, so you can eyeball whether the shrinkage
#' is doing its job.
sos_stress_test <- function(ratings, season = NULL, n = 15) {
  season <- season %||% max(ratings$season)
  ratings %>%
    filter(.data$season == !!season, is_fbs) %>%
    mutate(
      rating_rank = rank(-power_rating),
      raw_rank    = rank(-raw_margin_pg),
      vs_prior    = power_rating - prior_rating,
      z_vs_prior  = vs_prior / pmax(rating_se, 0.1)
    ) %>%
    filter(rating_rank <= 40) %>%
    arrange(desc(z_vs_prior)) %>%
    select(team, power_rating, rating_rank, raw_margin_pg, raw_rank,
           strength_of_schedule, avg_opponent_rating, schedule_adjustment,
           prior_rating, vs_prior, z_vs_prior, rating_se, games_played,
           n_fcs_opponents, n_distinct_opps) %>%
    head(n)
}

#' Schedule-graph connectivity. A team weakly connected to the rest of the
#' graph has an unstable coefficient no matter how good the estimator is.
schedule_connectivity <- function(tg, season) {
  e <- tg %>% filter(season == !!season) %>% distinct(team, opponent)
  teams <- sort(unique(c(e$team, e$opponent)))
  adj <- matrix(FALSE, length(teams), length(teams),
                dimnames = list(teams, teams))
  adj[cbind(match(e$team, teams), match(e$opponent, teams))] <- TRUE
  adj <- adj | t(adj)
  # BFS from the highest-degree node
  seen <- rep(FALSE, length(teams)); dist <- rep(NA_integer_, length(teams))
  start <- which.max(rowSums(adj)); seen[start] <- TRUE; dist[start] <- 0L
  frontier <- start; d <- 0L
  while (length(frontier) > 0) {
    d <- d + 1L
    nxt <- which(apply(adj[frontier, , drop = FALSE], 2, any) & !seen)
    seen[nxt] <- TRUE; dist[nxt] <- d; frontier <- nxt
  }
  tibble(team = teams, n_opponents = rowSums(adj),
         hops_to_core = dist, in_main_component = seen) %>%
    arrange(desc(is.na(hops_to_core)), desc(hops_to_core))
}

# -----------------------------------------------------------------------------
# 12. PLOTS
# -----------------------------------------------------------------------------

plot_validation <- function(v) {
  ggplot(v, aes(pred_margin, actual_margin)) +
    geom_point(alpha = 0.3) +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed") +
    geom_smooth(method = "lm", se = FALSE) +
    labs(title = sprintf("Out-of-sample predicted vs actual margin (MAE = %.2f)",
                         mean(v$abs_error, na.rm = TRUE)),
         x = "Predicted margin (home - away)", y = "Actual margin") +
    theme_minimal()
}

plot_rating_vs_sos <- function(ratings, season = NULL) {
  season <- season %||% max(ratings$season)
  ratings %>% filter(.data$season == !!season, is_fbs) %>%
    ggplot(aes(strength_of_schedule, power_rating)) +
    geom_point(alpha = 0.6) +
    geom_smooth(method = "lm", se = FALSE) +
    labs(title = "Power rating vs strength of schedule",
         subtitle = "A steep negative slope would indicate weak-schedule inflation",
         x = "Strength of schedule (points; higher = harder)",
         y = "Power rating (points vs average FBS)") +
    theme_minimal()
}

# -----------------------------------------------------------------------------
# 13. WORKED EXAMPLE
# -----------------------------------------------------------------------------

run_pipeline <- function(cfg = default_config()) {
  message("Pulling play-by-play: ", paste(cfg$seasons, collapse = ", "))
  pbp <- pull_pbp_data(cfg$seasons, cache_dir = cfg$cache_dir)
  
  message("Pulling game results...")
  games <- pull_game_results(cfg$seasons, cache_dir = cfg$cache_dir, pbp = pbp)
  
  message("Pulling team metadata...")
  team_meta <- pull_team_metadata(cfg$seasons, cache_dir = cfg$cache_dir)
  
  talent <- tryCatch(pull_talent_data(cfg$seasons, cache_dir = cfg$cache_dir),
                     error = function(e) {
                       message("Talent pull failed (", conditionMessage(e),
                               "); prior will use carryover only.")
                       NULL
                     })
  
  message("Building team-game units...")
  tg <- build_team_game_units(pbp, games, team_meta, cfg)
  
  message("Fitting ratings...")
  ratings <- compute_ratings(tg, talent, cfg, team_meta)
  
  list(pbp = pbp, games = games, team_meta = team_meta, talent = talent,
       tg = tg, ratings = ratings, cfg = cfg)
}

run_worked_example <- function() {
  cfg <- default_config()
  cfg$seasons <- get_default_seasons(3)
  p <- run_pipeline(cfg)
  
  latest <- max(p$ratings$season)
  cat("\n===== TOP 25,", latest, "=====\n")
  print(as.data.frame(rank_teams(p$ratings, 25, latest) %>%
                        select(rank, team, power_rating, offensive_rating,
                               defensive_rating, strength_of_schedule,
                               raw_margin_pg, schedule_adjustment,
                               games_played, rating_se)), digits = 3)
  
  cat("\n===== SANITY CHECKS =====\n")
  print(as.data.frame(run_sanity_checks(p$ratings, p$tg, latest)))
  
  cat("\n===== SOS STRESS TEST =====\n")
  print(as.data.frame(sos_stress_test(p$ratings, latest)), digits = 3)
  
  cat("\n===== WALK-FORWARD VALIDATION =====\n")
  v <- walk_forward_validate(p$tg, p$talent, cfg, p$team_meta, model = "full")
  print(as.data.frame(summarize_validation(v)), digits = 4)
  print(lapply(validation_by_schedule(v), as.data.frame))
  
  cat("\n===== BENCHMARKS =====\n")
  print(as.data.frame(benchmark_models(p$tg, p$talent, cfg, p$team_meta)), digits = 4)
  
  invisible(c(p, list(validation = v)))
}

if (identical(Sys.getenv("RUN_CFB_EXAMPLE"), "1")) run_worked_example()
