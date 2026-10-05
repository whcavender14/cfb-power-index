# Writes public/data/v2/players/ratings/ (CFPi+ Player Ratings v1 beta; docs/website/PLAYER_RATINGS_PREDECLARATION.md,
# PLAYER_RATINGS_VALIDATION.md): top.json (the /players/ Ratings view; TE left out, see below) and team/<team_id>.json
# (every rated roster player, for the player modal badge and team views). Modelled, not official; display only.
# The validated object is a rating through the last completed season for the next season, so this season's roster is
# rated with evidence through last season. Current-season games are not used (that would be an unvalidated v2).
# No CFBD calls, except once a year: when a new season starts, last season's history (5 calls) is pulled and cached.
#   Rscript scripts/export_player_ratings.R           build and write
#   Rscript scripts/export_player_ratings.R flags     only refresh the "profile" flags (after a profile export run by hand;
#                                                     the weekly export does the same inline)
suppressPackageStartupMessages(library(jsonlite))
if (!exists("PATHS")) source(file.path(Sys.getenv("CFB_PROJECT_ROOT", "."), "config", "paths.R"))
v2 <- file.path(PATHS$public_data, "v2"); out_dir <- file.path(v2, "players", "ratings")
has_profile <- function(ids) file.exists(file.path(v2, "player", paste0(ids, ".json")))
write_doc <- function(x, f) write_json(x, f, auto_unbox = TRUE, na = "null", null = "null", digits = 6)
RATING_COLS <- c("athlete_id", "name", "team_id", "position", "group", "class", "ovr", "band", "provisional", "estimated", "profile", "rs")

refresh_profile_flags <- function() {
  k <- match("profile", RATING_COLS)
  for (f in c(file.path(out_dir, "top.json"), list.files(file.path(out_dir, "team"), full.names = TRUE))) {
    d <- fromJSON(f, simplifyVector = FALSE)
    d$rows <- lapply(d$rows, function(r) { r[[k]] <- has_profile(r[[1]]); r })
    write_doc(d, f)
  }
}

if (identical(commandArgs(TRUE)[1], "flags")) { refresh_profile_flags(); quit(save = "no") }

source(file.path(PATHS$root, "R", "publish", "class_flags.R")); source(file.path(PATHS$root, "R", "ratings", "ratings_spec.R")); source(file.path(PATHS$root, "R", "ratings", "ratings_core.R"))
options(cfb.pull_ppa = FALSE); source(file.path(PATHS$root, "R", "publish", "pull_player_ppa.R"))
index <- fromJSON(file.path(v2, "index.json"), simplifyVector = FALSE)
teams <- fromJSON(file.path(v2, "teams.json"))$teams
season <- index$meta$season; through <- season - 1L
# Last season's history, once (cached for good in data/reference/player_cache).
for (k in list(c("stats", "stats/player/season"), c("ppa", "ppa/players/season"), c("usage", "player/usage"), c("success", "stats/player/success"), c("teamstats", "stats/season"))) {
  f <- file.path(CACHE, sprintf("hist_%s_%d.rds", k[1], through))
  if (file.exists(f)) next
  message(sprintf("Player ratings: 1 CFBD call, %s %d", k[2], through))
  q <- if (k[1] %in% c("stats", "success")) list(year = through, seasonType = "regular") else list(year = through)
  x <- cfbd_get(k[2], q); if (is.null(x)) stop("Player ratings: could not pull ", k[2], " ", through)
  saveRDS(as.data.frame(x), f)
}
roster <- readRDS(file.path(PATHS$state, sprintf("rosters_%d.rds", season)))
p <- build_ratings(through, teams$team, pool = roster_pool(season, teams$team, r = roster))
knots <- readRDS(file.path(PATHS$root, "R", "ratings", "ratings_knots.rds"))
# Band: half the OVR distance between mu - 1 SD and mu + 1 SD, measured on the scale before its 30/99 limits so that a
# capped rating still shows its uncertainty (display rule; the rating itself is the frozen v1 value).
ovr_open <- function(mu) { lo <- min(knots$x); hi <- max(knots$x); f <- splinefun(knots$x, knots$y, method = "hyman"); s <- function(a) (f(a + 1e-3) - f(a - 1e-3)) / 2e-3
  ifelse(mu < lo, knots$y[1] + s(lo) * (mu - lo), ifelse(mu > hi, tail(knots$y, 1) + s(hi) * (mu - hi), f(pmax(lo, pmin(hi, mu))))) }
