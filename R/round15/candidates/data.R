# Round 15 candidate data layer. Builds (once) and caches every per-season input the candidates use.
# Market data are never read here (test L4). Vendor columns are dropped at read (test L5).
suppressPackageStartupMessages(library(data.table))
R15C <- list(history = 2013:2025, components = c(2016L, 2017L, 2018L, 2019L, 2021L, 2022L, 2023L, 2024L, 2025L),
             dev = c(2017L, 2018L, 2019L, 2021L, 2022L), cond = 2023:2025, cache = "output/dev/round15/cand",
             raw6 = "/Users/willcavender/Desktop/CFB Modeling Backup/CFB-Modeling-round6/outputs/round6/raw",
             frozen_hfa = 3.06853968902663)
r15_vendor_cols <- "(?i)(^|_)(ppa|epa|wpa|wp|elo)($|_)|win_?prob|excitement"

# The incumbent estimator re-bound to history 2013 (identical to Round 6 / scripts/round15/05).
r15_bind_incumbent <- function() {
  e <- new.env(parent = globalenv())
  e$v4_config <- function() cfb_config(cache_dir = "outputs/round3/cache", source_cache = "cfb_data_v3", history_seasons = 2013:2022, version = "7.0.0")
  e$v4_pre <- local({ f <- v4_pre; environment(f) <- e; f })
  src <- paste(deparse(v5_prior, width.cutoff = 500L), collapse = "\n")
  stopifnot(length(gregexpr("season\\s*>\\s*2015", src, perl = TRUE)[[1]]) == 1)
  e$v5_prior <- eval(parse(text = sub("season\\s*>\\s*2015", "season > min(v4_config()$history_seasons)", src, perl = TRUE)), envir = e); environment(e$v5_prior) <- e
  e$v4_components <- local({ f <- v4_components; environment(f) <- e; f })
  e$v5_components <- local({ f <- v5_components; environment(f) <- e; f })
  e
}
r15_schedule <- function(y) {
  if (y >= 2015) return(v4_schedule(y))
  cfg <- v4_config(); cfg$cache_dir <- R15C$raw6; cfg$source_cache <- R15C$raw6; read_schedule(y, cfg, FALSE)
}
# FBS-involved (frozen) plus FCS-involved (P1) games, parsed like read_schedule, vendor columns dropped.
r15_full_games <- function(g, fcs) {
  a <- as.data.table(g)[, .(game_id, season, kickoff, available_at, period, final, neutral, home_id, away_id, home_team, away_team,
                            home_fbs, away_fbs, home_points, away_points)]
  f <- fcs[season == a$season[1] & !game_id %in% a$game_id]
  if (nrow(f)) {
    k <- utc(f$start_date)
    b <- f[, .(game_id, season, kickoff = k, available_at = k + 24 * 3600, period = period_start(k), final = completed %in% TRUE & is.finite(home_points) & is.finite(away_points),
               neutral = as.logical(neutral_site), home_id = as.integer(home_id), away_id = as.integer(away_id), home_team, away_team,
               home_fbs = tolower(home_division) == "fbs", away_fbs = tolower(away_division) == "fbs", home_points, away_points)]
    a <- rbind(a, b)
  }
  a
}
r15_build_data <- function(force = FALSE) {
  f <- file.path(R15C$cache, "data.rds"); if (file.exists(f) && !force) return(readRDS(f))
  dir.create(R15C$cache, recursive = TRUE, showWarnings = FALSE)
  source("R/round15/prep/fumble_parser.R"); source("R/round15/prep/sr_history.R"); source("R/round15/prep/passer_parser.R")
  sch <- setNames(lapply(R15C$history, r15_schedule), R15C$history)
  history <- as.data.table(v4_history(sch))
  e <- r15_bind_incumbent()
  base <- e$v4_components(sch, as_tibble(history), R15C$components)
  feat <- v5_validate_features(readRDS(file.path(PATHS$frozen, "outputs/round4/features.rds"))$features, setNames(lapply(2015:2026, v4_schedule), 2015:2026))
  inc <- e$v5_components(base, as_tibble(history), feat, "full")
  pars <- setNames(lapply(R15C$dev, function(s) v5_fit_parameters(inc, base, v5_candidates()$EB_features, s)), R15C$dev)
  fcs <- as.data.table(readRDS("output/dev/round15/prep/fcs_schedules_2013_2025.rds"))
  games <- setNames(lapply(R15C$history, function(y) r15_full_games(sch[[as.character(y)]], fcs)), R15C$history)
  # play-derived per-game quantities (SR means per offense, fumble luck, primary passer), seasons 2014-2025
  pbp <- rbindlist(lapply(2014:2025, function(y) {
    s <- r15_sr_season(file.path(R15C$raw6, sprintf("plays_%d.rds", y)), readRDS(if (y >= 2015) file.path(PATHS$frozen, "cfb_data_v3", sprintf("raw_schedule_%d.rds", y)) else file.path(R15C$raw6, sprintf("raw_schedule_%d.rds", y))), y)
    p <- as.data.table(readRDS(file.path(R15C$raw6, sprintf("plays_%d.rds", y))))
    p <- p[, grep(r15_vendor_cols, names(p), invert = TRUE, perl = TRUE), with = FALSE]; p[, game_id := as.character(game_id)]
    fum <- grepl("Fumble", p$play_type); lost <- fum & grepl("Interception|Fumble Recovery \\(Opponent\\)|Fumble Return", p$play_type)
    fl <- p[, .(game_id, offense)][, `:=`(fum = fum, lost = lost)][, .(fumbles = sum(fum), lost = sum(lost)), by = .(game_id, offense)]
    d <- p[play_type %in% r15_dropback_types][, passer := r15_passer(play_text)][!is.na(passer)]
    qb <- d[, .N, by = .(game_id, offense, passer)][order(-N)][, .(passer = passer[1], dropbacks = N[1]), by = .(game_id, offense)]
    m <- merge(merge(s$means[, .(season = y, game_id, offense, defense, sr = success, sr_plays = plays)], fl, by = c("game_id", "offense"), all = TRUE), qb, by = c("game_id", "offense"), all = TRUE)
    m[, season := y]; message("pbp ", y); m }), fill = TRUE)
  out <- list(sch = sch, history = history, base = base, inc = inc, pars = pars, games = games, pbp = pbp,
              inputs = fread("output/dev/round15/prep/preseason_inputs_2014_2026.csv"),
              sr_eos = fread("output/dev/round15/prep/sr_end_of_season_2013_2025.csv"), features = feat)
  saveRDS(out, f); out
}

# C3 (Amendment 02): each team-game's primary passer(s), seasons 2014-2025. A game's primary is the passer with the most
# dropbacks (>= 10); passers tied for that count are all kept (co-primaries, "|"-joined, sorted) so no tie-break is needed.
r15_qb_primary <- function(force = FALSE) {
  f <- file.path(R15C$cache, "qb_primary.rds"); if (file.exists(f) && !force) return(readRDS(f))
  source("R/round15/prep/passer_parser.R")
  out <- rbindlist(lapply(2014:2025, function(y) {
    p <- as.data.table(readRDS(file.path(R15C$raw6, sprintf("plays_%d.rds", y))))[, .(game_id = as.character(game_id), offense, play_type, play_text)]
    n <- p[play_type %in% r15_dropback_types][, passer := r15_passer(play_text)][!is.na(passer)][, .N, by = .(game_id, offense, passer)]
    n[, mx := max(N), by = .(game_id, offense)][N == mx & mx >= 10, .(season = y, primary = paste(sort(passer), collapse = "|"), dropbacks = mx[1]), by = .(game_id, offense)] }))
  saveRDS(out, f); out
}
