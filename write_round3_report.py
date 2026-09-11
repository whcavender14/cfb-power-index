from pathlib import Path
import csv,json,hashlib
p=Path('outputs/round3')
def rows(n):
 with (p/(n+'.csv')).open() as f:return list(csv.DictReader(f))
def table(rs,fields):
 def fmt(x):
  try:
   y=float(x)
   return str(int(y)) if y.is_integer() else f'{y:.3f}'
  except:return str(x)
 return '| '+' | '.join(fields)+' |\n| '+' | '.join(['---']*len(fields))+' |\n'+'\n'.join('| '+' | '.join(fmt(r.get(k,'')) for k in fields)+' |' for r in rs)
m=rows('locked_outer_metrics');dev=rows('development_metrics');season=rows('locked_outer_by_season');paired=rows('locked_outer_paired')
params={'A':'s=.9006317; H=3.06854; C=1.230839; t=4.348663e-7; k=4.981134; current ridge6',
'B':'s=.9006317; H=3.06854; k=2.423410; current ridge1',
'C':'s=.9006317; H=3.06854; prior precision8',
'D':'C with u=.5*prior power variance/median; precision8/(1+u); zero precision2/(1+cross)',
'baseline':'v3 ridge6; coefficients and selection frozen through2022',
'no_prior':'C precision8 with prior mean0','pre_only':'calibrated preseason mean only'}
formulas={'A':'O=C*n/(n+t)*eO+k/(n+k)*mO; same D; center',
'B':'O=n/(n+k)*eO+k/(n+k)*mO; same D; center',
'C':'argmin score SSE +8*sum((o-mO)^2+(d-mD)^2); center',
'D':'argmin score SSE +sum(l*(o-mO/(1+u))^2+l*(d-mD/(1+u))^2+z*(o^2+d^2)); center',
'baseline':'O=a(n)*eO+b(n)*pO; same D; v3 schedule; center',
'no_prior':'argmin score SSE +8*sum(o^2+d^2); center','pre_only':'O=mO; D=mD; center'}
reason={'A':'Passed stability; within .05 of B; B selected by declared simplicity order; not switched using outer.',
'B':'Selected: improved both development seasons, best pooled primary MAE, simplest eligible within .05. Final-standard caveats remain.',
'C':'Passed narrow season screen but >.05 behind B; rejected by development rule.',
'D':'Rejected: pooled development worse than baseline and only one season improved.',
'baseline':'Comparator; not selected by development rule. Different policy from supplied annually refit v3.',
'no_prior':'Diagnostic ablation, never eligible for selection.','pre_only':'Diagnostic ablation, never eligible for selection.'}
ledger=[]
for r in m:
 n=r['candidate'];dd=next(x for x in dev if x['candidate']==n)
 ledger.append(dict(candidate=n,formula=formulas[n],parameters=params[n],feature_availability='prior completed score ratings; current results kickoff+24h before cutoff; no optional features or market',
 history='2015 onward',inner_training='2018-2019 -> 2021; 2018-2019,2021 ->2022; preseason regressions earlier only',
 development='2021,2022',outer='2023,2024,2025',frozen_parameter_max_year=2022,
 game_universe='final FBS-FBS including postseason;1546 dev;2398 outer',development_mae=dd['mae'],
 **{('outer_'+k):v for k,v in r.items() if k!='candidate'},reason=reason[n]))
with (p/'candidate_ledger.csv').open('w') as f:
 w=csv.DictWriter(f,fieldnames=ledger[0].keys());w.writeheader();w.writerows(ledger)
