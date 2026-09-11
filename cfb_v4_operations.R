# Operational API for the separately versioned v4 study.
source('cfb_power_ratings_v4.R')
v4_baseline_snapshot <- function(sn,history) {
 cfg<-v4_config();hs<-history %>% filter(season<=2022)
 fh<-bind_rows(lapply(2015:2022,function(s)features_for(s,hs$team_id[hs$season==s],hs,NULL,cfg)))
 pm<-fit_preseason(fh,hs,2023,cfg)
 pre<-predict_preseason(pm,features_for(sn$season,sn$ids,history,NULL,cfg))
 hf<-median(unique(hs %>% select(season,hfa))$hfa)
 ef<-fit_efficiency(sn$tg,sn$ids,list(lambda=6,cap=Inf,fcs_weight=0),hf)
 list(pre=pre,ef=ef$ratings)
}
v4_baseline_ratings <- function(sn,freeze,history) {
 z<-v4_baseline_snapshot(sn,history);w<-blend_weights(freeze$baseline$par,z$ef$games_played)
 r<-z$ef %>% transmute(team_id,games_played,
   off_rating=w$a*eff_off+w$b*z$pre$pre_off,def_rating=w$a*eff_def+w$b*z$pre$pre_def,
   prior_contribution=w$b*z$pre$pre_power,current_contribution=w$a*eff_power,
   w_current=w$a,w_preseason=w$b)
 r$centering_contribution<- -mean(r$off_rating)+mean(r$def_rating)
 r$off_rating<-r$off_rating-mean(r$off_rating);r$def_rating<-r$def_rating-mean(r$def_rating)
 r$power_rating<-r$off_rating-r$def_rating;attr(r,'hfa')<-freeze$baseline$par$hfa
 attr(r,'training_ids')<-unique(sn$tg$game_id);attr(r,'as_of')<-sn$cutoff;r
}
v4_build <- function(season=2026,as_of=period_start(Sys.time()),candidate=NULL,
                     freeze_file='outputs/round3/design_frozen.rds',schedule=NULL) {
 f<-readRDS(freeze_file);if(is.null(candidate))candidate<-f$selected
 assert(candidate%in%f$reported_candidates,'Candidate not declared/evaluated')
 as_of<-as.POSIXct(as_of,tz='UTC');assert(!is.na(as_of),'Invalid cutoff')
 sch<-setNames(lapply(2015:(season-1),v4_schedule),2015:(season-1))
 hist<-v4_history(sch);g<-if(is.null(schedule))v4_schedule(season) else schedule
 ids<-fbs_ids(g);p<-v4_pre(season,ids,hist)
 tg<-team_games(g,ids,f$specs[[candidate]]$fcs_weight%or%0) %>% filter(available_at<as_of)
 hf<-median(unique(hist %>% filter(season<=2022) %>% select(season,hfa))$hfa)
 sn<-list(season=season,cutoff=as_of,ids=ids,pre=p$r,tg=tg,
     graph=v4_graph(g,ids,as_of),rows=v4_score_fit(tg,ids,lambda=1,hfa=hf),hfa=hf)
 if(candidate=='baseline') {
  oldhist<-bind_rows(lapply(sch,function(gs){fi<-fbs_ids(gs);z<-fit_efficiency(team_games(gs,fi,0),fi,list(lambda=6,cap=Inf,fcs_weight=0));z$ratings %>% mutate(season=gs$season[1],hfa=z$hfa)}))
  r<-v4_baseline_ratings(sn,f,oldhist)
 } else r<-v4_ratings(sn,f$specs[[candidate]],f$scale,f$blends[[candidate]])
 nm<-bind_rows(g %>% transmute(team_id=home_id,team=home_team,conference=home_conference),
              g %>% transmute(team_id=away_id,team=away_team,conference=away_conference)) %>% distinct(team_id,.keep_all=TRUE)
 hh<-attr(r,'hfa');training<-attr(r,'training_ids')
 r<-r %>% left_join(nm,by='team_id') %>% left_join(sn$graph %>% select(-conf),by='team_id') %>%
   left_join(p$r %>% select(team_id,pre_power,u,prev_off,prev_def),by='team_id') %>% arrange(desc(power_rating)) %>% mutate(rank=row_number())
 attr(r,'hfa')<-hh;attr(r,'training_ids')<-training;attr(r,'as_of')<-as_of
 attr(r,'candidate')<-candidate;attr(r,'frozen_design_md5')<-unname(tools::md5sum(freeze_file));r
}
v4_weekly_update <- function(season=2026,as_of=period_start(Sys.time()),refresh=FALSE) {
 g<-NULL
 if(refresh) {
  cfg<-v4_config();cfg$cache_dir<-'outputs/round3/live_cache'
  g<-read_schedule(season,cfg,refresh=TRUE)
 }
 r<-v4_build(season,as_of,schedule=g)
 path<-file.path('outputs/round3',paste0('ratings_',season,'_',format(as_of,'%Y%m%dT%H%M%S'),'.csv'))
 write.csv(r,path,row.names=FALSE);saveRDS(r,sub('csv$','rds',path));r
}
v4_archive_upcoming <- function(r,season=2026,path,schedule=NULL) {
 g<-if(is.null(schedule))v4_schedule(season) else schedule
 now<-Sys.time();cut<-attr(r,'as_of')
 assert(cut<=now,'Cannot archive a future information cutoff')
 te<-g %>% filter(home_fbs,away_fbs,kickoff>now,kickoff>=cut)
 assert(!any(te$game_id%in%attr(r,'training_ids')),'Target game in rating input')
 p<-te %>% transmute(game_id,season,kickoff,predicted_at=now,information_cutoff=cut,
  home_id,away_id,neutral,pred_margin=v4_predict(r,home_id,away_id,neutral),
  candidate=attr(r,'candidate'),design_md5=attr(r,'frozen_design_md5'))
 v4_archive(p,path);invisible(p)
}
# Optional future feature ingress: never enabled in this round's frozen model.
v4_check_features <- function(f,schedules,features) {
 assert(all(c('season','team_id','available_at','source',features)%in%names(f)),'Require ID, actual publication time, source and values')
 assert(!anyNA(f$source)&&all(nzchar(f$source)),'Missing provenance')
 assert(!anyDuplicated(paste(f$season,f$team_id)),'Duplicate feature keys')
 t<-utc(f$available_at);assert(!anyNA(t),'Missing/invalid feature vintage')
 for(s in unique(f$season)) {
  assert(as.character(s)%in%names(schedules),'Cannot verify vintage for unknown season')
  assert(all(t[f$season==s]<min(schedules[[as.character(s)]]$kickoff)),'Late feature vintage')
 }
 prepare_design(f,features)
}
