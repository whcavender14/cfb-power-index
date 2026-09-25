# C2 refinement research, Stage 1 (diagnosis only), part B: FCS calibration diagnosis from the part-A capture.
# Run from the round15-power-rating worktree root (reads its caches); writes tables to docs/c2r/stage1/ in c2-refinement.
# No correction is fitted, selected or applied. The one-parameter in-sample offsets in section 3 measure how the FCS error
# splits into level vs ordering; they are never applied to a prediction. The prior-pool counterfactuals in section 4 are
# exact linear attributions of C2's own system (Q is unchanged), not candidates.
# Sign convention everywhere: margins are FBS-oriented; bias = mean(predicted - actual). Negative bias = the FBS team won by
# more than predicted = the FCS team was rated too high (R15 reported the same sign, home-oriented).
suppressPackageStartupMessages({ source("config/paths.R"); source("config/production.R"); source(PATHS$model_ops); library(data.table)
  source("R/evaluation/evaluation_helpers.R"); source("R/round15/candidates/data.R") })
C2R <- "/Users/willcavender/Desktop/Revised CFB Modeling/.claude/worktrees/c2-refinement"
OUT <- file.path(C2R, "docs/c2r/stage1"); dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
w <- function(x, f) { fwrite(x, file.path(OUT, f)); invisible(x) }
options(width = 250, datatable.print.nrows = 200)
d <- r15_build_data(); x <- readRDS(file.path(C2R, "output/c2r/stage1/capture.rds")); dv <- readRDS(file.path(C2R, "output/c2r/stage1/divisions.rds"))
set.seed(15101L); NB <- 2000L
bci <- function(v, cl) { v <- as.numeric(v); ok <- is.finite(v); v <- v[ok]; cl <- cl[ok]; if (!length(v)) return(list(est = NA_real_, lo = NA_real_, hi = NA_real_))
  u <- unique(cl); ix <- split(seq_along(v), match(cl, u)); s <- vapply(ix, function(i) sum(v[i]), 0); k <- lengths(ix)
  bs <- replicate(NB, { j <- sample.int(length(u), replace = TRUE); sum(s[j]) / sum(k[j]) })
  list(est = mean(v), lo = unname(quantile(bs, .025)), hi = unname(quantile(bs, .975))) }
summ <- function(h, pred, by = NULL) {   # bias (pred - actual) with season x cutoff cluster bootstrap, MAE, n
  h <- copy(h); h[, p_ := get(pred)]; h <- h[is.finite(p_)]
  h[, { b <- bci(p_ - actual, paste(season, cutoff)); .(n = .N, bias = b$est, lo95 = b$lo, hi95 = b$hi, mae = mean(abs(p_ - actual))) }, by = by] }

# ============ 1. the FBS-vs-FCS evaluation set (every FBS-vs-non-FBS game after the season's first cutoff) ============
snaps <- unique(rbindlist(lapply(d$base$snap, function(sn) data.table(season = sn$season, cutoff = format(sn$cutoff, "%Y-%m-%d"), ct = sn$cutoff))))
snaps <- snaps[!duplicated(snaps[, .(season, cutoff)])]; setorder(snaps, season, ct); snaps[, wk := seq_len(.N), by = season]
Hs <- x$cuts[is.finite(H), .(H = H[1]), by = season]
S <- c(2017:2019, 2021:2025)
fc <- rbindlist(lapply(S, function(y) { g <- d$games[[as.character(y)]][final == TRUE & xor(home_fbs %in% TRUE, away_fbs %in% TRUE)]
  cs <- snaps[season == y]; g[, ci := findInterval(as.numeric(kickoff), as.numeric(cs$ct))]; g <- g[ci >= 1]
  g[, .(season, game_id, kickoff, neutral = as.logical(neutral), fbs_home = home_fbs %in% TRUE, fbs_id = fifelse(home_fbs %in% TRUE, home_id, away_id),
        fcs_id = fifelse(home_fbs %in% TRUE, away_id, home_id), actual = fifelse(home_fbs %in% TRUE, home_points - away_points, away_points - home_points),
        cutoff = cs$cutoff[ci], wk = cs$wk[ci])] }))
