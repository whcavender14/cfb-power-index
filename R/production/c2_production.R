# =====================================================================================================================
# R/production/c2_production.R: thin production adapter for Current C2.
#
# The model is R/c2/c2_current.R (tag c2-post-stage4-baseline), sourced and called UNCHANGED. c2_predict_season() does
# all the rating arithmetic. This adapter only:
#   1. loads the frozen season inputs (data/frozen/c2; MD5-verified; never recomputed here);
#   2. assembles the current season's data the way the frozen build assembled every historical season:
#        games = the live FBS schedule + CFBD's FCS-involved games (r15_full_games; Round 15 P1 field mapping);
#        play rows = success rate, fumbles, primary passer per game x offense (r15_build_data's per-season block);
#   3. returns C2's ratings in the incumbent's ratings schema, so downstream code is unchanged.
# Information rule (C2's own): only final games with available_at = kickoff + 24 h before the cutoff enter the solve.
# Two short blocks are copied because they are inline in frozen scripts, not functions:
#   * c2p_fcs_games(): the P1 mapping of scripts/round15/p1_pull_data.R;
#   * c2p_play_rows(): the per-season block of r15_build_data().
#   tests/production/test_c2_production.R proves both reproduce the frozen build's data exactly.
# Requires config/paths.R, config/production.R, config/production_model.R and PATHS$model_ops (sourced by the caller).
# =====================================================================================================================
suppressPackageStartupMessages({ library(data.table); library(Matrix) })

c2p_code_files <- function() file.path(PATHS$root, names(PRODUCTION_MODEL$c2$code_md5))

# Verify the frozen season inputs and every model code file against config/production_model.R (like v5_verify_frozen_inputs).
c2p_verify_frozen <- function() {
  paths <- c(file.path(PATHS$root, PRODUCTION_MODEL$c2$season_inputs), c2p_code_files())
  expected <- c(PRODUCTION_MODEL$c2$season_inputs_md5, unname(PRODUCTION_MODEL$c2$code_md5))
  actual <- unname(tools::md5sum(paths))
  data.frame(path = sub(paste0("^", PATHS$root, "/"), "", paths), expected_md5 = expected, actual_md5 = actual,
             ok = !is.na(actual) & actual == expected, stringsAsFactors = FALSE)
}

# Source the model (unchanged research code) once, after verifying it. The frozen helpers use project-relative paths.
c2p_load_model <- function() {
  v <- c2p_verify_frozen()
  if (!all(v$ok)) stop("Current C2 frozen input/code mismatch: ", paste(v$path[!v$ok], collapse = ", "), call. = FALSE)
  if (!exists("c2_predict_season", mode = "function")) {
    old <- setwd(PATHS$root); on.exit(setwd(old))
    for (f in c("R/round15/candidates/data.R", "R/round15/candidates/c1.R", "R/round15/candidates/c2.R", "R/c2/c2_current.R",
                "R/round15/prep/fumble_parser.R", "R/round15/prep/sr_history.R", "R/round15/prep/passer_parser.R", "R/round15/cfbd_client.R"))
      sys.source(f, envir = globalenv())
  }
  invisible(v)
}

c2p_season_inputs <- function(season) {
  if (!identical(as.integer(season), PRODUCTION_MODEL$c2$supported_season))
    stop("Current C2 has frozen season inputs for ", PRODUCTION_MODEL$c2$supported_season, " only; season ", season,
         " needs its own freeze (scripts/production/c2_freeze_season_inputs.R).", call. = FALSE)
  c2p_load_model()
  readRDS(file.path(PATHS$root, PRODUCTION_MODEL$c2$season_inputs))
}

# CFBD FCS-involved games of one season (regular + postseason), Round 15 P1 mapping, vendor fields dropped.
c2p_fcs_games <- function(season, cache_dir) {
  c2p_load_model()
  cl <- cfbd_client(cache_dir, max_calls = 4L)
  vendor <- "(?i)elo|win_?prob|winprob|excitement|linescores|highlights"
  fcs <- rbindlist(lapply(c("regular", "postseason"), function(st) {
    x <- cl$get("/games", list(year = season, seasonType = st, classification = "fcs")); if (!NROW(x)) return(NULL)
    x <- as.data.table(x); drop <- grep(vendor, names(x), perl = TRUE, value = TRUE)
    if (length(drop)) x[, (drop) := NULL]
    x[, .(game_id = as.character(id), season, week, season_type = seasonType, start_date = startDate, completed, neutral_site = neutralSite,
          home_id = homeId, home_team = homeTeam, home_division = homeClassification, home_conference = homeConference, home_points = homePoints,
          away_id = awayId, away_team = awayTeam, away_division = awayClassification, away_conference = awayConference, away_points = awayPoints)]
  }), fill = TRUE)
  if (!nrow(fcs)) stop("CFBD returned no FCS-involved games for ", season, ": refusing to rate without them.", call. = FALSE)
  unique(fcs, by = "game_id")
}

