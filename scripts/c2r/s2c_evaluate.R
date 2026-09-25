# C2 refinement research, Stage 2 (garbage time), part C: evaluate the rebuilt arms. Run from the round15-power-rating
# worktree root after s2a and s2b (A, A0, B); writes tables to docs/c2r/stage2/ in c2-refinement.
# Arms (C2 unless stated): A = frozen C2 (rebuilt, identical); A0 / B = full rebuild under that SR treatment;
# A0rows / Brows = attribution arms (the treatment's in-season SR rows and beta only). C1_* = C1 rebuilt under each
# treatment (the prior channel alone). Metrics follow the Round 15 scorer: sigma fitted leave-one-season-out on
# development (all development seasons for 2023-25), season x cutoff block bootstrap (4,000, seed 15015).
# No threshold is searched or tuned; no FCS treatment is changed.
suppressPackageStartupMessages({ source("config/paths.R"); source("config/production.R"); source(PATHS$model_ops); library(data.table)
  source("R/evaluation/evaluation_helpers.R"); for (f in c("data", "c1", "c2")) source(sprintf("R/round15/candidates/%s.R", f)) })
source("/Users/willcavender/Desktop/Revised CFB Modeling/.claude/worktrees/c2-refinement/scripts/c2r/lib_c2r.R")
OUT <- file.path(C2R, "docs/c2r/stage2"); dir.create(OUT, recursive = TRUE, showWarnings = FALSE); w <- function(x, f) { fwrite(x, file.path(OUT, f)); invisible(x) }
options(width = 250, datatable.print.nrows = 300); o2 <- file.path(C2R, "output/c2r/stage2")
d <- r15_build_data(); dv <- readRDS(file.path(C2R, "output/c2r/stage1/divisions.rds")); srt <- readRDS(file.path(o2, "sr_treatments.rds"))
bl <- setNames(lapply(c("A", "A0", "B"), function(a) readRDS(file.path(o2, sprintf("build_%s.rds", a)))), c("A", "A0", "B"))
CAP <- list(A = bl$A$cap, A0 = bl$A0$cap, B = bl$B$cap, A0rows = bl$A0$rows, Brows = bl$B$rows); ARMS <- names(CAP)
NREP <- 4000L; SEED <- 15015L; DEV <- R15C$dev

# ======================= 1. plays retained / removed and success rates =======================
acc <- rbindlist(lapply(names(srt$sr), function(tn) srt$sr[[tn]]$acc[, treatment := tn]))[type != "other"]
acc[, split := fifelse(season %in% DEV, "dev", fifelse(season >= 2023, "cond", "other"))]
pl <- acc[split != "other", .(scrimmage = sum(plays), kept = sum(kept), removed_garbage = sum(garbage), overtime = sum(overtime), exposure = sum(exposure),
                              sr_kept = sum(sr_kept * kept) / sum(kept)), by = .(split, treatment, type, offense = fifelse(off_fbs, "FBS offense", "FCS offense"))]
pl <- rbind(pl, acc[split != "other", .(offense = "all", scrimmage = sum(plays), kept = sum(kept), removed_garbage = sum(garbage), overtime = sum(overtime), exposure = sum(exposure),
                                         sr_kept = sum(sr_kept * kept) / sum(kept)), by = .(split, treatment, type)],
            acc[split != "other", .(type = "all", offense = "all", scrimmage = sum(plays), kept = sum(kept), removed_garbage = sum(garbage), overtime = sum(overtime), exposure = sum(exposure),
                                     sr_kept = sum(sr_kept * kept) / sum(kept)), by = .(split, treatment)])
pl[, share_removed := removed_garbage / scrimmage]; setorder(pl, split, type, offense, treatment)
cat("== 1. scrimmage plays retained/removed and success rate of kept plays ==\n"); print(pl, digits = 4); w(pl, "s2_plays_and_sr.csv")
# game x offense SR rows: how many change, and by how much
gm <- merge(srt$sr$A$means[, .(season, game_id, offense, defense, srA = sr, nA = sr_plays)], srt$sr$A0$means[, .(season, game_id, offense, defense, srA0 = sr, nA0 = sr_plays)], by = c("season", "game_id", "offense", "defense"), all = TRUE)
gm <- merge(gm, srt$sr$B$means[, .(season, game_id, offense, defense, srB = sr, nB = sr_plays)], by = c("season", "game_id", "offense", "defense"), all = TRUE)
typ <- rbindlist(lapply(2013:2025, function(y) { g <- d$games[[as.character(y)]]; nm <- r15_all_names(d, y); ids <- fbs_ids(d$sch[[as.character(y)]])
  data.table(season = y, team = nm$team, fbs = nm$team_id %in% ids) }))
