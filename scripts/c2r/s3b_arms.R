# C2 refinement research, Stage 3, part B: capture the arms of docs/c2r/STAGE3_PLAN.md.
# Usage (round15-power-rating worktree root): Rscript <c2r>/scripts/c2r/s3b_arms.R first | second
#   first : C0, G(4..14), L(anchor x n0)
#   second: S(k) on the selected L and G, the flat reference, L-sr (reads output/c2r/stage3/selection_first.rds)
stage <- commandArgs(trailingOnly = TRUE)[1]; stopifnot(stage %in% c("first", "second"))
source("config/paths.R"); source("config/production.R")
suppressPackageStartupMessages({ source(PATHS$model_ops); library(data.table); for (f in c("data", "c1", "c2")) source(sprintf("R/round15/candidates/%s.R", f)) })
source("/Users/willcavender/Desktop/Revised CFB Modeling/.claude/worktrees/c2-refinement/scripts/c2r/lib_c2r.R"); source(file.path(C2R, "scripts/c2r/lib_s3.R"))
out <- file.path(C2R, "output/c2r/stage3"); dir.create(file.path(out, "arms"), recursive = TRUE, showWarnings = FALSE)
d <- r15_build_data(); dv <- readRDS(file.path(C2R, "output/c2r/stage1/divisions.rds"))
c1 <- readRDS(file.path(R15C$cache, "c1_components.rds")); c2 <- readRDS(file.path(R15C$cache, "c2_components.rds"))
an <- readRDS(file.path(out, "level_history.rds"))$anchors
anc <- function(type) an[anchor == type, .(season, fcs, gap)]
arms <- list()
if (stage == "first") {
  arms$C0 <- list(opt = s3_opt())
  for (dl in c(4, 6, 8, 10, 12, 14)) arms[[sprintf("G%02d", dl)]] <- list(opt = s3_opt(shift = dl))
  for (a in c("fixed", "expanding", "rolling3", "last")) for (n0 in c(0, 20)) arms[[sprintf("L_%s_n%d", a, n0)]] <- list(opt = s3_opt(divmu = TRUE, level = TRUE, n0 = n0), anchor = a)
} else {
  sel <- readRDS(file.path(out, "selection_first.rds")); bL <- sel$L; bG <- sel$G
  for (k in c(2, 4)) { arms[[sprintf("S%d_on_%s", k, bL$name)]] <- list(opt = modifyList(bL$opt, list(kf = k)), anchor = bL$anchor)
                       arms[[sprintf("S%d_on_%s", k, bG$name)]] <- list(opt = modifyList(bG$opt, list(kf = k))) }
  arms[[sprintf("FLAT_on_%s", bL$name)]] <- list(opt = modifyList(bL$opt, list(flat = TRUE)), anchor = bL$anchor)
  arms[[sprintf("SR_on_%s", bL$name)]] <- list(opt = modifyList(bL$opt, list(srlevel = TRUE)), anchor = bL$anchor)
}
for (nm in names(arms)) { a <- arms[[nm]]; t0 <- Sys.time()
  cap <- s3_capture_all(d, c1, c2, dv, a$opt, if (!is.null(a$anchor)) anc(a$anchor) else NULL)
  cap$opt <- a$opt; cap$anchor <- a$anchor; cap$name <- nm
  if (nm == "C0") {   # fidelity: frozen C2 predictions and the Stage 1 FCS ratings / prior means
    ref <- fread(file.path(R15C$cache, "c2_predictions.csv"), colClasses = list(character = "game_id")); m <- merge(cap$pred, ref[, .(game_id, r = pred_margin)], by = "game_id")
    s1 <- readRDS(file.path(C2R, "output/c2r/stage1/capture.rds"))
    e <- merge(cap$ent[fbs == FALSE], s1$ent[fbs == FALSE, .(season, cutoff, team_id, p1 = power)], by = c("season", "cutoff", "team_id"))
    f <- merge(cap$fcs_prior, s1$fcs_prior[, .(season, cutoff, team_id, q = prior_power_c)], by = c("season", "cutoff", "team_id"))
    ok <- c(nrow(m) == nrow(ref), max(abs(m$pred_margin - m$r)) < 1e-9, nrow(e) == s1$ent[fbs == FALSE, .N], max(abs(e$power - e$p1)) < 1e-9, nrow(f) == nrow(s1$fcs_prior), max(abs(f$first_game_power - f$q)) < 1e-9)
    print(ok); stopifnot(all(ok)) }
  saveRDS(cap, file.path(out, "arms", paste0(nm, ".rds"))); message(nm, " ", format(Sys.time() - t0, digits = 3)) }
