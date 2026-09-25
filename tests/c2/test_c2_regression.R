# Regression tests: current C2 vs frozen Round 15 C2 (R/round15/candidates/c2.R, never modified). Run from the
# c2-refinement worktree root. Every difference must be one the Stage 3 FCS change explains; everything else identical.
# Writes docs/c2/validation/regression_*.csv; stops on any unexpected difference.
source("config/paths.R"); source("config/production.R")
suppressPackageStartupMessages({ source(PATHS$model_ops); library(data.table); for (f in c("data", "c1", "c2")) source(sprintf("R/round15/candidates/%s.R", f)) })
source("R/c2/c2_current.R"); source("R/round15/prep/fumble_parser.R"); source("R/round15/prep/sr_history.R")
VAL <- "docs/c2/validation"; dir.create(VAL, recursive = TRUE, showWarnings = FALSE); TOL <- 1e-9
d <- r15_build_data(); c1 <- readRDS(file.path(R15C$cache, "c1_components.rds")); c2 <- readRDS(file.path(R15C$cache, "c2_components.rds"))
dv <- c2_divisions(readRDS("output/dev/round15/prep/fcs_schedules_2013_2025.rds"))
cur <- c2_run(d, c1, c2, dv, keep_system = TRUE)
frz <- fread(file.path(R15C$cache, "c2_predictions.csv"), colClasses = list(character = "game_id"))
rr <- fread("output/dev/round15/eval/ratings_replay.csv", colClasses = list(character = "cutoff"))[model == "C2"]   # frozen C2 ratings (E0 replay)
chk <- list(); add <- function(test, expect, value, pass, detail = "") chk[[length(chk) + 1L]] <<- data.table(test = test, expectation = expect, value = value, pass = pass, detail = detail)

# ---- 1. unchanged inputs --------------------------------------------------------------------------------------------
e <- r15_r13_env(); add("garbage-time thresholds (R13$garbage)", "identical to frozen: Inf/38/28/22, OT dropped", paste(e$R13$garbage, collapse = "/"), identical(e$R13$garbage, c(Inf, 38, 28, 22)))
s19 <- r15_sr_season(file.path(R15C$raw6, "plays_2019.rds"), readRDS(file.path(PATHS$frozen, "cfb_data_v3", "raw_schedule_2019.rds")), 2019)$means
m19 <- merge(s19[, .(game_id, offense, defense, sr_new = success)], d$pbp[season == 2019 & !is.na(sr), .(game_id, offense, defense, sr)], by = c("game_id", "offense", "defense"))
add("success-rate instrument (2019 rebuilt from raw plays)", "identical to the frozen SR rows C2 reads", sprintf("%d rows, max diff %.1e", nrow(m19), max(abs(m19$sr_new - m19$sr))),
    nrow(m19) == d$pbp[season == 2019 & !is.na(sr), .N] && max(abs(m19$sr_new - m19$sr)) == 0)
E0 <- function(y) { k <- c2_key(y); list(prior = c1$priors[[as.character(y)]], a = c1$scl[[as.character(k)]], lam = r15_c1_lambda(c1$priors[[as.character(y)]], c1$varm[[as.character(k)]], c1$lam0[[c2_key22(k)]]),
  H = if (y >= 2023) R15C$frozen_hfa else r15_H(d, y), p2 = c2$p2[[as.character(k)]], lambda0 = c1$lam0[[c2_key22(y)]], omega = c2$om[[c2_key22(y)]]) }   # the E0 replay's argument set
same_inputs <- all(vapply(C2_SPEC$seasons, function(y) { S <- c2_season_inputs(d, c1, c2, y, dv, cur$anchors); F <- E0(y)
  identical(S$prior, F$prior) && S$a == F$a && identical(S$lam, F$lam) && S$H == F$H && identical(S$p2, F$p2) && S$lambda0 == F$lambda0 && S$omega == F$omega }, TRUE))
add("season inputs: C1 prior, scale a, lambda (turnover-scaled), H, beta, kappa, FCS moments, lambda0, omega", "identical to the frozen construction (E0 argument set)", as.character(same_inputs), same_inputs)
# FBS prior means and precisions inside every solve equal a x C1 prior and lambda (preseason scale 1.0, no decay)
pp <- rbindlist(Map(function(sys, k) { if (is.null(sys)) return(NULL); S <- c2_season_inputs(d, c1, c2, k$season, dv, cur$anchors); ids <- fbs_ids(d$sch[[as.character(k$season)]]); nt <- sys$nt
  data.table(d_po = max(abs(sys$po[seq_len(nt)] - S$a * S$prior$pre_off[match(ids, S$prior$team_id)])), d_lo = max(abs(sys$lo[seq_len(nt)] - S$lam$off[match(ids, S$prior$team_id)])),
             d_ld = max(abs(sys$ld[seq_len(nt)] - S$lam$def[match(ids, S$prior$team_id)]))) }, cur$system, split(unique(cur$ratings[, .(season, cutoff)]), seq_len(nrow(unique(cur$ratings[, .(season, cutoff)]))))))
