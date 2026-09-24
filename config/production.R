# =============================================================================
# config/production.R — frozen constants of the current production model.
#
# These values identify the incumbent (Round 4 "EB_features", frozen
# 2026-09-09) and the assumptions of the season simulation. They are recorded
# here so that scripts, tests and future challengers all compare against the
# same, explicitly named baseline. Changing any of them means you are no
# longer running the incumbent: make a new design/freeze instead.
# =============================================================================

PRODUCTION <- list(
  # ---- Model identity -------------------------------------------------------
  candidate            = "EB_features",
  model_version        = "5.0.0",               # design_frozen.rds$version
  max_selection_year   = 2022L,                  # no outcome after 2022 chose anything
  supported_season     = 2026L,                  # feature bundle + schedules cover 2015-2026 only

  # Checksums of the frozen artifacts (MD5 of the file bytes).
  design_file_md5      = "0f876d7390dace668ab8fb80547b949e",  # data/frozen/outputs/round4/design_frozen.rds
  feature_file_md5     = "f18013897d21334c74af3550b77842fe",  # data/frozen/outputs/round4/features.rds
  feature_object_hash  = "6a7e01742348969e8c623e21702185c6",  # design_frozen.rds$feature_hash
  model_engine_md5     = "711d01aa3562decdd3a3dcd3e4676765",  # R/model/cfb_power_ratings_vCurrent.R

  # Fitted parameters of EB_features (read from design_frozen.rds; listed for reference).
  prior_precision      = 4,                      # ridge penalty pulling o/d toward the scaled prior
  preseason_scale      = 1.12271478057756,       # multiplier on the preseason prior
  hfa_points           = 3.06853968902663,       # prediction home-field advantage

  # ---- Season simulation assumptions (NOT estimated by the model) -----------
  sim_count            = 1000L,
  sim_seed             = 1434L,
  sim_resid_sd         = 15.7874822415908,       # v5_calibration() RMSE, EB_features, 2023-25 (n = 2398)
  sim_hfa              = 3.0685,
  sim_fcs_power        = -25,                    # every FCS opponent
  playoff_seeds        = 12L,
  playoff_autobid      = "2026",

  # ---- Evaluation conventions -----------------------------------------------
  bootstrap_seed       = 9041L,
  bootstrap_reps       = 2000L,
  development_seasons  = c(2019L, 2021L, 2022L), # Round 4 split (Rounds 9-12 added 2018)
  conditional_seasons  = 2023:2025               # already exposed; not a clean test any more
)
