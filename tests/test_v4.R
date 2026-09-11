suppressPackageStartupMessages(source('cfb_v4_operations.R'))
results<-list()
test<-function(name,expr){ok<-tryCatch({force(expr);TRUE},error=function(e){message(name,': ',conditionMessage(e));FALSE});results[[name]]<<-ok;if(!ok)stop(name)}
reject<-function(expr) inherits(tryCatch(force(expr),error=identity),'error')
cut<-as.POSIXct('2022-09-12',tz='UTC');ids<-1:4
prior<-tibble(team_id=ids,pre_off=c(6,2,-3,-5),pre_def=c(-4,1,1,2))
g<-tibble(game_id='g1',season=2022L,week=1L,season_type='regular',
 kickoff=cut-3*86400,available_at=cut-2*86400,period=period_start(kickoff),
 home_id=1L,away_id=2L,home_fbs=TRUE,away_fbs=TRUE,home_points=30,away_points=20,
 neutral=FALSE,final=TRUE,home_conference='X',away_conference='Y')
tg<-team_games(g,ids,0);blank<-tg[FALSE,]
r0<-v4_score_fit(blank,ids,prior,8,3);r1<-v4_score_fit(tg,ids,prior,8,3)
test('zero game retains centered prior',stopifnot(max(abs(r0$eff_power-(prior$pre_off-prior$pre_def)))<1e-10,all(r0$games_played==0)))
test('one game updates rating finitely',stopifnot(all(is.finite(r1$eff_power)),identical(r1$games_played,c(1L,1L,0L,0L)),max(abs(r1$eff_power-r0$eff_power))>0))
test('target game excluded',stopifnot(reject(audit_fold(tg,g,cut,2021,2022))))
te<-g;te$game_id<-'future';te$kickoff<-cut+86400
test('availability cutoff enforced',stopifnot(reject(audit_fold(transform(tg,available_at=cut),te,cut,2021,2022))))
test('preseason target-year training excluded',stopifnot(reject(audit_fold(tg,te,cut,2022,2022))))
test('valid earlier fold accepted',stopifnot(audit_fold(tg,te,cut,2021,2022)))
gr<-v4_graph(g,ids,cut)
test('disconnected schedule components',stopifnot(identical(gr$component_size,c(2L,2L,1L,1L)),all(gr$n_cross==c(1L,1L,0L,0L))))
test('future graph edge excluded',stopifnot(all(v4_graph(transform(g,available_at=cut),ids,cut)$n_fbs_opponents==0)))
r<-tibble(team_id=ids,power_rating=r1$eff_power);attr(r,'hfa')<-3
pn<-v4_predict(r,1L,2L,TRUE);ph<-v4_predict(r,1L,2L,FALSE)
test('HFA once only and neutral antisymmetry',stopifnot(abs(ph-pn-3)<1e-10,abs(pn+v4_predict(r,2L,1L,TRUE))<1e-10))
test('power identity centered',stopifnot(max(abs(r1$eff_power-r1$eff_off+r1$eff_def))<1e-10,abs(mean(r1$eff_power))<1e-10))
test('deterministic solve',stopifnot(identical(r1,v4_score_fit(tg,ids,prior,8,3))))
test('market outcomes cannot enter calibration schema',stopifnot(reject(v4_scale(tibble(season=2023)))))
f<-data.frame(season=2022,team_id=1:4,available_at='2022-01-01T00:00:00Z',source='test fixture',x=1:4,y=2*(1:4),z=NA_real_,constant=1)
design<-v4_check_features(f,list('2022'=g),c('x','y','z','constant'))
test('all missing constant rank deficient dropped',stopifnot(all(c('y','z','constant')%in%names(design$dropped))))
f$available_at<-'2023-01-01T00:00:00Z'
test('late feature rejected',stopifnot(reject(v4_check_features(f,list('2022'=g),'x'))))
f$available_at<-NA_character_
test('missing vintage rejected',stopifnot(reject(v4_check_features(f,list('2022'=g),'x'))))
f$available_at<-'2022-01-01T00:00:00Z';f$source<-''
test('missing provenance rejected',stopifnot(reject(v4_check_features(f,list('2022'=g),'x'))))
test('cached run deterministic',{
 cfg<-v4_config();cfg$cache_dir<-tempfile();a<-cache(cfg,'fixture',42);b<-cache(cfg,'fixture',stop('should not execute'));stopifnot(identical(a,b))
})
test('archive refuses past predictions',stopifnot(reject(v4_archive(data.frame(kickoff=cut),tempfile()))))
test('archive refuses overwrite',{
 p<-tempfile();v4_archive(data.frame(kickoff=Sys.time()+86400,pred_margin=1),p)
 stopifnot(file.exists(p),reject(v4_archive(data.frame(kickoff=Sys.time()+86400),p)))
})
# Production uses exactly the same snapshot-to-rating function as validation.
if(file.exists('outputs/round3/design_frozen.rds')) {
 frozen<-readRDS('outputs/round3/design_frozen.rds');cp<-readRDS('outputs/round3/development_components.rds')$cp
 sn<-cp$snap[[length(cp$snap)]]
 for(n in c('A','B','C','D'))test(paste('production validation parity',n),{
  rr<-v4_ratings(sn,frozen$specs[[n]],frozen$scale,frozen$blends[[n]])
  pp<-v4_evaluate(v4_subset(cp,sn$season),frozen$specs[[n]],frozen$scale,frozen$blends[[n]]) %>% filter(cutoff==sn$cutoff)
  stopifnot(max(abs(pp$pred_margin-v4_predict(rr,pp$home_id,pp$away_id,pp$neutral)))<1e-10)
 })
 test('centering preserves matchup predictions',{
  rr<-v4_ratings(sn,frozen$specs$B,frozen$scale,frozen$blends$B)
  w<-frozen$blends$B$k/(sn$rows$games_played+frozen$blends$B$k)
  raw<-(1-w)*sn$rows$eff_power+w*frozen$scale$scale*sn$pre$pre_power
  stopifnot(max(abs(outer(raw,raw,'-')-outer(rr$power_rating,rr$power_rating,'-')))<1e-10)
 })
 test('all tuning years locked',stopifnot(frozen$max_selection_year==2022,frozen$scale$max_train<=2022,frozen$baseline$max_train_season<=2022))
}
write.csv(data.frame(test=names(results),pass=unlist(results)),'outputs/round3/tests.csv',row.names=FALSE)
cat(length(results),'tests passed\n')
