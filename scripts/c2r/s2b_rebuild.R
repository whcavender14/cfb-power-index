# C2 refinement research, Stage 2 (garbage time), part B: rebuild C1 and C2 end-to-end under one SR treatment.
# Usage (from the round15-power-rating worktree root): Rscript <c2r>/scripts/c2r/s2b_rebuild.R A|A0|B
# The frozen construction procedure is re-run on the treatment's SR inputs: C1 priors (last_sr), variance models, scale,
# lambda0 selection; C2 beta, omega selection; predictions; and the full rating capture. Nothing else changes (FCS
# treatment, fumble luck, HFA and the end-of-season points fits are SR-free and identical). Arm A must reproduce the frozen
# C1 and C2 components and predictions. For A0 and B an attribution arm "rows" is also captured: the treatment's in-season
# SR rows and beta with every other frozen C2 component unchanged (no prior, lambda0, scale or omega change).
arg <- commandArgs(trailingOnly = TRUE)[1]; stopifnot(arg %in% c("A", "A0", "B"))
source("config/paths.R"); source("config/production.R")
suppressPackageStartupMessages({ source(PATHS$model_ops); library(data.table)
  for (f in c("data", "c1", "c2", "tune")) source(sprintf("R/round15/candidates/%s.R", f)) })
source("/Users/willcavender/Desktop/Revised CFB Modeling/.claude/worktrees/c2-refinement/scripts/c2r/lib_c2r.R")
out <- file.path(C2R, "output/c2r/stage2"); t0 <- Sys.time()
d <- r15_build_data(); sr <- readRDS(file.path(out, "sr_treatments.rds")); dv <- readRDS(file.path(C2R, "output/c2r/stage1/divisions.rds"))
c1f <- readRDS(file.path(R15C$cache, "c1_components.rds")); c2f <- readRDS(file.path(R15C$cache, "c2_components.rds"))
dT <- c2r_substitute_sr(d, sr$sr[[arg]])
if (arg == "A") { k <- c("season", "game_id", "offense", "defense")
  stopifnot(identical(dT$pbp[!is.na(sr), c(k, "sr", "sr_plays"), with = FALSE], d$pbp[!is.na(sr), c(k, "sr", "sr_plays"), with = FALSE]),
            max(abs(dT$sr_eos$sr_off - d$sr_eos$sr_off), abs(dT$sr_eos$sr_def - d$sr_eos$sr_def)) < 1e-12, identical(dT$sr_eos$team, d$sr_eos$team)) }
c1 <- c2r_build_c1(dT); message("C1 built ", format(Sys.time() - t0))
c2 <- c2r_build_c2(dT, c1, c2f$eos_full); message("C2 built ", format(Sys.time() - t0))
pc1 <- c2r_predict_c1(dT, c1)
cap <- c2r_capture_all(dT, c1, c2, dv)
# capture fidelity: the captured predictions equal r15_predict_season_c2 on the same inputs
ref <- rbindlist(lapply(c2r_S, function(y) do.call(r15_predict_season_c2, c(list(d = dT, z = y), c2r_args(dT, c1, c2, y)))))
fid <- merge(cap$pred, ref[, .(game_id, r = pred_margin)], by = "game_id"); stopifnot(nrow(fid) == nrow(ref), max(abs(fid$pred_margin - fid$r)) < 1e-9)
chk <- NULL
if (arg == "A") {
  p1 <- fread(file.path(R15C$cache, "c1_predictions.csv"), colClasses = list(character = "game_id")); p2f <- fread(file.path(R15C$cache, "c2_predictions.csv"), colClasses = list(character = "game_id"))
  m1 <- merge(pc1, p1[, .(game_id, r = pred_margin)], by = "game_id"); m2 <- merge(cap$pred, p2f[, .(game_id, r = pred_margin)], by = "game_id")
  pr <- max(unlist(lapply(names(c1f$priors), function(z) max(abs(c1$priors[[z]]$pre_off - c1f$priors[[z]]$pre_off), abs(c1$priors[[z]]$pre_def - c1f$priors[[z]]$pre_def)))))
  chk <- data.table(item = c("C1 priors (max |diff|)", "C1 scale", "C1 lambda0", "C1 variance b", "C2 beta", "C2 omega", "C1 predictions", "C2 predictions"),
    value = c(pr, max(abs(c1$scl - c1f$scl)), max(abs(c1$lam0 - c1f$lam0)),
              max(unlist(lapply(names(c1f$varm), function(z) abs(c(c1$varm[[z]]$off$b - c1f$varm[[z]]$off$b, c1$varm[[z]]$def$b - c1f$varm[[z]]$def$b))))),
              max(abs(sapply(names(c2f$p2), function(z) c2$p2[[z]]$beta - c2f$p2[[z]]$beta))), max(abs(c2$om - c2f$om)),
              if (nrow(m1) == nrow(p1)) max(abs(m1$pred_margin - m1$r)) else Inf, if (nrow(m2) == nrow(p2f)) max(abs(m2$pred_margin - m2$r)) else Inf))
  print(chk); stopifnot(all(chk$value <= 1e-9))
}
rows <- NULL
if (arg != "A") {   # attribution arm: treatment SR rows + treatment beta, everything else frozen
  c2r_ <- c2f; for (z in names(c2r_$p2)) { c2r_$p2[[z]]$beta <- c2$p2[[z]]$beta; c2r_$p2[[z]]$beta_ok <- c2$p2[[z]]$beta_ok; c2r_$p2[[z]]$beta_rows <- c2$p2[[z]]$beta_rows }
  rows <- c2r_capture_all(dT, c1f, c2r_, dv)
}
c2$eos_full <- NULL
saveRDS(list(arm = arg, c1 = c1, c2 = c2, pred_c1 = pc1, cap = cap, rows = rows, check = chk), file.path(out, sprintf("build_%s.rds", arg)))
message("done ", arg, " ", format(Sys.time() - t0))
