# Round 15 design probe 02: CFBD coverage for data we do not hold yet (read-only GET requests).
# Budget-guarded: stops before MAX_CALLS or if the account's remaining calls fall below FLOOR.
# Every response is cached under output/dev/round15/raw/ (git-ignored) so no call is ever repeated.
# The API key is read from CFBD_API_KEY and never printed or written.
# No model fits and no outcome analysis: counts and coverage only.
# Usage (repo root): Rscript scripts/round15/02_probe_cfbd_coverage.R
source("config/paths.R")
suppressPackageStartupMessages({ library(data.table); library(httr2); library(jsonlite) })
raw <- "output/dev/round15/raw"; out <- "docs/round15/coverage"
dir.create(raw, recursive = TRUE, showWarnings = FALSE); dir.create(out, recursive = TRUE, showWarnings = FALSE)
MAX_CALLS <- 110L; FLOOR <- 300L; calls <- 0L
key <- Sys.getenv("CFBD_API_KEY"); if (!nzchar(key)) stop("CFBD_API_KEY is not set")
log <- list()

cfbd <- function(path, query = list(), tag = NULL) {
  tag <- tag %||% paste(c(gsub("/", "_", sub("^/", "", path)), unlist(Map(paste0, names(query), query))), collapse = "_")
  f <- file.path(raw, paste0(tag, ".rds"))
  if (file.exists(f)) return(readRDS(f))
  if (calls >= MAX_CALLS) stop("Call budget reached; rerun later (cached responses are kept)")
  req <- request("https://api.collegefootballdata.com") |> req_url_path_append(path) |> req_url_query(!!!query) |>
    req_headers(Authorization = paste("Bearer", key), Accept = "application/json") |> req_error(is_error = function(r) FALSE)
  resp <- req_perform(req); calls <<- calls + 1L; Sys.sleep(1)
  rem <- suppressWarnings(as.integer(resp_header(resp, "X-CallLimit-Remaining")))
  log[[length(log) + 1]] <<- data.table(tag, status = resp_status(resp), remaining_after = rem, bytes = length(resp_body_raw(resp)))
  if (resp_status(resp) != 200) { message(tag, " -> HTTP ", resp_status(resp)); return(NULL) }
  x <- fromJSON(resp_body_string(resp), simplifyVector = TRUE, flatten = TRUE)
  saveRDS(x, f)
  if (is.finite(rem) && rem < FLOOR) stop("Remaining account calls below floor (", rem, "); stopping")
  x
}
`%||%` <- function(a, b) if (is.null(a)) b else a

info0 <- cfbd("/info", tag = sprintf("info_start_%s", format(Sys.time(), "%Y%m%dT%H%M")))
if (!is.null(info0) && is.finite(info0$remainingCalls %||% NA) && info0$remainingCalls < FLOOR + MAX_CALLS) stop("Not enough account calls for this probe")

Y <- 2014:2026
res <- list(); add <- function(source, season, metric, value) res[[length(res) + 1]] <<- data.table(source, season, metric, value = as.numeric(value))
fbs <- function(y) { f <- if (y >= 2015) file.path(PATHS$frozen, "cfb_data_v3", sprintf("raw_schedule_%d.rds", y)) else
  file.path("/Users/willcavender/Desktop/CFB Modeling Backup/CFB-Modeling-round6/outputs/round6/raw", sprintf("raw_schedule_%d.rds", y))
  g <- readRDS(f); list(ids = unique(c(g$home_id[g$home_division == "fbs"], g$away_id[g$away_division == "fbs"])),
                        names = unique(c(g$home_team[g$home_division == "fbs"], g$away_team[g$away_division == "fbs"]))) }

# 1. Rosters with player IDs (links players across seasons and teams; basis for QB and transfer reconstruction)
for (y in Y) { r <- as.data.table(cfbd("/roster", list(year = y, classification = "fbs"))); if (!nrow(r)) next; F <- fbs(y)
  add("roster", y, "players", nrow(r)); add("roster", y, "fbs_team_share", mean(F$names %in% r$team))
  add("roster", y, "id_present_share", mean(!is.na(r$id))); add("roster", y, "class_year_present_share", mean(is.finite(r$year)))
  add("roster", y, "recruit_ids_present_share", mean(lengths(r$recruitIds) > 0)) }
# 2. Player season statistics: passing (QB identity and volume) and defensive (reconstructing defensive returning production)
for (y in Y) for (cat in c("passing", "defensive")) { s <- as.data.table(cfbd("/stats/player/season", list(year = y, category = cat))); if (!nrow(s)) next
  F <- fbs(y); add(paste0("player_stats_", cat), y, "rows", nrow(s)); add(paste0("player_stats_", cat), y, "fbs_team_share", mean(F$names %in% s$team))
  add(paste0("player_stats_", cat), y, "player_id_present_share", mean(!is.na(s$playerId) & nzchar(as.character(s$playerId)))) }
