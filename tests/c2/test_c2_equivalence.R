# Implementation equivalence: current C2 (R/c2/c2_current.R) vs the selected research model C2L (Stage 3 arm L_last_n20,
# scripts/c2r/lib_s3.R), both re-run now and as stored in the Stage 3 / Stage 4 artifacts. Run from the c2-refinement
# worktree root. Writes docs/c2/validation/equivalence.csv and stops if any quantity differs by more than 1e-9.
source("config/paths.R"); source("config/production.R")
suppressPackageStartupMessages({ source(PATHS$model_ops); library(data.table); for (f in c("data", "c1", "c2")) source(sprintf("R/round15/candidates/%s.R", f)) })
source("R/c2/c2_current.R"); source("R/c2/c2_diagnostics.R")
source("scripts/c2r/lib_c2r.R"); source("scripts/c2r/lib_s3.R")   # research code (historical reproducibility only)
VAL <- "docs/c2/validation"; dir.create(VAL, recursive = TRUE, showWarnings = FALSE); TOL <- 1e-9
d <- r15_build_data(); c1 <- readRDS(file.path(R15C$cache, "c1_components.rds")); c2 <- readRDS(file.path(R15C$cache, "c2_components.rds"))
dv <- c2_divisions(readRDS("output/dev/round15/prep/fcs_schedules_2013_2025.rds"))
cur <- c2_run(d, c1, c2, dv, keep_system = TRUE)

# research C2L re-run with its own inputs (Stage 1 division map, Stage 3 anchors) and the stored artifacts
dvr <- readRDS("output/c2r/stage1/divisions.rds"); lh <- readRDS("output/c2r/stage3/level_history.rds")
L3 <- readRDS("output/c2r/stage3/arms/L_last_n20.rds"); opt <- modifyList(s3_opt(), L3$opt)
res <- s3_capture_all(d, c1, c2, dvr, opt, lh$anchors[anchor == "last", .(season, fcs, gap)])
S4 <- readRDS("output/c2r/stage4/arms/C2L.rds")

cmp <- function(item, ref, a, b, key) { m <- merge(a, b, by = key, suffixes = c(".cur", ".ref"))
  x <- m[[paste0(item, ".cur")]]; y <- m[[paste0(item, ".ref")]]; dd <- abs(x - y)
  data.table(reference = ref, quantity = item, rows_current = nrow(a), rows_reference = nrow(b), rows_matched = nrow(m),
             max_abs_diff = max(dd), mean_abs_diff = mean(dd), n_nonidentical = sum(dd > 0), n_above_tol = sum(dd > TOL)) }
out <- list()
# inputs
out$div <- data.table(reference = "research", quantity = "division map (season, team, division)", rows_current = nrow(dv), rows_reference = nrow(dvr),
                      rows_matched = nrow(merge(dv, dvr, by = c("season", "team_id", "div"))), max_abs_diff = 0, mean_abs_diff = 0, n_nonidentical = nrow(dvr) - nrow(merge(dv, dvr, by = c("season", "team_id", "div"))), n_above_tol = 0)