add("FBS prior means and precisions in every weekly solve", "a x C1 prior; lambda constant at every games-played count", sprintf("max diff %.1e", max(unlist(pp))), max(unlist(pp)) == 0)

# ---- 2. the ridge core: with no group columns and frozen's pooled priors it IS frozen C2 --------------------------------
core <- rbindlist(lapply(C2_SPEC$seasons, function(y) { F <- E0(y); ids <- fbs_ids(d$sch[[as.character(y)]]); games <- d$games[[as.character(y)]]; luck <- r15_luck(d, y)
  fcs_all <- setdiff(unique(c(games$home_id, games$away_id)), ids); last <- c2$eos_full[[as.character(y - 1L)]]; v <- c1$varm[[as.character(c2_key(y))]]
  lamf <- c(off = F$lambda0 * v$off$vbar / F$p2$v_fcs[["off"]], def = F$lambda0 * v$def$vbar / F$p2$v_fcs[["def"]])
  rbindlist(lapply(Filter(function(sn) sn$season == y, d$base$snap), function(sn) {
    rows <- r15_rows(games, sn$cutoff, luck, F$p2$kappa); if (!nrow(rows)) return(NULL); rows[, adj := 0]      # r15_rows already folds luck into pf
    ft <- intersect(fcs_all, unique(rows$team_id)); ents <- c(as.character(ids), as.character(ft)); lf <- last[match(ft, last$team_id)]
    po <- c(F$a * F$prior$pre_off[match(ids, F$prior$team_id)], ifelse(is.finite(lf$eff_off), F$p2$mu[["off"]] + F$p2$rho[["off"]] * (lf$eff_off - F$p2$mu[["off"]]), F$p2$mu[["off"]]))
    pd <- c(F$a * F$prior$pre_def[match(ids, F$prior$team_id)], ifelse(is.finite(lf$eff_def), F$p2$mu[["def"]] + F$p2$rho[["def"]] * (lf$eff_def - F$p2$mu[["def"]]), F$p2$mu[["def"]]))
    lo <- c(F$lam$off[match(ids, F$prior$team_id)], rep(lamf[["off"]], length(ft))); ld <- c(F$lam$def[match(ids, F$prior$team_id)], rep(lamf[["def"]], length(ft)))
    sr <- if (F$omega > 0) r15_sr_rows(d, y, sn$cutoff, F$p2$beta)[entity %in% ents & opponent %in% ents] else NULL
    a <- r15_solve2(rows, ids, ents, po, pd, lo, ld, F$H, sr, F$omega); b <- c2_ridge_solve(rows, sr, ents, length(ids), po, pd, lo, ld, F$H, F$omega, list())
    data.table(season = y, cutoff = format(sn$cutoff, "%Y-%m-%d"), d_off = max(abs(a$eff_off - b$eff_off[seq_along(ids)])), d_def = max(abs(a$eff_def - b$eff_def[seq_along(ids)]))) })) }))
add("ridge core with no group columns vs frozen r15_solve2 (all 163 solved cutoffs)", "identical (the frozen system is the no-group special case)", sprintf("max diff %.1e", max(core$d_off, core$d_def)), max(core$d_off, core$d_def) < TOL)

