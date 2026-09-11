source('cfb_power_ratings_v6.R')
v6_frozen <- function(path=file.path(v6_dir,'design_frozen.rds')) {
 f<-readRDS(path);assert(f$max_selection_year==2022,'Selection year lock');v6_guard(f$config);v6_verify(f$model_manifest);v6_verify(f$source_manifest);f
}
v6_build <- function(season=2026,as_of=period_start(Sys.time()),schedule=NULL) {
 f<-v6_frozen();assert(identical(as.numeric(as_of),as.numeric(period_start(as_of))),'Operational cutoff must be Monday UTC')
 assert(as_of<=Sys.time(),'Future operational cutoff')
 if(f$selected=='v5_EB_features'){
 r<-v5_build(season,as_of,schedule=schedule)
 }else{
 sch<-setNames(lapply(2015:(season-1),v4_schedule),2015:(season-1));history<-v4_history(sch);g<-if(is.null(schedule))v4_schedule(season) else schedule;ids<-fbs_ids(g)
 bundle<-readRDS('outputs/round4/features.rds');input<-readRDS(file.path(v6_dir,'conditional_inputs.rds'));v6_guard(input)
 p<-v6_prior(season,ids,history,bundle$features,f$selected_blocks,input$extra)
 inc<-p$incumbent%or%p;tg<-team_games(g,ids,0) %>% filter(available_at<as_of);hf<-median(history$hfa[history$season<=2022])
 sn<-list(season=season,cutoff=as_of,ids=ids,pre=p$r,tg=tg,graph=v4_graph(g,ids,as_of),rows=v4_score_fit(tg,ids,lambda=1,hfa=hf),hfa=hf,external_active=length(inc$fits)>0,test=g[g$kickoff>=as_of,])
 if(f$selected_current){assert(file.exists(file.path(v6_dir,'operational_advanced.rds')),'Current efficiency requires separately audited operational advanced input');ad<-readRDS(file.path(v6_dir,'operational_advanced.rds'));v6_guard(ad);sn<-v6_current_snapshot(sn,ad,f$current_model)}
 par<-if(length(f$selected_blocks)&&!length(p$fits))f$incumbent_parameter else f$parameters[[f$selected]]
 r<-v5_ratings(sn,v5_candidates()$EB_features,par)
 attrs<-attributes(r);r<-left_join(r,v5_membership(g),by='team_id');for(n in setdiff(names(attrs),c('names','row.names','class')))attr(r,n)<-attrs[[n]]
 r$feature_snapshot_id<-vapply(seq_len(nrow(r)),function(i)key_of(list(team_id=r$team_id[i],prior=p$r[i,],input_hash=f$feature_hash)),character(1))
 }
 attr(r,'candidate')<-f$selected;attr(r,'design_hash')<-unname(tools::md5sum(file.path(v6_dir,'design_frozen.rds')));attr(r,'feature_hash')<-f$feature_hash
 r
}
v6_archive <- function(p,path,design_hash,feature_hash,training_ids=character()) {
 v6_guard(p);assert(!any(p$game_id%in%training_ids),'Archive target in training')
 assert(all(as.numeric(p$information_cutoff)==as.numeric(period_start(p$information_cutoff))),'Non-Monday archive cutoff')
 v5_archive(p,path,design_hash,feature_hash)
}
v6_archive_upcoming <- function(r,path,season=2026,schedule=NULL) {
 f<-v6_frozen();design<-unname(tools::md5sum(file.path(v6_dir,'design_frozen.rds')))
 assert(identical(design,attr(r,'design_hash'))&&identical(f$feature_hash,attr(r,'feature_hash')),'Archive rating hash mismatch')
 g<-if(is.null(schedule))v4_schedule(season) else schedule;now<-Sys.time();cut<-attr(r,'as_of')
 te<-g %>% filter(home_fbs,away_fbs,kickoff>now,kickoff>=cut)
 p<-te %>% transmute(game_id,season,kickoff,predicted_at=now,information_cutoff=cut,home_id,away_id,neutral,pred_margin=v4_predict(r,home_id,away_id,neutral),candidate=f$selected,design_hash=design,feature_hash=f$feature_hash,home_snapshot_id=r$feature_snapshot_id[match(home_id,r$team_id)],away_snapshot_id=r$feature_snapshot_id[match(away_id,r$team_id)])
 v6_archive(p,path,design,f$feature_hash,attr(r,'training_ids'));p
}
# Player/state ingress is disabled from fitting until historical coverage audit passes.
v6_player_validate <- function(x,cutoff,target_season) {
 v6_guard(x);required<-c('player_id','season','production_season','source_team_id','destination_team_id','state_available_before_cutoff','state_cutoff','unit','production','division','resolution_status')
 assert(all(required%in%names(x)),'Player schema incomplete')
 assert(!anyNA(x$player_id)&&all(nzchar(x$player_id)),'Resolved player ID required')
 assert(all(x$season==target_season & x$production_season==target_season-1),'Wrong production year')
 assert(all(x$state_available_before_cutoff & x$state_cutoff<cutoff),'Invalid preseason state')
 assert(all(x$resolution_status%in%c('resolved_id','manual_override')),'Unresolved player')
 assert(!anyDuplicated(paste(x$season,x$player_id,x$unit)),'Player returning/incoming double count')
 assert(all(x$division%in%c('fbs','fcs','lower')),'Unknown cross-division translation')
 assert(all(is.finite(x$production)),'Unknown production cannot be zero filled')
 x$translated_production<-x$production*ifelse(x$division=='fbs',1,.5);x
}
v6_qb_validate <- function(x) {
 v6_guard(x);states<-c('unknown_qb','returning_qb','transfer_qb_with_experience','transfer_qb_limited_experience','new_or_unknown_qb')
 assert(all(x$state%in%states),'Unknown QB state label');assert(all(is.na(x$quality[x$state%in%c('unknown_qb','new_or_unknown_qb')])),'Unknown QB quality cannot be zero');x
}
v6_coordinator_validate <- function(x,cutoff) {
 v6_guard(x);allowed<-c('season','team_id','coordinator_id','unit','assignment_at','continuity','tenure','season_appropriate','vintage_status')
 assert(all(names(x)%in%allowed),'Coordinator target performance column');assert(all(x$assignment_at<cutoff&x$season_appropriate),'Late/invalid coordinator');x
}
