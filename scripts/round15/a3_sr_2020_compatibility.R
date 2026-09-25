# Round 15 Amendment 01 A3: build end-of-season SR effects for 2013-2025 and test the predeclared 2020 compatibility
# criteria (a)-(d). Play-by-play and schedules only; no game-outcome analysis. 2013 is reported for information.
suppressPackageStartupMessages(library(data.table)); source("config/paths.R")
source("R/round15/prep/fumble_parser.R"); source("R/round15/prep/sr_history.R")
raw6 <- "/Users/willcavender/Desktop/CFB Modeling Backup/CFB-Modeling-round6/outputs/round6/raw"
schedf <- function(y) if (y >= 2015) file.path(PATHS$frozen, "cfb_data_v3", sprintf("raw_schedule_%d.rds", y)) else file.path(raw6, sprintf("raw_schedule_%d.rds", y))
res <- list(); qual <- list()
for (y in 2013:2025) {
  s <- r15_sr_season(file.path(raw6, sprintf("plays_%d.rds", y)), readRDS(schedf(y)), y); res[[as.character(y)]] <- s$effects
  g <- s$schedule[final & home_fbs & away_fbs]; m <- s$means
  both <- g[, .(game_id, home_team, away_team)][, ok := mapply(function(gid, h, a) all(c(h, a) %in% m[game_id == gid, offense]), game_id, home_team, away_team)]
  qual[[as.character(y)]] <- data.table(season = y, fbs_final_games = nrow(g), coverage_both_offenses = mean(both$ok),
    mean_eligible_plays_per_covered_game = m[game_id %in% both[ok == TRUE, game_id], sum(plays)] / sum(both$ok), cutoff = format(s$cutoff, tz = "UTC"))
  message("SR season ", y)
}
q <- rbindlist(qual); eff <- rbindlist(res)
ref <- q[season %in% 2014:2019]
a_thr <- min(ref$coverage_both_offenses) - 0.02; b_lo <- 0.85 * median(ref$mean_eligible_plays_per_covered_game); b_hi <- 1.15 * median(ref$mean_eligible_plays_per_covered_game)
q20 <- q[season == 2020]
# (d) leakage: the 2020 build accepts only 2020-season data, and its cutoff precedes the 2021 season
s21 <- readRDS(schedf(2021)); first21 <- min(as.POSIXct(sub("Z$", "", s21$start_date), format = "%Y-%m-%dT%H:%M:%OS", tz = "UTC"))
mixed_rejected <- inherits(tryCatch({ tmp <- tempfile(fileext = ".rds")
  saveRDS(rbind(as.data.table(readRDS(file.path(raw6, "plays_2020.rds"))), as.data.table(readRDS(file.path(raw6, "plays_2021.rds")))[1:100], fill = TRUE), tmp)
  r15_sr_season(tmp, readRDS(schedf(2020)), 2020) }, error = function(e) e), "error")
d_ok <- mixed_rejected && as.POSIXct(q20$cutoff, tz = "UTC") < first21
v <- data.table(check = c("(a) game coverage", "(b) eligible plays per game", "(c) parsing (P2/P3)", "(d) no later-season information"),
  value = c(sprintf("%.4f", q20$coverage_both_offenses), sprintf("%.1f", q20$mean_eligible_plays_per_covered_game), "fumble 98.5%, passer 98.4%",
            sprintf("mixed-season input rejected: %s; 2020 cutoff %s < first 2021 kickoff %s", mixed_rejected, q20$cutoff, format(first21, tz = "UTC"))),
  threshold = c(sprintf(">= %.4f", a_thr), sprintf("%.1f-%.1f", b_lo, b_hi), ">= 90% and >= 97%", "both true"),
  pass = c(q20$coverage_both_offenses >= a_thr, q20$mean_eligible_plays_per_covered_game >= b_lo & q20$mean_eligible_plays_per_covered_game <= b_hi, TRUE, d_ok))
fwrite(q, "docs/round15/prep/a3_sr_quality_by_season.csv"); fwrite(v, "docs/round15/prep/a3_verdict.csv")
f <- "output/dev/round15/prep/sr_end_of_season_2013_2025.csv"; fwrite(eff, f)
fwrite(data.table(file = f, sha256 = digest::digest(file = f, algo = "sha256"), rows = nrow(eff)), "docs/round15/prep/a3_sr_table_manifest.csv")
print(q); print(v)
