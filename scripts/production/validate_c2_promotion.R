# =====================================================================================================================
# scripts/production/validate_c2_promotion.R: pre-cutover validation of the Current C2 production path (run locally once).
#
# Needs the research caches (output/dev/round15 -> the Round 15 worktree; Round 6 raw plays; the canonical Current C2
# outputs in the c2-refinement worktree) and the live 2026 inputs used by the pre-promotion comparison. No network call
# except CFBD /games 2026 postseason (1 call, empty in September). Writes docs/production/validation/c2_validation.csv.
#   A  frozen inputs and code (MD5; code byte-identical to tag c2-post-stage4-baseline)
#   B  historical reproduction: the adapter's data assembly + c2_predict_season reproduce canonical C2 for all of 2025
#   C  2026 overlap: the production build (frozen inputs) reproduces the canonical recomputation at 2026-09-21 and the
#      pre-promotion comparison (docs/c2/live_2026_wk04)
#   D  schema, team names/IDs, every FBS team rated
#   E  cutoffs and leakage (training set; perturbing post-cutoff results changes nothing)
#   F  incumbent unchanged through the selection layer
#   G  no silent fallback
# =====================================================================================================================
source("config/paths.R"); source("config/production.R"); source("config/production_model.R")
suppressPackageStartupMessages({ source(PATHS$model_ops); source(PATHS$production_model); library(data.table) })
c2p_load_model()
REF <- normalizePath(file.path(PATHS$root, "..", "c2-refinement"))            # canonical outputs + pre-promotion comparison
MAIN <- normalizePath(file.path(PATHS$root, "..", "..", ".."))                  # main checkout: live production state
LIVE <- file.path(MAIN, "output/state/production_live")
res <- list(); check <- function(section, what, value, pass) {
  res[[length(res) + 1L]] <<- data.table(section, check = what, value = format(value, digits = 6), pass = isTRUE(pass))
  cat(sprintf("[%s] %-4s %s: %s\n", section, if (isTRUE(pass)) "PASS" else "FAIL", what, format(value, digits = 6)))
}
mad <- function(a, b) max(abs(a - b))

# ---------------- A. frozen inputs and code ----------------
v <- c2p_verify_frozen(); check("A", "C2 frozen inputs + code MD5", sprintf("%d/%d", sum(v$ok), nrow(v)), all(v$ok))
diffs <- system2("git", c("diff", "--name-only", PRODUCTION_MODEL$c2$research_commit, "HEAD", "--", names(PRODUCTION_MODEL$c2$code_md5)), stdout = TRUE)
check("A", "model code identical to research commit 6a187ea", length(diffs), length(diffs) == 0)

