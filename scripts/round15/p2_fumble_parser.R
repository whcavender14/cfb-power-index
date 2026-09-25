# Round 15 P2: evaluate the extended fumble parser against its predeclared rule (§4.3):
#   pass iff 2025 recovery >= 90% AND every 2013-2024 fumble-row classification (type and yards) is unchanged vs Round 8.
# Reads play text only; no outcome analysis. 2026 recovery on the forward dry-run pulls is reported for information.
suppressPackageStartupMessages(library(data.table))
e <- new.env(); sys.source("R/forward/vendor/round13_sr_stack.R", envir = e); source("R/round15/prep/fumble_parser.R")
raw6 <- "/Users/willcavender/Desktop/CFB Modeling Backup/CFB-Modeling-round6/outputs/round6/raw"
one <- function(p, y) { fum <- grepl("Fumble", p$play_type); t <- p$play_text[fum]
  a <- e$r13_parse_fumble_text(t, "r8"); b <- r15_parse_fumble_text(t, rep(y, length(t)), e)
  data.table(season = y, fumble_plays = sum(fum), r8_recovered = mean(!is.na(a$type)), r15_recovered = mean(!is.na(b$type)),
             rows_changed = sum(xor(is.na(a$type), is.na(b$type)) | (!is.na(a$type) & !is.na(b$type) & (a$type != b$type | a$gained != b$gained)))) }
res <- rbindlist(lapply(2013:2025, function(y) one(as.data.table(readRDS(file.path(raw6, sprintf("plays_%d.rds", y)))), y)))
live <- list.files("output/dev/round15/forward_dryrun/pbp/2026", "\\.rds$", full.names = TRUE)
if (length(live)) { p <- rbindlist(lapply(live, function(f) as.data.table(readRDS(f))), fill = TRUE); p <- unique(p, by = c("game_id", "play_id"))
  res <- rbind(res, one(p, 2026)[, season := 2026L]) }
v <- data.table(step = "P2", rule = "2025 recovery >= 0.90 and 0 changed rows 2013-2024",
                recovery_2025 = res[season == 2025, r15_recovered], changed_rows_2013_2024 = res[season <= 2024, sum(rows_changed)])
v[, pass := recovery_2025 >= 0.90 & changed_rows_2013_2024 == 0]
v[, parser_sha256 := digest::digest(file = "R/round15/prep/fumble_parser.R", algo = "sha256")]
fwrite(res, "docs/round15/prep/p2_fumble_recovery_by_season.csv"); fwrite(v, "docs/round15/prep/p2_verdict.csv"); print(res); print(v)
