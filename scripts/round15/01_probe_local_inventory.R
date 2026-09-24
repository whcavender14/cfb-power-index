# Round 15 design probe 01: coverage of the data we already hold, 2013-2026 (read-only).
# No API calls, no model fits, no outcome analysis. Counts only.
# Usage (repo root): Rscript scripts/round15/01_probe_local_inventory.R
source("config/paths.R"); source("config/legacy_paths.R")
suppressPackageStartupMessages(library(data.table))
out <- "docs/round15/coverage"; dir.create(out, recursive = TRUE, showWarnings = FALSE)
BAK <- LEGACY_ROOTS[["backup"]]; OLD <- LEGACY_ROOTS[["old"]]
raw6 <- file.path(BAK, "CFB-Modeling-round6/outputs/round6/raw")
raw5 <- file.path(BAK, "archive/v6-round5/results/artifacts/raw")
SEASONS <- 2013:2026
rows <- list()
add <- function(source, season, metric, value) rows[[length(rows) + 1]] <<- data.table(source, season, metric, value = as.numeric(value))

sched <- function(y) {
  f <- if (y >= 2015) file.path(PATHS$frozen, "cfb_data_v3", sprintf("raw_schedule_%d.rds", y)) else file.path(raw6, sprintf("raw_schedule_%d.rds", y))
  as.data.table(readRDS(f))
}
S <- lapply(SEASONS, sched); names(S) <- SEASONS
fbs_ids <- lapply(S, function(g) sort(unique(c(g$home_id[g$home_division == "fbs"], g$away_id[g$away_division == "fbs"]))))
fcs_ids <- lapply(S, function(g) sort(unique(c(g$home_id[g$home_division == "fcs"], g$away_id[g$away_division == "fcs"]))))

for (y in SEASONS) {
  g <- S[[as.character(y)]]; fin <- g[is.finite(home_points) & is.finite(away_points)]
  add("schedule", y, "fbs_teams", length(fbs_ids[[as.character(y)]]))
  add("schedule", y, "fbs_vs_fbs_final", fin[home_division == "fbs" & away_division == "fbs", .N])
  add("schedule", y, "fbs_vs_fcs_final", fin[xor(home_division == "fbs", away_division == "fbs") & (home_division == "fcs" | away_division == "fcs"), .N])
  add("schedule", y, "last_kickoff_in_file", as.numeric(as.Date(max(substr(g$start_date, 1, 10)))))
}

# Game types that identify conference and tier strength (counts only; season-indexed tier map)
tm <- fread(PATHS$tier_map)
tier <- function(conf, y) { t <- rep(NA_character_, length(conf)); for (i in seq_len(nrow(tm))) t[conf == tm$conference[i] & y >= tm$season_from[i] & y <= tm$season_to[i]] <- tm$tier[i]; t }
for (y in SEASONS) {
  g <- S[[as.character(y)]][is.finite(home_points) & is.finite(away_points) & home_division == "fbs" & away_division == "fbs"]
  if (!nrow(g)) next
  g[, `:=`(th = tier(home_conference, y), ta = tier(away_conference, y), conf = !is.na(home_conference) & home_conference == away_conference)]
  add("game_types", y, "fbs_conference_games", sum(g$conf)); add("game_types", y, "fbs_nonconference_games", sum(!g$conf))
  add("game_types", y, "nonconference_share_before_oct1", mean(as.Date(substr(g$start_date[!g$conf], 1, 10)) < as.Date(sprintf("%d-10-01", y))))
  add("game_types", y, "p4_vs_g5_games", sum((g$th == "P4" & g$ta == "G5") | (g$th == "G5" & g$ta == "P4"), na.rm = TRUE))
  add("game_types", y, "median_fbs_games_per_team", median(table(c(g$home_id, g$away_id))))
  f <- S[[as.character(y)]][is.finite(home_points) & xor(home_division == "fbs", away_division == "fbs")]
  add("game_types", y, "fbs_vs_fcs_games_per_fbs_team", nrow(f) / length(fbs_ids[[as.character(y)]]))
}

