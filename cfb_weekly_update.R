# =============================================================================
# CFB WEEKLY UPDATE
#
# Run ONE function every Sunday after games finish:
#
#     run_sunday_update(2026)
#
# This does NOT re-run the full research pipeline (3-season lambda search +
# validation + benchmarks) that run_worked_example() does. That pipeline is
# for auditing the model, not for a weekly refresh, and re-running it every
# week is exactly why this was slow:
#   * compute_ratings() re-searches lambda by walk-forward CV, from scratch,
#     for EVERY season, EVERY time it's called.
#   * walk_forward_validate() calls compute_ratings() again internally to
#     build history -- a second full 3-season refit.
#   * benchmark_models() calls walk_forward_validate() six more times.
#   That's 8+ full 3-season refits to print one table.
#
# What this file does instead:
#   1. Fits the trailing COMPLETED seasons (e.g. 2023-2025) ONCE and caches
#      the result to disk. Those seasons are finished; their ratings never
#      change, so there is no reason to ever refit them again.
#   2. Every week, pulls ONLY the current season's data (not three seasons),
#      and only the PBP for weeks not already cached, if you have a
#      CFBD_API_KEY set (the no-key loader used elsewhere in this project,
#      load_cfb_pbp(), has no way to ask for a single week -- it always
#      returns the whole season, so without a key this step re-pulls the
#      current season's file, which is still 1 season instead of 3).
#   3. Reuses the current season's already-selected lambda instead of
#      re-searching the grid every week -- pass refit_lambda = TRUE
#      occasionally (e.g. monthly) if you want it re-tuned as more games
#      accumulate.
#   4. Fits ONLY the current season and saves a dated snapshot plus a
#      "latest" file, so you can see week-over-week movers.
#
# SETUP (once):
#   1. Put this file in the same folder as cfb_power_ratings.R (or fix
#      MODEL_SCRIPT_PATH below).
#   2. Set CFB_DATA_DIR below to a REAL, PERSISTENT folder -- not tempdir().
#      tempdir() is wiped when R restarts, which would silently blow away
#      your cached history, lambda choices, and weekly snapshots and make
#      every run slow again. This is the single most important setting here.
#   3. Optionally: Sys.setenv(CFBD_API_KEY = "your_key") for true
#      week-by-week incremental PBP pulls instead of whole-season re-pulls.
#
# WEEKLY USE:
#   source("cfb_weekly_update.R")
#   run_sunday_update(2026)
# =============================================================================

MODEL_SCRIPT_PATH <- "cfb_power_ratings_functions.R"   # adjust to your filename
CFB_DATA_DIR       <- path.expand(Sys.getenv("CFB_DATA_DIR", "cfb_data"))

source(MODEL_SCRIPT_PATH)
dir.create(CFB_DATA_DIR, recursive = TRUE, showWarnings = FALSE)

# -----------------------------------------------------------------------------
# 1. INCREMENTAL PBP FOR THE CURRENT (IN-PROGRESS) SEASON
# -----------------------------------------------------------------------------

