# Round 15 P1 under Amendment 01 A1: every FBS team-season for which CFBD provides the required statistics is present.
# A team-season missing from the season pulls is a source gap only if team-specific queries (seasonType both and
# spring_regular) return no rows for that category. Cached GETs; no outcome analysis.
source("config/paths.R"); source("R/round15/cfbd_client.R")
raw <- "output/dev/round15/raw"; out <- "docs/round15/prep"; cl <- cfbd_client(raw, max_calls = 20L)
bak6 <- "/Users/willcavender/Desktop/CFB Modeling Backup/CFB-Modeling-round6/outputs/round6/raw"
fbs_names <- function(y) { f <- if (y >= 2015) file.path(PATHS$frozen, "cfb_data_v3", sprintf("raw_schedule_%d.rds", y)) else file.path(bak6, sprintf("raw_schedule_%d.rds", y))
  g <- readRDS(f); unique(c(g$home_team[g$home_division == "fbs"], g$away_team[g$away_division == "fbs"])) }
miss <- rbindlist(lapply(2013:2026, function(y) rbindlist(lapply(c("rushing", "receiving"), function(cat) {
  s <- readRDS(file.path(raw, sprintf("stats_player_season_year%d_category%s.rds", y, cat)))
  m <- setdiff(fbs_names(y), s$team); if (length(m)) data.table(season = y, category = cat, team = m) }))))
r13 <- readRDS(file.path(raw, "roster_year2013_classificationfbs.rds")); rm <- setdiff(fbs_names(2013), r13$team)
if (nrow(miss)) miss[, team_query_rows := mapply(function(y, cat, tm) sum(vapply(c("both", "spring_regular"), function(st)
  NROW(cl$get("/stats/player/season", list(year = y, team = tm, category = cat, seasonType = st))), 0)), season, category, team)]
gaps <- if (nrow(miss)) miss[team_query_rows == 0] else miss
unexplained <- if (nrow(miss)) miss[team_query_rows > 0] else miss
v <- data.table(step = "P1 (amended A1)", rule = "every FBS team-season for which CFBD provides the statistics is present; gaps confirmed by team-specific queries",
                missing_in_season_pulls = nrow(miss), confirmed_source_gaps = paste(gaps[, sprintf("%s %d %s", team, season, category)], collapse = "; "),
                unexplained_missing = nrow(unexplained) + length(rm), roster_2013_missing = length(rm), pass = nrow(unexplained) == 0 && length(rm) == 0)
fwrite(miss, file.path(out, "p1_amended_missing_team_seasons.csv")); fwrite(v, file.path(out, "p1_verdict_amended.csv")); print(miss); print(t(v))
