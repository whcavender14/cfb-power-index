# Calibration and advancement decision

The authoritative pre-fit protocol is PREDECLARATION.md. Candidate ordering, grids, calibration tolerance (.05 slope-distance deterioration), minimum .05 MAE gain, at least two improving seasons, and both paired 95% upper bounds below zero were fixed before fitting. Season and season-plus-period bootstraps use seed9041 and 2000 replicates. Calibration is measured using held-out predictions after HFA removal; no slope is forced to1.

B_scale fixes B's handoff/scale/HFA then fits gamma in [.5,2] on earlier margins only; gamma affects published neutral ratings, never HFA. Feature-family preseason scale uses [.1,3], baseline HFA fixed. Scalar log-k uses [-8,10] with objective profiles. No multidimensional nonlinear optimizer is used; prior ridge and EB are direct linear solves. Prior ridge alpha0, penalty grid {.1,1,10,100}, earlier forward unit-MSE selection. Reported scalar derivatives are finite-difference diagnostics of a nonsmooth LAD objective, not differentiability claims. No final corrected scalar fit is at its declared boundary.

| candidate | mae | slope | estimate | season_high | block_high | passes |
| --- | --- | --- | --- | --- | --- | --- |
| B | 13.238 | 1.136 | 0.000 | 0.000 | 0.000 | FALSE |
| B_scale | 13.176 | 0.982 | -0.062 | 0.041 | 0.067 | FALSE |
| C4 | 13.154 | 1.044 | -0.083 | -0.034 | 0.017 | FALSE |
| Coach | 13.232 | 1.134 | -0.006 | 0.013 | 0.017 | FALSE |
| Conference | 13.146 | 1.059 | -0.092 | -0.077 | 0.011 | FALSE |
| EB_features | 12.920 | 1.054 | -0.317 | -0.144 | -0.103 | TRUE |
| Full | 13.042 | 1.170 | -0.195 | -0.084 | -0.060 | TRUE |
| RP | 13.218 | 1.138 | -0.020 | 0.053 | 0.058 | FALSE |
| RP_def | 13.234 | 1.135 | -0.003 | 0.028 | 0.030 | FALSE |
| RP_off | 13.216 | 1.140 | -0.022 | 0.017 | 0.023 | FALSE |
| Talent_RP | 13.023 | 1.137 | -0.215 | -0.036 | -0.031 | TRUE |
| Uncertainty | 13.206 | 1.063 | -0.032 | 0.013 | 0.068 | FALSE |

Selected EB_features. It beats the passing Talent_RP and Full variants by more than the .05 simplicity tolerance. C4 and Conference have promising small gains but block intervals include zero. B_scale improves calibration but lacks stable MAE advancement evidence. RP alone is inconclusive; coaching-only is negligible. Conference also had to beat Uncertainty and did not clear all safeguards. No conference model is installed.

Final selected objective is score SSE +4 prior-mean squared deviation, with separate unit priors from eligible features. s=1.12271478057756, HFA=3.06853968902663, gamma=1. The selected EB fit does not use its separately reported comparator k. Exact formulas and component schedules are in MODEL_SPEC.md and component_schedules.csv.

The known-invalid initial scale implementation is preserved and disclosed in IMPLEMENTATION_CORRECTION.md. It was corrected before conditional scoring without changing the declared family, grid or rule. Conditional 2023–2025 results did not replace the selection.
