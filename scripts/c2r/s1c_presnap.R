# C2 refinement research, Stage 1 (diagnosis only), part C: pre-snap score margins in FBS-vs-FCS vs FBS-vs-FBS games,
# flagged as input for Stage 2 (garbage time). Nothing is refiltered or refit: the frozen Round 13 instrument is run with its
# own rules, and plays it drops as "garbage_or_overtime" are reported next to the plays it keeps.
# Run from the round15-power-rating worktree root; writes tables to docs/c2r/stage1/ in c2-refinement.
suppressPackageStartupMessages({ source("config/paths.R"); library(data.table); source("R/round15/prep/fumble_parser.R"); source("R/round15/prep/sr_history.R") })
C2R <- "/Users/willcavender/Desktop/Revised CFB Modeling/.claude/worktrees/c2-refinement"; OUT <- file.path(C2R, "docs/c2r/stage1")
raw6 <- "/Users/willcavender/Desktop/CFB Modeling Backup/CFB-Modeling-round6/outputs/round6/raw"
options(width = 250)
pl <- rbindlist(lapply(c(2017:2019, 2021:2025), function(y) {
  e <- r15_r13_env(); g <- e$r13_schedule(as.data.frame(readRDS(file.path(PATHS$frozen, "cfb_data_v3", sprintf("raw_schedule_%d.rds", y)))))
  raw <- e$r13_read_plays(file.path(raw6, sprintf("plays_%d.rds", y))); raw[, game_id := as.character(game_id)]; raw <- raw[game_id %in% g$game_id]
  st <- e$r13_states(r15_recover_fumbles(raw, e), g); el <- e$r13_eligible(st); stopifnot(identical(el$audit$play_id, st$play_id))
  x <- st[, .(season = y, game_id, offense, home, period, margin, down, distance, gained = yards_gained)][, reason := el$audit$reason]
  x <- x[reason %in% c("eligible", "garbage_or_overtime", "incomplete_game_exposure")]   # scrimmage plays that pass every non-garbage rule
  j <- match(x$game_id, g$game_id); hf <- g$home_fbs[j]; af <- g$away_fbs[j]
  x[, type := fifelse(hf & af, "FBS-FBS", fifelse(hf | af, "FBS-FCS", "FCS-FCS"))]
  x[, off_fbs := fifelse(offense == home, hf, af)]
  x[, success := as.numeric(gained >= distance * c(.5, .7, 1, 1)[pmin(pmax(down, 1), 4)])]
  message("plays ", y); x[type != "FCS-FCS"] }))
pl[, `:=`(split = fifelse(season >= 2023, "cond", "dev"), q = fifelse(period %in% 1:4, paste0("Q", period), "OT"), dropped = reason == "garbage_or_overtime",
          band = cut(abs(margin), c(-Inf, 8, 16, 22, 28, 38, Inf), labels = c("0-8", "9-16", "17-22", "23-28", "29-38", "39+")))]
cat("== share of scrimmage plays dropped by the frozen filter (Q2 >38, Q3 >28, Q4 >22, OT always) ==\n")
a <- pl[, .(scrimmage_plays = .N, dropped_share = mean(dropped)), by = .(split, type)][order(split, type)]; print(a, digits = 3)
fwrite(a, file.path(OUT, "s1_presnap_dropped_share.csv"))
cat("\n== pre-snap |margin| distribution by quarter (share of the type's scrimmage plays in that quarter) ==\n")
b <- pl[split == "dev", .N, by = .(type, q, band)][, share := N / sum(N), by = .(type, q)]
bw <- dcast(b, type + q ~ band, value.var = "share", fill = 0); print(bw, digits = 2); fwrite(bw, file.path(OUT, "s1_presnap_margin_by_quarter_dev.csv"))
cat("\n== kept plays only: share with |margin| > 21 (blowout-range plays the current thresholds keep), by quarter ==\n")
k <- pl[dropped == FALSE, .(kept = .N, over21 = mean(abs(margin) > 21), over28 = mean(abs(margin) > 28)), by = .(split, type, q)][order(split, type, q)]
print(k, digits = 3); fwrite(k, file.path(OUT, "s1_presnap_kept_blowout_share.csv"))
cat("\n== success rate by |margin| band, FBS-vs-FCS games, dev (descriptive flag for Stage 2; includes dropped plays) ==\n")
sr <- pl[type == "FBS-FCS" & split == "dev" & q != "OT", .(plays = .N, sr = mean(success), dropped = mean(dropped)), by = .(side = fifelse(off_fbs, "FBS offense", "FCS offense"), band)][order(side, band)]
print(sr, digits = 3); fwrite(sr, file.path(OUT, "s1_presnap_sr_by_band_fbsfcs_dev.csv"))