(p/'CANDIDATES.md').write_text('# Candidate ledger\n\nExact formulas and identification assumptions are in MODEL_SPEC.md. The machine-readable candidate_ledger.csv contains parameters, availability, seasons, universe, metrics and reasons.\n\n'+table(ledger,['candidate','development_mae','outer_mae','reason'])+'\n\nSecondary C4/C12/Ccap32/Casym/Crecent/CFCS: declared but not run because the declared primary gate required C or D to win. No optional-feature candidates were eligible. No optional-feature performance effect is claimed; the supplementary score experiments have no outer result.\n')
rr=rows('ratings_2026_v4');subset=[r for r in rr if r['team'] in ['Indiana','Ohio State','James Madison','South Florida','Old Dominion']]
zero=[r for r in rr if int(r['games_played'])==0];one=[r for r in rr if int(r['games_played'])==1]
(p/'ZERO_ONE.md').write_text(f'''# Zero-game and one-game report

2026 ratings as of 2026-09-09 00:00 UTC, using local schedules, fixed pre-2023 fitted coefficients and the development-selected B model. There are {len(zero)} zero-game and {len(one)} one-game teams among 138 FBS IDs. An FCS game does not advance the counted FBS clock.

At zero FBS games, current contribution is exactly zero and the published rating equals the calibrated preseason mean plus common centering. At one game, the prior coefficient is .707894 and current coefficient .292106. The current coefficient applies to ridge1 opponent-adjusted efficiency, not to raw margin.

'''+table(subset,['team','games_played','power_rating','prior_contribution','current_contribution','centering_contribution'])+'''

These contributions sum exactly to power. Separate off_rating and def_rating are in zero_one_game_teams.csv, which contains every zero/one-game team for all five primary/comparator candidates, not only the named examples.

James Madison and South Florida remain predominantly prior-driven. Their smaller ratings do not establish that missing offseason changes have been modeled. With only one informative FBS game, the data cannot reliably identify every team's offense and defense separately. B makes the weighting explicit; it does not create new information.

The frozen-baseline rating distribution has prior-finish correlation .947; B's is .961, using each model's preceding-season rating basis. Because the bases have different ridge penalties, these correlations are not a controlled causal dependence ablation. They nevertheless show that reduced amplitude does **not** establish reduced copying of prior-year ordering. This requirement remains unresolved.

The selected maximum rating is 19.142 and power SD is 7.377, compared with frozen v3 maximum27.587 and SD10.066. There was no output cap or final rescaling. These distributions are descriptive; outer calibration indicates B is too compressed.
''')
(p/'FEATURES.md').write_text('''# Feature and secondary-experiment status

The actual enabled feature set is prior-season score-adjusted offense, defensive burden, and missing-history/promotion status. The score cutoff is strictly earlier than each prediction cutoff. No valid historical QB, roster, portal, staff, injury, EPA, weather or travel snapshot was available in the supplied cache with sufficient publication provenance.

`feature_inventory.csv` reports rows, distinct team IDs where available, event-date presence, and publication/source fields **by every cached season**. No unavailable season is assigned a numeric zero.

- Talent/blue-chip table: has season and team_id but lacks available_at and source. Historical retrospective values cannot establish preseason availability.
- Returning-production table: has team_id and is_estimated, but lacks available_at/source. Estimated values are not assumed to be pre-kickoff observations.
- Portal table: has season and transfer_date, but no team_id join key, available_at or source. Actual transfer date is an event date, not evidence of publication or a reliable observation vintage. Coverage counts describe records, not verified season completeness. Incoming/outgoing values were not fabricated or pooled into a fake zero-filled history.
- Coaching table: has year, team_id and hire_date, alongside target-season games/wins/rank fields. Hire date does not prove the exact preseason staff snapshot. Target-season outcomes were excluded, and no starter/coach identity was derived from them.
- QB continuity/projected starter quality, coordinator/position continuity and confirmed availability: no dated preseason snapshots supplied. Not inferred from season participation or final depth charts.

`v4_check_features()` requires season, team_id, available_at, source and numeric feature values, rejects absent/late provenance, and calls the training-only rank/imputation audit. All-missing, constant, exactly dependent and numerically near-dependent fixtures are tested. No same-row residual-derived feature exists. The interface cannot authenticate the truth of a user-supplied timestamp: acquisition provenance must still be reviewed.

Feature-value ablations are therefore **not estimable**, rather than null effects. The valid score-model ablations are `pre_only` and `no_prior`; their complete development/outer seasonal metrics and paired uncertainty are in the CSVs. The no-prior ablation changes C's prior mean, not B's blend, and should be interpreted within C.

The secondary experiments were explicitly gated before outer evaluation: C/D had to win the primary stage. Neither did. Ridge4/12, offense/defense asymmetry, cap32, recency and pooled-FCS code specifications are retained but no validation-win claim is made for them. HFA ridge sensitivity is a diagnostic calculation. EPA remains disabled: the legacy v2 EPA cache is not an audited pre-cutoff construction and was not used. No arbitrary week intercept or HFA increase was fitted.

A future round needs independently timestamped preseason sources and an untouched later test period. The observed outer conference/dispersion diagnostics must not be used to choose another adjustment while retaining a claim that 2023–2025 are untouched.
''')
fields=['candidate','n','mae','rmse','bias','cor','calib_slope','su_rate']
early=[x for x in rows('outer_by_period_bucket') if x['candidate'] in ['B','baseline']]
conf=[x for x in rows('outer_team_by_conference') if x['candidate']=='B']
ints=[x for x in rows('paired_sensitivity_intervals') if x['candidate']=='B']
report='''# Round 3 results — modest MAE gain; final standard not met

The development-selected successor is **B, a convex blend with an explicitly calibrated preseason mean**. On the one-shot 2023–2025 evaluation it achieves **12.830 MAE**, compared with **12.938 for v3 under the same freeze policy** and **12.019 for the matched market benchmark**. All three outer seasons improve against the frozen baseline, but the gain is only **0.108 points**. A broader season/period bootstrap includes zero. This is a research candidate, not a claim that the requested production standard has been achieved.

The original supplied v3 result was 12.947. Its tuning policy differs, so the principal paired comparison uses a reconstructed frozen v3 baseline. Relative to the supplied headline the numerical reduction is 0.117, but that is not the clean same-policy comparison.

The new model has no preseason blend coefficient above one and no one-game jump to full current weight. However, calibration slope worsens to **1.184**, early bias persists, and conference residual differences remain. Prior-year ordering remains highly influential. Do not promote B merely because its ratings look more plausible.

## Audit findings

See AUDIT.md for confirmed defects, mathematical behavior and hypotheses. The main confirmed policy issue is v3's use of earlier outer years in subsequent candidate selection. A separate FCS-clock counting defect affects its pooled candidate. The preseason amplification is mathematically real, but compensation for ridge attenuation means coefficients above one cannot be classified as erroneous solely by their size.

The 2025 HFA estimate changes from 3.140 at ridge0.1 to 4.377 at ridge6 on the same games. Strong shrinkage and home-schedule composition explain a substantial part of the discrepancy with predictive HFA near3.07; this is not a reason to raise production HFA.

## What was locked, and what remains a limitation

PREDECLARATION.md was written before any successor outer result was computed. Development used expanding forward forecasts: historical score fitting starts in2015; preseason target regressions start in2016; component forecasts start in2018. The 2021 inner holdout calibrates on2018–2019; the 2022 holdout adds2021. All candidates see the same1546 development games. 2020 is excluded as a calibration/regression outcome, while its preceding-season score information remains available to2021.

After development, all candidate choices, handoff parameters, preseason-regression coefficients and HFA calibration were fixed through2022. Previous completed-season score ratings remain admissible next-season inputs under the fixed method; current results update subsequent weeks only after the assumed availability time. No outer outcome enters tuning or candidate selection. No market field enters any estimator or production artifact.

The original supplied outer summaries were already known and motivated this requested audit. Thus this is a locked **one-shot conditional evaluation**, not a pristine independently blinded discovery sample. The source schedules are retrospective snapshots and kickoff+24h is an assumed result availability rule. There is no independent historical snapshot authentication. Further changes informed by this report require a later untouched test period.

There are792 games in2023,798 in2024 and808 in2025: all2398 completed FBS–FBS games in the supplied schedule universe, regular and postseason, including overtime. Forecast cutoffs are Monday00:00 UTC calendar periods, not provider week numbers. No target game or same-period future result is in a fit. All serious candidates use exactly this universe.

## Development results and fixed choice

'''+table(dev,fields)+'''

B was selected because it improved both development seasons, had the best pooled primary MAE, and was simplest under the declared .05 tolerance order. A was also eligible but did not displace it. C was more than .05 behind B. D failed season stability. The two-season cluster interval used by the declared screen is weak evidence; the later reported period-block sensitivity is broader. No selection was changed after outer evaluation. The declared secondary gate did not open because C/D did not win. Optional-feature experiments were ineligible for lack of verified vintages.

MODEL_SPEC.md contains exact formulas; candidate_ledger.csv contains formulas, parameters, availability, training windows, metrics and reasons. CANDIDATES.md is a compact human-readable ledger.

## Locked outer results

'''+table(m,fields)+'''

Straight-up rates in this table are fractions. Bias is prediction minus actual home margin. Calibration slope comes from actual~predicted with an intercept; it is a diagnostic, never an instruction to rescale the published ratings.

'''+table([x for x in season if x['candidate'] in ['B','baseline']],['candidate','season','n','mae','rmse','bias','calib_slope'])+'''

B's paired seasonal MAE changes are −.067 in2023, −.107 in2024 and −.148 in2025. A's MAE is only .0006 lower overall than B; **that outer result does not authorize switching**. D loses all three outer years, consistent with its development rejection.

'''+table(paired,['candidate','estimate','low','high','seasons','improved'])+'''

Above, intervals resample whole seasons. With three seasons these intervals mostly describe variation among the observed years; they are not precise evidence about future seasons. The sensitivity analysis below also resamples calendar-period blocks within sampled seasons. It retains within-period game dependence but does not fully model repeated-team dependence across periods.

'''+table(ints,['stage','estimate','paired_game_low','paired_game_high','season_period_low','season_period_high'])+'''

The locked season/period interval for B is roughly **[−.231,+.014]**. The gain is consistent across observed seasons but not decisive under broader sampling uncertainty. Neither a0.03 nor a0.10 gain should be interpreted as a proven structural advance solely from the mean.

## Early-season behavior

'''+table(early,['candidate','period_bucket','n','mae','bias','calib_slope'])+'''

B improves MAE in each aggregated period but **does not remove early bias**. Period2 bias worsens from−4.040 to−4.528, and period3 from−3.050 to−3.839. Slopes in periods2–4 are approximately1.43,1.53,1.65: substantial underdispersion. Period1 has only13 games and its apparent gain is especially uncertain.

The bias appears at both home and neutral sites. In period2, B has home-site bias−4.461 across111 games and neutral-site bias−5.147 across12; increasing HFA cannot fix a neutral-site error. Those neutral samples are small. The provider-week/calendar crosswalk, favorite magnitude, prior magnitude, promotion, minimum games played, opponent quality and schedule-network tables are supplied. They are diagnostics, not fitted correction terms. No arbitrary calendar intercept, global HFA increase or final slope multiplication was added.

## Conference and schedule-network evidence

The following are **team appearances**, so each game contributes two rows. A positive signed error means that team's predicted margin is too high; positive/negative conference biases need not indicate a causal conference effect.

'''+table(conf,['conference','n','mae','bias'])+'''

Conference USA, the MAC, Sun Belt and American still have positive bias. SEC and Big Ten have negative bias. B modestly reduces some of the original differences but **cannot be said to eliminate weak-schedule overrating**. Low cross-conference exposure has higher MAE: B is14.407 with no distinct cross-conference opponents versus11.966 with more than3. This also mixes early-season information scarcity with schedule structure; it is not an identified connectivity effect. D's broad shrinkage damages dispersion and does not validate a blanket uncertainty discount.

Files include conference-by-season results; distinct FBS-opponent, P4/Pac-12 historical-power-opponent, component-size, cross-conference, FCS-exposure, one-score concentration, prior-variance and opponent-quality buckets. The historical power-conference label includes Pac-12 for its earlier structure and is used only descriptively. Conference labels never enter B. No subjective G5 penalty or SOS bonus is applied.

## Ratings and zero/one-game teams

ZERO_ONE.md reports all named examples, exact contributions, sample counts and limitations. zero_one_game_teams.csv contains every primary candidate's zero/one-game rows; production_all_candidates.csv contains all138 teams for each candidate. off_rating−def_rating equals power_rating throughout, and current+prior+common-centering contributions reconstruct power exactly.

Selected B rates Indiana19.142, Ohio State17.625, James Madison6.493, South Florida6.484 and Old Dominion4.538 at the fixed2026-09-09 cutoff. These are changes from a model experiment, not evidence of real offseason improvement/decline. James Madison and South Florida remain mostly prior-driven. B's power SD is7.377 versus frozen-v3 SD10.066. Its correlation with prior finish is.961, so compressed amplitudes must not be presented as solved carryover dependence.

The exact scalar B weights on calibrated prior/current are1/0 at zero games, .708/.292 at one, .548/.452 at two, .447/.553 at three, .288/.712 at six and .168/.832 at twelve. For EB candidates, scalar schedules are conditional illustrations; the exact joint update uses matrix weights. Both the formulas and this distinction are documented.

## Matched market benchmark

'''+table([x for x in rows('market_matched') if x['candidate'] in ['B','baseline']],['candidate','n','coverage','model_mae','market_mae','delta_mae'])+'''

Source is the supplied CFBD latest-available benchmark export. Provider counts: DraftKings2246, Bovada123, consensus29. No independent closing timestamp verification exists. Latest-available semantics do not establish historical closing lines. The benchmark covers100% of the2398 model games, uses `market_margin=−home_spread`, and was joined only after the frozen design and saved outer predictions. The model-market delta is **+.811**; the season-cluster interval is approximately[+.691,+.983]. Paired seasonal model/market MAE tables and provider coverage are included. Lines were not used to fit, select, rescale or produce ratings.

## Feature ablations and unfinished objectives

FEATURES.md and feature_inventory.csv document every cached feature season and why optional inputs remained disabled. Event dates were not relabeled as publication dates, unavailable years were not zero-filled, and target-season starters/coaches were not inferred from participation or wins. No valid feature-effect estimate can be claimed from these caches.

The score-only ablations show useful preseason information: zero-prior C has14.066 outer MAE; preseason-only has13.955; C has12.866. Their seasonal variation and paired intervals are supplied. These do not estimate the value of QB continuity or any unavailable feature. EPA, garbage-time processing and game-context experiments remain unperformed because no admissible implementation was advanced. The declared secondary C experiments were gated out, not silently claimed as tested.

The final requested standard is **not met**: the market gap remains substantial; gain uncertainty crosses zero under block resampling; early bias and underdispersion remain; prior-finish dependence and weaker-conference residual bias remain. B is a coherent, reproducible candidate suitable for prospective evaluation. There is no evidence here to authorize an outer-informed retuning while continuing to call2023–2025 untouched.

## Reproducibility and deliverables

- cfb_power_ratings_v4.R is separately versioned; its v4_* entry points implement the new models. Legacy v3 helpers remain for comparison. Use cfb_v4_operations.R and the exact commands in COMMANDS.md; do not call inherited v3 build/tune functions by mistake.
- run_round3.R implements development/freeze and outer evaluation. The freeze refuses reselection if its artifact exists and outer execution checks the source hash.
- 25 unit/invariant tests and12 integration checks pass, including full production reconstruction for all primary candidates, target exclusion, future-score counterfactual, timestamp/provenance rejection, HFA once-only, zero/one handling, disconnected graphs, FCS clock, near-rank deficiency, deterministic cache behavior and source integrity.
- A dated prospective prediction archive was actually created for future games only. It excludes outcomes and market fields, refuses overwrite, has integrity digests and read-only file permissions. This is **local append-only practice, not tamper-proof WORM storage**; a filesystem owner can still replace it. A true immutable external store is not configured.
- input_manifest.csv identifies raw inputs and scripts; pre_outer_manifest.csv records the pre-evaluation implementation; design_frozen.rds preserves fitted choices. Development and outer prediction RDS/CSVs retain game IDs and cutoffs; component snapshots retain the exact training rows.

The plots in diagnostics.png and diagnostics.pdf were visually checked. All CSVs and operational artifacts are under outputs/round3. No v3 source, input RDS, or original validation artifact was overwritten.
'''
# Normalize accidental word-number joins for readable prose.
import re
report=re.sub(r'(?<=[A-Za-z])(?=20\d\d\b)', ' ', report)
report=re.sub(r'(?<=\d)(?=[A-Za-z])',' ',report)
(p/'REPORT.md').write_text(report)
for a in (p/'prospective').glob('*.csv'):
 q=Path(str(a)+'.sha256'); digest=hashlib.sha256(a.read_bytes()).hexdigest()+'  '+a.name+'\n'
 if q.exists(): assert q.read_text()==digest, 'Archive digest mismatch'
 else: q.write_text(digest);q.chmod(0o444)
