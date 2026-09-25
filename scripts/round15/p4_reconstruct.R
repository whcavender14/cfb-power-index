# Round 15 P4 (predeclaration §4.3): build the preseason input table for seasons 2014-2026 (§4.1 definitions) and check it.
# Pass rule: unit tests pass (tests/round15/test_reconstruct.R), coverage reported by season, and reconstructed defensive
# continuity agrees with the vendor figure where both exist (pooled Pearson r >= 0.8).
# Inputs: frozen schedules, backup 2013-14 schedules, cached CFBD pulls (probe 02, P1), frozen coaches/returning files.
# No outcome of any target season is read; y-1 end-of-season ratings are prior-season inputs by definition.
# Usage (repo root): Rscript scripts/round15/p4_reconstruct.R
source("config/paths.R"); source("config/production.R")
suppressPackageStartupMessages({ source(PATHS$model_ops); library(data.table); source("R/round15/prep/reconstruct.R") })
raw <- "output/dev/round15/raw"; prep <- "output/dev/round15/prep"; out <- "docs/round15/prep"
bak6 <- "/Users/willcavender/Desktop/CFB Modeling Backup/CFB-Modeling-round6/outputs/round6/raw"
rd <- function(n) { f <- file.path(raw, n); if (!file.exists(f)) return(data.table()); x <- readRDS(f); if (!NROW(x)) data.table() else as.data.table(x) }
sched <- function(y) { if (y >= 2015) return(v4_schedule(y)); cfg <- v4_config(); cfg$cache_dir <- bak6; cfg$source_cache <- bak6; read_schedule(y, cfg, FALSE) }
Y <- 2013:2026; S <- setNames(lapply(Y, sched), Y)
fbs <- function(y) { g <- S[[as.character(y)]]; unique(rbind(data.table(team_id = g$home_id[g$home_fbs], team = g$home_team[g$home_fbs]),
                                                              data.table(team_id = g$away_id[g$away_fbs], team = g$away_team[g$away_fbs]))) }
hist <- as.data.table(v4_history(S[as.character(2013:2025)]))[, .(season, team_id, eff_off, eff_def)]
classes <- rd("recruiting_teams_all.rds"); recruits <- rbindlist(lapply(2010:2026, function(y) rd(sprintf("recruiting_players_year%d.rds", y))), fill = TRUE)
coaches <- as.data.table(readRDS(file.path(PATHS$frozen, "cfb_data_v2/coaches_1989_2026.rds")))
draft <- rd("draft_picks_all.rds")

tab <- rbindlist(lapply(2014:2026, function(y) {
  F <- fbs(y); Fp <- fbs(y - 1)$team
  st <- function(cat) rd(sprintf("stats_player_season_year%d_category%s.rds", y - 1, cat))
  roster <- rd(sprintf("roster_year%d_classificationfbs.rds", y))
  dr <- as.character(draft[year == y, collegeAthleteId])
  att <- r15_prod(st("passing"), "ATT", Fp)
  skill <- rbind(r15_prod(st("rushing"), "YDS", Fp), r15_prod(st("receiving"), "YDS", Fp))[, .(value = sum(value)), by = .(id, team)]
  tck <- r15_prod(st("defensive"), "TOT", Fp)
  x <- F[, .(season = y, team_id, team, promoted = as.numeric(!team %in% Fp))]
  x <- merge(x, setnames(r15_continuity(att, roster, dr, F$team), "cont", "cont_pass"), by = "team")
  x <- merge(x, setnames(r15_continuity(skill, roster, dr, F$team), "cont", "cont_skill"), by = "team")
  x <- merge(x, setnames(r15_continuity(tck, roster, dr, F$team), "cont", "cont_def"), by = "team")
  if (!nrow(tck)) x[, cont_def := NA_real_]
  x <- merge(x, r15_qb_xfer_in(att, roster, F$team), by = "team")
  x <- merge(x, r15_talent4(classes, y, F$team), by = "team")
  x <- merge(x, r15_bluechip4(recruits, y, F$team), by = "team")
  g <- S[[as.character(y)]]; k1 <- min(g$kickoff[g$home_fbs | g$away_fbs])
  x <- merge(x, r15_coach(coaches, y, k1), by = "team_id", all.x = TRUE)
  l1 <- hist[season == y - 1, .(team_id, last_off = eff_off, last_def = eff_def)]; l2 <- hist[season == y - 2, .(team_id, two_off = eff_off, two_def = eff_def)]
  x <- merge(merge(x, l1, by = "team_id", all.x = TRUE), l2, by = "team_id", all.x = TRUE)
  mem <- as.data.table(v5_membership(g))[, .(team_id, conf)]
  x <- merge(x, r15_conf_level(mem[team_id %in% F$team_id], hist[season == y - 1, .(team_id, eff_off, eff_def)]), by = "team_id", all.x = TRUE)
  x
}), fill = TRUE)
setcolorder(tab, c("season", "team_id", "team", "promoted", "last_off", "last_def", "two_off", "two_def", "cont_pass", "cont_skill", "cont_def",
                   "qb_xfer_in", "talent4", "bluechip4", "new_hc", "log_tenure", "conf_off", "conf_def"))
