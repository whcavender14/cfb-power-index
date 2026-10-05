# =============================================================================
# scripts/03_export_public_data.R — write the static-site JSON files.
#
# Reads output/state (production snapshots + simulations) and data/reference
# (team metadata) and writes public/data/{ratings,simulations}.json plus
# per-week archives, and the CFPi+ page datasets in public/data/v2
# (R/publish/export_site_data.R, docs/website/DATA_CONTRACT_V2.md).
# Set CFB_EXPORT_BETTING=true to also build betting.json (calls the CFBD API;
# needs CFBD_API_KEY for market lines).
# Schemas: docs/DATA_CONTRACT.md (v1) and docs/website/DATA_CONTRACT_V2.md.
# The website source is src/ (docs/website/ARCHITECTURE.md).
# =============================================================================
source("config/paths.R")
ensure_output_dirs()
source(PATHS$export_public, local = new.env(parent = globalenv()))
# Season player stats for "Statistical leaders" (one CFBD call; display only, never a model input).
if (!identical(Sys.getenv("CFB_PULL_PLAYERS"), "false")) source(PATHS$pull_players, local = new.env(parent = globalenv()))
# Player PPA and success rates for the /players/ leaderboards (two direct CFBD calls; display only).
if (!identical(Sys.getenv("CFB_PULL_PLAYERS"), "false")) tryCatch(source(file.path(PATHS$root, "R", "publish", "pull_player_ppa.R"), local = new.env(parent = globalenv())),
  error = function(e) warning("Player PPA: ", conditionMessage(e), "; leaderboards will omit PPA unless the kept pull lines up.", call. = FALSE))
# Depth charts (TWO·DEEP, with permission; display only). A failed pull keeps the last good file and only warns.
if (!identical(Sys.getenv("CFB_PULL_DEPTH"), "false")) tryCatch(source(PATHS$pull_depth, local = new.env(parent = globalenv())),
  error = function(e) warning("Depth charts: ", conditionMessage(e), "; continuing without a new pull.", call. = FALSE))
# CFPi+ page datasets (public/data/v2); reads the same outputs, never the model.
source(PATHS$export_site, local = new.env(parent = globalenv()))
# /players/ leaderboards (no CFBD calls). On failure the boards say they are unavailable rather than going stale.
tryCatch(source(file.path(PATHS$root, "scripts", "export_player_leaders.R"), local = new.env(parent = globalenv())), error = function(e) {
  warning("Player leaders: ", conditionMessage(e), call. = FALSE)
  e2 <- new.env(parent = globalenv()); sys.source(file.path(PATHS$root, "R", "publish", "player_leaders.R"), envir = e2)
  e2$write_empty_boards(file.path(PATHS$public_data, "v2", "players", "leaders"), jsonlite::fromJSON(file.path(PATHS$public_data, "v2", "index.json"))$meta,
                        "the leaderboard export failed this week", "CollegeFootballData")
})
# CFPi+ Player Ratings v1 beta (modelled, not official; display only): rated with evidence through last season, no
# CFBD calls in season. A failure keeps last week's files restamped by the profile-flag refresh below.
if (!identical(Sys.getenv("CFB_PLAYER_RATINGS"), "false")) tryCatch(source(file.path(PATHS$root, "scripts", "export_player_ratings.R"), local = new.env(parent = globalenv())),
  error = function(e) warning("Player ratings: ", conditionMessage(e), "; keeping the previous files.", call. = FALSE))
# Player profiles for the player modal, including every leaderboard player (about 4 CFBD calls; cached history in
# data/reference/player_cache, which the workflow commits). Also restores the depth-chart starters' ids and stat lines.
# A failure keeps last week's profiles and only warns (the validator still requires a profile for every leaderboard player).
if (!identical(Sys.getenv("CFB_PLAYER_PROFILES"), "false")) tryCatch(source(file.path(PATHS$root, "scripts", "export_player_profiles.R"), local = new.env(parent = globalenv())),
  error = function(e) warning("Player profiles: ", conditionMessage(e), "; keeping the previous files.", call. = FALSE))
# Ratings files say which players have a profile (and carry this export's stamp); refresh after the profiles.
if (dir.exists(file.path(PATHS$public_data, "v2", "players", "ratings"))) tryCatch({
  idx_meta <- jsonlite::fromJSON(file.path(PATHS$public_data, "v2", "index.json"), simplifyVector = FALSE)$meta
  for (f in c(file.path(PATHS$public_data, "v2", "players", "ratings", "top.json"), list.files(file.path(PATHS$public_data, "v2", "players", "ratings", "team"), full.names = TRUE))) {
    d <- jsonlite::fromJSON(f, simplifyVector = FALSE); d$meta <- idx_meta
    d$rows <- lapply(d$rows, function(r) { r[[11]] <- file.exists(file.path(PATHS$public_data, "v2", "player", paste0(r[[1]], ".json"))); r })
    jsonlite::write_json(d, f, auto_unbox = TRUE, na = "null", null = "null", digits = 6)
  }
}, error = function(e) warning("Player ratings flags: ", conditionMessage(e), call. = FALSE))
# Recruiting pages and the team-page Recruiting card (2 CFBD calls for the open class; finished classes cached).
# On failure the previous files are kept, restamped for this export.
if (!identical(Sys.getenv("CFB_RECRUITING"), "false")) tryCatch(source(file.path(PATHS$root, "scripts", "export_recruiting.R"), local = new.env(parent = globalenv())), error = function(e) {
  warning("Recruiting: ", conditionMessage(e), "; keeping the previous files.", call. = FALSE)
  e2 <- new.env(parent = globalenv()); sys.source(file.path(PATHS$root, "R", "publish", "recruiting.R"), envir = e2)
  e2$restamp_recruiting(file.path(PATHS$public_data, "v2", "recruiting"), jsonlite::fromJSON(file.path(PATHS$public_data, "v2", "index.json"), simplifyVector = FALSE)$meta)
})
if (identical(Sys.getenv("CFB_EXPORT_BETTING"), "true")) {
  source(PATHS$export_betting, local = new.env(parent = globalenv()))
}
