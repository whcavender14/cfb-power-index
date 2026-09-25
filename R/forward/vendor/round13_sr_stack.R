# Round 13 success-rate (SR) stack: pred = incumbent + w * SRnet when both teams
# have >= 1 PBP game before the cutoff, else the incumbent exactly.
# Spec: docs/round13/ROUND13_PREDECLARATION.md (C1-C13 over Appendix A).
# Ported from the archived Round 7-10 code in ~/Desktop/CFB Modeling Backup/archive:
#   v7 cfb_v7_forward.R::v7_states (scoreboard repair), cfb_power_ratings_v7.R
#   (v7_success, v7_allowed_types, v7_normalize eligibility; finite EPA replaced by its
#   model-free state condition),
#   v8 v8_parse_fumble_text / v8_recover_fumbles, v9 v9_effects joint ridge with
#   the home term zeroed (Round 10 v10_effects). No EP model; no vendor EPA/PPA/WP.
# Pure functions; the only I/O is in the explicit r13_read_* loaders.
suppressPackageStartupMessages({library(data.table); library(Matrix)})

r13_assert <- function(ok, msg) if (!isTRUE(ok)) stop(msg, call. = FALSE)

R13 <- list(lambda_off = 0.5, lambda_def = 0.5, half_life = 56, row_weight = 0.5,
            completed_hours = 4, available_hours = 12, garbage = c(Inf, 38, 28, 22),
            min_train = 2017L)

# ---- guards -------------------------------------------------------------------
r13_vendor_pattern <- "(^|_)(ppa|epa|wpa|wp)($|_)|win_prob|home_wp|away_wp"
r13_market_pattern <- "spread|odds|moneyline|market|provider|over_under|implied|closing|opening|sportsbook|vegas|(^|_)line($|_)"
r13_vendor_guard <- function(x) {
  bad <- grepl(r13_vendor_pattern, names(x), ignore.case = TRUE)
  r13_assert(!any(bad), paste("Vendor EPA/PPA/WP field present:", paste(names(x)[bad], collapse = ", ")))
  invisible(x)
}
r13_market_guard <- function(x) {
  bad <- grepl(r13_market_pattern, names(x), ignore.case = TRUE)
  r13_assert(!any(bad), paste("Market field rejected:", paste(names(x)[bad], collapse = ", ")))
  invisible(x)
}

