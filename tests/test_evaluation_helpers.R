# =============================================================================
# tests/test_evaluation_helpers.R — scoring helpers reproduce published numbers.
#
# Expected values come from the Round 4 report (docs/MODEL_HISTORY.md) and the
# Round 9/10/12 reports (P4-oriented bias). Run from the project root.
# =============================================================================
source("config/paths.R")
source(PATHS$eval_helpers)
near <- function(a, b, tol = 5e-4) isTRUE(abs(a - b) < tol)

dev <- load_incumbent_predictions("development"); cond <- load_incumbent_predictions("conditional")
stopifnot(nrow(dev) == 2320L, nrow(cond) == 2398L, !anyDuplicated(dev$game_id), !anyDuplicated(cond$game_id))
md <- margin_metrics(dev); mc <- margin_metrics(cond)
stopifnot(near(md$mae, 12.920), near(mc$mae, 12.518), near(md$calib_slope, 1.054, 1e-3), near(mc$calib_slope, 1.015, 1e-3))

# Season-indexed tier map: the 2026 Pac-12 is G5; Independents are "Other".
stopifnot(identical(tier_of(c("Pac-12", "Pac-12", "SEC", "FBS Independents"), c(2025, 2026, 2026, 2026)),
                    c("P4", "G5", "P4", "Other")))
stopifnot(identical(p4_orientation(c("SEC", "Sun Belt", "SEC", "Pac-12"), c("Sun Belt", "SEC", "ACC", "Big Ten"), 2026),
                    c(1L, -1L, 0L, -1L)))

# P4-oriented incumbent bias (Rounds 9-12): development 5.62, conditional 3.44.
stopifnot(near(p4_oriented_bias(dev)$bias, 5.616, 1e-3), near(p4_oriented_bias(cond)$bias, 3.441, 1e-3))

# A candidate identical to the incumbent has zero paired delta.
same <- compare_to_incumbent(cond[, c("game_id", "pred_margin")], "conditional", reps = 200L)
stopifnot(same$paired$estimate == 0, same$paired$block_high == 0)

# Bootstrap blocks are keyed on text cutoffs; missing keys fail loudly.
bad <- data.frame(season = 2020, cutoff = c("2020-09-07", NA), delta = 1:2)
stopifnot(inherits(try(block_bootstrap(bad), silent = TRUE), "try-error"))
blocks <- block_bootstrap(transform(dev, delta = abs_error), "delta", reps = 50L)
stopifnot(blocks$blocks > 3L)   # season x week blocks, not 3 season blocks (Round 12 run-1 defect)

# Mismatched game universes are refused.
stopifnot(inherits(try(compare_to_incumbent(cond[-1, c("game_id", "pred_margin")], "conditional"), silent = TRUE), "try-error"))
cat("PASS: metrics, tier map, P4-oriented bias, paired comparison and block bootstrap reproduce published values.\n")
