# Adapted from the old folder: only the source() path changed. Run from the project root.
source("config/paths.R")
source(PATHS$betting_funs)
# Fixtures exercise transformations only; none are exported to public/data.
g <- data.frame(game_id=1:5,week=c(1,2,2,3,2),season_type="regular",
  start_date=c("2026-09-10T20:00:00Z","2026-09-12T20:00:00Z","2026-09-12T21:00:00Z","2026-09-19T20:00:00Z",NA),
  home_id=1:5,away_id=6:10,home_team="Home",away_team="Away",neutral_site=FALSE,completed=c(TRUE,FALSE,TRUE,FALSE,FALSE))
selected <- upcoming_games(g,betting_utc("2026-09-11T00:00:00Z"))
stopifnot(identical(selected$game_id,c(2L,5L)))
stopifnot(nrow(upcoming_games(g,betting_utc("2026-10-01T00:00:00Z")))==0L)
lines <- data.frame(game_id=2L,home_team="Home",away_team="Away",provider="DraftKings",spread=3,formatted_spread="Away -3")
stopifnot(select_market(lines,g[2,])$spread==3)
lines$spread <- -7; lines$formatted_spread <- "Home -7"
stopifnot(select_market(lines,g[2,])$spread== -7)
lines$provider <- NA
stopifnot(is.na(select_market(lines,g[2,])$spread))
stopifnot(is.na(select_market(data.frame(game_id=2,spread=0,formatted_spread="home 0"),g[2,])$spread))
lines$provider <- "DraftKings";lines$formatted_spread <- "Unrelated Team -7"
stopifnot(is.na(select_market(lines,g[2,])$spread))
lines$formatted_spread <- "Home -9"
stopifnot(is.na(select_market(lines,g[2,])$spread))
lines$spread <- 0;lines$formatted_spread <- "PK"
stopifnot(select_market(lines,g[2,])$spread==0)
other <- lines;other$provider <- "Bovada";other$spread <- -1;other$formatted_spread <- "Home -1"
stopifnot(select_market(rbind(other,lines),g[2,])$provider=="DraftKings")
cat("PASS: upcoming-week selection, completed games, unknown times, market signs, provider priority, and fake-zero rejection.\n")
