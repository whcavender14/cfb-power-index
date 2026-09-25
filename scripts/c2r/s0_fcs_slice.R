# C2 refinement research, Stage 0 (read-only probe). Run from the round15-power-rating worktree root: it reads that worktree's
# untracked caches (output/dev/round15/...) and never writes to them. Nothing here is fitted, scored or tuned.
suppressPackageStartupMessages({library(data.table); library(tibble)})
d <- readRDS("output/dev/round15/cand/data.rds")
f <- as.data.table(readRDS("output/dev/round15/prep/fcs_schedules_2013_2025.rds"))
cat("FCS schedule divisions:\n"); print(f[, .N, by = .(home_division, away_division)][order(-N)][1:10])
rat <- fread("output/dev/round15/eval/ratings_replay.csv", colClasses = list(character = "cutoff"))
snaps <- unique(rbindlist(lapply(d$base$snap, function(sn) data.table(season = sn$season, cutoff = format(sn$cutoff, "%Y-%m-%d"), ct = sn$cutoff))))
res <- rbindlist(lapply(c(2017:2019, 2021:2025), function(y) {
  g <- d$games[[as.character(y)]][final == TRUE & xor(home_fbs %in% TRUE, away_fbs %in% TRUE)]
  cs <- snaps[season == y][order(ct)]; g[, ci := findInterval(as.numeric(kickoff), as.numeric(cs$ct))]
  g[, fcs_id := fifelse(home_fbs %in% TRUE, away_id, home_id)]
  g[ci >= 1, cutoff := cs$cutoff[ci]]
  r <- rat[model == "C2" & season == y & fbs == FALSE, .(cutoff, fcs_id = team_id, has = TRUE)]
  g <- merge(g, r, by = c("cutoff", "fcs_id"), all.x = TRUE)
  # FCS team's games played before kickoff
  al <- d$games[[as.character(y)]][final == TRUE]; tg <- rbind(al[, .(team_id = home_id, available_at)], al[, .(team_id = away_id, available_at)])
  g[, fcs_gp := mapply(function(t, k) tg[team_id == t & available_at < k, .N], fcs_id, kickoff)]
  data.table(season = y, fbs_fcs_games = nrow(g), before_first_cutoff = sum(g$ci < 1), fcs_gp0 = sum(g$fcs_gp == 0), has_c2_rating = sum(g$has %in% TRUE),
             median_week_kick = as.character(median(as.Date(g$kickoff)))) }))
print(res); print(res[, lapply(.SD, sum), .SDcols = 2:5, by = .(split = fifelse(season >= 2023, "cond", "dev"))])
cat("first cutoffs:\n"); print(snaps[season %in% c(2019, 2024)][order(ct)][1:3])