gm <- merge(gm, typ[, .(season, offense = team, off_fbs = fbs)], by = c("season", "offense"), all.x = TRUE); gm <- merge(gm, typ[, .(season, defense = team, def_fbs = fbs)], by = c("season", "defense"), all.x = TRUE)
gm[, type := fifelse(off_fbs & def_fbs, "FBS-FBS", fifelse(off_fbs | def_fbs, "FBS-FCS", "other"))][, split := fifelse(season %in% DEV, "dev", fifelse(season >= 2023, "cond", "other"))]
gr <- gm[split != "other" & type != "other", .(rows = .N, rows_changed_A0 = sum(nA0 != nA, na.rm = TRUE), mean_dSR_A0 = mean(srA0 - srA, na.rm = TRUE), mean_abs_dSR_A0 = mean(abs(srA0 - srA), na.rm = TRUE),
                                              rows_changed_B = sum(nB != nA, na.rm = TRUE), mean_dSR_B = mean(srB - srA, na.rm = TRUE), mean_abs_dSR_B = mean(abs(srB - srA), na.rm = TRUE)),
         by = .(split, type, offense = fifelse(off_fbs, "FBS offense", "FCS offense"))][order(split, type, offense)]
cat("\n== game x offense SR rows (the in-season SR input) ==\n"); print(gr, digits = 3); w(gr, "s2_sr_rows_change.csv")

# ======================= 2. SR-to-points conversion and other construction outputs =======================
cons <- rbindlist(lapply(names(bl), function(a) { b <- bl[[a]]
  data.table(arm = a, pkey = names(b$c2$p2), beta = sapply(b$c2$p2, `[[`, "beta"), points_per_sr_point = 0.01 / sapply(b$c2$p2, `[[`, "beta"),
             omega = b$c2$om[names(b$c2$p2)], lambda0 = b$c1$lam0[names(b$c2$p2)], c1_scale = b$c1$scl[names(b$c2$p2)]) }))
cat("\n== 2. construction outputs by arm (beta = SR per point; omega, lambda0, scale re-selected by the frozen procedure) ==\n"); print(dcast(cons, pkey ~ arm, value.var = c("beta", "points_per_sr_point", "omega", "lambda0", "c1_scale")), digits = 4)
w(cons, "s2_construction_outputs.csv")
pp <- rbindlist(lapply(names(bl), function(a) rbindlist(lapply(names(bl[[a]]$c1$priors), function(z) bl[[a]]$c1$priors[[z]][, .(arm = a, season = as.integer(z), team_id, pre_power)]))))
ppw <- dcast(pp, season + team_id ~ arm, value.var = "pre_power")
pri <- ppw[season %in% c2r_S, .(teams = .N, sd_A0_minus_A = sd(A0 - A), maxabs_A0 = max(abs(A0 - A)), sd_B_minus_A = sd(B - A), maxabs_B = max(abs(B - A))), by = season]
w(pri, "s2_prior_change.csv")

