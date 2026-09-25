# Round 15 P4 diagnostic (REPORT ONLY; changes no definition or verdict). Why does cont_def disagree with the vendor
# def_returning after 2021? The signed cont_def counts transfers-in production; the vendor figure does not. This recomputes
# the same machinery with own-team production only (players who were on team i in y-1 and are on its y roster, not drafted).
source("config/paths.R"); suppressPackageStartupMessages({ library(data.table); source("R/round15/prep/reconstruct.R") })
raw <- "output/dev/round15/raw"; rd <- function(n) { f <- file.path(raw, n); if (!file.exists(f)) data.table() else as.data.table(readRDS(f)) }
tab <- fread("output/dev/round15/prep/preseason_inputs_2014_2026.csv")
draft <- rd("draft_picks_all.rds")
own <- rbindlist(lapply(2017:2026, function(y) { t <- rd(sprintf("stats_player_season_year%d_categorydefensive.rds", y - 1))
  p <- t[statType == "TOT", .(value = sum(as.numeric(stat), na.rm = TRUE)), by = .(id = as.character(playerId), team)]
  r <- unique(rd(sprintf("roster_year%d_classificationfbs.rds", y))[, .(id = as.character(id), team)])
  dr <- as.character(draft[year == y, collegeAthleteId])
  den <- p[, .(den = sum(value)), by = team]
  num <- merge(p, r[!id %in% dr], by = c("id", "team"))[, .(num = sum(value)), by = team]
  x <- merge(den, num, by = "team", all.x = TRUE)[is.na(num), num := 0][, .(season = y, team, own_only = num / den)] }))
ven <- as.data.table(readRDS(file.path(PATHS$frozen, "cfb_data_v2/returning_2014_2026.rds")))[, .(season, team_id = as.integer(team_id), vendor_def = def_returning)]
d <- merge(merge(tab[, .(season, team_id, team, cont_def)], own, by = c("season", "team")), ven, by = c("season", "team_id"))[is.finite(vendor_def) & is.finite(cont_def)]
res <- rbind(d[, .(scope = "pooled", n = .N, r_signed_cont_def = cor(cont_def, vendor_def), r_own_team_only = cor(own_only, vendor_def),
                   mean_transfer_in_share = mean(cont_def - pmin(own_only, 1.5)))],
             d[, .(scope = as.character(season[1]), n = .N, r_signed_cont_def = cor(cont_def, vendor_def), r_own_team_only = cor(own_only, vendor_def),
                   mean_transfer_in_share = mean(cont_def - pmin(own_only, 1.5))), by = season][, !"season"])
fwrite(res, "docs/round15/prep/p4_diag_def_agreement_REPORT_ONLY.csv"); print(res, digits = 3)
