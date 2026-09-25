# C2 refinement research, Stage 3, part C: evaluate the arms and apply the selection rule of docs/c2r/STAGE3_PLAN.md.
# Usage (round15-power-rating worktree root): Rscript <c2r>/scripts/c2r/s3c_evaluate.R first | final
#   first: arms C0, M, G, L -> within-family selection; writes selection_first.rds (input to s3b_arms.R second)
#   final: all arms including S / FLAT / SR -> full tables in docs/c2r/stage3/
stage <- commandArgs(trailingOnly = TRUE)[1]; stopifnot(stage %in% c("first", "final", "posthoc"))
suppressPackageStartupMessages({ source("config/paths.R"); source("config/production.R"); source(PATHS$model_ops); library(data.table)
  source("R/evaluation/evaluation_helpers.R"); for (f in c("data", "c1", "c2")) source(sprintf("R/round15/candidates/%s.R", f)) })
source("/Users/willcavender/Desktop/Revised CFB Modeling/.claude/worktrees/c2-refinement/scripts/c2r/lib_c2r.R"); source(file.path(C2R, "scripts/c2r/lib_s3.R"))
out <- file.path(C2R, "output/c2r/stage3"); OUT <- file.path(C2R, "docs/c2r/stage3"); w <- function(x, f) { fwrite(x, file.path(OUT, f)); invisible(x) }
options(width = 250, datatable.print.nrows = 400); DEV <- R15C$dev; NREP <- 4000L; SEED <- 15015L
d <- r15_build_data(); dv <- readRDS(file.path(C2R, "output/c2r/stage1/divisions.rds"))
AR <- lapply(setNames(nm = sub("\\.rds$", "", list.files(file.path(out, "arms")))), function(a) readRDS(file.path(out, "arms", paste0(a, ".rds"))))
if (stage == "first") AR <- AR[grepl("^(C0|G|L_)", names(AR))]
if (stage == "posthoc") { AR <- c(AR[c("C0", "G12", "L_last_n20")], lapply(setNames(nm = c("P_noDiv", "P_noLow")), function(a) readRDS(file.path(out, "posthoc", paste0(a, ".rds"))))) }
RA <- names(AR); XG <- c(0, 4, 6, 8, 10, 12, 14)
fam <- function(a) fifelse(a == "C0", "C0", fifelse(grepl("^G", a), "G", fifelse(grepl("^L_", a), "L", fifelse(grepl("^S\\d_on_L", a), "S_L", fifelse(grepl("^S\\d_on_G", a), "S_G", fifelse(grepl("^FLAT", a), "FLAT", "SR"))))))

# ---------------- FBS-vs-FBS universe ----------------
G <- as.data.table(d$base$frame)[season %in% c2r_S, .(season, game_id, cutoff = format(cutoff, "%Y-%m-%d"), neutral, home_id, away_id, home_conference, away_conference, gp_home, gp_away, actual = actual_margin)]
G[, split := fifelse(season >= 2023, "cond", "dev")][, hfa := vapply(season, function(y) c2r_H(d, y), 0)][, site := hfa * (!as.logical(neutral))][, win := as.numeric(actual > 0)]
for (a in RA) G <- merge(G, AR[[a]]$pred[, .(game_id, v = pred_margin)][, setnames(.SD, "v", a)], by = "game_id")
G[, gpb := cut(pmin(gp_home, gp_away), c(-Inf, 0, 1, 3, 6, Inf), labels = c("0", "1", "2-3", "4-6", "7+"))][, s_p4 := p4_orientation(home_conference, away_conference, season)]
setorder(G, split, season, cutoff, game_id); stopifnot(G[split == "dev", .N] == 3868, G[split == "cond", .N] == 2398)
fit_sigma <- function(m, y) { f <- function(s) -sum(y * pnorm(m / s, log.p = TRUE) + (1 - y) * pnorm(-m / s, log.p = TRUE)); optimize(f, c(2, 80), tol = 1e-10)$minimum }
sig <- rbindlist(lapply(RA, function(x) { g <- G[split == "dev"]
  rbind(rbindlist(lapply(DEV, function(y) data.table(model = x, split = "dev", season = y, sigma = fit_sigma(g[season != y][[x]], g[season != y]$win)))),
        data.table(model = x, split = "cond", season = NA_integer_, sigma = fit_sigma(g[[x]], g$win))) }))
