# Build the current (integrated post-Stage-4) C2 for 2017-2025 and write its outputs to output/c2/current/.
# Run from the c2-refinement worktree root (output/dev/round15 -> the frozen Round 15 caches, read-only).
# Inputs: the frozen data cache and the frozen construction components (unchanged); nothing is fitted or tuned here
# beyond C2's own weekly solves and the end-of-season anchor fits defined in docs/c2/C2_CURRENT_SPEC.md.
source("config/paths.R"); source("config/production.R")
suppressPackageStartupMessages({ source(PATHS$model_ops); library(data.table); for (f in c("data", "c1", "c2")) source(sprintf("R/round15/candidates/%s.R", f)) })
source("R/c2/c2_current.R")
out <- "output/c2/current"; dir.create(out, recursive = TRUE, showWarnings = FALSE)
d <- r15_build_data(); c1 <- readRDS(file.path(R15C$cache, "c1_components.rds")); c2 <- readRDS(file.path(R15C$cache, "c2_components.rds"))
dv <- c2_divisions(readRDS("output/dev/round15/prep/fcs_schedules_2013_2025.rds"))
run <- c2_run(d, c1, c2, dv)
fwrite(run$pred[, model := "C2"], file.path(out, "c2_predictions.csv"))           # same schema as the frozen c2_predictions.csv (+ model)
fwrite(run$ratings, file.path(out, "c2_ratings.csv")); fwrite(run$levels, file.path(out, "c2_group_levels.csv"))
fwrite(run$first_game, file.path(out, "c2_first_game_ratings.csv")); fwrite(run$anchors, file.path(out, "c2_anchors.csv"))
fwrite(run$eos_levels, file.path(out, "c2_anchor_history.csv")); fwrite(dv, file.path(out, "c2_divisions.csv"))
fwrite(c2_fbs_vs_nonfbs(d, run), file.path(out, "c2_fbs_vs_nonfbs_predictions.csv"))
fs <- list.files(out, pattern = "\\.csv$", full.names = TRUE)
fwrite(data.table(file = fs, sha256 = vapply(fs, function(f) digest::digest(file = f, algo = "sha256"), ""), rows = vapply(fs, function(f) nrow(fread(f)), 0L)), file.path(out, "manifest.csv"))
cat("current C2 built:", nrow(run$pred), "FBS-vs-FBS predictions,", nrow(run$ratings), "rating rows\n")