# ======================= 3. the FBS-vs-FBS scoring universe =======================
G <- as.data.table(d$base$frame)[season %in% c2r_S, .(season, game_id, cutoff = format(cutoff, "%Y-%m-%d"), neutral, home_id, away_id, home_conference, away_conference, gp_home, gp_away, actual = actual_margin)]
G[, split := fifelse(season >= 2023, "cond", "dev")]; G[, hfa := vapply(season, function(y) c2r_H(d, y), 0)][, site := hfa * !as.logical(neutral)]
for (a in ARMS) G <- merge(G, CAP[[a]]$pred[, .(game_id, v = pred_margin)][, setnames(.SD, "v", a)], by = "game_id")
G <- merge(G, bl$A$pred_c1[, .(game_id, C1_A = pred_margin)], by = "game_id"); G <- merge(G, bl$A0$pred_c1[, .(game_id, C1_A0 = pred_margin)], by = "game_id"); G <- merge(G, bl$B$pred_c1[, .(game_id, C1_B = pred_margin)], by = "game_id")
MODS <- c(ARMS, "C1_A", "C1_A0", "C1_B")
stopifnot(G[split == "dev", .N] == 3868, G[split == "cond", .N] == 2398, !any(G$actual == 0)); G[, win := as.numeric(actual > 0)]
G[, gp := pmin(gp_home, gp_away)][, gpb := cut(gp, c(-Inf, 0, 1, 3, 6, Inf), labels = c("0", "1", "2-3", "4-6", "7+"))]
G[, `:=`(th = tier_of(home_conference, season), ta = tier_of(away_conference, season))]
G[, matchup := fifelse(th == "Other" | ta == "Other", "with independents", fifelse(th == "P4" & ta == "P4", "P4-P4", fifelse(th == "G5" & ta == "G5", "G5-G5", "P4-G5")))]
G[, s_p4 := p4_orientation(home_conference, away_conference, season)]
G[, pm_b := cut(abs(A), c(-Inf, 7, 14, 21, Inf), labels = c("|pred A|<7", "7-14", "14-21", "21+"))]
setorder(G, split, season, cutoff, game_id)
fit_sigma <- function(m, y) { f <- function(s) -sum(y * pnorm(m / s, log.p = TRUE) + (1 - y) * pnorm(-m / s, log.p = TRUE)); optimize(f, c(2, 80), tol = 1e-10)$minimum }
sig <- rbindlist(lapply(MODS, function(x) { g <- G[split == "dev"]
  rbind(rbindlist(lapply(DEV, function(y) data.table(model = x, split = "dev", season = y, sigma = fit_sigma(g[season != y][[x]], g[season != y]$win)))),
        data.table(model = x, split = "cond", season = NA_integer_, sigma = fit_sigma(g[[x]], g$win))) }))
sg_of <- function(x, sp, ss) { s <- sig[model == x & split == sp]; if (sp == "dev") s$sigma[match(ss, s$season)] else rep(s$sigma, length(ss)) }
clip <- function(p) pmin(pmax(p, 1e-6), 1 - 1e-6)
for (x in MODS) { m <- G[[x]]; s <- numeric(nrow(G)); for (sp in c("dev", "cond")) { i <- G$split == sp; s[i] <- sg_of(x, sp, G$season[i]) }
  p <- clip(pnorm(m / s)); set(G, j = paste0("ll_", x), value = -(G$win * log(p) + (1 - G$win) * log(1 - p))); set(G, j = paste0("br_", x), value = (p - G$win)^2)
  set(G, j = paste0("ae_", x), value = abs(m - G$actual)); set(G, j = paste0("se_", x), value = (m - G$actual)^2) }
mkboot <- function(g) { key <- paste(g$season, g$cutoff); lev <- sort(unique(key)); B <- length(lev); set.seed(SEED)
  idx <- matrix(sample.int(B, NREP * B, replace = TRUE), nrow = NREP); C <- t(apply(idx, 1, tabulate, nbins = B)); list(b = match(key, lev), B = B, C = C) }
bs <- function(bo, v) { s <- numeric(bo$B); t <- tapply(v, bo$b, sum); s[as.integer(names(t))] <- t; s }
qs <- function(x, lv = .95) unname(quantile(x, c((1 - lv) / 2, 1 - (1 - lv) / 2), na.rm = TRUE))
bmean <- function(bo, v, sel = TRUE) { sel <- rep_len(sel, length(v)) & !is.na(v); vv <- ifelse(sel, v, 0)
  dr <- as.numeric(bo$C %*% bs(bo, vv)) / as.numeric(bo$C %*% bs(bo, as.numeric(sel))); list(est = mean(v[sel]), draws = dr, n = sum(sel)) }
bdiff_rmse <- function(bo, a, b, sel = TRUE) { sel <- rep_len(sel, length(a)); n <- as.numeric(bo$C %*% bs(bo, as.numeric(sel)))
  dr <- sqrt(as.numeric(bo$C %*% bs(bo, ifelse(sel, a, 0))) / n) - sqrt(as.numeric(bo$C %*% bs(bo, ifelse(sel, b, 0))) / n); list(est = sqrt(mean(a[sel])) - sqrt(mean(b[sel])), draws = dr, n = sum(sel)) }
