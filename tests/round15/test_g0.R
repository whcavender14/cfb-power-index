# Round 15 G0b/G0c integrity and leakage tests (predeclaration v2 §8). Reads no development metric.
# Run from the repo root after the c1/c2/c3 builds: Rscript tests/round15/test_g0.R
source("config/paths.R"); source("config/production.R")
suppressPackageStartupMessages({ source(PATHS$model_ops); library(data.table); for (f in c("data", "c1", "c2", "c3", "tune")) source(sprintf("R/round15/candidates/%s.R", f)) })
n <- 0L; res <- list()
check <- function(ok, id, what) { res[[length(res) + 1]] <<- data.table(id = id, check = what, pass = isTRUE(ok)); if (!isTRUE(ok)) stop("FAIL: ", id, " ", what, call. = FALSE); n <<- n + 1L; cat("ok -", id, what, "\n") }
out <- R15C$cache; d0 <- r15_build_data(); c1 <- readRDS(file.path(out, "c1_components.rds")); c2 <- readRDS(file.path(out, "c2_components.rds")); c3t <- readRDS(file.path(out, "c3_tuning.rds"))
qz <- setNames(c3t$sel_q$selected, c3t$sel_q$target); qbz <- setNames(c3t$sel_qb$selected, c3t$sel_qb$target)
set.seed(15001)

# ---------------- L1 + L6: outcomes at/after the cutoff and all later seasons cannot move a prediction -------------------
Y <- 2019L; snaps <- Filter(function(sn) sn$season == Y, d0$base$snap); CUT <- snaps[[8]]$cutoff
scr <- function(x) x[sample.int(length(x))] + round(rnorm(length(x), 0, 7))
d <- d0
for (s in names(d$games)) { g <- copy(d$games[[s]]); late <- if (as.integer(s) > Y) rep(TRUE, nrow(g)) else if (as.integer(s) == Y) g$available_at >= CUT else rep(FALSE, nrow(g))
  if (any(late)) { g[late, `:=`(home_points = pmax(0L, as.integer(scr(home_points))), away_points = pmax(0L, as.integer(scr(away_points))))] }; d$games[[s]] <- g }
d$history <- copy(d0$history)[season >= Y, `:=`(eff_off = eff_off + rnorm(.N, 0, 5), eff_def = eff_def + rnorm(.N, 0, 5), hfa = hfa + rnorm(.N))]
late_g <- unlist(lapply(names(d0$games), function(s) { g <- d0$games[[s]]; if (as.integer(s) > Y) g$game_id else if (as.integer(s) == Y) g[available_at >= CUT, game_id] }))
d$pbp <- copy(d0$pbp)[game_id %in% late_g, `:=`(sr = runif(.N), fumbles = rpois(.N, 3), lost = rpois(.N, 1), passer = "Scrambled")]
d$sr_eos <- copy(d0$sr_eos)[season >= Y, `:=`(sr_off = sr_off + rnorm(.N, 0, .05), sr_def = sr_def + rnorm(.N, 0, .05))]
num <- setdiff(names(d0$inputs)[sapply(d0$inputs, is.numeric)], c("season", "team_id"))
d$inputs <- copy(d0$inputs); for (v in num) set(d$inputs, which(d$inputs$season > Y), v, d$inputs[[v]][d$inputs$season > Y] + rnorm(sum(d$inputs$season > Y)))
fr <- as.data.table(d0$base$frame); fr[(season == Y & cutoff >= CUT) | season > Y, actual_margin := round(rnorm(.N, 0, 20))]; d$base$frame <- as_tibble(fr)
e <- r15_bind_incumbent()
pri <- list(); for (z in c(2016L, 2017L, 2018L, Y)) pri[[as.character(z)]] <- r15_c1_prior(d, z, z - 1L, e)
vm <- r15_c1_variance(d, Y, pri); sc <- r15_scale(d, Y, pri, r15_H(d, Y))
eos <- setNames(lapply(2013:2025, function(s) r15_eos_full(d, s)), 2013:2025); p2 <- r15_c2_params(d, Y, eos); s2 <- r15_sigma2_row(d, Y)
check(isTRUE(all.equal(pri[[as.character(Y)]]$pre_off, c1$priors[[as.character(Y)]]$pre_off, tolerance = 1e-12)), "L1", "C1 prior for 2019 unchanged when 2019+ data are scrambled")
check(abs(vm$off$b - c1$varm[[as.character(Y)]]$off$b) < 1e-12 && abs(sc - c1$scl[[as.character(Y)]]) < 1e-9, "L1", "C1 variance model and prior scale for 2019 unchanged")
check(abs(p2$beta - c2$p2[[as.character(Y)]]$beta) < 1e-12 && abs(p2$kappa - c2$p2[[as.character(Y)]]$kappa) < 1e-10 && isTRUE(all.equal(p2$mu, c2$p2[[as.character(Y)]]$mu)), "L1", "C2 beta, kappa and FCS moments for 2019 unchanged")
lam <- r15_c1_lambda(pri[[as.character(Y)]], vm, c1$lam0[[as.character(Y)]]); H <- r15_H(d, Y); key <- format(CUT, "%Y-%m-%d")
dsub <- d; dsub$base$snap <- Filter(function(sn) sn$season == Y && sn$cutoff <= CUT, d$base$snap)
p_1 <- r15_predict_season_c1(dsub, Y, pri[[as.character(Y)]], sc, lam, H)[cutoff == key]
p_2 <- r15_predict_season_c2(dsub, Y, pri[[as.character(Y)]], sc, lam, H, p2, list(off = vm$off$vbar, def = vm$def$vbar), c1$lam0[[as.character(Y)]], eos, c2$om[[as.character(Y)]])[cutoff == key]
p_3 <- r15_predict_season_c3(dsub, Y, pri[[as.character(Y)]], sc, lam, H, p2, list(off = vm$off$vbar, def = vm$def$vbar), c1$lam0[[as.character(Y)]], eos, c2$om[[as.character(Y)]], qz[[as.character(Y)]], qbz[[as.character(Y)]], s2)[cutoff == key]
for (k in 1:3) { ref <- fread(file.path(out, sprintf("c%d_predictions.csv", k)), colClasses = list(character = "game_id"))
  p <- list(p_1, p_2, p_3)[[k]]; m <- merge(p, ref[, .(game_id, r = pred_margin)], by = "game_id")
  check(nrow(m) == nrow(p) && nrow(m) > 0 && max(abs(m$pred_margin - m$r)) < 1e-9, "L1",
        sprintf("C%d predictions at a mid-2019 cutoff unchanged when later 2019 results and all later seasons are scrambled (%d games)", k, nrow(m))) }
