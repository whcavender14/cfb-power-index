# Round 15 design probe 03: can the Tier A roster variables be reconstructed without look-ahead, and do vendor
# values get revised after the fact? Uses the probe-02 cache and the frozen 2026-09-10 pulls. No API calls.
# No outcome data is read: nothing here relates a variable to game results.
# Usage (repo root, after 02): Rscript scripts/round15/03_probe_reconstruction.R
source("config/paths.R")
suppressPackageStartupMessages(library(data.table))
raw <- "output/dev/round15/raw"; out <- "docs/round15/coverage"
rd <- function(n) { f <- file.path(raw, n); if (!file.exists(f)) return(data.table()); x <- readRDS(f); if (!NROW(x)) data.table() else as.data.table(x) }
res <- list(); add <- function(block, season, metric, value) res[[length(res) + 1]] <<- data.table(block, season, metric, value = as.numeric(value))
bak6 <- "/Users/willcavender/Desktop/CFB Modeling Backup/CFB-Modeling-round6/outputs/round6/raw"

sched <- rbindlist(lapply(2013:2026, function(y) { f <- if (y >= 2015) file.path(PATHS$frozen, "cfb_data_v3", sprintf("raw_schedule_%d.rds", y)) else file.path(bak6, sprintf("raw_schedule_%d.rds", y))
  g <- as.data.table(readRDS(f)); rbind(g[, .(season = y, id = as.integer(home_id), team = home_team, div = home_division)], g[, .(season = y, id = as.integer(away_id), team = away_team, div = away_division)]) }))
idmap <- unique(sched[, .(id, team)]); fbs <- unique(sched[div == "fbs", .(season, team, id)])

# A. Knowledge-date checks: frozen pull (2026-09-10) vs fresh pull (2026-09-24)
tal0 <- as.data.table(readRDS(file.path(PATHS$frozen, "cfb_data_v2/talent_2014_2026.rds")))[, team_id := as.integer(team_id)]
por0 <- as.data.table(readRDS(file.path(PATHS$frozen, "cfb_data_v2/portal_2014_2026.rds")))
for (y in 2024:2026) {
  t1 <- rd(sprintf("talent_year%d.rds", y)); t1[, team_id := idmap$id[match(team, idmap$team)]]
  m <- merge(tal0[season == y, .(team_id, v0 = talent_composite)], t1[!is.na(team_id), .(team_id, v1 = talent)], by = "team_id")
  add("talent_frozen_sdv_vs_cfbd_api", y, "teams_matched", nrow(m)); add("talent_frozen_sdv_vs_cfbd_api", y, "median_ratio_api_over_frozen", median(m$v1 / m$v0))
  add("talent_frozen_sdv_vs_cfbd_api", y, "pearson", cor(m$v0, m$v1)); add("talent_frozen_sdv_vs_cfbd_api", y, "spearman", cor(m$v0, m$v1, method = "spearman"))
  p1 <- rd(sprintf("player_portal_year%d.rds", y)); p0 <- por0[season == y]
  k0 <- p0[, paste(first_name, last_name, origin, position, as.Date(transfer_date))]; k1 <- p1[, paste(firstName, lastName, origin, position, as.Date(transferDate))]
  add("revision_portal", y, "rows_frozen", length(k0)); add("revision_portal", y, "rows_fresh", length(k1))
  add("revision_portal", y, "rows_only_in_fresh", sum(!k1 %in% k0)); add("revision_portal", y, "rows_only_in_frozen", sum(!k0 %in% k1))
  j <- merge(p0[, .(k = k0, d0 = destination, r0 = rating, s0 = stars)][!duplicated(k)], p1[, .(k = k1, d1 = destination, r1 = rating, s1 = stars)][!duplicated(k)], by = "k")
  add("revision_portal", y, "destination_changed", j[, sum(!identical(d0, d1) & (is.na(d0) != is.na(d1) | (!is.na(d0) & !is.na(d1) & d0 != d1)))])
  add("revision_portal", y, "destination_filled_since_frozen", j[, sum(is.na(d0) & !is.na(d1))])
  add("revision_portal", y, "rating_changed", j[, sum(xor(is.na(r0), is.na(r1)) | (!is.na(r0) & !is.na(r1) & abs(r0 - r1) > 1e-6))])
}
ret0 <- as.data.table(readRDS(file.path(PATHS$frozen, "cfb_data_v2/returning_2014_2026.rds")))[, team_id := as.integer(team_id)]
for (y in 2014:2026) { r1 <- rd(sprintf("player_returning_year%d.rds", y)); if (!nrow(r1)) next
  r1[, team_id := idmap$id[match(team, idmap$team)]]
  m <- merge(ret0[season == y, .(team_id, v0 = off_returning)], r1[!is.na(team_id), .(team_id, v1 = percentPPA)], by = "team_id")[is.finite(v0) & is.finite(v1)]
  add("off_returning_frozen_sdv_vs_cfbd_api", y, "teams", nrow(m)); add("off_returning_frozen_sdv_vs_cfbd_api", y, "pearson", cor(m$v0, m$v1))
  add("off_returning_frozen_sdv_vs_cfbd_api", y, "share_abs_diff_gt_0.05", mean(abs(m$v1 - m$v0) > 0.05)) }

