# C2 refinement research, Stage 0 (read-only probe). Run from the round15-power-rating worktree root: it reads that worktree's
# untracked caches (output/dev/round15/...) and never writes to them. Nothing here is fitted, scored or tuned.
suppressPackageStartupMessages({library(data.table); library(tibble)})
d <- readRDS("output/dev/round15/cand/data.rds")
cat("data.rds elements:", names(d), "\n")
raw6 <- "/Users/willcavender/Desktop/CFB Modeling Backup/CFB-Modeling-round6/outputs/round6/raw"
typ <- function(h, a) fifelse(h & a, "FBS-FBS", fifelse(h | a, "FBS-FCS", "FCS-FCS"))
out <- rbindlist(lapply(2014:2025, function(y) {
  g <- d$games[[as.character(y)]][final == TRUE]; g[, type := typ(home_fbs %in% TRUE, away_fbs %in% TRUE)]
  p <- as.data.table(readRDS(file.path(raw6, sprintf("plays_%d.rds", y))))[, .(game_id = as.character(game_id), period, clock_minutes, clock_seconds, offense_score, defense_score)]
  pg <- p[, .(plays = .N, na_clock = mean(is.na(clock_minutes) | is.na(clock_seconds)), na_score = mean(is.na(offense_score) | is.na(defense_score)), na_period = mean(is.na(period))), by = game_id]
  sr <- unique(d$pbp[season == y & !is.na(sr), .(game_id)])[, has_sr := TRUE]
  g <- merge(g, pg, by.x = as.character("game_id"), by.y = "game_id", all.x = TRUE)[, game_id := as.character(game_id)]
  g <- merge(g, sr, by = "game_id", all.x = TRUE)
  g[, .(games = .N, with_plays = sum(!is.na(plays)), with_sr = sum(has_sr %in% TRUE), plays = sum(plays, na.rm = TRUE),
        na_clock = weighted.mean(na_clock, plays, na.rm = TRUE), na_score = weighted.mean(na_score, plays, na.rm = TRUE)), by = type][, season := y]
}))
print(dcast(out, season ~ type, value.var = "games")); cat("games with plays / with SR rows:\n")
print(out[, .(season, type, games, with_plays, with_sr, plays, na_clock = round(na_clock, 4), na_score = round(na_score, 4))])
# base frame composition (what C1/C2/C3 predict)
fr <- as.data.table(d$base$frame); cat("base frame columns:", names(fr), "\n")
ids_fbs <- function(y) { s <- as.data.table(d$sch[[as.character(y)]]); unique(c(s$home_id[s$home_fbs %in% TRUE], s$away_id[s$away_fbs %in% TRUE])) }
fr[, both_fbs := mapply(function(y, h, a) h %in% ids_fbs(y) & a %in% ids_fbs(y), season, home_id, away_id)]
print(fr[, .(rows = .N, both_fbs = sum(both_fbs)), by = season])
# FCS connectivity at end of season: per FCS team, games vs FBS and vs FCS
con <- rbindlist(lapply(2016:2025, function(y) { g <- d$games[[as.character(y)]][final == TRUE]
  r <- rbind(g[, .(team_id = home_id, fbs = home_fbs %in% TRUE, opp_fbs = away_fbs %in% TRUE)], g[, .(team_id = away_id, fbs = away_fbs %in% TRUE, opp_fbs = home_fbs %in% TRUE)])[fbs == FALSE]
  r[, .(vs_fbs = sum(opp_fbs), vs_fcs = sum(!opp_fbs)), by = team_id][, .(season = y, fcs_teams = .N, with_fbs_game = sum(vs_fbs > 0), mean_vs_fbs = mean(vs_fbs), mean_vs_fcs = mean(vs_fcs), zero_fcs_games = sum(vs_fcs == 0))] }))
print(con)
# garbage filter active? one season audit
source("R/round15/prep/fumble_parser.R"); source("R/round15/prep/sr_history.R")
source("config/paths.R")
e <- r15_r13_env()
aud <- rbindlist(lapply(c(2017L, 2019L, 2022L, 2024L), function(y) {
  g <- e$r13_schedule(as.data.frame(readRDS(file.path(PATHS$frozen, "cfb_data_v3", sprintf("raw_schedule_%d.rds", y)))))
  raw <- e$r13_read_plays(file.path(raw6, sprintf("plays_%d.rds", y))); raw[, game_id := as.character(game_id)]; raw <- raw[game_id %in% g$game_id]
  st <- e$r13_states(r15_recover_fumbles(raw, e), g); el <- e$r13_eligible(st)
  a <- el$audit[, type := typ(g$home_fbs[match(game_id, g$game_id)], g$away_fbs[match(game_id, g$game_id)])]
  a[, .N, by = .(type, reason)][, share := N / sum(N), by = type][, season := y] }))
print(dcast(aud, season + reason ~ type, value.var = "share", fun.aggregate = function(x) round(sum(x), 4)))