sgv <- function(x, sp, ss) { sd_ <- sig[model == x[1] & split == "dev"]; sc_ <- sig[model == x[1] & split == "cond", sigma]; ifelse(sp == "dev", sd_$sigma[match(ss, sd_$season)], sc_) }
clip <- function(p) pmin(pmax(p, 1e-6), 1 - 1e-6)
llf <- function(m, s, y) { p <- clip(pnorm(m / s)); -(y * log(p) + (1 - y) * log(1 - p)) }; brf <- function(m, s, y) (clip(pnorm(m / s)) - y)^2
LG <- rbindlist(lapply(RA, function(a) G[, .(arm = a, set = "FBS-FBS", season, split, cutoff, game_id, pred = get(a), actual, s = sgv(a, split, season))]))

# ---------------- FBS-vs-FCS games (every game after the first cutoff; first games under each arm's own rule) ----------------
snaps <- unique(rbindlist(lapply(d$base$snap, function(sn) data.table(season = sn$season, cutoff = format(sn$cutoff, "%Y-%m-%d"), ct = sn$cutoff))))
snaps <- snaps[!duplicated(snaps[, .(season, cutoff)])]; setorder(snaps, season, ct)
FC0 <- rbindlist(lapply(c2r_S, function(y) { g <- d$games[[as.character(y)]][final == TRUE & xor(home_fbs %in% TRUE, away_fbs %in% TRUE)]
  cs <- snaps[season == y]; g[, ci := findInterval(as.numeric(kickoff), as.numeric(cs$ct))]; g <- g[ci >= 1]
  g[, .(season, game_id, neutral = as.logical(neutral), fbs_home = home_fbs %in% TRUE, fbs_id = fifelse(home_fbs %in% TRUE, home_id, away_id), fcs_id = fifelse(home_fbs %in% TRUE, away_id, home_id),
        actual = fifelse(home_fbs %in% TRUE, home_points - away_points, away_points - home_points), cutoff = cs$cutoff[ci])] }))
FC0[, split := fifelse(season >= 2023, "cond", "dev")][, H := vapply(season, function(y) c2r_H(d, y), 0)][, site := H * (!neutral) * fifelse(fbs_home, 1, -1)]
fcs_of <- function(a) { cp <- AR[[a]]; f <- merge(copy(FC0), cp$ent[fbs == TRUE, .(season, cutoff, fbs_id = team_id, fbs_r = power)], by = c("season", "cutoff", "fbs_id"))
  f <- merge(f, cp$ent[fbs == FALSE, .(season, cutoff, fcs_id = team_id, fcs_in = power, fcs_gp = gp)], by = c("season", "cutoff", "fcs_id"), all.x = TRUE)
  f <- merge(f, cp$fcs_prior[, .(season, cutoff, fcs_id = team_id, fg = first_game_power, grp)], by = c("season", "cutoff", "fcs_id")); stopifnot(nrow(f) == nrow(FC0))
  f[, `:=`(arm = a, first = !is.finite(fcs_in), fcs_r = fifelse(is.finite(fcs_in), fcs_in, fg))][, pred := fbs_r - fcs_r + site][is.na(fcs_gp), fcs_gp := 0L][] }
FC <- rbindlist(lapply(RA, fcs_of)); FC[, s := sgv(arm, split, season), by = arm]
# matchup benchmark M(X): C0 predictions + X on FBS-vs-FCS games only (no rating changes); sigma of C0
FCM <- rbindlist(lapply(XG, function(X) FC[arm == "C0"][, `:=`(arm = sprintf("M%02d", X), pred = pred + X)]))
FCA <- rbind(FC, FCM, fill = TRUE)
LF <- FCA[, .(arm, set = "FBS-FCS", season, split, cutoff, game_id, pred, actual, s)]
LGM <- rbindlist(lapply(XG, function(X) LG[arm == "C0"][, arm := sprintf("M%02d", X)]))
L <- rbind(LG, LGM, LF)[, `:=`(ll = llf(pred, s, as.numeric(actual > 0)), br = brf(pred, s, as.numeric(actual > 0)))]
ALL <- unique(L$arm); famx <- function(a) fifelse(grepl("^M\\d", a), "M", fam(a))