# Play-by-play and drives (Round 6 raw pulls, 2013-2025)
drop_types <- c("Kickoff", "Kickoff Return (Offense)", "Kickoff Return Touchdown", "Punt", "Punt Return Touchdown", "Blocked Punt",
                "Field Goal Good", "Field Goal Missed", "Blocked Field Goal", "Extra Point Good", "Extra Point Missed",
                "Timeout", "End Period", "End of Half", "End of Game", "End of Regulation", "Penalty", "Uncategorized",
                "Two Point Pass", "Two Point Rush", "Defensive 2pt Conversion", "Safety", "Blocked Punt Touchdown",
                "Missed Field Goal Return", "Missed Field Goal Return Touchdown", "Blocked Field Goal Touchdown",
                "Punt Return", "Kickoff Return", "Offensive 1pt Safety", "placeholder", "Start of Period", "End of Period")
dropback <- c("Pass", "Pass Reception", "Pass Completion", "Pass Incompletion", "Passing Touchdown", "Sack",
              "Pass Interception Return", "Pass Interception", "Interception", "Interception Return Touchdown")
passer_re <- "^[A-Z][-A-Za-z.' ]+ (pass |sacked)"
for (y in 2013:2025) {
  g <- S[[as.character(y)]]; fin <- g[is.finite(home_points) & is.finite(away_points)]
  ff <- fin[home_division == "fbs" & away_division == "fbs", game_id]
  fc <- fin[xor(home_division == "fbs", away_division == "fbs"), game_id]
  p <- as.data.table(readRDS(file.path(raw6, sprintf("plays_%d.rds", y))))
  d <- as.data.table(readRDS(file.path(raw6, sprintf("drives_%d.rds", y))))
  add("plays_raw", y, "fbs_vs_fbs_games_share", mean(ff %in% p$game_id))
  add("plays_raw", y, "fbs_vs_fcs_games_share", mean(fc %in% p$game_id))
  scr <- p[!play_type %in% drop_types & !is.na(down) & down %in% 1:4]
  add("plays_raw", y, "scrimmage_plays", nrow(scr))
  add("plays_raw", y, "vendor_ppa_finite_share", mean(is.finite(suppressWarnings(as.numeric(scr$ppa)))))
  db <- scr[play_type %in% dropback]
  add("plays_raw", y, "dropbacks_passer_name_parsed_share", mean(grepl(passer_re, db$play_text)))
  add("plays_raw", y, "dropbacks_passer_parsed_either_format_share",
      mean(grepl(passer_re, db$play_text) | grepl("#[0-9]+ [A-Z][-A-Za-z.' ]+ (pass |sacked)", db$play_text)))
  add("drives_raw", y, "fbs_vs_fbs_games_share", mean(ff %in% d$game_id))
  add("drives_raw", y, "start_yards_to_goal_finite_share", mean(is.finite(d$start_yards_to_goal)))
}
live <- file.path(OLD, "cfb_data/pbp_live_2026.rds")
if (file.exists(live)) {
  p <- as.data.table(readRDS(live)); gid <- intersect(c("game_id", "id_play"), names(p))[1]
  g <- S[["2026"]]; fin <- g[is.finite(home_points) & is.finite(away_points) & home_division == "fbs" & away_division == "fbs"]
  add("plays_live_2026", 2026, "rows", nrow(p))
  add("plays_live_2026", 2026, "frozen_fbs_vs_fbs_final_games_share", mean(fin$game_id %in% p[[gid]]))
}
r5 <- list.files(raw5, "^advanced_game_\\d{4}\\.rds$", full.names = TRUE)
for (f in r5) add("cfbd_advanced_game_r5", as.integer(gsub("\\D", "", basename(f))), "team_game_rows", nrow(readRDS(f)))