print('Reports written')
# Supplementary fixed-specification diagnostics do not revise the frozen selection.
if (p/'secondary_audit_metrics.csv').exists():
 sec=rows('secondary_audit_metrics');sp=rows('secondary_audit_paired_vs_B')
 note='''The primary secondary-selection gate was closed. To complete the requested robustness audit, the six already-declared fixed specifications were subsequently run on development data only, outside the primary execution protocol. They did not change the freeze or production candidate, and received no outer evaluation. This protocol deviation is explicit; these are supplementary diagnostics, not a retroactive extension of the locked selection claim.'''
 (p/'SECONDARY.md').write_text('# Supplementary development-only robustness audit\n\n'+note+'\n\n'+table(sec,['candidate','n','mae','rmse','bias','calib_slope'])+'\n\nPaired differences versus development-selected B:\n\n'+table(sp,['candidate','estimate','low','high','improved'])+'''\n\nC4 is C with penalty4; C12 has penalty12; Ccap32 caps margins at32; Casym uses offense4/defense12; Crecent uses an eight-calendar-week half-life; CFCS pools FCS observations with weight.25, with FCS excluded from the counted-FBS clock. All use the earlier-only preseason and HFA fits for the respective2021/2022 holdout and the same1546 FBS games. Exact predictions and seasonal metrics are saved.

C4 improves development MAE by .053 versus B, in both years. This is a small difference from only two seasons. It is not substituted for B after the primary outer evaluation. C4 is a defensible candidate for a separately registered prospective comparison. The other variants do not establish stable improvement over B. No EPA or game-context data were added.

Outer metrics for these supplementary variants are intentionally unavailable: the original protocol did not advance them. Run `Rscript secondary_audit_round3.R` to reproduce the fixed development-only audit; it asserts no locked years and verifies that the freeze artifact is unchanged.
''')
 replacements={
 'REPORT.md':[
  ('The declared secondary gate did not open because C/D did not win. Optional-feature experiments were ineligible for lack of verified vintages.','The declared secondary-selection gate did not open because C/D did not win. The already-defined secondary specifications were later audited on development only, outside the primary execution protocol; see SECONDARY.md. They did not change the frozen model or receive outer evaluation. Optional-feature experiments were ineligible for lack of verified vintages.'),
  ('The declared secondary C experiments were gated out, not silently claimed as tested.','The declared secondary C selection was gated out. A supplementary development-only audit subsequently tested the six fixed specifications, explicitly outside the primary execution protocol. C4 had development MAE13.244, a small .053 improvement over B; it is not substituted after viewing the primary outer report. See SECONDARY.md for all metrics and the protocol-deviation disclosure.'),
  ('The score-only ablations show useful preseason information:', 'The score-only ablations show useful preseason information:'),
 ],
 'CANDIDATES.md': [('Secondary C4/C12/Ccap32/Casym/Crecent/CFCS: declared but not run because the declared primary gate required C or D to win.','Secondary C4/C12/Ccap32/Casym/Crecent/CFCS: not advanced by the primary protocol; subsequently run as supplementary development-only diagnostics. See SECONDARY.md for the explicit protocol deviation and metrics.')],
 'FEATURES.md': [('Ridge4/12, offense/defense asymmetry, cap32, recency and pooled-FCS code specifications are retained but no validation-win claim is made for them.','Those six fixed specifications were subsequently run as supplementary development-only diagnostics outside the primary protocol. SECONDARY.md reports them, including the modest C4 improvement. They did not change selection, and no outer-win claim is made.')],
 }
 for name,repls in replacements.items():
  text=(p/name).read_text()
  for a,b in repls:text=text.replace(a,b)
  if name=='REPORT.md':text=re.sub(r'\b(?!round(?=\d))([A-Za-z]{2,})(?=\d)',r'\1 ',text)
  (p/name).write_text(text)
 with (p/'candidate_ledger.csv').open('a') as ff:
  ww=csv.DictWriter(ff,fieldnames=ledger[0].keys())
  for sr in sec:
   z={k:'' for k in ledger[0]};z.update(candidate=sr['candidate'],formula='C objective with fixed variant; see SECONDARY.md',
    parameters={'C4':'lambda4','C12':'lambda12','Ccap32':'lambda8 cap32','Casym':'off4 def12','Crecent':'lambda8 half_life8weeks','CFCS':'lambda8 fcs_weight.25'}[sr['candidate']],
    feature_availability='same audited score-only inputs; FCS weighted only for CFCS',history='2015-2022',
    inner_training='2018-2019 ->2021;2018-2019,2021 ->2022',development='2021,2022',outer='NOT EVALUATED: primary gate closed',
    frozen_parameter_max_year=2022,game_universe='same1546 development FBS games',development_mae=sr['mae'],
    reason='Supplementary post-freeze development diagnostics only; not eligible to replace frozen B; no outer claim')
   ww.writerow(z)
# Terminology of published component fields is explicit.
with (p/'ZERO_ONE.md').open('a') as ff:ff.write('\nIn the production CSV, pre_power is the unscaled historical-target regression output. The additive prior_contribution includes the learned game-margin scale and the handoff weight; use that field to interpret preseason influence.\n')