# Play-by-play of every week with a final FBS-involved game available before the cutoff (cfbfastR::cfbd_plays, the
# forward tool's source). One file per week in cache_dir; a cached week is reused, an empty pull stops the build.
c2p_pull_plays <- function(season, schedule, as_of, cache_dir) {
  wk <- unique(as.data.table(schedule)[final %in% TRUE & available_at < as_of & (home_fbs | away_fbs), .(season_type, week)])
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  rbindlist(lapply(seq_len(nrow(wk)), function(i) {
    f <- file.path(cache_dir, sprintf("plays_%s_wk%02d.rds", wk$season_type[i], wk$week[i]))
    if (!file.exists(f)) {
      x <- cfbfastR::cfbd_plays(year = season, season_type = wk$season_type[i], week = wk$week[i])
      if (!NROW(x)) stop(sprintf("Empty play-by-play pull for %d %s week %d", season, wk$season_type[i], wk$week[i]), call. = FALSE)
      saveRDS(x, f)
    }
    as.data.table(readRDS(f))[, `:=`(season = as.integer(season), wk = as.integer(wk$week[i]), season_type = wk$season_type[i])]
  }), fill = TRUE)
}

# Game x offense play rows for season y: r15_build_data()'s per-season block, verbatim (plays file + raw schedule).
c2p_play_rows <- function(plays_path, raw_schedule, y) {
  old <- setwd(PATHS$root); on.exit(setwd(old))    # the frozen SR code loads its vendored instrument by a project-relative path
  s <- r15_sr_season(plays_path, raw_schedule, y)
  p <- as.data.table(readRDS(plays_path))
  p <- p[, grep(r15_vendor_cols, names(p), invert = TRUE, perl = TRUE), with = FALSE]; p[, game_id := as.character(game_id)]
  fum <- grepl("Fumble", p$play_type); lost <- fum & grepl("Interception|Fumble Recovery \\(Opponent\\)|Fumble Return", p$play_type)
  fl <- p[, .(game_id, offense)][, `:=`(fum = fum, lost = lost)][, .(fumbles = sum(fum), lost = sum(lost)), by = .(game_id, offense)]
  d <- p[play_type %in% r15_dropback_types][, passer := r15_passer(play_text)][!is.na(passer)]
  qb <- d[, .N, by = .(game_id, offense, passer)][order(-N)][, .(passer = passer[1], dropbacks = N[1]), by = .(game_id, offense)]
  m <- merge(merge(s$means[, .(season = y, game_id, offense, defense, sr = success, sr_plays = plays)], fl, by = c("game_id", "offense"), all = TRUE), qb, by = c("game_id", "offense"), all = TRUE)
  m[, season := y]; m
}

# Assemble C2's season data object (the shape of r15_build_data()'s `d`, one season) and run c2_predict_season() at two
# cutoffs: before the first game (the preseason rating, C2's no-games branch) and `as_of`. `targets` (optional) are games
# to predict at `as_of` (FBS vs FBS). fcs_games / plays may be injected (forward archive, tests); else they are pulled.
# S: the frozen season inputs (default). Only the validation passes another season's canonical inputs to replay history.
c2p_run <- function(season, as_of, schedule, raw_schedule, cache_dir, fcs_games = NULL, plays = NULL, targets = NULL, S = NULL) {
  if (is.null(S)) S <- c2p_season_inputs(season) else c2p_load_model()
  y <- as.integer(season)
  as_of <- as.POSIXct(as_of, tz = "UTC"); stopifnot(length(as_of) == 1L, !is.na(as_of))
  if (is.null(fcs_games)) fcs_games <- c2p_fcs_games(y, cache_dir)
  fcs_games <- as.data.table(fcs_games)[season == y]
  S$dv <- rbind(S$dv[season != y], c2_divisions(fcs_games))          # current season's divisions from the same pull
  games <- r15_full_games(schedule, fcs_games)
  if (is.null(plays)) plays <- c2p_pull_plays(y, schedule, as_of, cache_dir)
  pfile <- tempfile(fileext = ".rds"); on.exit(unlink(pfile)); saveRDS(as.data.frame(plays), pfile)
  pbp <- c2p_play_rows(pfile, raw_schedule, y)

  # Fetch-completeness guard: a final FBS-vs-FBS game before the cutoff with NO plays in the pull means the pull is
  # broken. (Games whose plays the frozen SR instrument excludes are normal, about 4-6% historically, and only reported.)
  used <- games[final == TRUE & available_at < as_of]
  fbs_used <- used[home_fbs %in% TRUE & away_fbs %in% TRUE]
  no_pbp <- fbs_used[!game_id %in% as.character(plays$game_id), game_id]
  if (length(no_pbp) > PRODUCTION_MODEL$c2$max_missing_pbp_games)
    stop(sprintf("%d final FBS-vs-FBS games before the cutoff are missing from the play-by-play pull (limit %d): %s", length(no_pbp),
                 PRODUCTION_MODEL$c2$max_missing_pbp_games, paste(head(no_pbp, 10), collapse = ", ")), call. = FALSE)

  pre_cut <- min(c(games$available_at, as_of - 1), na.rm = TRUE)   # nothing is available before this: C2's no-games branch
  stopifnot(pre_cut < as_of, !any(games$available_at < pre_cut, na.rm = TRUE))
  frame <- if (is.null(targets)) data.table(season = integer(), game_id = character(), week = integer(), kickoff = as_of[0], neutral = logical(),
                                            home_id = integer(), away_id = integer(), cutoff = as_of[0]) else
    as.data.table(targets)[, .(season = y, game_id, week, kickoff, neutral, home_id, away_id, cutoff = as_of)]
  d <- list(sch = setNames(list(schedule), y), games = setNames(list(games), y), pbp = pbp,
            base = list(snap = list(list(season = y, cutoff = pre_cut), list(season = y, cutoff = as_of)), frame = frame))
  run <- c2_predict_season(d, y, S)
  list(pre = run[[1]], cur = run[[2]], S = S, games = games, pbp = pbp, d = d,
       coverage = list(games_used = nrow(used), fbs_vs_fbs_used = nrow(fbs_used), fbs_vs_fbs_missing_from_pull = no_pbp,
                       fbs_vs_fbs_without_sr_rows = fbs_used[!game_id %in% pbp[!is.na(sr), game_id], .N],
                       fbs_involved_without_sr_rows = used[(home_fbs | away_fbs) & !game_id %in% pbp[!is.na(sr), game_id], .N],
                       play_rows = nrow(pbp), fcs_games_pulled = nrow(fcs_games)))
}

