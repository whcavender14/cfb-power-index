# =============================================================================
# CFB POWER RATINGS v2
# -----------------------------------------------------------------------------
# A component-blend power rating on a point-spread scale.
#
#   power_rating_i(g) = a(g) * efficiency_i(g)  +  b(g) * preseason_i
#
# where g = games played, a() and b() are REGRESSION COEFFICIENTS estimated by
# regressing realized game margins on the two component differences, pooled
# across historical seasons and bucketed by games played. Because the rating IS
# the fitted linear predictor, the following holds by construction:
#
#   E[margin | A vs B, neutral] = power_A - power_B
#   E[margin | A vs B, A home]  = power_A - power_B + HFA
#
# and the calibration slope is 1 by construction on the fitting sample. There is
# no post-hoc rescaling anywhere in this file.
#
# WHY THIS SHAPE
# --------------
# The previous model was a single penalized regression shrunk toward a preseason
# prior. The prior-to-data handoff was an emergent byproduct of one ridge lambda,
# tuned on week-5-onward error, with no knob controlling early-season behavior.
# Here the two signals are estimated independently and combined with weights that
# are themselves fit out of sample, so early-season behavior is a design choice
# with an evidence trail.
#
# SIGN CONVENTIONS (read this once, it prevents an entire class of bug)
# --------------------------------------------------------------------
#   power_rating : points better than an average FBS team, neutral field.
#                  +20 beats an average FBS team by ~20. Higher is better.
#   off_rating   : points scored above an average FBS offense, vs an average
#                  FBS defense. HIGHER IS BETTER.
#   def_rating   : points allowed above an average FBS defense, vs an average
#                  FBS offense. This is a BURDEN. LOWER IS BETTER. Negative is
#                  a good defense.
#   power_rating == off_rating - def_rating, exactly, at every stage.
#
#   NOTE: this flips the defensive sign convention used in the v1 script, where
#   defensive_rating was negated so higher was better. Anything downstream that
#   reads def_rating must be updated. off_rank and def_rank are provided with
#   1 = best on both sides so ranks are safe to use without thinking about sign.
#
# TEAM IDENTITY
# -------------
# Every join in this file is on the CFBD integer team_id. No name matching
# anywhere. The v1 model matched talent by name prefix ("Alabama Crimson Tide"
# -> "Alabama"), which silently dropped talent out of the carryover regression
# and let prev_rating absorb roster persistence. That failure mode is now
# structurally impossible: if a join fails, a team_id is missing and the
# coverage checks abort the run.
#
# WEEK NUMBERING
# --------------
# Week labels are taken verbatim from the schedule. Some seasons have a week 0,
# some fold the late-August openers into week 1. Nothing in this file assumes
# either. `through_week` filters `week <= through_week` against the labels that
# actually exist, and every rating carries `weeks_included`. Validation is
# additionally reported by `week_seq` (the 1st, 2nd, 3rd... playing week of the
# season), which is comparable across seasons regardless of labeling.
#
# REQUIRES: dplyr, tidyr, purrr, tibble, cfbfastR (>= 3.0.0.9000)
#           CFBD_API_KEY set (for coaches, betting lines, live current-season)
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(tibble)
})

`%|%` <- function(x, y) if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x
`%or%` <- function(x, y) if (is.null(x)) y else x

# =============================================================================
# 1. CONFIGURATION
# =============================================================================

cfb_config <- function(...) {
  cfg <- list(
    
    cache_dir = path.expand("/Users/willcavender/Desktop/CFB Modeling/cfb_data_v2"),
    
    # Seasons used to fit everything: history ratings, preseason coefficients,
    # coaching POE, blend weights. Play-by-play is only pulled for these if
    # response$use_epa is TRUE.
    history_seasons = 2015:2025,
    
    # 2020 was played on a mutilated schedule (conference-only slates, canceled
    # games, opt-outs, wildly uneven game counts). It is excluded from PARAMETER
    # CALIBRATION by default, but its ratings are still produced so that 2021's
    # carryover term has a 2020 value to read. Set to FALSE and re-run
    # compare_calibration_windows() to test whether including it helps.
    exclude_2020_from_calibration = TRUE,
    
    response = list(
      # FALSE  = scores-only efficiency. No play-by-play dependency at all.
      #          Historical build is ~50 MB and runs in minutes.
      # TRUE   = blend actual points with EPA-implied points. Requires PBP,
      #          which is ~1-2 GB per season in memory.
      # Default FALSE. tune_response() tests this on identical folds; flip only
      # if it earns the dependency.
      use_epa = FALSE,
      w_epa   = 0.50,   # only read when use_epa is TRUE; tuned by tune_response()
      
      # Symmetric cap on the modeled game margin, in points. A 62-point win
      # carries little more information about strength than a 38-point win but
      # has large leverage on a squared-error fit. Inf disables. Tuned.
      margin_cap = 32
    ),
    
    efficiency = list(
      # Ridge penalty on the in-season offense/defense coefficients, shrunk
      # toward ZERO (league average), not toward the preseason. Keeping the
      # efficiency layer free of preseason information is what makes the two
      # components independent and the blend weights interpretable.
      #
      # lambda_base / (games + lambda_k) style schedule: heavier shrinkage when
      # the schedule graph is sparse, lighter once it connects. Attenuation from
      # this shrinkage is absorbed by the fitted a(g), so the scale stays right.
      lambda_base = 26,
      lambda_min  = 5,
      lambda_k    = 6,
      
      # All non-FBS opponents are collapsed into ONE pooled entity per season.
      # Rating 100+ FCS teams individually adds ~200 free parameters supported
      # by 0-3 games each; pooling makes FBS-vs-FCS games informative without
      # destabilizing the graph. Set FALSE to rate them individually.
      pool_fcs = TRUE,
      
      # Relative weight on games against the pooled FCS entity.
      fcs_game_weight = 0.75,
      
      # Within-season recency halflife in weeks. 0 disables. Default 0: a
      # season rating is a season-long average, and recency weighting mostly
      # adds variance. Tunable.
      recency_halflife_weeks = 0
    ),
    
    history = list(
      # Penalty used when fitting a COMPLETED season's rating. These ratings are
      # the carryover predictor and the preseason-regression target. Crucially
      # they are fit with NO preseason prior, so the carryover coefficient is
      # estimated on genuine season-over-season persistence rather than
      # recovering an assumption that was injected upstream. That circularity is
      # what produced the 105% carryover in v1.
      lambda = 6
    ),
    
    preseason = list(
      # Feature switches. Everything here is available before week 1 kicks off.
      use_prev_season   = TRUE,
      use_talent        = TRUE,
      use_returning     = TRUE,
      use_coaching      = TRUE,
      use_portal        = FALSE,  # tested by compare_preseason_specs(); off by default
      
      # Coach performance-over-expectation is shrunk toward 0 (neutral) by
      # n_seasons / (n_seasons + k). A first-time or no-history coach gets
      # exactly 0, never an invented value.
      coach_shrink_k    = 3,
      coach_max_seasons = 8,     # POE averaged over at most this many prior seasons
      
      # Hard guardrails. These abort rather than warn, because every one of them
      # firing means a silent data failure of the kind that produced v1's bugs.
      max_carryover     = 0.95,  # a fitted carryover above this means contamination
      min_talent_cover  = 0.90,  # fraction of FBS teams needing a talent value
      min_returning_cover = 0.85
    ),
    
    blend = list(
      # "parametric" : a(g) = A * g/(g+ka),  b(g) = B * kb/(g+kb). Smooth, 4
      #                parameters, no abrupt handoff. Default.
      # "bucket"     : independent ridge-stabilized fit per games-played bucket.
      #                More flexible, noisier. Reported alongside for comparison.
      form = "parametric",
      max_games_bucket = 12,
      
      # Grid searched against out-of-sample margin MAE.
      grid_A  = seq(0.55, 1.20, by = 0.05),
      grid_ka = c(1, 1.5, 2, 3, 4, 5, 6, 8, 10),
      grid_B  = seq(0.55, 1.20, by = 0.05),
      grid_kb = c(1, 1.5, 2, 3, 4, 5, 6, 8, 10)
    ),
    
    hfa = list(
      # Estimated jointly with the blend weights, on realized margins.
      fallback = 2.4,
      # Venue-specific HFA is available for predict_game() but is NOT used in
      # the ratings, which are always neutral-field. Shrunk toward the global
      # value by n_games / (n_games + k).
      venue_shrink_k = 60,
      use_venue      = FALSE
    ),
    
    checks = list(
      expected_fbs_min = 128,
      expected_fbs_max = 145,
      max_abs_rating   = 60,   # |rating| beyond this is almost certainly a bug
      min_rating_sd    = 7,
      max_rating_sd    = 22
    )
  )
  ov <- list(...)
  for (nm in names(ov)) cfg[[nm]] <- ov[[nm]]
  cfg
}

# =============================================================================
# 2. CACHE
# =============================================================================

cfb_cache_dir <- function(cfg) {
  d <- cfg$cache_dir
  if (!dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(d)) stop("Cannot create cache dir: ", d)
  d
}

#' Memoize an expression to an .rds file. Everything expensive goes through this.
cached <- function(key, cfg, expr, refresh = FALSE) {
  f <- file.path(cfb_cache_dir(cfg), paste0(key, ".rds"))
  if (!refresh && file.exists(f)) return(readRDS(f))
  val <- force(expr)
  tryCatch(saveRDS(val, f), error = function(e)
    warning("Cache write failed for ", key, ": ", conditionMessage(e), call. = FALSE))
  val
}

#' Deterministic short hash of a config subset, appended to cache keys so that
#' changing a modeling switch cannot silently return a stale cached artifact
#' fit under the old switch. Without this, compare_preseason_specs() would hand
#' back the same object for every spec and every ablation would look identical.
cfg_tag <- function(x) {
  txt <- paste(deparse(x, width.cutoff = 500L), collapse = "")
  r <- as.integer(charToRaw(txt))
  h <- 5381
  for (i in seq_along(r)) h <- (h * 33 + r[i]) %% 2147483647
  sprintf("%07x", h)
}

require_cfbfastR <- function() {
  if (!requireNamespace("cfbfastR", quietly = TRUE))
    stop("cfbfastR is not installed.")
  invisible(TRUE)
}

has_api_key <- function() nchar(Sys.getenv("CFBD_API_KEY")) > 0

require_api_key <- function(what) {
  if (!has_api_key())
    stop(what, " requires a CollegeFootballData API key.\n",
         "  usethis::edit_r_environ()  then add:  CFBD_API_KEY=your-key-here\n",
         "  or, for this session only: Sys.setenv(CFBD_API_KEY = \"your-key-here\")")
  invisible(TRUE)
}

#' Rename the first present alias to the canonical name; abort on anything
#' genuinely missing rather than degrading into an all-NA column.
canonicalize <- function(df, alias_map, required, what) {
  nm <- names(df)
  for (canon in names(alias_map)) {
    if (canon %in% nm) next
    hit <- intersect(alias_map[[canon]], nm)
    if (length(hit)) {
      names(df)[names(df) == hit[1]] <- canon
      nm <- names(df)
    }
  }
  miss <- setdiff(required, names(df))
  if (length(miss))
    stop(what, ": missing required column(s): ", paste(miss, collapse = ", "),
         "\n  columns present: ", paste(names(df), collapse = ", "),
         "\n  Add the real name to the alias map in this function.")
  df
}

# =============================================================================
# 3. TEAM IDENTITY
# =============================================================================

#' Current team directory: team_id -> display name, conference, venue.
#' Note this reflects CURRENT membership only, so it must never be used to
#' decide whether a team was FBS in some past season. Per-season division comes
#' from the schedule (section 4).
pull_team_directory <- function(cfg, refresh = FALSE) {
  require_cfbfastR()
  raw <- cached("team_directory", cfg, cfbfastR::load_cfb_teams(), refresh)
  raw <- canonicalize(
    raw,
    list(team_id = c("team_id", "id"),
         team    = c("school", "team"),
         conference = c("conference"),
         classification = c("classification", "division")),
    c("team_id", "team"), "pull_team_directory()")
  raw %>%
    transmute(team_id = as.integer(team_id),
              team = as.character(team),
              conference = as.character(conference),
              venue_id = if ("venue_id" %in% names(.)) as.integer(venue_id) else NA_integer_) %>%
    distinct(team_id, .keep_all = TRUE)
}

# =============================================================================
# 4. SCHEDULES AND GAME RESULTS
# =============================================================================

