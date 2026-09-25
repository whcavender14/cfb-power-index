# C2 refinement research, Stage 4A/4B (diagnosis, before any Stage 4 candidate is defined): how the C2L preseason prior works,
# how much of each FBS rating it still determines by games played, and how well-scaled gp = 0 predictions are.
# Baseline C2L = Stage 3 L_last_n20. Run from the round15-power-rating worktree root.
source("config/paths.R"); source("config/production.R")
suppressPackageStartupMessages({ source(PATHS$model_ops); library(data.table); source("R/evaluation/evaluation_helpers.R"); for (f in c("data", "c1", "c2")) source(sprintf("R/round15/candidates/%s.R", f)) })
source("/Users/willcavender/Desktop/Revised CFB Modeling/.claude/worktrees/c2-refinement/scripts/c2r/lib_c2r.R"); source(file.path(C2R, "scripts/c2r/lib_s3.R"))
out <- file.path(C2R, "output/c2r/stage4"); dir.create(file.path(out, "arms"), recursive = TRUE, showWarnings = FALSE); OUT <- file.path(C2R, "docs/c2r/stage4"); dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
w <- function(x, f) { fwrite(x, file.path(OUT, f)); invisible(x) }; options(width = 250, datatable.print.nrows = 200)
d <- r15_build_data(); dv <- readRDS(file.path(C2R, "output/c2r/stage1/divisions.rds"))
c1 <- readRDS(file.path(R15C$cache, "c1_components.rds")); c2 <- readRDS(file.path(R15C$cache, "c2_components.rds"))
an <- readRDS(file.path(C2R, "output/c2r/stage3/level_history.rds"))$anchors[anchor == "last", .(season, fcs, gap)]
L3 <- readRDS(file.path(C2R, "output/c2r/stage3/arms/L_last_n20.rds")); base <- modifyList(s3_opt(), L3$opt)
cap <- s3_capture_all(d, c1, c2, dv, modifyList(base, list(influence = TRUE)), an)
m <- merge(cap$pred, L3$pred[, .(game_id, r = pred_margin)], by = "game_id"); stopifnot(nrow(m) == nrow(L3$pred), max(abs(m$pred_margin - m$r)) < 1e-9)
cap$opt <- base; cap$name <- "C2L"; saveRDS(cap, file.path(out, "arms", "C2L.rds")); message("C2L reproduces Stage 3 L_last_n20")

# ================= 4A: the mechanism =================
pr <- rbindlist(lapply(c2r_S, function(y) { k <- keyof(y); A <- c2r_args(d, c1, c2, y)
  data.table(season = y, pkey = k, scale_a = A$a, lambda0 = A$lambda0, lam_off_mean = mean(A$lam$off), lam_off_p10 = quantile(A$lam$off, .1), lam_off_p90 = quantile(A$lam$off, .9),
             lam_def_mean = mean(A$lam$def), lam_def_p10 = quantile(A$lam$def, .1), lam_def_p90 = quantile(A$lam$def, .9), omega = A$omega,
             b_off = c1$varm[[as.character(k)]]$off$b, b_def = c1$varm[[as.character(k)]]$def$b,
             prior_power_sd = sd(A$a * (A$prior$pre_off - A$prior$pre_def))) }))
cat("== 4A. prior mechanics by season (scale a multiplies the C1 prior mean; lambda_i = lambda0 exp(-b (u_i - ubar)) per side) ==\n"); print(pr, digits = 3); w(pr, "s4a_prior_mechanics.csv")
inf <- cap$inf[, gpb := fifelse(gp >= 6, "6+", as.character(gp))][, split := fifelse(season >= 2023, "cond", "dev")]
it <- inf[, .(team_cutoffs = .N, own_prior_weight_power = mean(w_power), p10 = quantile(w_power, .1), p90 = quantile(w_power, .9), own_weight_off = mean(w_off), own_weight_def = mean(w_def),
              prior_variance_share = cov(power, prior_block) / var(power), lam_off = mean(lam_off), lam_def = mean(lam_def)), by = .(split, gpb)][order(split, gpb)]
cat("\n== 4A. effective preseason influence by games played (exact, from the solved system) ==\n"); print(it, digits = 3); w(it, "s4a_influence_by_gp.csv")

# ================= 4B: gp = 0 calibration =================
G <- as.data.table(d$base$frame)[season %in% c2r_S, .(season, game_id, cutoff_t = cutoff, cutoff = format(cutoff, "%Y-%m-%d"), neutral, home_id, away_id, home_conference, away_conference, gp_home_f = gp_home, gp_away_f = gp_away, actual = actual_margin)]
tg <- rbindlist(lapply(c2r_S, function(y) { g <- d$games[[as.character(y)]][final == TRUE]; rbind(g[, .(season = y, team_id = home_id, available_at)], g[, .(season = y, team_id = away_id, available_at)]) }))
gpat <- function(s, id, ct) tg[season == s & team_id == id & available_at < ct, .N]
G[, `:=`(gp_h = mapply(gpat, season, home_id, cutoff_t), gp_a = mapply(gpat, season, away_id, cutoff_t))]
G[, split := fifelse(season >= 2023, "cond", "dev")][, hfa := vapply(season, function(y) c2r_H(d, y), 0)][, site := hfa * (!as.logical(neutral))][, win := as.numeric(actual > 0)]
G <- merge(G, cap$pred[, .(game_id, C2L = pred_margin)], by = "game_id")
G <- merge(G, fread(file.path(R15C$cache, "c2_predictions.csv"), colClasses = list(character = "game_id"))[, .(game_id, C2 = pred_margin)], by = "game_id")
inc <- rbind(fread("output/dev/round15/incumbent_replay_2017_2022.csv", colClasses = list(character = "game_id"))[, .(game_id, I = pred_margin)],
             fread(PATHS$incumbent_cond, colClasses = list(character = "game_id"))[, .(game_id, I = pred_margin)])