# ---------------- B. historical reproduction (2025, every cutoff) ----------------
d <- r15_build_data(); c1 <- readRDS(file.path(R15C$cache, "c1_components.rds")); c2 <- readRDS(file.path(R15C$cache, "c2_components.rds"))
fcs_hist <- as.data.table(readRDS("output/dev/round15/prep/fcs_schedules_2013_2025.rds")); dv <- c2_divisions(fcs_hist)
levels <- rbindlist(lapply(2013:2025, function(s) c2_eos_levels(d, s, dv)))
Y <- 2025L; S25 <- c2_season_inputs(d, c1, c2, Y, dv, c2_anchors(levels, Y))
raw25 <- readRDS(frozen_path("cfb_data_v3", sprintf("raw_schedule_%d.rds", Y))); plays25 <- file.path(R15C$raw6, sprintf("plays_%d.rds", Y))
key <- c("season", "game_id", "offense")
pb <- c2p_play_rows(plays25, raw25, Y); ref <- d$pbp[season == Y]; setkeyv(pb, key); setkeyv(ref, key); setcolorder(pb, names(ref))
check("B", "play rows (SR, fumbles, passer) == frozen build d$pbp 2025", sprintf("%d rows", nrow(pb)), isTRUE(all.equal(pb, ref, check.attributes = FALSE)))
fcs25 <- c2p_fcs_games(Y, "output/dev/round15/raw")                            # the P1 responses, cached: no call
f_ref <- fcs_hist[season == Y]; setkey(fcs25, game_id); setkey(f_ref, game_id)
check("B", "FCS games mapping == P1 fcs_schedules 2025", sprintf("%d games", nrow(fcs25)), isTRUE(all.equal(fcs25, f_ref, check.attributes = FALSE)))
gam <- r15_full_games(d$sch[[as.character(Y)]], fcs25)
check("B", "games table == frozen build d$games 2025", nrow(gam), isTRUE(all.equal(gam[order(game_id)], d$games[[as.character(Y)]][order(game_id)], check.attributes = FALSE)))
cp <- fread(file.path(REF, "output/c2/current/c2_predictions.csv"), colClasses = list(character = "cutoff"))[season == Y]
cr <- fread(file.path(REF, "output/c2/current/c2_ratings.csv"), colClasses = list(character = "cutoff"))[season == Y]
cl <- fread(file.path(REF, "output/c2/current/c2_group_levels.csv"), colClasses = list(character = "cutoff"))[season == Y]
cf <- fread(file.path(REF, "output/c2/current/c2_first_game_ratings.csv"), colClasses = list(character = "cutoff"))[season == Y]
cn <- fread(file.path(REF, "output/c2/current/c2_fbs_vs_nonfbs_predictions.csv"), colClasses = list(character = "cutoff"))[season == Y]
snaps <- Filter(function(sn) sn$season == Y, d$base$snap); fr <- as.data.table(d$base$frame)[season == Y]
play_tab <- as.data.table(readRDS(plays25))
bm <- rbindlist(lapply(snaps, function(sn) {
  x <- c2p_run(Y, sn$cutoff, d$sch[[as.character(Y)]], raw25, tempdir(), fcs_games = fcs25, plays = play_tab, targets = fr[cutoff == sn$cutoff], S = S25)
  ct <- format(sn$cutoff, "%Y-%m-%d"); cur <- x$cur
  p <- merge(cur$pred[, .(game_id = as.character(game_id), pm = pred_margin)], cp[cutoff == ct, .(game_id = as.character(game_id), pred_margin)], by = "game_id")
  r <- merge(cur$ratings[, .(team_id, power)], cr[cutoff == ct, .(team_id, power_c = power)], by = "team_id")
  f <- merge(cur$first_game[, .(team_id, power)], cf[cutoff == ct, .(team_id, power_c = power)], by = "team_id")
  nf <- as.data.table(c2p_nonfbs_ratings(x)); fbp <- setNames(cur$ratings[fbs == TRUE, power], cur$ratings[fbs == TRUE, team_id])
  n <- cn[cutoff == ct][, pw := fbp[as.character(fbs_id)] - nf$power[match(nonfbs_id, nf$team_id)] + H * (!neutral) * fifelse(fbs_home, 1, -1)]
  data.table(cutoff = ct, n_pred = nrow(p), n_pred_ref = cp[cutoff == ct, .N], d_pred = if (nrow(p)) mad(p$pm, p$pred_margin) else 0,
             n_rat = nrow(r), n_rat_ref = cr[cutoff == ct, .N], d_rat = mad(r$power, r$power_c), d_first = if (nrow(f)) mad(f$power, f$power_c) else 0,
             n_first = nrow(f), n_first_ref = cf[cutoff == ct, .N],
             d_lvl = mad(c(cur$levels$delta_fcs, cur$levels$delta_low), c(cl[cutoff == ct, delta_fcs], cl[cutoff == ct, delta_low])),
             n_nonfbs = nrow(n), d_nonfbs = if (nrow(n)) mad(n$pw, n$pred_fbs_margin) else 0)
}))
fwrite(bm, "docs/production/validation/c2_historical_2025_by_cutoff.csv")
check("B", sprintf("2025 predictions, %d cutoffs: max |adapter - canonical|", nrow(bm)), max(bm$d_pred), max(bm$d_pred) < 1e-9 && all(bm$n_pred == bm$n_pred_ref))
check("B", "2025 ratings (all entities): max |diff|", max(bm$d_rat), max(bm$d_rat) < 1e-9 && all(bm$n_rat == bm$n_rat_ref))
check("B", "2025 group levels: max |diff|", max(bm$d_lvl), max(bm$d_lvl) < 1e-9)
check("B", "2025 first-game ratings: max |diff|", max(bm$d_first), max(bm$d_first) < 1e-9 && all(bm$n_first == bm$n_first_ref))
check("B", "2025 FBS-vs-nonFBS: adapter team rule == c2_fbs_vs_nonfbs() margins", sprintf("%d games, max %.2e", sum(bm$n_nonfbs), max(bm$d_nonfbs)), max(bm$d_nonfbs) < 1e-9)

