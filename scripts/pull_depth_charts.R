# Pull TWO·DEEP depth charts on their own (normally run inside scripts/03_export_public_data.R). Writes
# output/state/depth_charts_<season>.rds and its committed copy in data/reference/depth_charts/.
#   Rscript scripts/pull_depth_charts.R
source("config/paths.R")
ensure_output_dirs()
source(PATHS$pull_depth, local = new.env(parent = globalenv()))
