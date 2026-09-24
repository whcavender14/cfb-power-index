# FCS games in the current-season solve (vCurrent / EB_features)

Status: **positive but small; candidate for a new freeze, not promoted.**
Run date 2026-09-16. Code in `../code/`, results in `../results/artifacts/`.

## Protocol

- Reused the Round 4 walk-forward snapshots (`outputs/round4/{development,conditional}_results.rds`).
  Priors, history, parameters, cutoffs and the test universe are identical; only the
  current-season game table changes (plus the FCS-node prior mean for `_inf` variants).
- Test set: final FBS-vs-FBS games in each weekly period, predicted from games available
  before that Monday. Development 2019/2021/2022 (params fit on earlier seasons);
  locked outer 2023–2025 (frozen params).
- FCS opponents enter as one pooled `FCS` node (existing `team_games()` behavior). The data
  has zero FCS-vs-FCS games, so individual FCS ratings are not identifiable.
- `_inf`: FCS node shrinks toward its historical level (power ≈ −26, seasons ≤ 2022)
  instead of toward 0 (= average FBS team).
- Gate: baseline reproduces archived Round 4 EB_features predictions exactly
  (4,718 games, max |diff| = 0).

## Results (Δ MAE vs baseline; block-bootstrap 95% CI)

| model | dev MAE | dev Δ [CI] | dev seasons better | outer MAE | outer Δ [CI] | outer seasons better | Round 4 rule (outer) |
|---|---|---|---|---|---|---|---|
| base (FBS only) | 12.920 | — | — | 12.518 | — | — | — |
| w = 0.25 | 12.896 | −0.024 [−0.070, +0.012] | 3/3 | 12.466 | −0.052 [−0.087, −0.023] | 3/3 | pass |
| w = 0.50 | 12.899 | −0.021 [−0.104, +0.046] | 1/3 | 12.436 | −0.082 [−0.140, −0.032] | 3/3 | pass |
| w = 0.50 inf | 12.894 | −0.026 [−0.112, +0.043] | 2/3 | 12.442 | −0.076 [−0.132, −0.026] | 3/3 | pass |
| w = 1.00 | 12.957 | +0.037 [−0.114, +0.171] | 1/3 | 12.437 | −0.082 [−0.185, +0.011] | 3/3 | fail |
| w = 1.00 inf | 12.953 | +0.033 [−0.122, +0.168] | 1/3 | 12.445 | −0.073 [−0.175, +0.018] | 3/3 | fail |

No variant passes the Round 4 rule on development, and all variants were inspected on outer.
2023–2025 is therefore no longer a clean confirmation set.

Outer 2023–2025, games with a closing line (n = 2,398):

| model | MAE vs Vegas | Vegas in 80% conf. band | actual in 80% / 95% pred. band | calib. slope |
|---|---|---|---|---|
| base | 3.38 | 94.9% | 80.7% / 95.4% | 1.015 |
| w = 0.25 | 3.26 | 95.7% | 80.9% / 95.6% | 1.025 |
| w = 0.50 | 3.23 | 95.8% | 80.9% / 95.5% | 1.029 |

Other findings:
- Gains are not confined to early season. Outer: weeks 1–4 −0.07 (w = 0.25) and week 5+ −0.05.
- Games where neither team had played an FCS opponent get slightly worse (+0.01 to +0.02).
- The uninformed FCS node sits far above its true level early: at the week-3 cutoff it is
  −16 (w = 0.25) against a historical −26. The informed prior fixes the level (−28)
  but does not improve MAE.
- Promoted programs (n = 32 dev / 57 outer games): MAE improves −0.09 to −0.8. The sample
  is too small to conclude anything.

## Sacramento State 2026 (production cutoff 2026-09-14)

Sac State is FBS in 2026 (MAC) and already rated individually. Its only FCS game so far,
a 52–0 win over Mississippi Valley State, is excluded from the baseline.

| model | rank | power | off | def | prior contrib. | current contrib. |
|---|---|---|---|---|---|---|
| base | 83 | −4.81 | −1.92 | +2.90 | −2.55 | −2.26 |
| w = 0.25 | 83 | −3.83 | −1.56 | +2.27 | −2.49 | −1.34 |
| w = 0.50 | 77 | −3.05 | −1.32 | +1.72 | −2.44 | −0.61 |
| w = 0.50 inf | 78 | −3.19 | −1.41 | +1.78 | −2.44 | −0.75 |

80 of 138 FBS teams have played an FCS opponent. At w = 0.5 those teams move 1.44 points on
average; teams without one move 0.38. The largest single move is Utah State at −5.0.
