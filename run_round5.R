suppressPackageStartupMessages(source('cfb_v6_operations.R'))
args<-commandArgs(TRUE);mode<-if(length(args))args[1] else 'develop'
modelpaths<-c('cfb_power_ratings_v4.R','cfb_power_ratings_v5.R','cfb_v5_operations.R','cfb_power_ratings_v6.R','cfb_v6_operations.R','run_round5.R','audit_round5.R','outputs/round5/ROUND5_PREDECLARATION.md','outputs/round5/FEATURE_AUDIT.md')
if(mode=='develop'){
 assert(!file.exists(file.path(v6_dir,'design_frozen.rds')),'Already frozen: reselection prohibited')
 sourcepaths<-c(read.csv(file.path(v6_dir,'source_manifest.csv'))$path,file.path(v6_dir,'inputs.rds'))
 mf<-v6_manifest(modelpaths);sf<-v6_manifest(sourcepaths);v6_write(rbind(mf,sf),'pre_fit_manifest');saveRDS(list(model=mf,source=sf,at=Sys.time(),config=v6_config()),file.path(v6_dir,'pre_fit_lock.rds'))
 bundle<-readRDS('outputs/round4/features.rds');input<-readRDS(file.path(v6_dir,'inputs.rds'));v6_guard(input)
 sch<-setNames(lapply(2015:2022,v4_schedule),2015:2022);history<-v4_history(sch)
 base<-v4_components(sch,history,c(2018,2019,2021,2022));inc<-v5_components(base,history,bundle$features,'full')
 cps<-list(v5_EB_features=inc);blocks<-list(v5_EB_features=character(),efficiency_prior_EB='efficiency',special_teams_prior_EB='field',multi_year_prior_EB='multi',current_efficiency_EB=character())
 # Cache includes complete model/source, transform, grid and configuration identity.
 for(n in c('efficiency_prior_EB','special_teams_prior_EB','multi_year_prior_EB')){
 message('Building frozen family ',n);key<-key_of(list(mf,sf,v6_config(),n));cfg<-list(cache_dir=file.path(v6_dir,'cache'));cps[[n]]<-cache(cfg,key,v6_components(base,history,bundle$features,blocks[[n]],input$extra))
 }
 cps$current_efficiency_EB<-inc;cur<-setNames(lapply(c(2019,2021,2022,2023),v6_current_model,advanced=input$advanced),c(2019,2021,2022,2023))
 pred<-list();ratings<-list();parameters<-list();finalpars<-list();incpars<-list()
 for(s in c(2019,2021,2022,2023))incpars[[as.character(s)]]<-v5_fit_parameters(inc,base,v5_candidates()$EB_features,s)
 for(n in names(cps)){
 message('Scoring development ',n)
 for(s in v6_config()$development){p<-if(n%in%c('v5_EB_features','current_efficiency_EB'))incpars[[as.character(s)]] else v6_calibrate(cps[[n]],inc,s,incpars[[as.character(s)]])
 z<-v6_evaluate(v4_subset(cps[[n]],s),p,history,sch,if(n=='current_efficiency_EB')cur else NULL,input$advanced,incpars[[as.character(s)]])
 pred[[paste(n,s)]]<-mutate(z$predictions,candidate=n);ratings[[paste(n,s)]]<-mutate(z$ratings,candidate=n);parameters[[paste(n,s)]]<-p}
 finalpars[[n]]<-if(n%in%c('v5_EB_features','current_efficiency_EB'))incpars[['2023']] else v6_calibrate(cps[[n]],inc,2023,incpars[['2023']])
 }
 d<-bind_rows(pred);b<-d %>% filter(candidate=='v5_EB_features')
 old<-read.csv('outputs/round4/development_predictions.csv');old<-old[old$candidate=='EB_features',];assert(setequal(b$game_id,old$game_id),'Incumbent universe mismatch');assert(max(abs(b$pred_margin-old$pred_margin[match(b$game_id,old$game_id)]))<1e-9,'Incumbent reproduction failed')
 # Full-family membership is learned from earlier prediction folds only.
 gates<-list();fullblocks<-list()
 for(s in c(2019,2021,2022,2023)){
 passed<-character()
 for(n in c('efficiency_prior_EB','special_teams_prior_EB','multi_year_prior_EB','current_efficiency_EB')){
 ok<-v6_gate(d[d$candidate==n,],b,s);gates[[length(gates)+1]]<-data.frame(target=s,component=n,passes=ok,max_gate_season=if(any(b$season<s))max(b$season[b$season<s]) else NA_integer_);if(ok&&n!='current_efficiency_EB')passed<-c(passed,blocks[[n]])}
 fullblocks[[as.character(s)]]<-passed
 }
 for(n in c('full_preseason_EB','full_preseason_current_efficiency_EB')){
 cc<-inc;cc$prior_fits<-list()
 for(s in c(2018,2019,2021,2022)){
 bb<-fullblocks[[as.character(s)]]%or%character();if(length(bb)){one<-v6_components(v4_subset(base,s),history,bundle$features,bb,input$extra);cc$frame[cc$frame$season==s,]<-one$frame;cc$snap[names(one$snap)]<-one$snap;cc$prior_fits[[as.character(s)]]<-one$prior_fits[[as.character(s)]]}}
 cps[[n]]<-cc
 for(s in v6_config()$development){usecur<-n=='full_preseason_current_efficiency_EB'&&length(fullblocks[[as.character(s)]])>0&&v6_gate(d[d$candidate=='current_efficiency_EB',],b,s)
 # Combined family is incumbent unless BOTH nested gates pass.
 usecp<-if(n=='full_preseason_current_efficiency_EB'&&!usecur)inc else cc
 p<-v6_calibrate(usecp,inc,s,incpars[[as.character(s)]])
 z<-v6_evaluate(v4_subset(usecp,s),p,history,sch,if(usecur)cur else NULL,input$advanced,incpars[[as.character(s)]])
 pred[[paste(n,s)]]<-mutate(z$predictions,candidate=n);ratings[[paste(n,s)]]<-mutate(z$ratings,candidate=n);parameters[[paste(n,s)]]<-p}
 finalpars[[n]]<-v6_calibrate(cc,inc,2023,incpars[['2023']]);blocks[[n]]<-fullblocks[['2023']]
 }
 d<-bind_rows(pred);metrics<-bind_rows(lapply(unique(d$candidate),function(n)cbind(candidate=n,v6_advance(d[d$candidate==n,],b))))
 metrics$passes[metrics$candidate=='v5_EB_features']<-FALSE
 for(n in c('full_preseason_EB','full_preseason_current_efficiency_EB')){
 comp<-names(blocks)[vapply(names(blocks),function(k)length(blocks[[k]])==1&&all(blocks[[k]]%in%blocks[[n]]),logical(1))];comp<-intersect(comp,c('efficiency_prior_EB','special_teams_prior_EB','multi_year_prior_EB'))
 if(n=='full_preseason_current_efficiency_EB')comp<-c(comp,'current_efficiency_EB')
 metrics$passes[metrics$candidate==n]<-metrics$passes[metrics$candidate==n]&&length(blocks[[n]])>0&&all(metrics$passes[match(comp,metrics$candidate)])
 }
 win<-'v5_EB_features';good<-metrics[metrics$passes,];if(nrow(good)){eligible<-good$candidate[good$mae<=min(good$mae)+.05];win<-v6_candidates()[v6_candidates()%in%eligible][1]}
 ledger<-left_join(data.frame(candidate=v6_candidates(),simplicity_order=seq_along(v6_candidates())),metrics,by='candidate')
 ledger$disposition<-ifelse(is.na(ledger$n),'not_estimable_source_or_history',ifelse(ledger$candidate==win,'selected',ifelse(ledger$passes,'passed_not_selected','did_not_pass')))
 ledger$formula<-'power=off-def; precision4 joint score update; additive HFA';ledger$inputs<-vapply(ledger$candidate,function(n)paste(c('v5 full',blocks[[n]],if(grepl('current_efficiency',n))'25% success score measurement'),collapse=';'),character(1))
 ledger$coverage<-'same FBS game IDs; added atomic unit block or incumbent fallback';ledger$provenance_class<-'historical_vintage_unverified';ledger$training_seasons<-'2015 history; 2016+ unit targets except2020; expanding <target, <=2022';ledger$game_universe_hash<-key_of(sort(b$game_id));ledger$parameters<-vapply(ledger$candidate,function(n)if(is.null(finalpars[[n]]))NA_character_ else paste('s',finalpars[[n]]$scale$scale,'hfa',finalpars[[n]]$scale$hfa,'precision4'),character(1));ledger$optimizer_diagnostics<-'per-fold models, losses, QR audit and CV in development_results.rds and diagnostic CSVs'
 probs<-list();d$p_home<-NA_real_
 for(n in unique(d$candidate))for(s in unique(d$season)){ii<-which(d$candidate==n&d$season==s);m<-v6_probability_fit(d[d$candidate==n,],s);probs[[paste(n,s)]]<-m;d$p_home[ii]<-v6_probability(d[ii,],m)}
 finalprob<-setNames(lapply(unique(d$candidate),function(n)v6_probability_fit(d[d$candidate==n,],2023)),unique(d$candidate))
 saveRDS(list(predictions=d,ratings=bind_rows(ratings),parameters=parameters,incpars=incpars,cps=cps,history=history,current=cur,probabilities=probs),file.path(v6_dir,'development_results.rds'))
 v6_write(d,'development_predictions');v6_write(ledger,'candidate_ledger');v6_write(bind_rows(gates),'nested_component_gates')
 freeze<-list(version='6.0.0',selected=win,selected_blocks=blocks[[win]],selected_current=grepl('current_efficiency',win),blocks=blocks,parameters=finalpars,incumbent_parameter=incpars[['2023']],current_model=cur[['2023']],probability=finalprob,feature_hash=key_of(list(bundle$hash,input$extra)),max_selection_year=2022L,model_manifest=mf,source_manifest=sf,config=v6_config(),created_at=Sys.time())
 v6_verify(mf);v6_verify(sf);saveRDS(freeze,file.path(v6_dir,'design_frozen.rds'));v6_write(v6_manifest(c(file.path(v6_dir,c('development_predictions.csv','design_frozen.rds','candidate_ledger.csv')))),'prediction_freeze_manifest');print(ledger[,c('candidate','mae','estimate','block_high','passes','disposition')])
}
if(mode=='conditional'){
 f<-v6_frozen();assert(!file.exists(file.path(v6_dir,'conditional_results.rds')),'Conditional scoring already exists')
 input<-readRDS(file.path(v6_dir,'conditional_inputs.rds'));bundle<-readRDS('outputs/round4/features.rds');sch<-setNames(lapply(2015:2025,v4_schedule),2015:2025);history<-v4_history(sch);base<-v4_components(sch,history,2023:2025);inc<-v5_components(base,history,bundle$features,'full');out<-list();rr<-list();cps<-list(v5_EB_features=inc)
 for(n in names(f$parameters)){
 message('Frozen secondary conditional ',n);bb<-f$blocks[[n]];cc<-if(!length(bb))inc else v6_components(base,history,bundle$features,bb,input$extra);cps[[n]]<-cc
 cur<-if(grepl('current_efficiency',n))setNames(rep(list(f$current_model),3),2023:2025) else NULL
 if(n=='full_preseason_current_efficiency_EB'){gate<-read.csv(file.path(v6_dir,'nested_component_gates.csv'));ok<-gate$passes[gate$target==2023&gate$component=='current_efficiency_EB'];if(!length(bb)||!isTRUE(ok)){cc<-inc;cur<-NULL}}
 z<-v6_evaluate(cc,f$parameters[[n]],history,sch,cur,input$advanced,f$incumbent_parameter);z$predictions$candidate<-n;z$predictions$p_home<-v6_probability(z$predictions,f$probability[[n]]);out[[n]]<-z$predictions;rr[[n]]<-mutate(z$ratings,candidate=n)
 }
 d<-bind_rows(out);saveRDS(list(predictions=d,ratings=bind_rows(rr),cps=cps,history=history),file.path(v6_dir,'conditional_results.rds'));v6_write(d,'conditional_predictions');v6_write(v6_manifest(c(Sys.glob('outputs/round5/raw/*202[3-5].rds'),'outputs/round5/conditional_inputs.rds','outputs/round5/conditional_predictions.csv')),'conditional_input_prediction_manifest')
}
if(mode=='prospective'){
 r<-v6_build();tag<-format(Sys.time(),'%Y%m%dT%H%M%S',tz='UTC');saveRDS(r,file.path(v6_dir,paste0('ratings_2026_',tag,'.rds')));v6_write(r,paste0('ratings_2026_',tag));p<-v6_archive_upcoming(r,file.path(v6_dir,'prospective',paste0('predictions_',tag,'.csv')));cat(nrow(p),'future games archived\n')
}
