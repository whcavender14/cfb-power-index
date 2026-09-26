# =====================================================================================================================
# R/production/production_model.R: the model-selection layer. Every production consumer gets its ratings here.
#
#   production_model_id()          the model production runs: config/production_model.R (default C2_current), or an
#                                  explicit CFB_PRODUCTION_MODEL=EB_features for benchmark or rollback runs; else error
#   production_build(...)          ratings at a cutoff in the v5_build() schema (team_id, team, conf, power_rating,
#                                  off_rating, def_rating, games_played, pre_power, ...; attrs hfa, as_of,
#                                  training_ids, candidate, design_hash, feature_hash)
#   production_nonfbs_power(r, id) simulation power of non-FBS teams, under the model that produced `r`
#   production_sim_params(r)       simulation home field / margin SD, under the model that produced `r`
#
# The routing is keyed on the model that produced the ratings, so one ratings object never mixes models. Nothing here
# falls back to the incumbent: a failing or unknown model stops the caller.
# Requires config/paths.R (sources the model code and configs it needs).
# =====================================================================================================================
if (!exists("PRODUCTION")) source(file.path(PATHS$root, "config", "production.R"))
if (!exists("PRODUCTION_MODEL")) source(file.path(PATHS$root, "config", "production_model.R"))
if (!exists("v5_build")) suppressPackageStartupMessages(source(PATHS$model_ops))
if (!exists("c2_production_build")) source(PATHS$c2_production)

production_model_id <- function() {
  id <- Sys.getenv("CFB_PRODUCTION_MODEL", PRODUCTION_MODEL$default)
  if (!id %in% PRODUCTION_MODEL$choices)
    stop("Unknown CFB_PRODUCTION_MODEL '", id, "'; choices: ", paste(PRODUCTION_MODEL$choices, collapse = ", "), call. = FALSE)
  if (!identical(id, PRODUCTION_MODEL$default)) message("NOTE: running the NON-default model ", id, " (CFB_PRODUCTION_MODEL).")
  id
}

# schedule: the season's parsed schedule (NULL = the frozen schedule); schedule_dir: the directory holding the matching
# raw_schedule_<season>.rds (read_schedule()'s cache_dir). candidate: EB_features family only (01_build_ratings arg 2).
production_build <- function(season, as_of, schedule = NULL, schedule_dir = NULL, candidate = NULL, model = production_model_id()) {
  message("Production model: ", model)
  switch(model,
    EB_features = v5_build(season = season, as_of = as_of, candidate = candidate, schedule = schedule),
    C2_current = {
      if (!is.null(candidate)) stop("A v5 candidate name was given, but the production model is C2_current.", call. = FALSE)
      if (is.null(schedule)) { schedule <- v4_schedule(season); schedule_dir <- frozen_path("cfb_data_v3") }
      if (is.null(schedule_dir)) stop("C2 needs the raw schedule directory that matches `schedule`.", call. = FALSE)
      as_of <- as.POSIXct(as_of, tz = "UTC")
      c2_production_build(season, as_of, schedule, readRDS(file.path(schedule_dir, sprintf("raw_schedule_%d.rds", season))),
                          cache_dir = file.path(PATHS$state, "c2_live", format(as_of, "%Y%m%dT%H%M%SZ", tz = "UTC")))
    })
}

production_model_of <- function(ratings) {
  cand <- attr(ratings, "candidate")
  if (identical(cand, PRODUCTION_MODEL$c2$candidate)) return("C2_current")
  if (length(cand) == 1L && cand %in% names(v5_frozen()$specs)) return("EB_features")
  stop("Ratings carry an unknown model identity: ", format(cand), call. = FALSE)
}

production_nonfbs_power <- function(ratings, team_ids) {
  if (production_model_of(ratings) == "EB_features") return(rep(PRODUCTION$sim_fcs_power, length(team_ids)))  # incumbent convention
  nf <- attr(ratings, "nonfbs_ratings"); p <- nf$power[match(team_ids, nf$team_id)]
  if (anyNA(p) || any(!is.finite(p))) stop("Current C2 has no rating for non-FBS team(s): ",
                                           paste(team_ids[!is.finite(p)], collapse = ", "), call. = FALSE)
  p
}

production_sim_params <- function(ratings) {
  if (production_model_of(ratings) == "EB_features")
    return(list(hfa = PRODUCTION$sim_hfa, resid_sd = PRODUCTION$sim_resid_sd, fcs_power = PRODUCTION$sim_fcs_power,
                nonfbs_power_source = "every FCS opponent at a constant -25 (incumbent convention)"))
  list(hfa = attr(ratings, "hfa"), resid_sd = PRODUCTION_MODEL$c2$sigma, fcs_power = NA_real_,
       nonfbs_power_source = paste("Current C2's own ratings of FCS and lower-division teams (Stage 3 group levels;",
                                   "first-game rating before a team's first game)"))
}
