# Pure schedule/odds transformations, shared by exporter and tests.
betting_utc <- function(x) as.POSIXct(sub("Z$", "", x), format="%Y-%m-%dT%H:%M:%OS", tz="UTC")
upcoming_games <- function(g, now=Sys.time()) {
  if (is.null(g) || !nrow(g)) return(g)
  stopifnot(all(c("game_id","week","season_type","start_date","home_id","away_id",
                 "home_team","away_team","neutral_site","completed") %in% names(g)), !anyDuplicated(g$game_id))
  kickoff <- betting_utc(g$start_date)
  tbd <- if ("start_time_tbd" %in% names(g)) g$start_time_tbd %in% TRUE else rep(FALSE,nrow(g))
  future <- !g$completed %in% TRUE & !is.na(kickoff) &
    (kickoff > now | (tbd & as.Date(kickoff,tz="UTC") >= as.Date(now,tz="UTC")))
  next_rows <- which(future)
  if (!length(next_rows)) return(g[FALSE,,drop=FALSE])
  first <- next_rows[which.min(kickoff[next_rows])]
  # Keep unknown kickoff times in the selected provider week as unavailable.
  g[(future | (!g$completed %in% TRUE & is.na(kickoff))) &
      g$week == g$week[first] & g$season_type == g$season_type[first],,drop=FALSE]
}
select_market <- function(lines, game) {
  missing <- list(spread=NA_real_, provider=NA_character_)
  required <- c("game_id","home_team","away_team","provider","spread","formatted_spread")
  if (is.null(lines) || !all(required %in% names(lines))) return(missing)
  # cfbfastR has a synthetic "home 0" fallback. Require real provider and
  # matching game/team identity so that fallback can never become a market line.
  x <- lines[!is.na(lines$game_id) & as.character(lines$game_id)==as.character(game$game_id) &
    !is.na(lines$provider) & nzchar(lines$provider) &
    !is.na(lines$home_team) & lines$home_team==game$home_team &
    !is.na(lines$away_team) & lines$away_team==game$away_team,,drop=FALSE]
  if (!nrow(x)) return(missing)
  priority <- match(x$provider,c("DraftKings","ESPN Bet","Bovada","Caesars","consensus"))
  priority[is.na(priority)] <- 99L
  x <- x[order(priority,x$provider),,drop=FALSE]
  for (i in seq_len(nrow(x))) {
    raw <- suppressWarnings(as.numeric(x$spread[i]))
    if (!is.finite(raw)) next
    label <- x$formatted_spread[i]
    home_line <- NA_real_
    if (!is.na(label) && grepl(" [+-]?[0-9]+(\\.[0-9]+)?$",label)) {
      team <- sub(" [+-]?[0-9]+(\\.[0-9]+)?$","",label)
      points <- as.numeric(sub("^.* ([+-]?[0-9]+(\\.[0-9]+)?)$","\\1",label))
      if (identical(team,game$home_team)) home_line <- points
      if (identical(team,game$away_team)) home_line <- -points
      if (is.finite(home_line) && abs(abs(raw)-abs(home_line)) > 1e-8) home_line <- NA_real_
    } else if (raw == 0 && (is.na(label) || tolower(label) %in% c("pick'em","pick","pk"))) {
      home_line <- 0
    }
    if (is.finite(home_line)) return(list(spread=home_line,provider=x$provider[i]))
  }
  missing
}