# Team-season feature caches (frozen, pulled 2026-09-10)
tal <- as.data.table(readRDS(file.path(PATHS$frozen, "cfb_data_v2/talent_2014_2026.rds")))
ret <- as.data.table(readRDS(file.path(PATHS$frozen, "cfb_data_v2/returning_2014_2026.rds")))
coa <- as.data.table(readRDS(file.path(PATHS$frozen, "cfb_data_v2/coaches_1989_2026.rds")))
por <- as.data.table(readRDS(file.path(PATHS$frozen, "cfb_data_v2/portal_2014_2026.rds")))
for (y in 2014:2026) {
  f <- fbs_ids[[as.character(y)]]; n <- length(f)
  t <- tal[season == y]
  add("talent_composite", y, "fbs_share", mean(f %in% t$team_id[is.finite(t$talent_composite)]))
  add("talent_composite", y, "non_fbs_rows", sum(!t$team_id %in% f))
  add("talent_composite", y, "fcs_opponents_share", mean(fcs_ids[[as.character(y)]] %in% t$team_id))
  r <- ret[season == y]
  add("returning_prod", y, "off_fbs_share", mean(f %in% r$team_id[is.finite(r$off_returning)]))
  add("returning_prod", y, "def_fbs_share", mean(f %in% r$team_id[is.finite(r$def_returning)]))
  add("returning_prod", y, "is_estimated_true_rows", sum(r$is_estimated %in% TRUE))
  cc <- coa[year == y]
  add("coaches", y, "fbs_share_with_row", mean(f %in% cc$team_id))
  add("coaches", y, "fbs_share_with_hire_date", mean(f %in% cc$team_id[!is.na(cc$hire_date)]))
  add("coaches", y, "fbs_teams_with_2plus_coaches", sum(table(cc$team_id[cc$team_id %in% f]) > 1))
  pp <- por[season == y]
  add("portal", y, "events", nrow(pp))
  if (nrow(pp)) {
    add("portal", y, "destination_known_share", mean(!is.na(pp$destination) & nzchar(pp$destination)))
    add("portal", y, "rating_known_share", mean(is.finite(pp$rating)))
    add("portal", y, "stars_known_share", mean(is.finite(pp$stars) & pp$stars > 0))
    add("portal", y, "transfer_date_known_share", mean(!is.na(pp$transfer_date)))
    add("portal", y, "entries_after_aug1_share", mean(as.Date(pp$transfer_date) >= as.Date(sprintf("%d-08-01", y)), na.rm = TRUE))
    add("portal", y, "qb_events", sum(pp$position == "QB"))
  }
}
feat <- readRDS(file.path(PATHS$frozen, "outputs/round4/features.rds"))
tf <- as.data.table(if (is.data.frame(feat)) feat else feat[[intersect(names(feat), c("team_features", "features", "team"))[1]]])
if (nrow(tf) && "season" %in% names(tf)) for (v in intersect(c("log_talent", "blue_chip_ratio", "log_recruits", "off_returning", "def_returning", "log_tenure", "new_coach"), names(tf)))
  for (y in sort(unique(tf$season))) add("round4_feature_bundle", y, paste0(v, "_nonmissing_share"), mean(!is.na(tf[season == y][[v]])))

# Reference / comparator files
ml <- as.data.table(readRDS(PATHS$market_lines)); scol <- intersect(c("season", "year"), names(ml))[1]
for (y in sort(unique(ml[[scol]]))) add("market_lines_closing", y, "games", sum(ml[[scol]] == y))
cfp <- fread(file.path(PATHS$reference, "cfp_final_rankings_2018_2025.csv")); scol <- intersect(c("season", "year"), names(cfp))[1]
for (y in sort(unique(cfp[[scol]]))) add("cfp_final_top25", y, "rows", sum(cfp[[scol]] == y))
for (sp in c("dev", "cond")) { x <- fread(if (sp == "dev") PATHS$incumbent_dev else PATHS$incumbent_cond)
  for (y in sort(unique(x$season))) add(paste0("incumbent_pred_round4_", sp), y, "games", sum(x$season == y)) }
r13 <- path.expand("~/Desktop/Revised CFB Modeling/.claude/worktrees/round13-pbp-stack/output/dev/round13")
for (sp in c("dev", "cond")) { f <- file.path(r13, sprintf("predictions_%s.csv", sp)); if (file.exists(f)) { x <- fread(f)
  for (y in sort(unique(x$season))) add(paste0("round13_K_and_round6_incumbent_", sp), y, "games", sum(x$season == y)) } }

long <- rbindlist(rows)
long[metric == "last_kickoff_in_file", value := value]  # days since epoch; converted in the wide view
fwrite(long, file.path(out, "local_inventory_long.csv"))
wide <- dcast(long, source + metric ~ season, value.var = "value")
num <- setdiff(names(wide), c("source", "metric"))
wide[, (num) := lapply(.SD, function(v) ifelse(is.na(v), NA, ifelse(abs(v) < 1 & v != 0, round(v, 3), round(v, 1)))), .SDcols = num]
wide[metric == "last_kickoff_in_file", (num) := lapply(.SD, function(v) as.numeric(format(as.Date(v, origin = "1970-01-01"), "%Y%m%d"))), .SDcols = num]
fwrite(wide, file.path(out, "local_coverage_matrix.csv"))
print(wide, nrows = 200, width = 250)
