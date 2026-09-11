suppressPackageStartupMessages(source('cfb_v5_operations.R'))
args<-commandArgs(TRUE);mode<-if(length(args))args[1] else 'audit'
model_paths<-c('cfb_power_ratings_v4.R','cfb_power_ratings_v5.R','cfb_v5_operations.R','run_round4.R','outputs/round4/PREDECLARATION.md','outputs/round4/FEATURE_AUDIT.md')
source_paths<-c(Sys.glob('cfb_data_v3/raw_schedule_*.rds'),Sys.glob('cfb_data_v2/talent_*.rds'),Sys.glob('cfb_data_v2/returning_*.rds'),Sys.glob('cfb_data_v2/coaches_*.rds'),Sys.glob('cfb_data_v2/portal_*.rds'))
if(mode=='audit') {
 sch<-setNames(lapply(2015:2026,v4_schedule),2015:2026);b<-v5_ingest(sch)
 v5_write(v5_hashes(c(model_paths,source_paths)),'input_manifest');capture.output(sessionInfo(),file='outputs/round4/sessionInfo.txt');print(b$coverage)
}
if(mode=='develop') {
 assert(!file.exists('outputs/round4/design_frozen.rds'),'Already frozen; reselection prohibited')
 v5_write(v5_hashes(c(model_paths,source_paths,'outputs/round4/features.rds')),'pre_selection_manifest')
 specs<-v5_candidates();bundle<-readRDS('outputs/round4/features.rds')
 sch<-setNames(lapply(2015:2022,v4_schedule),2015:2022);hist<-v4_history(sch)
 cp<-v4_components(sch,hist,c(2018,2019,2021,2022));families<-unique(vapply(specs,`[[`,character(1),'features'));cps<-list(none=cp)
 for(fam in setdiff(families,'none')){message('Prior family ',fam);tag<-v5_key(c(v5_config(),family=fam),bundle$raw_hashes,bundle$hash,bundle$source_versions,v5_hashes(model_paths));cfg<-v4_config();cfg$cache_dir<-'outputs/round4/cache';cps[[fam]]<-cache(cfg,tag,v5_components(cp,hist,bundle$features,fam))}
 dev<-list();ratings<-list();params<-list();frozenpars<-list()
 for(n in names(specs)){
  message('Development candidate ',n);spec<-specs[[n]];cc<-cps[[spec$features]]
  for(s in v5_config()$development) {
   par<-v5_fit_parameters(cc,cp,spec,s);params[[paste(n,s)]]<-par
   z<-v5_evaluate(v4_subset(cc,s),spec,par,hist,sch)
   dev[[paste(n,s)]]<-mutate(z$predictions,candidate=n);ratings[[paste(n,s)]]<-mutate(z$ratings,candidate=n)
  }
  frozenpars[[n]]<-v5_fit_parameters(cc,cp,spec,2023)
 }
 d<-bind_rows(dev);b<-d %>% filter(candidate=='B');metrics<-d %>% group_by(candidate) %>% group_modify(~v5_calibration(.x)) %>% ungroup()
 pairs<-bind_rows(lapply(names(specs),function(n)cbind(candidate=n,v5_paired(d %>% filter(candidate==n),b))))
 ledger<-left_join(metrics,pairs,by='candidate');bs<-ledger$slope[ledger$candidate=='B']
 ledger$passes<-ledger$estimate<= -.05 & abs(ledger$slope-1)<=abs(bs-1)+.05 & ledger$improved>=2 & ledger$season_high<0 & ledger$block_high<0 & vapply(specs[ledger$candidate],`[[`,logical(1),'eligible')
 cu<-v5_paired(d %>% filter(candidate=='Conference'),d %>% filter(candidate=='Uncertainty'))
 cs<-ledger$slope[ledger$candidate=='Conference'];us<-ledger$slope[ledger$candidate=='Uncertainty']
 ledger$passes[ledger$candidate=='Conference']<-ledger$passes[ledger$candidate=='Conference']&&cu$estimate<= -.05&&cu$improved>=2&&cu$season_high<0&&cu$block_high<0&&abs(cs-1)<=abs(us-1)+.05
 winner<-'B';good<-ledger %>% filter(passes)
 if(nrow(good)){eligible<-good$candidate[good$mae<=min(good$mae)+.05];winner<-names(specs)[names(specs)%in%eligible][1]}
 ledger$selection_reason<-ifelse(ledger$candidate==winner,'Selected by predeclared development rule',ifelse(ledger$passes,'Passed; simplicity/MAE ordering','Did not pass all advancement requirements / diagnostic only'))
 ledger$feature_family<-vapply(specs[ledger$candidate],`[[`,character(1),'features');ledger$provenance_class<-ifelse(ledger$feature_family=='none','score_history','historical_vintage_unverified')
 ledger$training_seasons<-'earlier only; 2015 burn-in; exclude 2020 responses; maximum 2022';ledger$validation_seasons<-'2019,2021,2022';ledger$game_universe_hash<-key_of(sort(b$game_id))
 ledger$formula<-vapply(specs[ledger$candidate],function(x)if(x$kind=='B')'O=gamma*(n/(n+k)*eO+k/(n+k)*s*pO); D analogous; center; margin=O-D difference+HFA' else 'score SSE +4 prior precision; joint matrix solve; optional general uncertainty/conf hierarchy',character(1))
 ledger$parameters<-vapply(frozenpars[ledger$candidate],function(p)paste('s=',p$scale$scale,'HFA=',p$scale$hfa,'k=',p$blend$k,'gamma=',p$gamma),character(1));ledger$optimizer_status<-'bracketed scalar profiles; direct ridge/EB linear solves'
 freeze<-list(version='5.0.0',selected=winner,specs=specs,parameters=frozenpars,max_selection_year=2022L,
 feature_hash=bundle$hash,model_manifest=v5_hashes(model_paths),source_manifest=v5_hashes(source_paths),created_at=Sys.time(),config=v5_config())
 saveRDS(list(predictions=d,ratings=bind_rows(ratings),parameters=params,cps=cps,history=hist), 'outputs/round4/development_results.rds')
 v5_write(d,'development_predictions');v5_write(ledger,'candidate_ledger');v5_write(cu,'conference_vs_uncertainty')
 v5_write(d %>% group_by(candidate,season) %>% group_modify(~v5_calibration(.x)) %>% ungroup(),'development_by_season')
 saveRDS(freeze,'outputs/round4/design_frozen.rds');writeLines(paste('Selected:',winner),'outputs/round4/selection.txt');print(ledger %>% select(candidate,mae,slope,estimate,block_low,block_high,passes));cat('Selected:',winner,'\n')
}
if(mode=='conditional') {
 f<-v5_frozen();assert(!file.exists('outputs/round4/conditional_results.rds'),'Conditional results already exist')
 v5_write(v5_hashes(c(model_paths,source_paths,'outputs/round4/features.rds','outputs/round4/design_frozen.rds')),'pre_conditional_manifest')
 b<-readRDS('outputs/round4/features.rds');sch<-setNames(lapply(2015:2025,v4_schedule),2015:2025);hist<-v4_history(sch)
 cp<-v4_components(sch,hist,2023:2025);cps<-list(none=cp)
 for(fam in setdiff(unique(vapply(f$specs,`[[`,character(1),'features')),'none'))cps[[fam]]<-v5_components(cp,hist,b$features,fam)
 out<-list();rr<-list()
 for(n in names(f$specs)){message('Secondary conditional candidate ',n);z<-v5_evaluate(cps[[f$specs[[n]]$features]],f$specs[[n]],f$parameters[[n]],hist,sch);out[[n]]<-mutate(z$predictions,candidate=n);rr[[n]]<-mutate(z$ratings,candidate=n)}
 d<-bind_rows(out);base<-d %>% filter(candidate=='B');for(n in names(out))assert(setequal(base$game_id,out[[n]]$game_id),'Conditional universe changed')
 saveRDS(list(predictions=d,ratings=bind_rows(rr),cps=cps,history=hist),'outputs/round4/conditional_results.rds')
 v5_write(d,'conditional_predictions');v5_write(d %>% group_by(candidate) %>% group_modify(~v5_calibration(.x)) %>% ungroup(),'conditional_metrics')
 v5_write(d %>% group_by(candidate,season) %>% group_modify(~v5_calibration(.x)) %>% ungroup(),'conditional_by_season')
 cat('Selection remains',f$selected,'; secondary conditional only\n')
}
