# Résumé rankings (/rankings/resume/): methodology proposal

Status: **approved 2026-09-26 (option A, strength of record) and built** at `/rankings/resume/` (`resume.json`). The team page shows "Résumé rank" next to "CFPi+ rank (predictive)".

## What already exists

- **Strength of record (SOR)**, on team pages and `/teams/` since Stage 3: wins so far minus the wins a benchmark team would expect against the same opponents and sites.
- **The simulation's CFP résumé score** (`R/simulation/cfb_dynamic_playoffs.R`): `1.9887 × wins above benchmark + 0.14943 × opponent-adjusted margin + 1.7923 × conference title`. The coefficients are **fitted**, not hand-set: a rank-ordered (Plackett–Luce) logit on the committee's final top 25, 2018–2025, excluding 2020 (`scripts/calibrate_cfp_ranking.R`). It ranks teams inside simulated completed seasons.

## Proposal: rank by strength of record (wins above benchmark)

`SOR = Σ over final games (win − P_bench)`, with `P_bench = Φ((B − opp_power + HFA·loc) / σ)`.

| Input | Value | Why it is defensible |
|---|---|---|
| Wins and losses | Final games with kickoff before the ratings cutoff (the record shown everywhere) | A résumé is what a team has done, nothing projected. |
| Opponent strength | Current CFPi+ rating of each opponent, FBS and non-FBS (the model's own FCS ratings) | Uses the best available estimate of each opponent, so a win gains or loses value as the opponent's season plays out. This is the standard strength-of-record convention. |
| Benchmark B | The rating of the **No. 60** CFPi+ team | Already the benchmark in the production config (`cfp_rank_benchmark`), and the same term the committee-fitted score uses. No new parameter. |
| Home field, σ | 3.07 points; 15.65 | The model's own values. |
| Weights | None | SOR is a single sum of win-minus-expectation, so there are no weights to tune. |

Why not the full committee-fitted score? It is defensible for completed seasons, but mid-season (1) the conference-title term is unknown, and (2) the opponent-adjusted-margin term measures how well a team played, which is predictive and would blur the line with CFPi+. The coefficients were also fitted with the previous model's ratings (EB_features), not C2. **Option B**, if you prefer it: show the fitted score with the title term set to 0 until champions are decided, labelled "committee-style score". I recommend option A (SOR) as the ranking and at most showing option B's inputs.

### Handling of special cases

- **FCS and lower-division games** count, using the model's own non-FBS ratings. Beating an FCS team earns almost nothing (the benchmark would win ~99%); losing to one costs almost a full win.
- **Ties in SOR** (rare: all 138 values differ this week): fewer losses, then higher strength of schedule, then team id.
- **Byes / fewer games played**: no adjustment. SOR is a sum, so an extra win above expectation counts. The table shows games played so it is visible.
- **Early season**: shown from Week 1 with a note that one or two games decide it. Opponent ratings are also least certain then.
- **Independents**: no special case (no title term in option A).
- **Unavailable simulation**: SOR needs only ratings and results, but today's opponent powers come from the simulation file. If the simulation is missing, the page says so rather than falling back.

### How it stays separate from the predictive rank

- The page is titled **"Résumé ranking"** with the lede: "What each team has accomplished so far. It is not a prediction; for how good teams are, see CFPi+ Rankings."
- The table shows **Résumé rank** first and a separate column **"CFPi+ (predictive) rank"**, never merged or averaged.
- Wherever both appear (team pages, résumé page), the labels are "Résumé rank (SOR)" and "CFPi+ rank (predictive)".

### Preview (Week 3, 2026, from data already exported)

| Résumé rank | Team | Record | SOR | CFPi+ rank |
|---|---|---|---|---|
| 1 | Ole Miss | 3–0 | +1.70 | 13 |
| 2 | Texas | 3–0 | +1.62 | 2 |
| 3 | Alabama | 3–0 | +1.59 | 5 |
| 4 | Mississippi State | 3–0 | +1.47 | 19 |
| 5 | Duke | 3–0 | +1.23 | 47 |
| 6 | Notre Dame | 3–0 | +1.22 | 3 |
| 7 | Michigan | 3–0 | +1.21 | 26 |
| 8 | Pittsburgh | 3–0 | +1.11 | 28 |
| 9 | Florida | 3–0 | +1.05 | 14 |
| 10 | USC | 4–0 | +1.04 | 16 |

The gap between the columns (Duke 5th on résumé, 47th predictive) is exactly the distinction the page exists to show.

## Implementation (after approval)

The exporter already computes `sor` and `sor_rank`. The page adds the tie-break order above, a sortable table (résumé rank, team, record, SOR, SOS played, best win, worst loss, CFPi+ predictive rank), a methodology box and a PNG download. No new model inputs.
