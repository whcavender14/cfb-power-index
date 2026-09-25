# Round 15 probe 06: market-line coverage for 2017-2025 (EVALUATION-ONLY data; never a model input).
# Pulls CFBD /lines for regular + postseason 2017-2025 (18 calls, cached in the git-ignored output/dev/round15/market_raw/),
# builds per-game opening and closing lines (R/round15/market_lines.R), and reports coverage, book counts, line movement and
# consistency checks. Scores are dropped on read; no ATS result, edge or model prediction is computed here.
# Usage (repo root): Rscript scripts/round15/06_probe_market_lines.R
source("config/paths.R"); source("R/round15/cfbd_client.R"); source("R/round15/market_lines.R")
raw_dir <- "output/dev/round15/market_raw"; out <- "docs/round15/coverage"
cl <- cfbd_client(raw_dir, max_calls = 20L)
Y <- 2017:2025
q <- rbindlist(lapply(Y, function(y) rbindlist(lapply(c("regular", "postseason"), function(st)
  r15_line_quotes(cl$get("/lines", list(year = y, seasonType = st)))), fill = TRUE)), fill = TRUE)
gl <- r15_game_lines(q)
fwrite(gl, "output/dev/round15/market_lines_2017_2025.csv")

bak6 <- "/Users/willcavender/Desktop/CFB Modeling Backup/CFB-Modeling-round6/outputs/round6/raw"
univ <- rbindlist(lapply(Y, function(y) { g <- as.data.table(readRDS(file.path(PATHS$frozen, "cfb_data_v3", sprintf("raw_schedule_%d.rds", y))))
  g[home_division == "fbs" & away_division == "fbs" & is.finite(home_points) & is.finite(away_points), .(season = y, game_id = as.character(game_id))] }))
u <- merge(univ, gl, by = c("game_id", "season"), all.x = TRUE)
cov <- u[, .(fbs_games = .N, with_close = sum(is.finite(close_home_spread)), with_open = sum(is.finite(open_home_spread)),
             with_both = sum(is.finite(open_home_spread) & is.finite(close_home_spread)),
             median_close_books = as.numeric(median(close_books, na.rm = TRUE)), median_open_books = as.numeric(median(open_books, na.rm = TRUE)),
             share_moved_ge_0.5 = mean(abs(close_home_spread - open_home_spread) >= 0.5, na.rm = TRUE),
             median_abs_move = median(abs(close_home_spread - open_home_spread), na.rm = TRUE),
             p90_abs_move = as.numeric(quantile(abs(close_home_spread - open_home_spread), 0.9, na.rm = TRUE)),
             open_close_sign_agree_abs_close_ge3 = mean(sign(open_home_spread) == sign(close_home_spread) & abs(close_home_spread) >= 3, na.rm = TRUE) /
               mean(abs(close_home_spread) >= 3 & is.finite(open_home_spread), na.rm = TRUE)), by = season][order(season)]
cov[, `:=`(close_share = round(with_close / fbs_games, 3), open_share = round(with_open / fbs_games, 3), both_share = round(with_both / fbs_games, 3))]
prov <- q[valid & !conflict & game_id %in% univ$game_id, .(games = uniqueN(game_id), with_opener = uniqueN(game_id[is.finite(open_q)])), by = .(season, provider)][order(season, -games)]

held <- as.data.table(readRDS(PATHS$market_lines))[, .(game_id = as.character(game_id), held_close = home_spread)]
x <- merge(gl[season >= 2023], held, by = "game_id")
chk <- data.table(check = c("2023-25 games in both fresh and held closing file", "fresh close within 0.5 of held close", "fresh close identical to held close"),
                  value = c(nrow(x), mean(abs(x$close_home_spread - x$held_close) <= 0.5), mean(abs(x$close_home_spread - x$held_close) < 1e-9)))
qa <- q[, .(quote_rows = .N, valid_rows = sum(valid), conflict_rows = sum(conflict)), by = season][order(season)]

fwrite(cov, file.path(out, "market_line_coverage.csv")); fwrite(prov, file.path(out, "market_line_providers.csv"))
fwrite(chk, file.path(out, "market_line_crosscheck_2023_2025.csv")); fwrite(qa, file.path(out, "market_line_quote_audit.csv"))
fwrite(cbind(cl$log(), calls_this_run = cl$calls()), file.path(out, "market_probe_calls.csv"))
print(cov, width = 250); print(chk); print(qa); print(prov[, .SD[1:6], by = season], nrows = 80)