# ---------------- C. 2026 overlap at the 2026-09-21 cutoff ----------------
CUT <- as.POSIXct("2026-09-21", tz = "UTC"); cfg <- v4_config(); cfg$cache_dir <- LIVE; sch26 <- read_schedule(2026L, cfg, FALSE)
raw26 <- readRDS(file.path(LIVE, "raw_schedule_2026.rds"))
fcs_dir <- file.path(tempdir(), "fcs26"); dir.create(fcs_dir, showWarnings = FALSE)
file.copy(file.path(REF, "output/live2026/raw/games_year2026_seasonTyperegular_classificationfcs.rds"), fcs_dir)
fcs26 <- c2p_fcs_games(2026L, fcs_dir)
plays26 <- as.data.table(readRDS(file.path(REF, "output/live2026/raw/plays_2026_wk1_3.rds")))
wk4 <- as.data.table(sch26)[week == 4 & season_type == "regular"]
prod <- c2_production_build(2026L, CUT, sch26, raw26, tempdir(), fcs_games = fcs26, plays = plays26, targets = wk4[home_fbs & away_fbs])
# canonical recomputation (the pre-promotion comparison's path: everything recomputed from the research caches)
g26 <- r15_full_games(sch26, rbind(fcs_hist, fcs26, fill = TRUE)); pf <- tempfile(fileext = ".rds"); saveRDS(as.data.frame(plays26), pf)
d2 <- d; d2$sch[["2026"]] <- sch26; d2$games[["2026"]] <- g26; d2$pbp <- rbind(d$pbp, c2p_play_rows(pf, raw26, 2026L), fill = TRUE)
c1x <- c1; c1x$priors[["2026"]] <- r15_c1_prior(d2, 2026L, 2022L, r15_bind_incumbent())
dv2 <- c2_divisions(rbind(fcs_hist, fcs26, fill = TRUE)); S26 <- c2_season_inputs(d2, c1x, c2, 2026L, dv2, c2_anchors(levels, 2026L))
Sf <- readRDS(PRODUCTION_MODEL$c2$season_inputs)
check("C", "frozen season inputs == canonical recomputation (except divisions)",
      "all.equal", isTRUE(all.equal(Sf[setdiff(names(S26), "dv")], S26[setdiff(names(S26), "dv")], check.attributes = FALSE)))
d2$base$snap <- c(d$base$snap, list(list(season = 2026L, cutoff = CUT)))
d2$base$frame <- rbind(as.data.table(d$base$frame), wk4[home_fbs & away_fbs, .(season = 2026L, game_id, week, kickoff, neutral, home_id, away_id, cutoff = CUT)], fill = TRUE)
can <- c2_predict_season(d2, 2026L, S26)[[1]]
m <- merge(as.data.table(prod)[, .(team_id, power_rating, off_rating, def_rating)], can$ratings[fbs == TRUE, .(team_id, power, eff_off, eff_def)], by = "team_id")
check("C", "2026-09-21 FBS power/off/def: max |production - canonical|", mad(c(m$power_rating, m$off_rating, m$def_rating), c(m$power, m$eff_off, m$eff_def)),
      nrow(m) == 138L && mad(c(m$power_rating, m$off_rating, m$def_rating), c(m$power, m$eff_off, m$eff_def)) < 1e-9)