check(all(sapply(2017:2022, function(y) all(r15_Z(y) < y))) && !any(unlist(lapply(2017:2022, r15_Z)) == 2020), "L6", "every inner-tuning set Z(y) is strictly before y and excludes 2020")

# ---------------- L6: 2023-2025 parameters are frozen through 2022 -------------------------------------------------------
d6 <- d0; for (s in as.character(2023:2025)) { g <- copy(d6$games[[s]]); g[, `:=`(home_points = pmax(0L, as.integer(scr(home_points))), away_points = pmax(0L, as.integer(scr(away_points))))]; d6$games[[s]] <- g }
d6$history <- copy(d0$history)[season >= 2023, eff_off := eff_off + 9]
fr6 <- as.data.table(d0$base$frame)[season >= 2023, actual_margin := -actual_margin]; d6$base$frame <- as_tibble(fr6)
pri6 <- c1$priors; pri6[["2023"]] <- r15_c1_prior(d6, 2023L, 2022L, e)
check(isTRUE(all.equal(pri6[["2023"]]$pre_off, c1$priors[["2023"]]$pre_off, tolerance = 1e-12)) && abs(r15_scale(d6, 2023L, pri6, R15C$frozen_hfa) - c1$scl[["2023"]]) < 1e-9, "L6", "2023+ prior and scale use training data through 2022 only")
eos6 <- setNames(lapply(2013:2025, function(s) r15_eos_full(d6, s)), 2013:2025); p26 <- r15_c2_params(d6, 2023L, eos6)
check(abs(p26$kappa - c2$p2[["2023"]]$kappa) < 1e-10 && abs(p26$beta - c2$p2[["2023"]]$beta) < 1e-12 && abs(r15_sigma2_row(d6, 2023L) - r15_sigma2_row(d0, 2023L)) < 1e-9, "L6", "2023+ C2/C3 parameters use training data through 2022 only")

# ---------------- L2: no training row at or after its cutoff (asserted inside every predict function) ------------------
src <- unlist(lapply(c("c1", "c2", "c3"), function(f) readLines(sprintf("R/round15/candidates/%s.R", f))))
check(sum(grepl("stopifnot\\(all\\((sn\\$tg|rows)\\$available_at < sn\\$cutoff\\)\\)", src)) >= 3, "L2", "each candidate asserts every training row is available before its cutoff")
check(all(d0$games[["2019"]][available_at <= kickoff, .N] == 0), "L2", "result availability is kickoff + 24 h for every game")

# ---------------- L4: market isolation; L5: no vendor EPA/WP/ratings -----------------------------------------------------
cand_src <- unlist(lapply(c(list.files("R/round15/candidates", full.names = TRUE), list.files("R/round15/prep", full.names = TRUE),
                            list.files("scripts/round15", "^(c[0-9]|p[1-4]|a3)", full.names = TRUE)), readLines))
check(!any(grepl("market_lines|betting_lines|market_raw|PATHS\\$market|/lines", cand_src)), "L4", "no candidate or preparation code references market data")
vend <- "(?i)(^|_)(ppa|epa|wpa|wp|elo)($|_)|win_?prob|spread|odds|moneyline|sp_|fpi"
check(!any(grepl(vend, c(names(d0$pbp), names(d0$inputs), names(d0$sr_eos), unlist(lapply(d0$games, names))), perl = TRUE)), "L5", "no vendor EPA/WP/Elo/rating or market column in any candidate input")
check(inherits(tryCatch(r15_matrix_guard(data.frame(season = 1, team_id = 1, home_spread = 1), "talent4"), error = function(e) e), "error") &&
      inherits(tryCatch(r15_matrix_guard(data.frame(season = 1, team_id = 1, x = 1), "home_pregame_elo"), error = function(e) e), "error"), "L5", "the prior's matrix guard rejects market and vendor columns")

# ---------------- G0c: manifests verify ---------------------------------------------------------------------------------
for (k in 1:3) { m <- fread(sprintf("docs/round15/construction/c%d_manifest.csv", k))
  check(all(mapply(function(f, h) identical(digest::digest(file = f, algo = "sha256"), h), m$file, m$sha256)), "G0c", sprintf("C%d manifest hashes verify", k)) }
fwrite(rbindlist(res), "docs/round15/construction/g0b_g0c_tests.csv"); cat(sprintf("\n%d checks passed\n", n))
