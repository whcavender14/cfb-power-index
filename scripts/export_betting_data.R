suppressPackageStartupMessages(library(jsonlite))
source("scripts/betting_functions.R")
season <- as.integer(Sys.getenv("CFB_SEASON","2026"))
data_dir <- Sys.getenv("CFB_DATA_DIR","cfb_data")
out_dir <- Sys.getenv("CFB_PUBLIC_DIR","public/data")
now <- Sys.time()
stamp <- function(x) if (is.null(x) || !length(x) || is.na(x[1])) NA_character_ else
  format(x[1],"%Y-%m-%dT%H:%M:%SZ",tz="UTC")
optional <- function(p) if (file.exists(p)) readRDS(p) else NULL
snapshot <- optional(file.path(data_dir,sprintf("production_ratings_%d_latest.rds",season)))
hfa <- if (!is.null(snapshot$hfa)) snapshot$hfa else NA_real_
stopifnot(length(hfa)==1L, is.na(hfa) || is.finite(hfa))
schedule_path <- file.path(data_dir,sprintf("betting_schedule_%d.rds",season))
g <- optional(schedule_path)
schedule_status <- "cached"
if (identical(Sys.getenv("CFB_REFRESH_SCHEDULE"),"true")) {
  fresh <- tryCatch(suppressMessages(cfbfastR::cfbd_game_info(year=season,season_type="both")),error=function(e) NULL)
  if (!is.null(fresh) && nrow(fresh) && all(c("game_id","home_id","away_id") %in% names(fresh))) {
    g <- fresh
    dir.create(data_dir,recursive=TRUE,showWarnings=FALSE)
    saveRDS(g,schedule_path)
    schedule_status <- "refreshed"
  } else schedule_status <- "refresh unavailable; using supplied schedule"
}
if (is.null(g)) g <- optional(sprintf("pipeline_inputs/cfb_data_v3/raw_schedule_%d.rds",season))
schedule_updated <- if (!is.null(g)) stamp(attr(g,"cfbfastR_timestamp")) else NA_character_
games <- upcoming_games(if (!is.null(g)) as.data.frame(g) else NULL,now)
week <- if (!is.null(games) && nrow(games)) as.integer(games$week[1]) else NA_integer_
season_type <- if (!is.null(games) && nrow(games)) games$season_type[1] else NA_character_
lines <- NULL; fetched <- NA_character_
market_status <- "Data unavailable: no current market response."
if (!is.na(week) && nzchar(Sys.getenv("CFBD_API_KEY"))) {
  lines <- tryCatch(suppressMessages(cfbfastR::cfbd_betting_lines(year=season,week=week,season_type=season_type)),error=function(e) NULL)
  if (!is.null(lines) && nrow(lines)) { fetched <- stamp(Sys.time()); market_status <- "Latest available sportsbook lines retrieved from CollegeFootballData." }
} else if (!nzchar(Sys.getenv("CFBD_API_KEY"))) market_status <- "Data unavailable: the market feed is not configured."
rows <- lapply(seq_len(if (is.null(games)) 0L else nrow(games)),function(i) {
  game <- games[i,,drop=FALSE]
  quote <- select_market(lines,game)
  tbd <- "start_time_tbd" %in% names(game) && isTRUE(game$start_time_tbd)
  list(game_id=as.character(game$game_id),week=as.integer(game$week),season_type=game$season_type,
       kickoff=stamp(betting_utc(game$start_date)),time_tbd=tbd,
       away_team_id=as.character(game$away_id),away_team=game$away_team,
       home_team_id=as.character(game$home_id),home_team=game$home_team,
       neutral_site=if (is.na(game$neutral_site)) NA else as.logical(game$neutral_site),
       market_spread=quote$spread,market_provider=quote$provider,
       market_retrieved_at=if (is.finite(quote$spread)) fetched else NA_character_,
       market_updated_at=NA_character_)
})
doc <- list(schema_version=1L,season=season,week=week,season_type=season_type,
            updated_at=stamp(Sys.time()),ratings_updated_at=stamp(snapshot$updated_at),
            hfa=hfa, hfa_source="Production model hfa attribute",
            schedule_updated_at=schedule_updated,schedule_status=schedule_status,
            schedule_source="CollegeFootballData schedule",market_source="CollegeFootballData via cfbfastR::cfbd_betting_lines",
            market_retrieved_at=fetched,market_status=market_status,
            provider_policy="DraftKings, ESPN Bet, Bovada, Caesars, consensus, then provider name; one quoted line per game",
            games=rows)
dir.create(out_dir,recursive=TRUE,showWarnings=FALSE)
write_json(doc,file.path(out_dir,"betting.json"),auto_unbox=TRUE,na="null",null="null",pretty=TRUE,digits=8)
if (!is.na(week)) {
  archive <- file.path(out_dir,season,sprintf("week-%02d",week))
  dir.create(archive,recursive=TRUE,showWarnings=FALSE)
  file.copy(file.path(out_dir,"betting.json"),file.path(archive,"betting.json"),overwrite=TRUE)
}
cat(sprintf("Betting: %d scheduled games, %d real market quotes.\n",length(rows),sum(vapply(rows,function(r) is.finite(r$market_spread),logical(1)))))
