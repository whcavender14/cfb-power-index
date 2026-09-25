# Reproduce the established Stage 3/4 C2L results from the integrated C2 (not a selection exercise; nothing is tuned).
# Run from the c2-refinement worktree root after scripts/c2/c2_build_current.R. Every recomputed number is compared with
# the stored research table it came from; writes docs/c2/validation/performance_*.csv and stops on any mismatch > 1e-9.
source("config/paths.R"); source("config/production.R")
suppressPackageStartupMessages({ source(PATHS$model_ops); library(data.table); source("R/evaluation/evaluation_helpers.R"); for (f in c("data", "c1", "c2")) source(sprintf("R/round15/candidates/%s.R", f)) })
source("R/c2/c2_current.R"); source("R/c2/c2_diagnostics.R")
VAL <- "docs/c2/validation"; dir.create(VAL, recursive = TRUE, showWarnings = FALSE); ST <- "docs/c2r"; TOL <- 1e-9; NREP <- 4000L; SEED <- 15015L; DEV <- R15C$dev
d <- r15_build_data(); c1 <- readRDS(file.path(R15C$cache, "c1_components.rds")); c2 <- readRDS(file.path(R15C$cache, "c2_components.rds"))
dv <- c2_divisions(readRDS("output/dev/round15/prep/fcs_schedules_2013_2025.rds"))
run <- c2_run(d, c1, c2, dv, keep_system = TRUE)

# ---- FBS-vs-FBS universe with all-games games played (Stage 4 convention) --------------------------------------------
G <- as.data.table(d$base$frame)[season %in% C2_SPEC$seasons, .(season, game_id, cutoff = format(cutoff, "%Y-%m-%d"), neutral, home_id, away_id, home_conference, away_conference, actual = actual_margin)]
gp <- c2_games_played(d); G <- merge(G, gp[, .(season, cutoff, home_id = team_id, gp_h = gp)], by = c("season", "cutoff", "home_id"), all.x = TRUE)
G <- merge(G, gp[, .(season, cutoff, away_id = team_id, gp_a = gp)], by = c("season", "cutoff", "away_id"), all.x = TRUE); G[is.na(gp_h), gp_h := 0L][is.na(gp_a), gp_a := 0L]
G[, `:=`(gpmin = pmin(gp_h, gp_a), both0 = gp_h == 0 & gp_a == 0, split = fifelse(season >= 2023, "cond", "dev"))][, site := vapply(season, function(y) c2_H(d, y), 0) * (!as.logical(neutral))][, win := as.numeric(actual > 0)]
G[, gpb := fifelse(gpmin >= 7, "7+", fifelse(gpmin >= 4, "4-6", as.character(gpmin)))][, s_p4 := p4_orientation(home_conference, away_conference, season)]
G <- merge(G, run$pred[, .(game_id, C2 = pred_margin)], by = "game_id")
G <- merge(G, fread(file.path(R15C$cache, "c2_predictions.csv"), colClasses = list(character = "game_id"))[, .(game_id, C2_frozen = pred_margin)], by = "game_id")
G <- merge(G, rbind(fread("output/dev/round15/incumbent_replay_2017_2022.csv", colClasses = list(character = "game_id"))[, .(game_id, I = pred_margin)],
                    fread(PATHS$incumbent_cond, colClasses = list(character = "game_id"))[, .(game_id, I = pred_margin)]), by = "game_id")
G <- merge(G, readRDS("output/c2r/stage4/arms/NP.rds")$pred[, .(game_id, NP = pred_margin)], by = "game_id")   # Stage 4 no-prior reference (research artifact)
setorder(G, split, season, cutoff, game_id)
fit_sigma <- function(m, y) { f <- function(s) -sum(y * pnorm(m / s, log.p = TRUE) + (1 - y) * pnorm(-m / s, log.p = TRUE)); optimize(f, c(2, 80), tol = 1e-10)$minimum }
for (x in c("C2", "C2_frozen", "I", "NP")) { s <- numeric(nrow(G)); for (y in DEV) { g <- G[split == "dev" & season != y]; s[G$season == y] <- fit_sigma(g[[x]], g$win) }
  s[G$split == "cond"] <- fit_sigma(G[split == "dev"][[x]], G[split == "dev"]$win); set(G, j = paste0("s_", x), value = s)
  p <- pmin(pmax(pnorm(G[[x]] / s), 1e-6), 1 - 1e-6); set(G, j = paste0("ll_", x), value = -(G$win * log(p) + (1 - G$win) * log(1 - p))); set(G, j = paste0("br_", x), value = (p - G$win)^2) }