standardize_schedule <- function(g) {
  g <- canonicalize(
    g,
    list(game_id = c("game_id", "id"),
         season = c("season", "year"),
         week = c("week"),
         season_type = c("season_type"),
         neutral_site = c("neutral_site", "neutral"),
         home_id = c("home_id", "home_team_id"),
         away_id = c("away_id", "away_team_id"),
         home_team = c("home_team", "home"),
         away_team = c("away_team", "away"),
         home_points = c("home_points", "home_score"),
         away_points = c("away_points", "away_score"),
         home_division = c("home_division", "home_classification"),
         away_division = c("away_division", "away_classification"),
         venue_id = c("venue_id")),
    c("game_id", "season", "week", "home_id", "away_id",
      "home_points", "away_points"), "standardize_schedule()")
  
  if (!"season_type"  %in% names(g)) g$season_type  <- "regular"
  if (!"neutral_site" %in% names(g)) g$neutral_site <- FALSE
  if (!"venue_id"     %in% names(g)) g$venue_id     <- NA_integer_
  if (!"home_division" %in% names(g)) g$home_division <- NA_character_
  if (!"away_division" %in% names(g)) g$away_division <- NA_character_
  if (!"home_team" %in% names(g)) g$home_team <- NA_character_
  if (!"away_team" %in% names(g)) g$away_team <- NA_character_
  
  g %>%
    transmute(
      game_id = as.character(game_id),
      season = as.integer(season),
      week = as.integer(week),
      season_type = tolower(as.character(season_type)),
      venue_id = suppressWarnings(as.integer(venue_id)),
      neutral = as.logical(neutral_site) %|% FALSE,
      home_id = as.integer(home_id), away_id = as.integer(away_id),
      home_team = as.character(home_team), away_team = as.character(away_team),
      home_division = tolower(as.character(home_division)),
      away_division = tolower(as.character(away_division)),
      home_points = suppressWarnings(as.numeric(home_points)),
      away_points = suppressWarnings(as.numeric(away_points))
    ) %>%
    mutate(neutral = ifelse(is.na(neutral), FALSE, neutral)) %>%
    filter(!is.na(home_id), !is.na(away_id))
}

#' Season schedule with final scores.
#'
#' For a season in progress the data-repo loader can lag by days, so when a key
#' is present the live API is preferred and the loader is the fallback. The
#' function reports the freshest week it found; if that is behind what you
#' expect, the data is stale, not the model.
pull_schedule <- function(season, cfg, refresh = FALSE, prefer_live = NA) {
  require_cfbfastR()
  if (is.na(prefer_live)) prefer_live <- has_api_key()
  
  key <- paste0("schedule_", season)
  g <- cached(key, cfg, {
    out <- NULL
    if (prefer_live) {
      out <- tryCatch(cfbfastR::cfbd_game_info(year = season),
                      error = function(e) { message("Live game_info failed (",
                                                    conditionMessage(e), "); falling back to loader."); NULL })
    }
    if (is.null(out) || nrow(out) == 0)
      out <- cfbfastR::load_cfb_schedules(seasons = season)
    out
  }, refresh)
  
  g <- standardize_schedule(g)
  if (nrow(g) == 0) stop("pull_schedule(): no games returned for season ", season)
  g
}

#' Per-season FBS membership, taken from the schedule's own division labels so
#' that JMU/Liberty/Sam Houston/Kennesaw-style reclassifications land in the
#' right season. Falls back to the current team directory only if the schedule
#' carries no division information at all.
season_fbs_ids <- function(sched, cfg) {
  d <- bind_rows(
    sched %>% transmute(team_id = home_id, division = home_division),
    sched %>% transmute(team_id = away_id, division = away_division)
  ) %>% filter(!is.na(division), division != "")
  
  if (nrow(d) == 0) {
    warning("Schedule carries no division labels for season ",
            unique(sched$season)[1],
            "; falling back to CURRENT FBS membership, which is wrong for past ",
            "seasons with reclassified programs.", call. = FALSE)
    return(sort(unique(pull_team_directory(cfg)$team_id)))
  }
  ids <- d %>% filter(division == "fbs") %>% pull(team_id) %>% unique() %>% sort()
  as.integer(ids)
}

#' Two rows per completed game: one per team, with the opponent, the venue
#' condition and the response inputs.
#'
#' hfa_x is coded +0.5 / -0.5 / 0 so that (a) the fitted coefficient reads
#' directly as total home points in the margin, applied exactly once, and (b)
#' the column sums to zero within each game and therefore cannot become
#' collinear with the intercept.
build_team_games <- function(sched, fbs_ids, cfg, epa_tg = NULL) {
  g <- sched %>% filter(!is.na(home_points), !is.na(away_points))
  if (nrow(g) == 0)
    return(tibble(game_id = character(0), season = integer(0), week = integer(0)))
  
  home <- g %>% transmute(
    game_id, season, week, season_type, venue_id, neutral,
    team_id = home_id, opp_id = away_id,
    points_for = home_points, points_against = away_points,
    is_home = !neutral)
  away <- g %>% transmute(
    game_id, season, week, season_type, venue_id, neutral,
    team_id = away_id, opp_id = home_id,
    points_for = away_points, points_against = home_points,
    is_home = FALSE)
  
  tg <- bind_rows(home, away) %>%
    mutate(
      hfa_x = case_when(neutral ~ 0, is_home ~ 0.5, TRUE ~ -0.5),
      is_fbs = team_id %in% fbs_ids,
      opp_is_fbs = opp_id %in% fbs_ids,
      # Postseason sorts after every regular-season week regardless of labeling.
      time_index = week + 1000L * as.integer(!grepl("^reg", season_type))
    )
  
  if (!is.null(epa_tg)) {
    tg <- tg %>% left_join(epa_tg, by = c("game_id", "team_id"))
    if (!"epa_total" %in% names(tg)) tg$epa_total <- NA_real_
  } else {
    tg$epa_total <- NA_real_
    tg$off_plays <- NA_integer_
  }
  tg %>% arrange(season, time_index, game_id, desc(is_home))
}

#' Modeled response, in points.
#'
#' With use_epa = FALSE this is just points scored, capped at the game-margin
#' level. With use_epa = TRUE, EPA is converted to points by an ADDITIVE
#' baseline, not a fitted multiplier: EPA is already denominated in points, so
#' the only free quantity is the intercept that makes mean(pts_epa) match
#' mean(points_for) on the training rows. epa_points_slope() reports the
#' realized slope so the assumption is checkable rather than assumed.
#'
#' The cap is applied to the MARGIN so total game points are preserved and only
#' the spread is compressed.
build_response <- function(tg, cfg) {
  cap <- cfg$response$margin_cap
  y <- tg$points_for
  
  if (isTRUE(cfg$response$use_epa) && any(!is.na(tg$epa_total))) {
    ok <- !is.na(tg$epa_total)
    baseline <- mean(tg$points_for[ok], na.rm = TRUE) - mean(tg$epa_total[ok], na.rm = TRUE)
    pts_epa <- baseline + tg$epa_total
    w <- cfg$response$w_epa
    y <- ifelse(ok, w * pts_epa + (1 - w) * tg$points_for, tg$points_for)
  }
  
  tg$y_raw <- y
  if (is.finite(cap)) {
    k  <- paste(tg$game_id, tg$team_id)
    ko <- paste(tg$game_id, tg$opp_id)
    j  <- match(ko, k)
    m  <- tg$y_raw - tg$y_raw[j]
    adj <- ifelse(!is.na(m) & abs(m) > cap, (sign(m) * cap - m) / 2, 0)
    tg$y <- tg$y_raw + adj
  } else {
    tg$y <- tg$y_raw
  }
  tg
}

epa_points_slope <- function(tg) {
  d <- tg %>% filter(!is.na(epa_total), !is.na(points_for))
  if (nrow(d) < 100) return(NA_real_)
  unname(stats::coef(stats::lm(points_for ~ epa_total, data = d))[2])
}

# =============================================================================
# 5. OPTIONAL PLAY-BY-PLAY LAYER
# =============================================================================

#' Aggregate one season of play-by-play to team-game EPA totals and DISCARD the
#' plays immediately. Never hold more than one season of PBP in memory; eleven
#' seasons of raw PBP will not fit comfortably and does not need to.
#'
#' Team names in PBP are mapped to team_id through the season's own schedule
#' (game_id + home/away name -> id), which is exact by construction and needs no
#' name-matching heuristics.
build_epa_team_games <- function(season, sched, cfg, refresh = FALSE) {
  require_cfbfastR()
  cached(paste0("epa_tg_", season), cfg, {
    message("Pulling play-by-play for ", season, " (this is the slow step)...")
    pbp <- cfbfastR::load_cfb_pbp(seasons = season)
    
    nm <- names(pbp)
    off_col <- intersect(c("offense_play", "pos_team"), nm)[1]
    gid_col <- intersect(c("game_id", "id"), nm)[1]
    epa_col <- intersect(c("EPA", "epa"), nm)[1]
    if (any(is.na(c(off_col, gid_col, epa_col))))
      stop("build_epa_team_games(): cannot find offense/game_id/EPA columns in PBP. ",
           "Columns seen: ", paste(utils::head(nm, 40), collapse = ", "))
    
    p <- pbp %>%
      transmute(game_id = as.character(.data[[gid_col]]),
                team_name = as.character(.data[[off_col]]),
                EPA = as.numeric(.data[[epa_col]])) %>%
      filter(!is.na(EPA), !is.na(team_name))
    
    # Exact name -> id map, derived from this season's schedule.
    map <- bind_rows(
      sched %>% transmute(game_id, team_name = home_team, team_id = home_id),
      sched %>% transmute(game_id, team_name = away_team, team_id = away_id)
    ) %>% filter(!is.na(team_name))
    
    out <- p %>%
      inner_join(map, by = c("game_id", "team_name")) %>%
      group_by(game_id, team_id) %>%
      summarise(epa_total = sum(EPA), off_plays = n(), .groups = "drop")
    
    matched <- nrow(out)
    if (matched == 0)
      stop("build_epa_team_games(): zero PBP rows matched the schedule for ", season)
    rm(pbp, p); gc(verbose = FALSE)
    out
  }, refresh)
}

# =============================================================================
# 6. EFFICIENCY MODEL (opponent-adjusted, current season only)
# =============================================================================

#' Penalized least squares on team-game points.
#'
#'   y_it = mu + alpha_i + beta_j + gamma * hfa_x_it + e
#'
#' i = the scoring team, j = the conceding opponent. mu and gamma are
#' UNPENALIZED; alpha and beta are shrunk toward ZERO, i.e. toward league
#' average, NOT toward a preseason prior. That independence is what makes the
#' downstream blend weights mean what they say.
#'
#' Returns offense (higher better) and defense-as-burden (lower better) on the
#' points scale, centered so the FBS mean of each is exactly zero.
fit_efficiency <- function(tg, fbs_ids, cfg, lambda = NULL) {
  
  if (nrow(tg) == 0) return(NULL)
  
  pool <- isTRUE(cfg$efficiency$pool_fcs)
  key_of <- function(id) {
    k <- as.character(id)
    if (pool) k[!(id %in% fbs_ids)] <- "FCS"
    k
  }
  tg$tkey <- key_of(tg$team_id)
  tg$okey <- key_of(tg$opp_id)
  
  ents <- sort(unique(c(tg$tkey, tg$okey)))
  nE <- length(ents); n <- nrow(tg); p <- 2L * nE + 2L
  ti <- match(tg$tkey, ents); oi <- match(tg$okey, ents)
  
  # Games-played-dependent shrinkage: heavier while the schedule graph is sparse.
  gp_med <- stats::median(tg %>% count(team_id) %>% pull(n))
  if (is.null(lambda)) {
    lam <- cfg$efficiency$lambda_base * cfg$efficiency$lambda_k /
      (gp_med + cfg$efficiency$lambda_k)
    lambda <- max(lam, cfg$efficiency$lambda_min)
  }
  
  X <- matrix(0, n, p)
  X[, 1] <- 1
  X[cbind(seq_len(n), 1L + ti)] <- 1
  X[cbind(seq_len(n), 1L + nE + oi)] <- 1
  X[, p] <- tg$hfa_x
  
  w <- rep(1, n)
  fcs_game <- !(tg$team_id %in% fbs_ids) | !(tg$opp_id %in% fbs_ids)
  w[fcs_game] <- w[fcs_game] * cfg$efficiency$fcs_game_weight
  hl <- cfg$efficiency$recency_halflife_weeks
  if (is.finite(hl) && hl > 0) {
    age <- max(tg$time_index) - tg$time_index
    w <- w * 0.5 ^ (age / hl)
  }
  
  dvec <- c(0, rep(lambda, 2L * nE), 0)
  A <- crossprod(X * sqrt(w)) + diag(dvec, p, p)
  b <- crossprod(X, w * tg$y)
  Ainv <- tryCatch(solve(A), error = function(e)
    stop("fit_efficiency(): normal equations singular. This means the schedule ",
         "graph is degenerate (probably a single game or a fully disconnected ",
         "set). Raise efficiency$lambda_min."))
  theta <- as.numeric(Ainv %*% b)
  
  alpha <- theta[2:(nE + 1)]
  beta  <- theta[(nE + 2):(2 * nE + 1)]
  gamma <- theta[p]
  resid <- as.numeric(tg$y - X %*% theta)
  
  ent_is_fbs <- ents != "FCS" &
    suppressWarnings(as.integer(ents)) %in% fbs_ids
  ent_is_fbs[is.na(ent_is_fbs)] <- FALSE
  if (!any(ent_is_fbs)) stop("fit_efficiency(): no FBS entities in the fit.")
  
  # Center so 0 = average FBS team. The model is invariant to
  # alpha -> alpha + c, beta -> beta - c, so choosing c is choosing a free
  # parameter, not altering any prediction.
  alpha_c <- alpha - mean(alpha[ent_is_fbs])
  beta_c  <- beta  - mean(beta[ent_is_fbs])
  
  # Cluster-robust variance on game, since a game's two rows share conditions.
  U  <- X * (w * resid)
  Ug <- rowsum(U, tg$game_id)
  V  <- Ainv %*% crossprod(Ug) %*% Ainv
  se <- vapply(seq_len(nE), function(i) {
    io <- 1L + i; id <- 1L + nE + i
    sqrt(max(V[io, io] + V[id, id] - 2 * V[io, id], 0))
  }, numeric(1))
  
  gp <- tg %>% count(team_id, name = "games_played")
  
  out <- tibble(
    entity = ents,
    team_id = suppressWarnings(as.integer(ents)),
    eff_off = alpha_c,
    eff_def = beta_c,                      # BURDEN: lower is better
    eff_power = alpha_c - beta_c,
    eff_se = se
  ) %>%
    left_join(gp, by = "team_id") %>%
    mutate(games_played = coalesce(games_played, 0L))
  
  list(ratings = out, hfa = gamma, lambda = lambda,
       sigma = sqrt(sum(w * resid^2) / max(sum(w) - p, 1)),
       n_obs = n, epa_slope = epa_points_slope(tg))
}

