# Round 15 P3: pass iff >= 97% of dropbacks yield a passer name in every season 2013-2025 (predeclaration §4.3).
# Play text only; no outcome analysis. 2026 dry-run pulls reported for information.
suppressPackageStartupMessages(library(data.table)); source("R/round15/prep/passer_parser.R")
raw6 <- "/Users/willcavender/Desktop/CFB Modeling Backup/CFB-Modeling-round6/outputs/round6/raw"
one <- function(p, y) { d <- p[play_type %in% r15_dropback_types]; nm <- r15_passer(d$play_text)
  g <- d[, .(n = .N), by = .(game_id, offense)][, .N]
  data.table(season = y, dropbacks = nrow(d), parsed_share = mean(!is.na(nm)), team_games_with_primary_ge10 =
    d[, .(nm = r15_passer(play_text)), by = .(game_id, offense)][!is.na(nm), .N, by = .(game_id, offense, nm)][, max(N), by = .(game_id, offense)][V1 >= 10, .N] / g) }
res <- rbindlist(lapply(2013:2025, function(y) one(as.data.table(readRDS(file.path(raw6, sprintf("plays_%d.rds", y)))), y)))
live <- list.files("output/dev/round15/forward_dryrun/pbp/2026", "\\.rds$", full.names = TRUE)
if (length(live)) { p <- unique(rbindlist(lapply(live, function(f) as.data.table(readRDS(f))), fill = TRUE), by = c("game_id", "play_id")); res <- rbind(res, one(p, 2026L)) }
v <- data.table(step = "P3", rule = "passer parsed on >= 97% of dropbacks in every season 2013-2025",
                min_share = res[season <= 2025, min(parsed_share)], worst_season = res[season <= 2025][which.min(parsed_share), season])
v[, pass := min_share >= 0.97]; v[, parser_sha256 := digest::digest(file = "R/round15/prep/passer_parser.R", algo = "sha256")]
fwrite(res, "docs/round15/prep/p3_passer_parse_by_season.csv"); fwrite(v, "docs/round15/prep/p3_verdict.csv"); print(res); print(v)
