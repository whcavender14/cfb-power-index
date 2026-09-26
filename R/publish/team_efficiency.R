# =============================================================================
# R/publish/team_efficiency.R — raw per-play efficiency for the team pages (efficiency.json).
#
# Display only: nothing here feeds the ratings or the simulation. Source: CFBD play-by-play (cfbfastR::cfbd_plays,
# the same pull the production C2 build caches as plays_<type>_wkNN.rds), `ppa` = CFBD's expected points added.
# RAW, NOT opponent-adjusted: season means over every eligible play in the regular-season games the ratings used
# (FCS opponents included, all four quarters, no garbage-time filter).
#   eligible play: rush or pass play type (sacks and interceptions count as passes), down 1–4, distance > 0,
#                  finite ppa; kneels, spikes, penalties and no-plays excluded
#   success:       gained >= 50% of distance on 1st down, 70% on 2nd, 100% on 3rd/4th (the SR stack's definition)
#   net EPA/play:  offense EPA/play minus defense EPA/play allowed
# Ranks are among FBS teams (1 = best; for defense, lower EPA allowed = better).
# =============================================================================
suppressPackageStartupMessages(library(data.table))

EFF_RUSH <- c("Rush", "Rushing Touchdown")
EFF_PASS <- c("Pass", "Pass Reception", "Pass Completion", "Pass Incompletion", "Passing Touchdown", "Sack",
              "Pass Interception Return", "Pass Interception", "Interception", "Interception Return Touchdown")

# plays: CFBD play rows; teams: data.frame(team_id, school) of FBS teams; game_ids: games to include.
team_efficiency <- function(plays, teams, game_ids) {
  p <- as.data.table(plays)[as.character(game_id) %in% game_ids & play_type %in% c(EFF_RUSH, EFF_PASS)]
  p <- p[down %in% 1:4 & is.finite(distance) & distance > 0 & is.finite(ppa) & is.finite(yards_gained) &
         !grepl("kneel|spike|no.play|penalty", play_text, ignore.case = TRUE)]
  p <- unique(p, by = c("game_id", "play_id"))
  p[, `:=`(rush = play_type %in% EFF_RUSH, success = yards_gained >= distance * c(.5, .7, 1, 1)[down])]
  off <- p[, .(plays = .N, sr = mean(success), off_epa = mean(ppa), off_rush_epa = mean(ppa[rush]), off_pass_epa = mean(ppa[!rush]),
               off_rush_plays = sum(rush), off_pass_plays = sum(!rush)), by = .(school = offense)]
  def <- p[, .(def_plays = .N, def_epa = mean(ppa), def_rush_epa = mean(ppa[rush]), def_pass_epa = mean(ppa[!rush])), by = .(school = defense)]
  x <- merge(merge(data.table(team_id = as.character(teams$team_id), school = teams$school), off, by = "school", all.x = TRUE), def, by = "school", all.x = TRUE)
  x[, net_epa := off_epa - def_epa]
  higher <- c("sr", "net_epa", "off_epa", "off_rush_epa", "off_pass_epa"); lower <- c("def_epa", "def_rush_epa", "def_pass_epa")
  for (k in higher) x[, (paste0(k, "_rank")) := ifelse(is.na(get(k)), NA_integer_, rank(-get(k), ties.method = "min", na.last = "keep"))]
  for (k in lower) x[, (paste0(k, "_rank")) := ifelse(is.na(get(k)), NA_integer_, rank(get(k), ties.method = "min", na.last = "keep"))]
  num <- c(higher, lower)
  x[, (num) := lapply(.SD, function(v) round(v, 4)), .SDcols = num]
  x[, school := NULL]
  x[order(team_id)]
}

efficiency_doc <- function(eff, meta_block, n_games, through_week) {
  list(meta = meta_block,
       method = list(adjusted = FALSE, source = "CollegeFootballData play-by-play (ppa = expected points added)",
                     scope = sprintf("Regular-season games through Week %d that entered the ratings (%d games), all opponents, all quarters", through_week, n_games),
                     plays = "Rush and pass plays (sacks and interceptions count as passes), downs 1-4; kneels, spikes, penalties and no-plays excluded",
                     success = "Gain of at least 50% of the distance on 1st down, 70% on 2nd, 100% on 3rd and 4th",
                     ranks = "Among FBS teams; 1 = best. Defense: lower EPA allowed is better"),
       teams = eff)
}

# Latest cached play-by-play of the production build (output/state/c2_live/<run>/plays_*.rds), or $CFB_PLAYS_FILE.
read_site_plays <- function(state_dir) {
  f <- Sys.getenv("CFB_PLAYS_FILE", "")
  if (nzchar(f)) return(as.data.table(readRDS(f)))
  runs <- sort(list.dirs(file.path(state_dir, "c2_live"), recursive = FALSE), decreasing = TRUE)
  for (d in runs) {
    files <- list.files(d, pattern = "^plays_.*\\.rds$", full.names = TRUE)
    if (length(files)) return(rbindlist(lapply(files, function(x) as.data.table(readRDS(x))), fill = TRUE))
  }
  NULL
}
