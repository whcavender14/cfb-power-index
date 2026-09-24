#!/usr/bin/env Rscript
# ============================================================================
# v10_refined Gate 5: forward P4-vs-G5 test.
# Implements Amendment 2 to the v10_refined predeclaration:
#   archive/v10-round10/docs/v10_refined_amendment_02_gate5.md
#
#  * Season-indexed tier map: Pac-12 is P4 through 2025 and G5 from 2026.
#  * Eligible game: P4-vs-G5 under that map, kickoff at/after LOCK_UTC,
#    season 2026 or 2027 (regular season + postseason), completed, with a
#    frozen-incumbent prediction from an md5-verified prospective snapshot
#    made before kickoff (the latest such snapshot is used).
#  * One look. Before FINAL_LOOK_ON_OR_AFTER this script prints counts only:
#    no margins, residuals, bias or MAE.
#  * Rule: PASS iff |bias(v10_refined)| < |bias(incumbent)|.
#  * Frozen coefficients a = 2.356, b = 1.831. Nothing is re-fit.
# Pre-amendment script: sha256 79d3203005071793cf62ede8a40fe63be5a99abf31e8a545dc913853dae7d920
#   (diff: archive/v10-round10/docs/v10_refined_amendment_02_gate5_2026R.diff)
# ============================================================================
setwd("/Users/willcavender/Desktop/CFB Modeling")

if (!require("httr", quietly = TRUE)) install.packages("httr")
if (!require("jsonlite", quietly = TRUE)) install.packages("jsonlite")
if (!require("tidyverse", quietly = TRUE)) install.packages("tidyverse")

library(httr)
library(jsonlite)
library(tidyverse)
library(lubridate)

# ============================================================================
# PART A: Constants fixed by Amendment 2 (change only by a further amendment)
# ============================================================================

A_FROZEN <- 2.356
B_FROZEN <- 1.831

INCUMBENT_CANDIDATE    <- "EB_features"
INCUMBENT_DESIGN_HASH  <- "0f876d7390dace668ab8fb80547b949e"  # md5 of outputs/round4/design_frozen.rds
INCUMBENT_FEATURE_HASH <- "6a7e01742348969e8c623e21702185c6"
SNAPSHOT_DIR <- "outputs/round4/prospective"
SNAPSHOT_TZ  <- "America/New_York"  # predicted_at is written in local time; schedule kickoff is UTC

LOCK_UTC <- "2026-09-22T14:31:18Z"  # set at sign-off (Amendment 2 section 6)
WINDOW_SEASONS <- c(2026, 2027)
FINAL_LOOK_ON_OR_AFTER <- as.Date("2028-02-01")
N_FLOOR <- 60
EXTENSION_SEASON <- 2028            # used only if n < N_FLOOR at the final look
EXTENSION_MAX_WEEK <- 4
EXTENSION_FINAL_LOOK_ON_OR_AFTER <- as.Date("2028-10-01")

OUT_DIR <- "archive/v10-round10/results/gate5_amendment02"

# Season-indexed tier map (Amendment 2 section 2; same as Round 12 draft B3).
P4_CORE <- c("ACC", "Big Ten", "Big 12", "SEC")
G5_CORE <- c("American Athletic", "Conference USA", "Mid-American", "Mountain West", "Sun Belt")

tier_of <- function(conference, season) {
  case_when(
    conference %in% P4_CORE ~ "P4",
    conference %in% G5_CORE ~ "G5",
    conference %in% "Pac-12" & season <= 2025 ~ "P4",
    conference %in% "Pac-12" & season >= 2026 ~ "G5",
    TRUE ~ "Other"
  )
}

classify_p4_g5 <- function(g) {
  g %>%
    mutate(
      home_tier = tier_of(home_conference, season),
      away_tier = tier_of(away_conference, season),
      s = case_when(
        home_tier == "P4" & away_tier == "G5" ~ 1,
        home_tier == "G5" & away_tier == "P4" ~ -1,
        TRUE ~ 0
      ),
      p4_home = as.numeric(s == 1 & !neutral)
    )
}

# ============================================================================
# PART B: Schedules (regular season + postseason) from the CFBD API
# ============================================================================

fetch_schedule <- function(season, api_key) {
  # Regular season and postseason are pulled explicitly: the API default
  # skips bowls, and the development set (2018-22) includes them.
  bind_rows(lapply(c("regular", "postseason"), function(st) {
    url <- sprintf("https://api.collegefootballdata.com/games?year=%d&seasonType=%s", season, st)
    response <- GET(url, add_headers(Authorization = paste("Bearer", api_key)))
    if (status_code(response) != 200) {
      stop(paste("API Error:", status_code(response), "\n", content(response, "text")))
    }
    raw <- fromJSON(content(response, "text"))
    if (NROW(raw) == 0) return(NULL)
    as.data.frame(raw) %>%
      transmute(
        game_id = id, season = season, week = week, season_type = st, kickoff = startDate,
        home_team = homeTeam, away_team = awayTeam,
        home_conference = homeConference, away_conference = awayConference,
        neutral = neutralSite, home_score = homePoints, away_score = awayPoints,
        completed = completed
      )
  }))
}

