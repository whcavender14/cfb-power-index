# =============================================================================
# tests/test_reproduce_incumbent.R — the revised folder reproduces production.
#
# 1. Every frozen input matches its recorded MD5.
# 2. v5_build() at the 2026-09-07 cutoff reproduces the committed week-1
#    production snapshot (built by GitHub Actions with the old code) EXACTLY.
#    Later weekly snapshots used a live CFBD schedule, so they can only be
#    reproduced with CFB_REFRESH_SCHEDULE=true and an API key.
# 3. Zero-games identity: before any 2026 game counts, power = scaled prior.
# Run from the project root: Rscript tests/test_reproduce_incumbent.R  (~10 s)
# =============================================================================
source("config/paths.R")
source("config/production.R")
suppressPackageStartupMessages(source(PATHS$model_ops))

v <- v5_verify_frozen_inputs()
stopifnot(all(v$ok))

snap <- readRDS(file.path(PATHS$snapshot_seed, "production_ratings_2026_wk01.rds"))
stopifnot(snap$candidate == PRODUCTION$candidate, snap$design_hash == PRODUCTION$design_file_md5,
          snap$feature_hash == PRODUCTION$feature_object_hash)
r <- v5_build(2026, snap$as_of)
ix <- match(snap$ratings$team_id, r$team_id)
stopifnot(!anyNA(ix), nrow(r) == 138L)
for (col in c("power_rating", "off_rating", "def_rating", "pre_power", "prior_contribution", "current_contribution")) {
  d <- max(abs(r[[col]][ix] - snap$ratings[[col]]))
  if (d > 1e-9) stop("Mismatch in ", col, ": ", d)
}
stopifnot(identical(attr(r, "design_hash"), PRODUCTION$design_file_md5),
          abs(attr(r, "hfa") - PRODUCTION$hfa_points) < 1e-12,
          max(abs(r$power_rating - (r$off_rating - r$def_rating))) < 1e-9)

# Before the first 2026 kickoff no current-season evidence exists.
r0 <- v5_build(2026, as.POSIXct("2026-08-01", tz = "UTC"))
stopifnot(all(r0$games_played == 0L), max(abs(r0$current_contribution)) < 1e-9)
cat("PASS: frozen inputs verified; week-1 production snapshot reproduced exactly; zero-game identity holds.\n")
