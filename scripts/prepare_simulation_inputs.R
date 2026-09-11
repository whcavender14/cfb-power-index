# Copy exactly the frozen model's source dependencies into a portable CI bundle.
# Run locally when intentionally provisioning/changing the production freeze.
f <- readRDS("outputs/round4/design_frozen.rds")
stopifnot(all(unname(tools::md5sum(f$source_manifest$path)) == f$source_manifest$md5))
paths <- unique(c("outputs/round4/design_frozen.rds", "outputs/round4/features.rds", f$source_manifest$path))
stopifnot(all(file.exists(paths)), !any(grepl("^/|(^|/)\\.\\.(/|$)", paths)))
for (p in paths) {
  dest <- file.path("pipeline_inputs", p)
  dir.create(dirname(dest), recursive=TRUE, showWarnings=FALSE)
  file.copy(p, dest, overwrite=TRUE)
}
cat(sprintf("Prepared %d frozen model inputs (%.2f MB).\n", length(paths), sum(file.info(paths)$size)/1e6))
seed <- c("cfb_data/history_ratings_2023_2025.rds", "cfb_data/lambda_2026.rds")
dir.create("pipeline_inputs/weekly_seed", recursive=TRUE, showWarnings=FALSE)
for (p in seed[file.exists(seed)]) file.copy(p, file.path("pipeline_inputs/weekly_seed", basename(p)), overwrite=TRUE)