p[, `:=`(ovr = as.integer(round(to_ovr(mu, knots))),
         band = as.integer(round((ovr_open(mu + sd_z) - ovr_open(mu - sd_z)) / 2)),
         team_id = as.character(teams$team_id[match(team, teams$team)]))]
roster_season <- season; rs_lookup <- recruit_class_lookup(roster_season)   # (p has its own `season` column: the evidence season)
p[, rs := rs_flag(athlete_id, class, rs_lookup, roster_season)]
setorder(p, -mu, athlete_id)
row <- function(d) lapply(seq_len(nrow(d)), function(i) list(d$athlete_id[i], d$name[i], d$team_id[i], d$position[i], d$group[i],
  if (is.na(d$class[i])) NA else d$class[i], d$ovr[i], d$band[i], d$provisional[i], d$estimated[i], has_profile(d$athlete_id[i]), d$rs[i]))

val <- fromJSON(file.path(PATHS$reference, "ratings_v1_validation.json"), simplifyVector = FALSE)
o <- p$ovr
method <- list(version = RS$version, label = "Beta", rated_through = through, roster_season = season,
               note = sprintf("Ratings for %d rosters, built from games through the %d season. %d games are not included in this beta.", season, through, season),
               counts = list(rated = nrow(p), provisional = sum(p$provisional), estimated = sum(p$estimated)),
               distribution = list(mean = round(mean(o), 1), median = median(o), sd = round(sd(o), 1),
                                   at = list(`95` = round(100 * mean(o >= 95), 1), `90` = round(100 * mean(o >= 90), 1), `80` = round(100 * mean(o >= 80), 1), `70` = round(100 * mean(o >= 70), 1))),
               left_out = list(TE = "Tight ends are rated (see the player card) but left out of these lists: their validation gain was small and not significant (+0.04, 95% CI -0.09 to +0.16)."),
               validation = val)
# top.json: the 300 highest-rated players plus each group's 50 best, TE excepted.
q <- p[group != "TE"]
keep <- unique(c(head(q$athlete_id, 300), q[, head(athlete_id, 50), by = group]$V1))
top <- q[athlete_id %in% keep]
dir.create(file.path(out_dir, "team"), recursive = TRUE, showWarnings = FALSE)
write_doc(list(meta = index$meta, source = "CFPi+ Player Ratings (modelled, not official), from CollegeFootballData player data and 247Sports recruiting ratings",
               method = method, columns = RATING_COLS, rows = row(top)), file.path(out_dir, "top.json"))
written <- character()
for (t in unique(p$team_id[!is.na(p$team_id)])) {
  d <- p[team_id == t]
  write_doc(list(meta = index$meta, team_id = t, rated_through = through, version = RS$version, columns = RATING_COLS, rows = row(d)),
            file.path(out_dir, "team", paste0(t, ".json")))
  written <- c(written, paste0(t, ".json"))
}
stale <- setdiff(list.files(file.path(out_dir, "team")), written)
if (length(stale)) invisible(file.remove(file.path(out_dir, "team", stale)))
cat(sprintf("Player ratings %s (through %d, %d rosters): %d rated, %d teams; top.json %d rows; mean %.1f, SD %.1f; Provisional %.1f%%\n",
            RS$version, through, season, nrow(p), length(written), nrow(top), mean(o), sd(o), 100 * mean(p$provisional)))
