# Stage 4 inputs (display-only player ratings; docs/website/PLAYER_RATINGS_PREDECLARATION.md). One-time historical pulls,
# cached in data/reference/player_cache/hist_<kind>_<year>.rds and never pulled again. 30 CFBD calls:
#   stats/player/season, ppa/players/season, player/usage, stats/player/success for 2021-2025 (20),
#   draft/picks for 2022-2026 (5), stats/season (team season stats, OL unit adjustment) for 2021-2025 (5).
suppressPackageStartupMessages(library(jsonlite))
source("config/paths.R"); options(cfb.pull_ppa = FALSE); source("R/publish/pull_player_ppa.R")
dir <- file.path(PATHS$reference, "player_cache")
get <- function(kind, y, path, q) {
  f <- file.path(dir, sprintf("hist_%s_%d.rds", kind, y))
  if (file.exists(f)) return(invisible())
  message(sprintf("  CFBD call: %s year %d", path, y))
  x <- cfbd_get(path, q); if (is.null(x)) stop("pull failed: ", path, " ", y)
  saveRDS(as.data.frame(x), f)
}
for (y in 2021:2025) {
  get("stats", y, "stats/player/season", list(year = y, seasonType = "regular"))
  get("ppa", y, "ppa/players/season", list(year = y))
  get("usage", y, "player/usage", list(year = y))
  get("success", y, "stats/player/success", list(year = y, seasonType = "regular"))
  get("teamstats", y, "stats/season", list(year = y))
}
for (y in 2022:2026) get("draft", y, "draft/picks", list(year = y))