fc[, split := fifelse(season >= 2023, "cond", "dev")]; fc <- merge(fc, Hs, by = "season"); fc[, site := H * (!neutral) * fifelse(fbs_home, 1, -1)]
rr <- fread("output/dev/round15/eval/ratings_replay.csv", colClasses = list(character = "cutoff"))[model == "C2" & fbs == TRUE]
fc <- merge(fc, rr[, .(season, cutoff, fbs_id = team_id, fbs_r = rating)], by = c("season", "cutoff", "fbs_id"), all.x = TRUE); stopifnot(!anyNA(fc$fbs_r))
blk <- c("pts_ff", "pts_link", "pts_nn", "luck_ff", "luck_link", "hfa", "sr_ff", "sr_link", "prior_fbs", "prior_nonfbs")
ef <- x$ent[fbs == FALSE, c("season", "cutoff", "team_id", "power", "prior_power_c", "gp", "gp_vs_fbs", "free_power", "cf1", "cf2", blk), with = FALSE]
setnames(ef, c("team_id", "power", "prior_power_c", "gp", "gp_vs_fbs", "free_power", "cf1", "cf2"), c("fcs_id", "fcs_r", "fcs_prior_in", "fcs_gp", "fcs_gp_fbs", "fcs_free", "fcs_cf1", "fcs_cf2"))
fc <- merge(fc, ef, by = c("season", "cutoff", "fcs_id"), all.x = TRUE)
fp <- x$fcs_prior[, .(season, cutoff, fcs_id = team_id, div, fcs_prior = prior_power_c, d_prior_cf1, d_prior_cf2, in_solve)]
fc <- merge(fc, fp, by = c("season", "cutoff", "fcs_id"), all.x = TRUE); stopifnot(!anyNA(fc$fcs_prior))
stopifnot(all(fc$in_solve == is.finite(fc$fcs_r)), max(abs(fc$fcs_prior_in - fc$fcs_prior), na.rm = TRUE) < 1e-9)
fb <- x$ent[fbs == TRUE, .(season, cutoff, fbs_id = team_id, fbs_cf1 = cf1, fbs_cf2 = cf2, fbs_lvl = lvl_prior / 2)]
fc <- merge(fc, fb, by = c("season", "cutoff", "fbs_id"), all.x = TRUE)
fc[is.na(fcs_gp), `:=`(fcs_gp = 0L, fcs_gp_fbs = 0L)]
conf <- rbindlist(lapply(S, function(y) { s <- as.data.table(d$sch[[as.character(y)]]); unique(rbind(s[, .(season = y, team_id = home_id, conf = home_conference)], s[, .(season = y, team_id = away_id, conf = away_conference)]))[!duplicated(team_id)] }))
fc <- merge(fc, conf[, .(season, fbs_id = team_id, fbs_conf = conf)], by = c("season", "fbs_id"), all.x = TRUE)
fc[, fbs_tier := tier_of(fbs_conf, season)]; fc[fbs_tier == "Other", fbs_tier := "Independent"]
fc <- merge(fc, dv[, .(season, fcs_id = team_id, fcs_conf = conf)], by = c("season", "fcs_id"), all.x = TRUE)
cm <- x$cuts[, .(season, cutoff, pi_prior = pi_prior_fcsdiv, insample_link_resid)]; fc <- merge(fc, cm, by = c("season", "cutoff"), all.x = TRUE)
# predictions (FBS-oriented). C2 = frozen C2's own ratings; the prior-mean and flat -25 FCS values are references, not candidates.
fc[, `:=`(has = is.finite(fcs_r), c2 = fbs_r - fcs_r + site, prior_rule = fbs_r - fcs_prior + site, flat25 = fbs_r + 25 + site, u = fbs_r + site - actual)]
# tie-out to the Round 15 FBS-vs-FCS slice (home-oriented, games where C2 has an FCS rating)
ti <- fc[has == TRUE, .(n = .N, r15_bias_home_oriented = mean(fifelse(fbs_home, c2 - actual, actual - c2))), by = split]; print(ti)
stopifnot(ti[split == "dev", n] == 335L, abs(ti[split == "dev", r15_bias_home_oriented] - (-10.4960081882883)) < 1e-9,
          ti[split == "cond", n] == 212L, abs(ti[split == "cond", r15_bias_home_oriented] - (-11.3137710807295)) < 1e-9)
