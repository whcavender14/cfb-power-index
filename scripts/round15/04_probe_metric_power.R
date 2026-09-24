# Round 15 design probe 04: how much signal each candidate metric carries, and how far the metrics can disagree.
# Uses only predictions that already exist and were already reported (no new model, no candidate):
#   - Round 13 dev file: Round 6-replay incumbent and frozen Round 13 K on 3,092 dev games (2018/19/21/22)
#   - Round 4 dev file: all 12 Round 4 candidates on 2,320 dev games (2019/21/22)
#   - end-of-season score ratings 2015-2025 (v4_history cache) for the spread of team strength
# 2023-2025 and 2026 are not read. Nothing here selects or tunes anything.
# Usage (repo root): Rscript scripts/round15/04_probe_metric_power.R
source("config/paths.R"); source("config/legacy_paths.R")
suppressPackageStartupMessages(library(data.table))
out <- "docs/round15/coverage"; set.seed(15015); B <- 2000L; SIG <- 16
r13 <- fread(path.expand("~/Desktop/Revised CFB Modeling/.claude/worktrees/round13-pbp-stack/output/dev/round13/predictions_dev.csv"),
             colClasses = list(character = c("game_id", "cutoff", "kickoff")))
r4 <- fread(file.path(LEGACY_ROOTS[["old"]], "archive/v5-round4/results/artifacts/development_predictions.csv"), colClasses = list(character = c("game_id", "cutoff")))

score <- function(p, y) {   # per-game losses (lower is better); p = predicted home margin, y = actual home margin
  pw <- pmin(pmax(pnorm(p / SIG), 1e-6), 1 - 1e-6); w <- as.numeric(y > 0)
  data.table(abs = abs(p - y), sq = (p - y)^2, logloss = -(w * log(pw) + (1 - w) * log(1 - pw)), brier = (pw - w)^2,
             miss = as.numeric(sign(p) != sign(y)))
}
metrics <- c("abs", "sq", "logloss", "brier", "miss")

# 1. Paired power: incumbent vs Round 13 K, flat season x week block bootstrap
d <- r13[, .(season, cutoff, gp, inc = incumbent_margin, k = pred_margin, y = actual_margin)][y != 0]
si <- score(d$inc, d$y); sk <- score(d$k, d$y); blk <- d[, paste(season, cutoff)]; ub <- unique(blk)
pw <- rbindlist(lapply(c("all", "gp0-3", "gp4+"), function(sl) {
  keep <- switch(sl, all = rep(TRUE, nrow(d)), `gp0-3` = d$gp <= 3, `gp4+` = d$gp >= 4)
  rbindlist(lapply(metrics, function(m) {
    diff <- (sk[[m]] - si[[m]])[keep]; b <- blk[keep]; bs <- split(diff, b); nb <- length(bs)
    reps <- vapply(seq_len(B), function(i) mean(unlist(bs[sample.int(nb, nb, TRUE)], use.names = FALSE)), 0)
    se <- sd(reps); data.table(slice = sl, metric = m, n = sum(keep), inc_level = mean(si[[m]][keep]), delta_K_minus_inc = mean(diff),
                               block_se = se, z = mean(diff) / se, mde80 = 2.8 * se, mde80_pct_of_level = 100 * 2.8 * se / mean(si[[m]][keep]))
  }))
}))
pw[, disagree_winner_games := c(all = sum(sign(d$inc) != sign(d$k)), `gp0-3` = d[gp <= 3, sum(sign(inc) != sign(k))], `gp4+` = d[gp >= 4, sum(sign(inc) != sign(k))])[slice]]
fwrite(pw, file.path(out, "metric_power_incumbent_vs_r13K_dev.csv"))

# 2. Do the metrics rank Round 4's 12 candidates the same way?
r4 <- r4[actual_margin != 0]
agg <- r4[, { s <- score(pred_margin, actual_margin); pr <- pred_margin - hfa * !neutral; ya <- actual_margin - hfa * !neutral
  list(n = .N, mae = mean(s$abs), rmse = sqrt(mean(s$sq)), logloss = mean(s$logloss), brier = mean(s$brier), winner_pct = 100 * (1 - mean(s$miss)),
       slope = unname(coef(lm(ya ~ pr))[2]), sd_pred = sd(pred_margin)) }, by = candidate][order(mae)]
fwrite(agg, file.path(out, "metric_agreement_round4_candidates_dev.csv"))
rk <- agg[, lapply(.SD, frank), .SDcols = c("mae", "rmse", "logloss", "brier")][, winner_pct := frank(-agg$winner_pct)]
ag <- as.data.table(cor(rk, method = "spearman"), keep.rownames = "metric")
fwrite(ag, file.path(out, "metric_rank_agreement_round4_candidates_dev.csv"))