bols <- function(bo, x, y, sel = TRUE) { sel <- rep_len(sel, length(x)) & !is.na(x) & !is.na(y); z <- function(v) bs(bo, ifelse(sel, v, 0))
  S <- cbind(z(1), z(x), z(y), z(x * x), z(x * y)); A <- bo$C %*% S; dr <- (A[, 5] - A[, 2] * A[, 3] / A[, 1]) / (A[, 4] - A[, 2]^2 / A[, 1])
  list(est = unname(coef(lm(y[sel] ~ x[sel]))[2]), draws = dr, n = sum(sel)) }
U <- list(dev = G[split == "dev"], cond = G[split == "cond"]); BO <- lapply(U, mkboot); stopifnot(BO$dev$B == 106, BO$cond$B == 65)
absm <- function(g, x, bo = NULL) { m <- g[[x]]; r <- data.table(n = nrow(g), logloss = mean(g[[paste0("ll_", x)]]), brier = mean(g[[paste0("br_", x)]]), mae = mean(g[[paste0("ae_", x)]]),
  rmse = sqrt(mean(g[[paste0("se_", x)]])), bias = mean(m - g$actual), calib_slope = unname(coef(lm(I(g$actual - g$site) ~ I(m - g$site)))[2]))
  if (!is.null(bo)) { s <- bols(bo, m - g$site, g$actual - g$site); r[, `:=`(slope_lo95 = qs(s$draws)[1], slope_hi95 = qs(s$draws)[2])] }; r }
ov <- rbindlist(lapply(c("dev", "cond"), function(sp) rbindlist(lapply(MODS, function(x) cbind(data.table(split = sp, model = x), absm(U[[sp]], x, BO[[sp]]),
  sigma = if (sp == "cond") sig[model == x & split == "cond", sigma] else mean(sig[model == x & split == "dev", sigma]))))))
r15 <- fread("docs/round15/eval/results/metrics_overall.csv")[model == "C2" & universe %in% c("dev", "cond")]
tie <- merge(ov[model == "A", .(split, logloss, brier, mae, rmse)], r15[, .(split = universe, r_ll = logloss, r_br = brier, r_mae = mae, r_rmse = rmse)], by = "split")
print(tie); stopifnot(max(abs(tie$logloss - tie$r_ll), abs(tie$brier - tie$r_br), abs(tie$mae - tie$r_mae), abs(tie$rmse - tie$r_rmse)) < 1e-9)
cat("\n== 3a. FBS-vs-FBS overall (A reproduces Round 15's C2 exactly) ==\n"); print(ov, digits = 5); w(ov, "s2_fbs_overall.csv")
MET <- c(logloss = "ll_", brier = "br_", mae = "ae_")
drow <- function(g, bo, a, b, sel = TRUE) rbind(rbindlist(lapply(names(MET), function(mt) { r <- bmean(bo, g[[paste0(MET[[mt]], a)]] - g[[paste0(MET[[mt]], b)]], sel)
    data.table(metric = mt, delta = r$est, lo95 = qs(r$draws)[1], hi95 = qs(r$draws)[2], n = r$n) })),
  { r <- bdiff_rmse(bo, g[[paste0("se_", a)]], g[[paste0("se_", b)]], sel); data.table(metric = "rmse", delta = r$est, lo95 = qs(r$draws)[1], hi95 = qs(r$draws)[2], n = r$n) })
PAIRS <- list(c("A0", "A"), c("B", "A"), c("A0rows", "A"), c("Brows", "A"), c("C1_A0", "C1_A"), c("C1_B", "C1_A"))
dl <- rbindlist(lapply(c("dev", "cond"), function(sp) rbindlist(lapply(PAIRS, function(p) cbind(data.table(split = sp, comparison = paste(p[1], "-", p[2])), drow(U[[sp]], BO[[sp]], p[1], p[2]))))))
cat("\n== 3b. paired deltas vs frozen A (negative = better) ==\n"); print(dl, digits = 3); w(dl, "s2_fbs_deltas.csv")
SL <- c(season = "season", gp_bucket = "gpb", matchup = "matchup", pred_margin = "pm_b")
sld <- rbindlist(lapply(c("dev", "cond"), function(sp) { g <- U[[sp]]; rbindlist(lapply(names(SL), function(sn) { v <- as.character(g[[SL[[sn]]]])
  rbindlist(lapply(sort(unique(v)), function(lv) { sel <- v == lv; rbindlist(lapply(list(c("A0", "A"), c("B", "A")), function(p)
    cbind(data.table(split = sp, slice_type = sn, slice = lv, comparison = paste(p[1], "-", p[2]), A_logloss = mean(g[[paste0("ll_A")]][sel]), A_mae = mean(g$ae_A[sel])), drow(g, BO[[sp]], p[1], p[2], sel)))) })) })) }))
