# C2 refinement research, Stage 4, POST HOC diagnostic (not part of the predeclared selection): does a larger starting
# preseason scale combined with faster decay beat either change alone? Arms: S120+D3, S120+D5, S110+D5. And a scale applied
# only while a team has played no game (G0_110/120/130), which cannot affect later weeks.
source("config/paths.R"); source("config/production.R")
suppressPackageStartupMessages({ source(PATHS$model_ops); library(data.table); for (f in c("data", "c1", "c2")) source(sprintf("R/round15/candidates/%s.R", f)) })
source("/Users/willcavender/Desktop/Revised CFB Modeling/.claude/worktrees/c2-refinement/scripts/c2r/lib_c2r.R"); source(file.path(C2R, "scripts/c2r/lib_s3.R"))
out <- file.path(C2R, "output/c2r/stage4"); dir.create(file.path(out, "posthoc"), showWarnings = FALSE)
d <- r15_build_data(); dv <- readRDS(file.path(C2R, "output/c2r/stage1/divisions.rds"))
c1 <- readRDS(file.path(R15C$cache, "c1_components.rds")); c2 <- readRDS(file.path(R15C$cache, "c2_components.rds"))
an <- readRDS(file.path(C2R, "output/c2r/stage3/level_history.rds"))$anchors[anchor == "last", .(season, fcs, gap)]
base <- readRDS(file.path(out, "arms", "C2L.rds"))$opt; base$influence <- FALSE
arms <- list(P_S120_D3 = list(1.2, 3), P_S120_D5 = list(1.2, 5), P_S110_D5 = list(1.1, 5))
for (nm in names(arms)) { cap <- s3_capture_all(d, c1, c2, dv, modifyList(base, list(pscale = arms[[nm]][[1]], lam_mult = 0.5^((0:20) / arms[[nm]][[2]]))), an)
  saveRDS(cap, file.path(out, "posthoc", paste0(nm, ".rds"))) }
for (s0 in c(1.1, 1.2, 1.3)) { nm <- sprintf("P_G0_%03d", round(100 * s0)); arms[[nm]] <- list(); saveRDS(s3_capture_all(d, c1, c2, dv, modifyList(base, list(pscale_gp0 = s0)), an), file.path(out, "posthoc", paste0(nm, ".rds"))) }
G <- readRDS(file.path(out, "G_frame.rds")); G[, gpb := fifelse(gpmin >= 7, "7+", fifelse(gpmin >= 4, "4-6", as.character(gpmin)))]
fit_sigma <- function(m, y) { f <- function(s) -sum(y * pnorm(m / s, log.p = TRUE) + (1 - y) * pnorm(-m / s, log.p = TRUE)); optimize(f, c(2, 80), tol = 1e-10)$minimum }
P <- c(list(C2L = readRDS(file.path(out, "arms", "C2L.rds"))$pred, S120 = readRDS(file.path(out, "arms", "S120.rds"))$pred), lapply(setNames(nm = names(arms)), function(a) readRDS(file.path(out, "posthoc", paste0(a, ".rds")))$pred))
res <- rbindlist(lapply(names(P), function(a) { g <- merge(G[, .(game_id, season, split, win, actual, gpb)], P[[a]][, .(game_id, m = pred_margin)], by = "game_id"); s <- numeric(nrow(g))
  for (y in R15C$dev) s[g$season == y] <- fit_sigma(g[split == "dev" & season != y]$m, g[split == "dev" & season != y]$win); s[g$split == "cond"] <- fit_sigma(g[split == "dev"]$m, g[split == "dev"]$win)
  p <- pmin(pmax(pnorm(g$m / s), 1e-6), 1 - 1e-6); g[, ll := -(win * log(p) + (1 - win) * log(1 - p))]
  rbind(g[, .(arm = a, gp = "all", ll = mean(ll), mae = mean(abs(m - actual))), by = split], g[, .(arm = a, ll = mean(ll), mae = mean(abs(m - actual))), by = .(split, gp = gpb)]) }))
print(dcast(res, split + gp ~ arm, value.var = "ll"), digits = 4); fwrite(res, file.path(C2R, "docs/c2r/stage4/s4_posthoc_scale_decay.csv"))
