# Round 15 decisions (user, 2026-09-24/25)

These resolve the open list in `ROUND15_DESIGN.md`. The predeclaration draft (`ROUND15_PREDECLARATION.md`) implements them.

1. **Primary metric: winner log-loss.** Brier score is the secondary metric and the tie-break. Margin MAE is an important
   guardrail. MAE, RMSE, calibration, winner %, rating spread, per-season, games-played buckets and tier/conference
   slices are all still reported. The goal is underlying team-strength ordering with calibrated separation, not game-margin MAE alone.
2. **Development window: add 2017**, provided the incumbent reproduces for 2017 on the same information rules.
   **Result:** reproduced (§2 of the predeclaration; `docs/round15/replay/`). 2017 joins the development window.
3. **All three nested candidates are kept.** All three are predeclared before formal evaluation, and none is added or
   changed after results. The report shows absolute results, each layer's increment over the previous one, and every
   candidate against both the incumbent and frozen Round 13 K.
4. **Play-by-play: success rate only.** CFBD vendor EPA is not used in any formal Round 15 candidate. Any input derived
   from vendor PPA (including CFBD's PPA-based returning production) is also excluded. EPA may return in a later round with
   a specific hypothesis.
5. **Forward snapshots are automated.** The process must be conservative and auditable: timestamped, write-once, hashed,
   pre-kickoff verified, recording the information available at the cutoff, failing loudly, and keeping history permanently.
   It collects evidence only and never retrains, promotes or deploys. **Built and tested; activation awaits approval of the
   host** (`docs/forward/FORWARD_SNAPSHOTS.md` §6).
6. **Market value becomes the third evaluation objective.** The model stays independent: betting lines, market ratings
   and closing lines are never inputs, and are never used for training, rating updates, feature selection or tuning. Round
   15 evaluates three things: power-rating quality, game-prediction quality and market-prediction value.
   - **Market tests:** opening and closing lines, ATS against both, model edge, ATS by predeclared edge buckets, edge
     calibration, line movement toward the model, and closing-line value, each with sample sizes and uncertainty.
   - **Keep three questions separate:** predicting outcomes, predicting market movement, and beating the spread.
   - **Selection:** log-loss stays the primary power-rating metric. A candidate with materially worse margin prediction or
     obviously poor market behavior cannot advance on log-loss alone.
   - **Evidence weight:** 2023–2025 market results are supporting and descriptive. The strongest evidence must come from
     2026–2027 forward snapshots archived before lines and outcomes were known.
   - **Report:** a three-part scorecard (Power Rating / Game Prediction / Market Value) for the incumbent, frozen Round 13
     K and every Round 15 candidate.
7. **Process.** No thresholds or definitions are tuned to earlier Round 13/14 results, and every place those rounds
   influenced the design is disclosed. No production changes. The user signs off the complete predeclaration before the
   formal experiment begins.

## Follow-up (2026-09-25, before sign-off)

8. **2017 stays in development** and is reported separately (its reconstructed HFA is higher). K comparisons stay on 2018–2022.
9. **Forward host: the local Mac job**, with every safeguard. It is not activated until the final predeclaration and model freeze are approved.
10. **Revisions requested before sign-off, now in the draft:**
    - **Win-probability scale:** model-specific σ, fitted by leave-one-season-out on development and frozen afterwards,
      replaces the fixed σ = 16. Probe 08 found the fixed σ could reverse comparisons.
    - **Fumble value:** estimated walk-forward instead of assumed to be 4 points.
    - **Market evidence:** split into safety (veto), historical signal (descriptive, tests T1–T5) and prospective value
      (the only basis for claims). Historical ATS never gates or advances a candidate.
    - **G1:** explained in plain terms, with power.
    - **Candidates:** a plain-English summary is added as Appendix A.
