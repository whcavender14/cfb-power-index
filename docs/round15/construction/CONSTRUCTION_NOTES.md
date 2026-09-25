# Round 15 candidate construction and G0: notes

**Scope.** Candidates C1–C3 are built exactly as specified in predeclaration v3 (Amendment 02 revision 2; hashes in
`../predeclaration.sha256`). C1 and C2 are unchanged from v2 (`7e076b3c…4a7c`); only C3's QB-change detection changed. Their
development and 2023–2025 predictions are frozen and hashed (`c*_manifest.csv`).
- **Not done:** no development or conditional metric has been computed or read.
- **Inner-tuning objective values** are stored in the hashed `c*_tuning.rds` files and have not been printed or inspected.
- **Selected hyperparameters** are listed below.

## G0a: nesting reductions

| Check | Tolerance | Max |Δ| per season (2017, 2018, 2019, 2021, 2022) | Result |
|---|---|---|---|
| C1 in incumbent mode (incumbent prior, λ = 4, incumbent scale and HFA) vs incumbent replay | 1e-9 | 5.3e-14 … 5.7e-14 | PASS |
| C2 with ω = 0, no FCS teams, no fumble luck vs C1 | 1e-9 | 5.2e-14 … 5.7e-14 | PASS |
| C3 with q = q_QB = 0 vs C2 (post-Amendment 02 rebuild) | 1e-6 | 6.4e-14 … 9.2e-14 | PASS |

Grid values: q ∈ {0, 0.25, 0.5, 1, 2}; q_QB ∈ {0, 4, 16, 36} (κ units of prior precision, points²). §6.1 selection is
by-target inner walk-forward, pooled winner log-loss with σ profiled out, ties to the nesting value (0). 2017's q = 2
lands on the grid's upper edge — flagged in `c3_selection.csv` (`grid_edge = TRUE`) for transparency; it is still the
frozen §6.1 selection, not a fallback.

## Selected hyperparameters (by the frozen §6.1 procedure; one grid-edge selection, 2017 q; no fallbacks)

| Target | λ0 (C1) | ω (C2) | q (C3) | q_QB (C3) |
|---|---|---|---|---|
| 2017 | 3 | 0.50 | 2.0 (grid edge) | 4 |
| 2018 | 3 | 0.25 | 1.0 | 0 |
| 2019 | 4 | 0.25 | 0.5 | 0 |
| 2021 | 4 | 0.25 | 0.5 | 0 |
| 2022 (also used for 2023–2025) | 4 | 0.25 | 0.5 | 0 |

Other estimated values are in `c1_parameters.csv`, `c2_parameters.csv` and `c3_parameters.csv`.

The post-Amendment-02 C3 rebuild selected the same q and q_QB for every target as the pre-amendment build.

**C3 QB-change events** under Amendment 02 (`c3_qb_events_by_season.csv`):

| 2016 | 2017 | 2018 | 2019 | 2021 | 2022 | 2023 | 2024 | 2025 | Total |
|---|---|---|---|---|---|---|---|---|---|
| 179 | 202 | 216 | 217 | 301 | 328 | 266 | 244 | 323 | 2,276 |

## Undefined cases resolved with the nesting value

These arose while implementing, like §6.1 item 7. Items 1 and 2 affect only the **2016 inner season**, which is never
scored and is used only as tuning input. They are fixed and are not revisited after scoring.

