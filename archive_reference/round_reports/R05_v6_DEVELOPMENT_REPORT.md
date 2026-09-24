# Earlier-only development: 2019, 2021, 2022

Frozen selection: v5_EB_features

```
                            candidate    n   mae  rmse   bias intercept slope
                current_efficiency_EB 2320 12.90 16.25 0.5051   -0.6549 1.120
                  efficiency_prior_EB 2320 12.92 16.27 0.5427   -0.5921 1.038
                    full_preseason_EB 2320 12.92 16.27 0.5793   -0.6136 1.026
 full_preseason_current_efficiency_EB 2320 12.92 16.27 0.5168   -0.5854 1.054
                  multi_year_prior_EB 2320 12.85 16.17 0.6177   -0.6622 1.033
               special_teams_prior_EB 2320 12.91 16.26 0.5427   -0.6078 1.050
                       v5_EB_features 2320 12.92 16.27 0.5168   -0.5854 1.054
 prediction_sd actual_margin_sd straight_up_accuracy
         11.86            20.92               0.7211
         12.70            20.92               0.7108
         12.85            20.92               0.7155
         12.51            20.92               0.7095
         12.89            20.92               0.7125
         12.57            20.92               0.7134
         12.51            20.92               0.7095
```

All candidates share identical final FBS-versus-FBS IDs, including postseason. Candidate selection uses only development outcomes through2022. New families must clear every frozen safeguard; conditional performance cannot change selection.

The current-efficiency candidate replaces a fixed 25% of available past team-score evidence with a success-rate score mapping learned on earlier game rows. Added preseason blocks use fold-local elastic net and incumbent unit fallback. The special-teams family tests returns/field position; it does not cover kicking reliability or punting efficiency.

Position RP, valid QB starters/quality and coordinator continuity were not estimable from recovered historical state evidence. Their missing experiment is not a fitted zero effect. EPA/explosiveness are excluded because expected-points training/version provenance remains unresolved.

Probability coverage is reported separately. 2019 has no eligible earlier frozen margin predictions for this mapping; it remains missing. Brier/log loss and reliability apply only to rows with earlier-fitted probabilities. This layer never affects published margins or selection.

Diagnostics: separate calibration, probability, reliability, network and distribution CSVs. Fixed seed9041, 2000 season and season-then-Monday-block resamples. Only three principal development seasons limit precision. 2026 is prospective only.
