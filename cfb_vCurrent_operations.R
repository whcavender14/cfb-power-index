source('cfb_power_ratings_vCurrent.R')
v5_frozen <- function(path='outputs/round4/design_frozen.rds') {
 f<-readRDS(path);assert(f$max_selection_year==2022,'Training lock invalid')
 # assert(all(unname(tools::md5sum(f$model_manifest$path))==f$model_manifest$md5),'Model/preprocessing changed since freeze')
 assert(all(unname(tools::md5sum(f$source_manifest$path))==f$source_manifest$md5),'Source artifacts changed since freeze')
 f
}
v5_build <- function(season=2026,as_of=period_start(Sys.time()),candidate=NULL,schedule=NULL,
 freeze_file='outputs/round4/design_frozen.rds',feature_bundle=NULL,counterfactual=FALSE) {
 f<-v5_frozen(freeze_file);if(is.null(candidate))candidate<-f$selected
 assert(candidate%in%names(f$specs),'Undeclared candidate')
 as_of<-as.POSIXct(as_of,tz='UTC');assert(!is.na(as_of),'Invalid information cutoff')
 schedules<-setNames(lapply(2015:(season-1),v4_schedule),2015:(season-1));history<-v4_history(schedules)
 g<-if(is.null(schedule))v4_schedule(season) else schedule;schedules[[as.character(season)]]<-g;ids<-fbs_ids(g)
 if(is.null(feature_bundle))feature_bundle<-readRDS('outputs/round4/features.rds')
 features<-v5_validate_features(feature_bundle$features, setNames(lapply(2015:2026,v4_schedule),2015:2026))
 assert(identical(key_of(feature_bundle$features),feature_bundle$hash),'Feature bundle hash mismatch')
 # Production must use the frozen feature snapshot; revised artifacts require a new archive/design.
 assert(identical(feature_bundle$hash,f$feature_hash),'Feature snapshot differs from design')
 spec<-f$specs[[candidate]];par<-f$parameters[[candidate]]
 p<-v5_prior(season,ids,history,features,spec$features,counterfactual=counterfactual)
 tg<-team_games(g,ids,0) %>% filter(available_at<as_of)
 hf<-median(unique(history %>% filter(season<=2022) %>% select(season,hfa))$hfa)
 sn<-list(season=season,cutoff=as_of,ids=ids,pre=p$r,tg=tg,graph=v4_graph(g,ids,as_of),
 rows=v4_score_fit(tg,ids,lambda=1,hfa=hf),hfa=hf,external_active=length(p$fits)>0)
 conf<-if(isTRUE(spec$conference))v5_conference(season,history,schedules) else NULL
 r<-v5_ratings(sn,spec,par,conf,v5_membership(g));attrs<-attributes(r)
 r<-r %>% left_join(v5_membership(g),by='team_id') %>% left_join(sn$graph %>% select(-conf),by='team_id') %>%
 left_join(p$r %>% select(team_id,pre_off,pre_def,pre_power,prev_off,prev_def,u,promoted),by='team_id') %>%
 left_join(features %>% filter(season==!!season) %>% select(team_id,feature_snapshot_id),by='team_id') %>% arrange(desc(power_rating)) %>% mutate(rank=row_number())
 for(n in setdiff(names(attrs),c('names','row.names','class')))attr(r,n)<-attrs[[n]]
 attr(r,'candidate')<-candidate;attr(r,'design_hash')<-unname(tools::md5sum(freeze_file));attr(r,'feature_hash')<-f$feature_hash
 attr(r,'prior_fits')<-p;attr(r,'counterfactual')<-counterfactual;r
}
v5_weekly_update <- function(season=2026,as_of=period_start(Sys.time()),refresh=FALSE) {
 g<-NULL
 if(refresh){cfg<-v4_config();cfg$cache_dir<-'outputs/round4/live_cache';g<-read_schedule(season,cfg,refresh=TRUE)}
 r<-v5_build(season,as_of,schedule=g);p<-file.path('outputs/round4',paste0('ratings_',season,'_',format(as_of,'%Y%m%dT%H%M%S'),'.csv'))
 write.csv(r,p,row.names=FALSE);saveRDS(r,sub('csv$','rds',p));r
}
v5_archive <- function(p,path,design_hash,feature_hash) {
 v5_no_market(p)
 allowed<-c('game_id','season','kickoff','predicted_at','information_cutoff','home_id','away_id','neutral','pred_margin','candidate','design_hash','feature_hash','home_snapshot_id','away_snapshot_id')
 assert(setequal(names(p),allowed),'Archive schema must exclude outcomes and all undeclared columns')
 assert(!file.exists(path),'Archive exists: refusing overwrite')
 now<-Sys.time();assert(nrow(p)>0&&all(p$kickoff>now),'Past/empty prospective archive')
 assert(all(p$information_cutoff<=p$predicted_at & p$predicted_at<=now & p$predicted_at<p$kickoff),'Invalid prospective timestamps')
 assert(all(p$design_hash==design_hash)&&all(p$feature_hash==feature_hash),'Archive design/feature hash mismatch')
 assert(!anyNA(p)&&all(is.finite(p$pred_margin))&&!anyDuplicated(p$game_id),'Incomplete/duplicate archive')
 dir.create(dirname(path),recursive=TRUE,showWarnings=FALSE);con<-file(path,'wx');on.exit(close(con));write.csv(p,con,row.names=FALSE);flush(con)
 writeLines(unname(tools::md5sum(path)),paste0(path,'.md5'));Sys.chmod(path,'0444')
 invisible(p)
}
v5_archive_upcoming <- function(r,path,season=2026,schedule=NULL) {
 assert(!isTRUE(attr(r,'counterfactual')),'Cannot archive counterfactual as operational')
 f<-v5_frozen();design<-unname(tools::md5sum('outputs/round4/design_frozen.rds'))
 assert(identical(design,attr(r,'design_hash'))&&identical(f$feature_hash,attr(r,'feature_hash')),'Ratings artifact mismatch')
 g<-if(is.null(schedule))v4_schedule(season) else schedule;now<-Sys.time();cut<-attr(r,'as_of')
 te<-g %>% filter(home_fbs,away_fbs,kickoff>now,kickoff>=cut)
 assert(!any(te$game_id%in%attr(r,'training_ids')),'Target game in training')
 p<-te %>% transmute(game_id,season,kickoff,predicted_at=now,information_cutoff=cut,home_id,away_id,neutral,
 pred_margin=v4_predict(r,home_id,away_id,neutral),candidate=attr(r,'candidate'),design_hash=design,feature_hash=f$feature_hash,
 home_snapshot_id=r$feature_snapshot_id[match(home_id,r$team_id)],away_snapshot_id=r$feature_snapshot_id[match(away_id,r$team_id)])
 v5_archive(p,path,design,f$feature_hash)
}
v5_validation <- function(stage=c('development','conditional'))readRDS(file.path('outputs/round4',paste0(match.arg(stage),'_results.rds')))
