# =============================================================================
# scripts/03_export_public_data.R — write the static-site JSON files.
#
# Reads output/state (production snapshots + simulations) and data/reference
# (team metadata) and writes public/data/{ratings,simulations}.json plus
# per-week archives, and the CFPi+ page datasets in public/data/v2
# (R/publish/export_site_data.R, docs/website/DATA_CONTRACT_V2.md).
# Set CFB_EXPORT_BETTING=true to also build betting.json (calls the CFBD API;
# needs CFBD_API_KEY for market lines).
# Schemas: docs/DATA_CONTRACT.md (v1) and docs/website/DATA_CONTRACT_V2.md.
# The website source is src/ (docs/website/ARCHITECTURE.md).
# =============================================================================
source("config/paths.R")
ensure_output_dirs()
source(PATHS$export_public, local = new.env(parent = globalenv()))
# Season player stats for "Statistical leaders" (one CFBD call; display only, never a model input).
if (!identical(Sys.getenv("CFB_PULL_PLAYERS"), "false")) source(PATHS$pull_players, local = new.env(parent = globalenv()))
# CFPi+ page datasets (public/data/v2); reads the same outputs, never the model.
source(PATHS$export_site, local = new.env(parent = globalenv()))
if (identical(Sys.getenv("CFB_EXPORT_BETTING"), "true")) {
  source(PATHS$export_betting, local = new.env(parent = globalenv()))
}