1. **C1 turnover variance model for 2016** — *approved by the user 2026-09-25.* No earlier residual seasons exist (the first
   as-of prior is 2016's), so b = 0: constant precision λ0, the nesting value.
2. **C2 FCS prior precision for 2016** — *approved by the user 2026-09-25.* The FBS prior-error variance v̄_FBS comes from
   the same missing variance model, so λ_FCS = λ0 for 2016.
3. **C3 QB allowance, "once"** — superseded by Amendment 02 (core rule: an event is a change from the preceding
   qualifying game's primary passer; the same primary never re-triggers).
4. **C3 QB detection, tie for the season-to-date lead** — *approved by the user 2026-09-25*, then superseded by Amendment
   02. It changed exactly one event (2017, team 2084, game 400945007) in a build that was never scored.
5. **C3 ties within a game and games without a qualifying primary** — resolved by Amendment 02 A4 (co-primaries) and A5,
   *approved by the user 2026-09-25*. They were implemented before that confirmation, but before any scoring.

The 2017 C3 selection q = 2 at the top of the frozen grid was accepted by the user on 2026-09-25 as a disclosed grid-edge
selection; the grid is not extended. The two `test_g0.R` fixes (L6 syntax, L4 scope) were accepted on the same date.

## C3 QB-change detection: conformance check and Amendment 02 (2026-09-25, before any scoring)

1. **Conformance check.** The user asked for it before scoring.
   - The detector was run on synthetic sequences and counted on the 2016–2025 play-text inputs. No outcomes were read.
   - It matched the signed v2 text: a change was a difference from the season-to-date dropback leader.
   - Under that text, a return to a starter who still led the season was not a change: A ×5, B, B, A gave no event at the
     return to A.
   - Exact ties for the season-to-date lead were broken by player name. Correcting that changed one event and led to the
     rebuild at `afa860a` (tag `round15-construction-frozen`).
2. **Amendment 02** (`../AMENDMENT_02.md`, revision 2).
   - **Core rule.** An event is a change of primary passer from the team's preceding qualifying game, including a return
     to a previous starter.
   - **A4.** Co-primaries in tied games; a change needs disjoint primary sets.
   - **A5.** Games without a qualifying primary are skipped.
   - The q_QB grid, the §6.1 procedure and all other specification are unchanged.
3. **Event classifications, 2016–2025 excluding 2020** (`a02_qb_event_counts.csv`):
   - 2,276 events under Amendment 02, against 1,786 before;
   - 532 differ: 511 added, of which 510 are returns to the season's prior dropback leader, and 21 removed, all in tied
     games.
4. **Implementation.**
   - `r15_qb_primary()` (`data.R`) builds each team-game's primary passer set from play text, with ties kept as
     co-primaries.
   - In the 20,127 team-games without a tie, it matches the existing primary passer exactly.
   - `r15_qb_events()` (`c3.R`) applies the core rule, A4 and A5.
5. **Tests.**
   - `tests/round15/test_qb_events.R` covers the user's example sequences, ties in both name orders and skipped games.
   - `test_g0.R` L1 adds a leakage check: QB events before a mid-2019 cutoff are unchanged when later passers are
     scrambled.
6. **Rebuild.** C3 was rebuilt from scratch.
   - The pre-Amendment-02 outputs were never scored. They are archived in `output/dev/round15/cand/superseded_pre_A02/`
     (predictions `94363c9f…d155`, tuning `65abb9ac…27a2`).
   - The selections are unchanged.

## Implementation readings of the signed text (no new choice; recorded for transparency)

- **Prior regimes ("the incumbent's regime rule").**
  - Implemented as the incumbent's code does it: a team's regression uses its available predictors, fit on training rows
    that have all of them, with ≥ 80 rows and forward-chaining CV. Otherwise the team uses the incumbent's base prior.
  - **Consequence 1:** defensive continuity starts with 2016 stats, so defensive regimes are estimable only from the 2019
    target. For 2017 and 2018, 128/130 and 129/130 defensive priors use the base prior (`c1_prior_routes.csv`).
  - **Consequence 2:** 2016 (inner only) is almost entirely base prior, because two-back ratings start in 2015.
  - This mirrors the incumbent's own 2017–2018 behavior with vendor defensive returning production.
- **SR rows.** Each carries its own unpenalized intercept, so the mapping's α is absorbed and only β (scale) is used.
- **FCS priors.** They are in end-of-season points units; the scale a_X multiplies FBS priors only, as in the incumbent.
  v_FCS is the residual variance of the FCS persistence regression.
- **FCS-vs-FCS games** have no play-by-play (plays are pulled for FBS-involved games), so they carry no SR row and no
  fumble luck.
- **C3** is solved as the exact penalized equivalent of the Kalman filter: period-specific strengths, increments
  penalized by σ²_row/(q·Δweeks + allowance). Its q = 0 reduction is checked against C2 above.
- **Estimates used as fitted** (the signed rules forbid overriding them):
  - κ_fum = 1.99–3.25 points per unit of fumble luck, below the "about 3–6" plausibility band.
  - The defensive turnover slope b_def is negative in every season: more defensive turnover goes with *smaller* prior
    error variance.

## Final construction state (frozen 2026-09-25 after Amendment 02, before any scoring)

- **G0a:** all three nesting reductions pass. C3 was rebuilt under Amendment 02; max |Δ| vs C2 is 6.4e-14 … 9.2e-14.
- **G0b/G0c:** `tests/round15/test_g0.R` 18/18.
- **Other tests:** `tests/round15/test_qb_events.R` 13/13, `tests/round15/test_reconstruct.R` 14/14,
  `tests/forward/test_forward.R` 24/24.
- **Frozen, unscored predictions:** `c1_manifest.csv`, `c2_manifest.csv`, `c3_manifest.csv`.
  - C3 predictions `ac2a102e…3093`, tuning `2b9d5119…39fb`.
  - C1 and C2 are unchanged.
- **Freeze record:** `CONSTRUCTION_FREEZE_A02.sha256` hashes the candidate code, build scripts, tests, manifests, these
  notes and the frozen outputs.
  - Its own SHA-256 is recorded in `../predeclaration.sha256`.
  - The pre-amendment freeze record, `CONSTRUCTION_FREEZE.sha256` (`48f8bfe3…3085`), is kept unchanged.

## Deviations

None from the binding specification (v3). Undefined cases are resolved as listed above, and all are approved. All code,
hashes and tests are on branch `round15-power-rating`.