check("C", "2026-09-21 group levels: max |diff|", mad(unlist(attr(prod, "group_levels")[, c("delta_fcs", "delta_low")]), unlist(can$levels[, .(delta_fcs, delta_low)])),
      mad(unlist(attr(prod, "group_levels")[, c("delta_fcs", "delta_low")]), unlist(can$levels[, .(delta_fcs, delta_low)])) < 1e-9)
pp <- merge(as.data.table(attr(prod, "predictions"))[, .(game_id = as.character(game_id), a = pred_margin)], can$pred[, .(game_id = as.character(game_id), b = pred_margin)], by = "game_id")
check("C", "week-4 FBS-vs-FBS predictions: max |diff|", sprintf("%d games, %.2e", nrow(pp), mad(pp$a, pp$b)), nrow(pp) == wk4[home_fbs & away_fbs, .N] && mad(pp$a, pp$b) < 1e-9)
# against the pre-promotion comparison the user reviewed (rounded to 0.01 / 0.1 there)
w1 <- fread(file.path(REF, "docs/c2/live_2026_wk04/power_ratings_c2_vs_incumbent_2026_wk04.csv"))
q <- merge(as.data.table(prod)[, .(team_id, power_rating)], w1[, .(team_id, c2_power_rating, incumbent_power_rating)], by = "team_id")
check("C", "ratings vs pre-promotion comparison CSV (rounded 0.01)", mad(q$power_rating, q$c2_power_rating), nrow(q) == 138L && mad(q$power_rating, q$c2_power_rating) <= 0.005 + 1e-9)
w2 <- fread(file.path(REF, "docs/c2/live_2026_wk04/game_spreads_c2_vs_incumbent_2026_wk04.csv"))
nf <- as.data.table(attr(prod, "nonfbs_ratings")); pw <- function(id) { x <- prod$power_rating[match(id, prod$team_id)]; ifelse(is.finite(x), x, nf$power[match(id, nf$team_id)]) }
w2[, prod_spread := -(pw(wk4$home_id[match(game_id, wk4$game_id)]) - pw(wk4$away_id[match(game_id, wk4$game_id)]) + attr(prod, "hfa") * !wk4$neutral[match(game_id, wk4$game_id)])]
check("C", "all week-4 spreads incl. FBS-vs-FCS vs pre-promotion comparison (rounded 0.1)", sprintf("%d games, %.3f", nrow(w2), mad(w2$prod_spread, w2$c2_implied_spread)),
      mad(w2$prod_spread, w2$c2_implied_spread) <= 0.05 + 1e-9)

# ---------------- D. schema, names, IDs ----------------
inc <- readRDS(file.path(MAIN, "output/state/production_ratings_2026_latest.rds"))   # incumbent production snapshot, as_of 2026-09-21
ranking <- as.data.frame(prod)[, c("rank", "team", "team_id", "conf", "power_rating", "off_rating", "def_rating", "games_played", "pre_power",
                                   "prior_contribution", "current_contribution", "centering_contribution", "feature_snapshot_id")]
names(ranking)[names(ranking) == "conf"] <- "conference"
check("D", "ratings object class == v5_build()'s (tibble)", paste(class(prod), collapse = "/"), identical(class(prod), class(inc$ratings)))
check("D", "ranking columns == incumbent snapshot columns (same order)", paste(names(ranking), collapse = ","), identical(names(ranking), names(inc$ratings)))
check("D", "column classes == incumbent (numeric/character/integer)", "", identical(vapply(ranking, function(x) class(x)[1], ""), vapply(as.data.frame(inc$ratings), function(x) class(x)[1], "")) ||
        all(vapply(names(ranking), function(n) is.numeric(ranking[[n]]) == is.numeric(inc$ratings[[n]]), TRUE)))