fc[, grp := fifelse(has, "rated (gp>=1)", "first game (gp=0)")]
cat("\n== 1. overview (FBS-oriented bias = pred - actual; negative = FCS rated too high) ==\n")
ov <- rbindlist(lapply(c("c2", "prior_rule", "flat25"), function(p) summ(fc, p, c("split", "grp"))[, pred := p]))
ov <- ov[!(pred == "c2" & grp == "first game (gp=0)")]; setcolorder(ov, c("split", "grp", "pred")); print(ov[order(split, grp, pred)], digits = 3); w(ov, "s1_overview.csv")
w(fc[, .N, by = .(split, fbs_home, neutral)][order(split)], "s1_site_counts.csv")

# ============ 2. decomposition of the predicted margin and of the FCS rating (rated games) ============
cat("\n== 2. decomposition (means over rated games) ==\n")
dec <- fc[has == TRUE, c(.(n = .N, actual = mean(actual), pred_c2 = mean(c2), bias = mean(c2 - actual), fbs_r = mean(fbs_r), site = mean(site), fcs_r = mean(fcs_r),
                          fcs_prior_mean = mean(fcs_prior), fcs_update = mean(fcs_r - fcs_prior), implied_fcs = mean(u), fcs_free_level = mean(fcs_free, na.rm = TRUE), n_free = sum(is.finite(fcs_free))),
                        lapply(.SD, mean)), by = split, .SDcols = blk]
print(dec, digits = 3); w(dec, "s1_decomposition.csv")
dec_s <- fc[has == TRUE, c(.(n = .N, bias = mean(c2 - actual), fcs_r = mean(fcs_r), fcs_prior_mean = mean(fcs_prior), implied_fcs = mean(u), pi_prior = mean(pi_prior),
                            insample_link_resid = mean(insample_link_resid)), lapply(.SD, mean)), by = season, .SDcols = blk]
w(dec_s, "s1_decomposition_by_season.csv")

# ============ 3. level vs ordering ============
cat("\n== 3a. FCS-wide offset implied by outcomes with C2's relative FCS ratings held fixed (= -bias), by season ==\n")
off <- fc[has == TRUE, { b <- bci(actual - c2, paste(season, cutoff)); .(n = .N, offset = b$est, lo95 = b$lo, hi95 = b$hi) }, by = .(split, season)]
off <- rbind(off, fc[has == TRUE, { b <- bci(actual - c2, paste(season, cutoff)); .(season = NA_integer_, n = .N, offset = b$est, lo95 = b$lo, hi95 = b$hi) }, by = split])
print(off, digits = 3); w(off, "s1_level_offset.csv")
# implied FCS power u = fbs_r + site - actual: regress on the C2 FCS rating centred within cutoff (FCS-division mean over rated entities)
cmean <- x$ent[fbs == FALSE][x$fcs_prior[div == "fcs", .(season, cutoff, team_id)], on = .(season, cutoff, team_id), nomatch = 0][, .(cm_r = mean(power), cm_p = mean(prior_power_c)), by = .(season, cutoff)]
fc <- merge(fc, cmean, by = c("season", "cutoff"), all.x = TRUE)
fc[, `:=`(rc = fcs_r - cm_r, pc = fcs_prior - cm_p, upd = fcs_r - fcs_prior)]
cat("\n== 3b. implied FCS power on C2's FCS rating: slope 1 = relative spread right; intercept shift = level ==\n")
reg <- rbindlist(lapply(c("dev", "cond"), function(sp) { h <- fc[has == TRUE & split == sp]
  f1 <- lm(u ~ fcs_r, h); f2 <- lm(u ~ rc, h); f3 <- lm(u ~ pc + I(fcs_r - fcs_prior), h); f4 <- lm(I(actual) ~ fbs_r + fcs_r + site, h)
  cf <- function(f, k) summary(f)$coefficients[k, 1:2]
  data.table(split = sp, n = nrow(h), slope_on_rating = cf(f1, 2)[1], se = cf(f1, 2)[2], slope_on_centred_rating = cf(f2, 2)[1], se_c = cf(f2, 2)[2],
             mean_u = mean(h$u), mean_rating = mean(h$fcs_r), slope_prior_part = cf(f3, 2)[1], se_p = cf(f3, 2)[2], slope_update_part = cf(f3, 3)[1], se_upd = cf(f3, 3)[2],
             free_coef_fbs = cf(f4, 2)[1], se_fbs = cf(f4, 2)[2], free_coef_fcs = cf(f4, 3)[1], se_fcs = cf(f4, 3)[2]) }))   # site ~ constant here (FBS home): not reported
