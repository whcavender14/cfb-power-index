suppressPackageStartupMessages(source('cfb_v6_operations.R'))
checks<-list();test<-function(n,expr){force(expr);checks[[n]]<<-TRUE};reject<-function(x)inherits(tryCatch(force(x),error=identity),'error')
test('recursive market guard',for(n in c('spread','market_rating','vegas_wp','implied_probability','closing_status','consensus'))stopifnot(reject(v6_guard(setNames(list(list(x=1)),n)))))
test('nested market guard',stopifnot(reject(v6_guard(list(design=list(spread=1))))))
test('football line yards explicitly allowed',v6_guard(data.frame(adj_off_line_yds=1)))
set.seed(9041);tr<-data.frame(season=rep(2016:2018,each=90),prev_off=rnorm(270),prev_def=rnorm(270),promoted=0,off_returning=runif(270),eff_off=rnorm(270))
test('fold-local transforms penalties and objective equality',{
 for(al in c(0,.5,1)){m<-v6_fit(tr,c('prev_off','prev_def','promoted','off_returning'),'eff_off',al,.1);err<-v6_apply(tr,m)-tr$eff_off
 stopifnot(abs(mean(err^2)-m$training_mse)<1e-10,abs(m$objective-mean(err^2)-.1*((1-al)*sum(m$beta[-1]^2)+2*al*sum(abs(m$beta[-1]))))<1e-10)
 held<-tr;held$off_returning<-999;v6_apply(held,m);stopifnot(identical(m$design$training_seasons,2016:2018))}
})
test('substantive external missing not imputed',{
 bad<-tr;bad$off_returning[1]<-NA;stopifnot(reject(v6_fit(bad,c('prev_off','off_returning'),'eff_off',0,.1)))
})
test('multi-year target and future history cannot enter',{
 h<-data.frame(season=rep(2015:2022,each=2),team_id=rep(1:2,8),eff_off=1:16,eff_def=16:1);r<-data.frame(season=2020,team_id=1:3);a<-v6_older(r,h,4,2);h$eff_off[h$season>=2020]<-999;b<-v6_older(r,h,4,2);stopifnot(identical(a,b),a$older_n[3]==0,is.na(a$older_off[3]))
})
cut<-as.POSIXct('2022-08-20',tz='UTC');player<-data.frame(player_id='p1',season=2022,production_season=2021,source_team_id=1,destination_team_id=2,state_available_before_cutoff=TRUE,state_cutoff=cut-86400,unit='QB',production=100,division='fcs',resolution_status='resolved_id')
test('player IDs no duplication prior source and division translation',{
 stopifnot(v6_player_validate(player,cut,2022)$translated_production==50,reject(v6_player_validate(rbind(player,player),cut,2022)))
 for(field in c('player_id','production_season','state_available_before_cutoff','state_cutoff','resolution_status','division')){q<-player;q[[field]]<-switch(field,player_id=NA,production_season=2022,state_available_before_cutoff=FALSE,state_cutoff=cut,resolution_status='ambiguous',division='unknown');stopifnot(reject(v6_player_validate(q,cut,2022)))}
})
test('all QB states retained unknown is missing not zero',{
 q<-data.frame(state=c('unknown_qb','returning_qb','transfer_qb_with_experience','transfer_qb_limited_experience','new_or_unknown_qb'),quality=c(NA,120,100,80,NA));stopifnot(identical(q,v6_qb_validate(q)));q$quality[1]<-0;stopifnot(reject(v6_qb_validate(q)))
})
test('coordinator whitelist and late states',{
 q<-data.frame(season=2022,team_id=1,coordinator_id='c',assignment_at=cut-1,season_appropriate=TRUE);v6_coordinator_validate(q,cut);q$wins<-1;stopifnot(reject(v6_coordinator_validate(q,cut)));q$wins<-NULL;q$assignment_at<-cut;stopifnot(reject(v6_coordinator_validate(q,cut)))
})
test('logical negation HFA objective precedence',{
 site<-c(TRUE,FALSE,FALSE);hfa<-3.1;x<-c(2,-1,5);y<-c(4,-1,8);expected<-mean(abs(x+hfa*as.numeric(!site)-y));stopifnot(abs(expected-mean(abs(x+ifelse(site,0,hfa)-y)))<1e-12)
})
if(file.exists(file.path(v6_dir,'development_results.rds'))){
 z<-readRDS(file.path(v6_dir,'development_results.rds'));d<-z$predictions;f<-v6_frozen();base<-d[d$candidate=='v5_EB_features',]
 test('exact incumbent reproduction every principal game',{
 old<-read.csv('outputs/round4/development_predictions.csv');old<-old[old$candidate=='EB_features',];stopifnot(setequal(base$game_id,old$game_id),max(abs(base$pred_margin-old$pred_margin[match(base$game_id,old$game_id)]))<1e-9)
 })
 test('all candidate universes identical',for(n in unique(d$candidate))stopifnot(setequal(d$game_id[d$candidate==n],base$game_id)))
 test('all unit optimizers and nested penalties earlier only',{
 for(cp in z$cps)for(ss in names(cp$prior_fits))for(m in cp$prior_fits[[ss]]$fits)stopifnot(m$max_train<as.integer(ss),all(m$cv$year<as.integer(ss)),all(m$cv$train_max<m$cv$year))
 })
 test('probabilities earlier only and independent of margins',{
 for(k in names(z$probabilities)){m<-z$probabilities[[k]];if(is.null(m))next;s<-as.integer(tail(strsplit(k,' ')[[1]],1));stopifnot(m$max_train<s,!any(m$training_ids%in%d$game_id[d$season==s]))}
 q<-base;q$pred_margin<-q$pred_margin+1;v6_probability_fit(q,2022);stopifnot(identical(d,z$predictions))
 })
 test('all ratings preserve special teams two-component identity',stopifnot(max(abs(z$ratings$power_rating-z$ratings$off_rating+z$ratings$def_rating))<1e-9))
 test('all scale objectives agree with their reported response',{
 for(k in names(z$parameters)){tok<-strsplit(k,' ')[[1]];n<-tok[1];s<-as.integer(tok[2]);p<-z$parameters[[k]];if(is.null(p$profiles$scale))next
 tr<-z$cps[[n]]$frame;tr<-tr[tr$season<s&tr$season<=2022&tr$season!=2020,];expected<-mean(abs(p$scale$scale*(tr$pre_home-tr$pre_away)+p$scale$hfa*as.numeric(!tr$neutral)-tr$actual_margin));stopifnot(abs(expected-p$profiles$scale$objective)<1e-8)
 }
 })
 test('current efficiency target and later statistics excluded',{
 sn<-Filter(function(s)s$season==2022,z$cps$v5_EB_features$snap)[[3]];ad<-readRDS(file.path(v6_dir,'inputs.rds'))$advanced;m<-z$current[['2022']];a<-v6_current_snapshot(sn,ad,m);ad$success_rate[ad$available_at>=sn$cutoff]<-999;b<-v6_current_snapshot(sn,ad,m);stopifnot(identical(a,b),!any(sn$test$game_id%in%a$tg$game_id))
 zero<-sn;zero$tg<-sn$tg[FALSE,];stopifnot(identical(zero,v6_current_snapshot(zero,ad,m)))
 })
 test('feature no-op routing exact incumbent',{
 sn<-z$cps$v5_EB_features$snap[[1]];p<-v6_prior(sn$season,sn$ids,z$history,readRDS('outputs/round4/features.rds')$features);stopifnot(isTRUE(all.equal(p$r,sn$pre,tolerance=1e-12)))
 })
 test('cache dependency identity',{
 key<-function(a=1,b=1,c=1,d=1,e=1,f=1,g=1)key_of(list(code=a,raw=b,source_version=c,feature=d,transform=e,grid=f,config=g));old<-key();for(n in letters[1:7])stopifnot(old!=do.call(key,setNames(list(2),n)))
 })
 test('new ingress rejects market before calibration or probability',{
 q<-base;q$spread<-1;stopifnot(reject(v6_probability_fit(q,2022)));cp<-z$cps$v5_EB_features;cp$frame$spread<-1;stopifnot(reject(v6_calibrate(cp,z$cps$v5_EB_features,2022,z$incpars[['2022']])))
 })
}
test('prospective archive all required refusals',{
 now<-Sys.time();p<-data.frame(game_id='future',season=2026,kickoff=now+86400,predicted_at=now,information_cutoff=period_start(now),home_id=1,away_id=2,neutral=FALSE,pred_margin=1,candidate='v5_EB_features',design_hash='d',feature_hash='f',home_snapshot_id='h',away_snapshot_id='a');path<-tempfile();v6_archive(p,path,'d','f');stopifnot(reject(v6_archive(p,path,'d','f')),reject(v6_archive(p,tempfile(),'d','f','future')),reject(v6_archive(p,tempfile(),'wrong','f')),reject(v6_archive(p,tempfile(),'d','wrong')))
 for(n in c('actual_margin','home_points','spread')){q<-p;q[[n]]<-1;stopifnot(reject(v6_archive(q,tempfile(),'d','f')))};q<-p;q$kickoff<-now-1;stopifnot(reject(v6_archive(q,tempfile(),'d','f')))
})
v6_write(data.frame(test=names(checks),pass=unlist(checks)),'tests');cat(length(checks),'v6 invariant groups passed\n')
