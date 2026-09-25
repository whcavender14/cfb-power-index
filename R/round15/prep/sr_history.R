# Round 15: end-of-season opponent-adjusted success rate per season (the `last_sr` prior input, predeclaration §4.1).
# Frozen Round 13 instrument (vendored byte-for-byte), with the P2 fumble parser (identical to Round 8 for seasons <= 2024).
# [Amendment 01 A3] For season 2020 only, the three Round 13 "2020 excluded" guards are neutralized by occurrence-asserted
# source patches; every other rule is unchanged, and only 2020-season data enter the 2020 calculation.
suppressPackageStartupMessages(library(data.table))
R15_R13_VENDOR <- "R/forward/vendor/round13_sr_stack.R"

r15_patch <- function(f, pattern, replacement, env) {
  src <- paste(deparse(f, width.cutoff = 500L), collapse = "\n")
  hits <- gregexpr(pattern, src, fixed = TRUE)[[1]]
  if (length(hits) != 1L || hits[1] < 0) stop("A3 patch: expected exactly one occurrence of: ", pattern, call. = FALSE)
  g <- eval(parse(text = sub(pattern, replacement, src, fixed = TRUE)), envir = env); environment(g) <- env; g
}
r15_r13_env <- function(allow_2020 = FALSE) {
  e <- new.env(); sys.source(R15_R13_VENDOR, envir = e)
  if (allow_2020) {
    e$r13_schedule <- r15_patch(e$r13_schedule, 'r13_assert(!any(g$season == 2020), "2020 is excluded throughout")', 'invisible(NULL)', e)
    e$r13_eligible <- r15_patch(e$r13_eligible, 'drop(x$season == 2020, "excluded_2020")', 'invisible(NULL)', e)
    e$r13_effects <- r15_patch(e$r13_effects, ' && all(a$season != 2020)', '', e)
  }
  e
}
r15_recover_fumbles <- function(raw, e) {
  raw <- copy(raw); fum <- grepl("Fumble", raw$play_type)
  parsed <- r15_parse_fumble_text(raw$play_text, raw$season, e); rec <- fum & !is.na(parsed$type)
  raw[, `:=`(fumble_turnover = fum & grepl("Interception|Fumble Recovery \\(Opponent\\)|Fumble Return", play_type), fumble_total = fum, fumble_recovered = rec)]
  raw[rec, `:=`(play_type = parsed$type[rec], yards_gained = parsed$gained[rec])]
  raw[]
}
# One season: raw plays (Round 13 loader format) + raw schedule -> game x offense SR means and end-of-season effects.
r15_sr_season <- function(plays_path, raw_schedule, season) {
  e <- r15_r13_env(allow_2020 = season == 2020)
  g <- e$r13_schedule(as.data.frame(raw_schedule))
  stopifnot(all(g$season == season))
  raw <- e$r13_read_plays(plays_path); stopifnot(all(raw$season == season))
  raw[, game_id := as.character(game_id)]
  raw <- raw[game_id %in% g$game_id]
  st <- e$r13_states(r15_recover_fumbles(raw, e), g); el <- e$r13_eligible(st)
  means <- e$r13_game_means(el$plays)
  cut <- max(g$available_at[g$final], na.rm = TRUE) + 1
  ids <- sort(unique(c(g$home_team[g$home_fbs], g$away_team[g$away_fbs])))
  eff <- e$r13_effects(means, ids, cut, half_life = Inf)
  list(means = means, effects = eff[, .(season = season, team, sr_off, sr_def, games_played)], cutoff = cut, schedule = g)
}
