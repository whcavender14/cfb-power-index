# =============================================================================
# config/production_model.R: WHICH model production runs (promotion 2026-09-26).
#
# The production model is Current C2 (research tag c2-post-stage4-baseline,
# commit 6a187ea, Round 16 verdict QUALIFIED (historical): PRODUCTION
# CANDIDATE). Every production consumer (01_build_ratings, the season
# simulation and, through their outputs, the exports and the site) asks
# R/production/production_model.R for ratings. That module reads this file.
#
# The former incumbent (EB_features v5, frozen 2026-09-09) is unchanged. Its
# identity and the shared simulation/CFP conventions stay in
# config/production.R. It remains runnable as a benchmark and for rollback:
#   CFB_PRODUCTION_MODEL=EB_features Rscript scripts/run_weekly_pipeline.R
# That is an explicit, logged choice. No code path falls back to the incumbent
# when C2 fails: a C2 failure stops the build.
# Rollback without the switch: git tag production-incumbent-rollback (= e468b32).
# =============================================================================

PRODUCTION_MODEL <- list(
  default        = "C2_current",
  choices        = c("C2_current", "EB_features"),
  promoted       = "2026-09-26",
  production_tag = "c2-production-v1",
  rollback_tag   = "production-incumbent-rollback",   # e468b32, the last incumbent production commit

  c2 = list(
    candidate        = "C2_current",
    label            = "Current C2",
    research_tag     = "c2-post-stage4-baseline",
    research_commit  = "6a187ea1f38fb5fc002b84b92afb9190916d4947",
    supported_season = 2026L,

    # Frozen season inputs built once by scripts/production/c2_freeze_season_inputs.R (Round 16 §9). MD5 of file bytes.
    season_inputs     = file.path("data", "frozen", "c2", "c2_season_inputs_2026.rds"),
    season_inputs_md5 = "7618cbdd33561c950c5a02344c0cd284",

    # The model code, byte-identical to the research tag. MD5 is checked before every build.
    code_md5 = c(
      "R/c2/c2_current.R"                    = "d5696a9e25e00eea4556f6961ecc88a7",
      "R/round15/candidates/data.R"          = "5c4a209a57a64779dd7b9f4d125f9a0f",
      "R/round15/candidates/c1.R"            = "b26f43a5f5003727fb8f99be49a781a6",
      "R/round15/candidates/c2.R"            = "140951d188eda49010161e45621be17f",
      "R/round15/prep/fumble_parser.R"       = "285254283115d7b9acf06ff5b15c3c55",
      "R/round15/prep/sr_history.R"          = "229cc7d2dfea22c77c717593721dd66d",
      "R/round15/prep/passer_parser.R"       = "57ef9c4a26d7efea2204ae22909c47c0",
      "R/round15/cfbd_client.R"              = "9957ffef3840524bb39fa0e54e8454ee",
      "R/forward/vendor/round13_sr_stack.R"  = "5896c3c12b8aadc4de6769545e7781f9"
    ),

    # Home field: C2's H for 2023+ (R15C$frozen_hfa), the same value as the incumbent's hfa_points.
    hfa = 3.06853968902663,
    # Probability scale: C2's frozen Round 16 sigma, fitted on all development seasons and predeclared for 2023-25 and
    # forward (docs/round16/results/sigma.csv, model C). Used for the simulation's margin SD and the CFP resume spec.
    sigma        = 15.6500874177702,
    sigma_source = "Round 16 frozen sigma (docs/round16/results/sigma.csv, model C, all development seasons)",

    # Operational fetch guard: at most this many final FBS-vs-FBS games before the cutoff may be absent from the
    # play-by-play pull. More than that means the pull is broken, and the build stops rather than rating partial data.
    max_missing_pbp_games = 3L
  )
)
