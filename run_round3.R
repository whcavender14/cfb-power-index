suppressPackageStartupMessages(source('cfb_v4_operations.R'))
args<-commandArgs(TRUE);mode<-if(length(args))args[1] else 'develop'
outdir<-'outputs/round3';dir.create(outdir,recursive=TRUE,showWarnings=FALSE)
specs<-v4_specs();cfg<-v4_config()
make_A_frame<-function(cp) {
 d<-cp$frame
 for(sn in cp$snap){r<-v4_score_fit(sn$tg,sn$ids,lambda=6,hfa=sn$hfa)
  ix<-which(d$season==sn$season & d$cutoff==sn$cutoff)
  d$eff_home[ix]<-r$eff_power[match(d$home_id[ix],r$team_id)]
  d$eff_away[ix]<-r$eff_power[match(d$away_id[ix],r$team_id)]}
 d
}
if(mode=='develop') {
 assert(!file.exists(file.path(outdir,'design_frozen.rds')),'Design already frozen; do not rerun selection after outer access')
 sch<-setNames(lapply(2015:2022,v4_schedule),2015:2022)
 hist<-v4_history(sch);cp<-v4_components(sch,hist,c(2018,2019,2021,2022));ad<-make_A_frame(cp)
 # Baseline components contain earlier-only forecasts; immediately slice out locked years.
 old<-readRDS('cfb_data_v3/production_2026.rds')$components$uncapped_ridge6$frame %>% filter(season<=2022)
 dev<-list();pars<-list()
 for(s in 2021:2022) {
  sc<-v4_scale(cp$frame %>% filter(season<s));tr<-cp$frame %>% filter(season<s)
  blends<-list(A=v4_blend(ad %>% filter(season<s),'A',sc),B=v4_blend(tr,'B',sc))
  b<-calibrate_blend(old %>% filter(season<s),cfg)
  dev[[paste(s,'baseline')]]<-score_frame(old %>% filter(season==s),b) %>% mutate(candidate='baseline')
  for(n in c('A','B','C','D','no_prior','pre_only')){
   dev[[paste(s,n)]]<-v4_evaluate(v4_subset(cp,s),specs[[n]],sc,blends[[n]],sch) %>% mutate(candidate=n)
  }
  pars[[as.character(s)]]<-list(scale=sc,blends=blends)
 }
 d<-bind_rows(dev);base<-d %>% filter(candidate=='baseline')
 metrics<-summarize_predictions(d,'candidate');seasonal<-summarize_predictions(d,c('candidate','season'))
 paired<-bind_rows(lapply(setdiff(unique(d$candidate),'baseline'),function(n)cbind(candidate=n,v4_paired(d %>% filter(candidate==n),base))))
 eligible<-paired$candidate[paired$improved==2 & paired$high<0 & paired$candidate%in%c('A','B','C','D')]
 winner<-'baseline'
 if(length(eligible)) {
  mm<-metrics %>% filter(candidate%in%eligible);best<-min(mm$mae)
  # Interpretable convex blend first, then EB, then independent A, structural D.
  winner<-c('B','C','A','D')[c('B','C','A','D')%in%mm$candidate[mm$mae<=best+.05]][1]
 }
 primary<-winner;secondary_tested<-FALSE
 if(winner%in%c('C','D')) {
  secondary_tested<-TRUE
  for(s in 2021:2022)for(n in c('C4','C12','Ccap32','Casym','Crecent','CFCS'))
   dev[[paste(s,n)]]<-v4_evaluate(v4_subset(cp,s),specs[[n]],pars[[as.character(s)]]$scale,NULL,sch) %>% mutate(candidate=n)
  d<-bind_rows(dev);ref<-d %>% filter(candidate==primary)
  secpairs<-bind_rows(lapply(c('C4','C12','Ccap32','Casym','Crecent','CFCS'),function(n)cbind(candidate=n,v4_paired(d %>% filter(candidate==n),ref))))
  good<-secpairs$candidate[secpairs$improved==2 & secpairs$high<0 & secpairs$estimate< -.05]
  if(length(good)){m<-summarize_predictions(d %>% filter(candidate%in%good),'candidate');winner<-m$candidate[which.min(m$mae)]}
  v4_write(secpairs,'secondary_paired_vs_primary')
 }
 sc<-v4_scale(cp$frame);blends<-list(A=v4_blend(ad,'A',sc),B=v4_blend(cp$frame,'B',sc))
 freeze<-list(version='4.0.0',selected=winner,primary=primary,secondary_tested=secondary_tested,
  reported_candidates=unique(d$candidate),scale=sc,blends=blends,
  baseline=calibrate_blend(old,cfg),specs=specs,history=hist,development_parameters=pars,
  max_selection_year=2022L,created_at=Sys.time(),
  declaration_md5=unname(tools::md5sum(file.path(outdir,'PREDECLARATION.md'))),
  source_md5=unname(tools::md5sum('cfb_power_ratings_v4.R')))
 saveRDS(freeze,file.path(outdir,'design_frozen.rds'))
 saveRDS(list(cp=cp,history=hist,sch=sch),file.path(outdir,'development_components.rds'))
 v4_write(d,'development_predictions');v4_write(summarize_predictions(d,'candidate'),'development_metrics')
 v4_write(summarize_predictions(d,c('candidate','season')),'development_by_season')
 v4_write(bind_rows(lapply(setdiff(unique(d$candidate),'baseline'),function(n)cbind(candidate=n,v4_paired(d %>% filter(candidate==n),base)))),'development_paired')
 writeLines(c(paste('Selected:',winner),paste('Primary:',primary),paste('Secondary tested:',secondary_tested),
  paste('Frozen at:',freeze$created_at),paste('Maximum selection season:',2022)),file.path(outdir,'selection.txt'))
 print(summarize_predictions(d,'candidate'));print(paired);cat('FROZEN SELECTION:',winner,'\n')
}
if(mode=='outer') {
 freeze<-readRDS(file.path(outdir,'design_frozen.rds'))
 assert(freeze$max_selection_year==2022,'Invalid lock')
 assert(identical(freeze$source_md5,unname(tools::md5sum('cfb_power_ratings_v4.R'))),'Source changed after freeze')
 sch<-setNames(lapply(2015:2025,v4_schedule),2015:2025);hist<-v4_history(sch)
 cp<-v4_components(sch,hist,2023:2025)
 oldhist<-readRDS('cfb_data_v3/production_2026.rds')$components$uncapped_ridge6$history
 bp<-lapply(cp$snap,function(sn){
   r<-v4_baseline_ratings(sn,freeze,oldhist)
   te<-cp$frame %>% filter(season==sn$season,cutoff==sn$cutoff)
   te$pred_margin<-v4_predict(r,te$home_id,te$away_id,te$neutral)
   te$error<-te$pred_margin-te$actual_margin;te$abs_error<-abs(te$error);te
 })
 d<-list(baseline=bind_rows(bp) %>% mutate(candidate='baseline'))
 for(n in setdiff(freeze$reported_candidates,'baseline'))
  d[[n]]<-v4_evaluate(cp,freeze$specs[[n]],freeze$scale,freeze$blends[[n]],sch) %>% mutate(candidate=n)
 d<-bind_rows(d);base<-d %>% filter(candidate=='baseline')
 assert(all(table(d$candidate)==2398),'Unexpected outer universe; investigate without model reselection')
 saveRDS(list(predictions=d,cp=cp,history=hist),file.path(outdir,'locked_outer.rds'))
 v4_write(d,'locked_outer_predictions');v4_write(summarize_predictions(d,'candidate'),'locked_outer_metrics')
 v4_write(summarize_predictions(d,c('candidate','season')),'locked_outer_by_season')
 v4_write(bind_rows(lapply(setdiff(unique(d$candidate),'baseline'),function(n)cbind(candidate=n,v4_paired(d %>% filter(candidate==n),base)))),'locked_outer_paired')
 # The original supplied baseline is descriptive: it has a different tuning policy.
 orig<-readRDS('/Users/willcavender/Documents/Codex/2026-09-09/i-have-attached-an-r-script/outputs/local_validation/validation.rds')
 if(!is.null(orig$scored))v4_write(summarize_predictions(orig$scored),'supplied_v3_reference')
 print(summarize_predictions(d,'candidate'));cat('Selection remains:',freeze$selected,'\n')
}
