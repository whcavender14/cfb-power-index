# EVALUATION-ONLY market module. Nothing under R/model/ or any rating/candidate code may source this file or read its
# outputs (enforced by the Round 15 leakage test). Scores returned by CFBD /lines are dropped on read.
#
# Per game, from CFBD /lines book quotes (home perspective, negative = home favoured):
#   a quote is valid if the provider is named, `spread` is finite, and the sign implied by `formattedSpread`
#   ("<Team> <points>") matches `spread` for the named home/away team (Round 13's check); "consensus" rows are excluded.
#   open_home_spread  = median of `spreadOpen` over valid books with a finite opener
#   close_home_spread = median of `spread` over valid books
suppressPackageStartupMessages(library(data.table))

r15_line_quotes <- function(raw) {
  g <- as.data.table(raw)
  g[, c("homeScore", "awayScore") := NULL]
  q <- rbindlist(lapply(seq_len(nrow(g)), function(i) { l <- g$lines[[i]]
    if (!NROW(l)) return(NULL)
    l <- as.data.table(l)
    for (v in c("spread", "spreadOpen", "formattedSpread", "provider")) if (!v %in% names(l)) l[, (v) := NA]
    l[, .(game_id = as.character(g$id[i]), season = g$season[i], season_type = g$seasonType[i], week = g$week[i],
          home_team = g$homeTeam[i], away_team = g$awayTeam[i], home_id = g$homeTeamId[i], away_id = g$awayTeamId[i],
          home_class = g$homeClassification[i], away_class = g$awayClassification[i],
          provider = tolower(trimws(provider)), close_q = suppressWarnings(as.numeric(spread)),
          open_q = suppressWarnings(as.numeric(spreadOpen)), formatted = formattedSpread)] }), fill = TRUE)
  lab <- !is.na(q$formatted) & grepl(" [+-]?[0-9]+(\\.[0-9]+)?$", q$formatted)
  team <- sub(" [+-]?[0-9]+(\\.[0-9]+)?$", "", q$formatted)
  pts <- suppressWarnings(as.numeric(sub("^.* ([+-]?[0-9]+(\\.[0-9]+)?)$", "\\1", q$formatted)))
  signed <- rep(NA_real_, nrow(q))
  signed[lab & team == q$home_team] <- pts[lab & team == q$home_team]
  signed[lab & team == q$away_team] <- -pts[lab & team == q$away_team]
  pk <- !lab & is.finite(q$close_q) & q$close_q == 0 & (is.na(q$formatted) | tolower(q$formatted) %in% c("pk", "pick", "pick'em"))
  signed[pk] <- 0
  q[, valid := !is.na(provider) & nzchar(provider) & provider != "consensus" & is.finite(close_q) & is.finite(signed) & abs(signed - close_q) < 1e-8]
  q[, conflict := uniqueN(close_q) > 1, by = .(game_id, provider)]
  q[]
}

r15_game_lines <- function(q) {
  v <- q[valid & !conflict][!duplicated(q[valid & !conflict, .(game_id, provider)])]
  v[, .(season = season[1], season_type = season_type[1], home_id = home_id[1], away_id = away_id[1],
        open_home_spread = if (any(is.finite(open_q))) median(open_q[is.finite(open_q)]) else NA_real_,
        close_home_spread = median(close_q), open_books = sum(is.finite(open_q)), close_books = .N,
        providers = paste(sort(provider), collapse = ";")), by = game_id]
}
