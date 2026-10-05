# CFPi+ Player Ratings v1: predeclaration (2026-10-05)

**Modelled, not official.** CFPi+ Player Ratings are a CFPi+ derived metric. They are not a CollegeFootballData, NCAA, 247Sports, Madden or EA Sports rating, and have no affiliation with any of them. They are display only and never feed the CFPi+ team ratings, simulations or predictions.

This document is written and frozen **before** any predictive validation metric was computed. The specification is `R/ratings/ratings_spec.R`; the construction is `R/ratings/ratings_core.R`; the validation is `R/ratings/ratings_eval.R`; the OVR scale is `R/ratings/ratings_knots.rds`. Their SHA-256 hashes are in `docs/website/PLAYER_RATINGS_FREEZE.json`, taken before the first validation run. If validation fails, the specification is not adjusted to pass: any change is a new specification (v2) with its own predeclaration and a fresh validation. Only coverage counts and the pooled development distribution (no outcomes) were looked at before the freeze.

## 1. What a rating is

One overall (OVR) per rostered FBS player in a rated position group, 30-99, with an uncertainty band and flags. Groups: QB, RB, WR, TE, OL, DL, LB, DB, K, P. Long snappers and "ATH" are not rated.

| OVR | CFPi+ interpretation (not an official classification) |
|---|---|
| 99 | Generational / national superstar |
| 90-98 | Elite national player |
| 80-89 | High-end P4 starter |
| 70-79 | Solid FBS starter |
| 60-69 | Average FBS contributor |
| 50-59 | Replacement / depth player |
| 40-49 | Low-end / developmental player |
| 30-39 | Bottom of the FBS player pool |

## 2. Construction (through season s; reads seasons s and s-1 only)

1. **Evidence per player-season.** For each position group, features are z-scored within group and season against players with at least `nmin` opportunities, capped at +-3, then combined with fixed weights (renormalized over the features the player has):
   - QB: PPA per play 0.45, passing success rate 0.20, yards per attempt 0.20, (TD - INT) per attempt 0.15.
   - RB: rushing PPA 0.35, rushing success rate 0.20, yards per carry 0.30, rush usage share 0.15.
   - WR, TE: receiving PPA 0.40, yards per catch 0.30, pass usage share 0.30.
   - DL: sacks 0.30, TFL 0.30, QB hurries 0.20, tackles 0.20. LB: tackles 0.30, TFL 0.25, sacks 0.15, PD 0.10, INT 0.10, hurries 0.10. DB: tackles 0.25, PD 0.30, INT 0.25, TFL 0.20. All per 12 team games. CFBD publishes no player PPA for defenders and no snap counts.
   - K: field-goal rate (FGM + 3) / (FGA + 4) 0.70, longest 0.30. P: average 0.60, inside-20 rate 0.25, touchback rate -0.15.
   - Opportunities n: pass attempts (QB), carries (RB), catches (WR, TE), defensive actions = tackles + TFL + sacks + PD + INT (defense), FGA (K), punts (P). Reference minimums `nmin`: 30, 20, 8, 8, 10, 10, 10, 5, 10.
2. **Two seasons.** n_eff = n(s) + 0.5 * n(s-1); evidence is the n-weighted average of the two seasons' evidence.
3. **Shrinkage.** Reliability r = n_eff / (n_eff + k), k = 100 (QB), 60 (RB), 20 (WR, TE), 25 (DL, LB, DB), 12 (K), 20 (P). Prior mean = rho * Rz - 0.5, where Rz is the standardized 247Sports Composite recruit rating (mean 0.8248, SD 0.0533 from the 2018-2020 classes; unrated or unrecruited players Rz = -1) and rho = 0.25 (0.10 K and P). The 0.5 reflects that a rostered player is on average below the qualified players the z-scores are measured against. Posterior mean mu = r * evidence + (1 - r) * prior mean. Posterior SD (z units) = 0.9 * sqrt(1 - r). Players with no recorded production are rated from the prior alone.
4. **Offensive line (Estimated).** CFBD has no individual blocking, snap or pressure data. mu = 0.15 * unit_z + 0.85 * (0.30 * Rz + 0.25 * size_z + 0.10 * class_z) - 0.5, where unit_z is the team's mean of z(-sack rate allowed) and z(yards per carry) among FBS teams, size_z is recruit weight (mean 287 lb, SD 24.5) and class_z is class year. Always flagged Estimated and Provisional.
5. **Flags.** Provisional: r < 0.5 (little current evidence, so the prior dominates). Estimated: OL, K, P (a narrower evidence base).
6. **OVR scale.** A fixed monotone cubic map (Hyman) from mu to 30-99 through knots at the target cumulative probabilities (below), calibrated once on the 2021 and 2022 rosters and then frozen (`ratings_knots.rds`). Later seasons use the same knots; their distributions are whatever the model produces. This is a fixed transform, not a per-season percentile ranking, so ratings are comparable across seasons and cannot be bunched at 70, 80, 90 or 95 by construction (the map is smooth between knots).

