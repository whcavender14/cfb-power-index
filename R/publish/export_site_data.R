# =============================================================================
# R/publish/export_site_data.R — the CFPi+ site's page datasets (public/data/v2).
#
# Reads ONLY pipeline outputs (production snapshot, simulation result, team
# metadata, committed week archives) and writes precomputed JSON. It never
# sources or changes the model. Every statistic the site shows is computed here;
# the browser only displays. Schema: docs/website/DATA_CONTRACT_V2.md.
# Derived metrics (spread, win probability, matchup quality, bid type,
# representative field): docs/website/DERIVED_METRICS.md.
#
# Files (all under public/data/v2/):
#   index.json               homepage + rankings (ranks, movement, odds, top games)
#   teams.json               team directory (slug, colors, logos)
#   games.json               every 2026 game: result or projection, matchup quality
#   playoff.json             playoff odds, seed distributions, representative field
#   team/<slug>.json         one file per FBS team (schedule, resume, record/seed distributions)
#   history.json             CFPi+ rating history (preseason, reconstructed and published weeks)
#   changes.json             what changed since the previous week (same history source as movement)
#   conferences.json         conference aggregates (membership from team metadata)
#   <season>/week-NN/index.json   weekly archive (kept if a different model published it)
# =============================================================================
suppressPackageStartupMessages(library(jsonlite))
if (!exists("PATHS")) source(file.path(Sys.getenv("CFB_PROJECT_ROOT", "."), "config", "paths.R"))

site_season <- as.integer(Sys.getenv("CFB_SEASON", "2026"))
site_state <- PATHS$state
site_out <- file.path(PATHS$public_data, "v2")
P4_CONFS <- c("SEC", "Big Ten", "ACC", "Big 12")
G6_CONFS <- c("American Athletic", "Conference USA", "Mid-American", "Mountain West", "Pac-12", "Sun Belt")