# ---- time -----------------------------------------------------------------------
# A bare as.POSIXct() silently drops the time of day on these strings (C3).
r13_parse_kickoff <- function(start_date) {
  k <- as.POSIXct(as.character(start_date), tz = "UTC", format = "%Y-%m-%dT%H:%M:%OSZ")
  r13_assert(!anyNA(k), "Unparseable kickoff time")
  k
}
r13_period_start <- function(t) {
  d <- as.Date(t, tz = "UTC")
  as.POSIXct(d - ((as.POSIXlt(d)$wday + 6L) %% 7L), tz = "UTC")
}
r13_stamp <- function(t) format(t, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

# ---- schedule -----------------------------------------------------------------
r13_schedule <- function(raw) {
  fields <- c("game_id", "season", "week", "start_date", "completed", "neutral_site", "home_id", "away_id",
              "home_team", "away_team", "home_division", "away_division", "home_conference", "away_conference",
              "home_points", "away_points")
  r13_assert(all(fields %in% names(raw)), paste("Schedule missing:", paste(setdiff(fields, names(raw)), collapse = ", ")))
  g <- as.data.table(as.data.frame(raw)[, fields])
  r13_market_guard(g)
  r13_assert(!any(g$season == 2020), "2020 is excluded throughout")
  g[, game_id := as.character(game_id)]
  r13_assert(!anyDuplicated(g$game_id), "Duplicate schedule game_id")
  g[, kickoff := r13_parse_kickoff(start_date)]
  g[, `:=`(cutoff = r13_period_start(kickoff),
           completed_at = kickoff + R13$completed_hours * 3600,
           available_at = kickoff + R13$available_hours * 3600,
           neutral = as.logical(neutral_site),
           home_fbs = tolower(home_division) == "fbs", away_fbs = tolower(away_division) == "fbs")]
  g[, final := completed %in% TRUE & is.finite(home_points) & is.finite(away_points)]
  setorder(g, kickoff, game_id)
  g[]
}

# ---- raw plays ----------------------------------------------------------------
r13_play_fields <- c("season", "game_id", "play_id", "drive_number", "play_number", "offense", "defense",
                     "offense_score", "defense_score", "period", "clock_minutes", "clock_seconds", "yards_to_goal",
                     "down", "distance", "yards_gained", "play_type", "play_text")
# Sanctioned loader: vendor columns are dropped here and never examined.
r13_read_plays <- function(path) {
  raw <- readRDS(path)
  keep <- names(raw)[!grepl(r13_vendor_pattern, names(raw), ignore.case = TRUE)]
  x <- as.data.table(as.data.frame(raw)[, keep, drop = FALSE])
  r13_assert(all(r13_play_fields %in% names(x)), "Raw plays missing required fields")
  x[, r13_play_fields, with = FALSE]
}

# ---- fumble recovery (Round 8 change 3; Phase 2b vocabulary) --------------------
r13_extract1 <- function(pattern, x) {
  m <- regexpr(pattern, x, ignore.case = TRUE)
  out <- rep(NA_character_, length(x)); out[m > 0] <- regmatches(x, m); out
}
# vocab "r8": exact Round 8 parser. "r13": adds the 2025 CFBD phrasing (C: 2b),
# adopted only under the predeclared rule (2014-2024 row-for-row unchanged, 2025 >= 90%).
r13_parse_fumble_text <- function(text, vocab = c("r8", "r13")) {
  vocab <- match.arg(vocab)
  text <- ifelse(is.na(text), "", text)
  pre <- sub("(?i)fumbled.*$", "", text, perl = TRUE)
  type <- ifelse(grepl("sacked", pre, ignore.case = TRUE), "Sack",
          ifelse(grepl("pass complete", pre, ignore.case = TRUE), "Pass",
          ifelse(grepl("run for|rush(ed)? for", pre, ignore.case = TRUE), "Rush", NA_character_)))
  no_gain <- grepl("no gain", pre, ignore.case = TRUE)
  loss_n <- suppressWarnings(as.numeric(gsub("[^0-9]", "", r13_extract1("loss of [0-9]+ *y[a-z]*", pre))))
  pos_n <- suppressWarnings(as.numeric(gsub("[^0-9]", "", r13_extract1("[0-9]+ *y[a-z]*", pre))))
  gained <- ifelse(no_gain, 0, ifelse(!is.na(loss_n), -loss_n, ifelse(!is.na(pos_n), pos_n, 0)))
  if (vocab == "r13") {
    alt <- r13_parse_fumble_2025(text)
    use <- is.na(type) & !is.na(alt$type)
    type[use] <- alt$type[use]; gained[use] <- alt$gained[use]
  }
  data.frame(type = type, gained = gained, stringsAsFactors = FALSE)
}
# 2025 CFBD phrasing: "rush middle for 13 yards gain to the X38 fumbled by ...".
# Evaluated under the 2b adoption rule; see output/dev/round13/PHASE2_LOG.md.
r13_parse_fumble_2025 <- function(text) {
  pre <- sub("(?i)fumbled.*$", "", ifelse(is.na(text), "", text), perl = TRUE)
  m <- regmatches(pre, regexec("(?i)\\brush(?: (?:left|right|middle))? for (?:([0-9]+) yards? (gain|loss)|no gain)", pre, perl = TRUE))
  hit <- lengths(m) > 0
  n <- vapply(m, function(z) if (length(z) && nzchar(z[2])) as.numeric(z[2]) else 0, numeric(1))
  sgn <- vapply(m, function(z) if (length(z) && tolower(z[3]) == "loss") -1 else 1, numeric(1))
  data.frame(type = ifelse(hit, "Rush", NA_character_), gained = ifelse(hit, sgn * n, NA_real_), stringsAsFactors = FALSE)
}
r13_recover_fumbles <- function(raw, vocab = "r8") {
  raw <- copy(raw)
  fum <- grepl("Fumble", raw$play_type)
  parsed <- r13_parse_fumble_text(raw$play_text, vocab)
  rec <- fum & !is.na(parsed$type)
  raw[, `:=`(fumble_turnover = fum & grepl("Interception|Fumble Recovery \\(Opponent\\)|Fumble Return", play_type),
             fumble_total = fum, fumble_recovered = rec)]
  raw[rec, `:=`(play_type = parsed$type[rec], yards_gained = parsed$gained[rec])]
  raw[]
}

# ---- play states: monotone scoreboard repair (Round 7 Amendment 3) --------------
r13_states <- function(raw, g) {
  r13_vendor_guard(raw); r13_market_guard(raw)
  r13_assert(all(r13_play_fields %in% names(raw)), "Play states need the projected raw fields")
  x <- as.data.table(raw)
  x[, `:=`(game_id = as.character(game_id), play_id = as.character(play_id))]
  x[, duplicate_id := duplicated(paste(game_id, play_id)) | duplicated(paste(game_id, play_id), fromLast = TRUE)]
  setorder(x, game_id, drive_number, play_number, play_id)
  j <- match(x$game_id, g$game_id)
  x[, `:=`(home = g$home_team[j], away = g$away_team[j], home_points = g$home_points[j], away_points = g$away_points[j],
           completed_at = g$completed_at[j], available_at = g$available_at[j])]
  x[, `:=`(home_post = ifelse(offense == home, offense_score, defense_score),
           away_post = ifelse(offense == away, offense_score, defense_score))]
  x[, `:=`(home_run = cummax(home_post), away_run = cummax(away_post)), by = game_id]
  x[, stale_row := home_post < home_run | away_post < away_run]
  x[, `:=`(home_before = shift(home_run, fill = 0), away_before = shift(away_run, fill = 0)), by = game_id]
  x[, `:=`(dh = home_run - home_before, da = away_run - away_before)]
  x[, reconstruction_ok := !is.na(home_points[1L]) & !is.na(away_points[1L]) &
      max(home_run) == home_points[1L] & max(away_run) == away_points[1L], by = game_id]
  x[, bad_game := !reconstruction_ok | any(duplicate_id | is.na(home) | is.na(away) | is.na(offense) | is.na(defense) |
      !offense %in% c(home[1L], away[1L]) | !defense %in% c(home[1L], away[1L]) | offense == defense |
      is.na(dh) | is.na(da) | duplicated(paste(drive_number, play_number))), by = game_id]
  x[, margin := ifelse(offense == home, home_before - away_before, away_before - home_before)]
  x[, bad_transition := dh > 8 | da > 8 | (dh > 0 & da > 0)]
  x[, no_play := is.na(play_text) | grepl("kneel|spike|no.play|penalty", play_text, ignore.case = TRUE)]
  # Model-free equivalent of Round 7-8's finite-EPA requirement (Phase 2a root-cause fix, C4):
  # a valid yard line and clock, and a following football state in the half, an immediate
  # score, or an explicitly ended half. No EP model is fit or used.
  x[, half := ifelse(period <= 2, 1L, ifelse(period <= 4, 2L, 3L))]
  x[, secs := ifelse(period %% 2 == 1, 900, 0) + clock_minutes * 60 + clock_seconds]
  x[, score_home := ifelse(bad_transition, 0, ifelse(dh >= 6, 7, ifelse(dh == 3, 3, ifelse(dh == 2, 2, 0))) -
                                               ifelse(da >= 6, 7, ifelse(da == 3, 3, ifelse(da == 2, 2, 0))))]
  x[, state_valid := is.finite(yards_to_goal) & yards_to_goal >= 0 & yards_to_goal <= 100 & is.finite(secs) & secs >= 0 & secs <= 1800]
  x[, continuation := !bad_game & !no_play & !stale_row & !grepl("Kickoff|Timeout|End|Conversion", play_type) & period %in% 1:4 &
      down %in% 1:4 & is.finite(distance) & distance > 0 & state_valid & is.finite(margin)]
  x[, row_index := .I]
  x[, next_index := { out <- rep(NA_integer_, .N); nx <- NA_integer_
      for (i in .N:1L) { out[i] <- nx; if (continuation[i] || score_home[i] != 0) nx <- row_index[i] }; out }, by = .(game_id, half)]
  x[, half_terminal := any(grepl("End of Half|End of Game", play_type) | secs == 0), by = .(game_id, half)]
  x[, state_complete := state_valid & (score_home != 0 | !is.na(next_index) | half_terminal %in% TRUE)]
  x[, turnover := grepl("Interception|Fumble Recovery \\(Opponent\\)|Fumble Return", play_type)]
  if ("fumble_turnover" %in% names(x)) x[, turnover := turnover | (fumble_turnover %in% TRUE)]
  x[]
}

# ---- eligibility (v7_normalize minus the finite-EPA requirement) -----------------
r13_allowed_types <- c("Rush", "Rushing Touchdown", "Pass", "Pass Reception", "Pass Completion",
                       "Pass Incompletion", "Passing Touchdown", "Sack", "Pass Interception Return",
                       "Pass Interception", "Interception", "Interception Return Touchdown")
r13_success <- function(down, distance, gained) {
  r13_assert(all(down %in% 1:4 & is.finite(distance) & distance > 0 & is.finite(gained)), "Invalid success inputs")
  as.numeric(gained >= distance * c(.5, .7, 1, 1)[down])
}
r13_eligible <- function(st, garbage = R13$garbage) {
  x <- st
  no_play <- x$no_play | x$bad_game | x$stale_row | x$bad_transition
  why <- rep("eligible", nrow(x))
  drop <- function(mask, reason) { mask[is.na(mask)] <- TRUE; why[why == "eligible" & mask] <<- reason }
  drop(x$season == 2020, "excluded_2020")
  drop(is.na(x$available_at) | is.na(x$completed_at), "unverified_availability")
  key <- paste(x$game_id, x$play_id, sep = "/")
  drop(duplicated(key) | duplicated(key, fromLast = TRUE), "duplicate_play_id")
  drop(is.na(x$game_id) | is.na(x$play_id) | !nzchar(x$game_id) | !nzchar(x$play_id), "missing_id")
  drop(is.na(x$offense) | is.na(x$defense) | !nzchar(x$offense) | !nzchar(x$defense) | x$offense == x$defense, "invalid_teams")
  drop(no_play | grepl("kneel|spike|no.play|penalty|punt|kick|field goal", x$play_text, ignore.case = TRUE), "excluded_text_or_no_play")
  drop(!x$play_type %in% r13_allowed_types, "ambiguous_or_non_scrimmage")
  drop(!x$down %in% 1:4 | !is.finite(x$distance) | x$distance <= 0 | !is.finite(x$yards_gained) | is.na(x$turnover) |
       !x$state_complete, "invalid_response")
  drop(!x$period %in% 1:4 | !is.finite(x$margin) | abs(x$margin) > garbage[pmax(1, pmin(4, x$period))], "garbage_or_overtime")
  el <- which(why == "eligible")
  for (ids in split(el, x$game_id[el])) {
    teams <- unique(x$offense[ids])
    if (length(teams) != 2 || !all(x$defense[ids] %in% teams)) why[ids] <- "incomplete_game_exposure"
  }
  y <- x[why == "eligible", .(season, game_id, play_id, offense, defense, down, distance, gained = yards_gained,
                              completed_at, available_at)]
  y[, success := r13_success(down, distance, gained)]
  list(plays = y[], audit = data.table(game_id = x$game_id, play_id = x$play_id, reason = why))
}
r13_game_means <- function(p) {
  m <- p[, .(success = mean(success), plays = .N, completed_at = max(completed_at), available_at = max(available_at)),
         by = .(season, game_id, offense, defense)]
  r13_vendor_guard(m); r13_market_guard(m)
  m[]
}
# One season: raw plays + schedule -> game x offense mean success.
r13_season_means <- function(raw, g, vocab = "r8") {
  r13_assert(length(unique(raw$season)) == 1 && length(unique(g$season)) == 1, "One season at a time")
  st <- r13_states(r13_recover_fumbles(raw, vocab), g)
  el <- r13_eligible(st)
  list(means = r13_game_means(el$plays), audit = el$audit,
       fumbles = data.table(season = raw$season[1], total = sum(st$fumble_total & st$period %in% 1:4 & !st$bad_game & !st$stale_row),
                            recovered = sum(st$fumble_recovered & st$period %in% 1:4 & !st$bad_game & !st$stale_row)))
}

# ---- opponent-adjusted SR effects (v9_effects 'opponent' arm, home term zeroed) --
r13_effects <- function(means, ids, cutoff, lambda_off = R13$lambda_off, lambda_def = R13$lambda_def,
                        half_life = R13$half_life) {
  r13_vendor_guard(means); r13_market_guard(means)
  a <- means[available_at < cutoff]
  out <- data.table(team = ids, sr_off = 0, sr_def = 0, games_played = 0L)
  if (!nrow(a)) return(out)
  r13_assert(all(a$available_at < cutoff), "Effect cutoff leakage")
  r13_assert(length(unique(a$season)) == 1 && all(a$season != 2020), "Current-season solve cannot mix seasons or use 2020")
  w <- R13$row_weight * 2^(-as.numeric(difftime(cutoff, a$completed_at, units = "days")) / half_life)
  r13_assert(all(is.finite(a$success)) && all(is.finite(w)), "Nonfinite efficiency input")
  gp <- a[, .(g = uniqueN(game_id)), by = offense]
  out[, games_played := as.integer(gp$g[match(team, gp$offense)])][is.na(games_played), games_played := 0L]
  ents <- sort(unique(c(ids, a$offense, a$defense))); ne <- length(ents); nr <- nrow(a)
  io <- match(a$offense, ents); id <- match(a$defense, ents); j <- match(ids, ents)
  X <- Matrix::sparseMatrix(i = rep(seq_len(nr), 3), j = c(rep(1L, nr), 1 + io, 1 + ne + id),
                            x = c(rep(1, nr * 2), rep(-1, nr)), dims = c(nr, 1 + 2 * ne))
  A <- Matrix::crossprod(X, Matrix::Diagonal(x = w) %*% X) + Matrix::Diagonal(x = c(0, rep(lambda_off, ne), rep(lambda_def, ne)))
  b <- as.matrix(Matrix::solve(A, Matrix::crossprod(X, w * a$success)))[, 1]
  out[, `:=`(sr_off = b[1 + j], sr_def = b[1 + ne + j])]
  r13_assert(all(is.finite(out$sr_off)) && all(is.finite(out$sr_def)), "Nonfinite effect")
  out[]
}
# Weekly pregame snapshot for one season: one solve per Monday cutoff, attached to
# that week's final FBS-vs-FBS games (v9_snapshot). cutoff is returned as text.
r13_snapshot <- function(g, means) {
  ids <- sort(unique(c(g$home_team[g$home_fbs], g$away_team[g$away_fbs])))
  games <- g[final & home_fbs & away_fbs]
  rbindlist(lapply(sort(unique(games$cutoff)), function(cut) {
    te <- games[cutoff == cut]
    r <- r13_effects(means, ids, cut)
    h <- r[match(te$home_team, r$team)]; aw <- r[match(te$away_team, r$team)]
    data.table(season = te$season, game_id = te$game_id, cutoff = r13_stamp(cut),
               sr_off_home = h$sr_off, sr_def_home = h$sr_def, sr_off_away = aw$sr_off, sr_def_away = aw$sr_def,
               gp_home = h$games_played, gp_away = aw$games_played)
  }))[, `:=`(SRnet = (sr_off_home + sr_def_home) - (sr_off_away + sr_def_away), gp = pmin(gp_home, gp_away))][]
}

# ---- the stack ----------------------------------------------------------------
# No-intercept OLS of (actual - incumbent) on SRnet over gp >= 1 training games.
r13_fit_w <- function(train) {
  tr <- train[gp >= 1]
  r13_assert(nrow(tr) > 10 && all(is.finite(tr$SRnet)), "Too few stack training games")
  sum(tr$SRnet * (tr$actual_margin - tr$incumbent_margin)) / sum(tr$SRnet^2)
}
r13_apply <- function(incumbent, SRnet, gp, w) {
  n <- length(incumbent); SRnet <- rep_len(SRnet, n); gp <- rep_len(gp, n)
  out <- incumbent; k <- gp >= 1
  out[k] <- incumbent[k] + w * SRnet[k]
  out
}
# Walk-forward: target s uses a weight fit on seasons in [min_train, s) only.
r13_walk <- function(d, targets, min_train = R13$min_train) {
  r13_market_guard(d)
  r13_assert(!any(d$season == 2020), "2020 is excluded throughout")
  rbindlist(lapply(targets, function(s) {
    ws <- r13_fit_w(d[season >= min_train & season < s])
    te <- copy(d[season == s])
    te[, `:=`(w = ws, pred_margin = r13_apply(incumbent_margin, SRnet, gp, ws))]
  }))
}

# ---- forward guard (L6) ---------------------------------------------------------
# A forward snapshot may contain only games not yet kicked off, and no outcome or market fields.
r13_forward_guard <- function(games, snapshot_time) {
  r13_market_guard(games); r13_vendor_guard(games)
  outcome <- intersect(names(games), c("actual_margin", "home_points", "away_points", "home_score", "away_score"))
  r13_assert(!length(outcome), paste("Outcome field in forward snapshot:", paste(outcome, collapse = ", ")))
  k <- if (inherits(games$kickoff, "POSIXct")) games$kickoff else r13_parse_kickoff(games$kickoff)
  r13_assert(all(k > snapshot_time), "Forward snapshot includes a game that already kicked off")
  invisible(games)
}
