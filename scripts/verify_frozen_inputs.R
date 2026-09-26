# =============================================================================
# scripts/verify_frozen_inputs.R — check every frozen production input.
#
# Former incumbent (EB_features, benchmark/rollback): MD5 of design_frozen.rds,
# features.rds, the 12 frozen schedules, the 4 feature source caches and the
# model engine. Production model (Current C2): MD5 of its frozen 2026 season
# inputs and of every model code file (config/production_model.R). Run after
# copying/moving the project or restoring from backup. Exit status 1 on any
# mismatch.
# =============================================================================
source("config/paths.R")
source("config/production.R")
source("config/production_model.R")
suppressPackageStartupMessages({ source(PATHS$model_ops); source(PATHS$c2_production) })
v <- rbind(cbind(model = "EB_features (incumbent benchmark)", v5_verify_frozen_inputs()),
           cbind(model = "C2_current (production)", c2p_verify_frozen()))
print(v[, c("model", "path", "ok")], row.names = FALSE)
if (!all(v$ok)) { message("FROZEN INPUT MISMATCH"); quit(status = 1L) }
cat("All", nrow(v), "frozen inputs match their recorded checksums.\n")
