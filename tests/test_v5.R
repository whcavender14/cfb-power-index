suppressPackageStartupMessages(source('cfb_v5_operations.R'))
results<-list()
test<-function(name,expr){ok<-tryCatch({force(expr);TRUE},error=function(e){message(name,': ',conditionMessage(e));FALSE});results[[name]]<<-ok;if(!ok)stop(name)}
reject<-function(expr)inherits(tryCatch(force(expr),error=identity),'error')
sch<-setNames(lapply(2015:2026,v4_schedule),2015:2026);bundle<-readRDS('outputs/round4/features.rds');f<-bundle$features
one<-f %>% filter(season==2022) %>% slice(1)
test('missing publication metadata explicitly unverified and eligible',stopifnot(all(is.na(f$historical_available_at_if_verified)),all(f$vintage_status=='historical_vintage_unverified'),all(f$eligible)))
test('all substitute timestamp types rejected',{
 for(k in c('cache_download','cfbfastR_timestamp','file_modification','scrape','transfer_date','invented')){
  q<-one;q$historical_available_at_if_verified<-'2022-01-01T00:00:00Z';q$vintage_status<-'verified_historical_vintage';q$timestamp_evidence_kind<-k;q$timestamp_evidence_reference<-'fixture'
  stopifnot(reject(v5_validate_features(q,sch)))
 }
})
test('verified evidence and global cutoff',{
 q<-one;q$historical_available_at_if_verified<-'2022-01-01T00:00:00Z';q$vintage_status<-'verified_historical_vintage';q$timestamp_evidence_kind<-'original_publication';q$timestamp_evidence_reference<-'fixture original record'
 stopifnot(v5_validate_features(q,sch)$eligible)
 q$historical_available_at_if_verified<-format(min(sch[['2022']]$kickoff),'%Y-%m-%dT%H:%M:%SZ');stopifnot(!v5_validate_features(q,sch)$eligible)
 q$historical_available_at_if_verified<-'2022-01-01T00:00:00Z';q$leakage_risk_status<-'target_season_usage';stopifnot(!v5_validate_features(q,sch)$eligible)
})
test('future information overrides missing or valid publication date',{
 for(flag in c('known_post_cutoff','season_appropriate','leakage_risk_status')){
 q<-one;q[[flag]]<-switch(flag,known_post_cutoff=TRUE,season_appropriate=FALSE,leakage_risk_status='retrospective_outcomes');z<-v5_validate_features(q,sch);stopifnot(!z$eligible,all(is.na(z[,v5_terms])))
 }
})
test('raw maximum contributor publication time',{
 q<-data.frame(timestamp_evidence_kind=c('original_publication','independent_archive'),historical_available_at_if_verified=c('2022-01-01T00:00:00Z','2022-02-01T00:00:00Z'))
 stopifnot(v5_aggregate_time(q)=='2022-02-01T00:00:00Z');q$historical_available_at_if_verified[1]<-NA;stopifnot(is.na(v5_aggregate_time(q)))
})
test('forbidden coaching outcomes and market columns',{
 for(n in c('games','wins','losses','ties','srs','sp_offense','postseason_rank','market_rating','spread','closing_line')){q<-one;q[[n]]<-1;stopifnot(reject(v5_validate_features(q,sch)))}
 stopifnot(reject(v5_matrix_guard(one,'is_estimated')))
})
test('duplicate snapshot and join keys rejected',{
 stopifnot(reject(v5_validate_features(bind_rows(one,one),sch)));q<-one;q$feature_snapshot_id<-'other';stopifnot(reject(v5_validate_features(bind_rows(one,q),sch)))
})
test('missing defensive returning does not remove offense',{
 q<-f %>% filter(season==2016);stopifnot(all(is.na(q$def_returning)),sum(is.finite(q$off_returning))==128)
})
test('portal accounting excludes duplicates, preserves origin without destination',{
 pp<-tibble(season=2022,first_name=c('A','B','B','C'),last_name='Player',position='QB',origin='Team One',destination=c(NA,'Team Two','Team Two','unknown'),transfer_date=as.POSIXct('2022-06-01',tz='UTC'),rating=NA_real_,stars=NA_real_)
 lookup<-data.frame(name=c('Team One','Team Two'),team_id=c(1L,2L));p<-v5_portal(pp,sch,lookup)
 stopifnot(sum(p$aggregates$n_events[p$aggregates$direction=='outgoing'])==2,all(is.na(p$aggregates$rating_mean)),sum(p$events$accounting_status=='duplicate_or_ambiguous_player_excluded')==2)
 q<-v5_resolve(c('Team One','no match'),rbind(lookup,data.frame(name='Team One',team_id=3L)))
 stopifnot(identical(q$status,c('ambiguous','unmatched')),v5_resolve('Team One',lookup,data.frame(name='Team One',team_id=7L))$status=='manual_override')
})
hist<-v4_history(sch[as.character(2015:2022)]);ids<-fbs_ids(sch[['2022']])
test('all external missing exactly reproduces B prior',{
 ff<-f;for(n in v5_terms)ff[[n]]<-NA_real_
 a<-v5_prior(2022,ids,hist,ff,'full');b<-v4_pre(2022,ids,hist)
 stopifnot(identical(a$r,b$r),length(a$fits)==0)
})
test('nested selection and preprocessing use only training years',{
 p<-v5_prior(2022,ids,hist,f,'full')
 stopifnot(length(p$fits)>0)
 for(m in p$fits)stopifnot(m$max_train<2022,all(m$design$training_seasons<2022),all(m$cv$train_max<m$cv$year),all(m$cv$year<2022),m$gradient<1e-8)
 ff<-f;ff$off_returning[ff$season>2022]<-999
 q<-v5_prior(2022,ids,hist,ff,'full');stopifnot(identical(p$r,q$r),identical(p$fits,q$fits))
})
test('fold standardization independent of heldout feature range',{
 tr<-data.frame(season=2015:2020,prev_off=1:6,prev_def=c(2,4,1,5,0,3),promoted=0,off_returning=seq(.1,.6,.1))
 d<-v5_prepare(tr,c('prev_off','prev_def','promoted','off_returning'));stopifnot(max(abs(colMeans(d$X)[-1]))<1e-10,length(d$dropped)>0)
})
test('cache invalidates every declared dependency',{
 a<-v5_key(list(a=1),'raw','feature','version','code')
 stopifnot(a!=v5_key(list(a=2),'raw','feature','version','code'),a!=v5_key(list(a=1),'new','feature','version','code'),a!=v5_key(list(a=1),'raw','new','version','code'),a!=v5_key(list(a=1),'raw','feature','new','code'),a!=v5_key(list(a=1),'raw','feature','version','new'))
})
cp<-readRDS('outputs/round3/development_components.rds')$cp;sn<-cp$snap[[1]];freeze<-readRDS('outputs/round3/design_frozen.rds')
par<-list(scale=freeze$scale,blend=freeze$blends$B,gamma=1);spec<-v5_candidates()$B
r<-v5_ratings(sn,spec,par)
test('v5 snapshot exact v4 predictions',stopifnot(identical(r,v4_ratings(sn,v4_specs()$B,par$scale,par$blend))))
test('gamma scales neutral differences and contributions but never HFA',{
 pp<-par;pp$gamma<-1.25;z<-v5_ratings(sn,spec,pp)
 stopifnot(max(abs(z$power_rating-1.25*r$power_rating))<1e-10,attr(z,'hfa')==attr(r,'hfa'),abs(v4_predict(z,sn$ids[1],sn$ids[2],FALSE)-v4_predict(z,sn$ids[1],sn$ids[2],TRUE)-par$scale$hfa)<1e-9,
 abs(v4_predict(z,sn$ids[1],sn$ids[2],TRUE)+v4_predict(z,sn$ids[2],sn$ids[1],TRUE))<1e-9)
})
test('zero/one B and EB behaviors and FCS clock',{
 ss<-sn;ss$tg<-sn$tg[FALSE,];ss$rows<-v4_score_fit(ss$tg,ss$ids,lambda=1,hfa=ss$hfa)
 z<-v5_ratings(ss,spec,par);stopifnot(max(abs(z$power_rating-par$scale$scale*ss$pre$pre_power))<1e-9,all(z$games_played==0))
 g<-sch[['2022']];tg<-team_games(g,fbs_ids(g),.25);zz<-v4_score_fit(tg,fbs_ids(g),lambda=4)
 ct<-table(tg$team_id[tg$team_id%in%fbs_ids(g)&tg$opp_id%in%fbs_ids(g)]);stopifnot(all(zz$games_played==as.integer(ct[as.character(zz$team_id)])))
})
test('market cannot enter fitted calibration object',{
 d<-cp$frame;d$spread<-1;stopifnot(reject(v5_fit_parameters(list(frame=d),cp,spec,2022)))
})
test('future graph edges excluded and no conference power penalty',{
 g<-sch[['2022']];cut<-min(g$kickoff)-86400;gr<-v4_graph(g,ids,cut);stopifnot(all(gr$component_size==1),all(gr$n_cross==0))
 ss<-sn;ss$graph$conf[]<-'SEC';a<-v5_ratings(ss,v5_candidates()$Uncertainty,par);ss$graph$conf[]<-'Sun Belt';b<-v5_ratings(ss,v5_candidates()$Uncertainty,par);stopifnot(identical(a,b))
})
test('prospective archives reject overwrite, past, outcome, market and hashes',{
 p<-data.frame(game_id='future',season=2026,kickoff=Sys.time()+86400,predicted_at=Sys.time(),information_cutoff=Sys.time()-3600,home_id=1,away_id=2,neutral=FALSE,pred_margin=1,candidate='B',design_hash='d',feature_hash='f',home_snapshot_id='h',away_snapshot_id='a')
 path<-tempfile();v5_archive(p,path,'d','f');stopifnot(reject(v5_archive(p,path,'d','f')),reject(v5_archive(p,tempfile(),'wrong','f')))
 q<-p;q$kickoff<-Sys.time()-1;stopifnot(reject(v5_archive(q,tempfile(),'d','f')))
 for(n in c('actual_margin','home_points','spread','market')){q<-p;q[[n]]<-1;stopifnot(reject(v5_archive(q,tempfile(),'d','f')))}
})
v5_write(data.frame(test=names(results),pass=unlist(results)),'tests');cat(length(results),'v5 invariant groups passed\n')
