# C2 refinement research, Stage 4: capture the arms of docs/c2r/STAGE4_PLAN.md (baseline C2L = Stage 3 L_last_n20).
# Usage (round15-power-rating worktree root): Rscript <c2r>/scripts/c2r/s4b_arms.R scale | decay
#   scale: NP, S(0.90..1.30), O(s_off 1.10..1.40)       decay: D(h) and F diagnostics at the selected scale (selection_scale.rds)
phase <- commandArgs(trailingOnly = TRUE)[1]; stopifnot(phase %in% c("scale", "decay"))
source("config/paths.R"); source("config/production.R")
suppressPackageStartupMessages({ source(PATHS$model_ops); library(data.table); for (f in c("data", "c1", "c2")) source(sprintf("R/round15/candidates/%s.R", f)) })
source("/Users/willcavender/Desktop/Revised CFB Modeling/.claude/worktrees/c2-refinement/scripts/c2r/lib_c2r.R"); source(file.path(C2R, "scripts/c2r/lib_s3.R"))
out <- file.path(C2R, "output/c2r/stage4")
d <- r15_build_data(); dv <- readRDS(file.path(C2R, "output/c2r/stage1/divisions.rds"))
c1 <- readRDS(file.path(R15C$cache, "c1_components.rds")); c2 <- readRDS(file.path(R15C$cache, "c2_components.rds"))
an <- readRDS(file.path(C2R, "output/c2r/stage3/level_history.rds"))$anchors[anchor == "last", .(season, fcs, gap)]
base <- readRDS(file.path(out, "arms", "C2L.rds"))$opt; base$influence <- FALSE
arms <- list()
if (phase == "scale") {
  arms$NP <- modifyList(base, list(fbs_zero = TRUE))
  for (s in c(0.90, 1.10, 1.20, 1.30)) arms[[sprintf("S%03d", round(100 * s))]] <- modifyList(base, list(pscale = s))
  for (s in c(1.10, 1.20, 1.30, 1.40)) arms[[sprintf("O%03d", round(100 * s))]] <- modifyList(base, list(pscale_off = s))
} else {
  sb <- readRDS(file.path(out, "selection_scale.rds"))$opt
  for (h in 1:5) arms[[sprintf("D%d_%s", h, readRDS(file.path(out, "selection_scale.rds"))$name)]] <- modifyList(sb, list(lam_mult = 0.5^((0:20) / h), influence = TRUE))
  for (b in 1:5) for (mu in c(0.25, 0.5, 2, 4)) { v <- rep(1, 6); if (b == 5) v[6] <- mu else v[b + 1] <- mu
    arms[[sprintf("F_gp%s_x%s", if (b == 5) "5p" else b, mu)]] <- modifyList(sb, list(lam_mult = v)) }
}
for (nm in names(arms)) { t0 <- Sys.time(); cap <- s3_capture_all(d, c1, c2, dv, arms[[nm]], an); cap$opt <- arms[[nm]]; cap$name <- nm
  saveRDS(cap, file.path(out, "arms", paste0(nm, ".rds"))); message(nm, " ", format(Sys.time() - t0, digits = 3)) }
