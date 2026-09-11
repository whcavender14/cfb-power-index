# Produce a current, matchup-independent 2026 v5 power-rating table.
#
# Usage:
#   Rscript run_2026_rankings.R
#   Rscript run_2026_rankings.R 2026-09-09T00:00:00Z EB_features
#
# The optional first argument is the information cutoff (UTC); the optional
# second argument is a candidate recorded in the frozen Round 4 design. The
# default candidate is the selected frozen model. Source schedules stay frozen
# unless CFB_REFRESH_SCHEDULE=true; candidate selection remains frozen.

date <- "09/10/2026"

suppressPackageStartupMessages(source("cfb_vCurrent_operations.R"))

args <- commandArgs(trailingOnly = TRUE)
as_of <- if (length(args) >= 1L) {
  utc(args[[1L]])
} else {
  period_start(Sys.time())
}
candidate <- if (length(args) >= 2L) args[[2L]] else NULL

assert(!is.na(as_of), "Invalid UTC cutoff. Example: 2026-09-09T00:00:00Z")
season <- as.integer(Sys.getenv("CFB_SEASON", "2026"))
assert(identical(season, 2026L), "This production entrypoint currently supports the 2026 frozen model only.")
schedule <- NULL
if (identical(Sys.getenv("CFB_REFRESH_SCHEDULE"), "true")) {
  live_cfg <- v4_config()
  live_cfg$cache_dir <- file.path(Sys.getenv("CFB_DATA_DIR", "cfb_data"), "production_live")
  schedule <- read_schedule(season, live_cfg, refresh=TRUE)
}
ratings <- v5_build(season = season, as_of = as_of, candidate = candidate, schedule=schedule)

ranking <- ratings %>%
  arrange(desc(power_rating), team_id) %>%
  mutate(rank = row_number()) %>%
  rename(conference = conf) %>%
  select(
    rank, team, team_id, conference, power_rating, off_rating, def_rating,
    games_played, pre_power, prior_contribution, current_contribution,
    centering_contribution, feature_snapshot_id
  )

