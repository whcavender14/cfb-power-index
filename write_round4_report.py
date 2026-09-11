"""Generate narrative reports from frozen Round 4 CSV outputs, never fit/select."""
import csv
from pathlib import Path
P=Path('outputs/round4')
def rows(n): return list(csv.DictReader((P/(n+'.csv')).open()))
def num(r,k): return float(r[k])
def fmt(v):
    try: return f'{float(v):.3f}'
    except (ValueError,TypeError): return str(v)
def table(rs,cols):
    return '| '+' | '.join(cols)+' |\n| '+' | '.join(['---']*len(cols))+' |\n'+'\n'.join('| '+' | '.join(fmt(r.get(k,'')) if k not in ['candidate','team','season','period_bucket','site','parameter','passes'] else str(r.get(k,'')) for k in cols)+' |' for r in rs)
ledger=rows('candidate_ledger'); sel=next(r['candidate'] for r in ledger if r['selection_reason'].startswith('Selected'))
l={r['candidate']:r for r in ledger}; cm={r['candidate']:r for r in rows('conditional_metrics')}; mk={r['candidate']:r for r in rows('market_benchmark')}
b=l['B']; s=l[sel]; c=cm[sel]; m=mk[sel]
seasonal=[r for r in rows('development_paired_seasons') if r['candidate']==sel]
cp=next(r for r in rows('conditional_paired') if r['candidate']==sel)
prod=next(r for r in rows('production_distribution') if r['candidate']==sel)
requested=[r for r in rows('requested_team_components') if r['candidate']==sel]
periods=[r for r in rows('development_calibration_period_bucket') if r['candidate']==sel]
sites=[r for r in rows('conditional_calibration_site') if r['candidate']==sel]
weights=[r for r in rows('component_schedules') if r['candidate'] in ['B',sel]]
nt=len(rows('tests')); ni=len(rows('integration_tests')); nv4=len(rows('ported_v4_tests'))+len(rows('ported_v4_integration_tests'))
report=f'''# Round 4 results

**Selected: {sel}, the precision-4 empirical-Bayes score model with eligible talent, returning-production and coaching preseason features.** It earned advancement from earlier-only matched development evidence, before the secondary conditional test. v4 and all Round 3 artifacts remain unchanged.

## Development decision

The expanded development sample has 2,320 final FBS-versus-FBS games, including postseason, in 2019, 2021 and 2022. The earliest usable forward prior component is 2018; it calibrates 2019. Every candidate scores exactly the same game IDs. The original 2021–2022 B predictions are reproduced to numerical tolerance below 1e-9.

Selected MAE is **{fmt(s['mae'])}**, versus **{fmt(b['mae'])}** for B: a paired change of **{fmt(s['estimate'])} points/game**. Its season-cluster 95% interval is [{fmt(s['season_low'])}, {fmt(s['season_high'])}], and season-plus-calendar-period block interval is [{fmt(s['block_low'])}, {fmt(s['block_high'])}]. Its HFA-adjusted held-out calibration slope is **{fmt(s['slope'])}**, versus {fmt(b['slope'])}; no held-out slope was forced to one.

{table(ledger,['candidate','mae','slope','estimate','block_low','block_high','passes'])}

TRUE means the declared pooled-MAE, calibration, seasonal-stability and paired-uncertainty requirements passed, not that the candidate was necessarily selected. {sel} is more than .05 MAE better than the other passing candidates, so the simplicity tie-break does not override it. B is the incumbent reference and is not tested for advancement against itself.

{table(seasonal,['season','delta_mae'])}

Only three independent development seasons support this decision. Bootstrap intervals are descriptive resampling evidence, not a guarantee for a different football era. Talent_RP and Full also passed; RP alone, Coach alone, C4, B_scale, and both structural candidates did not clear all requirements. Conference also failed its required comparison against general Uncertainty. There is no installed conference or G5 penalty.

## Features and provenance

Historical offseason data with missing exact publication dates were used in primary development when substantively season-appropriate. All cached feature observations remain **historical_vintage_unverified**. No download, scrape, cfbfastR, file-modification, transfer or hire date is represented as a historical publication date. FEATURE_AUDIT.md gives field-level decisions; raw files and hashes are separate from team-level transformations and snapshot IDs.

Returning production is represented by separate offensive and defensive fractions. On FBS-only records, offense covers 128/130 teams in 2021; defense covers 47/130. Defense is absent before 2017. Coverage regimes retain available offense, use earlier training only, and never turn a missing substantive feature into zero. RP's development MAE change is {fmt(l['RP']['estimate'])} with block interval [{fmt(l['RP']['block_low'])}, {fmt(l['RP']['block_high'])}]: **its independent incremental benefit is inconclusive**. Offense-only and defense-only ablations are reported, not discarded for missing publication metadata.

No independently stronger historical-vintage or contributor-construction subset was recovered with enough training/forward coverage. Thus a distinct higher-provenance RP estimate is unavailable. is_estimated is missing for all pre-2026 rows and cannot authenticate them. Every external-feature improvement therefore depends on lower-confidence historical aggregates; these data do not establish historical-vintage robustness. Removing all external features routes the feature pipeline back to exact B.

Portal has event accounting, separate incoming/outgoing aggregates, name-resolution statuses and duplicate-player exclusions, but only one possible pre-2023 forward test season. Destination-state timing is also not independently authenticated. No portal effect is fitted. No acceptable QB continuity source exists; unknown_QB is explicit. Coaching excludes all target-season performance fields and uses only a unique pre-cutoff hire/tenure state. All transformations, penalty choices, imputation of previous-score inputs, rank screens and standardization are fold-local.

The feature extensions replace B's preseason OLS with the declared ridge coverage-regime model. Their differences include this estimation policy as well as feature content; they are not causal effects of roster changes. Talent_RP's gain is stronger than RP alone, while adding coaching to it does not improve its pooled MAE. The full EB family was fixed in advance and was not redesigned from conditional results.

## Secondary conditional test: 2023–2025

These outcomes were already conditionally exposed by Round 3. They are **not a fresh locked outer test**. The frozen selected candidate remains unchanged.

{table([cm[k] for k in ['B','B_scale','C4','RP','Talent_RP','Full',sel,'Uncertainty','Conference']],['candidate','n','mae','rmse','bias','intercept','slope'])}

Selected-vs-B paired MAE change is {fmt(cp['estimate'])}, with block interval [{fmt(cp['block_low'])}, {fmt(cp['block_high'])}]. Global HFA-adjusted slope {fmt(c['slope'])} and bias {fmt(c['bias'])} are encouraging conditional diagnostics. They do not authorize new tuning or prove that early-season behavior is solved.

## Calibration, evidence states and schedule structure

Slopes/intercepts below use actual and predicted margins with each fitted HFA removed. The raw game-scale MAE/RMSE/bias remain unadjusted. Neutral and nonneutral games are separately evaluated. Reliability bins, all declared game-state buckets, provider weeks, promotion, prior/favorite magnitudes, and bootstrap intervals are in the calibration CSVs.

Selected development period diagnostics:

{table(periods,['period_bucket','n','mae','bias','slope','slope_low','slope_high'])}

Period 1 is small and unstable; periods 2–4 still show compression in development. The selected model improves aggregate behavior but does not eliminate every early-state defect.

Selected conditional site diagnostics:

{table(sites,['site','n','mae','bias','intercept','slope','slope_low','slope_high'])}

Network reports cover historical conference, distinct FBS opponents, distinct cross-conference opponents, component size, descriptive power-conference opponents, FCS exposure, one-score concentration, prior uncertainty, already-faced opponent prior strength/current working variance, and zero/one/multiple-game states. Future edges are excluded. Conference membership is season-labeled provider metadata, not independently archived announcements. Unknown/ambiguous historical membership remains a provenance limitation. Conference-average plausibility did not determine selection.

## Current ratings and exact contributions

At the fixed 2026-09-09 00:00 UTC information cutoff, the selected rating SD is {fmt(prod['rating_sd'])} points. Preseason prior-finish Pearson correlation is {fmt(prod['pearson'])}; Spearman is {fmt(prod['spearman'])}. Correlation reduction was not optimized or treated as a success criterion.

{table(requested,['team','games_played','power_rating','prior_contribution','current_contribution','centering_contribution','power_prior_inputs_at_mean'])}

Prior and current contributions come from the coupled score system, not scalar marginal percentages. They sum to power with centering. The counterfactual replaces only previous-score offense/defense inputs by the centered FBS mean while keeping valid offseason features, promotion state and current evidence fixed. Team movements are model outputs, not evidence that a team's real ability changed by that amount.

The selected EB objective uses prior precision4, preseason scale 1.12271478057756, prediction HFA 3.06853968902663 and gamma1. It has no convex handoff parameter. Reported fitted k values for EB are unused comparison diagnostics. At globally zero games, EB is the centered calibrated preseason mean. After one game, its opponent-coupled matrix solve updates both units. The exact zero/one synthetic outputs and additive contributions are in zero_one_algebra_fixtures.csv. component_schedules.csv explicitly labels EB shares as conditional illustrations.

## Matched market benchmark

The read-only supplied CFBD latest-available export covers all 2,398 conditional games. Provider counts are in market_providers.csv. Source/query and content hash are in market_source_manifest.csv. No independent closing quote timestamp was recovered: **latest-available is not verified closing**. Lines were joined only after design and predictions were saved.

Selected model MAE **{fmt(m['model_mae'])}**, market MAE **{fmt(m['market_mae'])}**, model-minus-market **+{fmt(m['delta_mae'])}**. The model still trails this benchmark materially. Market inputs never enter priors, preprocessing, calibration, selection or production. Seasonal paired comparisons and both uncertainty intervals are exported.

## Verification and reproducibility

{nt} v5 invariant groups and {ni} integration checks pass; the integration suite includes both original v4 suites ({nv4} checks total) with output paths redirected into Round 4. Full production reconstruction passes for all twelve candidates using the frozen feature snapshots. Future/target score perturbations leave the target predictions unchanged, and conditional B reproduces v4 to below 1e-9. Tests cover missing-date eligibility, substantive leakage rejection, forbidden fields, no zero-filled returning shares, duplicate joins, portal accounting, nested preprocessing, graph/FCS clock, power/HFA identities, cache dependency invalidation and archive guards.

The first development execution had an R negation-precedence error in the new scale objectives. It was invalidated and retained under pre_fix_invalid_run/. The mathematical bug was fixed before any Round 4 conditional scoring; all declarations and selection rules stayed unchanged. Objective-to-prediction equality is now tested. See IMPLEMENTATION_CORRECTION.md. These invalid results must not be cited as evidence.

A future-game archive was actually created under prospective/, with prediction and information times, team IDs, neutral status, feature snapshot IDs/hashes and design hash, and no outcomes or market columns. Exclusive create, digest and read-only permissions provide local append-only practice; a filesystem owner can still alter files, so no hardware-WORM claim is made.

Use COMMANDS.md for exact reproduction and operational commands. design_frozen.rds contains the selected policy and fitted parameters; pre_selection_manifest.csv and pre_conditional_manifest.csv preserve stage hashes. diagnostics.png was visually inspected. Full formulas and limitations are in MODEL_SPEC.md and FEATURE_AUDIT.md.

## Decision boundary

This successor earns **development advancement**, not a claim of market superiority or fully verified historical vintage. It retains early-period uncertainty, strong prior dependence, uncertain historical feature revisions, and only three development seasons. Prospective performance and stronger historical provenance remain the most useful next evidence.
'''
(P/'REPORT.md').write_text(report)
(P/'CALIBRATION_DECISION.md').write_text(f'''# Calibration and advancement decision

The authoritative pre-fit protocol is PREDECLARATION.md. Candidate ordering, grids, calibration tolerance (.05 slope-distance deterioration), minimum .05 MAE gain, at least two improving seasons, and both paired 95% upper bounds below zero were fixed before fitting. Season and season-plus-period bootstraps use seed9041 and 2000 replicates. Calibration is measured using held-out predictions after HFA removal; no slope is forced to1.

B_scale fixes B's handoff/scale/HFA then fits gamma in [.5,2] on earlier margins only; gamma affects published neutral ratings, never HFA. Feature-family preseason scale uses [.1,3], baseline HFA fixed. Scalar log-k uses [-8,10] with objective profiles. No multidimensional nonlinear optimizer is used; prior ridge and EB are direct linear solves. Prior ridge alpha0, penalty grid {{.1,1,10,100}}, earlier forward unit-MSE selection. Reported scalar derivatives are finite-difference diagnostics of a nonsmooth LAD objective, not differentiability claims. No final corrected scalar fit is at its declared boundary.

{table(ledger,['candidate','mae','slope','estimate','season_high','block_high','passes'])}

Selected {sel}. It beats the passing Talent_RP and Full variants by more than the .05 simplicity tolerance. C4 and Conference have promising small gains but block intervals include zero. B_scale improves calibration but lacks stable MAE advancement evidence. RP alone is inconclusive; coaching-only is negligible. Conference also had to beat Uncertainty and did not clear all safeguards. No conference model is installed.

Final selected objective is score SSE +4 prior-mean squared deviation, with separate unit priors from eligible features. s=1.12271478057756, HFA=3.06853968902663, gamma=1. The selected EB fit does not use its separately reported comparator k. Exact formulas and component schedules are in MODEL_SPEC.md and component_schedules.csv.

The known-invalid initial scale implementation is preserved and disclosed in IMPLEMENTATION_CORRECTION.md. It was corrected before conditional scoring without changing the declared family, grid or rule. Conditional 2023–2025 results did not replace the selection.
''')
(P/'FEATURE_ABLATIONS.md').write_text('''# Feature ablations and provenance sensitivity

feature_ablations.csv contains matched game-level paired changes, season-cluster and calendar-period block intervals for B, RP, RP_off, RP_def, Talent_RP, Coach, Full and EB_features, separately for development and conditional testing. *_paired_seasons.csv records seasonal variation. feature_coverage.csv and feature_coverage_routes.csv describe unit-specific availability and learned coverage regimes; no incomplete team-season is dropped from evaluation.

RP uses every eligible historical unit observation with sufficient earlier training coverage. Offense and defense remain separate. Their independent incremental gains are inconclusive on development. Talent_RP and the fixed full-feature EB family provide stronger development evidence. Because ridge estimation and coverage regimes also differ from B, these are pipeline comparisons rather than causal feature effects.

All fitted external history is historical_vintage_unverified. There are zero independently stronger pre-2023 observations sufficient for a separate higher-provenance model. The is_estimated flag has no pre-2026 observed values and is not a source-authentication proxy. This limits provenance robustness; it does not render the main historical feature unestimable. The all-external-missing sensitivity returns exact B, so external-feature gains remain dependent on these lower-confidence observations.

Portal's short history and unresolved destination-state timing restrict it to exploratory accounting. QB continuity is unknown. No effects or zeros are invented for these unavailable specifications.
''')
(P/'MARKET_BENCHMARK.md').write_text(f'''# Read-only matched market benchmark

Source: supplied CollegeFootballData latest-available export, exact path/hash in market_source_manifest.csv. Provider breakdown in market_providers.csv. Quote publication/closing timestamps are not independently verified. A latest-available export is not established to be the final pre-kickoff closing line.

The benchmark was first read by report_round4.R after frozen model predictions were saved. No market fields are accepted by model/preprocessing/calibration ingress. Margin convention: market home margin = -home spread.

{table(rows('market_benchmark'),['candidate','n','coverage','model_mae','market_mae','delta_mae'])}

Positive delta means the model is worse. The selected model remains {fmt(m['delta_mae'])} points/game behind the matched market. Seasonal differences and both cluster/block intervals are supplied in market_paired_seasons.csv and market_paired_uncertainty.csv. Conditional outcomes remain previously exposed, and market semantics remain unverified-closing.
''')
print('Wrote Round 4 reports; selected',sel)
