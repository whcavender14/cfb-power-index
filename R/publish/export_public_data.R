# Export only allowlisted fields. Never source the model or read credentials here.
# Adapted from the old folder's scripts/export_public_data.R: identical logic;
# directories now come from config/paths.R (env vars still override), and team
# metadata is read from PATHS$teams_dir (data/reference) instead of the runtime
# cache. Output schema: docs/DATA_CONTRACT.md.
suppressPackageStartupMessages(library(jsonlite))
if (!exists("PATHS")) source(file.path(Sys.getenv("CFB_PROJECT_ROOT", "."), "config", "paths.R"))
season <- as.integer(Sys.getenv("CFB_SEASON", "2026"))
stopifnot(length(season) == 1L, !is.na(season), season >= 2000L)
data_dir <- PATHS$state
out_dir <- PATHS$public_data
read_optional <- function(path) if (file.exists(path)) readRDS(path) else NULL
iso <- function(x) if (length(x) && !is.na(x[1])) format(as.POSIXct(x[1], tz="UTC"), "%Y-%m-%dT%H:%M:%SZ", tz="UTC") else NA_character_
get_col <- function(x, name, n=nrow(x)) if (!is.null(x) && name %in% names(x)) x[[name]] else rep(NA_real_, n)
teams <- read_optional(file.path(PATHS$teams_dir, sprintf("teams_%d.rds", season)))
if (is.null(teams)) stop("Team metadata unavailable: cannot establish FBS membership or IDs.")
teams <- as.data.frame(teams)
teams <- teams[tolower(teams$classification) %in% "fbs", ]
stopifnot(nrow(teams) > 0, !anyNA(teams$team_id), !anyDuplicated(teams$team_id), !anyDuplicated(teams$school))
base <- data.frame(team_id=as.character(teams$team_id), team=teams$school,
                   conference=teams$conference, logo_url=teams$logo, stringsAsFactors=FALSE)
stopifnot(all(is.na(base$logo_url) | grepl("^https://", base$logo_url)))
resolve <- function(x) {
  if (is.null(x)) return(NULL)
  x <- as.data.frame(x)
  if ("season" %in% names(x)) stopifnot(all(x$season == season))
  if (!"team_id" %in% names(x)) {
    x$team_id <- base$team_id[match(x$team, base$team)]
    # Only metadata-supplied aliases are accepted, never fuzzy matching.
    for (alias in intersect(c("alt_name1", "alt_name2", "alt_name3"), names(teams))) {
      use <- is.na(x$team_id)
      x$team_id[use] <- as.character(teams$team_id[match(x$team[use], teams[[alias]])])
    }
  }
  x$team_id <- as.character(x$team_id)
  if ("is_fbs" %in% names(x)) stopifnot(!any(is.na(x$team_id) & x$is_fbs %in% TRUE))
  x <- x[!is.na(x$team_id) & x$team_id %in% base$team_id, , drop=FALSE]
  stopifnot(!anyDuplicated(x$team_id))
  x
}
align <- function(x, field) {
  if (is.null(x) || !field %in% names(x)) return(rep(NA_real_, nrow(base)))
  as.numeric(x[[field]][match(base$team_id, x$team_id)])
}
snapshot <- read_optional(file.path(data_dir, sprintf("production_ratings_%d_latest.rds", season)))
if (!is.null(snapshot)) stopifnot(snapshot$season == season, length(snapshot$week)==1L)
ratings <- resolve(snapshot$ratings)
week <- if (!is.null(snapshot)) snapshot$week else NA_integer_
updated <- if (!is.null(snapshot)) iso(snapshot$updated_at) else NA_character_
stopifnot(length(week) == 1L)
previous_snapshot <- if (!is.na(week) && week > 0) read_optional(file.path(data_dir, sprintf("production_ratings_%d_wk%02d.rds", season, week-1L))) else NULL
if (!is.null(previous_snapshot)) {
  stopifnot(previous_snapshot$season == season, previous_snapshot$week == week-1L)
  compatible <- all(vapply(c("candidate", "design_hash", "feature_hash"), function(k)
    !is.null(snapshot[[k]]) && identical(snapshot[[k]], previous_snapshot[[k]]), logical(1)))
  if (!compatible) previous_snapshot <- NULL
}
previous <- resolve(previous_snapshot$ratings)
r <- cbind(data.frame(season=season, week=week, updated_at=updated), base)
r$power_rating <- align(ratings, "power_rating")
r$offensive_rating <- align(ratings, "off_rating")
r$defensive_rating <- align(ratings, "def_rating")
r$weekly_change <- r$power_rating - align(previous, "power_rating")
r$preseason_change <- r$power_rating - align(ratings, "pre_power")

