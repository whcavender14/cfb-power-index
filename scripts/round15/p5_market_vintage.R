# Round 15 P5: record the fixed market-line vintage (evaluation-only data) with SHA-256 hashes. No market value is analysed.
suppressPackageStartupMessages(library(data.table))
f <- "output/dev/round15/market_lines_2017_2025.csv"; raws <- list.files("output/dev/round15/market_raw", "^lines_.*[.]rds$", full.names = TRUE)
man <- data.table(file = c(f, raws), sha256 = vapply(c(f, raws), function(p) digest::digest(file = p, algo = "sha256"), ""), bytes = file.size(c(f, raws)))
fwrite(man, "docs/round15/prep/p5_market_vintage_manifest.csv")
v <- data.table(step = "P5", rule = "market lines fixed at the 2026-09-25 pull; evaluation-only; recorded with hashes", vintage_utc = "2026-09-25T00:03Z",
  game_lines_rows = nrow(fread(f)), raw_files = length(raws), game_lines_sha256 = man$sha256[1], status = "RECORDED (no pass/fail rule)")
fwrite(v, "docs/round15/prep/p5_verdict.csv"); print(v)
