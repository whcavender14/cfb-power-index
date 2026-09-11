# Descriptive season-end HFA rankings for the rejected team-HFA experiment.
# This script does not source or modify production operations.
source('team_hfa_experiment.R')

out <- 'outputs/team_hfa'
freeze <- readRDS(file.path(out, 'design_frozen.rds'))
dev <- hfa_read('outputs/round5/development_predictions.csv')
conditional <- hfa_read('outputs/round5/conditional_predictions.csv')
all_predictions <- bind_rows(dev, conditional)

# The existing experiment selected lambda=50 before conditional labels were
# opened.  It remains fixed here: this is a descriptive ranking, not tuning.
lambda <- freeze$parameters$ridge
stopifnot(identical(lambda, 50))

name_lookup <- bind_rows(lapply(2022:2025, function(season) {
  g <- v4_schedule(season)
  bind_rows(
    transmute(g, team_id = home_id, team = home_team),
    transmute(g, team_id = away_id, team = away_team)
  )
})) %>%
  distinct(team_id, team, .keep_all = TRUE)

rankings <- bind_rows(lapply(2022:2025, function(season) {
  season_rows <- all_predictions[all_predictions$season == season, ]
  # Include a final game's result only after the conservative +24-hour rule.
  as_of <- max(season_rows$kickoff) + 24 * 60 * 60 + 1
  fit <- hfa_fit(all_predictions, as_of, lambda)
  global_hfa <- unique(season_rows$hfa)
  stopifnot(length(global_hfa) == 1L)

  fit$table %>%
    mutate(
      season = season,
      as_of_utc = format(as_of, '%Y-%m-%dT%H:%M:%SZ', tz = 'UTC'),
      global_HFA = global_hfa,
      team_HFA = global_hfa + deviation,
      rank_high_to_low = min_rank(desc(team_HFA)),
      diagnostic_status = 'rejected_nonproduction'
    ) %>%
    left_join(name_lookup, by = 'team_id') %>%
    select(season, rank_high_to_low, team, team_id, team_HFA, global_HFA,
           deviation, n, seasons, opponents, effective_n, shrinkage,
           centering_correction, mean_residual, as_of_utc, diagnostic_status) %>%
    arrange(rank_high_to_low, team_id)
}))

write.csv(rankings, file.path(out, 'team_hfa_rankings_2022_2025.csv'), row.names = FALSE)

summary <- rankings %>%
  group_by(season, as_of_utc, global_HFA) %>%
  summarise(teams = n(), min_team_HFA = min(team_HFA),
            median_team_HFA = median(team_HFA), max_team_HFA = max(team_HFA),
            .groups = 'drop')
write.csv(summary, file.path(out, 'team_hfa_rankings_2022_2025_summary.csv'), row.names = FALSE)

writeLines(c(
  '# 2022–2025 implied team HFA ranking',
  '',
  'This is a descriptive ranking from the rejected common-ridge team-HFA experiment. It is not a production rating, forecast input, or evidence supporting promotion.',
  '',
  'Each season uses every eligible archived forward-prediction residual available strictly before the displayed season-end cutoff. Results follow the experiment availability rule: final kickoff + 24 hours + one second. The ridge penalty is the frozen earlier-only selection, lambda=50, for every displayed season. No conditional outcome was used to tune that penalty or the model selection.',
  '',
  'team_HFA = that season\'s incumbent global_HFA + centered ridge deviation. The deviations are centered equally across observed home teams. `n` is raw eligible home-game residual count; `effective_n` is the conservative evidence count used by the fit; `shrinkage` is effective_n/(effective_n + 50), before the small centering correction.',
  '',
  'The ranking reflects residual prediction patterns and can still contain strength, schedule, opponent, and model-error effects. It should not be read as a causal stadium-effect ranking.'
), file.path(out, 'TEAM_HFA_RANKINGS_2022_2025.md'))

print(summary)
print(rankings %>% group_by(season) %>% slice_head(n = 10) %>%
        select(season, rank_high_to_low, team, team_HFA, n, effective_n, shrinkage))
