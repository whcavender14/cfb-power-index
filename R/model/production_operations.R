# =============================================================================
# R/model/production_operations.R — operational API for the frozen incumbent.
#
# Replaces the old folder's cfb_vCurrent_operations.R. The model mathematics
# are untouched: this file sources the verbatim engine
# (R/model/cfb_power_ratings_vCurrent.R) and only changes WHERE files are read
# from and written to, so the project no longer depends on the working
# directory containing cfb_data_v2/, cfb_data_v3/ and outputs/round4/.
#
# Differences from cfb_vCurrent_operations.R (all path-only):
#   * v4_schedule()      reads frozen schedules from PATHS$frozen/cfb_data_v3
#                        (redefined here; the engine's other functions pick up
#                        this definition because they look it up globally).
#   * v5_frozen()        resolves design_frozen.rds$source_manifest paths
#                        against PATHS$frozen before checking their MD5s.
#   * v5_build(), v5_frozen_features(), v5_archive_upcoming() take the design
#                        and feature files from PATHS$frozen.
#   * v5_weekly_update() is removed (scripts/01_build_ratings.R replaces it).
#   * v5_validation()    reads the Round 4 validation bundles from the legacy
#                        folder via config/legacy_paths.R.
# tests/test_reproduce_incumbent.R proves the ratings are identical to the
# old code's output.
#
# Requires config/paths.R to have been sourced (defines PATHS, frozen_path).
# =============================================================================

if (!exists("PATHS")) stop("Source config/paths.R before R/model/production_operations.R", call. = FALSE)
if (!exists("PRODUCTION")) source(file.path(PATHS$root, "config", "production.R"))

source(PATHS$model_engine)

V5_FROZEN_DESIGN_FILE      <- frozen_path("outputs", "round4", "design_frozen.rds")
V5_FROZEN_FEATURE_FILE     <- frozen_path("outputs", "round4", "features.rds")
V5_FROZEN_FEATURE_FILE_MD5 <- "f18013897d21334c74af3550b77842fe"

# Frozen, audited schedule snapshot for one season (2015-2026). Same logic as
# the engine's v4_schedule(); only the directory is configurable.
v4_schedule <- function(s) {
  cfg <- v4_config(); f <- frozen_path("cfb_data_v3", paste0("raw_schedule_", s, ".rds"))
  assert(file.exists(f), paste("Missing audited local schedule", f))
  cfg$cache_dir <- frozen_path("cfb_data_v3"); read_schedule(s, cfg, FALSE)
}

v5_frozen_features <- function(path = V5_FROZEN_FEATURE_FILE) {
  assert(file.exists(path), "Frozen feature bundle is missing")
  # key_of() reserializes an R object. That byte stream is not stable across
  # R releases, so an artifact created on macOS/R 4.3 can fail the self-hash
  # check after being read on Linux/R 4.4 even though the tracked RDS is exact.
  # Verify the immutable file bytes here; caller-supplied in-memory bundles
  # still have to pass the original object-hash check in v5_build().
  assert(identical(unname(tools::md5sum(path)), V5_FROZEN_FEATURE_FILE_MD5),
         "Frozen feature bundle file checksum mismatch")
  readRDS(path)
}

v5_frozen <- function(path = V5_FROZEN_DESIGN_FILE) {
  f <- readRDS(path); assert(f$max_selection_year == 2022, "Training lock invalid")
  # The design's model_manifest check stays disabled exactly as in production:
  # its recorded MD5 for cfb_power_ratings_v5.R predates the refactor that
  # inlined v4 into v5 (code-identical, different bytes).
  src <- frozen_path(f$source_manifest$path)
  assert(all(unname(tools::md5sum(src)) == f$source_manifest$md5), "Source artifacts changed since freeze")
  f
}

# Verify every frozen input without building anything. Returns a data.frame.
v5_verify_frozen_inputs <- function() {
  f <- readRDS(V5_FROZEN_DESIGN_FILE)
  paths <- c(V5_FROZEN_DESIGN_FILE, V5_FROZEN_FEATURE_FILE, frozen_path(f$source_manifest$path), PATHS$model_engine)
  expected <- c(PRODUCTION$design_file_md5, V5_FROZEN_FEATURE_FILE_MD5, f$source_manifest$md5, PRODUCTION$model_engine_md5)
  actual <- unname(tools::md5sum(paths))
  data.frame(path = sub(paste0("^", PATHS$root, "/"), "", paths), expected_md5 = expected,
             actual_md5 = actual, ok = !is.na(actual) & actual == expected, stringsAsFactors = FALSE)
}