#' Fetch only the weeks of PBP not already cached for `season`.
#'
#' With CFBD_API_KEY set: fetches week-by-week via the live API
#' (cfbd_pbp_data(year, week=)) and appends only NEW weeks to a running
#' cache -- this is the actual "just pull last week's game" behavior you
#' asked for.
#'
#' Without a key: load_cfb_pbp() cannot be asked for a single week, so this
#' degrades to re-pulling the whole current season (NOT all three) each
#' time. Slower than the incremental path but still far cheaper than the
#' full multi-season pipeline, and correct.
pull_pbp_incremental <- function(season, cache_dir = CFB_DATA_DIR, max_week = 20) {
  require_cfbfastR()
  cache_file <- file.path(cache_dir, paste0("pbp_live_", season, ".rds"))
  existing   <- if (file.exists(cache_file)) readRDS(cache_file) else NULL
  have_weeks <- if (!is.null(existing)) sort(unique(existing$week)) else integer(0)
  
  has_key <- nchar(Sys.getenv("CFBD_API_KEY")) > 0
  if (!has_key) {
    message("No CFBD_API_KEY set -- cannot fetch single weeks from the live API. ",
            "Re-pulling the full ", season, " season via load_cfb_pbp() (still ",
            "just 1 season, not 3). Set Sys.setenv(CFBD_API_KEY = \"...\") for ",
            "true week-by-week incremental updates.")
    full <- cfbfastR::load_cfb_pbp(seasons = season)
    safe_cache_write(full, cache_file)
    return(standardize_pbp_columns(full))
  }
  
  new_weeks <- setdiff(seq_len(max_week), have_weeks)
  fetched <- list()
  for (w in new_weeks) {
    wk_df <- tryCatch(
      cfbfastR::cfbd_pbp_data(year = season, week = w, epa_wpa = TRUE),
      error = function(e) NULL
    )
    if (is.null(wk_df) || nrow(wk_df) == 0) {
      message("No data for week ", w, " yet -- stopping (", length(fetched),
              " new week(s) fetched).")
      break
    }
    message("Fetched week ", w, " (", nrow(wk_df), " plays).")
    fetched[[length(fetched) + 1]] <- wk_df
  }
  
  combined <- dplyr::bind_rows(existing, fetched)
  if (nrow(combined) == 0) {
    stop("pull_pbp_incremental(): no play-by-play available yet for season ",
         season, ". Has week 1 finished?")
  }
  safe_cache_write(combined, cache_file)
  standardize_pbp_columns(combined)
}

# -----------------------------------------------------------------------------
# 2. FROZEN HISTORY FOR COMPLETED SEASONS (COMPUTED ONCE, CACHED FOREVER)
# -----------------------------------------------------------------------------

#' Ratings for completed prior seasons. This is the expensive step (one
#' walk-forward lambda search per season) -- it is cached to disk and should
#' basically never re-run once your season window is set. Only pass
#' force = TRUE if you deliberately want to rebuild it (e.g. once a new
#' season completes and you're rolling the trailing window forward).
build_history_ratings <- function(seasons, cfg = default_config(),
                                  cache_dir = CFB_DATA_DIR, force = FALSE) {
  cache_file <- file.path(cache_dir, paste0("history_ratings_",
                                            min(seasons), "_", max(seasons), ".rds"))
  if (!force && file.exists(cache_file)) {
    message("History ratings for ", min(seasons), "-", max(seasons),
            " loaded from cache. Pass force = TRUE to rebuild.")
    return(readRDS(cache_file))
  }
  
  message("Building history ratings for ", min(seasons), "-", max(seasons),
          " -- this is the slow step, but it only happens once.")
  cfg$cache_dir <- cache_dir
  pbp       <- pull_pbp_data(seasons, cache_dir = cache_dir)
  games     <- pull_game_results(seasons, cache_dir = cache_dir, pbp = pbp)
  team_meta <- pull_team_metadata(seasons, cache_dir = cache_dir)
  talent    <- tryCatch(pull_talent_data(seasons, cache_dir = cache_dir),
                        error = function(e) NULL)
  tg        <- build_team_game_units(pbp, games, team_meta, cfg)
  ratings   <- compute_ratings(tg, talent, cfg, team_meta)
  
  out <- list(ratings = ratings, team_meta = team_meta,
              hfa_by_season = attr(ratings, "hfa_by_season"),
              built_at = Sys.time())
  safe_cache_write(out, cache_file)
  out
}

# -----------------------------------------------------------------------------
# 3. THE WEEKLY REFIT (CURRENT SEASON ONLY)
# -----------------------------------------------------------------------------

