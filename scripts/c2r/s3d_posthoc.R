# C2 refinement research, Stage 3, part D (POST HOC, attribution only; not part of the predeclared selection):
# which component of the selected L arm (L_last_n20) produces its gains? P_noDiv = L without division-specific prior pools;
# P_noLow = L without the lower-division level column. Metrics as in s3c (development and 2023-25).
source("config/paths.R"); source("config/production.R")
suppressPackageStartupMessages({ source(PATHS$model_ops); library(data.table); for (f in c("data", "c1", "c2")) source(sprintf("R/round15/candidates/%s.R", f)) })
source("/Users/willcavender/Desktop/Revised CFB Modeling/.claude/worktrees/c2-refinement/scripts/c2r/lib_c2r.R"); source(file.path(C2R, "scripts/c2r/lib_s3.R"))
out <- file.path(C2R, "output/c2r/stage3"); dir.create(file.path(out, "posthoc"), showWarnings = FALSE)
d <- r15_build_data(); dv <- readRDS(file.path(C2R, "output/c2r/stage1/divisions.rds"))
c1 <- readRDS(file.path(R15C$cache, "c1_components.rds")); c2 <- readRDS(file.path(R15C$cache, "c2_components.rds"))
an <- readRDS(file.path(out, "level_history.rds"))$anchors[anchor == "last", .(season, fcs, gap)]
base <- modifyList(s3_opt(), readRDS(file.path(out, "arms", "L_last_n20.rds"))$opt)
for (nm in c("P_noDiv", "P_noLow")) { o <- if (nm == "P_noDiv") modifyList(base, list(divmu = FALSE)) else modifyList(base, list(lowcol = FALSE))
  cap <- s3_capture_all(d, c1, c2, dv, o, an); cap$opt <- o; cap$name <- nm; saveRDS(cap, file.path(out, "posthoc", paste0(nm, ".rds"))) }