ii <- match(inc$ratings$team_id, ranking$team_id)
check("D", "same 138 FBS team IDs as the incumbent", nrow(ranking), nrow(ranking) == 138L && !anyNA(ii) && setequal(ranking$team_id, inc$ratings$team_id))
check("D", "team names identical to the incumbent's", sum(ranking$team[ii] != inc$ratings$team), identical(ranking$team[ii], inc$ratings$team))
check("D", "conferences identical to the incumbent's", sum(ranking$conference[ii] != inc$ratings$conference, na.rm = TRUE), identical(ranking$conference[ii], inc$ratings$conference))
teams <- as.data.frame(readRDS(file.path(PATHS$teams_dir, "teams_2026.rds"))); fbs_ref <- teams$team_id[tolower(teams$classification) == "fbs"]
check("D", "every FBS team in teams_2026.rds has a finite rating", sum(fbs_ref %in% ranking$team_id[is.finite(ranking$power_rating)]), all(fbs_ref %in% ranking$team_id[is.finite(ranking$power_rating)]))
check("D", "FBS ratings centred on the FBS mean", mean(ranking$power_rating), abs(mean(ranking$power_rating)) < 1e-9)
check("D", "snapshot hfa == incumbent hfa (betting export input)", attr(prod, "hfa") - inc$hfa, abs(attr(prod, "hfa") - inc$hfa) < 1e-12)
fcs_opp <- unique(c(sch26$home_id[!sch26$home_fbs], sch26$away_id[!sch26$away_fbs]))
check("D", "every non-FBS opponent on the FBS schedule has a C2 rating (Stage 3)", sprintf("%d of %d", sum(fcs_opp %in% nf$team_id[is.finite(nf$power)]), length(fcs_opp)),
      all(fcs_opp %in% nf$team_id[is.finite(nf$power)]))
check("D", "non-FBS: no constant -25 anywhere", sum(nf$power == -25), !any(nf$power == -25) && sd(nf$power) > 1)

# ---------------- E. cutoffs and leakage ----------------
tr <- attr(prod, "training_ids"); gg <- r15_full_games(sch26, fcs26)
check("E", "training games all available before the cutoff", sprintf("%d games", length(tr)), all(gg[game_id %in% tr, available_at] < CUT) && all(gg[game_id %in% tr, final]))
check("E", "every final game available before the cutoff is used", "", setequal(tr, gg[final == TRUE & available_at < CUT, game_id]))
check("E", "no week-4 target game in training", "", !any(wk4$game_id %in% tr))
# perturbation: mark every week-4 game final with an absurd score and add fake plays; the ratings must not move
s2 <- as.data.frame(sch26); w <- s2$week == 4; s2$final[w] <- TRUE; s2$home_points[w] <- 99; s2$away_points[w] <- 0
fake <- plays26[game_id %in% plays26$game_id[1:3]][, `:=`(game_id = rep(wk4$game_id[1], .N), wk = 4L)]
p2 <- c2_production_build(2026L, CUT, s2, raw26, tempdir(), fcs_games = fcs26, plays = rbind(plays26, fake), targets = wk4[home_fbs & away_fbs])
check("E", "post-cutoff results/plays injected: max rating change", mad(p2$power_rating[match(prod$team_id, p2$team_id)], prod$power_rating),
      mad(p2$power_rating[match(prod$team_id, p2$team_id)], prod$power_rating) == 0)
early <- c2_production_build(2026L, as.POSIXct("2026-09-07", tz = "UTC"), sch26, raw26, tempdir(), fcs_games = fcs26, plays = plays26)
check("E", "earlier cutoff 2026-09-07 uses only week-1 games", max(gg[game_id %in% attr(early, "training_ids"), available_at]),
      max(gg[game_id %in% attr(early, "training_ids"), available_at]) < as.POSIXct("2026-09-07", tz = "UTC"))
