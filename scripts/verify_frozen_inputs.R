# =============================================================================
# scripts/verify_frozen_inputs.R — check every frozen production input.
#
# Confirms the MD5 of design_frozen.rds, features.rds, the 12 frozen schedules,
# the 4 feature source caches and the model engine. Run after copying/moving
# the project or restoring from backup. Exit status 1 on any mismatch.
# =============================================================================
source("config/paths.R")
source("config/production.R")
suppressPackageStartupMessages(source(PATHS$model_ops))
v <- v5_verify_frozen_inputs()
print(v[, c("path", "ok")], row.names = FALSE)
if (!all(v$ok)) { message("FROZEN INPUT MISMATCH"); quit(status = 1L) }
cat("All", nrow(v), "frozen inputs match their recorded checksums.\n")
