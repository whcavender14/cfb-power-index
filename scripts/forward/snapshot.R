# Forward evidence, task 2: write-once pre-kickoff prediction snapshots for the current weekly period.
# Models: incumbent (always), Round 13 K (always; flagged late_pull if its play-by-play was pulled after the cutoff),
# Current C2 (production since 2026-09-26) and frozen Round 15 C2 (Round 16 §9; same late_pull rule; they also archive
# this run's FCS-involved schedule), Round 15 candidates (only once a signed freeze manifest exists).
# Evidence only: no refit, promotion or deployment.
# Exit codes: 0 ok (or nothing to predict), 1 run failure (no snapshot written), 2 partial (incumbent written, a later model failed).
# Usage: CFB_FORWARD_ARCHIVE=<dir> Rscript scripts/forward/snapshot.R
source("config/paths.R"); source("config/production.R")
suppressPackageStartupMessages({ source(PATHS$model_ops); source(file.path(PATHS$root, "R/forward/forward_lib.R")); source(file.path(PATHS$root, "R/forward/forward_models.R")) })
archive <- Sys.getenv("CFB_FORWARD_ARCHIVE", file.path(PATHS$prospective, "forward"))
season <- as.integer(Sys.getenv("CFB_SEASON", PRODUCTION$supported_season))
fwd_assert(identical(season, PRODUCTION$supported_season), "The frozen incumbent supports only its design season; 2027 needs the extension")
run <- fwd_iso(); now <- Sys.time(); cutoff <- period_start(now); stamp <- fwd_stamp(now)
snap_dir <- function(model) file.path(archive, "snapshots", model, season)
write_model <- function(model, res, csv_writer = NULL) {
  base <- sprintf("%s_%d_cut%s_%s", model, season, format(cutoff, "%Y%m%d", tz = "UTC"), stamp)
  csv <- file.path(snap_dir(model), paste0(base, ".csv"))
  if (is.null(csv_writer)) fwd_archive_file(archive, res$pred, csv, "snapshot", model, season, "csv") else {
    csv_writer(res$pred, csv); Sys.chmod(paste0(csv, ".md5"), "0444")
    fwd_manifest_append(archive, "snapshot", model, season, csv, fwd_sha256(csv))
    fwd_manifest_append(archive, "snapshot_md5", model, season, paste0(csv, ".md5"), fwd_sha256(paste0(csv, ".md5"))) }
  meta <- c(common, list(model = model, rows = nrow(res$pred), model_meta = res$meta))
  fwd_archive_file(archive, meta, file.path(snap_dir(model), paste0(base, ".json")), "meta", model, season, "json")
  fwd_log(archive, run, model, if (isTRUE(res$meta$late_pull)) "ok_late_pull" else "ok", sprintf("%d games; file %s", nrow(res$pred), basename(csv)))
}

status <- tryCatch({
  fwd_verify_manifest(archive)
  inp <- file.path(archive, "inputs", paste0("snapshot_", stamp))
  cfg <- v4_config(); cfg$cache_dir <- inp
  g <- read_schedule(season, cfg, refresh = TRUE)
  sf <- file.path(inp, sprintf("raw_schedule_%d.rds", season)); Sys.chmod(sf, "0444")
  fwd_manifest_append(archive, "input", "schedule", season, sf, fwd_sha256(sf))
  unresolved <- fwd_unresolved(g, cutoff)
  fwd_assert(nrow(unresolved) <= FWD$max_unresolved, sprintf("%d FBS-vs-FBS games before the cutoff have no final result; refusing to snapshot on incomplete information", nrow(unresolved)))
  targets <- fwd_targets(g, now, cutoff)
  gd <- as.data.table(g)
  excluded <- gd[home_fbs & away_fbs & period == cutoff & !game_id %in% targets$game_id, .(game_id, kickoff = fwd_iso(kickoff), final)]
  if (!nrow(targets)) { fwd_log(archive, run, "snapshot", "ok_no_targets", sprintf("cutoff %s", fwd_iso(cutoff))); 0L } else {
    common <- c(fwd_provenance(PATHS$root), list(run_utc = run, snapshot_utc = fwd_iso(now), information_cutoff = fwd_iso(cutoff), season = season,
                  schedule_input = list(path = fwd_rel(sf, archive), sha256 = fwd_sha256(sf), retrieved_utc = run),
                  unresolved_before_cutoff = unresolved[, .(game_id, kickoff = fwd_iso(kickoff))],
                  excluded_current_period = excluded, kickoff_margin_minutes = FWD$kickoff_margin_min))
    inc <- fwd_model_incumbent(g, cutoff, targets, now)
    fwd_guard_snapshot(inc$pred, now, allow = c("design_hash", "feature_hash", "home_snapshot_id", "away_snapshot_id"))
    write_model("incumbent", inc, csv_writer = function(p, path) v5_archive(p, path, inc$meta$design_md5, inc$meta$feature_hash))
    code <- 0L
    this_season <- season
    pulls <- fwd_read_manifest(archive)[kind == "pbp" & season == this_season]
    k <- tryCatch({
      fwd_assert(nrow(pulls) > 0, "No play-by-play pulls archived for this season")
      pulls[, `:=`(file = file.path(archive, path), pulled_at = as.POSIXct(recorded_utc, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                   season_type = sub("^plays_([a-z]+)_wk.*$", "\\1", basename(path)), week = as.integer(sub("^.*_wk(\\d+)_.*$", "\\1", basename(path))))]
      res <- fwd_model_r13K(readRDS(sf), pulls, cutoff, targets, inc$pred, now)
      fwd_guard_snapshot(res$pred, now, allow = character()); write_model("round13_K", res); 0L
    }, error = function(e) { fwd_log(archive, run, "round13_K", "FAIL", conditionMessage(e)); message("round13_K FAIL: ", conditionMessage(e)); 2L })
    c2 <- tryCatch({
      c2pulls <- fwd_c2_pulls(archive, season)
      if (!exists("c2p_fcs_games")) source(PATHS$production_model)
      fcs <- c2p_fcs_games(season, inp)
      fwd_archive_file(archive, fcs, file.path(inp, sprintf("fcs_games_%d.rds", season)), "input", "fcs_schedule", season, "rds")
      res <- fwd_model_c2(g, readRDS(sf), c2pulls, fcs, cutoff, targets, now)
      for (m in names(res)) fwd_guard_snapshot(res[[m]]$pred, now, allow = character())
      for (m in names(res)) write_model(m, res[[m]])
      0L
    }, error = function(e) { fwd_log(archive, run, "c2", "FAIL", conditionMessage(e)); message("c2 FAIL: ", conditionMessage(e)); 2L })
    k <- max(k, c2)
    if (file.exists(R15_FREEZE)) {
      r15 <- tryCatch({ fwd_model_round15(); 0L }, error = function(e) { fwd_log(archive, run, "round15", "FAIL", conditionMessage(e)); 2L })
      k <- max(k, r15)
    } else fwd_log(archive, run, "round15", "skipped", "Round 15 candidates not frozen")
    max(code, k)
  }
}, error = function(e) { fwd_log(archive, run, "snapshot", "FAIL", conditionMessage(e)); message("FAIL: ", conditionMessage(e)); 1L })
quit(status = status, save = "no")
