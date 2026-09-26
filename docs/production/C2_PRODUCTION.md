# Production model: Current C2 (production tag `c2-production-v1`)

- **Promoted:** 2026-09-26, on your decision after Round 16 returned QUALIFIED (historical): PRODUCTION CANDIDATE.
- **Before promotion:** dependency audit in `C2_PROMOTION_DEPENDENCY_MAP.md`; rollback record in `rollback/`.

## 1. Identity

| | Former incumbent (benchmark) | Production model |
|---|---|---|
| Name / candidate id | EB_features v5.0.0 | Current C2 / `C2_current` |
| Frozen | 2026-09-09 | Research tag `c2-post-stage4-baseline` = `6a187ea`, unchanged |
| Code | `R/model/cfb_power_ratings_vCurrent.R` (MD5 `711d01aa…`) | `R/c2/c2_current.R` (MD5 `d5696a9e…`, sha256 `8b4d9d41…`) + frozen helpers `R/round15/{candidates,prep}`, `R/round15/cfbd_client.R`, `R/forward/vendor/round13_sr_stack.R` |
| Frozen inputs | `data/frozen/outputs/round4/*`, `cfb_data_v2/v3` | `data/frozen/c2/c2_season_inputs_2026.rds` (MD5 `7618cbdd…`), built once by the canonical code (Round 16 §9) |
| Home field | 3.06853968902663 | 3.06853968902663 |
| Probability / simulation SD | 15.787 (simulation) | 15.6500874177702 (Round 16 frozen σ, model C) |
| Non-FBS teams | Constant −25 in the simulation | C2's own Stage 3 ratings: in-solve, or first-game before a team's first game |
| Identity config | `config/production.R` (unchanged) | `config/production_model.R` |

**Naming.**
- No historical model was renamed.
- The research tags `c2-post-stage4-baseline` and `round16-*` are untouched.
- `c2-production-v1` is a separate production tag.

## 2. How production selects the model

Every production consumer asks `R/production/production_model.R` for ratings:
- `scripts/01_build_ratings.R`;
- `R/simulation/simulate_season.R`;
- through their outputs, the exporters and the site.

`production_model_id()` works as follows:
- It returns `C2_current` by default.
- `CFB_PRODUCTION_MODEL=EB_features` explicitly runs the former incumbent through the same pipeline.
- Any other value stops the run.

`production_build()` dispatches to the model:
- **C2:** the adapter `R/production/c2_production.R`, which verifies MD5s, assembles the season's games and play rows,
  calls `c2_predict_season()` unchanged, and returns the incumbent's ratings schema.
- **Incumbent:** `v5_build()`, unchanged.

Simulation parameters and non-FBS powers are keyed on the model that produced the ratings, so a ratings object never mixes
models. **There is no fallback.** A C2 failure stops the build: the frozen-input mismatch, a missing season, an empty pull,
a broken play pull and a missing non-FBS rating are each tested.

## 3. Weekly data (live, per run; nothing historical is rebuilt)

