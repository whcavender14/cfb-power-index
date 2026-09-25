# Round 15 P1 (predeclaration §4.3): pull the remaining inputs. Read-only CFBD GETs, cached write-once in the git-ignored
# output/dev/round15/raw/ (shared with probe 02, so already-cached seasons cost nothing).
#   rushing + receiving player season stats 2013-2026, passing 2013, FBS roster 2013, FCS schedules 2013-2025.
# Pass rule: every FBS team present in each season's rushing and receiving stats; FCS-vs-FCS coverage reported.
# Vendor columns (Elo, win probability) are dropped from the processed FCS schedule table. No outcome analysis.
# Usage (repo root): Rscript scripts/round15/p1_pull_data.R
source("config/paths.R"); source("R/round15/cfbd_client.R")
raw <- "output/dev/round15/raw"; prep <- "output/dev/round15/prep"; out <- "docs/round15/prep"
dir.create(prep, recursive = TRUE, showWarnings = FALSE)
cl <- cfbd_client(raw, max_calls = 70L)
bak6 <- "/Users/willcavender/Desktop/CFB Modeling Backup/CFB-Modeling-round6/outputs/round6/raw"
fbs_names <- function(y) { f <- if (y >= 2015) file.path(PATHS$frozen, "cfb_data_v3", sprintf("raw_schedule_%d.rds", y)) else file.path(bak6, sprintf("raw_schedule_%d.rds", y))
  g <- readRDS(f); unique(c(g$home_team[g$home_division == "fbs"], g$away_team[g$away_division == "fbs"])) }
res <- list(); add <- function(item, season, metric, value) res[[length(res) + 1]] <<- data.table(item, season, metric, value = as.numeric(value))

for (y in 2013:2026) for (cat in c("rushing", "receiving", if (y == 2013) "passing")) {
  s <- as.data.table(cl$get("/stats/player/season", list(year = y, category = cat)))
  F <- fbs_names(y)
  add(paste0("stats_", cat), y, "rows", nrow(s)); add(paste0("stats_", cat), y, "fbs_teams_missing", sum(!F %in% s$team))
  add(paste0("stats_", cat), y, "player_id_present_share", if (nrow(s)) mean(!is.na(s$playerId) & nzchar(as.character(s$playerId))) else 0)
}
r13 <- as.data.table(cl$get("/roster", list(year = 2013, classification = "fbs")))
add("roster", 2013, "players", nrow(r13)); add("roster", 2013, "fbs_teams_missing", sum(!fbs_names(2013) %in% r13$team))

vendor <- "(?i)elo|win_?prob|winprob|excitement|linescores|highlights"
fcs <- rbindlist(lapply(2013:2025, function(y) rbindlist(lapply(c("regular", "postseason"), function(st) {
  x <- cl$get("/games", list(year = y, seasonType = st, classification = "fcs")); if (!NROW(x)) return(NULL)
  x <- as.data.table(x); drop <- grep(vendor, names(x), perl = TRUE, value = TRUE)
  if (length(drop)) x[, (drop) := NULL]
  x[, .(game_id = as.character(id), season, week, season_type = seasonType, start_date = startDate, completed, neutral_site = neutralSite,
        home_id = homeId, home_team = homeTeam, home_division = homeClassification, home_conference = homeConference, home_points = homePoints,
        away_id = awayId, away_team = awayTeam, away_division = awayClassification, away_conference = awayConference, away_points = awayPoints)]
}), fill = TRUE)), fill = TRUE)
fcs <- unique(fcs, by = "game_id")
saveRDS(fcs, file.path(prep, "fcs_schedules_2013_2025.rds"))
for (y in 2013:2025) { x <- fcs[season == y]
  add("fcs_schedule", y, "games", nrow(x))
  add("fcs_schedule", y, "fcs_vs_fcs_games", x[home_division == "fcs" & away_division == "fcs", .N])
  add("fcs_schedule", y, "fcs_vs_fcs_with_final_score_share", x[home_division == "fcs" & away_division == "fcs", mean(completed %in% TRUE & is.finite(home_points) & is.finite(away_points))])
  add("fcs_schedule", y, "fcs_teams", uniqueN(c(x[home_division == "fcs", home_id], x[away_division == "fcs", away_id])))
  add("fcs_schedule", y, "fbs_vs_fcs_games_in_this_pull", x[xor(home_division == "fbs", away_division == "fbs"), .N]) }

long <- rbindlist(res); fwrite(long, file.path(out, "p1_coverage_long.csv"))
wide <- dcast(long, item + metric ~ season, value.var = "value", fun.aggregate = function(v) v[1]); fwrite(wide, file.path(out, "p1_coverage.csv"))
miss <- long[metric == "fbs_teams_missing" & item %in% c("stats_rushing", "stats_receiving", "roster")]
verdict <- data.table(step = "P1", rule = "every FBS team present in each season's rushing and receiving stats (and the 2013 roster)",
                      max_missing = max(miss$value), pass = all(miss$value == 0), calls_this_run = cl$calls())
fwrite(verdict, file.path(out, "p1_verdict.csv")); fwrite(cl$log(), file.path(out, "p1_calls.csv"))
print(wide, width = 250); print(verdict)