# 3. Returning production, one call (all seasons) with per-year fallback
rp <- as.data.table(cfbd("/player/returning", list(), tag = "player_returning_all"))
if (!nrow(rp) || uniqueN(rp$season) < 5) rp <- rbindlist(lapply(Y, function(y) as.data.table(cfbd("/player/returning", list(year = y)))), fill = TRUE)
for (y in intersect(Y, rp$season)) { F <- fbs(y); r <- rp[season == y]
  add("returning_cfbd_api", y, "fbs_team_share", mean(F$names %in% r$team))
  add("returning_cfbd_api", y, "passing_ppa_share_present", mean(is.finite(r$percentPassingPPA))) }
# 4. Recruiting: individual recruits (athlete IDs link to rosters) and team classes
for (y in 2010:2026) { r <- as.data.table(cfbd("/recruiting/players", list(year = y))); if (!nrow(r)) next
  add("recruits", y, "recruits", nrow(r)); add("recruits", y, "athlete_id_present_share", mean(!is.na(r$athleteId) & nzchar(as.character(r$athleteId))))
  add("recruits", y, "rating_present_share", mean(is.finite(r$rating))); add("recruits", y, "qb_recruits", sum(r$position %in% c("PRO", "DUAL", "QB"))) }
rt <- as.data.table(cfbd("/recruiting/teams", list(), tag = "recruiting_teams_all"))
for (y in sort(unique(rt$year))) add("recruiting_team_classes", y, "teams", rt[year == y, .N])
# 5. NFL draft (departure information knowable in late April)
dp <- as.data.table(cfbd("/draft/picks", list(), tag = "draft_picks_all"))
if (nrow(dp)) for (y in intersect(2014:2026, dp$year)) { d <- dp[year == y]
  add("draft", y, "picks", nrow(d)); add("draft", y, "college_athlete_id_present_share", mean(!is.na(d$collegeAthleteId))) }
# 6. Coaches: tenures (interim flags, effective dates) and coach-seasons
ct <- as.data.table(cfbd("/coaches/tenures", list(), tag = "coaches_tenures_all"))
cs <- as.data.table(cfbd("/coaches/seasons", list(minYear = 2013, maxYear = 2026), tag = "coaches_seasons_2013_2026"))
if (nrow(cs)) for (y in intersect(Y, cs$year)) add("coach_seasons_api", y, "rows", cs[year == y, .N])
if (nrow(ct)) add("coach_tenures_api", NA, "rows", nrow(ct))
# 7. Polls (Tier B candidate): preseason availability and depth
for (y in Y) { rk <- cfbd("/rankings", list(year = y)); if (is.null(rk) || !length(rk)) next
  rk <- as.data.table(rk); wk1 <- rk[seasonType == "regular"][week == min(week)]
  polls <- if (nrow(wk1)) rbindlist(lapply(seq_len(nrow(wk1)), function(i) { p <- as.data.table(wk1$polls[[i]])
    rbindlist(lapply(seq_len(nrow(p)), function(j) data.table(poll = p$poll[j], n = NROW(p$ranks[[j]])))) })) else data.table()
  add("polls", y, "first_regular_week", if (nrow(wk1)) wk1$week[1] else NA)
  add("polls", y, "ap_teams_listed_first_week", polls[poll == "AP Top 25", sum(n)])
  add("polls", y, "coaches_teams_listed_first_week", polls[grepl("Coaches", poll), sum(n)]) }
# 8. Knowledge-date checks: fresh pulls of seasons we already hold (compared with the 2026-09-10 frozen copies in probe 03)
for (y in 2024:2026) { cfbd("/talent", list(year = y)); cfbd("/player/portal", list(year = y)) }
# 9. Havoc with pass breakups (not recoverable from play-by-play)
for (y in c(2014, 2019, 2025)) { h <- as.data.table(cfbd("/stats/game/havoc", list(year = y))); if (nrow(h)) add("havoc_game_api", y, "team_game_rows", nrow(h)) }
# 10. Comparator ratings (descriptive only, never inputs): end-of-season availability
for (ep in c("/ratings/sp", "/ratings/fpi")) { x <- as.data.table(cfbd(ep, list(), tag = paste0(gsub("/", "_", sub("^/", "", ep)), "_all")))
  if (nrow(x)) for (y in intersect(Y, x$year)) add(paste0("comparator_", basename(ep)), y, "teams", x[year == y, .N]) }

info1 <- cfbd("/info", tag = sprintf("info_end_%s", format(Sys.time(), "%Y%m%dT%H%M")))
cov <- rbindlist(res)
fwrite(cov, file.path(out, "cfbd_probe_long.csv"))
wide <- dcast(cov, source + metric ~ season, value.var = "value", fun.aggregate = function(v) v[1])
num <- setdiff(names(wide), c("source", "metric"))
wide[, (num) := lapply(.SD, function(v) ifelse(abs(v) < 1 & v != 0, round(v, 3), round(v, 1))), .SDcols = num]
fwrite(wide, file.path(out, "cfbd_coverage_matrix.csv"))
calls_log <- rbindlist(log, fill = TRUE)
fwrite(data.table(calls_this_run = calls, patron_level = info0$patronLevel %||% NA,
                  remaining_start = info0$remainingCalls %||% NA, remaining_end = info1$remainingCalls %||% NA),
       file.path(out, "cfbd_probe_budget.csv"))
if (nrow(calls_log)) fwrite(calls_log, file.path(out, "cfbd_probe_calls.csv"))
print(wide, nrows = 300, width = 250); cat("calls this run:", calls, "\n")