# ---------------- FCS-vs-FCS (both FCS-division, both rated) ----------------
FF0 <- rbindlist(lapply(c2r_S, function(y) { g <- d$games[[as.character(y)]][final == TRUE & !(home_fbs %in% TRUE) & !(away_fbs %in% TRUE)]
  cs <- snaps[season == y]; g[, ci := findInterval(as.numeric(kickoff), as.numeric(cs$ct))]; g <- g[ci >= 1]
  g[, .(season, game_id, neutral = as.logical(neutral), home_id, away_id, actual = home_points - away_points, cutoff = cs$cutoff[ci])] }))
FF0[, H := vapply(season, function(y) c2r_H(d, y), 0)][, split := fifelse(season >= 2023, "cond", "dev")]
FF <- rbindlist(lapply(RA, function(a) { e <- AR[[a]]$ent[fbs == FALSE & grp == "fcs", .(season, cutoff, team_id, r = power)]
  m <- merge(merge(FF0, e[, .(season, cutoff, home_id = team_id, rh = r)], by = c("season", "cutoff", "home_id")), e[, .(season, cutoff, away_id = team_id, ra = r)], by = c("season", "cutoff", "away_id"))
  m[, `:=`(arm = a, pred = rh - ra + H * (!neutral))] }))
ffm <- FF[, .(n = .N, mae = mean(abs(pred - actual)), rmse = sqrt(mean((pred - actual)^2)), bias = mean(pred - actual), calib_slope = coef(lm(actual ~ pred))[2],
              spearman = cor(pred, actual, method = "spearman")), by = .(split, arm)]

# ---------------- summary per arm ----------------
Jt <- L[, .(J = mean(ll)), by = .(split, arm)]
fbm <- LG[, .(n = .N, logloss = mean(llf(pred, s, as.numeric(actual > 0))), brier = mean(brf(pred, s, as.numeric(actual > 0))), mae = mean(abs(pred - actual)), rmse = sqrt(mean((pred - actual)^2)),
              winners = mean(sign(pred) == sign(actual)), calib_slope = coef(lm(I(actual - 0) ~ pred))[2]), by = .(split, arm)]
tb <- merge(G[, .(game_id, site, s_p4)], LG, by = "game_id")
fbm <- merge(fbm, tb[, .(calib_slope_site = coef(lm(I(actual - site) ~ I(pred - site)))[2], p4g5 = mean(((actual - pred) * s_p4)[s_p4 != 0])), by = .(split, arm)], by = c("split", "arm"))
fbm <- rbind(fbm, rbindlist(lapply(XG, function(X) fbm[arm == "C0"][, arm := sprintf("M%02d", X)])))
fcm <- FCA[, .(n = .N, bias = mean(pred - actual), mae = mean(abs(pred - actual)), rmse = sqrt(mean((pred - actual)^2)), winners = mean(sign(pred) == sign(actual)),
               logloss = mean(llf(pred, s, as.numeric(actual > 0))), brier = mean(brf(pred, s, as.numeric(actual > 0))), pred_sd = sd(pred), pred_mean = mean(pred), fcs_mean = mean(fcs_r)), by = .(split, arm)]
fcm_fl <- FCA[, .(n = .N, bias = mean(pred - actual), mae = mean(abs(pred - actual)), rmse = sqrt(mean((pred - actual)^2))), by = .(split, arm, game = fifelse(first, "first game", "later"))]
sm <- Reduce(function(a, b) merge(a, b, by = c("split", "arm"), all.x = TRUE), list(Jt, setnames(copy(fbm), setdiff(names(fbm), c("split", "arm")), paste0("fbsfbs_", setdiff(names(fbm), c("split", "arm")))),
       setnames(copy(fcm), setdiff(names(fcm), c("split", "arm")), paste0("fbsfcs_", setdiff(names(fcm), c("split", "arm")))),
       setnames(copy(ffm), setdiff(names(ffm), c("split", "arm")), paste0("fcsfcs_", setdiff(names(ffm), c("split", "arm"))))))
sm[, family := famx(arm)]; setorder(sm, split, family, arm)

