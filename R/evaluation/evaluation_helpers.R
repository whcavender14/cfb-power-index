# =============================================================================
# R/evaluation/evaluation_helpers.R — reusable scoring for future candidates.
#
# NEW in the revised folder. Every round from 3 to 12 rebuilt its own versions
# of these routines, and two rounds were derailed by small inconsistencies
# (Round 11's unoriented bias metric; Round 12's bootstrap that parsed a text
# cutoff with as.numeric() and silently collapsed its blocks). This file puts
# one audited implementation of the project's conventions in one place.
#
# Conventions (see docs/EVALUATION_PROTOCOL.md):
#   * error      = pred_margin - actual_margin   (home perspective; engine convention)
#   * MAE        = mean |error| over the SAME game_ids for every model compared
#   * paired     = candidate |error| - incumbent |error|; negative favours the candidate
#   * bootstrap  = resample seasons, then (optionally) whole weekly-cutoff blocks
#                  within each sampled season; blocks keyed on the cutoff TEXT
#   * P4 bias    = mean((actual - pred) * s), s = +1 P4 home vs G5 away,
#                  -1 G5 home vs P4 away, 0 otherwise; season-indexed tier map
#                  (Pac-12 is P4 through 2025 and G5 from 2026)
#   * calibration slope = lm(actual - HFA*!neutral ~ pred - HFA*!neutral);
#                  a diagnostic only. Never force it to 1 (Round 8).
#
# Requires config/paths.R (for the tier map and incumbent prediction files).
# =============================================================================

if (!exists("PATHS")) stop("Source config/paths.R first", call. = FALSE)

# ---- Tier map ---------------------------------------------------------------
load_tier_map <- function(path = PATHS$tier_map) {
  m <- utils::read.csv(path, stringsAsFactors = FALSE)
  stopifnot(all(c("conference", "season_from", "season_to", "tier") %in% names(m)))
  m
}

tier_of <- function(conference, season, map = load_tier_map()) {
  stopifnot(length(season) %in% c(1L, length(conference)))
  season <- rep_len(season, length(conference))
  out <- rep("Other", length(conference))
  for (i in seq_len(nrow(map))) {
    hit <- !is.na(conference) & conference == map$conference[i] &
      season >= map$season_from[i] & season <= map$season_to[i]
    out[hit] <- map$tier[i]
  }
  out
}

# +1 when a P4 team hosts a G5 team, -1 when a G5 team hosts a P4 team, else 0.
p4_orientation <- function(home_conference, away_conference, season, map = load_tier_map()) {
  h <- tier_of(home_conference, season, map); a <- tier_of(away_conference, season, map)
  ifelse(h == "P4" & a == "G5", 1L, ifelse(h == "G5" & a == "P4", -1L, 0L))
}

# Positive = the model UNDER-rates the P4 side (the incumbent's known defect).
p4_oriented_bias <- function(d) {
  s <- p4_orientation(d$home_conference, d$away_conference, d$season)
  x <- (d$actual_margin - d$pred_margin) * s
  data.frame(n = sum(s != 0), bias = if (any(s != 0)) mean(x[s != 0]) else NA_real_,
             se = if (sum(s != 0) > 1) stats::sd(x[s != 0]) / sqrt(sum(s != 0)) else NA_real_)
}

# ---- Point metrics ----------------------------------------------------------
margin_metrics <- function(d, hfa = if ("hfa" %in% names(d)) d$hfa else 0) {
  stopifnot(all(c("pred_margin", "actual_margin", "neutral") %in% names(d)))
  err <- d$pred_margin - d$actual_margin
  site <- hfa * as.numeric(!as.logical(d$neutral))
  x <- d$pred_margin - site; y <- d$actual_margin - site
  fit <- stats::lm(y ~ x)
  data.frame(n = nrow(d), mae = mean(abs(err)), rmse = sqrt(mean(err^2)), bias = mean(err),
             cor = stats::cor(d$pred_margin, d$actual_margin),
             calib_intercept = unname(stats::coef(fit)[1]), calib_slope = unname(stats::coef(fit)[2]),
             sd_ratio = stats::sd(d$pred_margin) / stats::sd(d$actual_margin),
             straight_up = mean(sign(d$pred_margin) == sign(d$actual_margin) & d$actual_margin != 0))
}

