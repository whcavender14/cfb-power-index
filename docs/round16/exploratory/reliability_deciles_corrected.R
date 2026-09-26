# EXPLORATORY (post-run, no decision power): corrected reliability table. The frozen scorer's report-only
# reliability_deciles.csv took mean(p) over the whole universe instead of within each decile (a grouping bug; the
# win_rate column and every gate are unaffected). This recomputes mean predicted probability per decile with the
# frozen sigma.csv and the same predictions and outcomes. It does not modify docs/round16/results.
suppressPackageStartupMessages({ source("config/paths.R"); library(data.table) })
rd <- function(f) fread(f, colClasses = list(character = c("game_id", "cutoff")))
cols <- c("season", "game_id", "actual_margin", "pred_margin")
G <- rbind(rd("output/dev/round15/incumbent_replay_2017_2022.csv")[, ..cols][, split := "dev"], rd(PATHS$incumbent_cond)[, ..cols][, split := "cond"])
setnames(G, c("actual_margin", "pred_margin"), c("actual", "I"))
G <- merge(G, rd("output/c2/current/c2_predictions.csv")[, .(game_id, C = pred_margin)], by = "game_id"); G[, win := as.numeric(actual > 0)]
sig <- fread("docs/round16/results/sigma.csv")
out <- rbindlist(lapply(c("I", "C"), function(x) { s <- ifelse(G$split == "dev", sig[model == x & split == "dev"]$sigma[match(G$season, sig[model == x & split == "dev"]$season)], sig[model == x & split == "cond", sigma])
  p <- pmin(pmax(pnorm(G[[x]] / s), 1e-6), 1 - 1e-6); h <- data.table(split = G$split, p = p, win = G$win)
  h[, decile := cut(p, quantile(p, 0:10 / 10), include.lowest = TRUE, labels = 1:10), by = split][, .(model = x, n = .N, mean_p = mean(p), win_rate = mean(win), gap = mean(win) - mean(p)), by = .(split, decile)] }))
setorder(out, split, model, decile); fwrite(out, "docs/round16/exploratory/reliability_deciles_corrected.csv")
print(dcast(out, split + decile ~ model, value.var = c("mean_p", "win_rate")), digits = 3)
print(out[, .(max_abs_gap = max(abs(gap)), mean_abs_gap = mean(abs(gap))), by = .(split, model)], digits = 3)