#' Refit only the current season, using the frozen history for the preseason
#' prior. This is the function that should be fast: no 3-season refit, no
#' repeated lambda search unless you ask for one.
weekly_update <- function(current_season,
                          history_seasons = (current_season - 3):(current_season - 1),
                          cfg = default_config(),
                          refit_lambda = FALSE,
                          data_dir = CFB_DATA_DIR) {
  
  t0 <- Sys.time()
  cfg$cache_dir <- data_dir
  
  hist <- build_history_ratings(history_seasons, cfg, cache_dir = data_dir)
  
  pbp_cur   <- pull_pbp_incremental(current_season, cache_dir = data_dir)
  games_cur <- pull_game_results(current_season, use_cache = FALSE,
                                 cache_dir = data_dir, pbp = pbp_cur)
  team_meta <- pull_team_metadata(current_season, cache_dir = data_dir)
  talent    <- tryCatch(pull_talent_data(current_season, cache_dir = data_dir),
                        error = function(e) NULL)
  
  tg_cur <- build_team_game_units(pbp_cur, games_cur, team_meta, cfg)
  if (nrow(tg_cur) == 0) {
    stop("No games found yet for season ", current_season, ".")
  }
  latest_week <- max(tg_cur$time_index)
  message(sprintf("Season %d: %d games through week %d.",
                  current_season, dplyr::n_distinct(tg_cur$game_id), latest_week))
  
  rating_teams <- sort(unique(c(tg_cur$team, tg_cur$opponent)))
  prior <- build_preseason_prior(
    target_season = current_season,
    history_ratings = hist$ratings %>% select(season, team, power_rating),
    talent_data = talent, rating_teams = rating_teams,
    team_id_lookup = NULL, cfg = cfg
  )
  fbs_teams <- resolve_fbs_teams(team_meta, rating_teams)
  
  # --- lambda: cache per season; only re-search when explicitly asked
  lambda_file <- file.path(data_dir, paste0("lambda_", current_season, ".rds"))
  lam <- if (!refit_lambda && file.exists(lambda_file)) {
    readRDS(lambda_file)
  } else {
    l <- select_lambda_walkforward(tg_cur, prior, cfg, fbs_teams = fbs_teams)
    saveRDS(l, lambda_file)
    l
  }
  
  tg_full <- build_response(tg_cur, seq_len(nrow(tg_cur)), cfg)
  fit <- fit_points_model(tg_full, prior, cfg, lambda = lam, fbs_teams = fbs_teams)
  pr  <- setNames(fit$power_rating, fit$teams)
  
  sched <- tg_full %>%
    mutate(opp_rating = coalesce(pr[opponent], NA_real_),
           margin = points_for - points_against,
           hfa_term = if_else(neutral, 0, if_else(is_home, 1, -1)) * fit$hfa) %>%
    group_by(team) %>%
    summarise(games_played = n(), raw_margin_pg = mean(margin),
              avg_opponent_rating = mean(opp_rating, na.rm = TRUE),
              strength_of_schedule = mean(opp_rating - hfa_term, na.rm = TRUE),
              .groups = "drop")
  
  ratings_cur <- tibble(
    season = current_season, team = fit$teams,
    power_rating = fit$power_rating, offensive_rating = fit$offensive_rating,
    defensive_rating = fit$defensive_rating, rating_se = fit$rating_se,
    prior_weight = fit$prior_weight, is_fbs = fit$is_fbs
  ) %>%
    left_join(sched, by = "team") %>%
    left_join(prior, by = "team") %>%
    mutate(schedule_adjustment = power_rating - raw_margin_pg,
           as_of_week = latest_week, updated_at = Sys.time()) %>%
    filter(games_played > 0) %>%
    arrange(desc(power_rating))
  
  # --- persist a dated snapshot + overwrite "latest"; diff against last week
  latest_file <- file.path(data_dir, paste0("ratings_", current_season, "_latest.rds"))
  prev <- if (file.exists(latest_file)) readRDS(latest_file) else NULL
  
  snap_file <- file.path(data_dir,
                         sprintf("ratings_%d_wk%02d.rds", current_season, latest_week))
  saveRDS(ratings_cur, snap_file)
  saveRDS(ratings_cur, latest_file)
  
  movers <- if (!is.null(prev) && nrow(prev) > 0 && prev$as_of_week[1] < latest_week) {
    ratings_cur %>%
      select(team, power_rating, games_played) %>%
      inner_join(prev %>% select(team, prev_rating = power_rating), by = "team") %>%
      mutate(change = power_rating - prev_rating) %>%
      arrange(desc(abs(change)))
  } else NULL
  
  message(sprintf("weekly_update() finished in %.1f sec (lambda = %s, HFA = %.2f).",
                  as.numeric(Sys.time() - t0, units = "secs"), lam, fit$hfa))
  
  list(ratings = ratings_cur, movers = movers, lambda = lam,
       hfa = fit$hfa, latest_week = latest_week, season = current_season)
}