print(reg, digits = 3); w(reg, "s1_level_vs_ordering_regression.csv")
cat("\n== 3c. ordering information: residual SD after removing each column's own in-sample mean (1 df each; measurement only) ==\n")
ordv <- fc[has == TRUE, .(n = .N, sd_u = sd(u), sd_after_c2 = sd(u - fcs_r), sd_after_prior = sd(u - fcs_prior), sd_after_flat = sd(u),
                          cor_c2 = cor(u, fcs_r), cor_prior = cor(u, fcs_prior), spearman_c2 = cor(u, fcs_r, method = "spearman"),
                          mae_c2_offset_removed = mean(abs(u - fcs_r - mean(u - fcs_r))), mae_flat_offset_removed = mean(abs(u - mean(u))),
                          sd_c2_rating = sd(fcs_r), sd_prior_rating = sd(fcs_prior)), by = split]
print(ordv, digits = 3); w(ordv, "s1_ordering_information.csv")
cat("\n== 3d. FCS-vs-FCS and FCS-vs-lower-division games (level-free test of relative ratings) ==\n")
ff <- rbindlist(lapply(S, function(y) { g <- d$games[[as.character(y)]][final == TRUE & !(home_fbs %in% TRUE) & !(away_fbs %in% TRUE)]
  cs <- snaps[season == y]; g[, ci := findInterval(as.numeric(kickoff), as.numeric(cs$ct))]; g <- g[ci >= 1]
  g[, .(season, game_id, neutral = as.logical(neutral), home_id, away_id, actual = home_points - away_points, cutoff = cs$cutoff[ci])] }))
ff <- merge(ff, Hs, by = "season"); ffr <- x$ent[fbs == FALSE, .(season, cutoff, team_id, power, prior_power_c)]
ff <- merge(ff, setnames(copy(ffr), c("team_id", "power", "prior_power_c"), c("home_id", "rh", "ph")), by = c("season", "cutoff", "home_id"))
ff <- merge(ff, setnames(copy(ffr), c("team_id", "power", "prior_power_c"), c("away_id", "ra", "pa")), by = c("season", "cutoff", "away_id"))
ff <- merge(ff, dv[, .(season, home_id = team_id, dh = div)], by = c("season", "home_id"), all.x = TRUE); ff <- merge(ff, dv[, .(season, away_id = team_id, da = div)], by = c("season", "away_id"), all.x = TRUE)
ff[is.na(dh), dh := "unknown"][is.na(da), da := "unknown"]
ff[, type := fifelse(dh == "fcs" & da == "fcs", "FCS vs FCS", fifelse(dh == "fcs" | da == "fcs", "FCS vs lower", "lower vs lower"))]
# orient mixed games to the FCS-division team
ff[, sgn := fifelse(type == "FCS vs lower" & da == "fcs", -1, 1)]
ff[, `:=`(split = fifelse(season >= 2023, "cond", "dev"), c2 = sgn * (rh - ra + H * !neutral), prior_rule = sgn * (ph - pa + H * !neutral), hfa_only = sgn * H * !neutral, actual = sgn * actual)]
ffs <- ff[, { f <- lm(actual ~ c2); fp_ <- lm(actual ~ prior_rule)
  .(n = .N, bias_c2 = mean(c2 - actual), mae_c2 = mean(abs(c2 - actual)), rmse_c2 = sqrt(mean((c2 - actual)^2)), calib_slope_c2 = coef(f)[2], cor_c2 = cor(c2, actual),
    mae_prior = mean(abs(prior_rule - actual)), calib_slope_prior = coef(fp_)[2], mae_hfa_only = mean(abs(hfa_only - actual)), sd_actual = sd(actual)) }, by = .(split, type)]
# reference: C2 on FBS-vs-FBS (frozen predictions, same seasons)
c2p <- fread(file.path(R15C$cache, "c2_predictions.csv"), colClasses = list(character = "game_id"))
fr <- merge(c2p[, .(game_id, pred_margin)], as.data.table(d$base$frame)[season %in% S, .(game_id, season, actual = actual_margin)], by = "game_id")
fr[, split := fifelse(season >= 2023, "cond", "dev")]
ffs <- rbind(ffs, fr[, { f <- lm(actual ~ pred_margin); .(type = "FBS vs FBS (reference)", n = .N, bias_c2 = mean(pred_margin - actual), mae_c2 = mean(abs(pred_margin - actual)),
  rmse_c2 = sqrt(mean((pred_margin - actual)^2)), calib_slope_c2 = coef(f)[2], cor_c2 = cor(pred_margin, actual), sd_actual = sd(actual)) }, by = split], fill = TRUE)
