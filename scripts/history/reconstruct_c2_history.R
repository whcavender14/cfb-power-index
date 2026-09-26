# =============================================================================
# scripts/history/reconstruct_c2_history.R: rebuild CFPi+ (Current C2) ratings
# at past weekly cutoffs that were published by a different model.
#
# C2 is point-in-time: only final games with available_at < cutoff enter the
# solve (R/production/c2_production.R). Re-running the unchanged production
# entry point at an old cutoff, on the cached schedule and play-by-play the
# live run already used, therefore gives the rating C2 would have published
# then, except for any later CFBD data revisions.
#
# Guard: the script first rebuilds the latest published cutoff and stops unless
# it reproduces the published snapshot exactly (every team, every rating).
#
# Usage (CFB_DATA_DIR = the state folder of a live run with its caches):
#   Rscript scripts/history/reconstruct_c2_history.R 2026-09-07T00:00:00Z 2026-09-14T00:00:00Z
# Writes data/history/c2_reconstructed_<season>.csv (committed; read by the site exporter).
# =============================================================================
source("config/paths.R")
source(PATHS$production_model)
suppressPackageStartupMessages({ library(dplyr); library(data.table) })

parse_cutoff <- function(x) as.POSIXct(x, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
cutoffs <- parse_cutoff(commandArgs(trailingOnly = TRUE))
stopifnot(length(cutoffs) >= 1L, !anyNA(cutoffs))

latest <- readRDS(file.path(PATHS$state, sprintf("production_ratings_%d_latest.rds", 2026L)))
stopifnot(identical(latest$candidate, "C2_current"))
season <- latest$season
live <- file.path(PATHS$state, "production_live")
cfg <- v4_config(); cfg$cache_dir <- live
schedule <- read_schedule(season, cfg, refresh = FALSE)
raw <- readRDS(file.path(live, sprintf("raw_schedule_%d.rds", season)))
cache <- file.path(PATHS$state, "c2_live", format(latest$as_of, "%Y%m%dT%H%M%SZ", tz = "UTC"))
stopifnot(dir.exists(cache))
build <- function(as_of) c2_production_build(season, as_of, schedule, raw, cache_dir = cache)

# 1. Reproduction guard.
chk <- build(latest$as_of)
pub <- latest$ratings
m <- merge(as.data.frame(pub)[, c("team_id", "power_rating", "off_rating", "def_rating")],
           as.data.frame(chk)[, c("team_id", "power_rating", "off_rating", "def_rating")], by = "team_id")
dev <- max(abs(m$power_rating.x - m$power_rating.y), abs(m$off_rating.x - m$off_rating.y), abs(m$def_rating.x - m$def_rating.y))
if (nrow(m) != nrow(pub) || dev > 1e-9) stop(sprintf("Rebuild of the published cutoff differs (max %.3g over %d teams): not reconstructing.", dev, nrow(m)))
cat(sprintf("Reproduction guard passed: %d teams, max |difference| = %.3g\n", nrow(m), dev))

# 2. Past cutoffs.
out <- rbindlist(lapply(seq_along(cutoffs), function(i) {
  as_of <- cutoffs[i]; build_last <- build(as_of); r <- as.data.frame(build_last)
  obs <- schedule$final %in% TRUE & schedule$available_at < as_of
  wk <- if (any(obs)) max(schedule$week[obs]) else 0L
  r <- r[order(-r$power_rating, r$team_id), ]
  nf <- attr(build_last, "nonfbs_ratings")
  fbs <- data.table(team_id = as.integer(r$team_id), fbs = TRUE, rank = seq_len(nrow(r)), power = r$power_rating,
                    off = r$off_rating, def = r$def_rating, games_played = as.integer(r$games_played))
  # Non-FBS opponents' ratings at the same cutoff (needed to project past games against them).
  non <- data.table(team_id = as.integer(nf$team_id), fbs = FALSE, rank = NA_integer_, power = nf$power,
                    off = NA_real_, def = NA_real_, games_played = as.integer(nf$gp))
  cbind(data.table(season = season, week = as.integer(wk), as_of = format(as_of, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")),
        rbind(fbs, non),
        data.table(model_version = attr(r, "model_version"), design_hash = attr(r, "design_hash"), feature_hash = attr(r, "feature_hash"),
                   reconstructed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")))
}))
stopifnot(all(out$design_hash == latest$design_hash), all(out$feature_hash == latest$feature_hash))
f <- file.path(PATHS$root, "data", "history", sprintf("c2_reconstructed_%d.csv", season))
fwrite(out, f)
cat("Wrote", nrow(out), "rows for weeks", paste(unique(out$week), collapse = ", "), "to", f, "\n")
