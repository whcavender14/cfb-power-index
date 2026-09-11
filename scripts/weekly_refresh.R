season <- as.integer(Sys.getenv("CFB_SEASON", "2026"))
stopifnot(!is.na(season), season >= 2000L)
CFB_DATA_DIR <- Sys.getenv("CFB_DATA_DIR", "cfb_data")
# A failed ratings refresh fails the job; old data is never stamped as fresh.
Sys.setenv(CFB_CREATE_GRAPHIC="false")
result <- system2(file.path(R.home("bin"), "Rscript"), "run_2026_rankings.R")
if (result != 0L) stop("Production rankings refresh failed.")

# Simulation failures do not prevent publishing real ratings. They produce an
# explicit unavailable state, even when an older simulation is cached.
status <- tryCatch({
  if (season != 2026L) stop("The supplied simulation assumptions support 2026 only.")
  source("cfb_simulation.R", local=new.env(parent=globalenv()))
  list(status="available", attempted_at=Sys.time())
}, error=function(e) {
  message("Simulation unavailable: ", conditionMessage(e))
  list(status="unavailable", attempted_at=Sys.time())
})
saveRDS(status, file.path(CFB_DATA_DIR, sprintf("simulation_status_%d.rds", season)))
source("scripts/export_public_data.R")
source("scripts/export_betting_data.R")
