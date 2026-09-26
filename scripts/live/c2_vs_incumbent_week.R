# One-off live comparison: Current C2 (tag c2-post-stage4-baseline, R/c2/c2_current.R, UNMODIFIED) vs the production incumbent
# (EB_features) for the 2026 season as of a Monday cutoff, plus game-by-game implied spreads against the opening lines.
# NOT the forward test and not a model run of record: nothing is archived, hashed or scored; no model code is changed.
#
# Inputs (all read-only):
#   * fresh 2026 schedule/results:    <main>/output/state/production_live/raw_schedule_2026.rds (the production pipeline's pull)
#   * 2026 play-by-play, weeks 1-3:   round15-power-rating/output/dev/round15/forward_dryrun/pbp/2026/ (cfbfastR cfbd_plays pulls)
#   * FCS-classification schedule:    CFBD /games classification=fcs, 2026 (1 call; C2 needs FCS-vs-FCS results)
#   * incumbent ratings:              <main>/output/state/production_ratings_2026_latest.rds (as_of = the cutoff)
#   * opening lines (evaluation only, merged LAST; never seen by either model): CFBD /lines, 2026 week WEEK (1 call)
# Usage (c2-refinement worktree root): Rscript scripts/live/c2_vs_incumbent_week.R          (WEEK and CUTOFF env vars override)
WEEK <- as.integer(Sys.getenv("WEEK", "4")); CUTOFF <- as.POSIXct(Sys.getenv("CUTOFF", "2026-09-21"), tz = "UTC")
MAIN <- "/Users/willcavender/Desktop/Revised CFB Modeling"; R15WT <- file.path(MAIN, ".claude/worktrees/round15-power-rating")
OUT <- sprintf("docs/c2/live_2026_wk%02d", WEEK); dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
RAW <- "output/live2026/raw"; dir.create(RAW, recursive = TRUE, showWarnings = FALSE)
source("config/paths.R"); source("config/production.R")
suppressPackageStartupMessages({ source(PATHS$model_ops); library(data.table)
  for (f in c("data", "c1", "c2", "tune")) source(sprintf("R/round15/candidates/%s.R", f)); source("R/c2/c2_current.R")
  source("R/round15/prep/fumble_parser.R"); source("R/round15/prep/sr_history.R"); source("R/round15/prep/passer_parser.R"); source("R/round15/cfbd_client.R") })
say <- function(...) cat(sprintf(...), "\n")

# ============================ 1. 2026 data layer (same functions the frozen build uses) ============================
d <- r15_build_data(); c1 <- readRDS(file.path(R15C$cache, "c1_components.rds")); c2 <- readRDS(file.path(R15C$cache, "c2_components.rds"))
cl <- cfbd_client(RAW, max_calls = 6L)
live <- file.path(MAIN, "output/state/production_live"); cfg <- v4_config(); cfg$cache_dir <- live
sch26 <- read_schedule(2026L, cfg, FALSE); raw26 <- readRDS(file.path(live, "raw_schedule_2026.rds"))
say("2026 schedule: %d games; final games by week: %s", nrow(sch26), paste(sprintf("wk%s=%d", names(table(sch26[sch26$final, ]$week)), as.integer(table(sch26[sch26$final, ]$week))), collapse = " "))
fx <- as.data.table(cl$get("/games", list(year = 2026, seasonType = "regular", classification = "fcs")))
vendor <- "(?i)elo|win_?prob|winprob|excitement|linescores|highlights"; drop <- grep(vendor, names(fx), perl = TRUE, value = TRUE); if (length(drop)) fx[, (drop) := NULL]   # same mapping as P1
fcs26 <- unique(fx[, .(game_id = as.character(id), season, week, season_type = seasonType, start_date = startDate, completed, neutral_site = neutralSite,
  home_id = homeId, home_team = homeTeam, home_division = homeClassification, home_conference = homeConference, home_points = homePoints,
  away_id = awayId, away_team = awayTeam, away_division = awayClassification, away_conference = awayConference, away_points = awayPoints)], by = "game_id")
