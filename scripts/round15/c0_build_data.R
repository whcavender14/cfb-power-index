# Round 15 construction step 0: build and cache candidate inputs (no scoring, no market data).
source("config/paths.R"); source("config/production.R")
suppressPackageStartupMessages({ source(PATHS$model_ops); library(data.table); source("R/round15/candidates/data.R") })
d <- r15_build_data(force = TRUE)
cat("seasons:", names(d$sch), "\ncomponents:", length(d$base$snap), "snapshots\npbp rows:", nrow(d$pbp), "\n")
print(d$pbp[, .(rows = .N, sr = sum(!is.na(sr)), fum = sum(fumbles, na.rm = TRUE), qb = sum(!is.na(passer))), by = season])