# B-F. Player-ID reconstruction
# Roster `year` holds the class year (0-6); when the class is unknown it holds the season instead.
ros <- rbindlist(lapply(2014:2026, function(y) rd(sprintf("roster_year%d_classificationfbs.rds", y))[, .(season = y, class = fifelse(year <= 6L, year, NA_integer_), id = as.character(id), team, position, recruitIds)]))
pas <- rbindlist(lapply(2014:2026, function(y) rd(sprintf("stats_player_season_year%d_categorypassing.rds", y))), fill = TRUE)
pas <- pas[statType == "ATT", .(season, id = as.character(playerId), player, team, att = as.numeric(stat))]
def <- rbindlist(lapply(2014:2026, function(y) rd(sprintf("stats_player_season_year%d_categorydefensive.rds", y))), fill = TRUE)
def <- def[statType == "TOT", .(season, id = as.character(playerId), team, tot = as.numeric(stat))]
dra <- rd("draft_picks_all.rds")[, .(season = year, id = as.character(collegeAthleteId))]
rec <- rbindlist(lapply(2010:2026, function(y) rd(sprintf("recruiting_players_year%d.rds", y))[, .(rid = as.character(id), rating, stars)]))
for (y in 2014:2026) { r <- ros[season == y]; add("roster_ids", y, "negative_or_missing_id_share", mean(is.na(r$id) | startsWith(r$id, "-")))
  add("roster_ids", y, "class_year_known_share", mean(!is.na(r$class)))
  rr <- unlist(r$recruitIds); add("roster_recruit_link", y, "players_with_recruit_match_share", mean(vapply(r$recruitIds, function(v) length(v) > 0 && any(as.character(v) %in% rec$rid), TRUE))) }