check("E", "preseason rating (pre_power) == C2 no-games branch: a x C1 prior, FBS-centred", "",
      { pr <- Sf$prior; po <- Sf$a * pr$pre_off; pd <- Sf$a * pr$pre_def; pp0 <- (po - mean(po)) - (pd - mean(pd))
        mad(prod$pre_power, pp0[match(prod$team_id, pr$team_id)]) < 1e-9 })

# ---------------- F. incumbent unchanged through the selection layer ----------------
seed1 <- readRDS(file.path(PATHS$snapshot_seed, "production_ratings_2026_wk01.rds"))
e1 <- production_build(2026L, seed1$as_of, model = "EB_features"); v1 <- v5_build(2026L, seed1$as_of)
check("F", "routed EB_features build identical() to v5_build()", "", identical(e1, v1))
check("F", "routed EB_features reproduces committed week-1 snapshot", mad(e1$power_rating[match(seed1$ratings$team_id, e1$team_id)], seed1$ratings$power_rating),
      mad(e1$power_rating[match(seed1$ratings$team_id, e1$team_id)], seed1$ratings$power_rating) < 1e-10)
e3 <- production_build(2026L, CUT, sch26, LIVE, model = "EB_features")
check("F", "routed EB_features at 2026-09-21 == incumbent production snapshot", mad(e3$power_rating[match(inc$ratings$team_id, e3$team_id)], inc$ratings$power_rating),
      mad(e3$power_rating[match(inc$ratings$team_id, e3$team_id)], inc$ratings$power_rating) < 1e-10)
check("F", "incumbent simulation conventions kept for EB ratings", "", identical(production_sim_params(e3)[1:3], list(hfa = PRODUCTION$sim_hfa, resid_sd = PRODUCTION$sim_resid_sd, fcs_power = PRODUCTION$sim_fcs_power)))
check("F", "C2 simulation parameters (hfa, Round 16 sigma, no constant FCS)", paste(unlist(production_sim_params(prod)[1:3]), collapse = " / "),
      identical(production_sim_params(prod)$resid_sd, 15.6500874177702) && is.na(production_sim_params(prod)$fcs_power))

# ---------------- G. no silent fallback ----------------
err <- function(expr) inherits(try(expr, silent = TRUE), "try-error")
Sys.setenv(CFB_PRODUCTION_MODEL = "C3"); check("G", "unknown CFB_PRODUCTION_MODEL stops", "", err(production_model_id())); Sys.unsetenv("CFB_PRODUCTION_MODEL")
check("G", "default model is C2_current", production_model_id(), identical(production_model_id(), "C2_current"))
keep <- PRODUCTION_MODEL$c2$season_inputs_md5; PRODUCTION_MODEL$c2$season_inputs_md5 <- "0"
check("G", "C2 frozen-input mismatch stops the build (no fallback)", "", err(c2_production_build(2026L, CUT, sch26, raw26, tempdir(), fcs_games = fcs26, plays = plays26)))
PRODUCTION_MODEL$c2$season_inputs_md5 <- keep
check("G", "C2 refuses a season without frozen inputs", "", err(c2p_season_inputs(2027L)))
check("G", "missing non-FBS rating stops the simulation input", "", err(production_nonfbs_power(prod, 999999L)))
bad <- prod; attr(bad, "candidate") <- "mystery"; check("G", "unknown model identity stops simulation routing", "", err(production_sim_params(bad)))
check("G", "broken play-by-play pull (week 3 missing) stops the build", "", err(c2_production_build(2026L, CUT, sch26, raw26, tempdir(), fcs_games = fcs26, plays = plays26[wk != 3])))

out <- rbindlist(res); fwrite(out, "docs/production/validation/c2_validation.csv")
cat(sprintf("\n%d checks, %d passed, %d failed\n", nrow(out), sum(out$pass), sum(!out$pass)))
if (!all(out$pass)) quit(status = 1L)