iso_utc <- function(x) if (length(x) && !is.na(x[1])) format(as.POSIXct(x[1], tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC") else NA_character_
read_opt <- function(p) if (file.exists(p)) readRDS(p) else NULL
# URL slug: the same on every OS (stringi's Latin-ASCII, not iconv, whose transliteration differs between macOS and
# Linux), apostrophes dropped, "&" -> "and", anything else -> "-". e.g. "San José State" -> "san-jose-state".
slugify <- function(x) {
  s <- tolower(stringi::stri_trans_general(x, "Latin-ASCII"))
  s <- gsub("['\u2019]", "", s)
  s <- gsub("&", " and ", s, fixed = TRUE)
  s <- gsub("[^a-z0-9]+", "-", s)
  gsub("^-+|-+$", "", s)
}
r4 <- function(x) round(x, 4)
pick <- function(df, id, col) if (is.null(df) || !col %in% names(df)) NA else df[[col]][match(id, df$team_id)]
write_site_json <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  write_json(x, path, auto_unbox = TRUE, na = "null", null = "null", digits = 6)
}

# ---- Inputs ------------------------------------------------------------------
meta <- read_opt(file.path(PATHS$teams_dir, sprintf("teams_%d.rds", site_season)))
if (is.null(meta)) stop("Team metadata unavailable: cannot build the site data.")
meta <- as.data.frame(meta)
meta <- meta[tolower(meta$classification) %in% "fbs", ]
meta$team_id <- as.character(meta$team_id)
meta$slug <- slugify(meta$school)
stopifnot(!anyDuplicated(meta$team_id), !anyDuplicated(meta$slug), all(nzchar(meta$slug)))

snap <- read_opt(file.path(site_state, sprintf("production_ratings_%d_latest.rds", site_season)))
sim <- read_opt(file.path(site_state, sprintf("simulations_%d_latest.rds", site_season)))
sim_status <- read_opt(file.path(site_state, sprintf("simulation_status_%d.rds", site_season)))
if (!is.null(sim_status) && identical(sim_status$status, "unavailable")) sim <- NULL
if (!is.null(sim)) stopifnot(identical(as.integer(sim$season), site_season))
# The site never mixes models: simulation odds are shown only when they came from the model that built the ratings.
if (!is.null(sim) && !is.null(snap) && !identical(sim$model_metadata$candidate, snap$candidate)) {
  message("Simulation model (", sim$model_metadata$candidate, ") differs from the ratings model (", snap$candidate, "); simulation fields set to null.")
  sim <- NULL
}
n_sims <- if (!is.null(sim)) as.integer(sim$simulation_count) else NA_integer_

# ---- Ratings, ranks, movement ------------------------------------------------
rat <- if (!is.null(snap)) as.data.frame(snap$ratings) else NULL
if (!is.null(rat)) {
  rat$team_id <- as.character(rat$team_id)
  rat <- rat[order(-rat$power_rating, as.integer(rat$team_id)), ]
  rat$rank <- seq_len(nrow(rat))                       # same ordering as scripts/01_build_ratings.R
  rat$off_rank <- rank(-rat$off_rating, ties.method = "min")
  rat$def_rank <- rank(rat$def_rating, ties.method = "min")   # lower def_rating = better defense
}
week <- if (!is.null(snap)) as.integer(snap$week) else NA_integer_
model_name <- if (!is.null(snap)) paste0("vCurrent / ", snap$candidate) else NA_character_

# ---- Rating history: CFPi+ ratings only, never interpolated ----------------------
# Sources, in precedence order for each week:
#   published      committed v2 week archives written by this model (public/data/v2/<season>/week-NN/index.json)
#   reconstructed  data/history/c2_reconstructed_<season>.csv, written by scripts/history/reconstruct_c2_history.R
#                  (same design and feature hashes as the live snapshot; checked below)
# Preseason = the snapshot's pre_power (C2's no-games rating from the frozen prior). Missing weeks stay missing.
rank_fbs <- function(d) { d <- d[order(-d$power, as.integer(d$team_id)), ]; d$rank <- seq_len(nrow(d)); d }
hist_pts <- list(); cur_nonfbs <- NULL
if (!is.null(rat)) {
  nf_now <- attr(snap$ratings, "nonfbs_ratings")
  if (!is.null(nf_now)) cur_nonfbs <- data.frame(team_id = as.character(nf_now$team_id), team = nf_now$team, power = nf_now$power, stringsAsFactors = FALSE)
  rc_file <- file.path(PATHS$root, "data", "history", sprintf("c2_reconstructed_%d.csv", site_season))
  if (file.exists(rc_file)) {
    rc <- read.csv(rc_file, stringsAsFactors = FALSE, colClasses = c(team_id = "character", as_of = "character"))
    same <- rc$design_hash == snap$design_hash & rc$feature_hash == snap$feature_hash
    if (!all(same)) message(sum(!same), " reconstructed history rows come from a different model design; ignored.")
    rc <- rc[same & rc$week < week, ]
    for (w in sort(unique(rc$week))) {
      x <- rc[rc$week == w, ]; f <- x[x$fbs %in% TRUE, ]; n <- x[!(x$fbs %in% TRUE), ]
      hist_pts[[sprintf("w%02d", w)]] <- list(week = as.integer(w), as_of = x$as_of[1], source = "reconstructed",
        fbs = rank_fbs(data.frame(team_id = f$team_id, power = f$power, off = f$off, def = f$def, stringsAsFactors = FALSE)),
        nonfbs = data.frame(team_id = n$team_id, power = n$power, stringsAsFactors = FALSE))
    }
  }
  for (d in list.files(file.path(site_out, site_season), pattern = "^week-[0-9]{2}$", full.names = TRUE)) {
    f <- file.path(d, "index.json"); if (!file.exists(f)) next
    a <- fromJSON(f); w <- as.integer(a$meta$ratings_week)
    if (!identical(a$meta$model, model_name) || !length(w) || is.na(w) || w >= week) next
    t <- a$teams[!is.na(a$teams$power), ]
    hist_pts[[sprintf("w%02d", w)]] <- list(week = w, as_of = a$meta$ratings_as_of, source = "published",
      fbs = rank_fbs(data.frame(team_id = as.character(t$team_id), power = t$power, off = t$off, def = t$def, stringsAsFactors = FALSE)),
      nonfbs = if (length(a$nonfbs)) data.frame(team_id = as.character(a$nonfbs$team_id), power = a$nonfbs$power, stringsAsFactors = FALSE) else NULL)
  }
  hist_pts[[sprintf("w%02d", week)]] <- list(week = week, as_of = iso_utc(snap$as_of), source = "published",
    fbs = data.frame(team_id = rat$team_id, power = rat$power_rating, off = rat$off_rating, def = rat$def_rating, rank = rat$rank, stringsAsFactors = FALSE),
    nonfbs = if (!is.null(cur_nonfbs)) cur_nonfbs[, c("team_id", "power")] else NULL)
  hist_pts <- hist_pts[order(vapply(hist_pts, function(p) p$week, 0L))]
}

# Previous week (rank and rating movement sitewide) = the same history, week - 1, published or reconstructed.
prev <- NULL; prev_week <- NA_integer_; prev_source <- NA_character_; prev_pt <- NULL
if (!is.na(week) && !is.null(hist_pts[[sprintf("w%02d", week - 1L)]])) {
  prev_pt <- hist_pts[[sprintf("w%02d", week - 1L)]]
  prev <- prev_pt$fbs; prev_week <- week - 1L; prev_source <- prev_pt$source
}

# ---- Simulation-derived per-team quantities ----------------------------------
name_to_id <- if (!is.null(sim)) setNames(as.character(sim$ratings$team_id), sim$ratings$team) else character(0)
team_sim <- NULL; seed_dist <- NULL; wins_dist <- NULL; rep_field <- NULL
if (!is.null(sim)) {
  st <- as.data.frame(sim$standings)
  st <- st[st$team %in% names(name_to_id), ]
  st$team_id <- name_to_id[st$team]
  stopifnot(!anyNA(st$team_id), all(table(st$sim) == length(unique(st$team_id))))
  # Bid type, replicating cfbseedR::cfb_playoff_seeds(autobid = "2026"): P4 champions, the best-ranked G6 team,
  # Notre Dame if ranked inside the field. Everything else in the field is at-large.
  st$in_field <- !is.na(st$seed)
  top_g6 <- st[st$conference %in% G6_CONFS, ]
  top_g6 <- top_g6[order(top_g6$sim, top_g6$cfp_rank), ]
  top_g6 <- top_g6[!duplicated(top_g6$sim), c("sim", "team_id")]
  st$is_top_g6 <- paste(st$sim, st$team_id) %in% paste(top_g6$sim, top_g6$team_id)
  st$auto <- st$in_field & ((st$conf_champ & st$conference %in% P4_CONFS) | st$is_top_g6 |
                             (st$team == "Notre Dame" & st$cfp_rank <= 12L))
  exit_champ <- max(st$exit)
  stopifnot(exit_champ == 5L, all(tapply(st$exit == exit_champ, st$sim, sum) == 1L))
  agg <- function(x) as.numeric(tapply(x, st$team_id, mean))
  ids <- sort(unique(st$team_id))
  team_sim <- data.frame(
    team_id = ids,
    proj_wins = agg(st$wins), p_conf = agg(st$conf_champ), p_playoff = agg(st$in_field),
    p_auto = agg(st$auto), p_at_large = agg(st$in_field & !st$auto),
    p_bye = agg(st$in_field & st$seed <= 4L), p_host = agg(st$in_field & st$seed >= 5L & st$seed <= 8L),
    p_qf = agg(st$exit >= 2L), p_sf = agg(st$exit >= 3L), p_final = agg(st$exit >= 4L), p_champ = agg(st$exit == exit_champ),
    mean_seed = as.numeric(tapply(ifelse(st$in_field, st$seed, NA), st$team_id, mean, na.rm = TRUE)),
    stringsAsFactors = FALSE)
  team_sim$mean_seed[!is.finite(team_sim$mean_seed)] <- NA_real_
  # Must equal the aggregate cfbseedR summary the legacy export publishes.
  ov <- as.data.frame(sim$overall); ov <- ov[ov$team %in% names(name_to_id), ]
  ov$team_id <- name_to_id[ov$team]; m <- match(team_sim$team_id, ov$team_id)
  stopifnot(max(abs(team_sim$p_playoff - ov$playoff[m])) < 1e-9, max(abs(team_sim$p_champ - ov$won_natty[m])) < 1e-9,
            max(abs(team_sim$proj_wins - ov$wins[m])) < 1e-9, max(abs(team_sim$p_conf - ov$conf_champ[m])) < 1e-9)

  seed_tab <- table(factor(st$team_id, levels = ids), factor(st$seed, levels = 1:12))
  seed_dist <- lapply(setNames(ids, ids), function(i) as.numeric(seed_tab[i, ]) / n_sims)
  max_w <- max(st$wins)
  wins_tab <- table(factor(st$team_id, levels = ids), factor(st$wins, levels = 0:max_w))
  wins_dist <- lapply(setNames(ids, ids), function(i) as.numeric(wins_tab[i, ]) / n_sims)
  # Final regular-season records, raw simulation counts. No conference title game is simulated (cfbseedR names the
  # standings leader champion), so every FBS team has exactly its regular-season game count; checked below.
  stopifnot(all(st$ties == 0), all(st$wins + st$losses == st$games))
  rec <- aggregate(list(count = rep(1L, nrow(st))), by = list(team_id = st$team_id, wins = st$wins, losses = st$losses), FUN = sum)
  rec <- rec[order(rec$team_id, -rec$wins, rec$losses), ]
  record_dist <- split(rec[, c("wins", "losses", "count")], rec$team_id)
  for (i in ids) {
    r <- record_dist[[i]]
    stopifnot(sum(r$count) == n_sims,
              abs(sum(r$wins * r$count) / n_sims - team_sim$proj_wins[team_sim$team_id == i]) < 1e-9,
              abs(sum(wins_dist[[i]]) - 1) < 1e-9)
  }

  # Representative field: the simulated season whose 12 (team, seed) pairs are jointly most likely under the
  # seed distributions. It is an actual simulated outcome, so it obeys the implemented selection rules.
  fld <- st[st$in_field, c("sim", "team_id", "seed", "auto", "conf_champ", "cfp_rank")]
  fld$logp <- log(seed_tab[cbind(fld$team_id, as.character(fld$seed))] / n_sims)
  score <- tapply(fld$logp, fld$sim, sum)
  best <- as.integer(names(score)[which.max(score)])
  rf <- fld[fld$sim == best, ]; rf <- rf[order(rf$seed), ]
  rep_field <- list(sim = best, sims_with_identical_field = NA_integer_,
                    seeds = lapply(seq_len(nrow(rf)), function(k) list(seed = rf$seed[k], team_id = rf$team_id[k],
                      bid = if (rf$auto[k]) "auto" else "at-large", conf_champ = isTRUE(rf$conf_champ[k]))))
  key <- tapply(paste(fld$seed, fld$team_id), fld$sim, function(v) paste(sort(v), collapse = "|"))
  rep_field$sims_with_identical_field <- sum(key == key[as.character(best)])
}

# ---- Games: results, projections, matchup quality ----------------------------
games <- NULL; current_week <- NA_integer_
if (!is.null(sim) && !is.null(sim$schedule) && !is.null(sim$team_power)) {
  g <- as.data.frame(sim$schedule)
  hfa <- sim$simulation_assumptions$hfa; sigma <- sim$simulation_assumptions$resid_sd
  cutoff <- sim$as_of
  known <- g$final %in% TRUE & g$kickoff < cutoff
  tp <- sim$team_power
  hp <- unname(tp[g$home_team]); ap <- unname(tp[g$away_team])
  stopifnot(all(is.finite(hp)), all(is.finite(ap)))
  neutral <- as.logical(g$neutral)
  mu <- hp - ap + ifelse(neutral, 0, hfa)
  p_home <- pnorm(mu / sigma)
  # Strength: FBS power percentile (1 = best rated, 0 = worst); non-FBS teams count as 0.
  pct <- if (!is.null(rat)) setNames(1 - (rat$rank - 1) / (nrow(rat) - 1), rat$team_id) else numeric(0)
  sh <- ifelse(g$home_fbs, pct[as.character(g$home_id)], 0); sa <- ifelse(g$away_fbs, pct[as.character(g$away_id)], 0)
  sh[is.na(sh)] <- 0; sa[is.na(sa)] <- 0
  quality <- round(100 * ((sh + sa) / 2) * (1 - abs(2 * p_home - 1)))
  gs <- as.data.frame(sim$game_summary); gs <- gs[gs$game_type == "REG", ]
  gsm <- match(paste(g$week, g$home_team, g$away_team), paste(gs$week, gs$home_team, gs$away_team))
  conf_game <- if ("conference_game" %in% names(g)) as.logical(g$conference_game) else
    (!is.na(g$home_conference) & g$home_conference == g$away_conference & g$home_conference != "FBS Independents")
  tbd <- if ("start_time_tbd" %in% names(g)) as.logical(g$start_time_tbd) else rep(NA, nrow(g))
  games <- data.frame(
    game_id = as.character(g$game_id), week = as.integer(g$week), kickoff = format(g$kickoff, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    time_tbd = tbd, neutral = neutral, conference_game = conf_game,
    home_id = as.character(g$home_id), away_id = as.character(g$away_id), home_team = g$home_team, away_team = g$away_team,
    home_fbs = as.logical(g$home_fbs), away_fbs = as.logical(g$away_fbs),
    home_conference = g$home_conference, away_conference = g$away_conference,
    status = ifelse(known, "final", "scheduled"),
    home_points = ifelse(known, g$home_points, NA), away_points = ifelse(known, g$away_points, NA),
    # Projections describe games still to be played only; the site never shows current ratings as a past prediction.
    spread_home = ifelse(known, NA, r4(mu)), win_prob_home = ifelse(known, NA, r4(p_home)),
    sim_home_win = ifelse(known | is.na(gsm), NA, r4(gs$home_percentage[gsm])),
    quality = ifelse(known, NA, quality),
    in_ratings = g$final %in% TRUE & g$available_at < snap$as_of, stringsAsFactors = FALSE)
  # One row per team per game, for schedule strength, strength of record and weekly explanations.
  loc_h <- ifelse(neutral, 0, 1)
  sides <- data.frame(
    game_id = rep(as.character(g$game_id), 2), week = rep(as.integer(g$week), 2),
    team_id = c(as.character(g$home_id), as.character(g$away_id)), opp_id = c(as.character(g$away_id), as.character(g$home_id)),
    opp = c(g$away_team, g$home_team), opp_fbs = c(as.logical(g$away_fbs), as.logical(g$home_fbs)),
    opp_power = c(ap, hp), loc = c(loc_h, -loc_h), known = rep(known, 2),
    in_ratings = rep(g$final %in% TRUE & g$available_at < snap$as_of, 2), available_at = rep(g$available_at, 2),
    conf_game = rep(conf_game, 2),
    pts = c(g$home_points, g$away_points), opp_pts = c(g$away_points, g$home_points), stringsAsFactors = FALSE)
  sides$margin <- sides$pts - sides$opp_pts
  # Benchmark win probability: the simulation's own CFP resume definition (R/simulation/cfb_dynamic_playoffs.R).
  bench <- sim$simulation_assumptions$cfp_ranking$benchmark_rating
  sides$bench_p <- pnorm((bench - sides$opp_power + hfa * sides$loc) / sigma)
  games <- games[order(games$kickoff, games$game_id), ]
  current_week <- if (any(!known)) min(games$week[games$status == "scheduled"]) else NA_integer_
}

# ---- Scenario data (What-if page): stored simulation outcomes, packed ---------
# For each remaining regular-season game, one bit per simulation (1 = home team won; bit s of byte s %/% 8 is sim s+1,
# lowest bit first, as packBits writes it). Then, for each FBS team (team_ids order) and each simulation, one byte each
# for seed (0 = not in the field), wins, and flags (8 = conference title, low 3 bits = CFP exit round 0-5).
scenario <- NULL
if (!is.null(games) && !is.null(team_sim)) {
  fut <- games[games$status == "scheduled", ]
  reg <- as.data.frame(sim$games); reg <- reg[reg$game_type == "REG", ]
  gi <- match(paste(reg$week, reg$home_team, reg$away_team), paste(g$week, g$home_team, g$away_team))
  reg$game_id <- as.character(g$game_id)[gi]
  reg <- reg[reg$game_id %in% fut$game_id, ]
  stopifnot(!any(reg$result == 0), all(table(reg$sim) == nrow(fut)))
  bits <- matrix(FALSE, nrow(fut), n_sims)
  bits[cbind(match(reg$game_id, fut$game_id), reg$sim)] <- reg$result > 0
  nb <- ceiling(n_sims / 8)
  gbytes <- unlist(lapply(seq_len(nrow(fut)), function(i) as.integer(packBits(c(bits[i, ], rep(FALSE, nb * 8 - n_sims)), "raw"))))
  sc_ids <- team_sim$team_id
  sst <- st[order(match(st$team_id, sc_ids), st$sim), ]
  stopifnot(nrow(sst) == length(sc_ids) * n_sims, all(sst$sim == rep(seq_len(n_sims), length(sc_ids))))
  tbytes <- c(ifelse(is.na(sst$seed), 0L, sst$seed), sst$wins, as.integer(sst$conf_champ) * 8L + sst$exit)
  stopifnot(all(tbytes >= 0 & tbytes <= 255))
  team_games <- as.integer(tapply(sst$games, sst$team_id, function(v) { stopifnot(length(unique(v)) == 1L); v[1] })[sc_ids])
  scenario <- list(meta = NULL, n = n_sims, game_ids = I(fut$game_id), team_ids = I(sc_ids), team_games = I(team_games),
                   layout = "games: n_games x ceil(n/8) bytes (bit s%8 of byte s/8 = sim s, 1 = home win); then seed, wins, flags: n_teams x n bytes each (flags: 8 = conf title, low 3 bits = exit round)",
                   data = base64_enc(as.raw(c(gbytes, tbytes))))
}

# ---- Records to date (the results the ratings and simulation treat as known) ----
records <- NULL
if (!is.null(games)) {
  fin <- games[games$status == "final", ]
  side <- rbind(data.frame(team_id = fin$home_id, win = fin$home_points > fin$away_points, conf = fin$conference_game),
                data.frame(team_id = fin$away_id, win = fin$away_points > fin$home_points, conf = fin$conference_game))
  records <- data.frame(team_id = meta$team_id, stringsAsFactors = FALSE)
  records$w <- vapply(records$team_id, function(i) sum(side$win[side$team_id == i]), numeric(1))
  records$l <- vapply(records$team_id, function(i) sum(!side$win[side$team_id == i]), numeric(1))
  records$cw <- vapply(records$team_id, function(i) sum(side$win[side$team_id == i & side$conf %in% TRUE]), numeric(1))
  records$cl <- vapply(records$team_id, function(i) sum(!side$win[side$team_id == i & side$conf %in% TRUE]), numeric(1))
}

# ---- Resume: schedule strength and strength of record ---------------------------
# SOS = mean current CFPi+ rating of the opponents (FBS and non-FBS, as the simulation rates them).
# SOR = wins above benchmark on games played: sum(win - P(benchmark team wins that game)), the benchmark being the
# simulation's CFP-ranking benchmark (the No. PRODUCTION$cfp_rank_benchmark rated team), with home field.
resume <- NULL
if (!is.null(games)) {
  fb <- sides[sides$team_id %in% meta$team_id, ]
  resume <- do.call(rbind, lapply(meta$team_id, function(i) {
    x <- fb[fb$team_id == i, ]; k <- x[x$known, ]
    data.frame(team_id = i, sos_played = if (nrow(k)) mean(k$opp_power) else NA, sos_all = if (nrow(x)) mean(x$opp_power) else NA,
               sos_remaining = if (any(!x$known)) mean(x$opp_power[!x$known]) else NA,
               sor = if (nrow(k)) sum((k$margin > 0) - k$bench_p) else NA, stringsAsFactors = FALSE)
  }))
  rk <- function(v) { r <- rank(-v, ties.method = "min", na.last = "keep"); r }
  resume$sos_played_rank <- rk(resume$sos_played); resume$sos_all_rank <- rk(resume$sos_all)
  resume$sos_remaining_rank <- rk(resume$sos_remaining); resume$sor_rank <- rk(resume$sor)
  # Resume rank (docs/website/RESUME_PROPOSAL.md, approved): strength of record, then fewer losses, then harder
  # schedule played, then team id. Teams without a final game are unranked.
  lo <- vapply(resume$team_id, function(i) sum(fb$known & fb$team_id == i & fb$margin < 0), numeric(1))
  ok <- !is.na(resume$sor)
  o <- order(-resume$sor, lo, -resume$sos_played, as.integer(resume$team_id))
  o <- o[ok[o]]
  resume$resume_rank <- NA_integer_; resume$resume_rank[o] <- seq_along(o)
}
game_note <- function(k) {
  # Best win / worst loss among final games, by the opponent's current rating.
  w <- k[k$margin > 0, ]; l <- k[k$margin < 0, ]
  one <- function(r) if (!nrow(r)) NULL else list(game_id = r$game_id, opp_id = r$opp_id, opp = r$opp, opp_fbs = r$opp_fbs,
    opp_rank = pick(rat, r$opp_id, "rank"), loc = r$loc, pts = r$pts, opp_pts = r$opp_pts)
  list(best_win = one(w[which.max(w$opp_power), , drop = FALSE]), worst_loss = one(l[which.min(l$opp_power), , drop = FALSE]))
}

# ---- What changed since the previous week (deterministic, from model inputs only) ----
changes <- NULL
if (!is.null(prev_pt) && !is.null(games)) {
  lo <- as.POSIXct(prev_pt$as_of, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"); hi <- snap$as_of
  prev_pw <- c(setNames(prev_pt$fbs$power, prev_pt$fbs$team_id),
               if (!is.null(prev_pt$nonfbs)) setNames(prev_pt$nonfbs$power, prev_pt$nonfbs$team_id))
  # Games that entered the ratings in this window: final, result available at or after the previous cutoff and before this one.
  win <- sides[sides$in_ratings & sides$available_at >= lo & sides$available_at < hi & sides$team_id %in% meta$team_id, ]
  site_word <- function(loc) ifelse(loc > 0, "at home", ifelse(loc < 0, "on the road", "at a neutral site"))
  fmt1 <- function(x) formatC(abs(x), format = "f", digits = 1)
  changes <- lapply(meta$team_id, function(i) {
    x <- win[win$team_id == i, ]; x <- x[order(x$available_at), ]
    gl <- lapply(seq_len(nrow(x)), function(k) {
      r <- x[k, ]
      pm <- unname(prev_pw[i] - prev_pw[r$opp_id] + hfa * r$loc)
      prank <- if (r$opp_fbs) pick(prev, r$opp_id, "rank") else NA
      opp_txt <- paste0(if (!is.na(prank)) paste0("No. ", prank, " ") else "", r$opp)
      res <- if (r$margin > 0) "Beat" else "Lost to"
      txt <- sprintf("%s %s %d\u2013%d %s.", res, opp_txt, as.integer(max(r$pts, r$opp_pts)), as.integer(min(r$pts, r$opp_pts)), site_word(r$loc))
      if (!is.na(pm)) {
        d <- r$margin - pm
        txt <- paste0(txt, sprintf(" Week %d ratings projected a %s by %s; the result was %s points %s than projected.",
                                   prev_week, if (pm >= 0) "win" else "loss", fmt1(pm), fmt1(d), if (d >= 0) "better" else "worse"))
      }
      list(game_id = r$game_id, opp_id = r$opp_id, opp = r$opp, opp_fbs = r$opp_fbs, opp_rank_prev = prank, loc = r$loc,
           pts = r$pts, opp_pts = r$opp_pts, proj_margin = r4(pm), vs_projection = r4(r$margin - pm), text = txt)
    })
    list(team_id = i, games = gl,
         off_change = r4(pick(rat, i, "off_rating") - pick(prev, i, "off")),
         def_change = r4(pick(rat, i, "def_rating") - pick(prev, i, "def")))
  })
}

# ---- Conferences (membership from team metadata, never hard-coded) -------------
conf_kind <- function(cn) if (cn %in% P4_CONFS) "Power 4" else if (cn %in% G6_CONFS) "Group of 6" else if (cn == "FBS Independents") "Independents" else "Other"
conferences <- lapply(sort(unique(meta$conference)), function(cn) {
  ids <- meta$team_id[meta$conference == cn]
  pw <- pick(rat, ids, "power_rating"); rk <- pick(rat, ids, "rank")
  nc <- if (!is.null(games)) sides[sides$team_id %in% ids & sides$known & !(sides$conf_game %in% TRUE), ] else NULL
  list(slug = slugify(cn), name = cn, kind = conf_kind(cn), is_conference = cn != "FBS Independents",
       team_ids = I(ids), n = length(ids),
       avg_power = r4(mean(pw)), median_power = r4(stats::median(pw)), top25 = sum(rk <= 25, na.rm = TRUE),
       best_rank = if (all(is.na(rk))) NA else min(rk, na.rm = TRUE),
       exp_playoff = if (!is.null(team_sim)) r4(sum(pick(team_sim, ids, "p_playoff"))) else NA,
       exp_playoff_raw = if (!is.null(team_sim)) sum(pick(team_sim, ids, "p_playoff")) else NA,
       sos_avg = if (!is.null(resume)) r4(mean(pick(resume, ids, "sos_all"))) else NA,
       nonconf_wins = if (!is.null(nc)) sum(nc$margin > 0) else NA, nonconf_losses = if (!is.null(nc)) sum(nc$margin < 0) else NA,
       nonconf_fbs_wins = if (!is.null(nc)) sum(nc$margin > 0 & nc$opp_fbs) else NA,
       nonconf_fbs_losses = if (!is.null(nc)) sum(nc$margin < 0 & nc$opp_fbs) else NA)
})
cavg <- vapply(conferences, function(x) x$avg_power, 0)
crank <- rank(-cavg, ties.method = "min")
for (k in seq_along(conferences)) conferences[[k]]$avg_rank <- if (conferences[[k]]$is_conference) sum(cavg[vapply(conferences, function(x) x$is_conference, TRUE)] > cavg[k]) + 1L else NA
if (!is.null(team_sim)) stopifnot(abs(sum(vapply(conferences, function(x) x$exp_playoff_raw, 0)) - 12) < 1e-6)
conferences <- lapply(conferences, function(x) { x$exp_playoff_raw <- NULL; x })

# ---- Statistical leaders (CFBD season player stats; display only) ----------------
# Fixed rules, no player rating: passing-yards leader; top 2 rushers; top 3 receivers; top 3 by sacks; top by
# interceptions. A player needs a positive value in the ranking stat. Ties: the second stat listed, then name.
# Used only when the pull covers exactly the ratings week, so the stats and "Ratings through Week X" agree.
leaders <- NULL; leaders_week <- NA_integer_
ps <- read_opt(file.path(site_state, sprintf("player_stats_%d.rds", site_season)))
if (!is.null(ps) && !is.na(week) && identical(as.integer(attr(ps, "end_week")), week)) {
  leaders_week <- week
  z <- function(v) ifelse(is.na(v), 0, v)
  top <- function(d, by, then, n, fields) {
    d <- d[z(d[[by]]) > 0, , drop = FALSE]
    d <- d[order(-z(d[[by]]), -z(d[[then]]), d$player), , drop = FALSE]
    d <- head(d, n)
    lapply(seq_len(nrow(d)), function(k) c(list(athlete_id = as.character(d$athlete_id[k]), player = d$player[k], position = d$position[k]),
                                           setNames(lapply(fields, function(f) z(d[[f]][k])), fields)))
  }
  leaders <- lapply(setNames(meta$school, meta$team_id), function(school) {
    d <- ps[ps$team == school, , drop = FALSE]
    if (!nrow(d)) return(NULL)
    list(passing = top(d, "passing_yds", "passing_td", 1, c("passing_completions", "passing_att", "passing_yds", "passing_td", "passing_int")),
         rushing = top(d, "rushing_yds", "rushing_td", 2, c("rushing_car", "rushing_yds", "rushing_td")),
         receiving = top(d, "receiving_yds", "receiving_td", 3, c("receiving_rec", "receiving_yds", "receiving_td")),
         sacks = top(d, "defensive_sacks", "defensive_tfl", 3, c("defensive_sacks", "defensive_tfl", "defensive_tot")),
         interceptions = top(d, "interceptions_int", "interceptions_yds", 1, c("interceptions_int", "interceptions_yds", "interceptions_td")))
  })
  # Every shown value must be the pulled value for that player.
  for (id in names(leaders)) for (cat in names(leaders[[id]])) for (p in leaders[[id]][[cat]]) {
    row <- ps[ps$team == meta$school[meta$team_id == id] & as.character(ps$athlete_id) == p$athlete_id, ]
    stopifnot(nrow(row) == 1L)
    for (f in setdiff(names(p), c("athlete_id", "player", "position"))) stopifnot(identical(as.numeric(p[[f]]), as.numeric(z(row[[f]]))))
  }
} else if (!is.null(ps)) message("Player stats cover week ", attr(ps, "end_week"), ", ratings week ", week, ": leaders omitted.")

# ---- Assemble team rows --------------------------------------------------------
rows <- lapply(meta$team_id, function(id) {
  rank <- pick(rat, id, "rank"); prank <- pick(prev, id, "rank")
  list(team_id = id, slug = meta$slug[meta$team_id == id],
       rank = rank, rank_prev = prank, rank_change = if (!is.na(rank) && !is.na(prank)) prank - rank else NA,
       power = r4(pick(rat, id, "power_rating")),
       rating_change = r4(pick(rat, id, "power_rating") - pick(prev, id, "power")),
       off = r4(pick(rat, id, "off_rating")), def = r4(pick(rat, id, "def_rating")),
       off_rank = pick(rat, id, "off_rank"), def_rank = pick(rat, id, "def_rank"),
       preseason_power = r4(pick(rat, id, "pre_power")), games_played = pick(rat, id, "games_played"),
       wins = pick(records, id, "w"), losses = pick(records, id, "l"),
       conf_wins = pick(records, id, "cw"), conf_losses = pick(records, id, "cl"),
       proj_wins = r4(pick(team_sim, id, "proj_wins")), p_playoff = r4(pick(team_sim, id, "p_playoff")),
       p_conf = r4(pick(team_sim, id, "p_conf")), p_champ = r4(pick(team_sim, id, "p_champ")),
       sos = r4(pick(resume, id, "sos_all")), sos_rank = pick(resume, id, "sos_all_rank"),
       sor = r4(pick(resume, id, "sor")), sor_rank = pick(resume, id, "sor_rank"),
       resume_rank = pick(resume, id, "resume_rank"), sos_played = r4(pick(resume, id, "sos_played")))
})

meta_block <- list(
  schema_version = 2L, season = site_season, model = model_name,
  ratings_week = week, ratings_as_of = if (!is.null(snap)) iso_utc(snap$as_of) else NA,
  ratings_updated_at = if (!is.null(snap)) iso_utc(snap$updated_at) else NA,
  sim_status = if (!is.null(sim)) "available" else "unavailable",
  sim_count = n_sims, sim_updated_at = if (!is.null(sim)) iso_utc(sim$updated_at) else NA,
  sim_as_of = if (!is.null(sim)) iso_utc(sim$as_of) else NA,
  current_week = current_week, movement_compared_to_week = prev_week, movement_source = prev_source,
  hfa = if (!is.null(sim)) sim$simulation_assumptions$hfa else if (!is.null(rat)) attr(snap$ratings, "hfa") else NA,
  sigma = if (!is.null(sim)) sim$simulation_assumptions$resid_sd else NA,
  exported_at = iso_utc(Sys.time()))

top_games <- if (!is.null(games) && !is.na(current_week)) {
  tg <- games[games$week == current_week & games$status == "scheduled" & !is.na(games$quality), ]
  head(tg[order(-tg$quality, tg$kickoff), ], 6)
} else NULL

index <- list(meta = meta_block, teams = rows, top_games = top_games)
history_doc <- NULL
if (!is.null(rat)) {
  pts <- c(list(pre = list(week = NA_integer_, as_of = NA_character_, source = "preseason",
                           fbs = rank_fbs(data.frame(team_id = rat$team_id, power = rat$pre_power, off = NA_real_, def = NA_real_, stringsAsFactors = FALSE)))),
           hist_pts)
  col <- function(p, id, f) { v <- pick(p$fbs, id, f); if (is.na(v)) NA_real_ else as.numeric(v) }
  history_doc <- list(meta = meta_block,
    points = unname(lapply(pts, function(p) list(week = p$week, label = if (is.na(p$week)) "Preseason" else paste("Week", p$week),
                                                  as_of = p$as_of, source = p$source))),
    teams = setNames(lapply(meta$team_id, function(id) list(
      power = I(unname(vapply(pts, function(p) r4(col(p, id, "power")), 0))),
      rank = I(unname(vapply(pts, function(p) col(p, id, "rank"), 0))),
      off = I(unname(vapply(pts, function(p) r4(col(p, id, "off")), 0))),
      def = I(unname(vapply(pts, function(p) r4(col(p, id, "def")), 0))))), meta$team_id))
}
teams_doc <- list(meta = meta_block, teams = lapply(seq_len(nrow(meta)), function(k) list(
  team_id = meta$team_id[k], slug = meta$slug[k], team = meta$school[k], mascot = meta$mascot[k],
  abbreviation = meta$abbreviation[k], conference = meta$conference[k],
  color = meta$color[k], alt_color = meta$alt_color[k], logo = meta$logo[k], logo_dark = meta$logo_2[k])))

playoff_doc <- list(meta = meta_block,
  format = list(teams = 12L, byes = 4L,
                autobids = "Champions of the SEC, Big Ten, ACC and Big 12; the highest-ranked team from the American, Conference USA, MAC, Mountain West, Pac-12 and Sun Belt; Notre Dame if ranked in the top 12",
                ranking = "Each simulated season is ranked by a resume score: 1.9887 x wins above benchmark + 0.14943 x opponent-adjusted margin + 1.7923 x conference title",
                seeding = "Straight seeding by that ranking; seeds 1-4 get byes; seeds 5-8 host first-round games; later rounds are neutral",
                source = "cfbseedR::cfb_playoff_seeds(autobid = \"2026\") via R/simulation/cfb_dynamic_playoffs.R"),
  teams = if (!is.null(team_sim)) lapply(seq_len(nrow(team_sim)), function(k) {
    x <- as.list(team_sim[k, ]); x[-1] <- lapply(x[-1], r4); x$seed_dist <- r4(seed_dist[[team_sim$team_id[k]]]); x }) else list(),
  representative_field = rep_field)

# ---- Validation (fail the export on bad data) --------------------------------
probs <- c("p_playoff", "p_conf", "p_champ")
for (r in rows) for (f in probs) stopifnot(is.na(r[[f]]) || (r[[f]] >= 0 && r[[f]] <= 1))
if (!is.null(rat)) stopifnot(!anyDuplicated(rat$rank), all(rat$team_id %in% meta$team_id))
if (!is.null(team_sim)) {
  stopifnot(abs(sum(team_sim$p_playoff) - 12) < 1e-6, abs(sum(team_sim$p_champ) - 1) < 1e-6,
            abs(sum(team_sim$p_bye) - 4) < 1e-6, all(abs(vapply(seed_dist, sum, 0) - team_sim$p_playoff) < 1e-9))
  stopifnot(length(rep_field$seeds) == 12L, sum(vapply(rep_field$seeds, function(s) s$bid == "auto", TRUE)) >= 5L)
}
if (!is.null(games)) stopifnot(!anyDuplicated(games$game_id), all(is.na(games$win_prob_home) | (games$win_prob_home >= 0 & games$win_prob_home <= 1)))

# ---- Write ---------------------------------------------------------------------
write_site_json(index, file.path(site_out, "index.json"))
write_site_json(teams_doc, file.path(site_out, "teams.json"))
write_site_json(list(meta = meta_block, games = if (is.null(games)) list() else games), file.path(site_out, "games.json"))
write_site_json(playoff_doc, file.path(site_out, "playoff.json"))
if (!is.null(history_doc)) write_site_json(history_doc, file.path(site_out, "history.json"))
write_site_json(list(meta = meta_block, compared_to_week = prev_week, compared_to_source = prev_source,
                     window_start = if (!is.null(prev_pt)) prev_pt$as_of else NA, window_end = meta_block$ratings_as_of,
                     teams = if (is.null(changes)) list() else changes), file.path(site_out, "changes.json"))
write_site_json(list(meta = meta_block, conferences = conferences), file.path(site_out, "conferences.json"))
write_site_json(list(meta = meta_block, method = list(
    metric = "Strength of record: sum over final games of (win - P(benchmark team wins that game))",
    benchmark = "the No. 60 CFPi+ team (production cfp_rank_benchmark), with home field and the model's sigma",
    tiebreaks = "fewer losses, then harder schedule played (mean opponent rating), then team id",
    proposal = "docs/website/RESUME_PROPOSAL.md"),
  teams = if (is.null(resume)) list() else lapply(meta$team_id, function(id) {
    k <- sides[sides$team_id == id & sides$known, ]
    c(list(team_id = id, resume_rank = pick(resume, id, "resume_rank"), sor = r4(pick(resume, id, "sor")),
           sos_played = r4(pick(resume, id, "sos_played")), sos_played_rank = pick(resume, id, "sos_played_rank"),
           wins = pick(records, id, "w"), losses = pick(records, id, "l"), games = nrow(k), predictive_rank = pick(rat, id, "rank")),
      game_note(k)) })), file.path(site_out, "resume.json"))
if (!is.null(scenario)) { scenario$meta <- meta_block; write_site_json(scenario, file.path(site_out, "scenario.json")) } else unlink(file.path(site_out, "scenario.json"))
# Team files for teams no longer in the directory (renamed slug, left FBS) are removed, never left stale.
stale <- setdiff(list.files(file.path(site_out, "team"), pattern = "[.]json$"), paste0(meta$slug, ".json"))
if (length(stale)) { message("Removing stale team files: ", paste(stale, collapse = ", ")); unlink(file.path(site_out, "team", stale)) }
for (k in seq_len(nrow(meta))) {
  id <- meta$team_id[k]
  sched <- if (is.null(games)) list() else games[games$home_id == id | games$away_id == id, ]
  write_site_json(list(meta = meta_block, team = teams_doc$teams[[k]], summary = rows[[k]], schedule = sched,
                       wins_dist = if (!is.null(wins_dist)) r4(wins_dist[[id]]) else NULL,
                       record_dist = if (!is.null(team_sim)) record_dist[[id]] else NULL,
                       leaders = if (!is.null(leaders) && !is.null(leaders[[id]])) c(list(through_week = leaders_week, source = "CollegeFootballData"), leaders[[id]]) else NULL,
                       resume = if (!is.null(resume)) c(as.list(lapply(resume[resume$team_id == id, -1], function(v) if (is.double(v)) r4(v) else v)),
                                                        game_note(sides[sides$team_id == id & sides$known, ])) else NULL,
                       seed_dist = if (!is.null(seed_dist)) r4(seed_dist[[id]]) else NULL,
                       playoff = if (!is.null(team_sim)) { x <- as.list(team_sim[team_sim$team_id == id, ]); x[-1] <- lapply(x[-1], r4); x } else NULL),
                  file.path(site_out, "team", paste0(meta$slug[k], ".json")))
}
if (!is.na(week)) {
  target <- file.path(site_out, as.character(site_season), sprintf("week-%02d", week), "index.json")
  old <- if (file.exists(target)) tryCatch(fromJSON(target)$meta$model, error = function(e) NULL) else NULL
  if (!is.null(old) && !identical(old, model_name)) message("Keeping ", target, ": published by '", old, "'.") else
    write_site_json(c(index, list(nonfbs = if (!is.null(cur_nonfbs)) lapply(seq_len(nrow(cur_nonfbs)), function(k)
      list(team_id = cur_nonfbs$team_id[k], team = cur_nonfbs$team[k], power = r4(cur_nonfbs$power[k]))) else list())), target)
}
cat(sprintf("Site data: %d teams, %s games, simulations %s -> %s\n", nrow(meta),
            if (is.null(games)) "0" else nrow(games), meta_block$sim_status, site_out))