fcs_old <- as.data.table(readRDS("output/dev/round15/prep/fcs_schedules_2013_2025.rds")); fcs_all <- rbind(fcs_old, fcs26, fill = TRUE)
games26 <- r15_full_games(sch26, fcs_all)
say("2026 games table: %d rows (%d final); FBS-involved %d, non-FBS-only %d", nrow(games26), sum(games26$final), games26[home_fbs | away_fbs, .N], games26[!(home_fbs | away_fbs), .N])
# play-derived rows for 2026 (SR means, fumbles, passers): the block of r15_build_data, applied to the weeks-1-3 pulls
pf <- sort(list.files(file.path(R15WT, "output/dev/round15/forward_dryrun/pbp/2026"), "^plays_regular_wk0[1-3]_.*[.]rds$", full.names = TRUE))
wk_of <- sub("^.*_(wk[0-9]+)_.*$", "\\1", basename(pf)); pf <- tapply(pf, wk_of, function(x) tail(x, 1))   # latest pull of each week
plays <- rbindlist(lapply(names(pf), function(k) as.data.table(readRDS(pf[[k]]))[, `:=`(season = 2026L, wk = as.integer(sub("wk", "", k)), season_type = "regular")]), fill = TRUE)   # historical files carry these three columns
stopifnot(!anyDuplicated(plays, by = c("game_id", "play_id")))
say("2026 play-by-play: %d plays from %s", nrow(plays), paste(names(pf), collapse = "+"))
pfile <- file.path(RAW, "plays_2026_wk1_3.rds"); saveRDS(as.data.frame(plays), pfile)
s <- r15_sr_season(pfile, raw26, 2026L)
p <- plays[, grep(r15_vendor_cols, names(plays), invert = TRUE, perl = TRUE), with = FALSE]; p[, game_id := as.character(game_id)]
fum <- grepl("Fumble", p$play_type); lost <- fum & grepl("Interception|Fumble Recovery \\(Opponent\\)|Fumble Return", p$play_type)
fl <- p[, .(game_id, offense)][, `:=`(fum = fum, lost = lost)][, .(fumbles = sum(fum), lost = sum(lost)), by = .(game_id, offense)]
dq <- p[play_type %in% r15_dropback_types][, passer := r15_passer(play_text)][!is.na(passer)]
qb <- dq[, .N, by = .(game_id, offense, passer)][order(-N)][, .(passer = passer[1], dropbacks = N[1]), by = .(game_id, offense)]
pbp26 <- merge(merge(s$means[, .(season = 2026L, game_id, offense, defense, sr = success, sr_plays = plays)], fl, by = c("game_id", "offense"), all = TRUE), qb, by = c("game_id", "offense"), all = TRUE)[, season := 2026L]
say("2026 SR rows: %d game x offense rows", pbp26[!is.na(sr), .N])

# extended data object (the frozen d, plus 2026); the C1 prior for 2026 is built exactly as the frozen build built 2024-25
d2 <- d; d2$sch[["2026"]] <- sch26; d2$games[["2026"]] <- games26; d2$pbp <- rbind(d$pbp, pbp26, fill = TRUE)
e <- r15_bind_incumbent(); c1x <- c1; c1x$priors[["2026"]] <- r15_c1_prior(d2, 2026L, 2022L, e)
dv2 <- c2_divisions(fcs_all)
anch <- c2_anchors(fread("output/c2/current/c2_anchor_history.csv"), 2026L)   # previous season's end-of-season level (2025), 2020 excluded
d2$base$snap <- c(d$base$snap, list(list(season = 2026L, cutoff = CUTOFF)))
ids26 <- fbs_ids(sch26); wk_games <- as.data.table(sch26)[week == WEEK & season_type == "regular"]
d2$base$frame <- rbind(as.data.table(d$base$frame), wk_games[home_fbs & away_fbs, .(season = 2026L, game_id, week, kickoff, neutral, home_id, away_id, cutoff = CUTOFF)], fill = TRUE)

# ============================ 2. Current C2, 2026, as of the cutoff ============================
S <- c2_season_inputs(d2, c1x, c2, 2026L, dv2, anch); run <- c2_predict_season(d2, 2026L, S)[[1]]
say("Current C2 solved: %d games before the cutoff (%d of them FBS-vs-nonFBS); anchor season %d (FCS level %.2f); solved Delta_FCS %.2f, Delta_low %.2f",
    run$levels$n_games, run$levels$n_link, anch$anchor_season, anch$fcs, run$levels$delta_fcs, run$levels$delta_low)
