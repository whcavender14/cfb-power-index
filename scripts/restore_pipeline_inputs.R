# Restore portable sources to the paths expected by the supplied R model.
paths <- list.files("pipeline_inputs", recursive=TRUE, full.names=FALSE)
for (p in paths[!grepl("^weekly_seed/", paths)]) {
  dir.create(dirname(p), recursive=TRUE, showWarnings=FALSE)
  file.copy(file.path("pipeline_inputs", p), p, overwrite=TRUE)
}
data_dir <- Sys.getenv("CFB_DATA_DIR", "cfb_data")
dir.create(data_dir, recursive=TRUE, showWarnings=FALSE)
for (p in list.files("pipeline_inputs/weekly_seed", full.names=TRUE)) {
  dest <- file.path(data_dir, basename(p))
  if (!file.exists(dest)) file.copy(p, dest)
}