# =============================================================================
# 4. REPORTING & VISUALIZATION
# =============================================================================

#' Map team names to logo URLs. Uses ESPN's CDN for high-quality official logos.
#' Falls back to a placeholder if the team isn't found (rare).
get_team_logo <- function(team) {
  # Curated mapping of CFB team names to ESPN logo URLs
  # These are high-quality official SVG/PNG logos from ESPN's CDN
  logos <- list(
    "Alabama" = "https://a.espncdn.com/media/motion/2016/0915/alabama.svg",
    "Arizona" = "https://a.espncdn.com/media/motion/2016/0915/arizona.svg",
    "Arizona State" = "https://a.espncdn.com/media/motion/2016/0915/asu.svg",
    "Arkansas" = "https://a.espncdn.com/media/motion/2016/0915/arkansas.svg",
    "Auburn" = "https://a.espncdn.com/media/motion/2016/0915/auburn.svg",
    "Baylor" = "https://a.espncdn.com/media/motion/2016/0915/baylor.svg",
    "Boston College" = "https://a.espncdn.com/media/motion/2016/0915/bc.svg",
    "Bowling Green" = "https://a.espncdn.com/media/motion/2016/0915/bowling-green.svg",
    "BYU" = "https://a.espncdn.com/media/motion/2016/0915/byu.svg",
    "Central Michigan" = "https://a.espncdn.com/media/motion/2016/0915/cmichigan.svg",
    "Cincinnati" = "https://a.espncdn.com/media/motion/2016/0915/cincinnati.svg",
    "Clemson" = "https://a.espncdn.com/media/motion/2016/0915/clemson.svg",
    "Colorado" = "https://a.espncdn.com/media/motion/2016/0915/colorado.svg",
    "Colorado State" = "https://a.espncdn.com/media/motion/2016/0915/csurams.svg",
    "Connecticut" = "https://a.espncdn.com/media/motion/2016/0915/connecticut.svg",
    "Duke" = "https://a.espncdn.com/media/motion/2016/0915/duke.svg",
    "East Carolina" = "https://a.espncdn.com/media/motion/2016/0915/ecarolina.svg",
    "Eastern Michigan" = "https://a.espncdn.com/media/motion/2016/0915/emichigan.svg",
    "Florida" = "https://a.espncdn.com/media/motion/2016/0915/florida.svg",
    "Florida State" = "https://a.espncdn.com/media/motion/2016/0915/floridast.svg",
    "Fresno State" = "https://a.espncdn.com/media/motion/2016/0915/fresnostate.svg",
    "Georgia" = "https://a.espncdn.com/media/motion/2016/0915/georgia.svg",
    "Georgia Tech" = "https://a.espncdn.com/media/motion/2016/0915/gatech.svg",
    "Hawai'i" = "https://a.espncdn.com/media/motion/2016/0915/hawaii.svg",
    "Houston" = "https://a.espncdn.com/media/motion/2016/0915/houston.svg",
    "Indiana" = "https://a.espncdn.com/media/motion/2016/0915/indiana.svg",
    "Iowa" = "https://a.espncdn.com/media/motion/2016/0915/iowa.svg",
    "Iowa State" = "https://a.espncdn.com/media/motion/2016/0915/iowast.svg",
    "Jacksonville State" = "https://a.espncdn.com/media/motion/2016/0915/jaxstate.svg",
    "Kansas" = "https://a.espncdn.com/media/motion/2016/0915/kansas.svg",
    "Kansas State" = "https://a.espncdn.com/media/motion/2016/0915/kansasst.svg",
    "Kentucky" = "https://a.espncdn.com/media/motion/2016/0915/kentucky.svg",
    "LSU" = "https://a.espncdn.com/media/motion/2016/0915/lsu.svg",
    "Louisville" = "https://a.espncdn.com/media/motion/2016/0915/louisville.svg",
    "Marshall" = "https://a.espncdn.com/media/motion/2016/0915/marshall.svg",
    "Memphis" = "https://a.espncdn.com/media/motion/2016/0915/memphis.svg",
    "Miami" = "https://a.espncdn.com/media/motion/2016/0915/miami.svg",
    "Michigan" = "https://a.espncdn.com/media/motion/2016/0915/michigan.svg",
    "Michigan State" = "https://a.espncdn.com/media/motion/2016/0915/michiganst.svg",
    "Middle Tennessee" = "https://a.espncdn.com/media/motion/2016/0915/middletenn.svg",
    "Minnesota" = "https://a.espncdn.com/media/motion/2016/0915/minnesota.svg",
    "Mississippi" = "https://a.espncdn.com/media/motion/2016/0915/mississippi.svg",
    "Mississippi State" = "https://a.espncdn.com/media/motion/2016/0915/mississippist.svg",
    "Missouri" = "https://a.espncdn.com/media/motion/2016/0915/missouri.svg",
    "Navy" = "https://a.espncdn.com/media/motion/2016/0915/navy.svg",
    "NC State" = "https://a.espncdn.com/media/motion/2016/0915/ncstate.svg",
    "Nebraska" = "https://a.espncdn.com/media/motion/2016/0915/nebraska.svg",
    "New Mexico" = "https://a.espncdn.com/media/motion/2016/0915/newmexico.svg",
    "New Mexico State" = "https://a.espncdn.com/media/motion/2016/0915/nmstate.svg",
    "North Carolina" = "https://a.espncdn.com/media/motion/2016/0915/unc.svg",
    "North Dakota State" = "https://a.espncdn.com/media/motion/2016/0915/ndakotast.svg",
    "Northern Illinois" = "https://a.espncdn.com/media/motion/2016/0915/niu.svg",
    "Northwestern" = "https://a.espncdn.com/media/motion/2016/0915/northwestern.svg",
    "Notre Dame" = "https://a.espncdn.com/media/motion/2016/0915/notredame.svg",
    "Ohio" = "https://a.espncdn.com/media/motion/2016/0915/ohio.svg",
    "Ohio State" = "https://a.espncdn.com/media/motion/2016/0915/ohiostate.svg",
    "Oklahoma" = "https://a.espncdn.com/media/motion/2016/0915/oklahoma.svg",
    "Oklahoma State" = "https://a.espncdn.com/media/motion/2016/0915/oklahomastate.svg",
    "Ole Miss" = "https://a.espncdn.com/media/motion/2016/0915/olemiss.svg",
    "Oregon" = "https://a.espncdn.com/media/motion/2016/0915/oregon.svg",
    "Oregon State" = "https://a.espncdn.com/media/motion/2016/0915/oregonst.svg",
    "Penn State" = "https://a.espncdn.com/media/motion/2016/0915/pennstate.svg",
    "Pitt" = "https://a.espncdn.com/media/motion/2016/0915/pitt.svg",
    "Purdue" = "https://a.espncdn.com/media/motion/2016/0915/purdue.svg",
    "Rutgers" = "https://a.espncdn.com/media/motion/2016/0915/rutgers.svg",
    "San Diego State" = "https://a.espncdn.com/media/motion/2016/0915/sdstate.svg",
    "San José State" = "https://a.espncdn.com/media/motion/2016/0915/sjsu.svg",
    "SMU" = "https://a.espncdn.com/media/motion/2016/0915/smu.svg",
    "South Carolina" = "https://a.espncdn.com/media/motion/2016/0915/southcarolina.svg",
    "South Florida" = "https://a.espncdn.com/media/motion/2016/0915/southflorida.svg",
    "Southern Miss" = "https://a.espncdn.com/media/motion/2016/0915/southmiss.svg",
    "Stanford" = "https://a.espncdn.com/media/motion/2016/0915/stanford.svg",
    "Syracuse" = "https://a.espncdn.com/media/motion/2016/0915/syracuse.svg",
    "TCU" = "https://a.espncdn.com/media/motion/2016/0915/tcu.svg",
    "Temple" = "https://a.espncdn.com/media/motion/2016/0915/temple.svg",
    "Tennessee" = "https://a.espncdn.com/media/motion/2016/0915/tennessee.svg",
    "Texas" = "https://a.espncdn.com/media/motion/2016/0915/texas.svg",
    "Texas A&M" = "https://a.espncdn.com/media/motion/2016/0915/texasam.svg",
    "Texas Tech" = "https://a.espncdn.com/media/motion/2016/0915/texastech.svg",
    "Toledo" = "https://a.espncdn.com/media/motion/2016/0915/toledo.svg",
    "Troy" = "https://a.espncdn.com/media/motion/2016/0915/troy.svg",
    "Tulane" = "https://a.espncdn.com/media/motion/2016/0915/tulane.svg",
    "Tulsa" = "https://a.espncdn.com/media/motion/2016/0915/tulsa.svg",
    "UCF" = "https://a.espncdn.com/media/motion/2016/0915/ucf.svg",
    "UCLA" = "https://a.espncdn.com/media/motion/2016/0915/ucla.svg",
    "UNLV" = "https://a.espncdn.com/media/motion/2016/0915/unlv.svg",
    "USC" = "https://a.espncdn.com/media/motion/2016/0915/usc.svg",
    "Utah" = "https://a.espncdn.com/media/motion/2016/0915/utah.svg",
    "Utah State" = "https://a.espncdn.com/media/motion/2016/0915/utahstate.svg",
    "Vanderbilt" = "https://a.espncdn.com/media/motion/2016/0915/vanderbilt.svg",
    "Virginia" = "https://a.espncdn.com/media/motion/2016/0915/virginia.svg",
    "Virginia Tech" = "https://a.espncdn.com/media/motion/2016/0915/vatech.svg",
    "Wake Forest" = "https://a.espncdn.com/media/motion/2016/0915/wakeforest.svg",
    "Washington" = "https://a.espncdn.com/media/motion/2016/0915/washington.svg",
    "Washington State" = "https://a.espncdn.com/media/motion/2016/0915/washingtonst.svg",
    "West Virginia" = "https://a.espncdn.com/media/motion/2016/0915/wvirginia.svg",
    "Western Kentucky" = "https://a.espncdn.com/media/motion/2016/0915/wkentucky.svg",
    "Western Michigan" = "https://a.espncdn.com/media/motion/2016/0915/wmichigan.svg",
    "Wisconsin" = "https://a.espncdn.com/media/motion/2016/0915/wisconsin.svg",
    "Wyoming" = "https://a.espncdn.com/media/motion/2016/0915/wyoming.svg"
  )
  # Vectorized lookup: mutate() passes the whole `team` column at once, not
  # one name at a time, so this must handle a vector, not a scalar.
  result <- rep("https://a.espncdn.com/media/motion/2016/0915/ncaa.svg", length(team))
  matched <- team %in% names(logos)
  result[matched] <- unlist(logos[team[matched]], use.names = FALSE)
  result
}

