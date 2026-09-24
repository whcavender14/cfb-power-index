# Round 12 Report: P4/G5 tier term inside the incumbent ridge solve

**Generated 2026-09-22 15:13:06 UTC by `report_round12.R`.** Predeclaration: `ROUND12_PREDECLARATION.md` (hash verified). Freeze manifest verified (22 files).

## Decision

**Gate 1 or 2 FAIL -> NOT PROMOTED (conditional not evaluated)**

## Disclosure: Step 5 was run twice

Run 1 (2026-09-22) computed every paired bootstrap with a defective block key. The prediction files store `cutoff` as text; `v12_boot` converted it with `as.numeric()`, which returned NA, so all blocks collapsed to their season (3 blocks for the gated development series instead of season x week). Run 1 reported Gate 2 as **FAIL**, with upper bound +0.0149 (interval [-0.1231, +0.0149]) and decision "NOT PROMOTED (conditional not evaluated)". Its outputs are kept unchanged in `outputs/round12/superseded_run1/`.

The fix keys blocks on the text form of the cutoff and makes incomplete keys an error. It was made after run 1 had been read. It restores the bootstrap B6 declares (season x week blocks, 10,000 reps, seed 7007) and changes no threshold, grid, tier map, lambda_gamma, selection or prediction: the re-run Step 4 outputs are byte-identical to run 1 (file-by-file sha256 comparison: `outputs/round12/run1_vs_run2_manifest.csv`). The run-1 upper bound, +0.0149, is exactly the 2019 season mean, which is what a 3-block season bootstrap produces. Regression tests were added to `test_v12.R`. Both results are reported; the one computed to the predeclared specification is the one below.

## Gates (B7, evaluated along the B9 tree)

| Gate | Split | Metric | Value | Threshold | Result |
|---|---|---|---|---|---|
| 0 | all | integrity | tests PASS; max |off - incumbent| 0.0e+00; adversarial 5/5 identical; tier_map hash ok | all hold | **PASS** |
| arm | dev inner (lock) | selected lambda_gamma strictly beats off on inner MAE | lock lambda_gamma 30; inner MAE 12.8879 vs off 12.9887 | strict win | **PASS** |
| 1 | dev 2019,2021,2022 | paired delta MAE (v12 - incumbent) | -0.0644 | <= -0.055 | **PASS** |
| 2 | dev 2019,2021,2022 | 95% upper bound, season x week blocks, 10,000 reps, seed 7007 | -0.0644 [-0.1745, +0.0234]; 64 blocks | <= 0 | **FAIL** |

Gates 3 and 4 were **not evaluated**: the tree stops before the conditional split (B9). No conditional result was computed or read.

## Selection (B4)

| Target | Inner seasons | Selected lambda_gamma | Candidate | Candidate MAE | Off MAE | Arm | Lower-edge hit (B4) |
|---|---|---|---|---|---|---|---|
| 2019 | 2018 | 10 | 10 | 12.9770 | 13.1942 | on | no |
| 2021 | 2018,2019 | 30 | 30 | 12.8182 | 12.9156 | on | no |
| 2022 | 2018,2019,2021 | 30 | 30 | 12.9871 | 13.0804 | on | no |
| lock | 2018,2019,2021,2022 | 30 | 30 | 12.8879 | 12.9887 | on | no |

Grid edges: 2019 = interior; 2021 = UPPER edge; 2022 = UPPER edge; lock = UPPER edge. B4 names only the smallest value as a grid-edge hit; an upper-edge hit (the largest value, 30, strongest pull toward the carried prior) is disclosed here on the same terms. The grid is not extended.

## Development, report only

| Season | n | lambda_gamma | Paired Δ MAE | P4-vs-G5 n | Incumbent bias | v12 bias |
|---|---|---|---|---|---|---|
| 2019 | 774 | 10 | +0.0149 | 99 | 3.62 | 0.02 |
| 2021 | 770 | 30 | -0.0851 | 83 | 7.34 | 2.79 |
| 2022 | 776 | 30 | -0.1231 | 86 | 6.25 | -0.25 |

| Era | Incumbent bias | v12 bias (SE) | v12 zero-prior | Round 11 λ=1 |
|---|---|---|---|---|
| 2018-19 (2018 in-sample) | 4.87 | 0.31 (1.21) | 3.03 | 2.25 |
| 2021-22 | 6.79 | 1.25 (1.22) | 4.35 | 2.83 |
| 2019, 2021, 2022 (scored) | 5.62 | 0.79 (1.00) | 3.47 | 2.44 |