w(sld, "s2_fbs_slice_deltas.csv")
cat("\n== 3c. slice deltas (log-loss and MAE) ==\n"); print(dcast(sld[metric %in% c("logloss", "mae")], split + slice_type + slice ~ comparison + metric, value.var = "delta")[order(split, slice_type, slice)], digits = 3)
cal <- rbindlist(lapply(c("dev", "cond"), function(sp) { g <- U[[sp]]; rbindlist(lapply(c("A", "A0", "B"), function(x) rbindlist(lapply(c(levels(g$gpb), "pooled"), function(lv) {
  sel <- if (lv == "pooled") rep(TRUE, nrow(g)) else as.character(g$gpb) == lv; r <- bols(BO[[sp]], g[[x]] - g$site, g$actual - g$site, sel)
  data.table(split = sp, model = x, gp_bucket = lv, n = r$n, slope = r$est, lo95 = qs(r$draws)[1], hi95 = qs(r$draws)[2]) })))) }))
w(cal, "s2_calibration_slopes.csv")
tierb <- rbindlist(lapply(c("dev", "cond"), function(sp) { g <- U[[sp]]; rbindlist(lapply(c("A", "A0", "B"), function(x) { r <- bmean(BO[[sp]], (g$actual - g[[x]]) * g$s_p4, g$s_p4 != 0)
  data.table(split = sp, model = x, n = r$n, p4_vs_g5_underprediction = r$est, lo95 = qs(r$draws)[1], hi95 = qs(r$draws)[2]) })) }))
cat("\n== 3d. P4-vs-G5 oriented error (actual - predicted, P4 side) ==\n"); print(tierb, digits = 3); w(tierb, "s2_p4_g5.csv")

# ======================= 4. rating stability (FBS ratings, week to week) =======================
stab <- rbindlist(lapply(c("A", "A0", "B"), function(a) { f <- CAP[[a]]$ent[fbs == TRUE, .(season, cutoff, team_id, rating = power, gp)]; setorder(f, season, team_id, cutoff)
  f[, prev := shift(rating), by = .(season, team_id)]; f <- f[!is.na(prev)]
  f[, .(arm = a, n = .N, mean_abs_change = mean(abs(rating - prev))), by = .(split = fifelse(season >= 2023, "cond", "dev"))] }))
kend <- rbindlist(lapply(c("A", "A0", "B"), function(a) { f <- CAP[[a]]$ent[fbs == TRUE, .(season, cutoff, team_id, rating = power)]
  f[, { cs <- sort(unique(cutoff)); out <- numeric(); for (i in seq_along(cs)[-1]) { x0 <- .SD[cutoff == cs[i - 1]]; x1 <- .SD[cutoff == cs[i]]; top <- x0[order(-rating)][1:25, team_id]
      r0 <- x0$rating[match(top, x0$team_id)]; r1 <- x1$rating[match(top, x1$team_id)]; pr <- combn(25, 2); out <- c(out, mean(sign(r0[pr[1, ]] - r0[pr[2, ]]) != sign(r1[pr[1, ]] - r1[pr[2, ]]))) }
    .(kendall = mean(out)) }, by = season][, .(arm = a, kendall_top25 = mean(kendall)), by = .(split = fifelse(season >= 2023, "cond", "dev"))] }))
stab <- merge(stab, kend, by = c("split", "arm")); cat("\n== 4. rating stability ==\n"); print(stab, digits = 4); w(stab, "s2_stability.csv")

# ======================= 5. downstream: how far does each treatment move ratings and predictions? =======================
fr <- function(a) CAP[[a]]$ent[fbs == TRUE, .(season, cutoff, team_id, r = power)]
ds <- rbindlist(lapply(c("A0", "B", "A0rows", "Brows"), function(a) { m <- merge(fr(a), fr("A"), by = c("season", "cutoff", "team_id"), suffixes = c("", "_A"))
  data.table(arm = a, fbs_rating_sd_diff = sd(m$r - m$r_A), fbs_rating_maxabs = max(abs(m$r - m$r_A)), pred_sd_diff = sd(G[[a]] - G$A), pred_maxabs = max(abs(G[[a]] - G$A)),
             pred_mean_abs = mean(abs(G[[a]] - G$A))) }))