v5_build <- function(season = 2026, as_of = period_start(Sys.time()), candidate = NULL, schedule = NULL,
                     freeze_file = V5_FROZEN_DESIGN_FILE, feature_bundle = NULL, counterfactual = FALSE) {
  f <- v5_frozen(freeze_file); if (is.null(candidate)) candidate <- f$selected
  assert(candidate %in% names(f$specs), "Undeclared candidate")
  as_of <- as.POSIXct(as_of, tz = "UTC"); assert(!is.na(as_of), "Invalid information cutoff")
  schedules <- setNames(lapply(2015:(season - 1), v4_schedule), 2015:(season - 1)); history <- v4_history(schedules)
  g <- if (is.null(schedule)) v4_schedule(season) else schedule; schedules[[as.character(season)]] <- g; ids <- fbs_ids(g)
  frozen_feature_file <- is.null(feature_bundle)
  if (frozen_feature_file) feature_bundle <- v5_frozen_features()
  features <- v5_validate_features(feature_bundle$features, setNames(lapply(2015:2026, v4_schedule), 2015:2026))
  # Preserve strict self-hash validation for injected bundles. The default
  # production artifact was already verified byte-for-byte above, avoiding a
  # false mismatch caused solely by cross-version R serialization.
  assert(frozen_feature_file || identical(key_of(feature_bundle$features), feature_bundle$hash),
         "Feature bundle hash mismatch")
  # Production must use the frozen feature snapshot; revised artifacts require a new archive/design.
  assert(identical(feature_bundle$hash, f$feature_hash), "Feature snapshot differs from design")
  spec <- f$specs[[candidate]]; par <- f$parameters[[candidate]]
  p <- v5_prior(season, ids, history, features, spec$features, counterfactual = counterfactual)
  tg <- team_games(g, ids, 0) %>% filter(available_at < as_of)
  hf <- median(unique(history %>% filter(season <= 2022) %>% select(season, hfa))$hfa)
  sn <- list(season = season, cutoff = as_of, ids = ids, pre = p$r, tg = tg, graph = v4_graph(g, ids, as_of),
             rows = v4_score_fit(tg, ids, lambda = 1, hfa = hf), hfa = hf, external_active = length(p$fits) > 0)
  conf <- if (isTRUE(spec$conference)) v5_conference(season, history, schedules) else NULL
  r <- v5_ratings(sn, spec, par, conf, v5_membership(g)); attrs <- attributes(r)
  r <- r %>% left_join(v5_membership(g), by = "team_id") %>% left_join(sn$graph %>% select(-conf), by = "team_id") %>%
    left_join(p$r %>% select(team_id, pre_off, pre_def, pre_power, prev_off, prev_def, u, promoted), by = "team_id") %>%
    left_join(features %>% filter(season == !!season) %>% select(team_id, feature_snapshot_id), by = "team_id") %>%
    arrange(desc(power_rating)) %>% mutate(rank = row_number())
  for (n in setdiff(names(attrs), c("names", "row.names", "class"))) attr(r, n) <- attrs[[n]]
  attr(r, "candidate") <- candidate; attr(r, "design_hash") <- unname(tools::md5sum(freeze_file)); attr(r, "feature_hash") <- f$feature_hash
  attr(r, "prior_fits") <- p; attr(r, "counterfactual") <- counterfactual; r
}

# Write-once prospective archive (unchanged from production).
v5_archive <- function(p, path, design_hash, feature_hash) {
  v5_no_market(p)
  allowed <- c("game_id", "season", "kickoff", "predicted_at", "information_cutoff", "home_id", "away_id", "neutral", "pred_margin",
               "candidate", "design_hash", "feature_hash", "home_snapshot_id", "away_snapshot_id")
  assert(setequal(names(p), allowed), "Archive schema must exclude outcomes and all undeclared columns")
  assert(!file.exists(path), "Archive exists: refusing overwrite")
  now <- Sys.time(); assert(nrow(p) > 0 && all(p$kickoff > now), "Past/empty prospective archive")
  assert(all(p$information_cutoff <= p$predicted_at & p$predicted_at <= now & p$predicted_at < p$kickoff), "Invalid prospective timestamps")
  assert(all(p$design_hash == design_hash) && all(p$feature_hash == feature_hash), "Archive design/feature hash mismatch")
  assert(!anyNA(p) && all(is.finite(p$pred_margin)) && !anyDuplicated(p$game_id), "Incomplete/duplicate archive")
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE); con <- file(path, "wx"); on.exit(close(con)); write.csv(p, con, row.names = FALSE); flush(con)
  writeLines(unname(tools::md5sum(path)), paste0(path, ".md5")); Sys.chmod(path, "0444")
  invisible(p)
}

# Archive predictions for every not-yet-kicked-off FBS-vs-FBS game. `schedule`
# should be the same (live) schedule the ratings were built from.
v5_archive_upcoming <- function(r, path, season = 2026, schedule = NULL) {
  assert(!isTRUE(attr(r, "counterfactual")), "Cannot archive counterfactual as operational")
  f <- v5_frozen(); design <- unname(tools::md5sum(V5_FROZEN_DESIGN_FILE))
  assert(identical(design, attr(r, "design_hash")) && identical(f$feature_hash, attr(r, "feature_hash")), "Ratings artifact mismatch")
  g <- if (is.null(schedule)) v4_schedule(season) else schedule; now <- Sys.time(); cut <- attr(r, "as_of")
  te <- g %>% filter(home_fbs, away_fbs, kickoff > now, kickoff >= cut)
  assert(!any(te$game_id %in% attr(r, "training_ids")), "Target game in training")
  p <- te %>% transmute(game_id, season, kickoff, predicted_at = now, information_cutoff = cut, home_id, away_id, neutral,
                        pred_margin = v4_predict(r, home_id, away_id, neutral), candidate = attr(r, "candidate"), design_hash = design, feature_hash = f$feature_hash,
                        home_snapshot_id = r$feature_snapshot_id[match(home_id, r$team_id)], away_snapshot_id = r$feature_snapshot_id[match(away_id, r$team_id)])
  v5_archive(p, path, design, f$feature_hash)
}

# Round 4 walk-forward validation bundles (large; they stay in the old folder).
v5_validation <- function(stage = c("development", "conditional")) {
  stage <- match.arg(stage)
  if (!exists("legacy_path")) source(file.path(PATHS$root, "config", "legacy_paths.R"))
  readRDS(legacy_path(paste0("round4_", stage, "_results")))
}
