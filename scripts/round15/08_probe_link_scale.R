# Round 15 probe 08: sensitivity of winner log-loss comparisons to the rating -> win-probability scale sigma.
# Uses only the incumbent and frozen Round 13 K development predictions (2018-2022), already examined in Round 13.
# No Round 15 candidate exists or is read. Usage: Rscript scripts/round15/08_probe_link_scale.R
suppressPackageStartupMessages(library(data.table)); set.seed(15015)
d <- fread(path.expand("~/Desktop/Revised CFB Modeling/.claude/worktrees/round13-pbp-stack/output/dev/round13/predictions_dev.csv"),
           colClasses = list(character = c("game_id", "cutoff")))[actual_margin != 0]
d[, w := as.numeric(actual_margin > 0)]
ll <- function(m, s) { p <- pmin(pmax(pnorm(m / s), 1e-6), 1 - 1e-6); -(d$w * log(p) + (1 - d$w) * log(1 - p)) }
blk <- split(seq_len(nrow(d)), d[, paste(season, cutoff)]); nb <- length(blk)
se <- function(x) sd(replicate(2000, mean(x[unlist(blk[sample.int(nb, nb, TRUE)])])))
grid <- rbindlist(lapply(c(12, 13, 14, 15, 16, 17, 18, 20), function(s) { x <- ll(d$pred_margin, s) - ll(d$incumbent_margin, s)
  data.table(sigma = s, ll_inc = mean(ll(d$incumbent_margin, s)), ll_k = mean(ll(d$pred_margin, s)), delta = mean(x), se = se(x)) }))
mle <- function(m, idx) optimize(function(s) { p <- pmin(pmax(pnorm(m[idx] / s), 1e-6), 1 - 1e-6); -sum(d$w[idx] * log(p) + (1 - d$w[idx]) * log(1 - p)) }, c(5, 40))$minimum
fit <- data.table(model = c("incumbent", "K"), sigma_mle_all = c(mle(d$incumbent_margin, seq_len(nrow(d))), mle(d$pred_margin, seq_len(nrow(d)))),
                  rmse = c(sqrt(mean((d$incumbent_margin - d$actual_margin)^2)), sqrt(mean((d$pred_margin - d$actual_margin)^2))))
# leave-one-season-out, model-specific sigma (proposed method)
lo <- rbindlist(lapply(unique(d$season), function(y) { tr <- which(d$season != y)
  data.table(season = y, s_inc = mle(d$incumbent_margin, tr), s_k = mle(d$pred_margin, tr)) }))
d <- merge(d, lo, by = "season"); blk <- split(seq_len(nrow(d)), d[, paste(season, cutoff)]); nb <- length(blk)
pl <- function(m, s) { p <- pmin(pmax(pnorm(m / s), 1e-6), 1 - 1e-6); -(d$w * log(p) + (1 - d$w) * log(1 - p)) }
x <- pl(d$pred_margin, d$s_k) - pl(d$incumbent_margin, d$s_inc)
loso <- data.table(method = "LOSO model-specific sigma", delta = mean(x), se = se(x))
auc <- function(m) { r <- rank(m); n1 <- sum(d$w); (sum(r[d$w == 1]) - n1 * (n1 + 1) / 2) / (n1 * (nrow(d) - n1)) }
fwrite(grid, "docs/round15/coverage/link_scale_sensitivity_inc_vs_K.csv"); fwrite(rbind(fit, fill = TRUE), "docs/round15/coverage/link_scale_mle.csv")
fwrite(lo, "docs/round15/coverage/link_scale_loso_by_season.csv"); fwrite(loso, "docs/round15/coverage/link_scale_loso_delta.csv")
print(grid, digits = 4); print(fit, digits = 4); print(lo, digits = 4); print(loso, digits = 4); cat("AUC inc", auc(d$incumbent_margin), "K", auc(d$pred_margin), "\n")
