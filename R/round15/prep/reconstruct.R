# Round 15 P4: preseason input reconstruction, exactly as defined in predeclaration §4.1. Pure functions over
# already-pulled CFBD data. Knowledge dates by construction: season y uses y-1 player stats, the y roster, the April-y
# draft, recruiting classes <= y, coaches hired before y's first FBS kickoff, and y-1 end-of-season ratings.
# Missing inputs stay NA (never zero-filled). No outcome of season y is read.
suppressPackageStartupMessages(library(data.table))

# y-1 production per player at FBS teams: data.table(id, team, value)
r15_prod <- function(stats, stat_type, fbs_teams) {
  s <- as.data.table(stats)
  if (!nrow(s)) return(data.table(id = character(), team = character(), value = numeric()))
  s[statType == stat_type & team %in% fbs_teams, .(value = sum(suppressWarnings(as.numeric(stat)), na.rm = TRUE)),
    by = .(id = as.character(playerId), team)]
}

# Continuity share for every team on the y roster (FBS in y).
#   numerator: y-1 production, at ANY FBS team, of players on team i's y roster who were not drafted in April y
#   denominator: team i's own y-1 total; NA if the team had no y-1 FBS production (promoted, or no stats); cap 1.5
r15_continuity <- function(prod, roster, drafted_ids, teams_y, cap = 1.5) {
  r <- unique(as.data.table(roster)[, .(id = as.character(id), team)])
  own <- prod[, .(den = sum(value)), by = team]
  pp <- prod[, .(value = sum(value)), by = id]
  num <- merge(r[!id %in% drafted_ids], pp, by = "id")[, .(num = sum(value)), by = team]
  out <- data.table(team = teams_y)
  out[, den := own$den[match(team, own$team)]][, num := num$num[match(team, num$team)]]
  out[is.na(num) & !is.na(den), num := 0]
  out[, cont := ifelse(is.finite(den) & den > 0, pmin(cap, num / den), NA_real_)]
  out[, .(team, cont)]
}

# 1 if the y roster includes a player with >= min_att y-1 pass attempts at a DIFFERENT FBS team
r15_qb_xfer_in <- function(att, roster, teams_y, min_att = 100) {
  r <- unique(as.data.table(roster)[, .(id = as.character(id), team)])
  big <- att[value >= min_att, .(id, from = team)]
  hit <- merge(r, big, by = "id")[team != from, unique(team)]
  data.table(team = teams_y, qb_xfer_in = as.numeric(teams_y %in% hit))
}

# Mean 247 class points over classes y-3..y (>= 2 classes required), z-scored within season over FBS teams
r15_talent4 <- function(classes, y, teams_y) {
  c4 <- as.data.table(classes)[year %in% (y - 3):y & team %in% teams_y, .(pts = mean(points), n = .N), by = team]
  out <- data.table(team = teams_y)[, raw := c4$pts[match(team, c4$team)]][, n := c4$n[match(team, c4$team)]]
  out[is.na(n) | n < 2, raw := NA_real_]
  out[, talent4 := (raw - mean(raw, na.rm = TRUE)) / sd(raw, na.rm = TRUE)]
  out[, .(team, talent4)]
}

# Share of 4-5 star signees among the team's rated recruits in classes y-3..y
r15_bluechip4 <- function(recruits, y, teams_y) {
  r <- as.data.table(recruits)[year %in% (y - 3):y & committedTo %in% teams_y & is.finite(stars) & stars >= 1]
  b <- r[, .(bluechip4 = mean(stars >= 4), n = .N), by = .(team = committedTo)]
  data.table(team = teams_y)[, bluechip4 := b$bluechip4[match(team, b$team)]]
}

# Incumbent coaching rule (v5_ingest), ported verbatim in logic: only a unique coach hired before the season's first
# FBS kickoff counts; log_tenure = log1p(years since hire, Aug-1 boundary); new_coach = hired on/after Aug 1 of y-1.
r15_coach <- function(coaches, y, first_kickoff) {
  q <- as.data.table(coaches)[year == y, .(team_id = as.integer(team_id), hire = as.POSIXct(sub("Z$", "", as.character(hire_date)), format = "%Y-%m-%dT%H:%M:%OS", tz = "UTC"))]
  q[, status := ifelse(is.na(hire), "missing", ifelse(hire >= first_kickoff, "post_cutoff", "pre"))]
  qq <- q[status == "pre"][, if (.N == 1) .SD, by = team_id]
  qq[, `:=`(log_tenure = log1p(pmax(0, y - as.integer(format(hire, "%Y")) - as.integer(as.integer(format(hire, "%m")) >= 8))),
            new_hc = as.numeric(hire >= as.POSIXct(paste0(y - 1, "-08-01"), tz = "UTC")))]
  qq[, .(team_id, log_tenure, new_hc)]
}

# Mean last-season rating of the team's season-y conference members, excluding the team; NA for FBS independents
r15_conf_level <- function(members, last) {
  m <- merge(as.data.table(members), as.data.table(last), by = "team_id", all.x = TRUE)
  m[, `:=`(conf_off = NA_real_, conf_def = NA_real_)]
  ok <- !is.na(m$conf) & m$conf != "FBS Independents"
  for (i in which(ok)) { o <- m[conf == m$conf[i] & team_id != m$team_id[i] & is.finite(eff_off)]
    if (nrow(o)) { m$conf_off[i] <- mean(o$eff_off); m$conf_def[i] <- mean(o$eff_def) } }
  m[, .(team_id, conf_off, conf_def)]
}

# [Amendment 01 A2] VALIDATION ONLY, never a candidate input: returning-player component of continuity = own-team y-1
# production of players who were on team i in y-1, are on its y roster and were not drafted in April y, / own y-1 total.
r15_continuity_own <- function(prod, roster, drafted_ids, teams_y) {
  r <- unique(as.data.table(roster)[, .(id = as.character(id), team)])
  own <- prod[, .(den = sum(value)), by = team]
  num <- merge(prod, r[!id %in% drafted_ids], by = c("id", "team"))[, .(num = sum(value)), by = team]
  out <- data.table(team = teams_y)[, den := own$den[match(team, own$team)]][, num := num$num[match(team, num$team)]]
  out[is.na(num) & !is.na(den), num := 0]
  out[, .(team, cont_own = ifelse(is.finite(den) & den > 0, num / den, NA_real_))]
}
