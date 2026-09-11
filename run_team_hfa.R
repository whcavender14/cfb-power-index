source('team_hfa_experiment.R')
out<-'outputs/team_hfa'
stopifnot(!file.exists(file.path(out,'design_frozen.rds')))
paths<-c('team_hfa_experiment.R','run_team_hfa.R','outputs/team_hfa/PREDECLARATION.md','cfb_power_ratings_v5.R','cfb_power_ratings_v6.R','outputs/round5/development_predictions.csv','outputs/round4/development_predictions.csv','outputs/round4/design_frozen.rds')
manifest<-data.frame(path=paths,md5=unname(tools::md5sum(paths)))
write.csv(manifest,file.path(out,'pre_fit_manifest.csv'),row.names=FALSE)
saveRDS(list(manifest=manifest,at=Sys.time()),file.path(out,'pre_fit_lock.rds'))
b<-hfa_read('outputs/round5/development_predictions.csv')
old<-read.csv('outputs/round4/development_predictions.csv');old<-old[old$candidate=='EB_features',]
stopifnot(setequal(b$game_id,old$game_id),max(abs(b$pred_margin-old$pred_margin[match(b$game_id,old$game_id)]))<1e-9)
names_order<-c('global','ridge','eb');pred<-list();pars<-list();audits<-list();cv<-list()
for(s in c(2019,2021,2022,2023)){
 message('Earlier-only parameters for ',s)
 ridge<-hfa_tune(b,s);eb<-hfa_eb(b,s);pars[[as.character(s)]]<-list(global=Inf,ridge=ridge$lambda,eb=eb$lambda,eb_fit=eb,ridge_reason=ridge$reason)
 if(nrow(ridge$cv))cv[[as.character(s)]]<-cbind(target_season=s,ridge$cv)
 if(s==2023)next
 for(n in names_order){z<-hfa_score(b[b$season==s,],b,pars[[as.character(s)]][[n]])
  pred[[paste(n,s)]]<-mutate(z$predictions,candidate=n);audits[[paste(n,s)]]<-z$audit}
}
d<-bind_rows(pred);baseline<-d[d$candidate=='global',]
stopifnot(identical(baseline$pred_margin,b$pred_margin[match(baseline$game_id,b$game_id)]))
ledger<-bind_rows(lapply(names_order,function(n)cbind(candidate=n,v6_advance(d[d$candidate==n,],baseline))))
ledger$passes[ledger$candidate=='global']<-FALSE
win<-'global';good<-ledger[ledger$passes,];if(nrow(good))win<-names_order[names_order%in%good$candidate[good$mae<=min(good$mae)+.05]][1]
freeze<-list(selected=win,parameters=pars[['2023']],fold_parameters=pars,max_selection_year=2022,manifest=manifest,created_at=Sys.time())
write.csv(ledger,file.path(out,'candidate_ledger.csv'),row.names=FALSE)
write.csv(d,file.path(out,'development_predictions.csv'),row.names=FALSE)
write.csv(hfa_metrics(d),file.path(out,'development_metrics.csv'),row.names=FALSE)
write.csv(bind_rows(cv),file.path(out,'nested_penalty_validation.csv'),row.names=FALSE)
saveRDS(audits,file.path(out,'development_fold_audits.rds'))
saveRDS(freeze,file.path(out,'design_frozen.rds'))
print(ledger)
# Conditional inputs are first opened only after the development decision is frozen.
cnd<-hfa_read('outputs/round5/conditional_predictions.csv');history<-bind_rows(b,cnd)
cc<-list();ca<-list()
for(n in names_order){z<-hfa_score(cnd,history,freeze$parameters[[n]]);cc[[n]]<-mutate(z$predictions,candidate=n);ca[[n]]<-z$audit}
c<-bind_rows(cc)
write.csv(c,file.path(out,'conditional_predictions.csv'),row.names=FALSE)
write.csv(hfa_metrics(c),file.path(out,'conditional_metrics.csv'),row.names=FALSE)
write.csv(bind_rows(lapply(names_order,function(n)cbind(candidate=n,v6_advance(c[c$candidate==n,],c[c$candidate=='global',])))),file.path(out,'conditional_comparisons.csv'),row.names=FALSE)
saveRDS(ca,file.path(out,'conditional_fold_audits.rds'))
# Descriptive values use development data only, available strictly before 2023.
g<-v4_schedule(2022);team_names<-unique(bind_rows(transmute(g,team_id=home_id,team=home_team),transmute(g,team_id=away_id,team=away_team)))
frozen4<-readRDS('outputs/round4/design_frozen.rds');global<-frozen4$parameters$EB_features$scale$hfa
ex<-bind_rows(lapply(c('ridge','eb'),function(n){f<-hfa_fit(b,as.POSIXct('2023-01-01',tz='UTC'),freeze$parameters[[n]]);t<-f$table
 t$team_HFA<-global+t$deviation;t$global_HFA<-global;t$candidate<-n
 away<-b[b$available_at<as.POSIXct('2023-01-01',tz='UTC') & !b$neutral,]
 av<-aggregate(pred_margin-actual_margin~away_id,away,mean);names(av)<-c('team_id','away_mean_residual')
 left_join(left_join(t,team_names,by='team_id'),av,by='team_id')}))
write.csv(ex,file.path(out,'team_estimates_end2022.csv'),row.names=FALSE)
write.csv(data.frame(path='outputs/round5/conditional_predictions.csv',md5=unname(tools::md5sum('outputs/round5/conditional_predictions.csv'))),file.path(out,'conditional_manifest.csv'),row.names=FALSE)
stopifnot(all(unname(tools::md5sum(manifest$path))==manifest$md5))
writeLines(capture.output(sessionInfo()),file.path(out,'sessionInfo.txt'))