Target distribution (calibration target, not a quota): 95-99 1.2%, 90-94 2.6%, 85-89 5.4%, 80-84 11.1%, 75-79 15.9%, 70-74 21.7%, 65-69 21.5%, 60-64 17.5%, below 60 3.1%; mean about 70, SD about 10.

Known property, stated before validation: most rostered players have little or no recorded production (r is small), so their mu is mostly the recruit prior. A large share of ratings below about 70 therefore reflect recruiting and role, not performance, and differences among them are small in z units. The page will say so.

## 3. Validation design (cutoff-safe)

Rating through season a predicts season b > a. Development pairs (a, b): (2021, 2022), (2022, 2023). **Holdout pairs: (2023, 2024), (2024, 2025). The holdout is run once, after the development run, with frozen code.** Draft: rating through season s vs being drafted in the s+1 draft (JR/SR at s); development s = 2021, 2022; holdout s = 2023, 2024, 2025. All data are completed seasons pulled from CFBD after the fact, and every input to a rating through a comes from seasons <= a (rosters, stats, PPA, usage, success rates, team stats and recruiting classes up to a). CFBD's season PPA is computed with its current model, a known and unavoidable look-ahead in the PPA definition, not in the data selection. Leakage pitfall checked: the CSV cutoff-to-numeric issue does not arise (no CSV round-trips; all inputs are RDS).

Comparator: recruiting alone, rho * Rz (monotone in the 247Sports rating; unrated players tie at the bottom).

**Outcomes.**
1. Next-season production Y in season b, for QB, RB, WR, TE, DL, LB, DB. Offense: PPA per play (QB all plays, RB rushing, WR and TE receiving), among players with at least 100 attempts (QB), 40 carries (RB), 15 catches (WR, TE). Defense: the season-b evidence composite, among players with at least 15 defensive actions. Only players who played in both seasons and stayed in the group are included, so the test is about retained, playing players (a stated limitation; early departures to the NFL are excluded).
2. Draft: drafted in the following NFL draft (CFBD draft picks, joined by athlete id), among JR and SR, all groups.

**Statistics.** Y and both predictors are replaced by within-group, within-pair normal scores. Production: delta_corr = corr(rating, Y) - corr(recruiting, Y), pooled over the seven groups and pairs. Draft: delta_AUC = AUC(rating) - AUC(recruiting), AUC pooled within group-season (concordance of drafted vs not). 95% intervals from a cluster bootstrap over athletes, 2,000 replicates, seed 20261005.

## 4. Gate (all must hold on the holdout; any failure stops the work for the user's decision)

- **G1** pooled delta_corr >= 0.03 and its lower 95% bound > 0.
- **G2** delta_corr > 0 in at least 5 of 7 position groups.
- **G3** delta_AUC (draft) >= 0.02 and its lower 95% bound > 0.
- **G4** (positional inflation or compression) among players with r >= 0.5 in the non-Estimated groups, each group's mean OVR within 4 points of the pooled mean of those players. Reported with every group's n, mean, SD and share at 90+ and 80+.

Also reported (not gated): the full distribution (mean, median, SD, min, max, percentiles, share at 95+/90+/85+/80+/75+/70+, the nine bands against the target), per-group distributions, counts and shares of Provisional and Estimated, ceiling and floor effects.

## 5. Not allowed

No change to the specification after seeing validation results, and no tuning to improve the histogram. A failed gate is reported and the work stops. The ratings UI is not built until the gate passes and the user approves.