if (stage == "posthoc") { x <- sm[arm %in% names(AR), .(split, arm, J, fbsfbs_logloss, fbsfbs_mae, fbsfcs_bias, fbsfcs_mae, fbsfcs_logloss, fbsfcs_fcs_mean, fcsfcs_mae, fcsfcs_calib_slope, fcsfcs_spearman)]
  print(x, digits = 5); w(x, "s3_posthoc_attribution.csv"); quit(save = "no") }
# ---------------- leave-one-season-out selection within each family (development only) ----------------
famsets <- split(ALL, famx(ALL)); famsets <- famsets[intersect(names(famsets), c("M", "G", "L", "S_L", "S_G"))]
if ("S_L" %in% names(famsets)) { selL <- readRDS(file.path(out, "selection_first.rds"))$L$name; famsets$S_L <- c(selL, famsets$S_L) }
if ("S_G" %in% names(famsets)) { selG <- readRDS(file.path(out, "selection_first.rds"))$G$name; famsets$S_G <- c(selG, famsets$S_G) }
Ld <- L[split == "dev"]
loso <- rbindlist(lapply(names(famsets), function(fn) { cand <- famsets[[fn]]
  picks <- rbindlist(lapply(DEV, function(sv) { j <- Ld[arm %in% cand & season != sv, .(J = mean(ll)), by = arm][order(J)]; data.table(family = fn, held_out = sv, pick = j$arm[1]) }))
  h <- rbindlist(lapply(seq_len(nrow(picks)), function(i) Ld[arm == picks$pick[i] & season == picks$held_out[i]]))
  all5 <- Ld[arm %in% cand, .(J = mean(ll)), by = arm][order(J)]$arm[1]
  data.table(family = fn, picks = paste(sprintf("%d:%s", picks$held_out, picks$pick), collapse = " "), honest_J = mean(h$ll), honest_fbsfbs_ll = mean(h[set == "FBS-FBS", ll]),
             honest_fbsfcs_bias = mean(h[set == "FBS-FCS", pred - actual]), honest_fbsfcs_mae = mean(h[set == "FBS-FCS", abs(pred - actual)]), selected_all_dev = all5) }))
c0 <- Ld[arm == "C0"]; loso <- rbind(data.table(family = "C0", picks = "", honest_J = mean(c0$ll), honest_fbsfbs_ll = mean(c0[set == "FBS-FBS", ll]),
                                               honest_fbsfcs_bias = mean(c0[set == "FBS-FCS", pred - actual]), honest_fbsfcs_mae = mean(c0[set == "FBS-FCS", abs(pred - actual)]), selected_all_dev = "C0"), loso)
loso[, `:=`(dJ_vs_C0 = honest_J - honest_J[family == "C0"], dFBSFBS_vs_C0 = honest_fbsfbs_ll - honest_fbsfbs_ll[family == "C0"])]
c0ff <- ffm[split == "dev" & arm == "C0"]
loso[, `:=`(fcsfcs_mae_sel = ffm[split == "dev"][match(selected_all_dev, arm), mae], fcsfcs_slope_sel = ffm[split == "dev"][match(selected_all_dev, arm), calib_slope])]
loso[, eligible := family != "M" & family != "C0" & dJ_vs_C0 < 0 & dFBSFBS_vs_C0 <= 5e-4 & fcsfcs_mae_sel <= c0ff$mae + 0.10 & fcsfcs_slope_sel >= 0.9 & fcsfcs_slope_sel <= 1.1]
cat("== leave-one-season-out selection (development) ==\n"); print(loso, digits = 5); w(loso, sprintf("s3_selection_%s.csv", stage))

if (stage == "first") {
  pickL <- loso[family == "L", selected_all_dev]; pickG <- loso[family == "G", selected_all_dev]
  saveRDS(list(L = list(name = pickL, opt = AR[[pickL]]$opt, anchor = AR[[pickL]]$anchor), G = list(name = pickG, opt = AR[[pickG]]$opt)), file.path(out, "selection_first.rds"))
  print(sm[split == "dev", .(arm, J, fbsfbs_logloss, fbsfbs_mae, fbsfcs_bias, fbsfcs_mae, fbsfcs_fcs_mean, fcsfcs_mae, fcsfcs_calib_slope)], digits = 5)
  quit(save = "no")
}
w(sm, "s3_summary_all_arms.csv"); w(fcm_fl, "s3_fbsfcs_first_vs_later.csv"); w(sig, "s3_sigma.csv")