setorder(tab, season, team)
f_tab <- file.path(prep, "preseason_inputs_2014_2026.csv"); fwrite(tab, f_tab)

vars <- setdiff(names(tab), c("season", "team_id", "team"))
cov <- tab[, c(list(fbs_teams = .N), lapply(.SD, function(v) round(mean(!is.na(v)), 3))), by = season, .SDcols = vars]
rng <- rbindlist(lapply(vars, function(v) data.table(variable = v, min = min(tab[[v]], na.rm = TRUE), median = median(tab[[v]], na.rm = TRUE), max = max(tab[[v]], na.rm = TRUE))))
ven <- as.data.table(readRDS(file.path(PATHS$frozen, "cfb_data_v2/returning_2014_2026.rds")))[, .(season, team_id = as.integer(team_id), vendor_def = def_returning)]
# [Amendment 01 A2] validation target = returning-player component cont_def_own (the vendor's concept); cont_def is unchanged
own <- rbindlist(lapply(2017:2026, function(y) { F <- fbs(y)
  tck <- r15_prod(rd(sprintf("stats_player_season_year%d_categorydefensive.rds", y - 1)), "TOT", fbs(y - 1)$team)
  merge(F, r15_continuity_own(tck, rd(sprintf("roster_year%d_classificationfbs.rds", y)), as.character(draft[year == y, collegeAthleteId]), F$team), by = "team")[, season := y] }))
dd <- merge(merge(tab[, .(season, team_id, cont_def)], own[, .(season, team_id, cont_def_own = cont_own)], by = c("season", "team_id")), ven, by = c("season", "team_id"))[is.finite(cont_def_own) & is.finite(vendor_def)]
agree <- rbind(dd[, .(scope = "pooled", n = .N, r_amended_own = cor(cont_def_own, vendor_def), r_original_full = cor(cont_def, vendor_def, use = "complete.obs"))],
               dd[, .(scope = as.character(season[1]), n = .N, r_amended_own = cor(cont_def_own, vendor_def), r_original_full = cor(cont_def, vendor_def, use = "complete.obs")), by = season][, !"season"])
tests <- system2("Rscript", "tests/round15/test_reconstruct.R", stdout = TRUE, stderr = TRUE)
tests_ok <- any(grepl("checks passed", tests)) && !any(grepl("^FAIL|Error|Erreur", tests))
v <- data.table(step = "P4 (amended A2)", rule = "unit tests pass; coverage reported; pooled r(cont_def_own, vendor def_returning) >= 0.8 (cont_def unchanged)",
                tests_pass = tests_ok, def_agreement_r = agree[scope == "pooled", r_amended_own], def_agreement_n = agree[scope == "pooled", n],
                season_range = sprintf("%.3f-%.3f", min(agree[scope != "pooled", r_amended_own]), max(agree[scope != "pooled", r_amended_own])),
                original_full_r = agree[scope == "pooled", r_original_full],
                nmsu_2021_continuity = tab[season == 2021 & team == "New Mexico State", paste(is.na(cont_pass), is.na(cont_skill), is.na(cont_def))],
                table_sha256 = digest::digest(file = f_tab, algo = "sha256"), rows = nrow(tab))
v[, pass := tests_pass & def_agreement_r >= 0.8]
fwrite(cov, file.path(out, "p4_coverage_by_season.csv")); fwrite(rng, file.path(out, "p4_ranges.csv")); fwrite(agree, file.path(out, "p4_def_continuity_agreement_amended.csv"))
writeLines(tests, file.path(out, "p4_test_output.txt")); fwrite(v, file.path(out, "p4_verdict_amended.csv"))
print(cov, width = 250); print(rng); print(agree); print(v)