rt <- run$ratings; fg <- run$first_game

# ============================ 3. incumbent (production ratings as of the same cutoff) ============================
pr <- readRDS(file.path(MAIN, "output/state/production_ratings_2026_latest.rds")); inc <- as.data.table(pr$ratings)
stopifnot(format(as.Date(pr$as_of)) == format(as.Date(CUTOFF)), setequal(inc$team_id, ids26))
say("incumbent: production snapshot as_of %s, %d teams, hfa %.5f", format(pr$as_of), nrow(inc), pr$hfa)

# ============================ 4. file 1: team-by-team power ratings ============================
tm <- merge(inc[, .(team_id, team, conference, inc_power = power_rating, inc_off = off_rating, inc_def = def_rating, inc_games = games_played)],
            rt[fbs == TRUE, .(team_id, c2_power = power, c2_off = eff_off, c2_def = eff_def, c2_games_all = gp)], by = "team_id")
tm[, `:=`(diff_c2_minus_inc = c2_power - inc_power, c2_rank = frank(-c2_power, ties.method = "min"), inc_rank = frank(-inc_power, ties.method = "min"))]
setorder(tm, c2_rank)
w1 <- tm[, .(team, conference, c2_power_rating = round(c2_power, 2), incumbent_power_rating = round(inc_power, 2), c2_minus_incumbent = round(diff_c2_minus_inc, 2),
             c2_rank, incumbent_rank = inc_rank, c2_off_rating = round(c2_off, 2), c2_def_rating = round(c2_def, 2), incumbent_off_rating = round(inc_off, 2),
             incumbent_def_rating = round(inc_def, 2), games_played_all = c2_games_all, games_played_incumbent = inc_games, team_id)]
fwrite(w1, file.path(OUT, sprintf("power_ratings_c2_vs_incumbent_2026_wk%02d.csv", WEEK)))

# ============================ 5. file 2: game-by-game implied spreads ============================
H2 <- c2_H(d2, 2026L); Hi <- pr$hfa; FCS_INC <- PRODUCTION$sim_fcs_power
pw_c2 <- function(id) { x <- rt$power[match(id, rt$team_id)]; y <- fg$power[match(id, fg$team_id)]; ifelse(is.finite(x), x, y) }   # solved rating, else first-game rating
pw_in <- function(id) { x <- inc$power_rating[match(id, inc$team_id)]; ifelse(is.finite(x), x, FCS_INC) }                          # every non-FBS team at -25
g <- copy(wk_games)[, .(game_id, kickoff, home_team, away_team, home_id, away_id, neutral, home_fbs, away_fbs, home_conference, away_conference)]
g[, `:=`(c2_margin = pw_c2(home_id) - pw_c2(away_id) + H2 * (!neutral), inc_margin = pw_in(home_id) - pw_in(away_id) + Hi * (!neutral))]
stopifnot(!anyNA(g$c2_margin), !anyNA(g$inc_margin))
# tie-outs: (a) c2_predict_season's own predictions for the FBS-vs-FBS games; (b) the incumbent's archived dry-run snapshot for this cutoff
a <- merge(g[home_fbs & away_fbs, .(game_id, c2_margin)], run$pred[, .(game_id = as.character(game_id), pm = pred_margin)], by = "game_id")
say("tie-out (a) c2_predict_season vs rating-based margins: %d games, max |diff| %.2e", nrow(a), max(abs(a$c2_margin - a$pm)))
sf <- tail(sort(list.files(file.path(R15WT, "output/dev/round15/forward_dryrun/snapshots/incumbent/2026"), sprintf("cut%s.*csv$", format(CUTOFF, "%Y%m%d")), full.names = TRUE)), 1)
if (length(sf)) { z <- fread(sf); z[, game_id := as.character(game_id)]; b <- merge(g[, .(game_id, inc_margin)], z[, .(game_id, pm = pred_margin)], by = "game_id")
  say("tie-out (b) incumbent production ratings vs archived dry-run snapshot: %d games, max |diff| %.2e", nrow(b), max(abs(b$inc_margin - b$pm))) }