out_dir <- "outputs/round4"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
write.csv(ranking, file.path(out_dir, "current_2026_rankings.csv"), row.names = FALSE)
write.csv(
  data.frame(
    season = 2026L,
    candidate = attr(ratings, "candidate"),
    information_cutoff_utc = format(as_of, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    hfa_points = attr(ratings, "hfa"),
    design_hash = attr(ratings, "design_hash"),
    feature_hash = attr(ratings, "feature_hash"),
    stringsAsFactors = FALSE
  ),
  file.path(out_dir, "current_2026_rankings_metadata.csv"),
  row.names = FALSE
)

print(ranking %>% select(rank, team, conference, power_rating, games_played))
cat("\nWrote", file.path(out_dir, "current_2026_rankings.csv"), "\n")

# A separate namespace prevents comparisons with the older weekly ridge model.
if (is.null(schedule)) schedule <- v4_schedule(season)
observed <- schedule$final %in% TRUE & schedule$available_at < as_of
week <- if (any(observed)) max(schedule$week[observed]) else 0L
snapshot <- list(season=season, week=as.integer(week), updated_at=Sys.time(),
                 as_of=as_of, candidate=attr(ratings,"candidate"),
                 design_hash=attr(ratings,"design_hash"), feature_hash=attr(ratings,"feature_hash"),
                 ratings=ranking)
data_dir <- Sys.getenv("CFB_DATA_DIR", "cfb_data")
dir.create(data_dir, recursive=TRUE, showWarnings=FALSE)
saveRDS(snapshot, file.path(data_dir, sprintf("production_ratings_%d_latest.rds", season)))
saveRDS(snapshot, file.path(data_dir, sprintf("production_ratings_%d_wk%02d.rds", season, week)))

# Create a shareable top-30 graphic. Logos are presentation assets only: they
# are cached after the first successful download and never enter the model.
create_rankings_graphic <- function(ranking, as_of, out_dir, n = 30L) {
  assert(requireNamespace("ggplot2", quietly = TRUE),
         "Package 'ggplot2' is required to create the rankings graphic")
  assert(requireNamespace("ggimage", quietly = TRUE),
         "Package 'ggimage' is required to place team logos in the graphic")
  assert(requireNamespace("magick", quietly = TRUE),
         "Package 'magick' is required to read team logos")
  
  top <- ranking %>%
    slice_head(n = min(n, nrow(ranking))) %>%
    mutate(
      panel = if_else(rank <= ceiling(n() / 2), 1L, 2L),
      panel_row = if_else(panel == 1L, rank, rank - ceiling(n() / 2)),
      y = ceiling(n() / 2) - panel_row + 1,
      x_offset = if_else(panel == 1L, 0, 6.55),
      rating_line = sprintf("%+.1f / %+.1f / %+.1f",
                            power_rating, off_rating, def_rating),
      initials = vapply(strsplit(team, "[[:space:]]+"), function(words) {
        paste0(substr(words[seq_len(min(2L, length(words)))], 1L, 1L),
               collapse = "")
      }, character(1))
    )
  
  logo_dir <- file.path(out_dir, "team_logos")
  dir.create(logo_dir, recursive = TRUE, showWarnings = FALSE)
  logo_paths <- file.path(logo_dir, paste0(top$team_id, ".png"))
  # Use the frozen/local team directory to resolve logo URLs. The ID-based
  # ESPN URL is only a fallback if that artifact is unavailable.
  logo_urls <- rep(NA_character_, nrow(top))
  team_directory_file <- "cfb_data_v2/team_directory.rds"
  if (file.exists(team_directory_file)) {
    team_directory <- readRDS(team_directory_file)
    logo_column <- if ("logos_7" %in% names(team_directory)) "logos_7" else "logo"
    logo_urls <- team_directory[[logo_column]][match(top$team_id,
                                                     team_directory$team_id)]
  }
  logo_urls[is.na(logo_urls) | !nzchar(logo_urls)] <- sprintf(
    "https://a.espncdn.com/i/teamlogos/ncaa/500/%s.png",
    top$team_id[is.na(logo_urls) | !nzchar(logo_urls)]
  )
  
  old_timeout <- getOption("timeout")
  on.exit(options(timeout = old_timeout), add = TRUE)
  options(timeout = max(10, old_timeout))
  for (i in seq_along(logo_paths)) {
    if (!file.exists(logo_paths[[i]])) {
      try(suppressWarnings(download.file(logo_urls[[i]], logo_paths[[i]],
                                         mode = "wb", quiet = TRUE)),
          silent = TRUE)
    }
  }
  valid_logo <- file.exists(logo_paths) & file.info(logo_paths)$size > 0
  if (any(valid_logo)) {
    valid_logo[valid_logo] <- vapply(logo_paths[valid_logo], function(path) {
      !inherits(try(magick::image_read(path), silent = TRUE), "try-error")
    }, logical(1))
  }
  top$logo <- ifelse(valid_logo, logo_paths, NA_character_)
  
  navy <- "#071426"
  ink <- "#F7FAFC"
  muted <- "#9FB0C5"
  gold <- "#F4B942"
  rows <- top %>%
    transmute(x = x_offset + 3.25, y, fill = if_else(panel_row %% 2L == 0L,
                                                     "#10233B", "#0C1C31"))
  
  p <- ggplot2::ggplot() +
    ggplot2::geom_tile(data = rows, ggplot2::aes(x, y, fill = fill),
                       width = 6.35, height = 0.88, show.legend = FALSE) +
    ggplot2::scale_fill_identity() +
    ggplot2::geom_text(data = top, ggplot2::aes(x_offset + 0.32, y, label = rank),
                       color = gold, fontface = "bold", size = 4.2,
                       family = "sans") +
    ggimage::geom_image(data = top %>% filter(!is.na(logo)),
                        ggplot2::aes(x_offset + 0.86, y, image = logo),
                        size = 0.052, asp = 1) +
    ggplot2::geom_point(data = top %>% filter(is.na(logo)),
                        ggplot2::aes(x_offset + 0.86, y), shape = 21,
                        size = 8.5, stroke = 0.6, fill = "#243B57", color = muted) +
    ggplot2::geom_text(data = top %>% filter(is.na(logo)),
                       ggplot2::aes(x_offset + 0.86, y, label = initials),
                       color = ink, fontface = "bold", size = 2.7,
                       family = "sans") +
    ggplot2::geom_text(data = top, ggplot2::aes(x_offset + 1.34, y, label = team),
                       color = ink, fontface = "bold", size = 4.0, hjust = 0,
                       family = "sans") +
    ggplot2::geom_text(data = top,
                       ggplot2::aes(x_offset + 6.20, y, label = rating_line),
                       color = ink, size = 3.7, hjust = 1, family = "mono") +
    ggplot2::annotate("text", x = c(0.32, 6.87), y = 16.05,
                      label = "RANK", color = muted, fontface = "bold",
                      size = 3.0, hjust = 0.5) +
    ggplot2::annotate("text", x = c(6.20, 12.75), y = 16.05,
                      label = "POWER / OFF / DEF", color = muted,
                      fontface = "bold", family = "mono", size = 3.0,
                      hjust = 1) +
    ggplot2::labs(
      title = "2026 COLLEGE FOOTBALL POWER RATINGS",
      subtitle = sprintf("Top 30 · Matchup-independent · Through %s UTC",
                         format(as_of, "%B %d, %Y", tz = "UTC")),
      caption = "Ratings shown in points relative to an average FBS team"
    ) +
    ggplot2::coord_cartesian(xlim = c(0, 13.1), ylim = c(0.2, 16.35),
                             clip = "off", expand = FALSE) +
    ggplot2::theme_void(base_family = "sans") +
    ggplot2::theme(
      plot.background = ggplot2::element_rect(fill = navy, color = NA),
      panel.background = ggplot2::element_rect(fill = navy, color = NA),
      plot.title = ggplot2::element_text(color = ink, face = "bold", size = 24,
                                         margin = ggplot2::margin(b = 5)),
      plot.subtitle = ggplot2::element_text(color = muted, size = 11,
                                            margin = ggplot2::margin(b = 14)),
      plot.caption = ggplot2::element_text(color = muted, size = 9, hjust = 0,
                                           margin = ggplot2::margin(t = 10)),
      plot.margin = ggplot2::margin(24, 30, 20, 30)
    )
  
  date_clean <- format(as.Date(as_of, format = "%m/%d/%Y"), "%Y-%m-%d")
  output_file <- file.path(out_dir, paste0("current_", date_clean, "_rankings_top30.png"))
  
  output_file <- file.path(png_dir, paste0("current_", date_clean, "_rankings_top30.png"))
  ggplot2::ggsave(
    filename = output_file,
    plot     = p,
    width    = 15,
    height   = 11,
    units    = "in",
    dpi      = 220,
    bg       = navy
  )
  
  output_file
}

if (!identical(Sys.getenv("CFB_CREATE_GRAPHIC"), "false")) {
  png_dir <- "ratings"
  dir.create(png_dir, recursive=TRUE, showWarnings=FALSE)
  graphic_file <- create_rankings_graphic(ranking, as_of, png_dir)
  cat("Wrote", graphic_file, "\n")
}