| Comparison (paired Δ MAE vs its own incumbent; season×week blocks, 10,000 reps, seed 7007) | Estimate | 95% CI |
|---|---|---|
| v12, dev 2019/21/22 (gated series) | -0.0644 | [-0.1745, +0.0234] |
| v12, full four seasons (2018 at the lock, in-sample) | -0.0979 | [-0.1916, -0.0159] |
| v12 zero-prior ablation, dev 2019/21/22 | -0.0230 | [-0.0661, +0.0143] |
| Round 11 λ=1, dev 2019/21/22 | -0.0179 | [-0.0896, +0.0483] |
| v10_refined, dev 2019/21/22 (vs Round 10 incumbent; in-sample correction) | -0.0890 | [-0.1654, -0.0219] |

v10_refined P4-vs-G5 bias on the same seasons: 2.32 (Round 10 incumbent 6.01).

## γ̂ by season (mean over weekly snapshots; full weekly table in `gamma_by_week.csv`)

| Season | μ0 (carried) | μ1 (carried) | mean γ̂0 | mean γ̂1 |
|---|---|---|---|---|
| 2019 | 4.27 | -0.28 | 4.09 | 0.47 |
| 2021 | 2.92 | 0.32 | 4.89 | 1.43 |
| 2022 | 4.85 | 2.11 | 5.29 | 1.73 |

## Team ratings at the end of 2025 (report only; not production)

Final-snapshot fit on all 2025 games under the locked configuration (λ_γ = 30, parameters fit before 2023). v12 separates the P4/G5 shift from team power, so teams are ranked by *tier-adjusted* power: power ± γ̂0/2 for P4/G5 teams (γ̂0 = 3.71, γ̂1 = 1.39 at the end of 2025). Independents get no adjustment, so their rank relative to P4 teams is understated by up to γ̂0/2. Full table: `ratings_end2025.csv`.

| v12 rank | Team | Conf | Tier | v12 tier-adjusted | v12 power | Incumbent power | Incumbent rank |
|---|---|---|---|---|---|---|---|
| 1 | Indiana | Big Ten | P4 | 32.9 | 31.1 | 32.2 | 1 |
| 2 | Ohio State | Big Ten | P4 | 29.9 | 28.0 | 29.0 | 2 |
| 3 | Notre Dame | FBS Independents | Other | 27.7 | 27.7 | 28.1 | 3 |
| 4 | Oregon | Big Ten | P4 | 26.8 | 24.9 | 25.9 | 4 |
| 5 | Miami | ACC | P4 | 24.8 | 23.0 | 23.9 | 5 |
| 6 | Texas Tech | Big 12 | P4 | 24.4 | 22.5 | 23.3 | 6 |
| 7 | Georgia | SEC | P4 | 23.8 | 21.9 | 23.2 | 7 |
| 8 | Alabama | SEC | P4 | 22.2 | 20.3 | 21.4 | 8 |
| 9 | Texas A&M | SEC | P4 | 20.9 | 19.1 | 20.2 | 10 |
| 10 | Ole Miss | SEC | P4 | 20.8 | 18.9 | 20.3 | 9 |
| 11 | Utah | Big 12 | P4 | 19.6 | 17.7 | 18.4 | 12 |
| 12 | Texas | SEC | P4 | 19.4 | 17.5 | 18.9 | 11 |
| 13 | Iowa | Big Ten | P4 | 18.5 | 16.7 | 17.6 | 14 |
| 14 | Vanderbilt | SEC | P4 | 18.5 | 16.7 | 17.9 | 13 |
| 15 | Oklahoma | SEC | P4 | 18.3 | 16.4 | 17.6 | 15 |
| 16 | USC | Big Ten | P4 | 18.3 | 16.4 | 17.5 | 16 |
| 17 | Penn State | Big Ten | P4 | 18.0 | 16.2 | 17.3 | 17 |
| 18 | Tennessee | SEC | P4 | 14.8 | 13.0 | 14.2 | 18 |
| 19 | Michigan | Big Ten | P4 | 14.8 | 13.0 | 14.1 | 19 |
| 20 | BYU | Big 12 | P4 | 14.8 | 13.0 | 13.7 | 21 |
| 21 | Washington | Big Ten | P4 | 14.7 | 12.8 | 14.0 | 20 |
| 22 | SMU | ACC | P4 | 13.0 | 11.1 | 11.8 | 24 |
| 23 | Missouri | SEC | P4 | 12.7 | 10.8 | 12.0 | 22 |
| 24 | LSU | SEC | P4 | 12.5 | 10.7 | 11.8 | 23 |
| 25 | Clemson | ACC | P4 | 12.4 | 10.5 | 11.3 | 25 |

## Not run in Step 5

- Step 6 (weekly prospective predictions) runs only if the decision above is CONDITIONAL CANDIDATE.
- Step 7 (Gate 5) runs only when n ≥ 100 post-lock P4-vs-G5 games exist (B8).
- Step 8 (market benchmark) is post-freeze and never an input to any gate.
