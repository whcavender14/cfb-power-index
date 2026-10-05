# =============================================================================
# R/publish/pull_player_ppa.R: player PPA and success rate for the /players/ leaderboards
# (docs/website/PLAYER_DATA.md). Display only: nothing here feeds the model.
#
# Two direct CFBD calls per weekly run (httr2; logged with the call count and the account's remaining calls):
#   /ppa/players/season?year=        Predicted Points Added per play and in total (passers, rushers, receivers only).
#                                    CFBD has no week filter here: the pull is season to date at `pulled_at`, so the
#                                    exporter publishes it only if no game after the ratings week had kicked off by then.
#   /stats/player/success?year=&endWeek=&seasonType=regular   passing and rushing success (plays, successes), cut at
#                                    the ratings week.
# Written to output/state/player_ppa_<season>.rds: list(ppa, success) with attributes season, end_week, pulled_at.
# A failed call keeps the previous file; the exporter then shows those columns only if that file still lines up.
# =============================================================================
CFBD_BASE <- "https://api.collegefootballdata.com"

# One GET; returns the parsed JSON (simplified) or NULL, and logs the call.
cfbd_get <- function(path, query) {
  req <- httr2::request(CFBD_BASE) |> httr2::req_url_path_append(path) |> httr2::req_url_query(!!!query) |>
    httr2::req_auth_bearer_token(Sys.getenv("CFBD_API_KEY")) |> httr2::req_timeout(120) |>
    httr2::req_error(is_error = function(r) FALSE)
  r <- tryCatch(httr2::req_perform(req), error = function(e) { message("  CFBD ", path, " failed: ", conditionMessage(e)); NULL })
  if (is.null(r)) return(NULL)
  left <- httr2::resp_header(r, "x-calllimit-remaining")
  message(sprintf("  CFBD call %s -> HTTP %d (calls left: %s)", path, httr2::resp_status(r), if (is.null(left)) "?" else left))
  if (httr2::resp_status(r) != 200L) return(NULL)
  jsonlite::fromJSON(httr2::resp_body_string(r, encoding = "UTF-8"), flatten = TRUE)
}

# /ppa/players/season rows -> one row per player and team. Columns keep CFBD's names, flattened (averagePPA.pass ->
# avg_pass, totalPPA.all -> total_all).
parse_player_ppa <- function(x) {
  if (is.null(x) || !NROW(x)) return(NULL)
  x <- as.data.frame(x)
  names(x) <- sub("^averagePPA\\.", "avg_", sub("^totalPPA\\.", "total_", names(x)))
  x$id <- as.character(x$id)
  x[!duplicated(x[, c("id", "team")]), , drop = FALSE]
}

# /stats/player/success rows -> id, team, pass_plays, pass_successes, rush_plays, rush_successes.
parse_player_success <- function(x) {
  if (is.null(x) || !NROW(x)) return(NULL)
  x <- as.data.frame(x)
  n <- function(k) { v <- suppressWarnings(as.integer(x[[k]])); ifelse(is.na(v), 0L, v) }
  out <- data.frame(id = as.character(x$id), team = x$team, pass_plays = n("passing.plays"), pass_successes = n("passing.successes"),
                    rush_plays = n("rushing.plays"), rush_successes = n("rushing.successes"), stringsAsFactors = FALSE)
  out[!duplicated(out[, c("id", "team")]), , drop = FALSE]
}

# options(cfb.pull_ppa = FALSE) loads only the helpers above (tests, local seeding).
if (!isFALSE(getOption("cfb.pull_ppa"))) local({
  season <- as.integer(Sys.getenv("CFB_SEASON", "2026"))
  snap_file <- file.path(PATHS$state, sprintf("production_ratings_%d_latest.rds", season))
  week <- if (file.exists(snap_file)) as.integer(readRDS(snap_file)$week) else as.integer(Sys.getenv("CFB_PLAYER_WEEK", NA))
  if (is.na(week) || week < 1L) { message("Player PPA: no ratings week; skipped."); return(invisible()) }
  message(sprintf("Player PPA: 2 CFBD calls (/ppa/players/season, /stats/player/success through week %d)", week))
  pulled_at <- Sys.time()
  ppa <- parse_player_ppa(cfbd_get("ppa/players/season", list(year = season)))
  success <- parse_player_success(cfbd_get("stats/player/success", list(year = season, endWeek = week, seasonType = "regular")))
  if (is.null(ppa) || is.null(success)) { message("Player PPA: a pull failed; keeping the previous file."); return(invisible()) }
  out <- list(ppa = ppa, success = success)
  attr(out, "season") <- season; attr(out, "end_week") <- week; attr(out, "pulled_at") <- pulled_at
  saveRDS(out, file.path(PATHS$state, sprintf("player_ppa_%d.rds", season)))
  cat(sprintf("Player PPA: %d players with PPA, %d with success rates (weeks 1-%d)\n", nrow(ppa), nrow(success), week))
})
