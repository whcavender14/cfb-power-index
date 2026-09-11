suppressPackageStartupMessages(source('cfb_v5_operations.R'))
f<-v5_frozen();b<-readRDS('outputs/round4/features.rds');tf<-b$features
# Explicit derived-record lineage; raw artifact copies remain separate.
derived<-bind_rows(lapply(c('talent','returning','coaches'),function(src){
 terms<-switch(src,talent=c('log_talent','blue_chip_ratio','log_recruits'),returning=c('off_returning','def_returning'),coaches=c('log_tenure','new_coach'))
 q<-tf %>% select(season,team_id,feature_snapshot_id,historical_available_at_if_verified,vintage_status,leakage_risk_status)
 q$source<-src;q$raw_content_hash<-b$raw_hashes[[src]];q$source_version_or_retrieval_identifier_if_known<-NA_character_
 q$feature_values<-vapply(seq_len(nrow(tf)),function(i)paste(paste0(terms,'=',vapply(terms,function(t)if(is.finite(tf[[t]][i]))format(tf[[t]][i],digits=17) else 'missing',character(1))),collapse=';'),character(1))
 q$coverage<-vapply(seq_len(nrow(tf)),function(i)sum(vapply(terms,function(t)is.finite(tf[[t]][i]),logical(1))),integer(1))
 q$aggregation_rule<-switch(src,talent='log1p composite; raw bluechip; log1p recruits',returning='separate unit shares; no imputation',coaches='unique pre-cutoff hire; log1p tenure; new coach')
 q
}));v5_write(derived,'DERIVED_FEATURE_PROVENANCE_MANIFEST')
p<-b$portal$aggregates
 net<-full_join(p %>% filter(direction=='incoming') %>% select(season,team_id,incoming_events=n_events,incoming_rating_mean=rating_mean),
 p %>% filter(direction=='outgoing') %>% select(season,team_id,outgoing_events=n_events,outgoing_rating_mean=rating_mean),by=c('season','team_id')) %>% mutate(net_observed_events=incoming_events-outgoing_events)
