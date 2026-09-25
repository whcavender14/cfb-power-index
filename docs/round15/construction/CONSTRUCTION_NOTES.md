# Round 15 candidate construction and G0: notes

**Scope.** Candidates C1–C3 are built exactly as specified in predeclaration v2 (SHA-256 `7e076b3c…4a7c`). Their
development and 2023–2025 predictions are frozen and hashed (`c*_manifest.csv`).
- **Not done:** no development or conditional metric has been computed or read.
- **Inner-tuning objective values** are stored in the hashed `c*_tuning.rds` files and have not been printed or inspected.
- **Selected hyperparameters** are listed below.

## G0a: nesting reductions

| Check | Tolerance | Max |Δ| per season (2017, 2018, 2019, 2021, 2022) | Result |
|---|---|---|---|
| C1 in incumbent mode (incumbent prior, λ = 4, incumbent scale and HFA) vs incumbent replay | 1e-9 | 5.3e-14 … 5.7e-14 | PASS |
| C2 with ω = 0, no FCS teams, no fumble luck vs C1 | 1e-9 | 5.2e-14 … 5.7e-14 | PASS |
| C3 with q = q_QB = 0 vs C2 | 1e-6 | 6.4e-14 … 9.2e-14 | PASS |

Grid values: q ∈ {0, 0.25, 0.5, 1, 2}; q_QB ∈ {0, 4, 16, 36} (κ units of prior precision, points²). §6.1 selection is
by-target inner walk-forward, pooled winner log-loss with σ profiled out, ties to the nesting value (0). 2017's q = 2
lands on the grid's upper edge — flagged in `c3_selection.csv` (`grid_edge = TRUE`) for transparency; it is still the
frozen §6.1 selection, not a fallback.

## Selected hyperparameters (by the frozen §6.1 procedure; no grid-edge selections, no fallbacks)

| Target | λ0 (C1) | ω (C2) | q (C3) | q_QB (C3) |
|---|---|---|---|---|
| 2017 | 3 | 0.50 | 2.0 (grid edge) | 4 |
| 2018 | 3 | 0.25 | 1.0 | 0 |
| 2019 | 4 | 0.25 | 0.5 | 0 |
| 2021 | 4 | 0.25 | 0.5 | 0 |
| 2022 (also used for 2023–2025) | 4 | 0.25 | 0.5 | 0 |

Other estimated values are in `c1_parameters.csv`, `c2_parameters.csv` and `c3_parameters.csv`.

## Items for your confirmation: undefined cases resolved with the nesting value

These arose while implementing, like §6.1 item 7. Each affects only the **2016 inner season**, which is never scored and
is used only as tuning input.

1. **C1 turnover variance model for 2016.** No earlier residual seasons exist (the first as-of prior is 2016's), so b = 0:
   constant precision λ0, the nesting value.
2. **C2 FCS prior precision for 2016.** The FBS prior-error variance v̄_FBS comes from the same missing variance model,
   so λ_FCS = λ0 for 2016.
3. **C3 "once" rule for the QB allowance.** An event is recorded when the latest primary passer (≥ 10 dropbacks) differs
   from **both** the season-to-date primary **and** the previous game's primary. This gives one allowance per change of
   starter; the literal text would re-trigger it every week until the new starter's cumulative dropbacks overtook the old one.

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

## Deviations

None from the signed specification. All code, hashes and tests are on branch `round15-power-rating`.