bmet <- function(h, x) { m <- h[[x]]; list(logloss = mean(h[[paste0("ll_", x)]]), brier = mean(h[[paste0("br_", x)]]), mae = mean(abs(m - h$actual)), rmse = sqrt(mean((m - h$actual)^2)),
  bias = mean(m - h$actual), calib_slope = unname(coef(lm(I(h$actual - h$site) ~ I(m - h$site)))[2]), pred_sd = sd(m), winners = mean(sign(m) == sign(h$actual))) }

# ---- whole-system J: FBS-vs-FBS plus every FBS-vs-FCS game (first games under the first-game rule) ----------------------
fc <- c2_fbs_vs_nonfbs(d, run)[final == TRUE]; fc[, split := fifelse(season >= 2023, "cond", "dev")]
fc <- merge(fc, unique(G[, .(season, s = s_C2)]), by = "season"); fc[, ll := { p <- pmin(pmax(pnorm(pred_fbs_margin / s), 1e-6), 1 - 1e-6); yy <- as.numeric(actual_fbs_margin > 0); -(yy * log(p) + (1 - yy) * log(1 - p)) }]
J <- rbind(G[, .(split, ll = ll_C2)], fc[, .(split, ll)])[, .(J = mean(ll)), by = split]

rows <- list(); put <- function(src, split, what, slice, value, stored) rows[[length(rows) + 1L]] <<- data.table(source = src, split = split, metric = what, slice = slice, current = value, stored = stored)
# (a) overall FBS-vs-FBS metrics vs Stage 4 s4_overall.csv (C2L, frozen C2 = C0, incumbent = I)
so <- fread(file.path(ST, "stage4/s4_overall.csv"))
for (sp in c("dev", "cond")) for (x in c("C2", "C2_frozen", "I")) { v <- bmet(G[split == sp], x); ref <- so[split == sp & model == c(C2 = "C2L", C2_frozen = "C0", I = "I")[[x]]]
  for (k in names(v)) put("stage4/s4_overall.csv", sp, paste(x, k), "all", v[[k]], ref[[k]])
  put("stage4/s4_overall.csv", sp, paste(x, "p4g5"), "all", G[split == sp & s_p4 != 0, mean((actual - get(x)) * s_p4)], ref$p4g5) }
for (sp in c("dev", "cond")) put("stage4/s4_overall.csv", sp, "C2 whole-system J", "all", J[split == sp, J], so[split == sp & model == "C2L", J])
# (b) paired deltas with the R15 block bootstrap vs s4_deltas.csv
mkboot <- function(k) { lev <- sort(unique(k)); B <- length(lev); set.seed(SEED); idx <- matrix(sample.int(B, NREP * B, replace = TRUE), nrow = NREP); list(b = match(k, lev), B = B, C = t(apply(idx, 1, tabulate, nbins = B))) }
bs <- function(bo, v) { s <- numeric(bo$B); t <- tapply(v, bo$b, sum); s[as.integer(names(t))] <- t; s }
bm <- function(bo, v) { dr <- as.numeric(bo$C %*% bs(bo, v)) / as.numeric(bo$C %*% bs(bo, rep(1, length(v)))); c(mean(v), unname(quantile(dr, .025)), unname(quantile(dr, .975))) }
sd4 <- fread(file.path(ST, "stage4/s4_deltas.csv"))
for (sp in c("dev", "cond")) { g <- G[split == sp]; bo <- mkboot(paste(g$season, g$cutoff))
  for (b in c("C2_frozen", "I")) { vv <- c(C2_frozen = "C0", I = "I")[[b]]
    for (mt in c("logloss", "brier", "mae")) { v <- switch(mt, logloss = g$ll_C2 - g[[paste0("ll_", b)]], brier = g$br_C2 - g[[paste0("br_", b)]], mae = abs(g$C2 - g$actual) - abs(g[[b]] - g$actual))
      r <- bm(bo, v); ref <- sd4[split == sp & arm == "C2L" & vs == vv & metric == mt]
      put("stage4/s4_deltas.csv", sp, sprintf("C2 - %s %s", b, mt), "delta", r[1], ref$delta); put("stage4/s4_deltas.csv", sp, sprintf("C2 - %s %s", b, mt), "lo95", r[2], ref$lo95); put("stage4/s4_deltas.csv", sp, sprintf("C2 - %s %s", b, mt), "hi95", r[3], ref$hi95) } } }