v5_write(net,'portal_net_observed_counts')
abl<-list();corrs<-list()
for(stage in c('development','conditional')) {
 z<-readRDS(paste0('outputs/round4/',stage,'_results.rds'));d<-z$predictions;base<-d %>% filter(candidate=='B')
 for(n in c('B','RP','RP_off','RP_def','Talent_RP','Coach','Full','EB_features')){
  q<-d %>% filter(candidate==n);r<-v5_paired(q,base)
  abl[[paste(stage,n)]]<-cbind(stage=stage,candidate=n,provenance=if(n=='B')'scores' else 'historical_vintage_unverified',r)
 }
 for(fam in names(z$cps))for(s in unique(z$cps[[fam]]$frame$season)){
  sn<-Filter(function(x)x$season==s,z$cps[[fam]]$snap)[[1]];p<-sn$pre
  corrs[[paste(stage,fam,s)]]<-tibble(stage=stage,family=fam,season=s,pearson=cor(p$pre_power,p$prev_off-p$prev_def,use='complete.obs'),spearman=cor(p$pre_power,p$prev_off-p$prev_def,use='complete.obs',method='spearman'),preseason_sd=sd(p$pre_power))
 }
}
v5_write(bind_rows(abl),'feature_ablations');v5_write(bind_rows(corrs),'preseason_prior_finish_correlations')
v5_write(tibble(specification=c('RP eligible historical','RP higher provenance','Portal effect','QB continuity'),status=c('estimated in primary development','no independently stronger historical observations recovered; no separate fit','exploratory accounting; one possible pre-2023 forward season insufficient','no appropriate historical source; unknown QB'),verified_historical_rows=c(0L,0L,0L,0L)),'provenance_sensitivity_status')
# Exact numerical algebra fixtures: no game vs one observed FBS game, all candidates.
z<-readRDS('outputs/round4/development_results.rds');rr<-list()
for(n in names(f$specs)) {
 sn<-z$cps[[f$specs[[n]]$features]]$snap[[1]];ids<-sn$ids;cut<-as.POSIXct('2022-09-12',tz='UTC')
 g<-tibble(game_id='algebra_fixture',kickoff=cut-3*86400,available_at=cut-2*86400,period=period_start(cut-3*86400),home_id=ids[1],away_id=ids[2],home_fbs=TRUE,away_fbs=TRUE,home_points=30,away_points=20,neutral=FALSE,final=TRUE,home_conference='X',away_conference='Y')
 for(ng in 0:1){sn$tg<-team_games(if(ng==0)g[FALSE,] else g,ids,0);sn$cutoff<-cut;sn$rows<-v4_score_fit(sn$tg,ids,lambda=1,hfa=sn$hfa);sn$graph<-v4_graph(if(ng==0)g[FALSE,] else g,ids,cut)
  r<-v5_ratings(sn,f$specs[[n]],f$parameters[[n]])
  rr[[paste(n,ng)]]<-r %>% mutate(candidate=n,fixture_games=ng,fixture_note='synthetic 30-20; Conference fixture has zero conference offsets')
 }
}
v5_write(bind_rows(rr),'zero_one_algebra_fixtures')
# Integrity check on all original Round 3 files captured by original manifests.
m<-read.csv('outputs/round3/input_manifest.csv');if(all(c('path','md5')%in%names(m)))v5_write(transform(m,current_md5=unname(tools::md5sum(path)),unchanged=unname(tools::md5sum(path))==md5),'round3_integrity')
v5_write(v5_hashes(c('report_round4.R','supplemental_round4.R','tests/test_v5.R','tests/test_v5_integration.R')),'report_test_manifest')
# Applied effects after FBS-weighted centering, with centering covariance retained.
sch<-setNames(lapply(2015:2026,v4_schedule),2015:2026)
h<-v4_history(sch[as.character(2015:2025)]);applied<-list()
for(s in c(2019,2021:2026)) {
 e<-v5_conference(s,h,sch);m<-v5_membership(sch[[as.character(s)]]) %>% filter(team_id%in%fbs_ids(sch[[as.character(s)]])) %>% left_join(e,by='conf')
 for(side in c('off','def')){
  v<-m[[side]];v[!is.finite(v)]<-0;se<-m[[paste0('se_',side)]];se[!is.finite(se)]<-0
  cnt<-table(m$conf);w<-as.numeric(cnt[as.character(m$conf)])/nrow(m);w[is.na(w)]<-0
  unique_conf<-!duplicated(m$conf);common_var<-sum((w[unique_conf]*se[unique_conf])^2)
  m[[paste0('centered_',side)]]<-v-mean(v);m[[paste0('centered_se_',side)]]<-sqrt(pmax(0,se^2+common_var-2*w*se^2))
 }
 stopifnot(abs(mean(m$centered_off))<1e-10,abs(mean(m$centered_def))<1e-10)
 applied[[as.character(s)]]<-mutate(m,season=s)
}
v5_write(bind_rows(applied),'conference_applied_centered_effects')
# Complete routing ledger explicitly includes every B fallback, both units.
used<-read.csv('outputs/round4/feature_coverage_routes.csv',stringsAsFactors=FALSE)
route_all<-list()
for(stage in c('development','conditional')) {
 z<-readRDS(paste0('outputs/round4/',stage,'_results.rds'))
 for(fam in setdiff(names(z$cps),'none'))for(s in unique(z$cps[[fam]]$frame$season)){
  sn<-Filter(function(x)x$season==s,z$cps[[fam]]$snap)[[1]]
  q<-expand.grid(team_id=sn$ids,side=c('off','def'),stringsAsFactors=FALSE);q$stage<-stage;q$family<-fam;q$season<-s
  q<-left_join(q,used,by=c('team_id','side','stage','family','season'))
  q$routing_status<-ifelse(is.na(q$regime),'B_fallback','trained_eligible_regime')
  q$regime[is.na(q$regime)]<-'no usable external subset or insufficient nested training evidence'
  route_all[[paste(stage,fam,s)]]<-q
 }
}
v5_write(bind_rows(route_all),'feature_coverage_routes_complete')