print(ffs[order(split, type)], digits = 3); w(ffs, "s1_fcs_internal_games.csv")
cat("\n== 3e. bias by quintile of C2's FCS rating (within split) ==\n")
fc[has == TRUE, q_fcs := cut(frank(fcs_r) / .N, c(0, .2, .4, .6, .8, 1), labels = paste0("Q", 1:5)), by = split]
qt <- summ(fc[has == TRUE], "c2", c("split", "q_fcs"))[, mean_fcs_r := fc[has == TRUE, mean(fcs_r), by = .(split, q_fcs)][.SD, on = .(split, q_fcs), V1]]
print(qt[order(split, q_fcs)], digits = 3); w(qt, "s1_bias_by_fcs_quintile.csv")
cat("\n== 3f. is one FCS-wide offset enough? conference heterogeneity of the FBS-vs-FCS error, and cross-conference FCS-vs-FCS games ==\n")
het <- rbindlist(lapply(c("dev", "cond"), function(sp) { h <- fc[has == TRUE & split == sp][, e := actual - c2]; h[, cf := fifelse(fcs_conf %in% h[, .N, by = fcs_conf][N >= 15, fcs_conf], fcs_conf, "other")]
  a <- anova(lm(e ~ 1, h), lm(e ~ cf, h)); data.table(split = sp, n = nrow(h), conferences = uniqueN(h$cf), F = a$F[2], p = a$`Pr(>F)`[2], sd_conf_means = sd(h[, mean(e), by = cf]$V1)) }))
print(het, digits = 3); w(het, "s1_conference_heterogeneity.csv")
ffc <- merge(ff[type == "FCS vs FCS"], dv[, .(season, home_id = team_id, ch = conf)], by = c("season", "home_id"))
ffc <- merge(ffc, dv[, .(season, away_id = team_id, ca = conf)], by = c("season", "away_id"))[!is.na(ch) & !is.na(ca) & ch != ca]
xc <- rbind(ffc[, .(split, cutoff, season, conf = ch, e = actual - c2)], ffc[, .(split, cutoff, season, conf = ca, e = c2 - actual)])   # e > 0: conf outperformed C2
xct <- xc[, { b <- bci(e, paste(season, cutoff)); .(n = .N, conf_outperformance = b$est, lo95 = b$lo, hi95 = b$hi) }, by = .(split, conf)][n >= 20][order(split, conf_outperformance)]
print(xct, digits = 3); w(xct, "s1_fcs_cross_conference.csv")

# ============ 4. prior composition (lower-division teams in the FCS pool) ============
cat("\n== 4a. FCS prior-mean pools by division (power = off - def; entity-seasons in the training window) ==\n")
pl <- copy(x$pools)[, power := off - def]; pls <- dcast(pl, key ~ pool, value.var = c("power", "n")); print(pls, digits = 3); w(pls, "s1_prior_pools.csv")
cat("\n== 4b. exact attribution: move the pool means by division (cf1: FCS-division teams use the FCS-only mean; cf2: every division its own mean) ==\n")
# change in the predicted FBS margin = change in FBS rating - change in FCS rating (rated games: exact solve response; gp=0 games: prior mean shift)
fc[, `:=`(d_pred_cf1 = fcoalesce(fbs_cf1, 0) - fifelse(has, fcs_cf1, d_prior_cf1), d_pred_cf2 = fcoalesce(fbs_cf2, 0) - fifelse(has, fcs_cf2, d_prior_cf2))]
cmp <- fc[, .(n = .N, bias_c2_or_prior = mean(fifelse(has, c2, prior_rule) - actual), mean_dfcs_cf1 = mean(fifelse(has, fcs_cf1, d_prior_cf1)), mean_dpred_cf1 = mean(d_pred_cf1),
              mean_dfcs_cf2 = mean(fifelse(has, fcs_cf2, d_prior_cf2)), mean_dpred_cf2 = mean(d_pred_cf2)), by = .(split, grp)]
