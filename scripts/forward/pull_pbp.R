# Forward evidence, task 1: pull play-by-play for recently completed weeks BEFORE the Monday 00:00 UTC cutoff.
# Write-once raw files + hash-chained manifest. Scheduled Sunday afternoon local time (see docs/forward/FORWARD_SNAPSHOTS.md).
# Exit codes: 0 ok, 1 failure (nothing partial is recorded as complete).
# Usage: CFB_FORWARD_ARCHIVE=<dir> Rscript scripts/forward/pull_pbp.R
source("config/paths.R"); source("config/production.R")
suppressPackageStartupMessages({ source(PATHS$model_ops); source(file.path(PATHS$root, "R/forward/forward_lib.R")) })
archive <- Sys.getenv("CFB_FORWARD_ARCHIVE", file.path(PATHS$prospective, "forward"))
season <- as.integer(Sys.getenv("CFB_SEASON", PRODUCTION$supported_season))
run <- fwd_iso(); now <- Sys.time(); next_cutoff <- period_start(now) + 7 * 86400
status <- tryCatch({
  fwd_verify_manifest(archive)
  inp <- file.path(archive, "inputs", paste0("pbp_", fwd_stamp(now)))
  cfg <- v4_config(); cfg$cache_dir <- inp
  g <- read_schedule(season, cfg, refresh = TRUE)
  sf <- file.path(inp, sprintf("raw_schedule_%d.rds", season)); Sys.chmod(sf, "0444")
  fwd_manifest_append(archive, "input", "schedule", season, sf, fwd_sha256(sf))
  m <- fwd_read_manifest(archive)[kind == "pbp"]
  done <- unique(sub("_\\d{8}T\\d{6}Z\\.rds$", "", basename(m$path)))
  wk <- as.data.table(g)[final & kickoff < now & (home_fbs | away_fbs), .(last = max(kickoff)), by = .(season_type, week)]
  wk <- wk[last > now - 9 * 86400 | !sprintf("plays_%s_wk%02d", season_type, week) %in% done]
  for (i in seq_len(nrow(wk))) {
    x <- cfbfastR::cfbd_plays(year = season, season_type = wk$season_type[i], week = wk$week[i])
    fwd_assert(NROW(x) > 0, sprintf("Empty play-by-play pull for %s week %d", wk$season_type[i], wk$week[i]))
    f <- file.path(archive, "pbp", season, sprintf("plays_%s_wk%02d_%s.rds", wk$season_type[i], wk$week[i], fwd_stamp()))
    fwd_archive_file(archive, x, f, "pbp", "pbp", season, "rds")
    fwd_log(archive, run, sprintf("pbp %s wk%02d", wk$season_type[i], wk$week[i]), "ok",
            sprintf("rows=%d; before next cutoff %s: %s", NROW(x), fwd_iso(next_cutoff), Sys.time() < next_cutoff))
  }
  fwd_log(archive, run, "pull_pbp", "ok", sprintf("%d week(s) pulled", nrow(wk))); 0L
}, error = function(e) { fwd_log(archive, run, "pull_pbp", "FAIL", conditionMessage(e)); message("FAIL: ", conditionMessage(e)); 1L })
quit(status = status, save = "no")
