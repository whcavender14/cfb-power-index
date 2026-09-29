# =============================================================================
# R/publish/game_advanced.R — per-game advanced team stats for the finished-game recap (game_adv/<game_id>.json).
#
# Display only: nothing here feeds the ratings or the simulation. Source: the same CFBD play-by-play as
# team_efficiency.R (`ppa` = expected points added), same eligible plays and success definition. RAW, per game, one row per
# offense; the page derives "allowed" figures from the opponent's offense.
#   eligible play: rush or pass (sacks and interceptions count as passes), down 1-4, distance > 0, finite ppa;
#                  kneels, spikes, penalties and no-plays excluded
#   success:       gain >= 50% of distance on 1st down, 70% on 2nd, 100% on 3rd/4th
#   standard down: everything that is not a passing down (1st down; 2nd with fewer than 8 to go; 3rd/4th with fewer than 5)
#   passing down:  2nd with 8+ to go; 3rd/4th with 5+ to go
#   explosive:     rush of 10+ yards, pass of 15+ yards
#   red zone:      offense inside the opponent's 20
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
source_dir <- if (exists("PATHS")) file.path(PATHS$root, "R", "publish") else "R/publish"
if (!exists("EFF_RUSH")) source(file.path(source_dir, "team_efficiency.R"), local = TRUE)

# plays: CFBD plays; games: data.frame(game_id, home_id, away_id, home_team, away_team).
# Returns a named list (by game_id) of per-team offense lines.
game_advanced <- function(plays, games) {
  g <- as.data.table(games)[, .(game_id = as.character(game_id), home_id = as.character(home_id), away_id = as.character(away_id), home_team, away_team)]
  p <- as.data.table(plays)[as.character(game_id) %in% g$game_id & play_type %in% c(EFF_RUSH, EFF_PASS)]
  p <- p[down %in% 1:4 & is.finite(distance) & distance > 0 & is.finite(ppa) & is.finite(yards_gained) &
         !grepl("kneel|spike|no.play|penalty", play_text, ignore.case = TRUE)]
  p <- unique(p, by = c("game_id", "play_id"))
  p[, game_id := as.character(game_id)]
  p[, `:=`(rush = play_type %in% EFF_RUSH,
           success = yards_gained >= distance * c(.5, .7, 1, 1)[down],
           passing_down = (down == 2L & distance >= 8) | (down >= 3L & distance >= 5))]
  p[, `:=`(explosive = yards_gained >= ifelse(rush, 10, 15), redzone = yards_to_goal <= 20)]
  r <- function(v, d = 4) if (is.finite(v)) round(v, d) else NULL
  m <- function(v) if (length(v)) mean(v) else NaN
  line <- function(x) list(
    plays = nrow(x), rush_plays = sum(x$rush), pass_plays = sum(!x$rush),
    epa_play = r(m(x$ppa)), total_epa = r(sum(x$ppa), 2),
    rush_epa = r(m(x$ppa[x$rush])), pass_epa = r(m(x$ppa[!x$rush])),
    early_epa = r(m(x$ppa[x$down <= 2])), redzone_epa = r(m(x$ppa[x$redzone])), redzone_plays = sum(x$redzone),
    sr = r(m(x$success)), sr_standard = r(m(x$success[!x$passing_down])), sr_passing = r(m(x$success[x$passing_down])),
    sr_rush = r(m(x$success[x$rush])), sr_pass = r(m(x$success[!x$rush])),
    standard_plays = sum(!x$passing_down), passing_down_plays = sum(x$passing_down),
    explosive_rate = r(m(x$explosive)), third_conv = r(m((x$yards_gained >= x$distance)[x$down == 3L])), third_plays = sum(x$down == 3L))
  out <- list()
  for (i in seq_len(nrow(g))) {
    x <- p[game_id == g$game_id[i]]
    if (!nrow(x)) next
    ha <- x[offense == g$home_team[i]]; aw <- x[offense == g$away_team[i]]
    if (!nrow(ha) || !nrow(aw)) next
    out[[g$game_id[i]]] <- list(game_id = g$game_id[i], source = "CollegeFootballData play-by-play (ppa = expected points added)",
                                teams = setNames(list(line(aw), line(ha)), c(g$away_id[i], g$home_id[i])))
  }
  out
}

write_game_advanced <- function(docs, dir, meta_block = NULL) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  old <- list.files(dir, pattern = "\\.json$", full.names = TRUE); unlink(old)
  for (id in names(docs)) write_json(c(list(meta = meta_block), docs[[id]]), file.path(dir, paste0(id, ".json")), auto_unbox = TRUE, na = "null", null = "null", digits = 6)
  length(docs)
}