G <- merge(G, inc, by = "game_id", all.x = TRUE); G[, s_p4 := p4_orientation(home_conference, away_conference, season)]
cat("\ngp definitions: frame gp (R15 slices) vs all-games gp (drives C2's solve): agreement", G[, mean(pmin(gp_home_f, gp_away_f) == pmin(gp_h, gp_a))], "\n")
G[, `:=`(gpmin = pmin(gp_h, gp_a), both0 = gp_h == 0 & gp_a == 0)]
fit_sigma <- function(m, y) { f <- function(s) -sum(y * pnorm(m / s, log.p = TRUE) + (1 - y) * pnorm(-m / s, log.p = TRUE)); optimize(f, c(2, 80), tol = 1e-10)$minimum }
for (x in c("C2L", "C2", "I")) { s <- numeric(nrow(G)); for (y in R15C$dev) { g <- G[split == "dev" & season != y]; s[G$season == y] <- fit_sigma(g[[x]], g$win) }
  s[G$split == "cond"] <- fit_sigma(G[split == "dev"][[x]], G[split == "dev"]$win); set(G, j = paste0("s_", x), value = s) }
met <- function(h, x) { m <- h[[x]]; ok <- is.finite(m); h <- h[ok]; m <- m[ok]; s <- h[[paste0("s_", x)]]; p <- pmin(pmax(pnorm(m / s), 1e-6), 1 - 1e-6)
  data.table(n = nrow(h), logloss = mean(-(h$win * log(p) + (1 - h$win) * log(1 - p))), brier = mean((p - h$win)^2), mae = mean(abs(m - h$actual)), rmse = sqrt(mean((m - h$actual)^2)),
             winners = mean(sign(m) == sign(h$actual)), bias = mean(m - h$actual), calib_slope = unname(coef(lm(I(h$actual - h$site) ~ I(m - h$site)))[2]), pred_sd = sd(m),
             p4g5 = if (any(h$s_p4 != 0)) mean(((h$actual - m) * h$s_p4)[h$s_p4 != 0]) else NA_real_) }
g0 <- rbindlist(lapply(c("dev", "cond"), function(sp) rbindlist(lapply(c("C2L", "C2", "I"), function(x) rbind(
  cbind(data.table(split = sp, model = x, set = "min gp = 0"), met(G[split == sp & gpmin == 0], x)),
  cbind(data.table(split = sp, model = x, set = "both gp = 0 (pure prior)"), met(G[split == sp & both0 == TRUE], x)),
  cbind(data.table(split = sp, model = x, set = "all"), met(G[split == sp], x)))))))
cat("\n== 4B. gp = 0 calibration ==\n"); print(g0, digits = 4); w(g0, "s4b_gp0_calibration.csv")
# calibration by |predicted margin| (net of home field), oriented to the predicted favourite, pure-prior games and min-gp-0 games
bk <- c(0, 7, 14, 21, 28, Inf); bl <- c("0-7", "7-14", "14-21", "21-28", "28+")
cb <- rbindlist(lapply(c("both gp = 0", "min gp = 0", "gp 1-3", "gp 4+"), function(st) { h <- switch(st, "both gp = 0" = G[both0 == TRUE], "min gp = 0" = G[gpmin == 0], "gp 1-3" = G[gpmin %in% 1:3], "gp 4+" = G[gpmin >= 4])
  h[, `:=`(o = sign(C2L - site + 1e-9), pm = abs(C2L - site))][, .(n = .N, mean_pred_net = mean(pm), mean_actual_net = mean(o * (actual - site)), ratio = mean(o * (actual - site)) / mean(pm)),
    by = .(split, bucket = cut(pm, bk, labels = bl, right = FALSE))][, set := st][order(split, bucket)] }))
cat("\n== 4B. calibration by |predicted margin net of HFA| (favourite-oriented; ratio < 1 = predictions too extreme) ==\n"); print(cb, digits = 3); w(cb, "s4b_calibration_by_margin.csv")
# offense vs defense components of the pure-prior prediction
pp <- rbindlist(lapply(c2r_S, function(y) { A <- c2r_args(d, c1, c2, y); data.table(season = y, team_id = A$prior$team_id, po = A$a * A$prior$pre_off, pd = A$a * A$prior$pre_def) }))
h <- merge(G[both0 == TRUE], pp[, .(season, home_id = team_id, poh = po, pdh = pd)], by = c("season", "home_id")); h <- merge(h, pp[, .(season, away_id = team_id, poa = po, pda = pd)], by = c("season", "away_id"))
od <- h[, { f <- lm(I(actual - site) ~ I(poh - poa) + I(pda - pdh)); s_ <- summary(f)$coefficients
  .(n = .N, coef_offense = s_[2, 1], se_off = s_[2, 2], coef_defense = s_[3, 1], se_def = s_[3, 2], intercept = s_[1, 1]) }, by = split]
cat("\n== 4B. pure-prior games: margin on the offense and defense parts of the prior difference (1 = correctly scaled) ==\n"); print(od, digits = 3); w(od, "s4b_offense_defense_scale.csv")
saveRDS(G, file.path(out, "G_frame.rds"))
