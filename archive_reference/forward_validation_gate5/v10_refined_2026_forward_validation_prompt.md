# v10 Refined: 2026 Forward Validation

**Superseded by `v10_refined_amendment_02_gate5.md` (signed 2026-09-22T14:31:18Z).** This document's tier map (no season index — 2026 Pac-12 misclassified as P4) and decision rule (`|bias| < 0.23`) are replaced. Use `gate5_2026.R` and the amendment instead. Kept here for history only.

**When to use:** when 2026 season game results and incumbent predictions are available.

## Context

v10_refined passed gates 1–4 on 2018–2025 data. This evaluates gate 5: does it generalize to 2026?

Baselines (2023–25, P4-oriented bias = mean of (actual − pred) × s):
- Incumbent: 3.44
- v10_refined: −0.23
- v10_candidate (frozen, overshoots): −2.05

**Decision rule (as specified):** PROMOTE if |2026 v10_refined bias| < 0.23; otherwise STAY on incumbent.

> Note before running: the 2026 bias will have a standard error of roughly 13/√n (≈1.3 at n≈100). A 0.23 bar is far below that noise, so this rule will mostly reject regardless of the true quality of the correction. Step 4 therefore also reports the bias CI and the incumbent's bias for context. Consider deciding in advance whether the rule should instead be "v10_refined |bias| < incumbent |bias| in 2026" — amend and re-hash the predeclaration *before* looking at 2026 results if so.

## Frozen parameters (no re-fitting)

`correction = s × (a + b × p4_home)`, a = 2.356, b = 1.831 (from `archive/v10-round10/results/refined/v10_refined.py`). `v10_refined = ablation1_incumbent + correction`.

## Step 1: Load 2026 data and build v10_refined predictions

```python
import pandas as pd, numpy as np
A, B = 2.356, 1.831  # frozen
P4 = {'ACC','Big Ten','Big 12','SEC','Pac-12'}
G5 = {'American Athletic','Conference USA','Mid-American','Mountain West','Sun Belt'}
tier = lambda c: 'P4' if c in P4 else 'G5' if c in G5 else 'Other'

games = pd.read_csv('path/to/2026_games.csv')   # season, game_id, week, actual_margin, home_conference, away_conference, neutral
preds = pd.read_csv('path/to/2026_predictions.csv')
inc = preds[preds.model == 'ablation1_incumbent'][['season','game_id','predicted_margin_with_hfa']] \
        .rename(columns={'predicted_margin_with_hfa': 'ablation1_incumbent'})
d = games.merge(inc, on=['season','game_id'])
ht, at = d.home_conference.map(tier), d.away_conference.map(tier)
d['s'] = np.where((ht=='P4')&(at=='G5'), 1, np.where((ht=='G5')&(at=='P4'), -1, 0))
d['p4_home'] = ((d.s==1) & (~d.neutral.astype(bool))).astype(float)
d['v10_refined'] = d.ablation1_incumbent + d.s * (A + B * d.p4_home)
print(len(d), 'games;', (d.s != 0).sum(), 'P4-vs-G5')
```

## Step 2: Bias

```python
x = d[d.s != 0].copy()
x['r_incumbent']  = (x.actual_margin - x.ablation1_incumbent) * x.s
x['r_v10_refined'] = (x.actual_margin - x.v10_refined) * x.s
for c in ['r_incumbent','r_v10_refined']:
    m, se = x[c].mean(), x[c].std()/np.sqrt(len(x))
    print(f'{c}: bias {m:.2f}  SE {se:.2f}  95% CI [{m-1.96*se:.2f}, {m+1.96*se:.2f}]')
```

## Step 3: MAE (paired, block bootstrap by week)

```python
def delta(df): return ((df.actual_margin-df.v10_refined).abs()-(df.actual_margin-df.ablation1_incumbent).abs()).mean()
for name, df in [('all 2026 games', d), ('P4-vs-G5 only', x)]:
    g = df.groupby('week').indices; keys = list(g); rng = np.random.RandomState(42)
    bs = [delta(df.iloc[np.concatenate([g[k] for k in rng.choice(keys, len(keys))])]) for _ in range(2000)]
    print(name, f'paired dMAE {delta(df):.3f}  95% CI [{np.percentile(bs,2.5):.3f}, {np.percentile(bs,97.5):.3f}]')
```

## Step 4: Decision

```python
b = x.r_v10_refined.mean(); base = -0.23
print('PROMOTE' if abs(b) < abs(base) else 'STAY on incumbent',
      f'(2026 bias {b:.2f} vs baseline {base}; incumbent {x.r_incumbent.mean():.2f})')
```

## Deliverables

- `2026_v10_refined_bias.csv`: season, game_id, actual_margin, ablation1_incumbent, v10_refined, s, r_incumbent, r_v10_refined
- `2026_v10_refined_report.txt`: bias comparison with CIs, MAE deltas, decision

## Notes

- No re-fitting; coefficients are frozen from 2018–22.
- 2026 was not used in any fit, diagnostic or gate definition.
- If promoted, v10_refined becomes the incumbent; if not, v5_EB_features remains in production.