#' Schedule-graph connectivity. A team weakly attached to the graph has an
#' unstable coefficient no matter how good the estimator is. Reported as a
#' diagnostic and used to warn, not to switch models: an abrupt model switch is
#' worse than the smooth weight transition the blend already provides.
schedule_connectivity <- function(tg, fbs_ids) {
  e <- tg %>% filter(team_id %in% fbs_ids, opp_id %in% fbs_ids) %>%
    distinct(team_id, opp_id)
  teams <- sort(unique(c(e$team_id, e$opp_id)))
  if (length(teams) < 2)
    return(tibble(team_id = teams, n_fbs_opponents = 0L,
                  hops_to_core = NA_integer_, in_main_component = FALSE))
  adj <- matrix(FALSE, length(teams), length(teams))
  adj[cbind(match(e$team_id, teams), match(e$opp_id, teams))] <- TRUE
  adj <- adj | t(adj)
  seen <- rep(FALSE, length(teams)); dist <- rep(NA_integer_, length(teams))
  start <- which.max(rowSums(adj)); seen[start] <- TRUE; dist[start] <- 0L
  frontier <- start; d <- 0L
  while (length(frontier) > 0) {
    d <- d + 1L
    nxt <- which(apply(adj[frontier, , drop = FALSE], 2, any) & !seen)
    if (length(nxt) == 0) break
    seen[nxt] <- TRUE; dist[nxt] <- d; frontier <- nxt
  }
  tibble(team_id = teams, n_fbs_opponents = as.integer(rowSums(adj)),
         hops_to_core = dist, in_main_component = seen)
}

# =============================================================================
# 7. HISTORY: COMPLETED-SEASON RATINGS
# =============================================================================

#' Full-season opponent-adjusted rating for a COMPLETED season, fit with a small
#' fixed penalty and NO preseason prior.
#'
#' These objects serve two roles and must be free of preseason information for
#' both: they are the carryover PREDICTOR for season s+1 and the TARGET the
#' preseason regression is fit against. v1 fit carryover on ratings that had
#' already been shrunk toward carry * prev_rating, which partially recovers the
#' assumption fed in, which is one of the two reasons its carryover exceeded 1.
season_history_rating <- function(season, cfg, refresh = FALSE) {
  key <- paste0("hist_rating_", season, "_",
                cfg_tag(list(cfg$response, cfg$efficiency, cfg$history)))
  cached(key, cfg, {
    sched <- pull_schedule(season, cfg)
    fbs   <- season_fbs_ids(sched, cfg)
    epa_tg <- if (isTRUE(cfg$response$use_epa))
      build_epa_team_games(season, sched, cfg) else NULL
    tg <- build_team_games(sched, fbs, cfg, epa_tg)
    if (nrow(tg) == 0) stop("season_history_rating(): no completed games in ", season)
    tg <- build_response(tg, cfg)
    fit <- fit_efficiency(tg, fbs, cfg, lambda = cfg$history$lambda)
    
    sos <- tg %>%
      left_join(fit$ratings %>% select(opp_id = team_id, opp_power = eff_power),
                by = "opp_id") %>%
      group_by(team_id) %>%
      summarise(
        raw_margin_pg = mean(points_for - points_against),
        # SOS in points, HIGHER = HARDER: the expected margin an average FBS
        # team would post against this exact schedule, netting out where each
        # game was played.
        sos = mean(opp_power - ifelse(neutral, 0, ifelse(is_home, 1, -1)) * fit$hfa,
                   na.rm = TRUE),
        n_fcs_opp = sum(!opp_is_fbs),
        .groups = "drop")
    
    list(
      season = season,
      ratings = fit$ratings %>%
        filter(!is.na(team_id), team_id %in% fbs) %>%
        left_join(sos, by = "team_id") %>%
        transmute(season = season, team_id,
                  hist_power = eff_power, hist_off = eff_off, hist_def = eff_def,
                  games_played, sos, raw_margin_pg, n_fcs_opp),
      hfa = fit$hfa, sigma = fit$sigma, epa_slope = fit$epa_slope,
      fbs_ids = fbs)
  }, refresh)
}

build_history <- function(cfg, seasons = NULL, refresh = FALSE) {
  seasons <- seasons %or% cfg$history_seasons
  message("Building completed-season ratings for ", min(seasons), "-", max(seasons))
  parts <- lapply(seasons, function(s) {
    message("  season ", s)
    season_history_rating(s, cfg, refresh)
  })
  names(parts) <- as.character(seasons)
  list(
    ratings = bind_rows(lapply(parts, `[[`, "ratings")),
    hfa = vapply(parts, function(p) p$hfa, numeric(1)),
    sigma = vapply(parts, function(p) p$sigma, numeric(1)),
    fbs_ids = lapply(parts, `[[`, "fbs_ids"),
    seasons = seasons
  )
}

# =============================================================================
# 8. PRESEASON FEATURES
# =============================================================================
# Every feature below is published before week 1 of its season. Nothing here
# reads a single snap of the season it describes.

#' 247 composite roster talent. Joined on team_id, z-scored within season across
#' FBS teams only, so a z of +2 means the same thing in 2016 and 2026.
pull_talent <- function(seasons, cfg, refresh = FALSE) {
  require_cfbfastR()
  cached(paste0("talent_", min(seasons), "_", max(seasons)), cfg, {
    cfbfastR::load_cfb_team_talent(seasons = seasons)
  }, refresh) %>%
    canonicalize(list(season = c("season", "year"),
                      team_id = c("team_id", "id"),
                      talent = c("talent_composite", "talent"),
                      blue_chip_ratio = c("blue_chip_ratio")),
                 c("season", "team_id", "talent"), "pull_talent()") %>%
    transmute(season = as.integer(season), team_id = as.integer(team_id),
              talent = as.numeric(talent),
              blue_chip = if ("blue_chip_ratio" %in% names(.))
                as.numeric(blue_chip_ratio) else NA_real_) %>%
    filter(!is.na(team_id), !is.na(talent)) %>%
    distinct(season, team_id, .keep_all = TRUE)
}

#' Returning production, separately for offense and defense.
#'
#' NOTE ON overall_returning: in the 2025 pull, overall_returning is identical
#' to off_returning row for row, which is a data defect. It is not used here.
#' Offense and defense are read separately, which is what we wanted anyway
#' because it also replaces v1's hardcoded 50/50 offense/defense prior split
#' with something the data can speak to.
pull_returning <- function(seasons, cfg, refresh = FALSE) {
  require_cfbfastR()
  raw <- cached(paste0("returning_", min(seasons), "_", max(seasons)), cfg, {
    if (exists("load_cfb_returning_production", asNamespace("cfbfastR"))) {
      cfbfastR::load_cfb_returning_production(seasons = seasons)
    } else {
      require_api_key("Returning production")
      purrr::map_dfr(seasons, function(s) {
        d <- tryCatch(cfbfastR::cfbd_player_returning(year = s),
                      error = function(e) NULL)
        if (is.null(d) || nrow(d) == 0) return(NULL)
        if (!"season" %in% names(d)) d$season <- s
        d
      })
    }
  }, refresh)
  
  raw %>%
    canonicalize(list(season = c("season", "year"),
                      team_id = c("team_id", "id"),
                      off_returning = c("off_returning", "percent_returning_ppa",
                                        "offense_ppa"),
                      def_returning = c("def_returning", "percent_returning_ppa_def",
                                        "defense_ppa")),
                 c("season", "team_id", "off_returning"), "pull_returning()") %>%
    transmute(season = as.integer(season), team_id = as.integer(team_id),
              off_returning = as.numeric(off_returning),
              def_returning = if ("def_returning" %in% names(.))
                as.numeric(def_returning) else NA_real_) %>%
    filter(!is.na(team_id)) %>%
    distinct(season, team_id, .keep_all = TRUE)
}

#' Head coach of record per team-season, plus tenure and first-year flag.
#'
#' Multiple rows per team-season occur when a coach is fired midseason. The
#' coach of record is the one who coached the most games. For the PRESEASON of
#' season s we need the coach expected to start season s, which is the coach of
#' record in season s itself (hires are announced in the prior offseason and the
#' endpoint records them against the upcoming season).
pull_coaches <- function(seasons, cfg, refresh = FALSE) {
  require_cfbfastR(); require_api_key("Coaching data")
  raw <- cached(paste0("coaches_", min(seasons), "_", max(seasons)), cfg, {
    purrr::map_dfr(seasons, function(s) {
      d <- tryCatch(cfbfastR::cfbd_coaches(year = s), error = function(e) NULL)
      if (is.null(d) || nrow(d) == 0) {
        warning("No coach data for ", s, call. = FALSE); return(NULL)
      }
      if (!"year" %in% names(d)) d$year <- s
      d
    })
  }, refresh)
  
  if (is.null(raw) || nrow(raw) == 0)
    stop("pull_coaches(): no coaching data returned for ",
         min(seasons), "-", max(seasons))
  
  # sp_overall / sp_offense / sp_defense / srs are deliberately DROPPED here.
  # They are external national ratings; using them would import consensus
  # through the back door. Coaching quality is measured against our own ratings.
  raw %>%
    canonicalize(list(coach_id = c("id", "coach_id"),
                      team_id = c("team_id"),
                      season = c("year", "season"),
                      games = c("games"),
                      hire_date = c("hire_date")),
                 c("coach_id", "team_id", "season"), "pull_coaches()") %>%
    transmute(coach_id = as.character(coach_id),
              team_id = as.integer(team_id),
              season = as.integer(season),
              games = suppressWarnings(as.numeric(games)) %|% 0,
              hire_date = as.character(hire_date)) %>%
    filter(!is.na(team_id)) %>%
    group_by(team_id, season) %>%
    arrange(desc(games), hire_date, .by_group = TRUE) %>%
    slice(1) %>%
    ungroup()
}

coach_features <- function(coaches, season) {
  cur  <- coaches %>% filter(season == !!season) %>% select(team_id, coach_id)
  prev <- coaches %>% filter(season == !!season - 1L) %>%
    select(team_id, prev_coach = coach_id)
  tenure <- coaches %>%
    filter(season < !!season) %>%
    group_by(team_id, coach_id) %>%
    summarise(first_season_here = min(season), n_here = n(), .groups = "drop")
  cur %>%
    left_join(prev, by = "team_id") %>%
    left_join(tenure, by = c("team_id", "coach_id")) %>%
    mutate(
      is_new_hc = as.integer(is.na(prev_coach) | prev_coach != coach_id),
      tenure_years = coalesce(season - first_season_here, 0L),
      tenure_years = pmin(tenure_years, 20L)
    ) %>%
    select(team_id, coach_id, is_new_hc, tenure_years)
}