print(cmp[order(split, grp)], digits = 3); w(cmp, "s1_prior_pool_attribution.csv")
lowd <- x$fcs_prior[in_solve == TRUE, .(nonfbs = .N, fcs = sum(div == "fcs"), ii = sum(div == "ii"), iii = sum(div == "iii"), unknown = sum(div == "unknown")), by = .(season, cutoff)][, .SD[.N], by = season]
nn <- rbindlist(lapply(S, function(y) { g <- d$games[[as.character(y)]][final == TRUE & !(home_fbs %in% TRUE) & !(away_fbs %in% TRUE)]
  g <- merge(g, dv[season == y, .(home_id = team_id, dh = div)], by = "home_id", all.x = TRUE); g <- merge(g, dv[season == y, .(away_id = team_id, da = div)], by = "away_id", all.x = TRUE)
  g[, .(season = y, nonfbs_games = .N, involving_lower = sum(!(dh %in% "fcs") | !(da %in% "fcs")))] }))
lowd <- merge(lowd, nn, by = "season"); print(lowd); w(lowd, "s1_lower_division_presence.csv")

# ============ 5. shrinkage toward the FBS-centred system ============
cat("\n== 5a. end-of-season fits (produce mu_FCS and last_eos): penalized vs free-level mean power by division ==\n")
eo <- merge(x$eos, dv[, .(season, team_id, div)], by = c("season", "team_id"), all.x = TRUE); eo[fbs == TRUE, div := "fbs"]; eo[is.na(div), div := "unknown"]
eos_t <- eo[fbs == FALSE, .(n = .N, penalized = mean(power), free_level = mean(free_power), pi_prior = mean(pi_prior)), by = .(season, div)]
eos_w <- dcast(eos_t[div %in% c("fcs", "ii")], season ~ div, value.var = c("n", "penalized", "free_level", "pi_prior"))
eos_w <- merge(eos_w, unique(eo[, .(season, n_link, insample_link_resid)]), by = "season"); print(eos_w, digits = 3); w(eos_w, "s1_eos_level_shrinkage.csv")
cat("\n== 5b. in-season C2 (dev seasons): level share set by the prior, free-level gap, in-sample linking residual, by week ==\n")
ie <- x$ent[fbs == FALSE][x$fcs_prior[div == "fcs", .(season, cutoff, team_id)], on = .(season, cutoff, team_id), nomatch = 0][, .(free_gap = mean(free_power - power)), by = .(season, cutoff)]
cu <- merge(x$cuts[n_rows > 0], ie, by = c("season", "cutoff"), all.x = TRUE); cu <- merge(cu, snaps[, .(season, cutoff, wk)], by = c("season", "cutoff"))
wkt <- cu[season %in% R15C$dev, .(seasons = .N, n_fcsdiv = mean(n_fcsdiv), n_link_games = mean(n_link_games), n_nn_games = mean(n_nn_games), pi_prior = mean(pi_prior_fcsdiv),
                                   free_gap = mean(free_gap), insample_link_resid = mean(insample_link_resid)), by = wk][order(wk)]
print(wkt, digits = 3); w(cu[, .(season, cutoff, wk, n_rows, n_fcsdiv, n_nonfbs, n_link_games, n_nn_games, lamf_off, lamf_def, pi_prior_nonfbs, pi_prior_fcsdiv, pi_data_pts_fcsdiv,
                                  free_gap, insample_link_resid, mean_prior_fbs_power)], "s1_inseason_level_by_cutoff.csv")
cat("\n== 5c. level chain by season (rated games): eos shrinkage -> prior level -> in-season level -> outcome ==\n")
ch <- fc[has == TRUE, .(n = .N, prior_level = mean(fcs_prior), c2_level = mean(fcs_r), implied_level = mean(u), prior_err = mean(fcs_prior - u), c2_err = mean(fcs_r - u),
                        retained = mean(fcs_r - u) / mean(fcs_prior - u), pi_prior = mean(pi_prior), free_level = mean(fcs_free, na.rm = TRUE)), by = .(split, season)]
ch <- merge(ch, eos_w[, .(season = season + 1L, eos_prev_fcs_penalized = penalized_fcs, eos_prev_fcs_free = free_level_fcs)], by = "season", all.x = TRUE)
print(ch, digits = 3); w(ch, "s1_level_chain.csv")