# ---------------- final: family choice, then detailed tables for the key arms ----------------
el <- loso[eligible == TRUE]; best <- min(el$honest_J); ord <- c(G = 1, L = 2, S_L = 3, S_G = 3)
chosen <- el[honest_J <= best + 5e-4][order(ord[family], honest_J)][1]
cat("\n== family chosen by the predeclared rule:", chosen$family, "->", chosen$selected_all_dev, "==\n")
selM <- loso[family == "M", selected_all_dev]; selG <- loso[family == "G", selected_all_dev]; selL <- loso[family == "L", selected_all_dev]
selSL <- loso[family == "S_L", selected_all_dev]; KEY <- unique(c("C0", selM, selG, selL, selSL, loso[family == "S_G", selected_all_dev], grep("^FLAT|^SR", RA, value = TRUE), chosen$selected_all_dev))
saveRDS(list(chosen = chosen, key = KEY, loso = loso), file.path(out, "selection_final.rds"))
print(sm[arm %in% KEY, .(split, arm, J, fbsfbs_logloss, fbsfbs_brier, fbsfbs_mae, fbsfbs_rmse, fbsfbs_winners, fbsfbs_calib_slope_site, fbsfbs_p4g5, fbsfcs_bias, fbsfcs_mae, fbsfcs_rmse, fbsfcs_winners,
             fbsfcs_logloss, fbsfcs_pred_sd, fbsfcs_fcs_mean, fcsfcs_mae, fcsfcs_rmse, fcsfcs_bias, fcsfcs_calib_slope, fcsfcs_spearman)], digits = 4)
# bootstrap deltas vs C0 (FBS-vs-FBS metrics and the whole-system J), R15 block bootstrap
mkboot <- function(k) { lev <- sort(unique(k)); B <- length(lev); set.seed(SEED); idx <- matrix(sample.int(B, NREP * B, replace = TRUE), nrow = NREP); list(b = match(k, lev), B = B, C = t(apply(idx, 1, tabulate, nbins = B))) }
bs <- function(bo, v) { s <- numeric(bo$B); t <- tapply(v, bo$b, sum); s[as.integer(names(t))] <- t; s }
bm <- function(bo, v) { dr <- as.numeric(bo$C %*% bs(bo, v)) / as.numeric(bo$C %*% bs(bo, rep(1, length(v)))); c(est = mean(v), lo = unname(quantile(dr, .025)), hi = unname(quantile(dr, .975))) }
dl <- rbindlist(lapply(c("dev", "cond"), function(sp) rbindlist(lapply(setdiff(KEY, "C0"), function(a) rbindlist(lapply(c("FBS-FBS", "all"), function(st) {
  x <- L[split == sp & arm == a & (st == "all" | set == st)]; y <- L[split == sp & arm == "C0" & (st == "all" | set == st)]; m <- merge(x, y, by = c("game_id", "set"), suffixes = c("", "0"))
  bo <- mkboot(paste(m$season, m$cutoff)); r <- rbind(bm(bo, m$ll - m$ll0), bm(bo, m$br - m$br0), bm(bo, abs(m$pred - m$actual) - abs(m$pred0 - m$actual)))
  data.table(split = sp, arm = a, games = st, metric = c("logloss", "brier", "mae"), delta = r[, 1], lo95 = r[, 2], hi95 = r[, 3]) }))))))
cat("\n== deltas vs C0 (block bootstrap; negative = better) ==\n"); print(dl, digits = 3); w(dl, "s3_deltas_vs_C0.csv")
# FBS-vs-FBS slices and seasons for the key arms
tbk <- merge(G[, .(game_id, gpb, s_p4, site)], LG[arm %in% KEY], by = "game_id")[, ll := llf(pred, s, as.numeric(actual > 0))]
sl <- rbind(tbk[, .(slice = "season", level = as.character(season), n = .N, logloss = mean(ll), mae = mean(abs(pred - actual))), by = .(split, arm, season)][, season := NULL],
            tbk[, .(slice = "games played", n = .N, logloss = mean(ll), mae = mean(abs(pred - actual))), by = .(split, arm, level = as.character(gpb))])
