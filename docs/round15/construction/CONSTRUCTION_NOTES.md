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

## Selected hyperparameters (by the frozen §6.1 procedure; one grid-edge selection, 2017 q; no fallbacks)

| Target | λ0 (C1) | ω (C2) | q (C3) | q_QB (C3) |
|---|---|---|---|---|
| 2017 | 3 | 0.50 | 2.0 (grid edge) | 4 |
| 2018 | 3 | 0.25 | 1.0 | 0 |
| 2019 | 4 | 0.25 | 0.5 | 0 |
| 2021 | 4 | 0.25 | 0.5 | 0 |
| 2022 (also used for 2023–2025) | 4 | 0.25 | 0.5 | 0 |

Other estimated values are in `c1_parameters.csv`, `c2_parameters.csv` and `c3_parameters.csv`.

## Undefined cases resolved with the nesting value

These arose while implementing, like §6.1 item 7. Items 1 and 2 affect only the **2016 inner season**, which is never
scored and is used only as tuning input. They are fixed and are not revisited after scoring.

1. **C1 turnover variance model for 2016** — *approved by the user 2026-09-25.* No earlier residual seasons exist (the first
   as-of prior is 2016's), so b = 0: constant precision λ0, the nesting value.
2. **C2 FCS prior precision for 2016** — *approved by the user 2026-09-25.* The FBS prior-error variance v̄_FBS comes from
   the same missing variance model, so λ_FCS = λ0 for 2016.
3. **C3 QB allowance, "once"** — see the conformance check below.
4. **C3 QB detection, tie for the season-to-date lead** — *awaiting confirmation.* See the conformance check below.

The 2017 C3 selection q = 2 at the top of the frozen grid was accepted by the user on 2026-09-25 as a disclosed grid-edge
selection; the grid is not extended. The two `test_g0.R` fixes (L6 syntax, L4 scope) were accepted on the same date.

## C3 QB-change conformance check (2026-09-25, before any scoring)

**Signed text (predeclaration v2 §5.4 item 2, unchanged from the original signed file):**

> **Detection:** a change is detected when a team's primary passer in its latest game (≥ 10 dropbacks) differs from its
> season-to-date primary passer. Detection uses play text only, from games before the cutoff.
> **Effect:** it adds q_QB to that team's **offense** state variance once, at the cutoff after the game where it was
> detected. Defense is unaffected.

The primary passer per team-game is "the passer with the most dropbacks, with ≥ 10 dropbacks required" (§4.2).

**Implemented rule.** A game is an event when its primary passer differs from the season-to-date primary (most
accumulated primary dropbacks in the team's earlier games that season). A run of consecutive detections of the same passer
counts once: after the first detection, later games by the same passer are repeats until another passer is primary.
Implementation: `passer ∉ season-to-date leaders AND passer ≠ previous game's primary`. Every event is a literal
detection. The only literal detections left out are repeats of the previous game's detection.

**Synthetic sequences** (`tests/round15/test_qb_events.R`, 30 dropbacks per game unless stated):

| Sequence | Events (game) | Literal detections | Every change of primary |
|---|---|---|---|
| A A B B | 3 | 3, 4 | 3 |
| A B A (A leads 40/20) | 2 | 2 | 2, 3 |
| A B A (B leads 40/20) | 2, 3 | 2, 3 | 2, 3 |
| A B C | 2, 3 | 2, 3 | 2, 3 |
| A B B A (B leads) | 2, 4 | 2, 3, 4 | 2, 4 |
| A B B A (A leads 60 vs 25+25) | 2 | 2, 3 | 2, 4 |
| A×5, B, B, A | 6 | 6, 7 | 6, 8 |
| A×5, B, A, B | 6, 8 | 6, 8 | 6, 7, 8 |

**Change back to a previous starter.** Under the signed text, a return to a passer who is still the season-to-date
primary is **not** a detected change, because that passer does not differ from the season-to-date primary (A×5, B, B, A:
no event at week 8). A return to a passer who is no longer the season-to-date leader is detected (A B B A with B leading:
event at week 4). The implementation follows the signed text here. An allowance at every change of primary, including
every return, would compare against the previous game's primary instead of the season-to-date primary. That would change
the signed detection rule, so it would need a dated amendment before scoring. It is not implemented.

**Ties (undefined case 4).** The signed text does not say what the season-to-date primary is when two passers are exactly
tied in accumulated dropbacks. The first build broke ties by the alphabetical order of player names, which is arbitrary.
Corrected rule: a passer tied for the season-to-date lead does not differ from it, so no detection. This resolves the
case toward the nesting value (no shock), as with items 1–2.

**Real-data counts (2016–2025 excl. 2020; inputs only, no outcomes read):**
- 15,690 team-games have a primary passer.
- 2,301 are changes of primary from the previous game.
- The corrected rule gives 1,786 events. All 1,786 are changes of primary.
- The other 515 changes are returns to the season-to-date primary or ties for the lead.
- Exactly one event differs from the first build: 2017, team 2084, game 400945007, a tie for the season-to-date lead.

Because 2017 is an inner season for later targets and is itself a target, C3 was rebuilt in full after the correction.
The selections and hashes above are from that rebuild. C1 and C2 are unaffected.

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

## Final construction state (frozen 2026-09-25, before any scoring)

- **G0a:** all three nesting reductions pass (C3 rebuilt after the tie correction: max |Δ| 6.4e-14 … 9.2e-14 vs C2).
- **G0b/G0c:** `tests/round15/test_g0.R` 17/17.
- **Other tests:** `tests/round15/test_qb_events.R` 13/13, `tests/round15/test_reconstruct.R` 14/14,
  `tests/forward/test_forward.R` 24/24.
- **Frozen, unscored predictions:** `c1_manifest.csv`, `c2_manifest.csv`, `c3_manifest.csv`.
  - C3 after the rebuild: predictions `94363c9f…d155`, tuning `65abb9ac…27a2`.
  - They replace the first build's `d50f4a28…cd54` / `09ad7c38…5df9`, which were never scored.
- **Freeze record:** `CONSTRUCTION_FREEZE.sha256` hashes the candidate code, build scripts, tests, manifests and these
  notes.

## Deviations

None from the signed specification. Undefined cases are resolved as listed above; item 4 awaits confirmation. All code,
hashes and tests are on branch `round15-power-rating`.