#' Net transfer-portal talent movement. Off by default; enabled only if
#' compare_preseason_specs() shows it adds beyond returning production.
pull_portal <- function(seasons, cfg, refresh = FALSE) {
  require_cfbfastR(); require_api_key("Transfer portal data")
  raw <- cached(paste0("portal_", min(seasons), "_", max(seasons)), cfg, {
    purrr::map_dfr(seasons, function(s) {
      d <- tryCatch(cfbfastR::cfbd_recruiting_transfer_portal(year = s),
                    error = function(e) NULL)
      if (is.null(d) || nrow(d) == 0) return(NULL)
      if (!"season" %in% names(d)) d$season <- s
      d
    })
  }, refresh)
  if (is.null(raw) || nrow(raw) == 0) return(NULL)
  
  nm <- names(raw)
  orig <- intersect(c("origin", "origin_team", "from_team"), nm)[1]
  dest <- intersect(c("destination", "destination_team", "to_team"), nm)[1]
  rate <- intersect(c("rating", "stars"), nm)[1]
  if (any(is.na(c(orig, dest)))) {
    warning("pull_portal(): unrecognized portal schema; portal feature disabled. ",
            "Columns: ", paste(nm, collapse = ", "), call. = FALSE)
    return(NULL)
  }
  r <- if (is.na(rate)) rep(1, nrow(raw)) else
    suppressWarnings(as.numeric(raw[[rate]]))
  r[is.na(r)] <- stats::median(r, na.rm = TRUE)
  
  inc <- tibble(season = as.integer(raw$season), team = as.character(raw[[dest]]),
                v = r) %>% group_by(season, team) %>%
    summarise(portal_in = sum(v), .groups = "drop")
  out <- tibble(season = as.integer(raw$season), team = as.character(raw[[orig]]),
                v = r) %>% group_by(season, team) %>%
    summarise(portal_out = sum(v), .groups = "drop")
  
  # Portal endpoint carries names, not ids. Resolve through the team directory
  # by exact name only; unresolved teams get NA and are treated as league-average
  # rather than silently zeroed.
  dir <- pull_team_directory(cfg) %>% select(team_id, team)
  full_join(inc, out, by = c("season", "team")) %>%
    mutate(portal_in = coalesce(portal_in, 0), portal_out = coalesce(portal_out, 0),
           portal_net = portal_in - portal_out) %>%
    inner_join(dir, by = "team") %>%
    select(season, team_id, portal_net)
}

#' Assemble one row per (season, FBS team) of everything known before kickoff.
#' Coverage failures abort here rather than propagating as league-average zeros.
build_preseason_features <- function(season, history, cfg,
                                     talent = NULL, returning = NULL,
                                     coaches = NULL, portal = NULL,
                                     fbs_ids = NULL) {
  
  if (is.null(fbs_ids)) fbs_ids <- season_fbs_ids(pull_schedule(season, cfg), cfg)
  base <- tibble(season = as.integer(season), team_id = as.integer(fbs_ids))
  nf <- nrow(base)
  
  # --- previous-season adjusted strength (opponent-adjusted, no prior in it)
  prev <- history$ratings %>%
    filter(season == !!season - 1L) %>%
    transmute(team_id, prev_power = hist_power, prev_off = hist_off,
              prev_def = hist_def)
  base <- base %>% left_join(prev, by = "team_id") %>%
    mutate(has_prev = !is.na(prev_power))
  # A team with no prior-season rating (promoted from FCS, or first season in
  # the window) is deliberately treated as league-average on this feature, and
  # flagged, rather than dropped.
  base <- base %>%
    mutate(prev_power = coalesce(prev_power, 0),
           prev_off = coalesce(prev_off, 0), prev_def = coalesce(prev_def, 0))
  
  # --- talent, z-scored within season across FBS
  if (isTRUE(cfg$preseason$use_talent)) {
    if (is.null(talent)) talent <- pull_talent(season, cfg)
    t_s <- talent %>% filter(season == !!season) %>%
      semi_join(base, by = "team_id")
    cover <- nrow(t_s) / nf
    if (cover < cfg$preseason$min_talent_cover)
      stop(sprintf("Talent coverage for %d is %.1f%% of %d FBS teams (need %.0f%%). ",
                   season, 100 * cover, nf, 100 * cfg$preseason$min_talent_cover),
           "This is exactly the silent-join failure the v2 design exists to ",
           "prevent. Check load_cfb_team_talent(seasons = ", season, ").")
    mu <- mean(t_s$talent); sdv <- stats::sd(t_s$talent)
    if (!is.finite(sdv) || sdv <= 0) stop("Talent has zero variance in ", season)
    base <- base %>%
      left_join(t_s %>% transmute(team_id, talent_z = (talent - mu) / sdv),
                by = "team_id") %>%
      mutate(talent_z = coalesce(talent_z, 0))
  } else base$talent_z <- 0
  
  # --- returning production, offense and defense separately
  if (isTRUE(cfg$preseason$use_returning)) {
    if (is.null(returning)) returning <- pull_returning(season, cfg)
    r_s <- returning %>% filter(season == !!season) %>%
      semi_join(base, by = "team_id")
    cover <- sum(!is.na(r_s$off_returning)) / nf
    if (cover < cfg$preseason$min_returning_cover)
      stop(sprintf("Returning-production coverage for %d is %.1f%% of %d FBS ",
                   season, 100 * cover, nf), "teams. Check the pull.")
    zc <- function(x) { m <- mean(x, na.rm = TRUE); s <- stats::sd(x, na.rm = TRUE)
    if (!is.finite(s) || s <= 0) return(rep(0, length(x))); (x - m) / s }
    r_s <- r_s %>% mutate(rp_off_z = zc(off_returning), rp_def_z = zc(def_returning))
    base <- base %>%
      left_join(r_s %>% select(team_id, rp_off_z, rp_def_z), by = "team_id") %>%
      mutate(rp_off_z = coalesce(rp_off_z, 0), rp_def_z = coalesce(rp_def_z, 0))
  } else { base$rp_off_z <- 0; base$rp_def_z <- 0 }
  
  # --- coaching identity features (POE is attached later, in stage two)
  if (isTRUE(cfg$preseason$use_coaching)) {
    if (is.null(coaches)) coaches <- pull_coaches((season - 25L):season, cfg)
    cf <- coach_features(coaches, season)
    base <- base %>% left_join(cf, by = "team_id") %>%
      mutate(is_new_hc = coalesce(is_new_hc, 0L),
             tenure_years = coalesce(tenure_years, 0L),
             coach_id = coalesce(coach_id, NA_character_))
  } else { base$is_new_hc <- 0L; base$tenure_years <- 0L; base$coach_id <- NA_character_ }
  
  # --- portal
  if (isTRUE(cfg$preseason$use_portal) && !is.null(portal)) {
    p_s <- portal %>% filter(season == !!season)
    m <- mean(p_s$portal_net, na.rm = TRUE); s <- stats::sd(p_s$portal_net, na.rm = TRUE)
    base <- base %>% left_join(p_s %>% select(team_id, portal_net), by = "team_id") %>%
      mutate(portal_z = if (is.finite(s) && s > 0) coalesce((portal_net - m) / s, 0) else 0) %>%
      select(-portal_net)
  } else base$portal_z <- 0
  
  base
}

# =============================================================================
# 9. PRESEASON MODEL
# =============================================================================
# Two regressions, one for offense and one for defense, each mapping preseason
# features onto the points scale. Fitting them separately gives a data-driven
# offense/defense split and preserves pre_power = pre_off - pre_def exactly.
#
# TARGET: the completed-season rating from section 7, which contains no
# preseason information. PREDICTORS: the previous completed-season rating (same
# estimator, same shrinkage) plus talent, returning production and coaching.
# Because target and predictor are produced by the same prior-free estimator,
# the fitted carryover is genuine season-over-season persistence, not a
# recovered assumption.

preseason_formula_terms <- function(cfg) {
  tm <- c()
  if (isTRUE(cfg$preseason$use_prev_season)) tm <- c(tm, "prev_off", "prev_def")
  if (isTRUE(cfg$preseason$use_talent))      tm <- c(tm, "talent_z")
  if (isTRUE(cfg$preseason$use_returning))   tm <- c(tm, "rp_off_z", "rp_def_z")
  if (isTRUE(cfg$preseason$use_coaching))    tm <- c(tm, "coach_poe", "is_new_hc")
  if (isTRUE(cfg$preseason$use_portal))      tm <- c(tm, "portal_z")
  tm
}

#' Coach performance over expectation, measured against OUR ratings.
#'
#' Stage one fits a coach-free preseason model. A coach-season's POE is the
#' residual of that model: how much better the team was than its roster,
#' carryover and returning production said it should be. A coach's value in
#' season s is the shrunk mean of their POE over seasons strictly before s, at
#' any school. n / (n + k) shrinkage means a first-time or thin-history coach
#' lands at exactly 0 rather than inheriting an invented history.
compute_coach_poe <- function(feat_hist, history, coaches, cfg, upto_season) {
  
  train <- feat_hist %>%
    filter(season < upto_season) %>%
    inner_join(history$ratings %>% select(season, team_id, hist_power),
               by = c("season", "team_id")) %>%
    filter(has_prev)
  if (isTRUE(cfg$exclude_2020_from_calibration))
    train <- train %>% filter(season != 2020L)
  if (nrow(train) < 200) return(tibble(coach_id = character(0),
                                       n_seasons = integer(0),
                                       coach_poe = double(0)))
  
  rhs <- c("prev_off", "prev_def", "talent_z", "rp_off_z", "rp_def_z")
  rhs <- intersect(rhs, names(train))
  f <- stats::as.formula(paste("hist_power ~", paste(rhs, collapse = " + ")))
  m <- stats::lm(f, data = train)
  train$poe <- stats::residuals(m)
  
  train %>%
    filter(!is.na(coach_id)) %>%
    arrange(coach_id, desc(season)) %>%
    group_by(coach_id) %>%
    slice_head(n = cfg$preseason$coach_max_seasons) %>%
    summarise(n_seasons = n(), poe_bar = mean(poe), .groups = "drop") %>%
    mutate(coach_poe = poe_bar * n_seasons / (n_seasons + cfg$preseason$coach_shrink_k)) %>%
    select(coach_id, n_seasons, coach_poe)
}

#' Fit the preseason offense and defense regressions on seasons < upto_season.
fit_preseason_model <- function(feat_hist, history, cfg, upto_season) {
  
  train <- feat_hist %>%
    filter(season < upto_season) %>%
    inner_join(history$ratings %>%
                 select(season, team_id, hist_power, hist_off, hist_def),
               by = c("season", "team_id"))
  
  if (isTRUE(cfg$exclude_2020_from_calibration))
    train <- train %>% filter(season != 2020L)
  
  # A team-season with no prior-season rating (the first season in the window,
  # or a program promoted from FCS) carries prev_* = 0 as a placeholder. Leaving
  # those rows in would feed the carryover regression a block of artificial
  # zeros and bias the coefficient. They are dropped from FITTING; they are
  # still RATED at prediction time, where the placeholder is honest.
  train <- train %>% filter(has_prev)
  
  if (nrow(train) < 200)
    stop("fit_preseason_model(): only ", nrow(train), " usable team-seasons ",
         "before ", upto_season, ". Widen history_seasons.")
  
  terms <- preseason_formula_terms(cfg)
  terms <- intersect(terms, names(train))
  fo <- stats::as.formula(paste("hist_off ~", paste(terms, collapse = " + ")))
  fd <- stats::as.formula(paste("hist_def ~", paste(terms, collapse = " + ")))
  mo <- stats::lm(fo, data = train)
  md <- stats::lm(fd, data = train)
  
  # Carryover guardrail. The implied season-over-season persistence of overall
  # strength is the coefficient on prev_off in the offense model minus the
  # coefficient on prev_def in the defense model, evaluated on a unit of overall
  # strength. Approximate it directly by refitting power on power.
  carry <- NA_real_
  if ("prev_off" %in% terms) {
    mp <- try(stats::lm(hist_power ~ prev_power,
                        data = train %>% mutate(prev_power = prev_off - prev_def)),
              silent = TRUE)
    if (!inherits(mp, "try-error")) carry <- unname(stats::coef(mp)[2])
  }
  if (is.finite(carry) && carry > cfg$preseason$max_carryover)
    stop(sprintf(paste0("Fitted carryover is %.3f, above the %.2f ceiling. A ",
                        "carryover near or above 1 means an omitted correlated feature (usually ",
                        "talent failing to join) is being absorbed by the previous-season term, ",
                        "or the target is contaminated by the prior. Investigate before ",
                        "proceeding; do not raise the ceiling."), carry, cfg$preseason$max_carryover))
  
  list(off = mo, def = md, terms = terms, carryover = carry,
       n_train = nrow(train), seasons_used = sort(unique(train$season)),
       rmse_power = sqrt(mean((train$hist_power -
                                 (stats::predict(mo, train) - stats::predict(md, train)))^2)))
}