for (y in 2015:2026) {
  prev <- pas[season == y - 1 & team %in% fbs[season == y - 1, team]]
  lead <- prev[order(-att)][, .(id = id[1], att1 = att[1], share = att[1] / sum(att)), by = team]
  now <- ros[season == y]; own <- now[, .(team_now = team), by = id]
  lead[, on_same := mapply(function(i, t) any(now$id == i & now$team == t), id, team)]
  lead[, on_other := !on_same & id %in% now$id]
  lead[, drafted := id %in% dra[season == y, id]]
  add("qb_continuity", y, "fbs_teams", nrow(lead)); add("qb_continuity", y, "leader_id_positive_share", mean(!startsWith(lead$id, "-")))
  add("qb_continuity", y, "leader_clear_starter_share_ge_0.6", mean(lead$share >= 0.6))
  add("qb_continuity", y, "leader_on_same_roster", mean(lead$on_same)); add("qb_continuity", y, "leader_on_other_fbs_roster", mean(lead$on_other))
  add("qb_continuity", y, "leader_drafted_april", mean(lead$drafted & !lead$on_same)); add("qb_continuity", y, "leader_not_found", mean(!lead$on_same & !lead$on_other & !lead$drafted))
  lead[, class_prev := ros[season == y - 1][match(lead$id, id), class]]
  add("qb_continuity", y, "leader_prev_class_known_share", mean(!is.na(lead$class_prev)))
  add("qb_continuity", y, "not_found_with_prev_class_ge4_share", lead[!on_same & !on_other & !drafted, mean(class_prev >= 4, na.rm = TRUE)])
  qb_in <- prev[att >= 100][, .(id, from = team)][now[, .(id, to = team)], on = "id", nomatch = 0][from != to]
  add("qb_continuity", y, "fbs_qbs_100att_moved_fbs_team", nrow(qb_in))
  a <- ros[season == y - 1 & !startsWith(id, "-"), .(id, t0 = team)]; b <- ros[season == y & !startsWith(id, "-"), .(id, t1 = team)]
  mv <- merge(a[!duplicated(id)], b[!duplicated(id)], by = "id")[t0 != t1]
  add("transfers_roster_id", y, "fbs_to_fbs_moves", nrow(mv)); add("transfers_roster_id", y, "teams_receiving", uniqueN(mv$t1))
  if (y >= 2021) { po <- por0[season == y & !is.na(destination)]; add("transfers_roster_id", y, "portal_fbs_dest_events", po[destination %in% fbs[season == y, team] & origin %in% fbs[season == y - 1, team], .N]) }
  dprev <- def[season == y - 1 & team %in% fbs[season == y - 1, team]]
  if (nrow(dprev)) { dprev[, back := mapply(function(i, t) any(now$id == i & now$team == t), id, team)]
    dr <- dprev[, .(def_ret = sum(tot[back]) / sum(tot)), by = team]; dr[, team_id := idmap$id[match(team, idmap$team)]]
    add("def_returning_reconstructed", y, "fbs_team_share", nrow(dr) / fbs[season == y - 1, uniqueN(team)])
    m <- merge(dr, ret0[season == y, .(team_id, v0 = def_returning)], by = "team_id")[is.finite(v0)]
    add("def_returning_reconstructed", y, "teams_with_vendor_value", nrow(m)); add("def_returning_reconstructed", y, "corr_with_vendor", if (nrow(m) > 10) cor(m$def_ret, m$v0) else NA) }
}

# G. 2025 play-text change (why passer names stop parsing)
p <- as.data.table(readRDS(file.path(bak6, "plays_2025.rds")))
db <- p[play_type %in% c("Pass Reception", "Pass Incompletion", "Sack", "Passing Touchdown", "Interception", "Pass Interception Return")]
bad <- db[!grepl("^[A-Z][-A-Za-z.' ]+ (pass |sacked)", play_text)]
bad[, stat_crew_format := grepl("#[0-9]+ [A-Z][-A-Za-z.' ]+ (pass |sacked)", play_text)]
add("plays_2025_passer", 2025, "old_format_unparsed_share", nrow(bad) / nrow(db))
add("plays_2025_passer", 2025, "unparsed_by_either_format_share", bad[, sum(!stat_crew_format)] / nrow(db))
pat <- bad[, .N, by = .(pattern = sub("^(\\S+ \\S+ \\S+).*", "\\1", gsub("[A-Z][a-z]+", "Name", play_text)))][order(-N)][1:8]
fwrite(pat, file.path(out, "plays_2025_unparsed_passer_patterns.csv"))
wk <- bad[, .(N = .N, N_either = sum(!stat_crew_format)), by = wk]; tot <- db[, .(n = .N), by = wk]
wk <- merge(tot, wk, by = "wk", all.x = TRUE)[is.na(N), `:=`(N = 0L, N_either = 0L)][, `:=`(share_old_format_unparsed = round(N / n, 3), share_unparsed_either = round(N_either / n, 3))]
fwrite(wk, file.path(out, "plays_2025_unparsed_passer_by_week.csv"))

# H. Portal timing (no commitment date exists; destination is recorded post hoc)
por0[, m := format(as.Date(transfer_date), "%m")]
for (y in 2021:2026) { x <- por0[season == y]; for (mm in c("12", "01", "04", "05")) add("portal_entry_month", y, paste0("share_month_", mm), mean(x$m == mm)) }

long <- rbindlist(res); fwrite(long, file.path(out, "reconstruction_long.csv"))
wide <- dcast(long, block + metric ~ season, value.var = "value", fun.aggregate = function(v) v[1])
num <- setdiff(names(wide), c("block", "metric"))
wide[, (num) := lapply(.SD, function(v) ifelse(abs(v) < 1 & v != 0, round(v, 3), round(v, 1))), .SDcols = num]
fwrite(wide, file.path(out, "reconstruction_matrix.csv"))
print(wide, nrows = 200, width = 250); print(pat); print(wk)
