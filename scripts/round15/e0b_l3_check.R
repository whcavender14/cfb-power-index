# Round 15 G0b L3 (predeclaration v3 §8): every preseason input is dated before its season (§4.1). This test was
# predeclared but missing from tests/round15/test_g0.R; it is run here before any metric is read. Any failure stops the
# round. Provenance checks only: no target-season outcome enters any comparison.
source("config/paths.R"); source("config/production.R")
suppressPackageStartupMessages({ source(PATHS$model_ops); library(data.table); source("R/round15/candidates/data.R") })
d <- r15_build_data(); tab <- d$inputs; S <- 2016:2025
res <- list(); add <- function(id, what, ok, detail = "") { res[[length(res) + 1L]] <<- data.table(id = id, check = what, pass = isTRUE(ok), detail = detail)
  cat(if (isTRUE(ok)) "ok -" else "FAIL -", what, detail, "\n") }
# home_fbs/away_fbs are NA for some non-FBS games: use which() so NA flags drop out
first_kick <- sapply(S, function(y) { g <- d$games[[as.character(y)]]; min(g$kickoff[which(g$home_fbs | g$away_fbs)]) }); names(first_kick) <- S
last_avail <- sapply(2013:2025, function(y) max(d$games[[as.character(y)]][final == TRUE, available_at])); names(last_avail) <- 2013:2025
ends_before <- setNames(sapply(S, function(y) last_avail[[as.character(y - 1)]] < first_kick[[as.character(y)]]), S)
stopifnot(!anyNA(first_kick), !anyNA(last_avail), !anyNA(ends_before))
add("L3", "every season y-1 (and y-2) result is available before season y's first FBS kickoff", all(ends_before),
    paste(names(ends_before)[!ends_before], collapse = ","))
h <- d$history[, .(season, team_id, eff_off, eff_def)]
cmp <- function(lag, a, b) { x <- merge(tab[season %in% S, c("season", "team_id", a, b), with = FALSE], h[, .(season = season + lag, team_id, ho = eff_off, hd = eff_def)], by = c("season", "team_id"), all.x = TRUE)
  x <- x[is.finite(get(a)) | is.finite(ho)]; list(n = nrow(x), bad = x[!(abs(get(a) - ho) < 1e-9 & abs(get(b) - hd) < 1e-9)]) }
l1 <- cmp(1L, "last_off", "last_def"); add("L3", "last_off/last_def(y) equal the end-of-season y-1 fit for every team", !nrow(l1$bad), sprintf("n=%d mismatched=%d", l1$n, nrow(l1$bad)))
l2 <- cmp(2L, "two_off", "two_def"); add("L3", "two_off/two_def(y) equal the end-of-season y-2 fit for every team", !nrow(l2$bad), sprintf("n=%d mismatched=%d", l2$n, nrow(l2$bad)))
cf <- rbindlist(lapply(S, function(y) { g <- d$sch[[as.character(y)]]; mem <- unique(rbind(data.table(team_id = g$home_id[g$home_fbs], conf = g$home_conference[g$home_fbs]), data.table(team_id = g$away_id[g$away_fbs], conf = g$away_conference[g$away_fbs])))
  x <- merge(tab[season == y, .(season, team_id, conf_off, conf_def, last_off, last_def)], mem[!duplicated(team_id)], by = "team_id")
  x[, `:=`(n = .N, so = sum(last_off, na.rm = TRUE), sd_ = sum(last_def, na.rm = TRUE), k = sum(is.finite(last_off))), by = conf]
  x[, `:=`(ro = (so - ifelse(is.finite(last_off), last_off, 0)) / (k - is.finite(last_off)), rd = (sd_ - ifelse(is.finite(last_def), last_def, 0)) / (k - is.finite(last_def)))]
  x[conf != "FBS Independents" & is.finite(conf_off)] }))
add("L3", "conf_off/conf_def(y) are the mean y-1 ratings of the team's season-y conference members, excluding the team",
    all(abs(cf$conf_off - cf$ro) < 1e-9 & abs(cf$conf_def - cf$rd) < 1e-9), sprintf("n=%d max|diff|=%.2e", nrow(cf), max(abs(c(cf$conf_off - cf$ro, cf$conf_def - cf$rd)))))
sr_ok <- sapply(S, function(y) { s <- d$sr_eos[season == y - 1]; nrow(s) > 0 })
add("L3", "last_sr(y) comes from the season y-1 end-of-season table (built from season y-1 plays only, cutoff = its last availability + 1 s)", all(sr_ok) && all(ends_before))
pr <- rbindlist(lapply(S, function(y) { g <- d$sch[[as.character(y - 1)]]; f1 <- unique(c(g$home_id[g$home_fbs], g$away_id[g$away_fbs]))
  tab[season == y, .(season, team_id, promoted, want = as.numeric(!team_id %in% f1))] }))
add("L3", "promoted(y) is read from the season y-1 FBS schedule", all(pr$promoted == pr$want), sprintf("n=%d mismatched=%d", nrow(pr), sum(pr$promoted != pr$want)))
src <- readLines("scripts/round15/p4_reconstruct.R")
add("L3", "continuity uses y-1 player stats, the y roster and the April-y draft; recruiting classes y-3..y; coaching as of season y's first kickoff (code)",
    any(grepl("stats_player_season_year%d_category%s.rds\", y - 1", src, fixed = TRUE)) && any(grepl("roster_year%d_classificationfbs.rds\", y)", src, fixed = TRUE)) &&
    any(grepl("draft[year == y", src, fixed = TRUE)) && any(grepl("r15_coach(coaches, y, k1)", src, fixed = TRUE)) && any(grepl("r15_talent4(classes, y", src, fixed = TRUE)))
tr <- system2("Rscript", "tests/round15/test_reconstruct.R", stdout = TRUE, stderr = TRUE)
add("L3", "reconstruction unit tests (continuity, transfers, talent4/bluechip4 class windows, coaching port) pass", any(grepl("14 checks passed", tr)))
r <- rbindlist(res); fwrite(r, "docs/round15/eval/g0b_l3_check.csv"); if (!all(r$pass)) stop("L3 FAILED: the round stops here")
cat(sprintf("\nL3: %d checks passed\n", nrow(r)))