w(sl, "s3_fbsfbs_slices.csv"); cat("\n== FBS-vs-FBS log-loss by season / games played (key arms) ==\n"); print(dcast(sl, split + slice + level ~ arm, value.var = "logloss"), digits = 4)
# FBS-vs-FCS detail for the key arms: by season, first vs later, FCS strength (C0 FCS-rating quintile), FBS strength
FK <- FCA[arm %in% KEY]; q0 <- FC[arm == "C0", .(game_id, qf = cut(frank(fcs_r) / .N, c(0, .2, .4, .6, .8, 1), labels = paste0("FCS Q", 1:5)), qb = cut(frank(fbs_r) / .N, c(0, .2, .4, .6, .8, 1), labels = paste0("FBS Q", 1:5))), by = split]
FK <- merge(FK, q0[, .(game_id, qf, qb)], by = "game_id")
fd <- rbind(FK[, .(slice = "season", level = as.character(season), n = .N, bias = mean(pred - actual), mae = mean(abs(pred - actual))), by = .(split, arm, season)][, season := NULL],
            FK[, .(slice = "game", n = .N, bias = mean(pred - actual), mae = mean(abs(pred - actual))), by = .(split, arm, level = fifelse(first, "first game", "later"))],
            FK[, .(slice = "FCS strength (C0 quintile)", n = .N, bias = mean(pred - actual), mae = mean(abs(pred - actual))), by = .(split, arm, level = as.character(qf))],
            FK[, .(slice = "FBS strength (C0 quintile)", n = .N, bias = mean(pred - actual), mae = mean(abs(pred - actual))), by = .(split, arm, level = as.character(qb))])
w(fd, "s3_fbsfcs_slices.csv"); cat("\n== FBS-vs-FCS bias by slice (key arms) ==\n"); print(dcast(fd, split + slice + level ~ arm, value.var = "bias"), digits = 3)
pdist <- FK[, as.list(quantile(pred, c(.05, .25, .5, .75, .95))), by = .(split, arm)]; w(pdist, "s3_fbsfcs_pred_distribution.csv")
# rating effects at each season's final cutoff
fin <- function(a) { e <- AR[[a]]$ent; e[, last := cutoff == max(cutoff), by = season]; e[last == TRUE] }
e0 <- fin("C0"); nfcs <- rbindlist(lapply(c2r_S, function(y) { g <- d$games[[as.character(y)]][final == TRUE]; ids <- fbs_ids(d$sch[[as.character(y)]])
  r <- rbind(g[, .(team_id = home_id, opp = away_id)], g[, .(team_id = away_id, opp = home_id)])[team_id %in% ids]; r[, .(season = y, n_fcs_opp = sum(!opp %in% ids), opps = list(opp)), by = team_id] }))