# ---- 3. where the new C2 must equal frozen C2 exactly, and where it must differ -----------------------------------------
pr <- merge(cur$pred[, .(game_id, season, cutoff, cur = pred_margin)], frz[, .(game_id, frz = pred_margin)], by = "game_id")
lk <- cur$levels[, .(season, cutoff, n_link)]; pr <- merge(pr, lk, by = c("season", "cutoff")); pr[is.na(n_link), n_link := 0L]
snaps <- unique(cur$ratings[, .(season, cutoff)])[order(season, cutoff)][, wk := seq_len(.N), by = season]; pr <- merge(pr, snaps, by = c("season", "cutoff"))
pr[, `:=`(diff = cur - frz, phase = fifelse(wk <= 3, "early (cutoff 1-3)", "later"), linked = fifelse(n_link > 0, "FBS-vs-non-FBS game already played", "no FBS-vs-non-FBS game yet"))]
dt <- pr[, .(games = .N, n_identical = sum(abs(diff) <= TOL), max_abs_diff = max(abs(diff)), mean_abs_diff = mean(abs(diff))), by = .(linked, phase)][order(linked, phase)]
print(dt); fwrite(dt, file.path(VAL, "regression_predictions_vs_frozen.csv"))
# Cutoffs with no FBS-vs-non-FBS game yet: the only channel from non-FBS teams to FBS ratings is the shared scoring intercept
# (FCS-vs-FCS points rows help fit it). Frozen C2 itself shows the channel: removing its non-FBS rows at these cutoffs changes
# its FBS ratings. So tiny differences here are the mechanical consequence of the Stage 3 non-FBS priors, not a new behavior.
chan <- rbindlist(lapply(C2_SPEC$seasons, function(y) { F <- E0(y); ids <- fbs_ids(d$sch[[as.character(y)]]); games <- d$games[[as.character(y)]]; luck <- r15_luck(d, y)
  cu <- lk[season == y & n_link == 0]; rbindlist(lapply(Filter(function(sn) sn$season == y && format(sn$cutoff, "%Y-%m-%d") %in% cu$cutoff, d$base$snap), function(sn) {
    rows <- r15_rows(games, sn$cutoff, luck, F$p2$kappa); if (!nrow(rows) || all(rows$team_id %in% ids)) return(NULL)
    fo <- rows[team_id %in% ids & opp_id %in% ids]; po <- F$a * F$prior$pre_off[match(ids, F$prior$team_id)]; pd <- F$a * F$prior$pre_def[match(ids, F$prior$team_id)]
    lo <- F$lam$off[match(ids, F$prior$team_id)]; ld <- F$lam$def[match(ids, F$prior$team_id)]; ents <- as.character(ids)
    sr <- if (F$omega > 0) r15_sr_rows(d, y, sn$cutoff, F$p2$beta)[entity %in% ents & opponent %in% ents] else NULL
    a <- r15_solve2(fo, ids, ents, po, pd, lo, ld, F$H, sr, F$omega); a[, p := eff_off - eff_def]
    f0 <- rr[season == y & cutoff == format(sn$cutoff, "%Y-%m-%d") & fbs == TRUE]
    data.table(season = y, cutoff = format(sn$cutoff, "%Y-%m-%d"), non_fbs_rows = sum(!rows$team_id %in% ids), frozen_fbs_change_without_nonfbs_rows = max(abs(a$p - f0$rating[match(a$team_id, f0$team_id)]))) })) }))
print(chan); fwrite(chan, file.path(VAL, "regression_intercept_channel.csv"))
un <- pr[linked == "no FBS-vs-non-FBS game yet", max(abs(diff))]
add("FBS-vs-FBS predictions at cutoffs before any FBS-vs-non-FBS game", "EXPECTED tiny difference only where non-FBS games exist (shared scoring intercept; frozen C2 has the same channel)",
    sprintf("%d games, %d differ, max diff %.1e; frozen C2's own FBS ratings move up to %.1e when its non-FBS rows are removed", pr[linked == "no FBS-vs-non-FBS game yet", .N], pr[linked == "no FBS-vs-non-FBS game yet", sum(abs(diff) > TOL)], un, max(chan$frozen_fbs_change_without_nonfbs_rows)),
    un < 0.05 && nrow(chan) > 0 && max(chan$frozen_fbs_change_without_nonfbs_rows) > TOL && pr[linked == "no FBS-vs-non-FBS game yet" & abs(diff) > TOL, all(cutoff %in% chan$cutoff)])
add("FBS-vs-FBS predictions at cutoffs after linking games", "EXPECTED difference (Stage 3: FBS teams lose the credit from over-rated FCS opponents)",
    sprintf("%d games, mean |diff| %.3f, max %.3f", pr[linked != "no FBS-vs-non-FBS game yet", .N], pr[linked != "no FBS-vs-non-FBS game yet", mean(abs(diff))], pr[linked != "no FBS-vs-non-FBS game yet", max(abs(diff))]), TRUE)