ds <- rbind(ds, data.table(arm = c("C1_A0", "C1_B"), pred_sd_diff = c(sd(G$C1_A0 - G$C1_A), sd(G$C1_B - G$C1_A)), pred_maxabs = c(max(abs(G$C1_A0 - G$C1_A)), max(abs(G$C1_B - G$C1_A))),
                             pred_mean_abs = c(mean(abs(G$C1_A0 - G$C1_A)), mean(abs(G$C1_B - G$C1_A)))), fill = TRUE)
cat("\n== 5. downstream movement vs A (FBS ratings at every cutoff; FBS-vs-FBS predictions) ==\n"); print(ds, digits = 3); w(ds, "s2_downstream_movement.csv")

# ======================= 6. FBS-vs-FCS games and the FCS level =======================
snaps <- unique(rbindlist(lapply(d$base$snap, function(sn) data.table(season = sn$season, cutoff = format(sn$cutoff, "%Y-%m-%d"), ct = sn$cutoff))))
snaps <- snaps[!duplicated(snaps[, .(season, cutoff)])]; setorder(snaps, season, ct)
fc0 <- rbindlist(lapply(c2r_S, function(y) { g <- d$games[[as.character(y)]][final == TRUE & xor(home_fbs %in% TRUE, away_fbs %in% TRUE)]
  cs <- snaps[season == y]; g[, ci := findInterval(as.numeric(kickoff), as.numeric(cs$ct))]; g <- g[ci >= 1]
  g[, .(season, game_id, neutral = as.logical(neutral), fbs_home = home_fbs %in% TRUE, fbs_id = fifelse(home_fbs %in% TRUE, home_id, away_id), fcs_id = fifelse(home_fbs %in% TRUE, away_id, home_id),
        actual = fifelse(home_fbs %in% TRUE, home_points - away_points, away_points - home_points), cutoff = cs$cutoff[ci])] }))
fc0[, split := fifelse(season >= 2023, "cond", "dev")][, H := vapply(season, function(y) c2r_H(d, y), 0)][, site := H * (!neutral) * fifelse(fbs_home, 1, -1)]
fcs_eval <- function(a) { cp <- CAP[[a]]; f <- copy(fc0)
  f <- merge(f, cp$ent[fbs == TRUE, .(season, cutoff, fbs_id = team_id, fbs_r = power)], by = c("season", "cutoff", "fbs_id"), all.x = TRUE); stopifnot(!anyNA(f$fbs_r))
  f <- merge(f, cp$ent[fbs == FALSE, .(season, cutoff, fcs_id = team_id, fcs_r = power, fcs_gp = gp, sr_link, sr_ff, pts_link)], by = c("season", "cutoff", "fcs_id"), all.x = TRUE)
  f <- merge(f, cp$fcs_prior[, .(season, cutoff, fcs_id = team_id, fcs_prior = prior_power_c)], by = c("season", "cutoff", "fcs_id"))
  f[, `:=`(arm = a, has = is.finite(fcs_r), pred = fbs_r - fifelse(is.finite(fcs_r), fcs_r, fcs_prior) + site)][, u := fbs_r + site - actual]
  x <- if (a %in% sig$model) a else "A"; s <- ifelse(f$split == "dev", sg_of(x, "dev", f$season), sg_of(x, "cond", f$season))
  p <- clip(pnorm(f$pred / s)); yw <- as.numeric(f$actual > 0); f[, `:=`(ll = -(yw * log(p) + (1 - yw) * log(1 - p)), br = (p - yw)^2)]; f }