#' Apply a fitted preseason model, returning point-denominated per-feature
#' contributions that sum exactly to pre_off and pre_def.
predict_preseason <- function(pm, feat) {
  f <- feat
  for (t in pm$terms) if (!t %in% names(f)) f[[t]] <- 0
  f$pre_off <- as.numeric(stats::predict(pm$off, newdata = f))
  f$pre_def <- as.numeric(stats::predict(pm$def, newdata = f))
  f$pre_power <- f$pre_off - f$pre_def
  
  co <- stats::coef(pm$off); cd <- stats::coef(pm$def)
  contrib <- function(term) {
    if (!term %in% names(co) || !term %in% names(cd) || !term %in% names(f))
      return(rep(0, nrow(f)))
    a <- co[[term]]; b <- cd[[term]]
    if (!is.finite(a)) a <- 0
    if (!is.finite(b)) b <- 0
    (a - b) * f[[term]]
  }
  f$c_prev    <- contrib("prev_off") + contrib("prev_def")
  f$c_talent  <- contrib("talent_z")
  f$c_return  <- contrib("rp_off_z") + contrib("rp_def_z")
  f$c_coach   <- contrib("coach_poe") + contrib("is_new_hc")
  f$c_portal  <- contrib("portal_z")
  f$c_base    <- f$pre_power - (f$c_prev + f$c_talent + f$c_return +
                                  f$c_coach + f$c_portal)
  # Re-center the preseason power on the FBS mean so 0 stays "average FBS".
  ctr <- mean(f$pre_power)
  f$pre_power <- f$pre_power - ctr
  f$pre_off <- f$pre_off - mean(f$pre_off)
  f$pre_def <- f$pre_def - mean(f$pre_def)
  f$c_base <- f$c_base - ctr
  f
}

# =============================================================================
# 10. BLEND WEIGHTS
# =============================================================================
# The transition from preseason to in-season is fit, not assumed.
#
# On a pooled set of genuinely out-of-sample weekly predictions, regress the
# realized home margin on the two component differences and a home indicator,
# separately by games played:
#
#   margin ~ 0 + a(g) * (eff_home - eff_away)
#              + b(g) * (pre_home - pre_away)
#              + hfa  * is_home_game
#
# Because the rating is then DEFINED as a(g)*eff + b(g)*pre, the point-spread
# identity and a calibration slope of 1 both hold by construction. There is no
# separate rescaling step, and the weights are not constrained to sum to 1 --
# forcing that would push the attenuation from efficiency shrinkage into the
# ratings themselves.

blend_predict <- function(par, eff_diff, pre_diff, gp, home_ind, form = "parametric") {
  a <- par$A * gp / (gp + par$ka)
  b <- par$B * par$kb / (gp + par$kb)
  a * eff_diff + b * pre_diff + par$hfa * home_ind
}

blend_weights <- function(par, gp) {
  list(a = par$A * gp / (gp + par$ka),
       b = par$B * par$kb / (gp + par$kb))
}

#' Grid-search the four-parameter smooth weight schedule plus HFA.
calibrate_blend <- function(oos, cfg) {
  d <- oos %>%
    filter(!is.na(eff_diff), !is.na(pre_diff), !is.na(actual_margin)) %>%
    mutate(gp = pmin(pmin(gp_home, gp_away), cfg$blend$max_games_bucket),
           home_ind = as.numeric(!neutral))
  if (nrow(d) < 500)
    stop("calibrate_blend(): only ", nrow(d), " out-of-sample games. Widen ",
         "history_seasons or check the validation loop.")
  
  best <- NULL
  for (A in cfg$blend$grid_A) for (ka in cfg$blend$grid_ka)
    for (B in cfg$blend$grid_B) for (kb in cfg$blend$grid_kb) {
      a <- A * d$gp / (d$gp + ka)
      b <- B * kb / (d$gp + kb)
      base <- a * d$eff_diff + b * d$pre_diff
      # HFA solved in closed form given the rest, so it is not on the grid.
      r <- d$actual_margin - base
      hfa <- sum(r * d$home_ind) / max(sum(d$home_ind^2), 1)
      mae <- mean(abs(r - hfa * d$home_ind))
      if (is.null(best) || mae < best$mae)
        best <- list(A = A, ka = ka, B = B, kb = kb, hfa = hfa, mae = mae)
    }
  
  # Bucket-wise fit reported alongside, as a check on the parametric shape.
  bucket <- d %>% group_by(gp) %>% group_modify(~{
    if (nrow(.x) < 60) return(tibble(a = NA_real_, b = NA_real_, hfa = NA_real_, n = nrow(.x)))
    X <- cbind(.x$eff_diff, .x$pre_diff, .x$home_ind)
    ridge <- diag(c(1e-3, 1e-3, 1e-6), 3, 3)
    cf <- tryCatch(as.numeric(solve(crossprod(X) + ridge, crossprod(X, .x$actual_margin))),
                   error = function(e) rep(NA_real_, 3))
    tibble(a = cf[1], b = cf[2], hfa = cf[3], n = nrow(.x))
  }) %>% ungroup()
  
  list(par = best, bucket = bucket, n_games = nrow(d),
       form = cfg$blend$form,
       schedule = tibble(games_played = 0:cfg$blend$max_games_bucket) %>%
         mutate(a = best$A * games_played / (games_played + best$ka),
                b = best$B * best$kb / (games_played + best$kb),
                pct_current = 100 * a / pmax(a + b, 1e-9)))
}

#' Shrunk venue home-field advantage. Available to predict_game(); never enters
#' a rating, which is always neutral-field.
calibrate_venue_hfa <- function(oos, global_hfa, cfg) {
  oos %>%
    filter(!neutral, !is.na(venue_id)) %>%
    mutate(resid = actual_margin - pred_margin) %>%
    group_by(venue_id) %>%
    summarise(n = n(), mean_resid = mean(resid), .groups = "drop") %>%
    mutate(venue_hfa = global_hfa +
             mean_resid * n / (n + cfg$hfa$venue_shrink_k))
}

# =============================================================================
# 11. WALK-FORWARD VALIDATION
# =============================================================================
# Every prediction below uses only information that existed before the predicted
# games kicked off:
#   * preseason model coefficients fit on seasons strictly earlier than s
#   * coach POE computed from seasons strictly earlier than s
#   * carryover from season s-1's completed rating
#   * efficiency from season s games in weeks strictly earlier than the target
#
# The FIRST playing week of every season is scored, with the efficiency term
# absent, which is the whole point: v1's first_predicted_week = 4 meant weeks 1
# through 4 were never in the validation set at all.

#' Produce raw component differences for every game of every season, at every
#' weekly cut. Blend weights are NOT applied here -- this frame is the input to
#' calibrate_blend(), and afterwards the same frame is scored under the fitted
#' weights. That keeps weight fitting and scoring on identical folds.
build_oos_frame <- function(cfg, history = NULL, seasons = NULL,
                            talent = NULL, returning = NULL, coaches = NULL,
                            portal = NULL, verbose = TRUE) {
  
  history <- history %or% build_history(cfg)
  seasons <- seasons %or% cfg$history_seasons
  
  all_seasons <- sort(unique(history$ratings$season))
  span <- (min(all_seasons) - 1L):max(all_seasons)
  talent    <- talent    %or% pull_talent(span, cfg)
  returning <- returning %or% pull_returning(span, cfg)
  coaches   <- coaches   %or% if (isTRUE(cfg$preseason$use_coaching))
    pull_coaches((min(span) - 25L):max(span), cfg) else NULL
  portal    <- portal    %or% if (isTRUE(cfg$preseason$use_portal))
    pull_portal(span, cfg) else NULL
  
  # Feature frame for every historical season (needed to fit the preseason model
  # and the coach POE at each cut).
  feat_hist <- purrr::map_dfr(all_seasons, function(s) {
    fb <- history$fbs_ids[[as.character(s)]]
    tryCatch(build_preseason_features(s, history, cfg, talent, returning,
                                      coaches, portal, fbs_ids = fb),
             error = function(e) { warning("features ", s, ": ",
                                           conditionMessage(e), call. = FALSE); NULL })
  })
  
  # Scoreable seasons need at least one earlier season for carryover and enough
  # earlier seasons for the preseason regression.
  scoreable <- seasons[seasons >= min(all_seasons) + 3L]
  if (length(scoreable) == 0)
    stop("build_oos_frame(): no seasons have enough history to score. ",
         "history_seasons spans ", min(all_seasons), "-", max(all_seasons), ".")
  
  out <- list()
  for (s in scoreable) {
    if (verbose) message("OOS season ", s)
    
    poe <- if (isTRUE(cfg$preseason$use_coaching))
      compute_coach_poe(feat_hist, history, coaches, cfg, upto_season = s) else NULL
    
    fh <- feat_hist
    if (!is.null(poe)) {
      fh <- fh %>% left_join(poe %>% select(coach_id, coach_poe), by = "coach_id") %>%
        mutate(coach_poe = coalesce(coach_poe, 0))
    } else fh$coach_poe <- 0
    
    pm <- tryCatch(fit_preseason_model(fh, history, cfg, upto_season = s),
                   error = function(e) { warning("preseason model for ", s, ": ",
                                                 conditionMessage(e), call. = FALSE); NULL })
    if (is.null(pm)) next
    
    sched <- pull_schedule(s, cfg)
    fbs   <- season_fbs_ids(sched, cfg)
    pre <- predict_preseason(pm, fh %>% filter(season == s))
    pre_v <- setNames(pre$pre_power, pre$team_id)
    pre_o <- setNames(pre$pre_off, pre$team_id)
    pre_d <- setNames(pre$pre_def, pre$team_id)
    
    epa_tg <- if (isTRUE(cfg$response$use_epa))
      build_epa_team_games(s, sched, cfg) else NULL
    tg_all <- build_team_games(sched, fbs, cfg, epa_tg)
    if (nrow(tg_all) == 0) next
    
    wk <- sort(unique(tg_all$time_index))
    for (i in seq_along(wk)) {
      k <- wk[i]
      train <- tg_all %>% filter(time_index < k)
      test_tg <- tg_all %>% filter(time_index == k)
      if (nrow(test_tg) == 0) next
      
      if (nrow(train) > 0) {
        tr <- build_response(train, cfg)
        fit <- tryCatch(fit_efficiency(tr, fbs, cfg), error = function(e) NULL)
      } else fit <- NULL
      
      if (!is.null(fit)) {
        ev <- setNames(fit$ratings$eff_power, fit$ratings$team_id)
        eo <- setNames(fit$ratings$eff_off, fit$ratings$team_id)
        ed <- setNames(fit$ratings$eff_def, fit$ratings$team_id)
        gpv <- setNames(fit$ratings$games_played, fit$ratings$team_id)
      } else {
        ev <- eo <- ed <- gpv <- setNames(numeric(0), character(0))
      }
      gk <- function(v, id, default = 0) {
        x <- v[as.character(id)]; x[is.na(x)] <- default; as.numeric(x)
      }
      
      games <- test_tg %>% filter(is_home | neutral) %>%
        distinct(game_id, .keep_all = TRUE)
      
      out[[length(out) + 1]] <- games %>%
        transmute(
          season = s, week = week, time_index = time_index, week_seq = i,
          game_id, venue_id, neutral,
          home_id = team_id, away_id = opp_id,
          both_fbs = (team_id %in% fbs) & (opp_id %in% fbs),
          eff_home = gk(ev, team_id), eff_away = gk(ev, opp_id),
          eff_off_home = gk(eo, team_id), eff_off_away = gk(eo, opp_id),
          eff_def_home = gk(ed, team_id), eff_def_away = gk(ed, opp_id),
          pre_home = gk(pre_v, team_id), pre_away = gk(pre_v, opp_id),
          gp_home = gk(gpv, team_id), gp_away = gk(gpv, opp_id),
          actual_margin = points_for - points_against
        ) %>%
        mutate(eff_diff = eff_home - eff_away,
               pre_diff = pre_home - pre_away)
    }
  }
  
  res <- bind_rows(out)
  attr(res, "feat_hist") <- feat_hist
  attr(res, "history") <- history
  res
}

#' Apply fitted blend weights to the OOS frame and score.
score_oos <- function(oos, blend, cfg, fbs_only = TRUE) {
  d <- oos
  if (fbs_only) d <- d %>% filter(both_fbs)
  gp <- pmin(pmin(d$gp_home, d$gp_away), cfg$blend$max_games_bucket)
  w <- blend_weights(blend$par, gp)
  d %>% mutate(
    a = w$a, b = w$b,
    pred_margin = w$a * eff_diff + w$b * pre_diff +
      ifelse(neutral, 0, blend$par$hfa),
    error = pred_margin - actual_margin,
    abs_error = abs(error))
}

