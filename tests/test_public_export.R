# Exercise the exporter against isolated copies of the supplied reference inputs.
# Adapted from the old folder's tests/test_public_export.R: same assertions;
# inputs come from data/reference and the exporter's directories are pointed at
# a scratch folder by overriding PATHS. Run from the project root:
#   Rscript tests/test_public_export.R
source("config/paths.R")
root <- PATHS$root
scratch <- tempfile("cfb-export-test-")
dir.create(scratch)
input <- file.path(scratch, "input"); output <- file.path(scratch, "public")
dir.create(input)
stopifnot(file.copy(file.path(PATHS$teams_dir, "teams_2026.rds"), file.path(input, "teams_2026.rds")))
stopifnot(file.copy(file.path(PATHS$snapshot_seed, "production_ratings_2026_latest.rds"),
                    file.path(input, "production_ratings_2026_latest.rds")))
old_env <- Sys.getenv("CFB_SEASON", unset=NA)
Sys.setenv(CFB_SEASON="2026")
PATHS$state <- input; PATHS$public_data <- output; PATHS$teams_dir <- input
run_export <- function() {
  sys.source(PATHS$export_public, envir=new.env(parent=globalenv()))
  list(r=jsonlite::fromJSON(file.path(output, "ratings.json")),
       s=jsonlite::fromJSON(file.path(output, "simulations.json")))
}
x <- run_export()
stopifnot(nrow(x$r$teams)==138L, x$r$rated_teams==138L,
          all(is.na(x$r$teams$weekly_change)), x$s$status=="unavailable",
          all(is.na(x$s$teams$projected_wins_current)))
current <- readRDS(file.path(input, "production_ratings_2026_latest.rds"))
ix <- match(current$ratings$team_id, x$r$teams$team_id)
stopifnot(!anyNA(ix), x$r$source == "scripts/01_build_ratings.R", !x$r$defensive_higher_is_better)
for (pair in list(c("power_rating","power_rating"), c("off_rating","offensive_rating"), c("def_rating","defensive_rating")))
  stopifnot(max(abs(current$ratings[[pair[1]]]-x$r$teams[[pair[2]]][ix])) < 1e-7)
stopifnot(max(abs(x$r$teams$preseason_change[ix]-(current$ratings$power_rating-current$ratings$pre_power))) < 1e-7)
previous <- current
previous$week <- 0L
previous$ratings$power_rating <- previous$ratings$power_rating - 2
saveRDS(previous, file.path(input, "production_ratings_2026_wk00.rds"))
x <- run_export()
stopifnot(all(abs(na.omit(x$r$teams$weekly_change)-2)<1e-7))
# A same-week rerun must still compare to week zero, not to its own earlier run.
current$ratings$power_rating <- current$ratings$power_rating + 1
saveRDS(current, file.path(input, "production_ratings_2026_latest.rds"))
x <- run_export()
stopifnot(all(abs(na.omit(x$r$teams$weekly_change)-3)<1e-7))
# Different frozen models must never be compared, even within the same week.
previous$design_hash <- "different-model"
saveRDS(previous, file.path(input, "production_ratings_2026_wk00.rds"))
x <- run_export()
stopifnot(all(is.na(x$r$teams$weekly_change)))
# Failed simulation status must hide an older otherwise valid simulation.
source_sim <- file.path(root,"output","state","simulations_2026_latest.rds")  # created by scripts/02_simulate_season.R
if (file.exists(source_sim)) {
  sim <- readRDS(source_sim)
  sim$games <- NULL; sim$standings <- NULL; sim$team_wins <- NULL
  saveRDS(sim, file.path(input,"simulations_2026_latest.rds"))
  x <- run_export(); stopifnot(x$s$status=="available")
  saveRDS(list(status="unavailable"), file.path(input,"simulation_status_2026.rds"))
  x <- run_export()
  stopifnot(x$s$status=="unavailable", is.null(x$s$updated_at), all(is.na(x$s$teams$playoff_probability)))
}
# Malformed identity cannot silently fan out table rows.
bad_teams <- readRDS(file.path(input,"teams_2026.rds"))
bad_teams$team_id[2] <- bad_teams$team_id[1]
saveRDS(bad_teams,file.path(input,"teams_2026.rds"))
stopifnot(inherits(try(run_export(),silent=TRUE),"try-error"))
if (is.na(old_env)) Sys.unsetenv("CFB_SEASON") else Sys.setenv(CFB_SEASON=old_env)
cat("PASS: missing sources, exact previous week, same-week reruns, failed simulation, duplicate IDs.\n")