FC <- rbindlist(lapply(ARMS, fcs_eval))
ti <- FC[arm == "A" & has == TRUE, .(n = .N, b = mean(fifelse(fbs_home, pred - actual, actual - pred))), by = split]
stopifnot(ti[split == "dev", n] == 335, abs(ti[split == "dev", b] + 10.4960081882883) < 1e-9, abs(ti[split == "cond", b] + 11.3137710807295) < 1e-9)
fcs_tab <- FC[, .(n = .N, bias = mean(pred - actual), mae = mean(abs(pred - actual)), rmse = sqrt(mean((pred - actual)^2)), logloss = mean(ll), brier = mean(br),
                  fcs_level = mean(fifelse(has, fcs_r, fcs_prior)), implied_level = mean(u), sr_link_contrib = mean(sr_link, na.rm = TRUE), fbs_r = mean(fbs_r)),
              by = .(split, arm, group = fifelse(has, "rated (gp>=1)", "first game (prior mean)"))][order(split, group, arm)]
cat("\n== 6a. FBS-vs-FCS (FBS-oriented; bias = pred - actual; negative = FCS rated too high) ==\n"); print(fcs_tab, digits = 4); w(fcs_tab, "s2_fbs_vs_fcs.csv")
fcd <- rbindlist(lapply(c("A0", "B", "A0rows", "Brows"), function(a) { m <- merge(FC[arm == a, .(game_id, split, has, season, cutoff, pred, fcs_r, actual)], FC[arm == "A", .(game_id, predA = pred, fcs_rA = fcs_r)], by = "game_id")
  m[, { e0 <- abs(pred - actual) - abs(predA - actual); ix <- split(seq_along(e0), paste(season, cutoff)); sm <- vapply(ix, function(i) sum(e0[i]), 0); k <- lengths(ix); set.seed(SEED)
        bsd <- replicate(2000, { j <- sample.int(length(ix), replace = TRUE); sum(sm[j]) / sum(k[j]) })
        .(arm = a, n = .N, d_pred = mean(pred - predA), d_fcs_rating = mean(fcs_r - fcs_rA, na.rm = TRUE), d_mae = mean(e0), d_mae_lo95 = qs(bsd)[1], d_mae_hi95 = qs(bsd)[2]) }, by = .(split, has)] }))
cat("\n== 6b. change vs A on FBS-vs-FCS games (d_pred > 0: FBS margin predicted larger = FCS rated lower) ==\n"); print(fcd, digits = 3); w(fcd, "s2_fbs_vs_fcs_change.csv")
fcs_season <- FC[has == TRUE, .(n = .N, offset = mean(actual - pred)), by = .(arm, season)]; w(dcast(fcs_season, season ~ arm, value.var = "offset"), "s2_fcs_offset_by_season.csv")
fcs_gp <- FC[has == TRUE, .(n = .N, bias = mean(pred - actual)), by = .(split, arm, fcs_gp = cut(fcs_gp, c(0, 1, 3, Inf), labels = c("1", "2-3", "4+")))]
w(dcast(fcs_gp, split + fcs_gp ~ arm, value.var = "bias"), "s2_fcs_bias_by_gp.csv")
cat("\n== offset by season / bias by FCS games played ==\n"); print(dcast(fcs_season, season ~ arm, value.var = "offset"), digits = 3); print(dcast(fcs_gp, split + fcs_gp ~ arm, value.var = "bias"), digits = 3)
# relative FCS ranking: slope of implied strength on the FCS rating; FCS-vs-FCS out-of-sample games
ordr <- FC[has == TRUE, { f <- lm(u ~ fcs_r); .(n = .N, slope = coef(f)[2], se = summary(f)$coefficients[2, 2], cor = cor(u, fcs_r)) }, by = .(split, arm)]
ffg <- rbindlist(lapply(c2r_S, function(y) { g <- d$games[[as.character(y)]][final == TRUE & !(home_fbs %in% TRUE) & !(away_fbs %in% TRUE)]
  cs <- snaps[season == y]; g[, ci := findInterval(as.numeric(kickoff), as.numeric(cs$ct))]; g <- g[ci >= 1]
  g[, .(season, game_id, neutral = as.logical(neutral), home_id, away_id, actual = home_points - away_points, cutoff = cs$cutoff[ci])] }))