out$eos <- cmp("fcs", "research", cur$eos_levels, lh$levels[, .(season, fcs, gap)], "season"); out$gap <- cmp("gap", "research", cur$eos_levels, lh$levels[, .(season, fcs, gap)], "season")
ar <- lh$anchors[anchor == "last", .(season, fcs, gap)]; out$anc <- cmp("fcs", "research", cur$anchors[, .(season, fcs, gap)], ar, "season"); out$ancg <- cmp("gap", "research", cur$anchors[, .(season, fcs, gap)], ar, "season")
out$anc[, quantity := "anchor: FCS level"]; out$ancg[, quantity := "anchor: lower gap"]; out$eos[, quantity := "end-of-season FCS level (anchor history)"]; out$gap[, quantity := "end-of-season lower gap"]
# ratings, levels, predictions
K <- c("season", "cutoff", "team_id")
rc <- cur$ratings[, .(season, cutoff, team_id, fbs, eff_off, eff_def, power)]; rr <- res$ent[, .(season, cutoff, team_id, fbs, eff_off, eff_def, power)]
for (fb in c(TRUE, FALSE)) for (q in c("eff_off", "eff_def", "power")) out[[paste(fb, q)]] <- cmp(q, "research", rc[fbs == fb], rr[fbs == fb], K)[, quantity := paste(if (fb) "FBS" else "non-FBS", q)]
out$pw3 <- cmp("power", "stored Stage 3 artifact", rc, L3$ent[, .(season, cutoff, team_id, power)], K)[, quantity := "all team power"]
lv <- cur$levels[, .(season, cutoff, dL = delta_fcs, dLow = delta_low, fcs_level)]
out$dL <- cmp("dL", "research", lv, res$cuts[, .(season, cutoff, dL, dLow, fcs_level)], c("season", "cutoff"))[, quantity := "group level Delta_FCS"]
out$dLow <- cmp("dLow", "research", lv, res$cuts[, .(season, cutoff, dL, dLow, fcs_level)], c("season", "cutoff"))[, quantity := "group level Delta_low"]
out$fl <- cmp("fcs_level", "stored Stage 3 artifact", lv[is.finite(fcs_level)], L3$cuts[is.finite(fcs_level), .(season, cutoff, fcs_level)], c("season", "cutoff"))[, quantity := "FCS-division mean rating"]
out$fg <- cmp("power", "stored Stage 3 artifact", cur$first_game[, .(season, cutoff, team_id, power)], L3$fcs_prior[, .(season, cutoff, team_id, power = first_game_power)], K)[, quantity := "first-game non-FBS rating"]
out$pr3 <- cmp("pred_margin", "stored Stage 3 artifact", cur$pred, L3$pred, "game_id")[, quantity := "FBS-vs-FBS predicted margin"]
out$pr4 <- cmp("pred_margin", "stored Stage 4 artifact (C2L)", cur$pred, S4$pred, "game_id")[, quantity := "FBS-vs-FBS predicted margin"]
# FBS-vs-FCS predicted margins: the research evaluation formula (s3c/s4c) on the stored artifact vs c2_fbs_vs_nonfbs
fc <- c2_fbs_vs_nonfbs(d, cur)[final == TRUE]
rfc <- merge(fc[, .(game_id, season, cutoff, fbs_id, nonfbs_id, H, neutral, fbs_home)], L3$ent[fbs == TRUE, .(season, cutoff, fbs_id = team_id, fr = power)], by = c("season", "cutoff", "fbs_id"))
rfc <- merge(rfc, L3$ent[fbs == FALSE, .(season, cutoff, nonfbs_id = team_id, fi = power)], by = c("season", "cutoff", "nonfbs_id"), all.x = TRUE)
rfc <- merge(rfc, L3$fcs_prior[, .(season, cutoff, nonfbs_id = team_id, fg = first_game_power)], by = c("season", "cutoff", "nonfbs_id"))
rfc[, pred_fbs_margin := fr - fifelse(is.finite(fi), fi, fg) + H * (!neutral) * fifelse(fbs_home, 1, -1)]
out$fc <- cmp("pred_fbs_margin", "stored Stage 3 artifact", fc[, .(game_id, pred_fbs_margin)], rfc[, .(game_id, pred_fbs_margin)], "game_id")[, quantity := "FBS-vs-FCS predicted margin (all 926 games)"]
# win probabilities: sigma fitted leave-one-season-out on development FBS-vs-FBS games (the R15 scorer rule), per model
act <- as.data.table(d$base$frame)[, .(game_id, season, win = as.numeric(actual_margin > 0))]
fit_sigma <- function(m, y) { f <- function(s) -sum(y * pnorm(m / s, log.p = TRUE) + (1 - y) * pnorm(-m / s, log.p = TRUE)); optimize(f, c(2, 80), tol = 1e-10)$minimum }
wp <- function(p) { g <- merge(p[, .(game_id, m = pred_margin)], act, by = "game_id"); s <- numeric(nrow(g))
  for (y in R15C$dev) s[g$season == y] <- fit_sigma(g[season %in% R15C$dev & season != y]$m, g[season %in% R15C$dev & season != y]$win)
  s[g$season >= 2023] <- fit_sigma(g[season %in% R15C$dev]$m, g[season %in% R15C$dev]$win); g[, .(game_id, win_prob = pnorm(m / s))] }
out$wp <- cmp("win_prob", "stored Stage 3 artifact", wp(cur$pred), wp(L3$pred), "game_id")[, quantity := "FBS-vs-FBS win probability"]
# Stage 4 diagnostic: preseason influence from the solved system
inf <- c2_influence_all(cur)
for (q in c("w_power", "w_off", "w_def", "prior_block")) out[[q]] <- cmp(q, "stored Stage 4 artifact (C2L influence)", inf[, c(K, q), with = FALSE], S4$inf[, c(K, q), with = FALSE], K)[, quantity := paste("preseason influence:", q)]
eq <- rbindlist(out, fill = TRUE); print(eq, digits = 3); fwrite(eq, file.path(VAL, "equivalence.csv"))
stopifnot(all(eq$n_above_tol == 0), all(eq$rows_matched == eq$rows_reference), all(eq$rows_current == eq$rows_reference))
cat("EQUIVALENCE PASSED: current C2 reproduces C2L within", TOL, "\n")