load_schedules <- function(seasons) {
  replay <- Sys.getenv("GATE5_SCHEDULE_FILES")  # comma-separated saved pulls, for offline replay/tests
  if (nzchar(replay)) {
    g <- bind_rows(lapply(strsplit(replay, ",")[[1]], read.csv, stringsAsFactors = FALSE))
    if (!"season_type" %in% names(g)) g$season_type <- "regular"
    if (!"completed" %in% names(g)) g$completed <- g$played
  } else {
    api_key <- Sys.getenv("CFBD_API_KEY")
    if (api_key == "") {
      stop("CFBD_API_KEY environment variable not set. Run: export CFBD_API_KEY='your_key'")
    }
    g <- bind_rows(lapply(seasons, fetch_schedule, api_key = api_key))
    dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
    pull_path <- file.path(OUT_DIR, sprintf("schedule_pull_%s.csv", format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")))
    write.csv(g, pull_path, row.names = FALSE)
    cat(sprintf("Saved schedule pull to %s\n", pull_path))
  }
  g %>%
    filter(season %in% seasons) %>%
    mutate(
      game_id = as.character(game_id),
      kickoff_utc = ymd_hms(kickoff, tz = "UTC"),
      neutral = as.logical(neutral),
      actual_margin = ifelse(!is.na(home_score) & !is.na(away_score), home_score - away_score, NA),
      played = !is.na(completed) & as.logical(completed) & !is.na(actual_margin)
    ) %>%
    classify_p4_g5()
}

# ============================================================================
# PART C: Frozen incumbent predictions from prospective snapshots
# ============================================================================

load_snapshots <- function(dir = SNAPSHOT_DIR) {
  files <- list.files(dir, pattern = "^predictions_.*\\.csv$", full.names = TRUE)
  if (length(files) == 0) stop(sprintf("No prospective snapshots in %s", dir))
  snap <- bind_rows(lapply(files, function(f) {
    md5_path <- paste0(f, ".md5")
    if (!file.exists(md5_path)) stop(sprintf("Missing md5 sidecar: %s", md5_path))
    if (unname(tools::md5sum(f)) != trimws(readLines(md5_path, warn = FALSE)[1])) {
      stop(sprintf("md5 mismatch, snapshot changed after archiving: %s", f))
    }
    read.csv(f, stringsAsFactors = FALSE) %>%
      mutate(game_id = as.character(game_id), snapshot_file = basename(f))
  }))
  snap <- snap %>%
    filter(
      candidate == INCUMBENT_CANDIDATE,
      design_hash == INCUMBENT_DESIGN_HASH,
      feature_hash == INCUMBENT_FEATURE_HASH
    ) %>%
    mutate(predicted_at_utc = with_tz(ymd_hms(predicted_at, tz = SNAPSHOT_TZ), "UTC"))
  if (anyNA(snap$predicted_at_utc)) stop("Unparseable predicted_at in a prospective snapshot")
  snap
}

# Latest snapshot made strictly before kickoff. The schedule's kickoff is
# authoritative, so a game moved earlier than its snapshot is excluded.
latest_prekickoff_prediction <- function(snap, sched) {
  snap %>%
    select(game_id, season, predicted_at_utc, incumbent_margin = pred_margin, snapshot_file) %>%
    inner_join(sched %>% select(game_id, season, kickoff_utc), by = c("game_id", "season")) %>%
    filter(predicted_at_utc < kickoff_utc) %>%
    group_by(game_id, season) %>%
    slice_max(predicted_at_utc, n = 1, with_ties = FALSE) %>%
    ungroup() %>%
    select(-kickoff_utc)
}

# ============================================================================
# PART D: Gate 5 rule (Amendment 2 section 3)
# ============================================================================

gate5_decide <- function(d) {
  d <- d %>%
    mutate(
      correction = s * (A_FROZEN + B_FROZEN * p4_home),
      v10_refined = incumbent_margin + correction,
      r_incumbent = (actual_margin - incumbent_margin) * s,
      r_v10_refined = (actual_margin - v10_refined) * s
    )
  bias_inc <- mean(d$r_incumbent)
  bias_v10r <- mean(d$r_v10_refined)
  list(
    rows = d, n = nrow(d),
    bias_incumbent = bias_inc, bias_v10_refined = bias_v10r,
    mean_applied = mean(A_FROZEN + B_FROZEN * d$p4_home),
    pass = abs(bias_v10r) < abs(bias_inc)
  )
}

# ============================================================================
# PART E: Counts-only monitoring, or the single final look
# ============================================================================

main <- function() {
  lock_utc <- if (is.na(LOCK_UTC)) NA else ymd_hms(LOCK_UTC, tz = "UTC")
  today <- Sys.Date()
  final_report_path <- file.path(OUT_DIR, "gate5_final_report.txt")
  final_rows_path <- file.path(OUT_DIR, "gate5_final_rows.csv")
  if (file.exists(final_report_path)) {
    stop(sprintf("Final look already run (%s). Gate 5 is evaluated once.", final_report_path))
  }

  sched <- load_schedules(WINDOW_SEASONS)
  snap <- load_snapshots()
  preds <- latest_prekickoff_prediction(snap, sched)

  x <- sched %>%
    filter(s != 0) %>%
    left_join(preds, by = c("game_id", "season")) %>%
    mutate(
      in_window = !is.na(lock_utc) & kickoff_utc >= lock_utc,
      has_prediction = !is.na(incumbent_margin),
      eligible = in_window & played & has_prediction
    )
  if (anyNA(x$kickoff_utc)) stop("P4-vs-G5 game with an unparseable kickoff time")

  cat("\n", strrep("=", 60), "\n", sep = "")
  cat("v10_refined GATE 5: COUNTS (no outcomes are used in this section)\n")
  cat(strrep("=", 60), "\n", sep = "")
  cat(sprintf("Lock: %s | final look on or after %s | n floor %d\n",
              ifelse(is.na(LOCK_UTC), "NOT SET (amendment not signed)", LOCK_UTC),
              FINAL_LOOK_ON_OR_AFTER, N_FLOOR))
  cat(sprintf("Snapshots: %d file(s); latest predicted_at %s UTC\n",
              n_distinct(snap$snapshot_file), format(max(snap$predicted_at_utc))))
  counts <- x %>%
    group_by(season, season_type) %>%
    summarise(
      n_p4_vs_g5 = n(),
      n_pre_lock = sum(!in_window),
      n_in_window = sum(in_window),
      n_in_window_played = sum(in_window & played),
      n_eligible = sum(eligible),
      n_played_no_pred = sum(in_window & played & !has_prediction),
      .groups = "drop"
    )
  print(as.data.frame(counts), row.names = FALSE)
  n_eligible <- sum(x$eligible)
  cat(sprintf("\nEligible so far: %d\n", n_eligible))
  if (any(counts$n_played_no_pred > 0)) {
    cat("WARNING: in-window games were played without a pre-kickoff snapshot prediction.\n")
    cat("         Archive a snapshot weekly (v5_weekly_update + v5_archive_upcoming) before kickoffs.\n")
  }
  upcoming_without_pred <- sum(x$in_window & !x$played & !x$has_prediction)
  if (upcoming_without_pred > 0) {
    cat(sprintf("NOTE: %d upcoming in-window games have no snapshot prediction yet.\n", upcoming_without_pred))
  }
  dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
  write.csv(
    x %>% select(game_id, season, season_type, week, kickoff_utc, home_team, away_team,
                 home_conference, away_conference, s, p4_home,
                 in_window, played, has_prediction, eligible, snapshot_file),
    file.path(OUT_DIR, "gate5_window_ids.csv"), row.names = FALSE
  )

  if (is.na(LOCK_UTC) || today < FINAL_LOOK_ON_OR_AFTER) {
    cat("\nNot the final look: counts only. No bias, residual or MAE is computed before the final look.\n")
    return(invisible(NULL))
  }

  if (n_eligible < N_FLOOR) {
    if (today < EXTENSION_FINAL_LOOK_ON_OR_AFTER) {
      cat(sprintf("\nn = %d < floor %d. Window extends through %d regular-season week %d (Amendment 2 section 4.2). No verdict.\n",
                  n_eligible, N_FLOOR, EXTENSION_SEASON, EXTENSION_MAX_WEEK))
      return(invisible(NULL))
    }
    ext_sched <- load_schedules(EXTENSION_SEASON)
    ext <- ext_sched %>%
      filter(s != 0, season_type == "regular", week <= EXTENSION_MAX_WEEK) %>%
      left_join(latest_prekickoff_prediction(snap, ext_sched), by = c("game_id", "season")) %>%
      mutate(in_window = TRUE, has_prediction = !is.na(incumbent_margin), eligible = played & has_prediction)
    x <- bind_rows(x, ext)
    n_eligible <- sum(x$eligible)
    cat(sprintf("Extension window added: eligible n = %d\n", n_eligible))
  }

  d <- x %>% filter(eligible)
  if (nrow(d) == 0) stop("Final look reached with no eligible games; check snapshots and schedule.")
  res <- gate5_decide(d)
  d <- res$rows

  L <- character(0)
  say <- function(...) { line <- sprintf(...); cat(line, "\n", sep = ""); L <<- c(L, line) }
  se <- function(v) sd(v) / sqrt(length(v))
  ci <- function(v) mean(v) + c(-1.96, 1.96) * se(v)
  split_bias <- function(mask) if (any(mask)) sprintf("n=%d bias %+.2f", sum(mask), mean(d$r_v10_refined[mask])) else "n=0"

  set.seed(42)
  blocks <- split(seq_len(nrow(d)), paste(d$season, d$season_type, d$week))
  boot <- replicate(2000, {
    idx <- unlist(blocks[sample(length(blocks), replace = TRUE)], use.names = FALSE)
    c(mean(d$r_incumbent[idx]), mean(d$r_v10_refined[idx]))
  })
  boot_ci <- apply(boot, 1, quantile, c(0.025, 0.975))
  d_mae <- mean(abs(d$actual_margin - d$v10_refined) - abs(d$actual_margin - d$incumbent_margin))
  d_mse <- mean((d$actual_margin - d$v10_refined)^2 - (d$actual_margin - d$incumbent_margin)^2)
  age_days <- as.numeric(difftime(d$kickoff_utc, d$predicted_at_utc, units = "days"))
  p4_conf <- ifelse(d$s == 1, d$home_conference, d$away_conference)

  say("%s", strrep("=", 60))
  say("v10_refined GATE 5: FINAL LOOK (Amendment 2)")
  say("%s", strrep("=", 60))
  say("Run at %s UTC | lock %s", format(Sys.time(), tz = "UTC"), LOCK_UTC)
  say("Eligible P4-vs-G5 games: n = %d (%s)", res$n,
      paste(names(table(d$season)), table(d$season), sep = ": ", collapse = ", "))
  say("Incumbent bias:   %+.2f (SE %.2f)", res$bias_incumbent, se(d$r_incumbent))
  say("v10_refined bias: %+.2f (SE %.2f)", res$bias_v10_refined, se(d$r_v10_refined))
  say("Mean applied correction %.3f; break-even incumbent bias %.3f", res$mean_applied, res$mean_applied / 2)
  say("")
  say("Rule: PASS iff |bias(v10_refined)| < |bias(incumbent)|")
  say("  |%+.2f| %s |%+.2f|", res$bias_v10_refined, ifelse(res$pass, "<", ">="), res$bias_incumbent)
  say("Gate 5: %s", ifelse(res$pass, "PASS -> PROMOTE v10_refined (predeclaration Part E)",
                                     "FAIL -> STAY on incumbent (predeclaration Part E)"))
  say("")
  say("Report only (not gating):")
  say("  95%% CI, iid:          incumbent [%+.2f, %+.2f] | v10_refined [%+.2f, %+.2f]",
      ci(d$r_incumbent)[1], ci(d$r_incumbent)[2], ci(d$r_v10_refined)[1], ci(d$r_v10_refined)[2])
  say("  95%% CI, week blocks:  incumbent [%+.2f, %+.2f] | v10_refined [%+.2f, %+.2f] (2000 reps, seed 42)",
      boot_ci[1, 1], boot_ci[2, 1], boot_ci[1, 2], boot_ci[2, 2])
  say("  Paired dMAE (v10_refined - incumbent) %+.3f | paired dMSE %+.2f", d_mae, d_mse)
  say("  v10_refined venue split: P4 home %s | P4 away/neutral %s", split_bias(d$p4_home == 1), split_bias(d$p4_home == 0))
  for (conf in P4_CORE) say("  v10_refined, P4 side %s: %s", conf, split_bias(p4_conf == conf))
  say("  Snapshot age at kickoff (days): median %.1f, max %.1f", median(age_days), max(age_days))

  write.csv(
    d %>% select(game_id, season, season_type, week, kickoff_utc, home_team, away_team,
                 home_conference, away_conference, s, p4_home, actual_margin,
                 incumbent_margin, v10_refined, r_incumbent, r_v10_refined,
                 snapshot_file, predicted_at_utc),
    final_rows_path, row.names = FALSE
  )
  writeLines(L, final_report_path)
  Sys.chmod(c(final_report_path, final_rows_path), "0444")
  cat(sprintf("\nSaved %s and %s (read-only)\n", final_report_path, final_rows_path))
}

if (sys.nframe() == 0L) main()