reff <- rbindlist(lapply(setdiff(KEY, "C0"), function(a) { if (grepl("^M", a)) return(NULL); e <- fin(a); m <- merge(e, e0[, .(season, team_id, p0 = power)], by = c("season", "team_id"))
  fc_ <- m[grp == "fcs"]; fb_ <- merge(m[fbs == TRUE], nfcs[, .(season, team_id, n_fcs_opp)], by = c("season", "team_id"))
  sos <- rbindlist(lapply(seq_len(nrow(nfcs)), function(i) { r <- nfcs[i]; pa <- e[season == r$season]; p0 <- e0[season == r$season]
    data.table(season = r$season, team_id = r$team_id, n_fcs_opp = r$n_fcs_opp, sos = mean(pa$power[match(r$opps[[1]], pa$team_id)]), sos0 = mean(p0$power[match(r$opps[[1]], p0$team_id)])) }))
  data.table(arm = a, split = c("dev", "cond"),
             fcs_mean = c(fc_[season %in% DEV, mean(power)], fc_[season >= 2023, mean(power)]), fcs_mean_C0 = c(fc_[season %in% DEV, mean(p0)], fc_[season >= 2023, mean(p0)]),
             fcs_sd = c(fc_[season %in% DEV, sd(power)], fc_[season >= 2023, sd(power)]), fcs_sd_C0 = c(fc_[season %in% DEV, sd(p0)], fc_[season >= 2023, sd(p0)]),
             fcs_rank_spearman_vs_C0 = c(fc_[season %in% DEV, cor(power, p0, method = "spearman"), by = season][, mean(V1)], fc_[season >= 2023, cor(power, p0, method = "spearman"), by = season][, mean(V1)]),
             lower_mean = c(m[fbs == FALSE & grp != "fcs" & season %in% DEV, mean(power)], m[fbs == FALSE & grp != "fcs" & season >= 2023, mean(power)]),
             fbs_sd_change = c(fb_[season %in% DEV, sd(power - p0)], fb_[season >= 2023, sd(power - p0)]),
             fbs_change_0fcs = c(fb_[season %in% DEV & n_fcs_opp == 0, mean(power - p0)], fb_[season >= 2023 & n_fcs_opp == 0, mean(power - p0)]),
             fbs_change_1fcs = c(fb_[season %in% DEV & n_fcs_opp == 1, mean(power - p0)], fb_[season >= 2023 & n_fcs_opp == 1, mean(power - p0)]),
             fbs_change_2fcs = c(fb_[season %in% DEV & n_fcs_opp >= 2, mean(power - p0)], fb_[season >= 2023 & n_fcs_opp >= 2, mean(power - p0)]),
             sos_change_0fcs = c(sos[season %in% DEV & n_fcs_opp == 0, mean(sos - sos0)], sos[season >= 2023 & n_fcs_opp == 0, mean(sos - sos0)]),
             sos_change_1plus = c(sos[season %in% DEV & n_fcs_opp >= 1, mean(sos - sos0)], sos[season >= 2023 & n_fcs_opp >= 1, mean(sos - sos0)]),
             sos_rank_spearman_vs_C0 = c(sos[season %in% DEV, cor(sos, sos0, method = "spearman"), by = season][, mean(V1)], sos[season >= 2023, cor(sos, sos0, method = "spearman"), by = season][, mean(V1)])) }))
cat("\n== rating effects at each season's final cutoff (vs C0) ==\n"); print(reff, digits = 3); w(reff, "s3_rating_effects.csv")
sim <- FCA[arm %in% KEY, .(n = .N, mean_pred_fbs_winprob = mean(clip(pnorm(pred / s))), actual_fbs_win = mean(actual > 0)), by = .(split, arm)]
cat("\n== simulation input: predicted FBS win probability vs FCS opponents ==\n"); print(sim, digits = 4); w(sim, "s3_sim_winprob.csv")
stab <- rbindlist(lapply(setdiff(KEY, grep("^M", KEY, value = TRUE)), function(a) { f <- AR[[a]]$ent[fbs == TRUE, .(season, cutoff, team_id, r = power)]; setorder(f, season, team_id, cutoff)
  f[, pr := shift(r), by = .(season, team_id)][!is.na(pr), .(arm = a, mean_abs_weekly_change = mean(abs(r - pr))), by = .(split = fifelse(season >= 2023, "cond", "dev"))] }))
w(stab, "s3_stability.csv"); cat("\n== FBS rating stability ==\n"); print(dcast(stab, arm ~ split, value.var = "mean_abs_weekly_change"), digits = 4)
lvl <- rbindlist(lapply(grep("^L_|^S\\d_on_L|^SR|^FLAT", KEY, value = TRUE), function(a) AR[[a]]$cuts[n_rows > 0][, .(arm = a, season, cutoff, n_link, level = fcs_level, dL)]))
if (nrow(lvl)) { lvl <- merge(lvl, snaps[, .(season, cutoff, wk = frank(ct)), by = season][, .(season, cutoff, wk)], by = c("season", "cutoff"))
  lw <- lvl[season %in% DEV, .(n_link = mean(n_link), fcs_level = mean(level, na.rm = TRUE)), by = .(arm, wk)][order(arm, wk)]; w(lw, "s3_inseason_level_by_week.csv")
  cat("\n== in-season FCS-division level by weekly cutoff (dev mean) ==\n"); print(dcast(lw[wk <= 16], wk ~ arm, value.var = "fcs_level"), digits = 3) }
