# =============================================================================
# scripts/04_archive_prospective_snapshot.R — write-once pre-kickoff predictions.
#
# WHY THIS MATTERS: forward (prospective) evaluation is the only clean test left
# for any candidate, and the locked v10_refined Gate 5 test is scored ONLY from
# md5-verified incumbent predictions made before kickoff. As of 2026-09-24 the
# only snapshot that exists is 2026-09-09 (data/prospective/). Nothing in CI
# creates these files. Run this every week BEFORE the first kickoff (e.g. each
# Monday/Tuesday) to keep the forward record current.
#
# Usage (from the project root; live schedule strongly recommended):
#   CFB_REFRESH_SCHEDULE=true Rscript scripts/04_archive_prospective_snapshot.R
#
# Writes data/prospective/predictions_<UTC timestamp>.csv (+ .md5), read-only.
# It refuses to overwrite, to include started games, outcomes or market data.
# NOTE on Gate 5: the locked gate5_2026.R reads snapshots from the OLD folder
# (outputs/round4/prospective). See docs/EVALUATION_PROTOCOL.md, "Gate 5".
# =============================================================================
source("config/paths.R")
source("config/production.R")
suppressPackageStartupMessages(source(PATHS$model_ops))

season <- as.integer(Sys.getenv("CFB_SEASON", "2026"))
assert(identical(season, PRODUCTION$supported_season), "Frozen design supports 2026 only.")
as_of <- period_start(Sys.time())
schedule <- NULL
if (identical(Sys.getenv("CFB_REFRESH_SCHEDULE"), "true")) {
  cfg <- v4_config(); cfg$cache_dir <- file.path(PATHS$state, "prospective_live")
  schedule <- read_schedule(season, cfg, refresh = TRUE)
} else {
  warning("Using the frozen schedule: ratings will ignore every result after 2026-09-09. ",
          "Set CFB_REFRESH_SCHEDULE=true for a meaningful snapshot.", call. = FALSE)
}
r <- v5_build(season, as_of, schedule = schedule)
stamp <- format(Sys.time(), "%Y%m%dT%H%M%S")
path <- file.path(PATHS$prospective, sprintf("predictions_%s.csv", stamp))
p <- v5_archive_upcoming(r, path, season = season, schedule = schedule)
cat(sprintf("Archived %d upcoming FBS-vs-FBS predictions (cutoff %s) to %s\n", nrow(p),
            format(as_of, "%Y-%m-%d", tz = "UTC"), path))
