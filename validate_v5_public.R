# Produce reader-facing validation metrics for the frozen v5 model.
#
# Usage:
#   Rscript validate_v5_public.R
#   Rscript validate_v5_public.R /path/to/read_only_market_lines.csv
#
# The default input is the frozen 2023-2025 secondary conditional test. Those
# seasons were previously exposed by Round 3 and must not be called a fresh
# holdout. Market data is optional and is read only after frozen predictions
# are loaded; it never enters the rating model, feature pipeline, calibration,
# or candidate selection.

suppressPackageStartupMessages(source("cfb_v5_operations.R"))

args <- commandArgs(trailingOnly = TRUE)
market_file <- if (length(args)) args[[1L]] else NA_character_
freeze <- v5_frozen()
candidate <- freeze$selected
model_label <- candidate
validation <- v5_validation("conditional")$predictions %>%
  filter(candidate == !!candidate)

assert(nrow(validation) > 0L, "No frozen conditional predictions found.")
assert(all(is.finite(validation$pred_margin)), "Non-finite frozen predictions.")

public_metrics <- function(d) {
  x <- d$pred_margin - d$hfa * as.numeric(!d$neutral)
  y <- d$actual_margin - d$hfa * as.numeric(!d$neutral)
  fit <- stats::lm(y ~ x)
  decisive <- d$actual_margin != 0 & d$pred_margin != 0
  tibble(
    games = nrow(d),
    mae_points = mean(abs(d$pred_margin - d$actual_margin)),
    rmse_points = sqrt(mean((d$pred_margin - d$actual_margin)^2)),
    bias_points = mean(d$pred_margin - d$actual_margin),
    calibration_intercept = unname(stats::coef(fit)[1L]),
    calibration_slope = unname(stats::coef(fit)[2L]),
    straight_up_pick_pct = if (any(decisive)) {
      mean(sign(d$pred_margin[decisive]) == sign(d$actual_margin[decisive]))
    } else {
      NA_real_
    },
    prediction_sd = stats::sd(d$pred_margin),
    actual_margin_sd = stats::sd(d$actual_margin)
  )
}

overall <- public_metrics(validation) %>%
  mutate(candidate = model_label, evaluation = "2023-2025 secondary conditional")
by_season <- validation %>%
  group_by(season) %>%
  group_modify(~ public_metrics(.x)) %>%
  ungroup() %>%
  mutate(candidate = model_label)
by_state <- validation %>%
  mutate(
    calendar_period = ifelse(week_seq <= 4L, paste0("period_", week_seq), "period_5_plus"),
    min_fbs_games = pmin(gp_home, gp_away),
    evidence_state = cut(min_fbs_games, c(-1, 0, 1, 3, 6, Inf),
      labels = c("0", "1", "2-3", "4-6", "7_plus")
    )
  ) %>%
  group_by(calendar_period, evidence_state) %>%
  group_modify(~ public_metrics(.x)) %>%
  ungroup() %>%
  mutate(candidate = model_label)

out_dir <- "outputs/round4"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
write.csv(overall, file.path(out_dir, "public_validation_overall.csv"), row.names = FALSE)
write.csv(by_season, file.path(out_dir, "public_validation_by_season.csv"), row.names = FALSE)
write.csv(by_state, file.path(out_dir, "public_validation_by_evidence_state.csv"), row.names = FALSE)

if (!is.na(market_file)) {
  assert(file.exists(market_file), paste("Market file does not exist:", market_file))
  # This read happens after validation has been frozen and loaded. These fields
  # are deliberately kept local to this reporting-only block.
  lines <- read.csv(market_file, stringsAsFactors = FALSE)
  assert(all(c("game_id", "spread") %in% names(lines)),
    "Market file requires game_id and home-team spread columns."
  )
  lines <- lines %>%
    transmute(game_id = as.character(game_id), market_home_margin = -as.numeric(spread))
  assert(!anyDuplicated(lines$game_id), "Market file has duplicate game IDs.")

  ats_games <- validation %>%
    mutate(game_id = as.character(game_id)) %>%
    inner_join(lines, by = "game_id") %>%
    mutate(
      # The model's ATS side is based on its frozen margin versus the line.
      model_home_cover = pred_margin > market_home_margin,
      actual_home_cover = actual_margin > market_home_margin,
      model_pick = pred_margin != market_home_margin,
      push = actual_margin == market_home_margin,
      ats_win = model_pick & !push & model_home_cover == actual_home_cover,
      ats_loss = model_pick & !push & model_home_cover != actual_home_cover
    )
  assert(nrow(ats_games) == nrow(validation),
    "Market coverage is incomplete; do not report an all-games ATS rate."
  )
  ats_summary <- ats_games %>%
    summarise(
      candidate = model_label,
      games_with_lines = n(),
      ats_decisions = sum(ats_win | ats_loss),
      ats_wins = sum(ats_win),
      ats_losses = sum(ats_loss),
      pushes = sum(push),
      ats_win_pct = ats_wins / ats_decisions,
      model_mae_points = mean(abs(pred_margin - actual_margin)),
      market_mae_points = mean(abs(market_home_margin - actual_margin)),
      model_minus_market_mae = model_mae_points - market_mae_points
    )
  write.csv(ats_summary, file.path(out_dir, "public_validation_ats.csv"), row.names = FALSE)
} else {
  message("ATS omitted: supply a read-only market file with game_id and spread.")
}

writeLines(c(
  "Public validation metric definitions",
  "MAE/RMSE: error in predicted final home margin, in points.",
  "Bias: predicted final home margin minus actual final home margin.",
  "Calibration slope/intercept: OLS of actual neutralized margin on predicted neutralized margin; fitted HFA is removed from both.",
  "Straight-up pick percentage: fraction of non-tied games where the predicted winner matches the winner.",
  "ATS: post-prediction comparison to an optional read-only home-team spread. It is not a model input. Pushes and exact model/line ties are excluded from the denominator.",
  "The 2023-2025 results are a secondary conditional test, not a fresh holdout or proof of future betting profitability."
), file.path(out_dir, "public_validation_metric_definitions.txt"))

print(overall)
cat("\nWrote public validation files under", out_dir, "\n")
