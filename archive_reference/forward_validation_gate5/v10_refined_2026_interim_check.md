# v10 Refined: 2026 Interim Check (Non-Decisive Early Read)

**Superseded by `v10_refined_amendment_02_gate5.md` (signed 2026-09-22T14:31:18Z).** The 34-game read below used a tier map without a season index (6 of the 34 games have the 2026 Pac-12 misclassified as P4) and no games from it can enter Gate 5 (they all kicked off before the lock). The "re-check at n=100-150" cadence is replaced by the single 2028-02-01 look in the amendment. Kept here for history only.

**Status: NOT a Gate 5 verdict.** This is a labeled early read at n=34 P4-vs-G5 games, run in a parallel session on 2026-09-21/22. No promote/hold decision was made, and none should be drawn from this document alone. Gate 5 stays open until re-checked at a larger sample (see cadence below).

## What was run

- **2026 schedule:** refreshed live from the CFBD API, filtered to `season==2026`.
- **2026 incumbent predictions:** `outputs/round4/prospective/predictions_20260909T142134.csv` — the frozen `EB_features` candidate (recorded as `selected` in `outputs/round4/design_frozen.rds`), predicted 2026-09-09, genuinely pre-kickoff for all but the earliest completed games. Joined to the refreshed schedule on `game_id`.
- **v10_refined parameters:** frozen, unchanged from the earlier run — a = 2.356, b = 1.831 (0.65-shrunk, era-averaged fit). No re-fitting.
- **Sample:** 106 completed games matched to predictions; 34 of those are P4-vs-G5.

## Results

| Metric | Value |
|---|---|
| n (P4-vs-G5) | 34 |
| Incumbent bias | +5.64 ± 2.48 |
| v10_refined bias | +1.56 ± 2.48; 95% CI [−2.87, +6.32] |
| Gate 5 band | [−1.60, +1.14] |
| Point estimate vs. band | outside (above) |
| Paired Δ MAE (v10_refined − incumbent) | −0.416 (favors v10_refined) |
| Venue split | P4 home +1.27 (n=32); P4 away/neutral +6.22 (n=2) |
| Conference split | SEC −6.60 (n=9), Big Ten +5.23 (n=10), Big 12 +1.31 (n=7), ACC +5.84 (n=2), Pac-12 +6.57 (n=6) |
| Back-solved implied shrinkage (corrected formula) | 0.90 |

## Read

The 95% CI on v10_refined bias, [−2.87, +6.32], fully contains the pass band [−1.60, +1.14]. At n=34 the data cannot distinguish a Gate 5 pass from a fail — the point estimate landing outside the band is not evidence of failure by itself. The paired MAE is favorable (−0.416), which cuts against reading this as a bad sign. Venue and conference splits are each on samples of 2–10 games and are not a basis for any adjustment; they're recorded here for the record, not as findings.

## Verification item: HFA convention (resolved)

**Resolved via code trace, not data spot-check.** `pred_margin` in the prospective predictions file is confirmed to be the with-HFA margin, applied exactly once, matching the `predicted_margin_with_hfa` convention used elsewhere.

Chain: `outputs/round4/MODEL_SPEC.md:31` defines `home_margin = P_home − P_away + HFA*(not neutral)`. `cfb_vCurrent_operations.R:82` builds the archive via `pred_margin = v4_predict(r, home_id, away_id, neutral)`. `cfb_power_ratings_vCurrent.R:1380` defines `v4_predict <- function(r,h,a,neutral) r$power_rating[home]-r$power_rating[away]+attr(r,'hfa')*!neutral` — a single HFA application, no double-counting and no missing term.

This was worth checking (an HFA error would have concentrated in the venue split, which is P4-home-heavy at 32 of 34 games), but it is not the explanation for the observed +1.56 bias.

Note: the empirical spot-check originally proposed (comparing neutral-site vs. heavy-favorite games) would not have been conclusive anyway — only 7 of 710 games in the prospective file are neutral-site, too few to isolate the HFA term empirically. The code trace is the more reliable check here and is treated as settling the question.

## What was explicitly NOT done

- The predeclaration was not modified.
- The 0.65 shrinkage factor was not changed.
- No promote/hold decision was made.

## Re-check cadence

Re-run Gate 5 once completed P4-vs-G5 games reach roughly **n = 100–150** — about 3+ more weeks of the season — rather than weekly. At n=34 the CI is wide enough to contain the entire pass band; weekly re-checks at this sample size would mostly produce noise, not signal, and risk motivating premature adjustment.
