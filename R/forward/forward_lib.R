# Forward-evidence archive: write-once pre-kickoff snapshots with a hash-chained manifest.
# Evidence collection only: nothing here trains, refits, promotes or deploys a model, and no market data is read.
# Procedure and rules: docs/forward/FORWARD_SNAPSHOTS.md.
suppressPackageStartupMessages({ library(data.table); library(digest); library(jsonlite) })

FWD <- list(version = "1.0.0", kickoff_margin_min = 15, max_unresolved = 3L, inc_available_hours = 24, r13_available_hours = 12,
            outcome_fields = c("actual_margin", "home_points", "away_points", "home_score", "away_score", "error", "abs_error"),
            market_pattern = "spread|odds|moneyline|market|provider|over_under|overunder|implied|closing|opening|sportsbook|vegas|consensus|(^|_)line($|_)",
            vendor_pattern = "(^|_)(ppa|epa|wpa|wp|elo)($|_)|win_prob")

fwd_assert <- function(ok, msg) if (!isTRUE(ok)) stop(msg, call. = FALSE)
`%||%` <- function(a, b) if (is.null(a)) b else a
fwd_stamp <- function(t = Sys.time()) format(t, "%Y%m%dT%H%M%SZ", tz = "UTC")
fwd_iso <- function(t = Sys.time()) format(t, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
fwd_sha256 <- function(path) digest::digest(file = path, algo = "sha256")
fwd_rel <- function(path, archive) sub(paste0("^", normalizePath(archive), "/"), "", normalizePath(path))

# ---- write-once files -----------------------------------------------------------------------------------------------
fwd_write_once <- function(x, path, writer = c("csv", "rds", "json")) {
  writer <- match.arg(writer)
  fwd_assert(!file.exists(path), paste("Write-once file exists; refusing to overwrite:", path))
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- tempfile(tmpdir = dirname(path), fileext = ".partial")
  switch(writer, csv = fwrite(as.data.table(x), tmp), rds = saveRDS(x, tmp),
         json = writeLines(toJSON(x, auto_unbox = TRUE, pretty = TRUE, digits = NA, null = "null"), tmp))
  fwd_assert(file.rename(tmp, path), paste("Atomic rename failed:", path))
  Sys.chmod(path, "0444")
  fwd_sha256(path)
}

# ---- hash-chained, append-only manifest -----------------------------------------------------------------------------
fwd_manifest_path <- function(archive) file.path(archive, "manifest.csv")
fwd_line_hash <- function(r) digest::digest(paste(r$seq, r$recorded_utc, r$kind, r$model, r$season, r$path, r$sha256, r$bytes, r$prev_line_sha256, sep = "|"),
                                            algo = "sha256", serialize = FALSE)
fwd_read_manifest <- function(archive) {
  f <- fwd_manifest_path(archive)
  if (!file.exists(f)) return(data.table(seq = integer(), recorded_utc = character(), kind = character(), model = character(), season = integer(),
                                         path = character(), sha256 = character(), bytes = numeric(), prev_line_sha256 = character(), line_sha256 = character()))
  fread(f, colClasses = list(character = c("recorded_utc", "kind", "model", "path", "sha256", "prev_line_sha256", "line_sha256")))
}
# Verifies the chain and that every listed file still exists with its recorded hash. Stops on any discrepancy.
fwd_verify_manifest <- function(archive) {
  m <- fwd_read_manifest(archive); if (!nrow(m)) return(invisible(m))
  prev <- "GENESIS"
  for (i in seq_len(nrow(m))) {
    r <- m[i]
    fwd_assert(r$seq == i && r$prev_line_sha256 == prev, paste("Manifest chain broken at line", i))
    fwd_assert(identical(fwd_line_hash(r), r$line_sha256), paste("Manifest line hash mismatch at line", i))
    f <- file.path(archive, r$path)
    fwd_assert(file.exists(f), paste("Archived file missing:", r$path))
    fwd_assert(identical(fwd_sha256(f), r$sha256), paste("Archived file changed since it was recorded:", r$path))
    prev <- r$line_sha256
  }
  invisible(m)
}
fwd_manifest_append <- function(archive, kind, model, season, path, sha256) {
  m <- fwd_verify_manifest(archive)
  r <- data.table(seq = nrow(m) + 1L, recorded_utc = fwd_iso(), kind = kind, model = model, season = as.integer(season),
                  path = fwd_rel(path, archive), sha256 = sha256, bytes = file.size(path),
                  prev_line_sha256 = if (nrow(m)) m$line_sha256[nrow(m)] else "GENESIS", line_sha256 = NA_character_)
  r$line_sha256 <- fwd_line_hash(r)
  fwrite(r, fwd_manifest_path(archive), append = file.exists(fwd_manifest_path(archive)))
  invisible(r)
}
fwd_archive_file <- function(archive, x, path, kind, model, season, writer) {
  h <- fwd_write_once(x, path, writer); fwd_manifest_append(archive, kind, model, season, path, h); h
}
fwd_log <- function(archive, run_utc, step, status, detail = "") {
  f <- file.path(archive, "run_log.csv"); dir.create(archive, recursive = TRUE, showWarnings = FALSE)
  fwrite(data.table(run_utc = run_utc, logged_utc = fwd_iso(), step = step, status = status, detail = substr(detail, 1, 2000)), f, append = file.exists(f))
}

# ---- guards ---------------------------------------------------------------------------------------------------------
fwd_guard_snapshot <- function(p, snapshot_time, allow = character()) {
  n <- setdiff(names(p), allow)
  bad_o <- intersect(n, FWD$outcome_fields); fwd_assert(!length(bad_o), paste("Outcome field in snapshot:", paste(bad_o, collapse = ", ")))
  bad_m <- n[grepl(FWD$market_pattern, n, ignore.case = TRUE)]; fwd_assert(!length(bad_m), paste("Market field in snapshot:", paste(bad_m, collapse = ", ")))
  bad_v <- n[grepl(FWD$vendor_pattern, n, ignore.case = TRUE)]; fwd_assert(!length(bad_v), paste("Vendor rating/EPA field in snapshot:", paste(bad_v, collapse = ", ")))
  k <- as.POSIXct(p$kickoff, tz = "UTC")
  fwd_assert(nrow(p) > 0 && all(k > snapshot_time + 60 * FWD$kickoff_margin_min), "Snapshot includes a game at or after kickoff (or within the safety margin)")
  fwd_assert(all(is.finite(p$pred_margin)) && !anyDuplicated(p$game_id), "Nonfinite or duplicate predictions")
  invisible(p)
}

# ---- schedule-level rules -------------------------------------------------------------------------------------------
# Games in the current weekly period that have not kicked off (FBS vs FBS), with a safety margin.
fwd_targets <- function(g, now, cut_at) {
  g <- as.data.table(g)
  g[home_fbs & away_fbs & period == cut_at & !final & kickoff > now + 60 * FWD$kickoff_margin_min]
}
# FBS-vs-FBS games whose result should be known at the cutoff under the incumbent's rule (kickoff + 24 h < cutoff) but is not final.
fwd_unresolved <- function(g, cut_at) {
  g <- as.data.table(g); g[home_fbs & away_fbs & kickoff + 3600 * FWD$inc_available_hours < cut_at & !final, .(game_id, kickoff, home_id, away_id)]
}

# ---- provenance ---------------------------------------------------------------------------------------------------------
fwd_provenance <- function(root) {
  commit <- tryCatch(system2("git", c("-C", shQuote(root), "rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE), error = function(e) NA_character_)
  dirty <- tryCatch(length(system2("git", c("-C", shQuote(root), "status", "--porcelain", "--untracked-files=no"), stdout = TRUE, stderr = FALSE)) > 0, error = function(e) NA)
  pk <- c("data.table", "dplyr", "Matrix", "cfbfastR", "digest")
  code <- c(list.files(file.path(root, "R/forward"), "\\.R$", full.names = TRUE, recursive = TRUE),
            list.files(file.path(root, "scripts/forward"), "\\.(R|sh)$", full.names = TRUE),
            file.path(root, c("R/model/cfb_power_ratings_vCurrent.R", "R/model/production_operations.R", "config/production.R",
                              "config/paths.R", "config/forward/round13_forward_weight.csv")))
  code_sha256 <- setNames(as.list(vapply(code, fwd_sha256, "")), sub(paste0("^", root, "/"), "", code))
  list(tool_version = FWD$version, git_commit = commit[1], git_dirty = dirty, code_sha256 = code_sha256, r_version = R.version.string,
       packages = as.list(setNames(vapply(pk, function(p) as.character(utils::packageVersion(p)), ""), pk)), host = Sys.info()[["nodename"]])
}