#' Generate an HTML report with team logos, styled for sharing.
#'
#' Produces a beautiful standalone HTML file with inline CSS. No dependencies
#' needed; open in any browser or email the file directly.
generate_html_report <- function(result, n = 25, n_movers = 10,
                                 output_file = NULL, data_dir = CFB_DATA_DIR) {
  if (is.null(output_file)) {
    output_file <- file.path(data_dir,
                             sprintf("report_%d_wk%02d.html", 
                                     result$season, result$latest_week))
  }
  
  ratings_top <- result$ratings %>%
    filter(is_fbs) %>%
    arrange(desc(power_rating)) %>%
    head(n) %>%
    mutate(rank = row_number(),
           logo = get_team_logo(team))
  
  # Build the HTML
  html <- sprintf('<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>CFB Power Ratings - Week %d</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      background: linear-gradient(135deg, #667eea 0%%, #764ba2 100%%);
      min-height: 100vh;
      padding: 20px;
    }
    .container {
      max-width: 1200px;
      margin: 0 auto;
    }
    .header {
      text-align: center;
      color: white;
      margin-bottom: 40px;
      padding: 30px 20px;
    }
    .header h1 {
      font-size: 2.5em;
      margin-bottom: 10px;
      font-weight: 700;
    }
    .header p {
      font-size: 1.1em;
      opacity: 0.9;
    }
    .ratings-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
      gap: 15px;
      margin-bottom: 40px;
    }
    .rating-card {
      background: white;
      border-radius: 12px;
      padding: 20px;
      box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
      transition: transform 0.2s, box-shadow 0.2s;
      display: flex;
      flex-direction: column;
    }
    .rating-card:hover {
      transform: translateY(-2px);
      box-shadow: 0 8px 12px rgba(0, 0, 0, 0.15);
    }
    .card-header {
      display: flex;
      align-items: center;
      margin-bottom: 15px;
      gap: 15px;
    }
    .card-rank {
      font-size: 1.8em;
      font-weight: 700;
      color: #667eea;
      min-width: 40px;
      text-align: center;
    }
    .card-logo {
      width: 60px;
      height: 60px;
      object-fit: contain;
      flex-shrink: 0;
    }
    .card-team {
      flex: 1;
    }
    .card-team-name {
      font-size: 1.2em;
      font-weight: 600;
      color: #333;
      margin-bottom: 4px;
    }
    .card-record {
      font-size: 0.85em;
      color: #999;
    }
    .rating-main {
      font-size: 2.2em;
      font-weight: 700;
      color: #667eea;
      margin-bottom: 12px;
      text-align: center;
    }
    .rating-main.positive { color: #10b981; }
    .rating-main.negative { color: #ef4444; }
    .stats {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 10px;
      font-size: 0.9em;
      border-top: 1px solid #e5e7eb;
      padding-top: 12px;
    }
    .stat-row {
      display: flex;
      justify-content: space-between;
    }
    .stat-label {
      color: #666;
      font-weight: 500;
    }
    .stat-value {
      color: #333;
      font-weight: 600;
    }
    .movers-section {
      background: white;
      border-radius: 12px;
      padding: 30px;
      box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
    }
    .movers-section h2 {
      color: #333;
      margin-bottom: 20px;
      font-size: 1.5em;
    }
    .mover-item {
      display: flex;
      align-items: center;
      padding: 12px 0;
      border-bottom: 1px solid #e5e7eb;
    }
    .mover-item:last-child { border-bottom: none; }
    .mover-logo {
      width: 50px;
      height: 50px;
      object-fit: contain;
      margin-right: 15px;
      flex-shrink: 0;
    }
    .mover-info {
      flex: 1;
    }
    .mover-team {
      font-weight: 600;
      color: #333;
      font-size: 1em;
    }
    .mover-change {
      font-size: 1.3em;
      font-weight: 700;
      margin-right: 15px;
    }
    .mover-change.up { color: #10b981; }
    .mover-change.down { color: #ef4444; }
    .footer {
      text-align: center;
      color: white;
      margin-top: 40px;
      padding: 20px;
      font-size: 0.9em;
      opacity: 0.8;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>⚡ CFB Power Ratings</h1>
      <p>2026 Season • Week %d</p>
      <p style="font-size: 0.95em; margin-top: 8px; opacity: 0.9;">
        Points vs Average FBS on Neutral Field
      </p>
    </div>

    <div class="ratings-grid">
', result$latest_week, result$latest_week)
  
  # Add rating cards
  for (i in seq_len(nrow(ratings_top))) {
    row <- ratings_top[i, ]
    rating_class <- if (row$power_rating >= 0) "positive" else "negative"
    
    html <- paste0(html, sprintf('
      <div class="rating-card">
        <div class="card-header">
          <div class="card-rank">%d</div>
          <img class="card-logo" src="%s" alt="%s logo">
          <div class="card-team">
            <div class="card-team-name">%s</div>
            <div class="card-record">%d game(s)</div>
          </div>
        </div>
        <div class="rating-main %s">%+.1f</div>
        <div class="stats">
          <div class="stat-row">
            <span class="stat-label">Off Rating</span>
            <span class="stat-value">%+.1f</span>
          </div>
          <div class="stat-row">
            <span class="stat-label">Def Rating</span>
            <span class="stat-value">%+.1f</span>
          </div>
          <div class="stat-row">
            <span class="stat-label">SOS</span>
            <span class="stat-value">%+.1f</span>
          </div>
          <div class="stat-row">
            <span class="stat-label">Margin/Game</span>
            <span class="stat-value">%+.1f</span>
          </div>
        </div>
      </div>
',
                                 row$rank, row$logo, row$team, row$team, row$games_played,
                                 rating_class, row$power_rating,
                                 row$offensive_rating, row$defensive_rating,
                                 row$strength_of_schedule, row$raw_margin_pg))
  }
  
  html <- paste0(html, '
    </div>')
  
  # Add movers section if available
  if (!is.null(result$movers) && nrow(result$movers) > 0) {
    movers_top <- result$movers %>% head(n_movers)
    
    html <- paste0(html, '
    <div class="movers-section">
      <h2>📊 Biggest Movers</h2>')
    
    for (i in seq_len(nrow(movers_top))) {
      row <- movers_top[i, ]
      change_class <- if (row$change > 0) "up" else "down"
      arrow <- if (row$change > 0) "↑" else "↓"
      
      html <- paste0(html, sprintf('
      <div class="mover-item">
        <img class="mover-logo" src="%s" alt="%s logo">
        <div class="mover-info">
          <div class="mover-team">%s</div>
        </div>
        <div class="mover-change %s">%s %+.1f</div>
      </div>
', get_team_logo(row$team), row$team, row$team, change_class, arrow, row$change))
    }
    html <- paste0(html, '
    </div>')
  }
  
  html <- paste0(html, sprintf('
    <div class="footer">
      Generated %s | Model: Opponent-Adjusted, Prior-Stabilized Ridge Regression
    </div>
  </div>
</body>
</html>
', format(Sys.time(), "%%B %%d, %%Y at %%I:%%M %%p")))
  
  # Write file
  writeLines(html, output_file)
  message(sprintf("HTML report saved to: %s", output_file))
  output_file
}

print_weekly_report <- function(result, n = 25, n_movers = 10, 
                                html_output = TRUE, data_dir = CFB_DATA_DIR) {
  # Console output (backward compatible)
  cat(sprintf("\n===== TOP %d, %d WEEK %d =====\n", n, result$season, result$latest_week))
  print(as.data.frame(
    result$ratings %>% filter(is_fbs) %>% arrange(desc(power_rating)) %>%
      head(n) %>%
      select(team, power_rating, offensive_rating, defensive_rating,
             strength_of_schedule, raw_margin_pg, schedule_adjustment,
             games_played, rating_se)
  ), digits = 3)
  
  if (!is.null(result$movers) && nrow(result$movers) > 0) {
    cat(sprintf("\n===== BIGGEST MOVERS SINCE LAST UPDATE =====\n"))
    print(as.data.frame(head(result$movers, n_movers)), digits = 3)
  } else {
    cat("\n(No prior week's snapshot to compare against -- this is the first run.)\n")
  }
  
  # Generate HTML report if requested
  if (html_output) {
    html_file <- generate_html_report(result, n, n_movers, data_dir = data_dir)
    cat(sprintf("\n✨ Shareable HTML report: %s\n", basename(html_file)))
  }
  
  invisible(result)
}

# -----------------------------------------------------------------------------
# 5. THE ONE FUNCTION TO RUN EVERY SUNDAY
# -----------------------------------------------------------------------------

#' run_sunday_update(2026)
#'
#' First call of the season: builds the 3-season history (slow, one time),
#' fits 2026 on whatever games have happened, prints the top 25.
#' Every call after that: pulls only new weeks, refits only 2026, prints
#' the top 25 plus movers since last time. Should take seconds to low tens
#' of seconds once the history cache is warm, not minutes.
run_sunday_update <- function(season, refit_lambda = FALSE) {
  result <- weekly_update(current_season = season, refit_lambda = refit_lambda)
  print_weekly_report(result)
  invisible(result)
}