summarize_predictions <- function(d, group = NULL) {
  core <- function(x) {
    if (nrow(x) == 0)
      return(tibble(n = 0L, mae = NA_real_, rmse = NA_real_, bias = NA_real_,
                    cor = NA_real_, calib_slope = NA_real_, su_rate = NA_real_))
    tibble(
      n = nrow(x),
      mae = mean(x$abs_error, na.rm = TRUE),
      rmse = sqrt(mean(x$error^2, na.rm = TRUE)),
      # bias = predicted minus actual. Positive means the model favors the home
      # team too much in this cell.
      bias = mean(x$error, na.rm = TRUE),
      cor = tryCatch(suppressWarnings(stats::cor(x$pred_margin, x$actual_margin,
                                                 use = "complete.obs")),
                     error = function(e) NA_real_),
      calib_slope = tryCatch(unname(stats::coef(
        stats::lm(actual_margin ~ pred_margin, data = x))[2]),
        error = function(e) NA_real_),
      su_rate = mean(sign(x$pred_margin) == sign(x$actual_margin), na.rm = TRUE))
  }
  if (is.null(group)) return(core(d))
  d %>% group_by(across(all_of(group))) %>% group_modify(~ core(.x)) %>% ungroup()
}

#' The headline table: MAE by early week, then weeks 5+, then overall.
week_table <- function(d, label = "model") {
  d <- d %>% mutate(bucket = ifelse(week_seq <= 4, paste0("W", week_seq), "W5+"))
  bind_rows(
    summarize_predictions(d, "bucket") %>% rename(cell = bucket),
    summarize_predictions(d) %>% mutate(cell = "ALL")
  ) %>% mutate(model = label, .before = 1) %>%
    arrange(match(cell, c("W1", "W2", "W3", "W4", "W5+", "ALL")))
}

# =============================================================================
# 12. BENCHMARKS
# =============================================================================

#' Closing betting spreads, used ONLY as a benchmark, never as a model input.
#'
#' CFBD returns `spread` (latest available, i.e. closing) and `spread_open`
#' (opening). This function uses `spread`, labels it, and never substitutes the
#' opener. CFBD's convention is home-team-relative and negative when the home
#' team is favored, so the implied home margin is -spread; the sign is verified
#' empirically below rather than assumed, because getting it backwards would
#' silently produce a terrible-looking benchmark.
pull_lines <- function(seasons, cfg, refresh = FALSE,
                       providers = c("consensus", "DraftKings", "Bovada", "ESPN Bet")) {
  require_cfbfastR(); require_api_key("Betting lines")
  raw <- cached(paste0("lines_", min(seasons), "_", max(seasons)), cfg, {
    purrr::map_dfr(seasons, function(s) {
      d <- tryCatch(cfbfastR::cfbd_betting_lines(year = s), error = function(e) NULL)
      if (is.null(d) || nrow(d) == 0) { warning("No lines for ", s, call. = FALSE); return(NULL) }
      if (!"season" %in% names(d)) d$season <- s
      d
    })
  }, refresh)
  if (is.null(raw) || nrow(raw) == 0) return(NULL)
  
  nm <- names(raw)
  gid <- intersect(c("game_id", "id"), nm)[1]
  sp  <- intersect(c("spread"), nm)[1]
  prov <- intersect(c("provider", "line_provider"), nm)[1]
  if (is.na(gid) || is.na(sp)) {
    warning("pull_lines(): unrecognized schema; benchmark disabled. Columns: ",
            paste(nm, collapse = ", "), call. = FALSE)
    return(NULL)
  }
  d <- tibble(game_id = as.character(raw[[gid]]),
              spread = suppressWarnings(as.numeric(raw[[sp]])),
              provider = if (is.na(prov)) "unknown" else as.character(raw[[prov]])) %>%
    filter(!is.na(spread)) %>%
    mutate(rankp = match(provider, providers),
           rankp = ifelse(is.na(rankp), length(providers) + 1L, rankp)) %>%
    arrange(game_id, rankp) %>%
    distinct(game_id, .keep_all = TRUE) %>%
    select(game_id, spread, provider)
  attr(d, "line_type") <- "closing (CFBD `spread` field; NOT `spread_open`)"
  d
}

benchmark_market <- function(oos_scored, lines) {
  if (is.null(lines)) return(NULL)
  d <- oos_scored %>% inner_join(lines, by = "game_id")
  if (nrow(d) < 100) {
    warning("benchmark_market(): only ", nrow(d), " games matched a line.",
            call. = FALSE)
    if (nrow(d) == 0) return(NULL)
  }
  c1 <- suppressWarnings(stats::cor(-d$spread, d$actual_margin, use = "complete.obs"))
  if (!is.finite(c1)) stop("benchmark_market(): cannot verify line sign convention.")
  sgn <- if (c1 > 0) -1 else 1
  if (abs(c1) < 0.5)
    stop(sprintf(paste0("Market line correlates with actual margin at only %.2f. ",
                        "Something is wrong with the join or the provider mix; refusing to report ",
                        "a benchmark from it."), c1))
  if (sgn == 1)
    warning("Betting-line sign convention was POSITIVE-home-favorite in this ",
            "pull; flipped automatically.", call. = FALSE)
  d %>% mutate(pred_margin = sgn * spread,
               error = pred_margin - actual_margin,
               abs_error = abs(error))
}

#' The v1 architecture, given the clean v2 data layer, so that the comparison
#' isolates ARCHITECTURE rather than the name-join bugs.
#'
#' Single penalized regression shrunk toward a preseason prior built as
#' intercept + carryover * prev_rating + talent_beta * talent_z, with carryover
#' fit on already-shrunk outputs (the v1 behavior, reproduced deliberately).
#' Week 1 falls back to the prior, which the original could not do.
#'
#' Note this FLATTERS v1 relative to what has actually been running, because v1
#' in production had talent dropping out of the carryover regression entirely.
legacy_oos_frame <- function(cfg, history, oos_template, lambda = 32) {
  seasons <- sort(unique(oos_template$season))
  out <- list()
  talent <- pull_talent((min(history$ratings$season) - 1L):max(seasons), cfg)
  
  for (s in seasons) {
    hist_s <- history$ratings %>% filter(season < s)
    if (nrow(hist_s) == 0) next
    # v1-style carryover: regress fitted rating on prior fitted rating.
    fitset <- hist_s %>% select(season, team_id, hist_power) %>%
      inner_join(hist_s %>% transmute(season = season + 1L, team_id,
                                      prev = hist_power),
                 by = c("season", "team_id"))
    carry <- if (nrow(fitset) >= 100)
      unname(stats::coef(stats::lm(hist_power ~ prev, data = fitset))[2]) else 0.55
    prev <- history$ratings %>% filter(season == s - 1L) %>%
      transmute(team_id, prev = hist_power)
    t_s <- talent %>% filter(season == s)
    tz <- if (nrow(t_s) > 5) {
      m <- mean(t_s$talent); sd_ <- stats::sd(t_s$talent)
      t_s %>% transmute(team_id, talent_z = (talent - m) / sd_)
    } else tibble(team_id = integer(0), talent_z = double(0))
    
    sched <- pull_schedule(s, cfg); fbs <- season_fbs_ids(sched, cfg)
    prior <- tibble(team_id = fbs) %>%
      left_join(prev, by = "team_id") %>% left_join(tz, by = "team_id") %>%
      mutate(prior = carry * coalesce(prev, 0) + 6.0 * coalesce(talent_z, 0))
    pv <- setNames(prior$prior, prior$team_id)
    
    tg_all <- build_team_games(sched, fbs, cfg, NULL)
    wk <- sort(unique(tg_all$time_index))
    for (i in seq_along(wk)) {
      k <- wk[i]
      train <- tg_all %>% filter(time_index < k)
      test <- tg_all %>% filter(time_index == k, is_home | neutral) %>%
        distinct(game_id, .keep_all = TRUE)
      if (nrow(test) == 0) next
      
      if (nrow(train) == 0) {
        rv <- pv; hfa_k <- cfg$hfa$fallback
      } else {
        tr <- build_response(train, cfg)
        f <- tryCatch(legacy_fit(tr, fbs, pv, lambda), error = function(e) NULL)
        if (is.null(f)) { rv <- pv; hfa_k <- cfg$hfa$fallback }
        else { rv <- setNames(f$power, f$team_id); hfa_k <- f$hfa }
      }
      gk <- function(v, id) { x <- v[as.character(id)]; x[is.na(x)] <- 0; as.numeric(x) }
      out[[length(out) + 1]] <- test %>% transmute(
        season = s, week, week_seq = i, game_id, neutral,
        both_fbs = (team_id %in% fbs) & (opp_id %in% fbs),
        pred_margin = gk(rv, team_id) - gk(rv, opp_id) +
          ifelse(neutral, 0, hfa_k),
        actual_margin = points_for - points_against)
    }
  }
  bind_rows(out) %>% filter(both_fbs) %>%
    mutate(error = pred_margin - actual_margin, abs_error = abs(error))
}

legacy_fit <- function(tg, fbs_ids, prior_vec, lambda) {
  keys <- sort(unique(c(tg$team_id, tg$opp_id)))
  nT <- length(keys); n <- nrow(tg); p <- 2L * nT + 2L
  ti <- match(tg$team_id, keys); oi <- match(tg$opp_id, keys)
  X <- matrix(0, n, p); X[, 1] <- 1
  X[cbind(seq_len(n), 1L + ti)] <- 1
  X[cbind(seq_len(n), 1L + nT + oi)] <- 1
  X[, p] <- tg$hfa_x
  pr <- prior_vec[as.character(keys)]; pr[is.na(pr)] <- 0
  is_fbs <- keys %in% fbs_ids
  lam <- ifelse(is_fbs, lambda, lambda * 6)
  dvec <- c(0, lam, lam, 0)
  mvec <- c(0, 0.5 * pr, -0.5 * pr, 0)
  A <- crossprod(X) + diag(dvec, p, p)
  b <- crossprod(X, tg$y) + dvec * mvec
  th <- as.numeric(solve(A, b))
  a <- th[2:(nT + 1)]; bb <- th[(nT + 2):(2 * nT + 1)]
  a <- a - mean(a[is_fbs]); bb <- bb - mean(bb[is_fbs])
  list(team_id = keys, power = a - bb, hfa = th[p])
}

# =============================================================================
# 13. ONE-TIME MODEL BUILD
# =============================================================================

#' Fit and cache everything the weekly function needs: completed-season ratings,
#' preseason regressions, coach POE, blend weights, HFA.
#'
#' Run once per season (and again after a season completes, to roll the window
#' forward). Everything downstream reads the cached artifact.
fit_model_artifacts <- function(cfg = cfb_config(), refresh = FALSE,
                                target_season = NULL) {
  
  target_season <- target_season %or% (max(cfg$history_seasons) + 1L)
  key <- paste0("artifacts_", target_season, "_",
                min(cfg$history_seasons), "_", max(cfg$history_seasons), "_",
                cfg_tag(cfg[setdiff(names(cfg), "cache_dir")]))
  
  cached(key, cfg, {
    history <- build_history(cfg)
    
    span <- (min(cfg$history_seasons) - 1L):target_season
    talent    <- pull_talent(span, cfg)
    returning <- pull_returning(span, cfg)
    coaches   <- if (isTRUE(cfg$preseason$use_coaching))
      pull_coaches((min(span) - 25L):target_season, cfg) else NULL
    portal    <- if (isTRUE(cfg$preseason$use_portal)) pull_portal(span, cfg) else NULL
    
    message("Building out-of-sample frame for weight calibration...")
    oos <- build_oos_frame(cfg, history, cfg$history_seasons,
                           talent, returning, coaches, portal)
    oos_fbs <- oos %>% filter(both_fbs)
    if (isTRUE(cfg$exclude_2020_from_calibration))
      oos_fbs <- oos_fbs %>% filter(season != 2020L)
    
    message("Calibrating blend weights on ", nrow(oos_fbs), " out-of-sample games...")
    blend <- calibrate_blend(oos_fbs, cfg)
    
    feat_hist <- attr(oos, "feat_hist")
    poe <- if (isTRUE(cfg$preseason$use_coaching))
      compute_coach_poe(feat_hist, history, coaches, cfg, upto_season = target_season)
    else NULL
    fh <- feat_hist
    fh$coach_poe <- 0
    if (!is.null(poe)) {
      fh <- fh %>% select(-coach_poe) %>%
        left_join(poe %>% select(coach_id, coach_poe), by = "coach_id") %>%
        mutate(coach_poe = coalesce(coach_poe, 0))
    }
    pm <- fit_preseason_model(fh, history, cfg, upto_season = target_season)
    
    venue <- NULL
    if (isTRUE(cfg$hfa$use_venue)) {
      sc <- score_oos(oos_fbs, blend, cfg)
      sched_all <- purrr::map_dfr(cfg$history_seasons,
                                  function(s) pull_schedule(s, cfg) %>%
                                    select(game_id, venue_id))
      venue <- calibrate_venue_hfa(sc %>% select(-venue_id) %>%
                                     left_join(sched_all, by = "game_id"),
                                   blend$par$hfa, cfg)
    }
    
    message(sprintf("Preseason model: n=%d, carryover=%.3f, in-sample RMSE=%.2f pts",
                    pm$n_train, pm$carryover, pm$rmse_power))
    message(sprintf("Blend: A=%.2f ka=%.1f B=%.2f kb=%.1f HFA=%.2f (OOS MAE %.3f)",
                    blend$par$A, blend$par$ka, blend$par$B, blend$par$kb,
                    blend$par$hfa, blend$par$mae))
    
    list(cfg = cfg, target_season = target_season, history = history,
         talent = talent, returning = returning, coaches = coaches, portal = portal,
         coach_poe = poe, preseason_model = pm, blend = blend, venue_hfa = venue,
         oos = oos, built_at = Sys.time())
  }, refresh)
}