| Input | Source | Rule |
|---|---|---|
| FBS schedule and results | `read_schedule()` (unchanged) | |
| FCS-involved schedule | CFBD `/games classification=fcs`, regular + postseason (2 calls) | Round 15 P1 mapping; proven to reproduce the P1 pull for 2025 exactly |
| Play-by-play | `cfbfastR::cfbd_plays`, one call per week with a final FBS game before the cutoff | `r15_build_data`'s per-season block; proven to reproduce the frozen build's 2025 play rows exactly |
| Information cutoff | Monday 00:00 UTC | Final games with kickoff + 24 h before the cutoff (C2's own rule) |

**Fetch guard.** If more than 3 final FBS-vs-FBS games before the cutoff are missing from the play pull, the build stops.
Games that the frozen success-rate instrument excludes (about 4–6% historically) are normal and are only reported.

## 4. Validation (before cutover; `docs/production/validation/`)

| Area | Result |
|---|---|
| Frozen inputs and code | All MD5s match. The model code is byte-identical to `6a187ea`. |
| Historical reproduction | All 22 cutoffs of 2025 through the adapter vs canonical Current C2. Maximum difference: 1.6e-13 for predictions, 2.4e-13 for ratings of all entities, 6.4e-14 for group levels, 1.4e-13 for first-game ratings, 8.5e-14 for the FBS-vs-non-FBS rule (126 games). |
| 2026 overlap (cutoff 2026-09-21) | The frozen inputs equal the canonical recomputation. FBS power/off/def, levels and 58 week-4 predictions differ by exactly 0. All 71 week-4 spreads, FCS games included, equal the pre-promotion comparison up to its 0.1 rounding. |
| Schema | Tibble with the incumbent's 13 columns in the same order. The same 138 team IDs, names and conferences. Every FBS team is rated and centred. All 100 non-FBS opponents are rated; none is at −25. |
| Cutoffs and leakage | The training set is exactly the final games available before the cutoff. Injecting post-cutoff results and plays changes no rating (difference 0). An earlier cutoff uses only earlier games. |
| No fallback | 7 failure paths each stop the build. |
| Incumbent | The routed incumbent is `identical()` to `v5_build()`. It reproduces the committed week-1 snapshot, and the 2026-09-21 production snapshot, exactly. |
| End-to-end (live pulls, scratch dirs) | `verify_frozen_inputs` (29/29) passes. `run_weekly_pipeline` (C2 ratings, 200-season simulation, export) and the betting export pass. Week-03 archives were kept as published by the incumbent. |
| Simulation | Unplayed FBS-vs-non-FBS games: the simulated FBS win share is 0.9854, against 0.9854 expected from C2's ratings and 0.9234 at −25. The 12-team CFP and 2026 auto-bid assertions pass. |
| Site | 22/22 web tests on the C2 JSON; `tsc` and `vite build` succeed. |
| Test suites | All pass: `test_production_routing` (new), `test_reproduce_incumbent`, `test_public_export`, `test_betting_export`, `test_cfp_resume_ranking`, `test_evaluation_helpers`, `test_simulation_playoff_variance`, `tests/forward` (24), `tests/c2/run_all` (equivalence, regression, performance). |
| Forward plugins | Frozen R15 C2's forward call reproduces its own 808 predictions for 2025 (maximum difference 5.7e-14). The Current C2 plugin equals the production build. A full scratch dry run wrote all four models, and the manifest verified. |

## 5. Rollback (nothing to reconstruct)

The rollback point is tag **`production-incumbent-rollback`** = `e468b32`, the last incumbent production commit and
`origin/main` at promotion. The artifact hashes are in `rollback/incumbent_production_e468b32.sha256`. The local runtime
state was copied read-only to `output/rollback/incumbent_state_e468b32/` in the main checkout.

Ways to restore, from lightest to heaviest:
1. **One run on the incumbent:** set `CFB_PRODUCTION_MODEL=EB_features` for that run.
2. **Full restore:** `git revert` the promotion commits, or reset `main` to `production-incumbent-rollback`, then push.
   - This was verified: a clean checkout of the tag passes `verify_frozen_inputs` (19/19), `test_reproduce_incumbent`
     and `test_public_export`.

## 6. Cutover behaviour

- **When C2 goes live.** A push to `main` rebuilds the site from the committed JSON only; it does not run R. C2 output first
  appears at the next refresh run: the scheduled Monday 09:00 UTC run, or a manual `workflow_dispatch`.
- **Historical records are protected.** Week snapshots and `public/data/<season>/week-NN/*.json` archives published by
  another model are never overwritten. A same-model rerun still refreshes them.
- **Weekly change at cutover.** In the first C2 week, `weekly_change` is null, because the exporter never compares
  snapshots from different models.

## 7. Forward test (unchanged by promotion)

**What was added.** The forward tool gained two plugins: Current C2 and frozen R15 C2.

**What was not changed.**
- No rule, threshold, timing, guard, probability scale or comparison rule.
- The incumbent and K plugins.

**Activation.** The forward window is still not activated. Activation (`scripts/forward/install_launchd.sh <commit>`) needs
your separate approval, as Round 16 §9 and `docs/forward/FORWARD_SNAPSHOTS.md` §6 require.
