# v5 point-scale specification

Round 4 reuses v4 score solvers read-only, through source('cfb_power_ratings_v4.R'). Public production entry points are v5_*. No v4 model or Round 3 artifact is modified.

## Common construction and units

Historical ridge1 fits PF_ij = mu + o_i + d_j + H*hx_ij, hx=+1/2 home, -1/2 away, zero neutral. Offense and defensive burden are point-scale effects (lower d is better); power=o-d. Historical H uses the existing weak penalty toward 3. Only prior-season finished score estimates feed next-season prior inputs. Current score estimation uses results with available_at < information_cutoff, conservatively defined as kickoff+24h. FCS games never enter the score solver or counted-FBS clock in these candidates. Available game IDs and graph states are retained in snapshots.

B is exactly v4: separate OLS preseason regressions on prev_off, prev_def and promotion/missing-history state, then a fitted positive preseason scale s. HFA is fitted jointly with the baseline preseason difference by LAD on earlier forward predictions. B current-score HFA is the earlier historical median, distinct from prediction HFA; neither is added twice. B's final k=2.42341032206791, s=.900631707813218, HFA=3.06853968902663.

## External priors and missingness

For each side independently, form the available subset of external features for each target team. RP uses off_returning for offense, def_returning for defense. Talent_RP also uses log1p(talent_composite), blue_chip_ratio and log1p(n_recruits). Coach uses log1p(tenure) and new_coach. Full uses all of these. Do not infer QB state: unknown_QB is metadata only.

For each coverage regime, fit y = b0 + X*b to completed earlier unit ratings, using prior offense, prior burden, promotion and the available external subset. Minimize mean((y-Xb)^2) + lambda*sum(b_j^2), excluding intercept from the penalty. Alpha=0 (ridge); lambda in {.1,1,10,100}; select separately for each side/regime by earlier forward team-season MSE. At least 80 complete earlier rows and a usable inner forward fold are required. Training-only medians apply to previous-score missingness. External substantive features are never imputed. Training-only QR rank audit, means and SDs define each design; exact/numerically near dependencies and constants are logged. No target-season outcome normalization or feature selection.

With no usable external subset, that side falls back to B. Center resulting o and d across all FBS IDs. If every external feature is unavailable, the feature-enabled snapshot path returns exact B priors AND baseline scale/handoff predictions; EB feature mode also explicitly falls back to B in that case. Pure-score EB comparators remain their declared distinct estimators. Common centering can shift individual fallback rows when other teams have features; matchup contrasts remain coherent.

The feature model replaces the unit preseason regression, so its contrast against B includes both the feature and the declared ridge/coverage-regime estimation policy. RP-only and talent/coaching component comparisons help locate the gains; they are not causal estimates of player continuity.

## Calibration and update families

Each feature family fits its own preseason scalar s by bracketed LAD on earlier forward margins, with the corresponding baseline HFA fixed. B_scale fixes B's s, k and HFA, then fits positive gamma on earlier forward margins. Its published O=gamma*latent_O and D=gamma*latent_D; HFA is never multiplied by gamma. It is a fitted model parameter, not a held-out slope correction.

Convex families: w=n/(n+k), O=(1-w)*s*pre_off+w*current_off, D analogous. Center then apply gamma. At n=0 the uncentered rating equals calibrated prior. At n=1 current component is opponent-adjusted ridge1, not raw margin. Tables report exact convex shares at 0/1/2/3/6/12 games.

C4/EB_features: minimize sum_team_rows(PF-mu-o_i-d_j-H*hx)^2 +4*sum_i((o_i-s*pre_off_i)^2+(d_i-s*pre_def_i)^2). This joint Gaussian working posterior has matrix weights depending on the already observed schedule. n/(n+4) and 4/(n+4) are conditional illustrations ONLY when opponents/intercept are known; they are not marginal weight claims. At no games globally, the centered calibrated prior is exact. At one game, solve the same coupled matrix; it propagates prior and opponent information. Exact prior contribution is full fitted power minus the solve with the prior RHS set to zero. Current contribution is that zero-prior solve; their sum is exact. Penalties and posterior variances are working observation-scale quantities, not validated probabilistic uncertainty.

Uncertainty adds zero-mean precision z=2*u/(sqrt(component_size)*(1+n_cross)) to C4, using only pre-cutoff graph evidence and prior working variance u. Conference adds earlier forward baseline preseason residual conference means, partially pooled with precision20, before the same update. Conference effects are weighted-centered across current FBS membership; coupled score information fades them. No G5/P4 indicator or hand-applied conference penalty enters. Model formulas are fixed before fitting; Conference must outperform both B and Uncertainty under the full advancement rule.

For every family publish P=O-D. Neutral margin(A,B)=P_A-P_B; home margin=P_home-P_away+HFA*(not neutral). One team has one rating at a cutoff regardless of upcoming opponent.

## Counterfactual and limitations

The prior-input-mean counterfactual replaces only prev_off and prev_def by zero (the FBS centered mean), preserving promotion state and all valid external features, then applies the same frozen prior model and current evidence. Report resulting preseason/current power; the difference is not a pure causal decomposition because standardization and coverage models are estimated representations.

Nested fitted coefficients and routing are in prior_coefficients.csv, nested_penalty_validation.csv and feature_coverage_routes.csv. Frozen calibration values and development dispositions are in candidate_ledger.csv; all scalar objective profiles and boundary diagnostics are exported. Handoff values for EB rows in the ledger are comparator diagnostics and are not applied by EB. This distinguishes a fitted but unused blend diagnostic from the actual EB precision4 update.
