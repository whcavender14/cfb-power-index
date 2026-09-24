# =============================================================================
# scripts/03_export_public_data.R — write the static-site JSON files.
#
# Reads output/state (production snapshots + simulations) and data/reference
# (team metadata) and writes public/data/{ratings,simulations}.json plus
# per-week archives. Set CFB_EXPORT_BETTING=true to also build betting.json
# (calls the CFBD API; needs CFBD_API_KEY for market lines).
# Schema: docs/DATA_CONTRACT.md. The live dashboard itself is NOT part of this
# folder; see docs/legacy_file_manifest.md (web dashboard entries).
# =============================================================================
source("config/paths.R")
ensure_output_dirs()
source(PATHS$export_public, local = new.env(parent = globalenv()))
if (identical(Sys.getenv("CFB_EXPORT_BETTING"), "true")) {
  source(PATHS$export_betting, local = new.env(parent = globalenv()))
}
