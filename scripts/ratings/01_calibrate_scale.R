# Calibrates the frozen OVR scale ONCE on the development seasons' rosters (2021, 2022); no outcome data is read.
# Writes R/ratings/ratings_knots.rds. Run before the freeze manifest; never re-run after it.
suppressMessages(library(jsonlite)); source("config/paths.R"); source("R/ratings/ratings_spec.R"); source("R/ratings/ratings_core.R")
fbs <- fromJSON("public/data/v2/teams.json")$teams$team
mu <- unlist(lapply(c(2021L, 2022L), function(s) build_ratings(s, fbs)$mu))
k <- fit_knots(mu); saveRDS(k, "R/ratings/ratings_knots.rds")
print(data.frame(mu = round(k$x, 4), ovr = k$y))
cat("pooled development rating points:", length(mu), "\n")