# ---- Bootstrap --------------------------------------------------------------
# Two-level block bootstrap: seasons with replacement ("season" interval), and
# seasons then weekly-cutoff blocks within each season ("block" interval).
# Mirrors the engine's v5_boot(), but keys blocks on as.character(cutoff) and
# fails loudly on missing keys (the Round 12 run-1 defect).
block_bootstrap <- function(d, value = "delta", reps = 2000L, seed = 9041L, block = "cutoff") {
  stopifnot(value %in% names(d), "season" %in% names(d), block %in% names(d))
  key <- as.character(d[[block]])
  if (anyNA(key) || any(!nzchar(key))) stop("Missing bootstrap block keys in column '", block, "'.")
  set.seed(seed)
  seasons <- unique(d$season)
  blocks <- lapply(seasons, function(s) split(which(d$season == s), key[d$season == s]))
  v <- d[[value]]
  draws <- replicate(reps, {
    si <- sample(seq_along(seasons), length(seasons), replace = TRUE)
    ix <- unlist(lapply(si, function(j) unlist(blocks[[j]], use.names = FALSE)), use.names = FALSE)
    bi <- unlist(lapply(si, function(j) {
      b <- blocks[[j]]; unlist(b[sample(seq_along(b), length(b), replace = TRUE)], use.names = FALSE)
    }), use.names = FALSE)
    c(season = mean(v[ix]), block = mean(v[bi]))
  })
  data.frame(estimate = mean(v),
             season_low = unname(stats::quantile(draws[1, ], 0.025)), season_high = unname(stats::quantile(draws[1, ], 0.975)),
             block_low = unname(stats::quantile(draws[2, ], 0.025)), block_high = unname(stats::quantile(draws[2, ], 0.975)),
             seasons = length(seasons), blocks = sum(lengths(blocks)))
}

# ---- Incumbent baseline -----------------------------------------------------
# Round 4 walk-forward predictions of the frozen incumbent (EB_features):
#   development = 2019, 2021, 2022 (2,320 games; MAE 12.920)
#   conditional = 2023-2025        (2,398 games; MAE 12.518; already exposed)
load_incumbent_predictions <- function(split = c("development", "conditional")) {
  split <- match.arg(split)
  path <- if (split == "development") PATHS$incumbent_dev else PATHS$incumbent_cond
  utils::read.csv(path, colClasses = c(game_id = "character", cutoff = "character", kickoff = "character"),
                  stringsAsFactors = FALSE)
}

# Compare a candidate (data.frame with game_id + pred_margin) to the incumbent
# on the identical game universe. Returns metrics, paired bootstrap, P4 bias.
compare_to_incumbent <- function(candidate, split = c("development", "conditional"),
                                 reps = 2000L, seed = 9041L) {
  split <- match.arg(split)
  inc <- load_incumbent_predictions(split)
  stopifnot(all(c("game_id", "pred_margin") %in% names(candidate)), !anyDuplicated(candidate$game_id))
  if (!setequal(candidate$game_id, inc$game_id)) {
    stop("Candidate and incumbent game universes differ (", length(setdiff(inc$game_id, candidate$game_id)),
         " incumbent games missing, ", length(setdiff(candidate$game_id, inc$game_id)), " extra).")
  }
  inc$abs_error <- abs(inc$pred_margin - inc$actual_margin)   # recompute; CSV values are rounded
  cand <- inc; cand$pred_margin <- candidate$pred_margin[match(inc$game_id, candidate$game_id)]
  cand$abs_error <- abs(cand$pred_margin - cand$actual_margin)
  paired <- inc; paired$delta <- cand$abs_error - inc$abs_error
  per_season <- stats::aggregate(delta ~ season, paired, mean)
  list(split = split,
       incumbent = margin_metrics(inc), candidate = margin_metrics(cand),
       paired = cbind(block_bootstrap(paired, "delta", reps, seed), seasons_improved = sum(per_season$delta < 0)),
       per_season = per_season,
       p4_bias = rbind(cbind(model = "incumbent", p4_oriented_bias(inc)),
                       cbind(model = "candidate", p4_oriented_bias(cand))))
}
