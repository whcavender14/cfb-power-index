# =============================================================================
# scripts/build_legacy_manifest.R — regenerate docs/legacy_file_manifest.md
# from config/legacy_paths.R (the single source of truth). Run after editing
# the registry:  Rscript scripts/build_legacy_manifest.R
# =============================================================================
source("config/paths.R")
source("config/legacy_paths.R")
x <- legacy_registry()
x$status <- ifelse(grepl("^git:", x$absolute_path), "git object",
                   ifelse(file.exists(x$absolute_path), "present", "**MISSING**"))
esc <- function(s) gsub("\\|", "\\\\|", s)
out <- c(
  "# Legacy file manifest",
  "",
  sprintf("_Generated %s by `scripts/build_legacy_manifest.R` from `config/legacy_paths.R`. Edit the registry, not this file._",
          format(Sys.Date())),
  "",
  "Everything below was **intentionally not copied** into this folder. Nothing was deleted: the old folders are",
  "read-only archives. In code, never hard-code these paths; use `legacy_path(\"<key>\")` from `config/legacy_paths.R`.",
  "",
  "| Root | Location |",
  "|---|---|",
  sprintf("| `old` | `%s` (original working folder; git repo) |", LEGACY_ROOTS[["old"]]),
  sprintf("| `backup` | `%s` (2026-09-22 copy; the **only** place the archived round `code/` and `docs/` folders survive) |", LEGACY_ROOTS[["backup"]]),
  "| `external` | absolute path given in the table |",
  "",
  "**Important:** in the old folder, `archive/<round>/code/` and `archive/<round>/docs/` are missing and 77 documentation symlinks",
  "under `archive/*/results/artifacts/*.md` are broken. The copies in the Backup folder are intact.",
  "Also, `outputs/round6` in the old folder is a broken symlink; the real files are in `CFB-Modeling-round6/outputs/round6`.",
  "")
for (g in unique(x$group)) {
  y <- x[x$group == g, ]
  out <- c(out, paste("##", g), "",
           "| Key | Root | Path | Contains | Why excluded | When a future model might need it | Status |",
           "|---|---|---|---|---|---|---|",
           sprintf("| `%s` | %s | `%s` | %s | %s | %s | %s |", y$key, y$root, esc(y$path), esc(y$contains),
                   esc(y$excluded_because), esc(y$needed_when), y$status), "")
}
writeLines(out, file.path(PATHS$root, "docs", "legacy_file_manifest.md"))
cat("Wrote docs/legacy_file_manifest.md with", nrow(x), "entries;", sum(x$status == "**MISSING**"), "missing.\n")
