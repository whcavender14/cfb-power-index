suppressPackageStartupMessages(source('cfb_v6_operations.R'))
f<-v6_frozen();z<-readRDS(file.path(v6_dir,'development_results.rds'));bundle<-readRDS('outputs/round4/features.rds');input<-readRDS(file.path(v6_dir,'inputs.rds'));history<-z$history;sch<-setNames(lapply(2015:2022,v4_schedule),2015:2022);base<-v4_components(sch,history,c(2018,2019,2021,2022));inc<-z$cps$v5_EB_features;b<-z$predictions[z$predictions$candidate=='v5_EB_features',]
variants<-list(efficiency_no_pass_rush=list(block='efficiency',metrics=c('success_rate','line_yds','stuff_rate')),efficiency_no_front=list(block='efficiency',metrics=c('success_rate','passing_plays_success_rate','rushing_plays_success_rate')),multi_L2=list(block='multi',L=2),multi_L3=list(block='multi',L=3),multi_L4=list(block='multi',L=4))
out<-list();ledger<-list()
for(n in names(variants)){
 message('Predeclared diagnostic ablation ',n);a<-variants[[n]];v6_eff_metrics<-a$metrics%or%c('success_rate','passing_plays_success_rate','rushing_plays_success_rate','line_yds','stuff_rate')
 cp<-v6_components(base,history,bundle$features,a$block,input$extra,a$L);pred<-list()
 for(s in v6_config()$development){p<-v6_calibrate(cp,inc,s,z$incpars[[as.character(s)]]);pred[[as.character(s)]]<-v6_evaluate(v4_subset(cp,s),p,history,sch,incpar=z$incpars[[as.character(s)]])$predictions}
 d<-bind_rows(pred);out[[n]]<-mutate(d,candidate=n);ledger[[n]]<-cbind(candidate=n,v6_advance(d,b));ledger[[n]]$passes<-NULL
}
v6_write(bind_rows(out),'diagnostic_ablation_predictions');v6_write(bind_rows(ledger),'diagnostic_ablations')
writeLines(c('# Feature ablations and coverage/provenance sensitivity','',
'Primary block ablations are each eligible family versus v5_EB_features in development_paired.csv. Separate declared diagnostic ablations in diagnostic_ablations.csv remove efficiency passing/rushing splits or the line/stuff block, and restrict older-score history to L2/L3/L4 with inner half-life/penalty choice. These diagnostics cannot promote or revise a candidate.',
'',
'Position-level returning/incoming and QB ablations: not estimable; no recovered player-ID-resolved preseason state history supporting three folds. Coordinator: not estimable; no eligible coordinator identity source. These are missing experiments, not evidence of no effect. The inherited aggregate returning-production comparator remains part of v5, and Round4 RP_off/RP_def evidence is read-only history.',
'',
'Special-teams ablation is the entire returns/field-position block versus v5. Kicking and punting efficiency, player continuity, EPA/explosiveness, havoc and finishing-drive fields were not available with the required calculation/state audit and were not fit.',
'',
'Atomic added unit blocks route to the incumbent when any required external value is missing, including zero return attempts. feature_coverage_routes.csv enumerates routing; every evaluated family retains all 2320 game IDs. All-new-block-disabled sensitivity is exact incumbent by construction and tested. No feature availability is zero-filled.',
'',
'Independently verified historical-vintage-only sensitivity: zero eligible forward seasons; no estimate. Missing exact publication time alone did not exclude season-appropriate primary inputs. Reconstructed history depends on unverified historical provider revisions.',
'',
'No full-family deletion ablation is estimable where the nested union contains no components; check nested_component_gates.csv. No ablation changed the frozen selected model.'),file.path(v6_dir,'FEATURE_ABLATIONS.md'))