# opening lines LAST (evaluation only; home perspective, negative = home favoured; median of valid books' opening quotes, the R15 definition)
source("R/round15/market_lines.R")
ln <- r15_game_lines(r15_line_quotes(cl$get("/lines", list(year = 2026, seasonType = "regular", week = WEEK))))
g <- merge(g, ln[, .(game_id, open_line_home = open_home_spread, open_books)], by = "game_id", all.x = TRUE)
g[, `:=`(c2_spread = -c2_margin, inc_spread = -inc_margin)]                       # betting convention: negative = home favoured
setorder(g, kickoff, home_team)
ET <- function(x) format(as.POSIXct(x, tz = "UTC"), "%a %m/%d %I:%M %p", tz = "America/New_York")
w2 <- g[, .(kickoff_et = ET(kickoff), home_team, away_team, neutral_site = neutral, home_conference, away_conference, opponent_type = fifelse(home_fbs & away_fbs, "FBS vs FBS", "FBS vs FCS/lower"),
            opening_line_home_spread = open_line_home, c2_implied_spread = round(c2_spread, 1), incumbent_implied_spread = round(inc_spread, 1),
            c2_minus_incumbent = round(c2_spread - inc_spread, 1), c2_minus_opening_line = round(c2_spread - open_line_home, 1), incumbent_minus_opening_line = round(inc_spread - open_line_home, 1),
            opening_line_books = open_books, game_id)]
fwrite(w2, file.path(OUT, sprintf("game_spreads_c2_vs_incumbent_2026_wk%02d.csv", WEEK)))

# ============================ 6. sanity report ============================
say("\nSANITY: teams %d; mean power C2 %.3f / incumbent %.3f; SD C2 %.2f / incumbent %.2f; cor %.4f; SD(C2-inc) %.2f; max |diff| %.2f (%s)", nrow(tm), mean(tm$c2_power), mean(tm$inc_power),
    sd(tm$c2_power), sd(tm$inc_power), cor(tm$c2_power, tm$inc_power), sd(tm$diff_c2_minus_inc), max(abs(tm$diff_c2_minus_inc)), tm[which.max(abs(diff_c2_minus_inc)), team])
say("rank correlation %.4f; top-25 overlap %d of 25", cor(tm$c2_rank, tm$inc_rank, method = "spearman"), length(intersect(tm[c2_rank <= 25, team], tm[inc_rank <= 25, team])))
pp <- merge(as.data.table(c1x$priors[["2026"]])[, .(team_id, c1_pre = S$a * (pre_off - pre_def))], inc[, .(team_id, pre_power)], by = "team_id"); say("2026 C1 preseason prior (x a) vs incumbent pre_power: cor %.3f", cor(pp$c1_pre, pp$pre_power))
say("games: %d in week %d; with an opening line %d (FBS-vs-FBS %d, FBS-vs-FCS %d); without %d", nrow(g), WEEK, g[!is.na(open_line_home), .N], g[!is.na(open_line_home) & home_fbs & away_fbs, .N], g[!is.na(open_line_home) & !(home_fbs & away_fbs), .N], g[is.na(open_line_home), .N])
h <- g[!is.na(open_line_home) & home_fbs & away_fbs]
say("vs opening line (FBS-vs-FBS, n=%d): mean |C2 - line| %.2f (SD %.2f); mean |incumbent - line| %.2f (SD %.2f); mean |C2 - incumbent| %.2f (max %.1f)", nrow(h),
    mean(abs(h$c2_spread - h$open_line_home)), sd(h$c2_spread - h$open_line_home), mean(abs(h$inc_spread - h$open_line_home)), sd(h$inc_spread - h$open_line_home), mean(abs(h$c2_spread - h$inc_spread)), max(abs(h$c2_spread - h$inc_spread)))
say("same favourite as the opening line: C2 %d of %d, incumbent %d of %d; C2 and incumbent disagree on the favourite in %d games", h[sign(c2_spread) == sign(open_line_home), .N], nrow(h),
    h[sign(inc_spread) == sign(open_line_home), .N], nrow(h), h[sign(c2_spread) != sign(inc_spread), .N])
saveRDS(list(week = WEEK, cutoff = CUTOFF, pulled_utc = format(Sys.time(), tz = "UTC"), cfbd_calls = cl$log()), file.path(OUT, "run_info.rds"))