sim <- read_optional(file.path(data_dir, sprintf("simulations_%d_latest.rds", season)))
status <- read_optional(file.path(data_dir, sprintf("simulation_status_%d.rds", season)))
if (!is.null(status) && identical(status$status, "unavailable")) sim <- NULL
sim_week <- NA_integer_; sim_updated <- NA_character_; overall <- NULL
if (!is.null(sim)) {
  stopifnot(identical(as.integer(sim$season), season), length(sim$week)==1L,
            length(sim$updated_at)==1L, !is.null(sim$overall))
  sim_week <- as.integer(sim$week); sim_updated <- iso(sim$updated_at)
  overall <- resolve(sim$overall)
}
s <- cbind(data.frame(season=season, week=sim_week, updated_at=sim_updated), base)
s$projected_wins_current <- align(overall, "wins")
pre_sim <- read_optional(file.path(data_dir, sprintf("simulations_%d_preseason.rds", season)))
if (!is.null(pre_sim)) stopifnot(pre_sim$season == season, pre_sim$week == 0L, identical(pre_sim$wins_scope, sim$wins_scope) || is.null(sim))
s$projected_wins_preseason <- align(if (!is.null(pre_sim)) resolve(pre_sim$overall) else NULL, "wins")
s$playoff_probability <- align(overall, "playoff")
s$conference_title_probability <- align(overall, "conf_champ")
s$national_title_probability <- align(overall, "won_natty")
vegas_path <- file.path(data_dir, sprintf("vegas_%d_preseason.csv", season))
vegas <- if (file.exists(vegas_path)) resolve(read.csv(vegas_path, stringsAsFactors=FALSE)) else NULL
s$vegas_win_total_preseason <- align(vegas, "vegas_win_total_preseason")
for (field in c("playoff_probability", "conference_title_probability", "national_title_probability")) {
  v <- s[[field]]; stopifnot(all(is.na(v) | (is.finite(v) & v >= 0 & v <= 1)))
}
for (x in list(r, s)) for (field in names(x)[vapply(x, is.numeric, logical(1))]) stopifnot(all(is.na(x[[field]]) | is.finite(x[[field]])))
envelope <- function(rows, wk, date, model, extra=list()) c(list(schema_version=1L, season=season, week=wk,
  updated_at=date, status=if (any(!is.na(rows[[if ("power_rating" %in% names(rows)) "power_rating" else "projected_wins_current"]]))) "available" else "unavailable",
  model=model, teams=rows), extra)
rating_doc <- envelope(r, week, updated, paste0("vCurrent / ", if (!is.null(snapshot)) snapshot$candidate else "frozen selected model"), list(
  rated_teams=sum(!is.na(r$power_rating)), total_teams=nrow(base), defensive_higher_is_better=FALSE,
  as_of=if (!is.null(snapshot)) iso(snapshot$as_of) else NA_character_,
  source="scripts/01_build_ratings.R",
  weekly_comparison_week=if (!is.null(previous)) week-1L else NA_integer_,
  preseason_source=if (!is.null(ratings)) "Production model pre_power" else NA_character_))
# Simulation model name: the candidate recorded by the ratings build inside the simulation output (never assumed).
sim_model <- if (!is.null(sim)) sim$model_metadata$candidate else if (!is.null(snapshot)) snapshot$candidate else NULL
stopifnot(is.null(sim_model) || (is.character(sim_model) && length(sim_model) == 1L && nzchar(sim_model)))
sim_doc <- envelope(s, sim_week, sim_updated, paste0("vCurrent / ", if (!is.null(sim_model)) sim_model else "frozen selected model", " + cfbseedR"), list(
  unavailable_reason=if (is.null(sim)) "No completed simulation output is available for this season." else NA_character_,
  simulation_count=if (!is.null(sim)) sim$simulation_count else NA_integer_,
  playoff_format=if (!is.null(sim)) sim$playoff_format else NA_character_,
  wins_scope=if (!is.null(sim)) sim$wins_scope else NA_character_,
  as_of=if (!is.null(sim)) iso(sim$as_of) else NA_character_,
  assumptions=if (!is.null(sim)) sim$simulation_assumptions else list()))
dir.create(out_dir, recursive=TRUE, showWarnings=FALSE)
write_doc <- function(doc, name, wk) {
  write_json(doc, file.path(out_dir, paste0(name, ".json")), auto_unbox=TRUE, na="null", null="null", digits=8, pretty=TRUE)
  if (!is.na(wk)) {
    archive <- file.path(out_dir, as.character(season), sprintf("week-%02d", wk))
    dir.create(archive, recursive=TRUE, showWarnings=FALSE)
    target <- file.path(archive, paste0(name, ".json"))
    # A week archive published by a different model is a historical record: keep it (same-model reruns still refresh).
    old_model <- if (file.exists(target)) tryCatch(jsonlite::fromJSON(target)$model, error=function(e) NULL) else NULL
    if (!is.null(old_model) && !identical(old_model, doc$model)) {
      message(sprintf("Keeping %s: week %d was published by '%s'.", target, wk, old_model))
    } else file.copy(file.path(out_dir, paste0(name, ".json")), target, overwrite=TRUE)
  }
}
write_doc(rating_doc, "ratings", week)
write_doc(sim_doc, "simulations", sim_week)
cat(sprintf("Exported %d FBS teams; %d rated. Simulations: %s.\n", nrow(base), rating_doc$rated_teams, sim_doc$status))
