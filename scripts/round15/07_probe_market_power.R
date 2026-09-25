# Round 15 probe 07: size of model-market disagreement (edge) for the incumbent, to plan market-metric power.
# Reads incumbent predictions and market lines ONLY; no game outcome, ATS result or edge-vs-outcome relation is computed.
# Usage (repo root, after 05 and 06): Rscript scripts/round15/07_probe_market_power.R
source("config/paths.R"); suppressPackageStartupMessages(library(data.table))
inc_dev <- fread("output/dev/round15/incumbent_replay_2017_2022.csv", colClasses = list(character = "game_id"))[, .(season, game_id, m = pred_margin)]
inc_cond <- fread(PATHS$incumbent_cond, colClasses = list(character = "game_id"))
inc_cond <- inc_cond[, .(season, game_id, m = pred_margin)]
ln <- fread("output/dev/round15/market_lines_2017_2025.csv", colClasses = list(character = "game_id"))
d <- merge(rbind(inc_dev, inc_cond), ln[, .(game_id, open_home_spread, close_home_spread)], by = "game_id", all.x = TRUE)
d[, `:=`(split = fifelse(season <= 2022, "dev 2017-2022", "cond 2023-2025"), e_close = m + close_home_spread, e_open = m + open_home_spread,
         move = -(close_home_spread - open_home_spread))]
buck <- function(x) cut(abs(x), c(0, 1, 2, 3, 5, 7, Inf), right = FALSE, labels = c("0-1", "1-2", "2-3", "3-5", "5-7", "7+"))
s <- d[, .(games = .N, with_close = sum(is.finite(e_close)), with_open = sum(is.finite(e_open)),
           sd_edge_close = sd(e_close, na.rm = TRUE), sd_edge_open = sd(e_open, na.rm = TRUE), sd_move = sd(move, na.rm = TRUE)), by = split]
b <- d[is.finite(e_close), .N, by = .(split, bucket = buck(e_close))][order(split, bucket)][, share := round(N / sum(N), 3), by = split]
fwrite(s, "docs/round15/coverage/market_edge_spread_incumbent.csv"); fwrite(b, "docs/round15/coverage/market_edge_buckets_incumbent.csv")
print(s); print(dcast(b, bucket ~ split, value.var = "N"))
