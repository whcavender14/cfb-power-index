# CFB Power Rating Model — Project Context and Round History

## Purpose and authority

This document is the durable project-level orientation for future work.  It records the
historical development decisions supplied on 2026-09-22 and the Round 13 operating brief.
It is context, not a substitute for a round's own predeclaration, code, tests, or report.
Where an older historical report conflicts with a later reconciliation, the later
reconciliation in this document controls.

## Production baseline

The frozen production incumbent is **v5_EB_features** (Round 4).  It jointly solves
offensive and defensive team ratings with empirical-Bayes ridge shrinkage toward a
feature-informed preseason prior.  Its source of truth is
`archive/v5-round4/code/cfb_power_ratings_v5.R`; later rounds must wrap/source it,
not duplicate it.  The expected home margin is the double difference of offense and
defense ratings plus home-field advantage and any explicitly declared adjustment.

Round 4 advanced v5 on a 0.317-point development MAE improvement and a 0.312-point
conditional improvement over the Round 3 incumbent.  Talent, returning production,
and coaching continuity are incorporated with historically appropriate provenance.
The market gap remained about 0.5 MAE points, so a promising diagnostic alone is not
grounds for promotion.

## Non-negotiable governance

1. Draft a new round's predeclaration and obtain explicit user sign-off before writing
   model code or examining real-outcome evaluation results.
2. Hash the signed predeclaration and all declared configuration/tier-map inputs into
   `predeclaration.sha256` before any fit, grid search, or evaluation.  Forward and
   reporting scripts must verify the hash.
3. Follow the declared gate tree literally.  Stop at the first failure.  Do not compute,
   read, or report downstream conditional gates after a prior failure.
4. Do not retune grids, thresholds, or methods after a failing result.  A new idea
   requires a new predeclared round.
5. Disclose every grid-edge selection; do not extend a grid unless its predeclared rule
   says to do so.
6. Treat an execution error or failed assertion as a Gate 0 integrity issue.  Fix the
   root cause and restart the prescribed run; never patch around it for a result.
7. Preserve historical feature provenance.  Unknown/missing historical fields remain
   missing rather than being zero-filled.

## Metric conventions

P4-versus-G5 directional bias is always P4-oriented:

```
bias = mean((actual_margin - pred_margin) * s)
s = +1  P4 home, G5 away
    -1  G5 home, P4 away
     0  same-tier or Other matchup
```

It is not a home-oriented residual mean.  Any tier-term implementation must verify its
design-matrix identity with a unit test.  For a P4/G5 two-parameter term, the resulting
home-margin effect must equal `s * (gamma0 + gamma1 * p4home)`.

For carried cross-season priors, the prior mean for season T is the final snapshot from
the latest included prior season (with 2020 excluded), rather than zero.  This matters
because Week 1 has no current-season cross-tier evidence; a zero prior would leave those
predictions identical to the incumbent.

## Round decision record

| Round | Candidate / subject | Outcome and lasting lesson |
|---|---|---|
| 3 | v4 score-only successor | Conditional, modest improvement. Early-season compression and conference residuals persisted; motivated external features. |
| 4 | v5 `EB_features` | **Promoted and frozen incumbent.** Feature-informed EB ridge improved MAE materially and robustly. |
| 5 | v6 position production, QB, efficiency, multi-year priors | Exploratory only; no standard completed selection. Multi-year history was interesting but not locked early enough. |
| 6 | Conference/tier hierarchy | Not promoted. Tier/conference/team structure reduced cross-tier bias but MAE gain (~0.03) was underpowered. |
| 7 | PBP efficiency replacement | Not promoted. Efficiency-only ratings were under-dispersed and worse than score-margin updates; data-quality defects were documented and repaired. |
| 8 | Dispersion calibration, stronger EP, fumbles | Not promoted. Forced variance matching amplified a noisy (~0.60-correlation) signal; it proved the Round 7 compression was useful shrinkage, not a repair target. |
| 9 | Efficiency ensemble | Not promoted. Predeclared zeroing set efficiency weight to zero: incremental information beyond the incumbent was negligible. |
| 10 | Cross-tier correction / talent gate | Not promoted. Development correction did not generalize; talent reapplication harmed early-season conditional performance. |
| 10 refined | EB shrinkage refinement | Forward candidate, locked under Amendment 2 on 2026-09-22; no verdict yet. |
| 11 | Tier random effects in joint solve | Archived not promoted, but the original reported bias gate used the wrong home-oriented metric. Correct P4-oriented reconciliation found lambda=1 reduced bias by 2.63 points in inner 2018–19 and 3.24 in full development. Do not reopen without explicit user direction. |
| 12 | P4/G5 gamma shift with carried prior | Archived not promoted at Gate 2. Gate 0 and arm rule passed; development MAE delta was -0.0644, but its 95% CI [-0.1745, +0.0234] failed the required upper bound <= 0. Later gates were not evaluated. |

## Established findings and constraints

- Play-by-play efficiency has repeatedly failed as a replacement or incremental ensemble
  feature (Rounds 7–10).  Do not revive it casually as an undifferentiated efficiency
  proposal.
- Naive variance matching/dispersion rescaling is ruled out: it amplifies noise when
  prediction correlation is modest.
- Cross-tier bias is real and directionally important, but simple static corrections can
  overfit.  Hierarchical and tier effects have some genuine mechanism but have not earned
  production promotion.
- The earlier Round 11 decision must remain archived unless the user explicitly chooses
  to reopen it under the corrected oriented metric.
- Round 12 shows that substantial directional-bias removal does not itself guarantee a
  meaningful MAE improvement because game-level residual variance remains large.
- The historic market advantage likely reflects information diversity unavailable to this
  single-model architecture; it is a benchmark, not a license for post-hoc tuning.

## Current forward work: v10 refined Gate 5

`v10_refined` is locked and under forward evaluation.  Amendment 2 is locked at
`2026-09-22T14:31:18Z`; it uses a season-indexed tier map (Pac-12 is P4 through 2025 and
G5 from 2026), one rule `abs(bias(v10_refined)) < abs(bias(incumbent))`, and pools
post-lock 2026 games with all 2027.  The floor is n >= 60 and there is one look on or
after 2028-02-01.  Do not alter this evaluation protocol.

Prospective incumbent predictions are write-once, MD5-verified snapshots under
`outputs/round4/prospective/`; they are the evidence source for Gate 5.  Before relying
on a snapshot, confirm it was created pre-kickoff for each relevant game.  Any live
refresh/archive action is operational and requires an explicit request; do not assume it
has happened from this document alone.

## Round 13 starting point

Round 13 has no model code or predeclaration at the time this document was added.  The
only proposed next step is a **report-only, prototype-first** tempo normalization probe,
scored on 2023–2025, to test whether that feature class is worth a later predeclared
round.  Possible hypotheses include tempo normalization, recursive strength of schedule,
and game-script/possession weighting.  This is not authorization to fit a new candidate,
select hyperparameters, or draft an outcome-informed predeclaration without user
direction.

## Repository and worktree hygiene

Use an isolated worktree for round work.  Do not alter or attempt recovery of unrelated
changes in another checkout.  Avoid bare `git stash` operations because stashes are shared
across worktrees.  Generated outputs and artifacts are generally gitignored; keep the
tracked code, predeclarations, hashes, tests, and reports as the durable audit trail.