# (c) by games played and the value of preseason information vs s4_by_gp_all.csv / s4_incremental_value_vs_noprior.csv
BK <- list("0" = "0", "1" = "1", "2" = "2", "3" = "3", "0-3" = c("0", "1", "2", "3"), "4-6" = "4-6", "7+" = "7+")
bg <- fread(file.path(ST, "stage4/s4_by_gp_all.csv")); iv <- fread(file.path(ST, "stage4/s4_incremental_value_vs_noprior.csv"))
for (sp in c("dev", "cond")) for (b in names(BK)) { h <- G[split == sp & gpb %in% BK[[b]]]; v <- bmet(h, "C2"); ref <- bg[split == sp & model == "C2L" & gp == b]
  for (k in c("logloss", "brier", "mae", "rmse", "bias", "calib_slope", "pred_sd")) put("stage4/s4_by_gp_all.csv", sp, k, paste("gp", b), v[[k]], ref[[k]])
  put("stage4/s4_incremental_value_vs_noprior.csv", sp, "log-loss gain vs no prior", paste("gp", b), mean(h$ll_NP) - mean(h$ll_C2), iv[split == sp & model == "C2L" & gp == b, ll_gain_vs_noprior]) }
# (d) gp = 0 calibration vs s4b_gp0_calibration.csv
g0 <- fread(file.path(ST, "stage4/s4b_gp0_calibration.csv"))
for (sp in c("dev", "cond")) for (st in c("min gp = 0", "both gp = 0 (pure prior)")) { h <- if (st == "min gp = 0") G[split == sp & gpmin == 0] else G[split == sp & both0 == TRUE]; v <- bmet(h, "C2"); ref <- g0[split == sp & model == "C2L" & set == st]
  for (k in c("logloss", "brier", "mae", "rmse", "winners", "bias", "calib_slope", "pred_sd")) put("stage4/s4b_gp0_calibration.csv", sp, k, st, v[[k]], ref[[k]]) }
# (e) FBS-vs-FCS first vs later games, and the Stage 3 summary (FBS-vs-FCS and FCS-vs-FCS)
fl <- fread(file.path(ST, "stage4/s4_fbsfcs_first_later.csv"))
for (sp in c("dev", "cond")) for (gm in c("first game", "later")) { h <- fc[split == sp & first_game == (gm == "first game")]; ref <- fl[split == sp & arm == "C2L" & game == gm]
  put("stage4/s4_fbsfcs_first_later.csv", sp, "FBS-vs-FCS bias", gm, h[, mean(pred_fbs_margin - actual_fbs_margin)], ref$bias); put("stage4/s4_fbsfcs_first_later.csv", sp, "FBS-vs-FCS MAE", gm, h[, mean(abs(pred_fbs_margin - actual_fbs_margin))], ref$mae) }
s3 <- fread(file.path(ST, "stage3/s3_summary_all_arms.csv"))[arm == "L_last_n20"]
ff <- d$games; ffg <- rbindlist(lapply(C2_SPEC$seasons, function(y) { cs <- unique(run$ratings[season == y, cutoff]); ct <- sort(as.POSIXct(cs, tz = "UTC"))
  g <- d$games[[as.character(y)]][final == TRUE & !(home_fbs %in% TRUE) & !(away_fbs %in% TRUE)]; sn <- Filter(function(z) z$season == y, d$base$snap); cts <- sort(unique(do.call(c, lapply(sn, `[[`, "cutoff"))))
  g[, ci := findInterval(as.numeric(kickoff), as.numeric(cts))]; g <- g[ci >= 1]; g[, .(season, neutral = as.logical(neutral), home_id, away_id, actual = home_points - away_points, cutoff = format(cts[ci], "%Y-%m-%d"))] }))