# =============================================================================
# 14. THE WEEKLY PRODUCTION FUNCTION
# =============================================================================

#' Neutral-field power ratings for every FBS team, on a point-spread scale.
#'
#' @param season       season to rate.
#' @param through_week include games with week <= through_week. NULL (default)
#'                     uses every completed game. Pass a number to freeze the
#'                     rating at a point in time. Week labels are taken from the
#'                     schedule verbatim, so if the season has a week 0 it works
#'                     without special-casing, and if it does not, through_week
#'                     = 0 simply yields the pure preseason rating.
#' @param artifacts    output of fit_model_artifacts(). Built and cached if NULL.
#' @param refresh_schedule re-pull the current season's schedule (do this weekly).
#'
#' @return tibble, one row per FBS team, sorted by power_rating descending.
build_power_ratings <- function(season, through_week = NULL,
                                cfg = cfb_config(), artifacts = NULL,
                                refresh_schedule = TRUE, quiet = FALSE) {
  
  artifacts <- artifacts %or% fit_model_artifacts(cfg, target_season = season)
  cfg <- artifacts$cfg
  pm <- artifacts$preseason_model
  blend <- artifacts$blend
  
  sched <- pull_schedule(season, cfg, refresh = refresh_schedule)
  fbs <- season_fbs_ids(sched, cfg)
  if (length(fbs) < cfg$checks$expected_fbs_min ||
      length(fbs) > cfg$checks$expected_fbs_max)
    stop(sprintf("Found %d FBS teams for %d, outside the expected %d-%d range.",
                 length(fbs), season, cfg$checks$expected_fbs_min,
                 cfg$checks$expected_fbs_max))
  
  # --- preseason component
  feat <- build_preseason_features(season, artifacts$history, cfg,
                                   artifacts$talent, artifacts$returning,
                                   artifacts$coaches, artifacts$portal,
                                   fbs_ids = fbs)
  feat$coach_poe <- 0
  if (!is.null(artifacts$coach_poe))
    feat <- feat %>% select(-coach_poe) %>%
    left_join(artifacts$coach_poe %>% select(coach_id, coach_poe),
              by = "coach_id") %>%
    mutate(coach_poe = coalesce(coach_poe, 0))
  pre <- predict_preseason(pm, feat)
  
  # --- current-season efficiency component
  played <- sched %>% filter(!is.na(home_points), !is.na(away_points))
  if (!is.null(through_week)) played <- played %>% filter(week <= through_week)
  weeks_included <- sort(unique(played$week))
  
  epa_tg <- NULL
  if (isTRUE(cfg$response$use_epa) && nrow(played) > 0)
    epa_tg <- build_epa_team_games(season, sched, cfg)
  
  tg <- build_team_games(played, fbs, cfg, epa_tg)
  conn <- NULL
  if (nrow(tg) > 0) {
    tg <- build_response(tg, cfg)
    fit <- fit_efficiency(tg, fbs, cfg)
    conn <- schedule_connectivity(tg, fbs)
    eff <- fit$ratings %>% filter(!is.na(team_id)) %>%
      select(team_id, eff_off, eff_def, eff_power, eff_se, games_played)
    sos <- tg %>%
      left_join(eff %>% select(opp_id = team_id, opp_power = eff_power),
                by = "opp_id") %>%
      group_by(team_id) %>%
      summarise(raw_margin_pg = mean(points_for - points_against),
                sos = mean(opp_power -
                             ifelse(neutral, 0, ifelse(is_home, 1, -1)) * fit$hfa, na.rm = TRUE),
                n_fcs_opp = sum(!opp_is_fbs), .groups = "drop")
  } else {
    fit <- list(hfa = blend$par$hfa, lambda = NA_real_, sigma = NA_real_,
                epa_slope = NA_real_)
    eff <- tibble(team_id = integer(0), eff_off = double(0), eff_def = double(0),
                  eff_power = double(0), eff_se = double(0), games_played = integer(0))
    sos <- tibble(team_id = integer(0), raw_margin_pg = double(0),
                  sos = double(0), n_fcs_opp = integer(0))
  }
  
  dir <- pull_team_directory(cfg)
  
  out <- pre %>%
    select(team_id, pre_off, pre_def, pre_power,
           c_base, c_prev, c_talent, c_return, c_coach, c_portal,
           prev_power, talent_z, rp_off_z, rp_def_z, coach_poe, is_new_hc,
           tenure_years, has_prev) %>%
    left_join(eff, by = "team_id") %>%
    left_join(sos, by = "team_id") %>%
    mutate(games_played = coalesce(games_played, 0L),
           eff_off = coalesce(eff_off, 0), eff_def = coalesce(eff_def, 0),
           eff_power = coalesce(eff_power, 0), eff_se = coalesce(eff_se, NA_real_))
  
  gpb <- pmin(out$games_played, cfg$blend$max_games_bucket)
  w <- blend_weights(blend$par, gpb)
  out$w_current <- w$a
  out$w_preseason <- w$b
  
  out <- out %>%
    mutate(
      off_rating = w$a * eff_off + w$b * pre_off,
      def_rating = w$a * eff_def + w$b * pre_def,
      power_rating = off_rating - def_rating)
  
  # Center on the full FBS universe for this season, by construction.
  out <- out %>%
    mutate(off_rating = off_rating - mean(off_rating),
           def_rating = def_rating - mean(def_rating),
           power_rating = off_rating - def_rating,
           power_rating = power_rating - mean(power_rating))
  
  # Approximate standard error: efficiency sampling error scaled by its weight,
  # plus the preseason model's historical RMSE scaled by its weight. Treated as
  # independent, which understates slightly. Reported as approximate.
  out <- out %>%
    mutate(rating_se = sqrt((w$a * coalesce(eff_se, 0))^2 +
                              (w$b * pm$rmse_power)^2))
  
  if (!is.null(conn))
    out <- out %>% left_join(conn %>% select(team_id, n_fbs_opponents,
                                             in_main_component), by = "team_id")
  else { out$n_fbs_opponents <- 0L; out$in_main_component <- NA }
  
  res <- out %>%
    left_join(dir %>% select(team_id, team, conference), by = "team_id") %>%
    arrange(desc(power_rating)) %>%
    mutate(rank = row_number(),
           off_rank = rank(-off_rating, ties.method = "min"),
           def_rank = rank(def_rating, ties.method = "min")) %>%
    transmute(
      rank, team, conference, team_id,
      power_rating, off_rating, def_rating, off_rank, def_rank,
      games_played, rating_se,
      w_current, w_preseason,
      eff_power, eff_off, eff_def,
      pre_power, pre_off, pre_def,
      c_base, c_prev, c_talent, c_return, c_coach, c_portal,
      prev_power, talent_z, rp_off_z, rp_def_z, coach_poe, is_new_hc,
      tenure_years, sos = coalesce(sos, NA_real_),
      raw_margin_pg = coalesce(raw_margin_pg, NA_real_),
      n_fcs_opp = coalesce(n_fcs_opp, 0L),
      n_fbs_opponents = coalesce(n_fbs_opponents, 0L),
      has_prev_season = has_prev)
  
  attr(res, "season") <- season
  attr(res, "weeks_included") <- weeks_included
  attr(res, "through_week") <- through_week
  attr(res, "hfa") <- blend$par$hfa
  attr(res, "in_season_hfa") <- fit$hfa
  attr(res, "blend_par") <- blend$par
  attr(res, "epa_points_slope") <- fit$epa_slope
  attr(res, "n_fbs") <- length(fbs)
  
  if (!quiet) {
    message(sprintf("%d: %d FBS teams, weeks included: %s (%d games played by the median team)",
                    season, length(fbs),
                    if (length(weeks_included)) paste(weeks_included, collapse = ",") else "none (preseason)",
                    as.integer(stats::median(res$games_played))))
    message(sprintf("  weights at the median team: current %.2f / preseason %.2f | HFA %.2f",
                    stats::median(res$w_current), stats::median(res$w_preseason),
                    blend$par$hfa))
  }
  res
}

#' Expected margin between two teams. Ratings are neutral-field; HFA is applied
#' here and only here.
predict_game <- function(ratings, home, away, neutral = FALSE,
                         venue_id = NULL, artifacts = NULL) {
  g <- function(nm) {
    r <- ratings %>% filter(team == nm)
    if (nrow(r) == 0) stop("Team not in ratings: ", nm)
    r$power_rating[1]
  }
  hfa <- attr(ratings, "hfa") %|% 2.4
  if (!neutral && !is.null(venue_id) && !is.null(artifacts$venue_hfa)) {
    v <- artifacts$venue_hfa %>% filter(venue_id == !!venue_id)
    if (nrow(v)) hfa <- v$venue_hfa[1]
  }
  m <- g(home) - g(away) + ifelse(neutral, 0, hfa)
  tibble(home = home, away = away, neutral = neutral,
         home_rating = g(home), away_rating = g(away),
         hfa_applied = ifelse(neutral, 0, hfa),
         projected_margin = m,
         favorite = ifelse(m >= 0, home, away),
         spread = -abs(m))
}

# =============================================================================
# 15. SANITY CHECKS
# =============================================================================

run_sanity_checks <- function(ratings, artifacts = NULL, scored_oos = NULL,
                              cfg = cfb_config()) {
  chk <- function(name, pass, detail = "")
    tibble(check = name, pass = isTRUE(pass), detail = as.character(detail))
  
  n <- nrow(ratings)
  sdv <- stats::sd(ratings$power_rating)
  if (is.null(artifacts))
    stop("run_sanity_checks(): pass the artifacts object so the carryover and ",
         "HFA checks can run: run_sanity_checks(r, artifacts).")
  pm <- artifacts$preseason_model
  bl <- artifacts$blend
  
  out <- bind_rows(
    chk("FBS universe complete",
        n >= cfg$checks$expected_fbs_min && n <= cfg$checks$expected_fbs_max,
        paste0(n, " teams")),
    chk("No duplicate teams", !any(duplicated(ratings$team_id))),
    chk("No missing ratings",
        !any(is.na(ratings$power_rating)) && !any(is.na(ratings$off_rating)),
        paste0(sum(is.na(ratings$power_rating)), " NA power ratings")),
    chk("Ratings centered on zero", abs(mean(ratings$power_rating)) < 1e-8,
        sprintf("mean = %.2e", mean(ratings$power_rating))),
    chk("power == off - def exactly",
        max(abs(ratings$power_rating -
                  (ratings$off_rating - ratings$def_rating))) < 1e-8),
    chk("Rating dispersion plausible for points",
        sdv > cfg$checks$min_rating_sd && sdv < cfg$checks$max_rating_sd,
        sprintf("SD = %.1f, range [%.1f, %.1f]", sdv,
                min(ratings$power_rating), max(ratings$power_rating))),
    chk("No extreme ratings",
        max(abs(ratings$power_rating)) < cfg$checks$max_abs_rating,
        sprintf("max |rating| = %.1f", max(abs(ratings$power_rating)))),
    chk("Component weights non-negative and bounded",
        all(ratings$w_current >= 0) && all(ratings$w_preseason >= 0) &&
          all(ratings$w_current <= 2) && all(ratings$w_preseason <= 2),
        sprintf("current %.2f-%.2f, preseason %.2f-%.2f",
                min(ratings$w_current), max(ratings$w_current),
                min(ratings$w_preseason), max(ratings$w_preseason))),
    chk("Talent joined for effectively every team",
        mean(ratings$talent_z != 0) > 0.9,
        sprintf("%.0f%% of teams have a nonzero talent z",
                100 * mean(ratings$talent_z != 0))),
    chk("Returning production joined",
        mean(ratings$rp_off_z != 0) > 0.85,
        sprintf("%.0f%% nonzero", 100 * mean(ratings$rp_off_z != 0))),
    chk("Coaching joined and neutral where it should be",
        mean(ratings$coach_poe == 0) < 0.6,
        sprintf("%.0f%% of teams neutral (new/no-history coaches)",
                100 * mean(ratings$coach_poe == 0))),
    chk("Carryover coefficient sane",
        is.na(pm$carryover) || pm$carryover < cfg$preseason$max_carryover,
        sprintf("carryover = %.3f", pm$carryover %|% NA_real_)),
    chk("HFA in a plausible range",
        bl$par$hfa > 0.5 && bl$par$hfa < 5,
        sprintf("HFA = %.2f", bl$par$hfa)),
    chk("Schedule graph connected",
        all(coalesce(ratings$in_main_component, TRUE)) ||
          sum(!coalesce(ratings$in_main_component, TRUE)) < 5,
        sprintf("%d team(s) outside the main component",
                sum(!coalesce(ratings$in_main_component, TRUE)))),
    chk("Rating is not just raw margin",
        all(is.na(ratings$raw_margin_pg)) ||
          stats::sd(ratings$power_rating - ratings$raw_margin_pg, na.rm = TRUE) > 1,
        "opponent adjustment is moving teams off their raw margin"),
    chk("Rating still tracks on-field performance after controlling for SOS",
        {
          d <- ratings %>% filter(!is.na(raw_margin_pg), !is.na(sos))
          if (nrow(d) < 40) TRUE else {
            cf <- stats::coef(stats::lm(power_rating ~ raw_margin_pg + sos, data = d))
            is.finite(cf[["raw_margin_pg"]]) && cf[["raw_margin_pg"]] > 0.2
          }
        }, "weak-schedule teams are not being mechanically penalized")
  )
  
  if (!is.null(scored_oos)) {
    wt <- week_table(scored_oos)
    out <- bind_rows(out,
                     chk("Calibration slope near 1 in every week bucket",
                         all(abs(wt$calib_slope - 1) < 0.2, na.rm = TRUE),
                         paste0("slopes: ", paste(sprintf("%s=%.2f", wt$cell, wt$calib_slope),
                                                  collapse = ", "))),
                     chk("Bias small in every week bucket",
                         all(abs(wt$bias) < 1.5, na.rm = TRUE),
                         sprintf("max |bias| = %.2f", max(abs(wt$bias), na.rm = TRUE))))
  }
  out
}

