# C2 refinement research, Stage 2 (garbage time), part A: rebuild the success-rate inputs under each treatment.
# Run from the round15-power-rating worktree root; writes only under the c2-refinement worktree.
# Treatments (pre-snap |margin|; overtime plays are dropped in every arm, as frozen C2 does; no source addresses overtime):
#   A0 = no garbage filter;
#   A  = frozen C2 / Round 13: drop Q2 > 38, Q3 > 28, Q4 > 22 (Q1 never) -- the literal reading of the Football Outsiders
#        2018 S&P+ text "a game is not within 38 points in the second quarter, 28 points in the third quarter, or 22 points
#        in the fourth quarter";
#   B  = Connelly's own statement (@ESPN_BillC, 3 Sep 2019): "Lead of 44+ in Q1, 38+ in Q2, 28+ in Q3, 22+ in Q4", i.e. drop
#        Q1 >= 44, Q2 >= 38, Q3 >= 28, Q4 >= 22 (margins are integers, so >= k is > k - 1).
# Everything else is the frozen Round 13 instrument with the Round 15 P2 fumble parser and the Amendment 01 A3 2020 patch
# (r15_sr_season with only the garbage vector changed). Arm A must reproduce the frozen play-derived inputs exactly.
suppressPackageStartupMessages({ source("config/paths.R"); library(data.table); source("R/round15/prep/fumble_parser.R"); source("R/round15/prep/sr_history.R") })
C2R <- "/Users/willcavender/Desktop/Revised CFB Modeling/.claude/worktrees/c2-refinement"; out <- file.path(C2R, "output/c2r/stage2"); dir.create(out, recursive = TRUE, showWarnings = FALSE)
raw6 <- "/Users/willcavender/Desktop/CFB Modeling Backup/CFB-Modeling-round6/outputs/round6/raw"
schedf <- function(y) if (y >= 2015) file.path(PATHS$frozen, "cfb_data_v3", sprintf("raw_schedule_%d.rds", y)) else file.path(raw6, sprintf("raw_schedule_%d.rds", y))
TR <- list(A0 = c(Inf, Inf, Inf, Inf), A = c(Inf, 38, 28, 22), B = c(43, 37, 27, 21))

res <- lapply(2013:2025, function(y) {
  e <- r15_r13_env(allow_2020 = y == 2020); g <- e$r13_schedule(as.data.frame(readRDS(schedf(y)))); stopifnot(all(g$season == y))
  raw <- e$r13_read_plays(file.path(raw6, sprintf("plays_%d.rds", y))); stopifnot(all(raw$season == y)); raw[, game_id := as.character(game_id)]; raw <- raw[game_id %in% g$game_id]
  st <- e$r13_states(r15_recover_fumbles(raw, e), g)
  cut <- max(g$available_at[g$final], na.rm = TRUE) + 1; ids <- sort(unique(c(g$home_team[g$home_fbs], g$away_team[g$away_fbs])))
  j <- match(st$game_id, g$game_id); hf <- g$home_fbs[j]; af <- g$away_fbs[j]
  typ <- fifelse(hf & af, "FBS-FBS", fifelse(hf | af, "FBS-FCS", "other"))
  offb <- fifelse(st$offense == st$home, hf, af)
  sapply(names(TR), function(tn) {
    el <- e$r13_eligible(st, garbage = TR[[tn]]); means <- e$r13_game_means(el$plays)
    eff <- e$r13_effects(means, ids, cut, half_life = Inf)
    ok <- el$audit$reason %in% c("eligible", "garbage_or_overtime", "incomplete_game_exposure")   # scrimmage plays passing every non-garbage rule
    sc <- data.table(type = typ, off_fbs = offb, reason = el$audit$reason, q = pmin(st$period, 5L),
                     succ = as.numeric(st$yards_gained >= st$distance * c(.5, .7, 1, 1)[pmin(pmax(st$down, 1L), 4L)]))[ok]
    acc <- sc[, .(plays = .N, kept = sum(reason == "eligible"), garbage = sum(reason == "garbage_or_overtime" & q <= 4), overtime = sum(reason == "garbage_or_overtime" & q == 5),
                  exposure = sum(reason == "incomplete_game_exposure"), sr_kept = mean(succ[reason == "eligible"]), sr_all = mean(succ[q <= 4])), by = .(type, off_fbs)][, season := y]
    list(means = means[, .(season = y, game_id, offense, defense, sr = success, sr_plays = plays)], eff = eff[, .(season = y, team, sr_off, sr_def, games_played)], acc = acc)
  }, simplify = FALSE)
})
names(res) <- 2013:2025
sr <- lapply(setNames(names(TR), names(TR)), function(tn) list(means = rbindlist(lapply(res, function(r) r[[tn]]$means)), eff = rbindlist(lapply(res, function(r) r[[tn]]$eff)),
                                                              acc = rbindlist(lapply(res, function(r) r[[tn]]$acc))))
# ---- tie-out: arm A reproduces the frozen inputs (data.rds pbp sr/sr_plays for 2014-2025; the A3 end-of-season SR table)
d <- readRDS("output/dev/round15/cand/data.rds")
fz <- d$pbp[!is.na(sr), .(season, game_id, offense, defense, sr, sr_plays)]
ma <- merge(fz, sr$A$means[season >= 2014], by = c("season", "game_id", "offense", "defense"), all = TRUE, suffixes = c("_f", "_a"))
nkey <- function(x) gsub("[^A-Za-z0-9 &().'-]", "", iconv(x, "", "ASCII", sub = ""))   # the A3 CSV and the in-memory table encode "San Jose State" differently
eo <- merge(copy(d$sr_eos)[, k := nkey(team)], copy(sr$A$eff)[, k := nkey(team)][, team := NULL], by = c("season", "k"), all = TRUE, suffixes = c("_f", "_a"))
stopifnot(!anyDuplicated(d$sr_eos[, .(season, nkey(team))]))
chk <- data.table(item = c("game x offense SR rows", "end-of-season SR rows"), frozen = c(nrow(fz), nrow(d$sr_eos)), rebuilt_A = c(sr$A$means[season >= 2014, .N], nrow(sr$A$eff)),
                  unmatched = c(ma[is.na(sr_f) | is.na(sr_a), .N], eo[is.na(sr_off_f) | is.na(sr_off_a), .N]),
                  max_abs_diff = c(max(abs(ma$sr_f - ma$sr_a), abs(ma$sr_plays_f - ma$sr_plays_a), na.rm = TRUE),
                                   max(abs(eo$sr_off_f - eo$sr_off_a), abs(eo$sr_def_f - eo$sr_def_a), abs(eo$games_played_f - eo$games_played_a), na.rm = TRUE)))
print(chk); stopifnot(all(chk$unmatched == 0), all(chk$max_abs_diff < 1e-12))
saveRDS(list(sr = sr, check = chk, treatments = TR), file.path(out, "sr_treatments.rds"))
acc <- rbindlist(lapply(names(TR), function(tn) sr[[tn]]$acc[, treatment := tn])); print(acc[season %in% c(2017, 2024) & type != "other"][order(season, type, off_fbs, treatment)], digits = 3)
