# Writes public/data/v2/recruiting/ (R/publish/recruiting.R, transfers.R): hs_<year>.json and teams_<year>.json for every
# class from 2018 to next year's open class, portal_<year>.json for every portal year from 2021 (the open year once it
# has rows), cards.json (team-page Recruiting card) and dashboard.json. Runs in the weekly export
# after the player profiles (skip with CFB_RECRUITING=false), or alone:
#   Rscript scripts/export_recruiting.R
# CFBD calls: 3 a run (the open class's players and teams, the open portal year); finished classes, rankings, talent,
# portal years and rosters come from data/reference/player_cache after their first pull.
suppressPackageStartupMessages(library(jsonlite))
if (!exists("PATHS")) source(file.path(Sys.getenv("CFB_PROJECT_ROOT", "."), "config", "paths.R"))
source(file.path(PATHS$root, "R", "publish", "player_profiles.R"))
source(file.path(PATHS$root, "R", "publish", "recruiting.R"))
source(file.path(PATHS$root, "R", "publish", "transfers.R"))
v2 <- file.path(PATHS$public_data, "v2")
index <- fromJSON(file.path(v2, "index.json"), simplifyVector = FALSE)
index_rows <- fromJSON(file.path(v2, "index.json"))$teams
teams <- fromJSON(file.path(v2, "teams.json"))$teams
season <- index$meta$season
x <- pull_recruiting(season)
if (is.null(x$recruits) || !nrow(x$recruits)) stop("Recruiting: no recruit rows; keeping the previous files.")
has_profile <- function(ids) file.exists(file.path(v2, "player", paste0(ids, ".json")))
docs <- build_recruiting(x, teams, index_rows, has_profile)

# Transfer portal: rows matched to athlete ids (rosters + box scores), per-year documents, team-card and dashboard summaries.
portal <- cached_years("portal_", PORTAL_FIRST, season + 1L, season, function(y) .quiet(cfbfastR::cfbd_recruiting_transfer_portal(year = y)))
box <- career_games(season, index$meta$ratings_week)
box <- unique(box[, c("season", "team", "athlete_id", "athlete_name")])
matched <- match_portal(portal, roster_years((PORTAL_FIRST - 1L):season, season), box)
portal_docs <- build_transfers(matched, teams, has_profile, season)
last_portal <- max(as.integer(names(portal_docs)))
pd <- portal_docs[[as.character(last_portal)]]
for (k in seq_along(docs$cards$teams)) {
  z <- Filter(function(t) t[[1]] == docs$cards$teams[[k]]$team_id, pd$teams)
  docs$cards$teams[[k]]$portal <- if (length(z)) list(year = last_portal, `in` = z[[1]][[3]], out = z[[1]][[4]], churn = z[[1]][[5]], star_churn = z[[1]][[10]], rank = z[[1]][[2]], teams = length(pd$teams)) else NULL
}
summ <- function(t) list(team_id = t[[1]], rank = t[[2]], `in` = t[[3]], out = t[[4]], churn = t[[5]], star_churn = t[[10]])
scored <- Filter(function(t) !is.na(t[[10]]), pd$teams)   # teams with a Star Churn (stars known on both sides)
docs$dashboard$portal <- list(year = last_portal, top = lapply(head(scored, 5), summ), bottom = lapply(rev(tail(scored, 5)), summ),
                              match = pd$match, fbs_rows = pd$fbs_rows)

out_dir <- file.path(v2, "recruiting")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)   # overwritten in place (deleting the folder makes iCloud keep conflict copies)
source_text <- "CollegeFootballData recruiting data (247Sports Composite): high-school recruits, team class rankings, team talent"
put <- function(body, name) {
  write_json(c(list(meta = index$meta, source = source_text, pulled_at = format(as.POSIXct(attr(x, "pulled_at"), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")), body),
             file.path(out_dir, name), auto_unbox = TRUE, na = "null", null = "null", digits = 6)
  name
}
written <- c(unlist(lapply(docs$hs, function(d) put(d, sprintf("hs_%d.json", d$year)))),
             unlist(lapply(docs$teams, function(d) put(d, sprintf("teams_%d.json", d$year)))),
             unlist(lapply(portal_docs, function(d) put(d, sprintf("portal_%d.json", d$year)))),
             put(c(docs$cards, list(classes = as.integer(names(docs$hs)), portal_years = as.integer(names(portal_docs)))), "cards.json"),
             put(c(docs$dashboard, list(classes = as.integer(names(docs$hs)), portal_years = as.integer(names(portal_docs)))), "dashboard.json"))
stale <- setdiff(list.files(out_dir, pattern = "\\.json$"), written)
if (length(stale)) invisible(file.remove(file.path(out_dir, stale)))
for (d in docs$hs) cat(sprintf("Recruiting %d: %4d recruits, %3d FBS classes%s\n", d$year, length(d$rows), length(docs$teams[[as.character(d$year)]]$rows),
                               if (docs$teams[[as.character(d$year)]]$ranked) "" else " (no CFBD ranking yet)"))
for (d in portal_docs) cat(sprintf("Portal %d: %4d rows (%4d with an FBS program); matched %d by destination roster, %d by origin; %d ambiguous, %d conflicting, %d unmatched\n",
                                   d$year, d$rows_total, d$fbs_rows, d$match$destination, d$match$origin, d$match$ambiguous, d$match$conflict, d$match$unmatched))
