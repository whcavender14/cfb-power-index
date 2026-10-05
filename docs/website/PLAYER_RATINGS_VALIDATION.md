# CFPi+ Player Ratings v1: validation result (2026-10-05)

**Modelled, not official.** Predeclaration: `PLAYER_RATINGS_PREDECLARATION.md`; freeze hashes: `PLAYER_RATINGS_FREEZE.json` (verified unchanged before the holdout run). Code: `R/ratings/`, `scripts/ratings/02_validate.R`. The holdout was run once.

## Result: all four predeclared gates pass on the holdout. The ratings UI is NOT built; it awaits review.

| Gate | Holdout result | Threshold |
|---|---|---|
| G1 pooled next-season production, delta corr (rating - recruiting) | +0.251 (95% CI 0.223 to 0.278); rating 0.283 vs recruiting 0.032, n = 6,330 player-pairs | >= 0.03, lower bound > 0 |
| G2 groups with positive delta | 7 of 7 (QB +0.351, RB +0.134, WR +0.136, TE +0.037 [CI -0.085 to 0.161], DL +0.306, LB +0.287, DB +0.289) | >= 5 of 7 |
| G3 draft, delta AUC | +0.173 (CI 0.152 to 0.195); rating 0.873 vs recruiting 0.700, 726 drafted of 35,747 JR/SR | >= 0.02, lower bound > 0 |
| G4 positional inflation | evidence-based players (r >= 0.5): group means within -1.3 to +0.6 of the pooled 81.9 | within 4 points |

Development pairs gave the same picture (pooled +0.285; draft +0.267), so the holdout is not a lucky draw.

## Distribution (rating through 2025, 2025 FBS rosters, n = 15,465; frozen scale calibrated on 2021-22)

Mean 73.8, median 73.8, SD 8.8, min 35, max 99. Percentiles: 1% 51.5, 5% 62.2, 10% 64.6, 25% 65.8, 75% 79.6, 90% 85.0, 99% 95.8. Share at 95+/90+/85+/80+/75+/70+: 1.2 / 4.0 / 9.9 / 23.9 / 44.3 / 67.0 %. Bands vs target: 95-99 1.2 (1.2), 90-94 2.8 (2.6), 85-89 5.9 (5.4), 80-84 14.0 (11.1), 75-79 20.4 (15.9), 70-74 22.6 (21.7), 65-69 22.1 (21.5), 60-64 8.2 (17.5), <60 2.7 (3.1). The model runs about 4 points above the target mean and is bunched at 65-66 (the 25th percentile is 65.8; the 60-64 band has less than half its target).

By group (n, mean, SD, 90+%, 80+%): DB 2,922, 74.4, 8.6, 5.1, 25.3; OL 2,675, 73.8, 9.1, 1.6, 26.1; DL 2,504, 74.1, 8.5, 5.4, 21.4; WR 2,085, 73.3, 8.6, 3.0, 23.1; LB 1,789, 74.0, 9.2, 7.4, 24.3; RB 1,090, 73.9, 9.3, 3.3, 27.8; TE 998, 72.6, 7.6, 1.3, 16.4; QB 714, 74.3, 9.7, 5.5, 26.6; K 415, 72.5, 8.7; P 273, 74.3, 8.7. TE is compressed (SD 7.6, 1.3% at 90+); OL has the fewest 90+ (1.6%). No group is inflated.

Provisional: 11,755 (76.0%). Estimated (OL, K, P): 3,363 (21.7%). Ceiling: 1.2% at 95+, max 99. Floor: min 35.

## Caveats the review should weigh

- **The recruiting comparator is weak among players who play.** Within qualified players, recruit rating correlates ~0.03 with next-season production. The gain is large partly because it is easy to beat. Most of the production gain for defense is persistence of the same per-game composite from one season to the next; offense uses next-season PPA, which is also an input (different season).
- **Draft:** both predictors rank within position group; the rating carries last season's production and class year, which stars do not. The comparison says the rating contains information about draft outcomes beyond recruiting; it is not a draft forecast.
- **Survivorship:** production outcomes include only players who played in both seasons.
- **TE is the weak spot:** delta +0.04, interval crosses zero.
- **76% of ratings are Provisional** (prior-dominated). Below about 70, ratings mostly reflect recruiting and role, and differences are small in z units (the dense bulk is mapped over 60-70). The 60-64 band is under-populated and the mean is 3.8 above target because 2025 differs from the 2021-22 calibration.
- **OL, K, P cannot be validated on production** (OL has no individual production data); OL enters the draft test through its prior and unit adjustment only.
- Defenders: no PPA, no snaps.
- CFBD season PPA uses CFBD's current model (a look-ahead in the definition, not in data selection).

## Calls

30 CFBD calls (one-time, cached in `data/reference/player_cache/hist_*`): player stats, PPA, usage and success 2021-2025 (20), draft 2022-2026 (5), team stats 2021-2025 (5). A weekly run would add none for ratings through completed seasons; the current season uses the already-pulled stats, PPA, usage and success (no new calls).