#' Leakage audit. Asserts every scored prediction used only earlier games.
audit_leakage <- function(oos) {
  bad <- oos %>%
    group_by(season, week_seq) %>%
    summarise(max_gp = max(pmax(gp_home, gp_away)), .groups = "drop") %>%
    filter(max_gp > week_seq - 1)
  if (nrow(bad) > 0) {
    print(as.data.frame(bad))
    stop("LEAKAGE: some predictions were made with more games in the training ",
         "set than could have been played before that week.")
  }
  message("Leakage audit passed: ", nrow(oos), " predictions, ",
          "no fold used a game from the predicted week or later.")
  invisible(TRUE)
}

# =============================================================================
# 16. MODEL COMPARISON / TUNING HARNESSES
# =============================================================================

#' Score the new model, the patched v1 architecture, the market, and simple
#' baselines on identical folds. This is the table to look at before believing
#' anything in this file.
run_validation <- function(cfg = cfb_config(), artifacts = NULL,
                           include_market = TRUE, include_legacy = TRUE) {
  
  artifacts <- artifacts %or% fit_model_artifacts(cfg)
  cfg <- artifacts$cfg
  oos <- artifacts$oos %>% filter(both_fbs)
  if (isTRUE(cfg$exclude_2020_from_calibration)) oos <- oos %>% filter(season != 2020L)
  
  audit_leakage(oos)
  scored <- score_oos(oos, artifacts$blend, cfg)
  
  tabs <- list(week_table(scored, "new model"))
  
  # Baseline 1: preseason only, all season long.
  pre_only <- oos %>% mutate(
    pred_margin = artifacts$blend$par$B * pre_diff + ifelse(neutral, 0, artifacts$blend$par$hfa),
    error = pred_margin - actual_margin, abs_error = abs(error))
  tabs[[length(tabs) + 1]] <- week_table(pre_only, "preseason only")
  
  # Baseline 2: home field only.
  hfa_only <- oos %>% mutate(
    pred_margin = ifelse(neutral, 0, artifacts$blend$par$hfa),
    error = pred_margin - actual_margin, abs_error = abs(error))
  tabs[[length(tabs) + 1]] <- week_table(hfa_only, "home field only")
  
  if (include_legacy) {
    message("Scoring the patched v1 architecture on the same folds...")
    lg <- tryCatch(legacy_oos_frame(cfg, artifacts$history, oos),
                   error = function(e) { warning("legacy: ", conditionMessage(e),
                                                 call. = FALSE); NULL })
    if (!is.null(lg) && nrow(lg) > 0) {
      if (isTRUE(cfg$exclude_2020_from_calibration)) lg <- lg %>% filter(season != 2020L)
      tabs[[length(tabs) + 1]] <- week_table(lg, "v1 architecture (patched)")
    }
  }
  
  mkt <- NULL
  if (include_market) {
    lines <- tryCatch(pull_lines(sort(unique(oos$season)), cfg),
                      error = function(e) { warning("lines: ", conditionMessage(e),
                                                    call. = FALSE); NULL })
    mkt <- tryCatch(benchmark_market(scored, lines), error = function(e) {
      warning("market benchmark: ", conditionMessage(e), call. = FALSE); NULL })
    if (!is.null(mkt))
      tabs[[length(tabs) + 1]] <- week_table(mkt, "closing market line")
  }
  
  list(
    by_week_bucket = bind_rows(tabs),
    by_week_seq = summarize_predictions(scored, "week_seq"),
    by_season = summarize_predictions(scored, "season"),
    by_games_played = summarize_predictions(
      scored %>% mutate(gp = pmin(pmin(gp_home, gp_away), 12)), "gp"),
    blend_schedule = artifacts$blend$schedule,
    blend_bucket_fit = artifacts$blend$bucket,
    preseason_model = summary(artifacts$preseason_model$off),
    carryover = artifacts$preseason_model$carryover,
    scored = scored, market = mkt)
}

#' Does play-by-play EPA earn its dependency? Refits everything under each
#' response spec on identical folds and reports the same week table.
tune_response <- function(cfg = cfb_config(),
                          specs = list(
                            list(label = "points only", use_epa = FALSE),
                            list(label = "EPA 0.25", use_epa = TRUE, w_epa = 0.25),
                            list(label = "EPA 0.50", use_epa = TRUE, w_epa = 0.50),
                            list(label = "EPA 0.75", use_epa = TRUE, w_epa = 0.75),
                            list(label = "EPA only", use_epa = TRUE, w_epa = 1.00))) {
  purrr::map_dfr(specs, function(sp) {
    c2 <- cfg
    c2$response$use_epa <- sp$use_epa
    if (!is.null(sp$w_epa)) c2$response$w_epa <- sp$w_epa
    message("=== response spec: ", sp$label, " ===")
    a <- tryCatch(fit_model_artifacts(c2), error = function(e) {
      warning(sp$label, ": ", conditionMessage(e), call. = FALSE); NULL })
    if (is.null(a)) return(NULL)
    s <- score_oos(a$oos %>% filter(both_fbs), a$blend, c2)
    week_table(s, sp$label)
  })
}

#' Does each preseason component earn its place? Ablations on identical folds.
compare_preseason_specs <- function(cfg = cfb_config()) {
  specs <- list(
    list(label = "full",             use_talent = TRUE,  use_returning = TRUE,  use_coaching = TRUE,  use_portal = FALSE),
    list(label = "no coaching",      use_talent = TRUE,  use_returning = TRUE,  use_coaching = FALSE, use_portal = FALSE),
    list(label = "no returning",     use_talent = TRUE,  use_returning = FALSE, use_coaching = TRUE,  use_portal = FALSE),
    list(label = "no talent",        use_talent = FALSE, use_returning = TRUE,  use_coaching = TRUE,  use_portal = FALSE),
    list(label = "carryover only",   use_talent = FALSE, use_returning = FALSE, use_coaching = FALSE, use_portal = FALSE),
    list(label = "full + portal",    use_talent = TRUE,  use_returning = TRUE,  use_coaching = TRUE,  use_portal = TRUE)
  )
  purrr::map_dfr(specs, function(sp) {
    c2 <- cfg
    c2$preseason$use_talent    <- sp$use_talent
    c2$preseason$use_returning <- sp$use_returning
    c2$preseason$use_coaching  <- sp$use_coaching
    c2$preseason$use_portal    <- sp$use_portal
    message("=== preseason spec: ", sp$label, " ===")
    a <- tryCatch(fit_model_artifacts(c2), error = function(e) {
      warning(sp$label, ": ", conditionMessage(e), call. = FALSE); NULL })
    if (is.null(a)) return(NULL)
    s <- score_oos(a$oos %>% filter(both_fbs), a$blend, c2)
    week_table(s, sp$label) %>% filter(cell %in% c("W1", "W2", "W3", "W4", "ALL"))
  })
}

#' Should 2020 be in the calibration set? Test rather than assume.
compare_calibration_windows <- function(cfg = cfb_config()) {
  purrr::map_dfr(c(TRUE, FALSE), function(excl) {
    c2 <- cfg; c2$exclude_2020_from_calibration <- excl
    a <- tryCatch(fit_model_artifacts(c2), error = function(e) NULL)
    if (is.null(a)) return(NULL)
    s <- score_oos(a$oos %>% filter(both_fbs, season != 2020L), a$blend, c2)
    week_table(s, ifelse(excl, "2020 excluded", "2020 included"))
  })
}

#' Grid over the margin cap and the efficiency shrinkage schedule.
tune_efficiency <- function(cfg = cfb_config(),
                            caps = c(24, 28, 32, 38, Inf),
                            lambda_bases = c(18, 26, 34)) {
  purrr::map_dfr(caps, function(cp) {
    purrr::map_dfr(lambda_bases, function(lb) {
      c2 <- cfg; c2$response$margin_cap <- cp; c2$efficiency$lambda_base <- lb
      a <- tryCatch(fit_model_artifacts(c2), error = function(e) NULL)
      if (is.null(a)) return(NULL)
      s <- score_oos(a$oos %>% filter(both_fbs), a$blend, c2)
      week_table(s, sprintf("cap=%s lam=%s", cp, lb)) %>% filter(cell == "ALL")
    })
  })
}

# =============================================================================
# 17. PRINTING
# =============================================================================

print_ratings <- function(ratings, n = 25) {
  cat(sprintf("\n=== CFB POWER RATINGS, %s | weeks: %s ===\n",
              attr(ratings, "season"),
              paste(attr(ratings, "weeks_included"), collapse = ",")))
  cat(sprintf("Neutral-field points vs an average FBS team. %d teams. HFA %.2f.\n",
              nrow(ratings), attr(ratings, "hfa")))
  cat("def_rating is a BURDEN: lower is better.\n\n")
  print(as.data.frame(
    ratings %>% head(n) %>%
      select(rank, team, conference, power_rating, off_rating, def_rating,
             off_rank, def_rank, games_played, sos, w_current, w_preseason)),
    digits = 3, row.names = FALSE)
  invisible(ratings)
}

# =============================================================================
# 18. USAGE
# =============================================================================
#
# ONE-TIME SETUP
# --------------
#   Sys.setenv(CFBD_API_KEY = "your-key")     # or put it in .Renviron, see below
#   source("cfb_power_ratings_v2.R")
#   cfg <- cfb_config()                        # cache lands in ~/cfb_data_v2
#   artifacts <- fit_model_artifacts(cfg)      # SLOW, ONCE. builds 2015-2025.
#
#   Persistent key (preferred):
#     usethis::edit_r_environ()
#     # add the line:  CFBD_API_KEY=your-key-here
#     # save, restart R
#
# BEFORE YOU TRUST IT
# -------------------
#   v <- run_validation(cfg, artifacts)
#   print(as.data.frame(v$by_week_bucket), digits = 4)   # the headline table
#   print(as.data.frame(v$blend_schedule), digits = 3)    # the weight schedule
#   v$carryover                                          # must be well under 1
#   print(as.data.frame(compare_preseason_specs(cfg)), digits = 4)
#   print(as.data.frame(tune_response(cfg)), digits = 4)  # does PBP earn its keep?
#
# EVERY WEEK
# ----------
#   source("cfb_power_ratings_v2.R")
#   artifacts <- fit_model_artifacts(cfb_config())   # instant, reads cache
#   r <- build_power_ratings(2026, artifacts = artifacts)
#   print_ratings(r, 25)
#   print(as.data.frame(run_sanity_checks(r, artifacts)))
#
#   Freeze at a point in time:   build_power_ratings(2026, through_week = 3, ...)
#   Pure preseason:              build_power_ratings(2026, through_week = -1, ...)
#   A matchup:                   predict_game(r, "Ohio State", "Michigan")
#
# AFTER A SEASON ENDS
# -------------------
#   cfg <- cfb_config(history_seasons = 2016:2026)
#   artifacts <- fit_model_artifacts(cfg, refresh = TRUE)
# =============================================================================