# ============ 6. first-game FCS matchups (no in-season C2 rating) ============
cat("\n== 6. first-game (gp=0) games: prior-mean rule vs flat -25 (C2's FBS rating either way) ==\n")
lastok <- rbindlist(lapply(S, function(y) data.table(season = y, fcs_id = readRDS(file.path(R15C$cache, "c2_components.rds"))$eos_full[[as.character(y - 1L)]][fcs == TRUE, team_id], last_eos = TRUE)))
fc <- merge(fc, lastok, by = c("season", "fcs_id"), all.x = TRUE); fc[is.na(last_eos), last_eos := FALSE]
g0 <- rbind(summ(fc[grp == "first game (gp=0)"], "prior_rule", c("split", "div"))[, pred := "prior_rule"], summ(fc[grp == "first game (gp=0)"], "flat25", c("split", "div"))[, pred := "flat25"],
            summ(fc[grp == "first game (gp=0)"], "prior_rule", c("split", "last_eos"))[, pred := "prior_rule"], fill = TRUE)
print(g0, digits = 3); w(g0, "s1_first_game.csv")
g0w <- summ(fc[grp == "first game (gp=0)"], "prior_rule", c("split", "wk")); w(g0w, "s1_first_game_by_week.csv")

# ============ 7. bias slices (rated games unless stated) ============
cat("\n== 7. bias slices, C2 on rated games ==\n")
fc[, `:=`(gp_b = cut(fcs_gp, c(0, 1, 3, 6, Inf), labels = c("1", "2-3", "4-6", "7+")), fbsgp_b = fifelse(fcs_gp_fbs >= 1, "1+", "0"),
          site_b = fifelse(neutral, "neutral", fifelse(fbs_home, "FBS home", "FCS home")),
          pm_b = cut(c2, c(-Inf, 14, 28, 42, Inf), labels = c("<14", "14-28", "28-42", "42+")), wk_b = cut(wk, c(0, 2, 3, 5, Inf), labels = c("1-2", "3", "4-5", "6+")))]
fc[, q_fbs := cut(frank(fbs_r) / .N, c(0, .2, .4, .6, .8, 1), labels = paste0("Q", 1:5)), by = split]
sl <- rbindlist(lapply(c("season", "wk_b", "gp_b", "fbsgp_b", "q_fbs", "fbs_tier", "site_b", "pm_b", "div"), function(v) {
  s <- summ(fc[has == TRUE], "c2", c("split", v)); setnames(s, v, "level"); s[, slice := v][, level := as.character(level)] }))
setcolorder(sl, c("slice", "split", "level")); print(sl, digits = 3); w(sl, "s1_bias_slices.csv")
cfs <- summ(fc[has == TRUE], "c2", c("split", "fcs_conf"))[n >= 15][order(split, bias)]; print(cfs, digits = 3); w(cfs, "s1_bias_by_fcs_conference.csv")

# ============ 8. does the FCS level leak into FBS ratings? ============
cat("\n== 8. sensitivity of FBS ratings to the FCS block level (level moved through the FCS prior), by FBS team's games vs non-FBS ==\n")
lk <- x$ent[fbs == TRUE, .(season, cutoff, team_id, s = lvl_prior / 2, n_nonfbs_games = gp - gp_vs_fbs, pts_link)]
lk <- merge(lk, cu[, .(season, cutoff, wk)], by = c("season", "cutoff"))[, last := wk == max(wk), by = season]
lkt <- lk[last == TRUE & season %in% R15C$dev, .(team_seasons = .N, mean_s = mean(s), sd_s = sd(s), mean_pts_link_contrib = mean(pts_link)), by = n_nonfbs_games][order(n_nonfbs_games)]
print(lkt, digits = 3); w(lkt, "s1_fbs_leak.csv")
ffp <- merge(fr, as.data.table(d$base$frame)[, .(game_id, cutoff = format(cutoff, "%Y-%m-%d"), home_id, away_id)], by = "game_id")
ffp <- merge(ffp, lk[, .(season, cutoff, home_id = team_id, sh = s)], by = c("season", "cutoff", "home_id")); ffp <- merge(ffp, lk[, .(season, cutoff, away_id = team_id, sa = s)], by = c("season", "cutoff", "away_id"))
lkg <- ffp[, .(n = .N, mean_abs_dpred_per_point = mean(abs(sh - sa)), p90_abs = quantile(abs(sh - sa), .9), max_abs = max(abs(sh - sa))), by = split]
print(lkg, digits = 3); w(lkg, "s1_fbs_leak_game_sensitivity.csv")
saveRDS(fc, file.path(C2R, "output/c2r/stage1/eval_set.rds")); cat("\nStage 1 part B done\n")