ffg <- merge(ffg, dv[, .(season, home_id = team_id, dh = div)], by = c("season", "home_id"), all.x = TRUE); ffg <- merge(ffg, dv[, .(season, away_id = team_id, da = div)], by = c("season", "away_id"), all.x = TRUE)
ffg <- ffg[dh %in% "fcs" & da %in% "fcs"][, H := vapply(season, function(y) c2r_H(d, y), 0)]
ffr <- rbindlist(lapply(ARMS, function(a) { e <- CAP[[a]]$ent[fbs == FALSE, .(season, cutoff, team_id, r = power)]
  m <- merge(merge(ffg, e[, .(season, cutoff, home_id = team_id, rh = r)], by = c("season", "cutoff", "home_id")), e[, .(season, cutoff, away_id = team_id, ra = r)], by = c("season", "cutoff", "away_id"))
  m[, pred := rh - ra + H * (!neutral)][, .(arm = a, n = .N, bias = mean(pred - actual), mae = mean(abs(pred - actual)), calib_slope = coef(lm(actual ~ pred))[2], cor = cor(pred, actual)),
    by = .(split = fifelse(season >= 2023, "cond", "dev"))] }))
ordr <- merge(ordr, ffr, by = c("split", "arm"), suffixes = c("_fbsfcs", "_fcsfcs")); cat("\n== 6c. relative FCS ranking quality ==\n"); print(ordr, digits = 3); w(ordr, "s2_fcs_ranking.csv")

# ======================= 7. is SR evidence misleading about FCS teams? =======================
lv <- rbindlist(lapply(c("A", "A0", "B"), function(a) { cu <- CAP[[a]]$cuts[n_rows > 0]; cu[, last := cutoff == max(cutoff), by = season]
  rbind(cu[last == TRUE, .(arm = a, when = "final cutoff", pts_link_resid = mean(pts_link_resid), sr_link_resid = mean(sr_link_resid), pi_prior = mean(pi_prior_fcsdiv)), by = .(split = fifelse(season >= 2023, "cond", "dev"))],
        cu[, .(arm = a, when = "all cutoffs", pts_link_resid = mean(pts_link_resid, na.rm = TRUE), sr_link_resid = mean(sr_link_resid, na.rm = TRUE), pi_prior = mean(pi_prior_fcsdiv, na.rm = TRUE)), by = .(split = fifelse(season >= 2023, "cond", "dev"))]) }))
cat("\n== 7a. in-sample FBS-margin residual on FBS-vs-FCS games, points rows vs SR rows (points units; > 0 = FBS better than C2's fit) ==\n"); print(lv, digits = 3); w(lv, "s2_link_residuals.csv")
# model-free: SR margin (points units via the arm's beta) vs points margin (net of home field), by game type, end of season
gsr <- rbindlist(lapply(c("A", "A0", "B"), function(a) { mm <- srt$sr[[a]]$means
  rbindlist(lapply(c2r_S, function(y) { g <- d$games[[as.character(y)]][final == TRUE & (home_fbs %in% TRUE | away_fbs %in% TRUE)]; nm <- r15_all_names(d, y); be <- bl[[a]]$c2$p2[[as.character(keyof(y))]]$beta
    s <- merge(mm[season == y], nm[, .(offense = team, off_id = team_id)], by = "offense")
    g <- merge(g, s[, .(game_id, home_id = off_id, sh = sr)], by = c("game_id", "home_id")); g <- merge(g, s[, .(game_id, away_id = off_id, sa = sr)], by = c("game_id", "away_id"))
    g[, .(arm = a, season, type = fifelse((home_fbs %in% TRUE) & (away_fbs %in% TRUE), "FBS-FBS", "FBS-FCS"), o = fifelse(home_fbs %in% TRUE, 1, -1),
          pts = home_points - away_points - c2r_H(d, y) * (!as.logical(neutral)), srm = (sh - sa) / be)] })) }))
gsr[, `:=`(pts = o * pts, srm = o * srm)]
gst <- gsr[, { f <- lm(pts ~ srm); .(games = .N, mean_points_margin = mean(pts), mean_sr_margin_pts = mean(srm), ratio = mean(srm) / mean(pts), slope = coef(f)[2], intercept = coef(f)[1]) },
           by = .(split = fifelse(season >= 2023, "cond", "dev"), type, arm)][order(split, type, arm)]
cat("\n== 7b. SR margin in points (arm's beta) vs points margin net of home field; FBS-vs-FCS oriented to FBS (FBS-vs-FBS home-oriented) ==\n"); print(gst, digits = 3); w(gst, "s2_sr_vs_points_margin.csv")
saveRDS(list(G = G, FC = FC, sig = sig), file.path(o2, "eval.rds")); cat("\nStage 2 evaluation done\n")