fr <- run$ratings[fbs == FALSE & group == "fcs", .(season, cutoff, team_id, power)]
ffg <- merge(merge(ffg, fr[, .(season, cutoff, home_id = team_id, rh = power)], by = c("season", "cutoff", "home_id")), fr[, .(season, cutoff, away_id = team_id, ra = power)], by = c("season", "cutoff", "away_id"))
ffg[, pred := rh - ra + vapply(season, function(y) c2_H(d, y), 0) * (!neutral)][, split := fifelse(season >= 2023, "cond", "dev")]
for (sp in c("dev", "cond")) { h <- fc[split == sp]; ref <- s3[split == sp]; q <- ffg[split == sp]
  put("stage3/s3_summary_all_arms.csv", sp, "FBS-vs-FCS bias", "all", h[, mean(pred_fbs_margin - actual_fbs_margin)], ref$fbsfcs_bias)
  put("stage3/s3_summary_all_arms.csv", sp, "FBS-vs-FCS MAE", "all", h[, mean(abs(pred_fbs_margin - actual_fbs_margin))], ref$fbsfcs_mae)
  put("stage3/s3_summary_all_arms.csv", sp, "FBS-vs-FCS log-loss", "all", mean(h$ll), ref$fbsfcs_logloss)
  put("stage3/s3_summary_all_arms.csv", sp, "FCS-vs-FCS MAE", "all", q[, mean(abs(pred - actual))], ref$fcsfcs_mae)
  put("stage3/s3_summary_all_arms.csv", sp, "FCS-vs-FCS calibration slope", "all", unname(coef(lm(actual ~ pred, q))[2]), ref$fcsfcs_calib_slope) }
# (f) FCS level in early weeks, FBS credit, preseason influence by games played
le <- fread(file.path(ST, "stage4/s4_fcs_level_early.csv"))[arm == "C2L"]; wk <- unique(run$ratings[, .(season, cutoff)])[order(season, cutoff)][, wk := seq_len(.N), by = season]
lv <- merge(run$levels, wk, by = c("season", "cutoff"))[season %in% DEV & wk <= 5 & n_games > 0, .(v = mean(fcs_level, na.rm = TRUE)), by = wk]
for (k in lv$wk) put("stage4/s4_fcs_level_early.csv", "dev", "FCS-division mean rating", paste("cutoff", k), lv[wk == k, v], le[wk == k, fcs_level])
inf <- c2_influence_all(run)[, split := fifelse(season >= 2023, "cond", "dev")][, gpb := fifelse(gp >= 6, "6+", as.character(gp))]
ib <- fread(file.path(ST, "stage4/s4a_influence_by_gp.csv")); ib[, gpb := as.character(gpb)]
for (sp in c("dev", "cond")) for (b in c("0", "1", "2", "3", "4", "5", "6+")) put("stage4/s4a_influence_by_gp.csv", sp, "own-prior share of rating", paste("gp", b), inf[split == sp & gpb == b, mean(w_power)], ib[split == sp & gpb == b, own_prior_weight_power])

# Probability metrics pass through sigma, found by optimize(tol = 1e-10) over a sum whose order depends on the row order
# of the game table (the research scripts ordered games differently). Show the size of that effect directly, then allow it.
gd <- G[split == "dev"]; s_a <- fit_sigma(gd$C2, gd$win); s_b <- fit_sigma(rev(gd$C2), rev(gd$win))
ll_at <- function(s) { p <- pmin(pmax(pnorm(gd$C2 / s), 1e-6), 1 - 1e-6); mean(-(gd$win * log(p) + (1 - gd$win) * log(1 - p))) }
sig_note <- data.table(check = "sigma refit on reversed row order (dev, all seasons)", sigma_diff = abs(s_a - s_b), logloss_diff = abs(ll_at(s_a) - ll_at(s_b)))
print(sig_note); fwrite(sig_note, file.path(VAL, "performance_sigma_order_sensitivity.csv"))
res <- rbindlist(rows)[, diff := current - stored]
res[, tolerance := fifelse(grepl("logloss|brier|log-loss|J$", metric) | metric %in% c("logloss", "brier") | slice %in% c("lo95", "hi95"), 5e-9, TOL)]
fwrite(res, file.path(VAL, "performance_reproduction.csv"))
cat(sprintf("%d stored numbers re-derived; max |current - stored| = %.2e; above their tolerance: %d\n", nrow(res), max(abs(res$diff)), sum(abs(res$diff) > res$tolerance)))
print(res[metric %in% c("C2 logloss", "C2 mae", "C2 whole-system J") | grepl("^C2 - ", metric) & slice != "lo95" & slice != "hi95"][, .(source, split, metric, slice, current, stored, diff)], digits = 6)
stopifnot(all(abs(res$diff) <= res$tolerance)); cat("PERFORMANCE REPRODUCED\n")
