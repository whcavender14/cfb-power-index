# Forward-evidence archive tests (no API calls). Run from the repo root: Rscript tests/forward/test_forward.R
source("config/paths.R"); source("config/production.R")
suppressPackageStartupMessages({ source(PATHS$model_ops); source("R/forward/forward_lib.R"); source("R/forward/forward_models.R") })
n <- 0L; check <- function(ok, what) { if (!isTRUE(ok)) stop("FAIL: ", what, call. = FALSE); n <<- n + 1L; cat("ok -", what, "\n") }
errs <- function(expr) inherits(tryCatch({ force(expr); NULL }, error = function(e) e), "error")
ar <- file.path(tempdir(), paste0("fwdtest_", fwd_stamp())); dir.create(ar)

# write-once, read-only, atomic
f <- file.path(ar, "a", "x.csv"); h <- fwd_archive_file(ar, data.table(a = 1:3), f, "test", "m", 2026, "csv")
check(file.exists(f) && identical(h, fwd_sha256(f)), "file written and hashed")
check(bitwAnd(as.integer(file.info(f)$mode), strtoi("222", 8L)) == 0, "archived file is read-only")
check(errs(fwd_write_once(data.table(a = 9), f, "csv")), "second write to the same path is refused")
check(!length(list.files(dirname(f), pattern = "partial$")), "no partial temp file left behind")

# hash chain
fwd_archive_file(ar, list(k = "v"), file.path(ar, "a", "y.json"), "meta", "m", 2026, "json")
check(nrow(fwd_verify_manifest(ar)) == 2, "manifest chain verifies")
m <- fread(fwd_manifest_path(ar)); m$sha256[1] <- paste0(substr(m$sha256[1], 1, 63), "0"); mf <- file.path(ar, "manifest_tampered")
dir.create(mf); file.copy(file.path(ar, "a"), mf, recursive = TRUE); fwrite(m, fwd_manifest_path(mf))
check(errs(fwd_verify_manifest(mf)), "edited manifest line is detected")
ar2 <- file.path(tempdir(), paste0("fwdtest2_", fwd_stamp())); dir.create(ar2)
g2 <- file.path(ar2, "z.csv"); fwd_archive_file(ar2, data.table(a = 1), g2, "test", "m", 2026, "csv"); Sys.chmod(g2, "0644"); write("tamper", g2, append = TRUE)
check(errs(fwd_verify_manifest(ar2)), "modified archived file is detected")
unlink(g2); check(errs(fwd_verify_manifest(ar2)), "deleted archived file is detected")

# snapshot guards
now <- as.POSIXct("2026-10-01 12:00:00", tz = "UTC")
p <- data.table(game_id = c("1", "2"), kickoff = now + c(3, 5) * 3600, pred_margin = c(3.5, -1))
check(!errs(fwd_guard_snapshot(p, now)), "clean snapshot passes")
check(errs(fwd_guard_snapshot(cbind(p, actual_margin = 1), now)), "outcome column rejected")
check(errs(fwd_guard_snapshot(cbind(p, home_spread = 1), now)), "market column rejected")
check(errs(fwd_guard_snapshot(cbind(p, home_pregame_elo = 1), now)), "vendor Elo column rejected")
check(errs(fwd_guard_snapshot(cbind(p, ppa = 1), now)), "vendor EPA column rejected")
check(errs(fwd_guard_snapshot(copy(p)[1, kickoff := now - 60], now)), "game already kicked off rejected")
check(errs(fwd_guard_snapshot(copy(p)[1, kickoff := now + 5 * 60], now)), "game inside the 15-minute margin rejected")
check(errs(fwd_guard_snapshot(rbind(p, p[1]), now)), "duplicate game rejected")

# target selection and readiness
cut <- period_start(now)
g <- data.table(game_id = as.character(1:6), home_fbs = c(TRUE, TRUE, TRUE, TRUE, FALSE, TRUE), away_fbs = TRUE,
                kickoff = c(now + 3600, now - 3600, now + 8 * 86400, now + 2 * 3600, now + 3600, cut - 3 * 86400),
                final = c(FALSE, FALSE, FALSE, TRUE, FALSE, FALSE), home_id = 1:6, away_id = 11:16)
g[, period := period_start(kickoff)]
check(identical(fwd_targets(g, now, cut)$game_id, "1"), "targets: current period, not started, not final, FBS vs FBS only")
check(nrow(fwd_unresolved(g, cut)) == 1, "an unresolved pre-cutoff game is detected")

# play-by-play pull selection and the late_pull flag (Round 13 forward rule)
pl <- data.table(season_type = "regular", week = c(4L, 4L, 5L), file = c("a", "b", "c"),
                 pulled_at = c(cut - 3600, cut + 3600, cut + 7200))
s <- fwd_select_pulls(pl, cut)
check(s[week == 4, file] == "a" && !s[week == 4, late_pull], "the latest pre-cutoff pull is used when one exists")
check(s[week == 5, late_pull], "a week pulled only after the cutoff is flagged late_pull")

# frozen Round 13 inputs, and market isolation of forward/model code
check(identical(fwd_git_blob(R13_VENDOR), R13_VENDOR_BLOB), "vendored Round 13 code is the frozen tag's blob")
check(identical(fwd_sha256(R13_WEIGHT), R13_WEIGHT_SHA256), "Round 13 forward weight matches its freeze manifest")
src <- unlist(lapply(c(list.files("R/forward", "\\.R$", full.names = TRUE, recursive = TRUE), list.files("scripts/forward", "\\.R$", full.names = TRUE)), readLines))
check(!any(grepl("market_lines|betting_lines|/lines|market_raw|PATHS\\$market", src)), "forward code never reads market data")
check(!file.exists(R15_FREEZE) && errs(fwd_model_round15()), "Round 15 plugin refuses to run before a freeze exists")
cat(sprintf("\n%d checks passed\n", n))