# 3. Signal vs noise, model-free: per season, margin = HFA*site + a_home - a_away + e with a ~ N(0, tau^2), e ~ N(0, sigma^2),
#    fitted by REML on that season's FBS-vs-FBS results (no prior, no candidate). Seasons 2014-2019, 2021, 2022 only.
bak6 <- file.path(LEGACY_ROOTS[["backup"]], "CFB-Modeling-round6/outputs/round6/raw")
vc <- function(y) {
  f <- if (y >= 2015) file.path(PATHS$frozen, "cfb_data_v3", sprintf("raw_schedule_%d.rds", y)) else file.path(bak6, sprintf("raw_schedule_%d.rds", y))
  g <- as.data.table(readRDS(f))[home_division == "fbs" & away_division == "fbs" & is.finite(home_points) & is.finite(away_points)]
  g[, `:=`(t = as.POSIXct(substr(start_date, 1, 19), format = "%Y-%m-%dT%H:%M:%S", tz = "UTC"), m = home_points - away_points, site = as.numeric(!neutral_site))]
  tm <- sort(unique(c(g$home_id, g$away_id))); n <- nrow(g); X <- matrix(0, n, length(tm)); X[cbind(1:n, match(g$home_id, tm))] <- 1; X[cbind(1:n, match(g$away_id, tm))] <- -1
  Z <- cbind(g$site); XX <- tcrossprod(X)
  nll <- function(p) { V <- exp(2 * p[1]) * XX + diag(exp(2 * p[2]), n); R <- chol(V); Vi <- chol2inv(R)
    ZVZ <- crossprod(Z, Vi %*% Z); b <- solve(ZVZ, crossprod(Z, Vi %*% g$m)); r <- g$m - Z %*% b
    sum(log(diag(R))) + 0.5 * determinant(ZVZ)$modulus + 0.5 * drop(crossprod(r, Vi %*% r)) }
  o <- optim(c(log(12), log(15)), nll); tau <- exp(o$par[1]); sig <- exp(o$par[2])
  post_sd <- function(k) { keep <- rank(g$t, ties.method = "first") <= k; A <- crossprod(X[keep, , drop = FALSE]) / sig^2 + diag(1 / tau^2, length(tm))
    gp <- colSums(abs(X[keep, , drop = FALSE])); c(median(gp), sqrt(mean(diag(solve(A))))) }
  steps <- sapply(c(0.25, 0.5, 1), function(q) post_sd(round(q * n)))
  data.table(season = y, games = n, teams = length(tm), tau_true_sd = tau, sigma_game_noise = sig,
             gp_q25 = steps[1, 1], post_sd_q25 = steps[2, 1], gp_q50 = steps[1, 2], post_sd_q50 = steps[2, 2], gp_full = steps[1, 3], post_sd_full = steps[2, 3])
}
sp <- rbindlist(lapply(c(2014:2019, 2021, 2022), vc))
sim <- function(sd_true, se, n_team = 130, reps = 4000) {   # rank noise of an estimate with posterior SD `se`
  z <- replicate(reps, { t <- rnorm(n_team, 0, sd_true); o <- t + rnorm(n_team, 0, se); tr <- rank(-t); er <- rank(-o)
    top <- tr <= 25; c(mean(abs(er[top] - tr[top])), mean(er[tr <= 25] <= 25), mean(er[tr <= 12] <= 12), cor(t, o, method = "kendall")) })
  as.list(setNames(rowMeans(z), c("mean_abs_rank_error_true_top25", "share_true_top25_ranked_top25", "share_true_top12_ranked_top12", "kendall_tau_all")))
}
tau <- median(sp$tau_true_sd)
noise <- rbindlist(lapply(c("q25", "q50", "full"), function(k) { se <- median(sp[[paste0("post_sd_", k)]]); gp <- median(sp[[paste0("gp_", k)]])
  c(list(stage = k, median_games_played = gp, tau_true_sd = tau, sigma_game_noise = median(sp$sigma_game_noise), post_sd_no_prior = se,
         reliability = 1 - se^2 / tau^2), sim(tau, se)) }))
fwrite(sp, file.path(out, "strength_variance_components_by_season.csv")); fwrite(noise, file.path(out, "team_rating_noise.csv"))

print(pw, digits = 4); print(agg, digits = 4); print(ag, digits = 3); print(sp, digits = 3); print(noise, digits = 3)