# FBS offense / defense vs the frozen solve (frozen ratings via r15_solve2 = core check above); by team games played
fb <- merge(cur$ratings[fbs == TRUE, .(season, cutoff, team_id, gp, power)], rr[fbs == TRUE, .(season, cutoff, team_id, p0 = rating)], by = c("season", "cutoff", "team_id"))
fb <- merge(fb, lk, by = c("season", "cutoff")); fbt <- fb[, .(team_cutoffs = .N, max_abs_diff = max(abs(power - p0)), mean_abs_diff = mean(abs(power - p0))), by = .(team_games = fifelse(gp == 0, "0 games", "1+ games"), linked = n_link > 0)]
print(fbt); fwrite(fbt, file.path(VAL, "regression_fbs_ratings_vs_frozen.csv"))
add("FBS ratings at cutoffs before any linking game", "EXPECTED tiny difference via the shared intercept only (see above); identical where no non-FBS game exists",
    sprintf("max diff %.1e; at cutoffs with no non-FBS game at all: %.1e", fb[n_link == 0, max(abs(power - p0))], fb[n_link == 0 & !cutoff %in% chan$cutoff, max(c(0, abs(power - p0)))]),
    fb[n_link == 0, max(abs(power - p0))] < 0.05 && fb[n_link == 0 & !cutoff %in% chan$cutoff, max(c(0, abs(power - p0)))] <= TOL)
nf <- merge(cur$ratings[fbs == FALSE, .(season, cutoff, team_id, group, power)], rr[fbs == FALSE, .(season, cutoff, team_id, p0 = rating)], by = c("season", "cutoff", "team_id"))
add("non-FBS ratings", "EXPECTED difference (Stage 3 group levels and division pools)", sprintf("FCS mean shift %.2f; lower-division mean shift %.2f", nf[group == "fcs", mean(power - p0)], nf[group != "fcs", mean(power - p0)]), TRUE)
# relative FCS order and first cutoff behaviour
rk <- nf[group == "fcs", .(sp = cor(power, p0, method = "spearman")), by = .(season, cutoff)][, mean(sp)]
add("within-FCS ordering (Spearman vs frozen, mean over cutoffs)", "EXPECTED small change (division pools, Delta_low)", sprintf("%.3f", rk), rk > 0.95)
z0 <- merge(fb, cur$levels[n_games == 0, .(season, cutoff)], by = c("season", "cutoff")); zp <- merge(pr, cur$levels[n_games == 0, .(season, cutoff)], by = c("season", "cutoff"))
add("season-opening cutoffs (no game played): FBS ratings = prior", "identical to frozen", sprintf("%d cutoffs, %d team rows, %d games, max diff %.1e", cur$levels[n_games == 0, .N], nrow(z0), nrow(zp), max(abs(z0$power - z0$p0), abs(zp$diff))),
    max(abs(z0$power - z0$p0), abs(zp$diff)) <= TOL)
# anchors use only earlier seasons
add("anchors use only seasons before the target (2020 excluded)", "anchor_season < season for every target", paste(cur$anchors[, sprintf("%d<-%d", season, anchor_season)], collapse = " "), cur$anchors[, all(anchor_season < season & anchor_season != 2020)])
# FBS credit from FCS opponents at the final cutoff (Stage 3 effect)
nfo <- rbindlist(lapply(C2_SPEC$seasons, function(y) { g <- d$games[[as.character(y)]][final == TRUE]; ids <- fbs_ids(d$sch[[as.character(y)]])
  r <- rbind(g[, .(team_id = home_id, opp = away_id)], g[, .(team_id = away_id, opp = home_id)])[team_id %in% ids]; r[, .(season = y, n_fcs = sum(!opp %in% ids)), by = team_id] }))
fin <- fb[, .SD[cutoff == max(cutoff)], by = season]; fin <- merge(fin, nfo, by = c("season", "team_id"))
cr <- fin[season %in% R15C$dev, .(change_vs_frozen = mean(power - p0)), by = .(n_fcs_opponents = pmin(n_fcs, 2))][order(n_fcs_opponents)]
add("final-cutoff FBS rating change by FCS opponents (dev)", "EXPECTED Stage 3 credit correction (+0.65 / -0.11 / -0.70)", paste(sprintf("%d:%+.2f", cr$n_fcs_opponents, cr$change_vs_frozen), collapse = " "),
    isTRUE(all.equal(cr$change_vs_frozen, c(0.645736223530796, -0.107676761851293, -0.697489512890283), tolerance = 1e-9)))
res <- rbindlist(chk); print(res); fwrite(res, file.path(VAL, "regression_checks.csv")); stopifnot(all(res$pass)); cat("REGRESSION PASSED: no unexpected difference from frozen C2\n")
