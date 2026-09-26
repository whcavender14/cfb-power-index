# =============================================================================
# config/paths.R — the ONE place where file locations are defined.
#
# Every script in this project sources this file first. Nothing else should
# hard-code a path. Override any location with an environment variable (listed
# next to each entry) instead of editing code.
#
#   source("config/paths.R")          # from the project root, or
#   source(file.path(root, "config/paths.R"))
#
# Legacy (old-folder) locations live in config/legacy_paths.R, not here.
# =============================================================================

# Locate the project root: $CFB_PROJECT_ROOT if set, otherwise walk upward from
# the working directory until a folder containing config/paths.R is found.
cfb_project_root <- function() {
  env <- Sys.getenv("CFB_PROJECT_ROOT", "")
  if (nzchar(env)) return(normalizePath(env, mustWork = TRUE))
  d <- normalizePath(getwd(), mustWork = TRUE)
  repeat {
    if (file.exists(file.path(d, "config", "paths.R"))) return(d)
    parent <- dirname(d)
    if (identical(parent, d)) {
      stop("Cannot find the project root (a folder containing config/paths.R). ",
           "Run from inside 'Revised CFB Modeling' or set CFB_PROJECT_ROOT.", call. = FALSE)
    }
    d <- parent
  }
}

PROJECT_ROOT <- cfb_project_root()
.cfb_env <- function(var, default) {
  v <- Sys.getenv(var, "")
  if (nzchar(v)) v else default
}

PATHS <- list(
  root = PROJECT_ROOT,

  # --- Code ------------------------------------------------------------------
  model_engine   = file.path(PROJECT_ROOT, "R", "model", "cfb_power_ratings_vCurrent.R"),
  model_ops      = file.path(PROJECT_ROOT, "R", "model", "production_operations.R"),
  # Production model selection (config/production_model.R) and the Current C2 adapter.
  production_model = file.path(PROJECT_ROOT, "R", "production", "production_model.R"),
  c2_production  = file.path(PROJECT_ROOT, "R", "production", "c2_production.R"),
  dynamic_cfp    = file.path(PROJECT_ROOT, "R", "simulation", "cfb_dynamic_playoffs.R"),
  simulate       = file.path(PROJECT_ROOT, "R", "simulation", "simulate_season.R"),
  betting_funs   = file.path(PROJECT_ROOT, "R", "publish", "betting_functions.R"),
  export_public  = file.path(PROJECT_ROOT, "R", "publish", "export_public_data.R"),
  export_betting = file.path(PROJECT_ROOT, "R", "publish", "export_betting_data.R"),
  export_site    = file.path(PROJECT_ROOT, "R", "publish", "export_site_data.R"),
  pull_players   = file.path(PROJECT_ROOT, "R", "publish", "pull_player_stats.R"),
  graphic        = file.path(PROJECT_ROOT, "R", "publish", "rankings_graphic.R"),
  eval_helpers   = file.path(PROJECT_ROOT, "R", "evaluation", "evaluation_helpers.R"),

  # --- Frozen production inputs (read-only; checksummed by design_frozen.rds) --
  # Layout deliberately mirrors the relative paths recorded inside
  # design_frozen.rds$source_manifest (cfb_data_v2/..., cfb_data_v3/...), so
  # those manifest paths are resolved against this directory.   [CFB_FROZEN_DIR]
  frozen         = .cfb_env("CFB_FROZEN_DIR", file.path(PROJECT_ROOT, "data", "frozen")),

  # --- Reference data (small, read-mostly) -------------------------------------
  reference      = file.path(PROJECT_ROOT, "data", "reference"),
  teams_dir      = .cfb_env("CFB_TEAMS_DIR", file.path(PROJECT_ROOT, "data", "reference")),
  team_directory = file.path(PROJECT_ROOT, "data", "reference", "team_directory.rds"),
  market_lines   = file.path(PROJECT_ROOT, "data", "reference", "market", "betting_lines_2023_2025.rds"),
  incumbent_dev  = file.path(PROJECT_ROOT, "data", "reference", "incumbent_predictions",
                             "eb_features_development_predictions.csv"),
  incumbent_cond = file.path(PROJECT_ROOT, "data", "reference", "incumbent_predictions",
                             "eb_features_conditional_predictions.csv"),
  snapshot_seed  = file.path(PROJECT_ROOT, "data", "reference", "production_snapshots_2026"),
  tier_map       = file.path(PROJECT_ROOT, "config", "tier_map.csv"),

  # --- Write-once prospective prediction archives (evidence; never overwrite) --
  prospective    = .cfb_env("CFB_PROSPECTIVE_DIR", file.path(PROJECT_ROOT, "data", "prospective")),

  # --- Generated outputs (safe to delete and regenerate) ----------------------
  output         = file.path(PROJECT_ROOT, "output"),
  # Runtime state: production snapshots, simulation results, live caches.  [CFB_DATA_DIR]
  state          = .cfb_env("CFB_DATA_DIR", file.path(PROJECT_ROOT, "output", "state")),
  rankings       = file.path(PROJECT_ROOT, "output", "rankings"),
  graphics       = file.path(PROJECT_ROOT, "output", "graphics"),
  # Static-site JSON (ratings.json, simulations.json, betting.json). Lives under
  # public/, not output/: Vite serves it directly and copies it into dist/ on
  # build, and it is committed so the site always has real data. [CFB_PUBLIC_DIR]
  public_data    = .cfb_env("CFB_PUBLIC_DIR", file.path(PROJECT_ROOT, "public", "data")),
  dev_runs       = file.path(PROJECT_ROOT, "output", "dev")
)

# Convenience: resolve a path relative to the frozen-input directory.
frozen_path <- function(...) file.path(PATHS$frozen, ...)

# Create generated-output directories on demand (never the frozen/reference ones).
ensure_output_dirs <- function() {
  for (p in PATHS[c("output", "state", "rankings", "graphics", "public_data", "dev_runs")]) {
    dir.create(p, recursive = TRUE, showWarnings = FALSE)
  }
  invisible(TRUE)
}