# Non-FBS team powers at the cutoff (Stage 3 rule): the in-solve rating once a team has played, else its first-game
# rating (prior deviation + current group levels). This is the rule c2_fbs_vs_nonfbs() applies per game.
c2p_nonfbs_ratings <- function(x) {
  cur <- x$cur; g <- x$games
  nm <- unique(rbind(g[, .(team_id = home_id, team = home_team)], g[, .(team_id = away_id, team = away_team)]))[!duplicated(team_id)]
  nf <- merge(cur$first_game[, .(team_id, group, first_game_power = power)], cur$ratings[fbs == FALSE, .(team_id, in_solve_power = power, gp)],
              by = "team_id", all.x = TRUE)
  nf[, `:=`(power = fifelse(is.finite(in_solve_power), in_solve_power, first_game_power),
            source = fifelse(is.finite(in_solve_power), "in_solve", "first_game"), gp = fifelse(is.na(gp), 0L, gp))]
  nf[, team := nm$team[match(team_id, nm$team_id)]]
  as.data.frame(nf[, .(team_id, team, group, power, source, gp, in_solve_power, first_game_power)])
}

# Production entry point: C2 ratings at `as_of` in the incumbent's ratings schema (see v5_build()).
c2_production_build <- function(season, as_of, schedule, raw_schedule, cache_dir, fcs_games = NULL, plays = NULL, targets = NULL) {
  x <- c2p_run(season, as_of, schedule, raw_schedule, cache_dir, fcs_games, plays, targets)
  fb <- x$cur$ratings[fbs == TRUE]; ids <- fbs_ids(schedule)
  stopifnot(setequal(fb$team_id, ids), !anyDuplicated(fb$team_id), all(is.finite(fb$power)))
  memb <- as.data.table(v5_membership(schedule)); pre <- x$pre$ratings
  r <- data.frame(team_id = fb$team_id, team = memb$team[match(fb$team_id, memb$team_id)], conf = memb$conf[match(fb$team_id, memb$team_id)],
                  power_rating = fb$power, off_rating = fb$eff_off, def_rating = fb$eff_def, games_played = as.integer(fb$gp),
                  pre_power = pre$power[match(fb$team_id, pre$team_id)],
                  prior_contribution = NA_real_, current_contribution = NA_real_, centering_contribution = NA_real_,   # EB-only decomposition
                  feature_snapshot_id = NA_character_, stringsAsFactors = FALSE)
  stopifnot(!anyNA(r$team), all(is.finite(r$pre_power)))
  r <- r[order(-r$power_rating, r$team_id), ]; r$rank <- seq_len(nrow(r))
  r <- tibble::as_tibble(r)                                                   # the class v5_build() returns
  attr(r, "hfa") <- x$S$H
  attr(r, "as_of") <- as.POSIXct(as_of, tz = "UTC")
  attr(r, "training_ids") <- x$games[final == TRUE & available_at < as_of, game_id]
  attr(r, "candidate") <- PRODUCTION_MODEL$c2$candidate
  attr(r, "design_hash") <- PRODUCTION_MODEL$c2$season_inputs_md5
  attr(r, "feature_hash") <- PRODUCTION_MODEL$c2$code_md5[["R/c2/c2_current.R"]]
  attr(r, "model_version") <- PRODUCTION_MODEL$c2$research_tag
  attr(r, "sigma") <- PRODUCTION_MODEL$c2$sigma
  attr(r, "nonfbs_ratings") <- c2p_nonfbs_ratings(x)
  attr(r, "group_levels") <- as.data.frame(x$cur$levels)
  attr(r, "predictions") <- as.data.frame(x$cur$pred)
  attr(r, "data_coverage") <- x$coverage
  r
}
