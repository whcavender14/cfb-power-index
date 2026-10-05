# Redshirt tag (display only; docs/website/PLAYER_DATA.md). CFBD's roster has a class year 1-4 and no redshirt flag. On
# the 2026 rosters that field behaves like eligibility years used (a redshirt year does not count): of the 2025 high-school
# class, 1,288 are listed as year 1 (redshirted in 2025) and 1,669 as year 2. So a player is tagged RS when the seasons
# since his recruiting class exceed his class year minus one: season - class > year - 1. Only for players with a
# high-school recruiting record (the class is needed) and a class year of 1-4; everyone else gets no tag.
recruit_class_lookup <- function(season, first = 2016L) {
  x <- lapply(first:season, function(y) { f <- file.path(PATHS$reference, "player_cache", sprintf("recruits_%d.rds", y))
    if (!file.exists(f)) return(NULL); d <- as.data.frame(readRDS(f)); data.frame(athlete_id = as.character(d$athlete_id), cls = as.integer(d$year), stringsAsFactors = FALSE) })
  x <- do.call(rbind, x); x <- x[!is.na(x$athlete_id) & nzchar(x$athlete_id), , drop = FALSE]
  x <- x[order(-x$cls), , drop = FALSE]; x[!duplicated(x$athlete_id), , drop = FALSE]
}
# class: roster class year (1-4 or NA); id: athlete ids; lookup: recruit_class_lookup(); season: roster season.
rs_flag <- function(id, class, lookup, season) {
  cls <- lookup$cls[match(as.character(id), lookup$athlete_id)]
  !is.na(cls) & !is.na(class) & class >= 1L & class <= 4L & cls <= season & (season - cls) > (class - 1L)
}
