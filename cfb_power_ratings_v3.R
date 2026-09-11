# CFB power ratings v3 -- scores-based, temporally audited, nested validation.
# Standalone. No execution on source(). See README.md for commands and limitations.
# Defense is points ALLOWED above average (lower is better).
# Power = offense - defense. MAE targets a conditional median; conditional mean
# calibration is a diagnostic, never an algebraic promise.
library(dplyr)
library(tibble)
library(Matrix)

cfb_config <- function(cache_dir = 'cfb_data_v3',
                       source_cache = '/Users/willcavender/Desktop/CFB Modeling/cfb_data_v2',
                       history_seasons = 2015:2025, outer_seasons = 2023:2025,
                       feature_file = NULL, features = character(),
                       candidates = NULL, ...) {
  if (is.null(candidates)) candidates <- list(
    list(label='uncapped_ridge6', cap=Inf, lambda=6, fcs_weight=0),
    list(label='cap32_ridge6', cap=32, lambda=6, fcs_weight=0),
    list(label='uncapped_ridge12', cap=Inf, lambda=12, fcs_weight=0),
    list(label='pooled_fcs', cap=Inf, lambda=6, fcs_weight=0.25))
  cfg <- list(version='3.0.0',cache_dir=cache_dir,source_cache=source_cache,
    history_seasons=history_seasons,outer_seasons=outer_seasons,
    features=features,feature_file=feature_file,candidates=candidates,
    inner_start=2021L, exclude_2020=TRUE, availability_hours=24,
    bootstrap_reps=2000L, seed=9041L)
  modifyList(cfg,list(...))
}
assert <- function(ok, msg) if (!isTRUE(ok)) stop(msg,call.=FALSE)
key_of <- function(x) {f<-tempfile();on.exit(unlink(f));saveRDS(x,f,version=2);unname(tools::md5sum(f))}
cache <- function(cfg,key,expr,refresh=FALSE) {
  dir.create(cfg$cache_dir,recursive=TRUE,showWarnings=FALSE)
  f<-file.path(cfg$cache_dir,paste0(key,'.rds'))
  if(file.exists(f)&&!refresh)return(readRDS(f))
  x<-force(expr);saveRDS(x,f);x
}
utc <- function(x) {
 if(inherits(x,'POSIXt'))return(as.POSIXct(x,tz='UTC'))
 as.POSIXct(sub('Z$','',as.character(x)),format='%Y-%m-%dT%H:%M:%OS',tz='UTC')
}
# Monday 00:00 UTC; fixed calendar periods, never provider week labels.
period_start <- function(x) {
 d<-as.Date(x,tz='UTC');as.POSIXct(d-((as.POSIXlt(d)$wday+6L)%%7L),tz='UTC')
}
read_schedule <- function(season,cfg,refresh=FALSE) {
 raw<-cache(cfg,paste0('raw_schedule_',season),{
   old<-file.path(cfg$source_cache,paste0('schedule_',season,'.rds'))
   if(file.exists(old)&&!refresh)readRDS(old) else {
     assert(requireNamespace('cfbfastR',quietly=TRUE),'Install cfbfastR.')
     if(nzchar(Sys.getenv('CFBD_API_KEY'))) {
       # Explicitly request both types; endpoint defaults need not include bowls.
       bind_rows(lapply(c('regular','postseason'),function(st)
         cfbfastR::cfbd_game_info(year=season,season_type=st)))
     } else cfbfastR::load_cfb_schedules(seasons=season)
   }
 },refresh)
 g<-as.data.frame(raw)
 aliases<-list(game_id=c('id'),home_id=c('home_team_id'),away_id=c('away_team_id'),
   neutral_site=c('neutral'),home_division=c('home_classification'),away_division=c('away_classification'))
 for(n in names(aliases))if(!n%in%names(g)) {hit<-intersect(aliases[[n]],names(g));if(length(hit))names(g)[match(hit[1],names(g))]<-n}
 req<-c('game_id','season','week','season_type','start_date','neutral_site','home_id','away_id',
   'home_division','away_division','home_points','away_points')
 assert(all(req%in%names(g)),paste('Schedule missing:',paste(setdiff(req,names(g)),collapse=', ')))
 g<-as_tibble(g) %>% mutate(game_id=as.character(game_id),home_id=as.integer(home_id),away_id=as.integer(away_id),
   kickoff=utc(start_date),neutral=as.logical(neutral_site),
   home_fbs=tolower(home_division)=='fbs',away_fbs=tolower(away_division)=='fbs',
   period=period_start(kickoff),available_at=kickoff+cfg$availability_hours*3600)
 # Completed flag is required when present; a scored in-progress game is not final.
 g$final<-is.finite(g$home_points)&is.finite(g$away_points)
 if('completed'%in%names(g))g$final<-g$final & !is.na(g$completed) & g$completed
 assert(!anyDuplicated(g$game_id),'Duplicate game IDs: resolve source conflicts, do not silently deduplicate.')
 assert(!anyNA(g$kickoff)&&!anyNA(g$neutral),'Unknown kickoff/neutral-site status; fix schedule metadata.')
 assert(!anyNA(g$home_fbs)&&!anyNA(g$away_fbs),'Unknown historical division; current membership fallback prohibited.')
 assert(all(g$season==season),'Wrong season in schedule.')
 g %>% arrange(kickoff,game_id)
}
fbs_ids <- function(g)sort(unique(c(g$home_id[g$home_fbs],g$away_id[g$away_fbs])))
team_games <- function(g,ids,fcs_weight=0) {
 g<-g %>% filter(final,home_fbs|away_fbs)
 if(fcs_weight==0)g<-g %>% filter(home_fbs,away_fbs)
 bind_rows(g %>% transmute(game_id,kickoff,available_at,period,team_id=home_id,opp_id=away_id,
   pf=home_points,pa=away_points,hx=ifelse(neutral,0,0.5)),
  g %>% transmute(game_id,kickoff,available_at,period,team_id=away_id,opp_id=home_id,
   pf=away_points,pa=home_points,hx=ifelse(neutral,0,-0.5))) %>%
 mutate(entity=ifelse(team_id%in%ids,as.character(team_id),'FCS'),
        opponent=ifelse(opp_id%in%ids,as.character(opp_id),'FCS'),
        weight=ifelse(entity=='FCS'|opponent=='FCS',fcs_weight,1))
}
# Ridge coefficients shrink to zero, independently of preseason. Historical HFA
# has a weak fixed penalty to 3; current-season HFA is frozen from prior years.
fit_efficiency <- function(tg,ids,spec,hfa=NULL) {
 blank<-tibble(team_id=ids,eff_off=0,eff_def=0,eff_power=0,games_played=0L)
 if(!nrow(tg))return(list(ratings=blank,hfa=if(is.null(hfa))3 else hfa,fcs=NULL))
 ents<-unique(c(as.character(ids),tg$entity,tg$opponent));nt<-length(ents);n<-nrow(tg)
 ti<-match(tg$entity,ents);oi<-match(tg$opponent,ents)
 X<-sparseMatrix(i=rep(seq_len(n),3),j=c(rep(1L,n),1L+ti,1L+nt+oi),x=1,dims=c(n,1L+2L*nt))
 y<-(tg$pf+tg$pa)/2+pmax(-spec$cap,pmin(spec$cap,tg$pf-tg$pa))/2
 penalty<-c(0,rep(spec$lambda,2L*nt));rhs_prior<-rep(0,length(penalty))
 if(is.null(hfa)) {X<-cbind(X,tg$hx);penalty<-c(penalty,10);rhs_prior<-c(rhs_prior,30)} else y<-y-hfa*tg$hx
 W<-Diagonal(x=tg$weight)
 coef<-as.numeric(solve(crossprod(X,W%*%X)+Diagonal(x=penalty),crossprod(X,tg$weight*y)+rhs_prior))
 if(is.null(hfa))hfa<-tail(coef,1)
 off<-coef[1L+seq_len(nt)];def<-coef[1L+nt+seq_len(nt)]
 fi<-match(as.character(ids),ents)
 off<-off-mean(off[fi]);def<-def-mean(def[fi])
 gp<-tg %>% filter(team_id%in%ids) %>% group_by(team_id) %>% summarise(games_played=n_distinct(game_id),.groups='drop')
 r<-tibble(team_id=ids,eff_off=off[fi],eff_def=def[fi],eff_power=off[fi]-def[fi]) %>%
 left_join(gp,by='team_id') %>% mutate(games_played=coalesce(games_played,0L))
 f<-match('FCS',ents)
 list(ratings=r,hfa=hfa,fcs=if(is.na(f))NULL else off[f]-def[f])
}

# Optional snapshots: season, team_id, available_at (ISO UTC), numeric feature
# columns. Timestamps must describe actual publication, not a backfilled guess.
# Missing values are retained and median-imputed using training seasons only.
load_features <- function(cfg,schedules) {
 if(!length(cfg$features))return(NULL)
 assert(!is.null(cfg$feature_file)&&file.exists(cfg$feature_file),'Enabled features require a dated snapshot file.')
 f<-read.csv(cfg$feature_file,stringsAsFactors=FALSE)
 assert(all(c('season','team_id','available_at',cfg$features)%in%names(f)),'Feature file schema incomplete.')
 f$available_at<-utc(f$available_at)
 assert(!anyNA(f$available_at),'Feature publication timestamp missing.')
 assert(!anyDuplicated(paste(f$season,f$team_id)),'Feature snapshot has duplicate team-season rows.')
 for(s in unique(f$season)) {
   g<-schedules[[as.character(s)]];if(is.null(g))next
   assert(all(f$available_at[f$season==s]<min(g$kickoff)),'Feature published after first season kickoff.')
 }
 as_tibble(f)
}
features_for <- function(s,ids,history,features,cfg) {
 prev<-history %>% filter(season==s-1L) %>% select(team_id,prev_off=eff_off,prev_def=eff_def)
 f<-tibble(season=s,team_id=ids) %>% left_join(prev,by='team_id')
 f$promoted<-as.numeric(!is.finite(f$prev_off)|!is.finite(f$prev_def))
 if(length(cfg$features)) f<-left_join(f,features %>% filter(season==s) %>% select(team_id,all_of(cfg$features)),by='team_id')
 f
}
# Explicit rank audit: constants/all-missing/linear dependencies are recorded.
# Imputation constants are training medians; missingness gets its own predictor.
prepare_design <- function(train,terms) {
 X<-data.frame(intercept=rep(1,nrow(train)));med<-list();dropped<-list()
 for(t in terms) {
  x<-train[[t]];assert(is.numeric(x),paste('Non-numeric predictor',t))
  if(!any(is.finite(x))){dropped[[t]]<-'all missing';next}
  med[[t]]<-median(x[is.finite(x)]);miss<-!is.finite(x);x[miss]<-med[[t]]
  X[[t]]<-x;X[[paste0(t,'__missing')]]<-as.numeric(miss)
 }
 keep<-'intercept'
 for(t in setdiff(names(X),'intercept')) {
  if(length(unique(X[[t]]))<2){dropped[[t]]<-'constant';next}
  z<-as.matrix(X[,c(keep,t),drop=FALSE])
  if(qr(z,tol=1e-9)$rank<ncol(z)){dropped[[t]]<-'linear dependency';next}
  keep<-c(keep,t)
 }
 list(X=as.matrix(X[,keep,drop=FALSE]),med=med,keep=keep,dropped=dropped)
}
apply_design <- function(f,design) {
 X<-data.frame(intercept=rep(1,nrow(f)))
 for(t in names(design$med)) {
  assert(t%in%names(f),paste('Missing prediction feature',t))
  x<-f[[t]];miss<-!is.finite(x);x[miss]<-design$med[[t]]
  X[[t]]<-x;X[[paste0(t,'__missing')]]<-as.numeric(miss)
 }
 as.matrix(X[,design$keep,drop=FALSE])
}
fit_preseason <- function(fh,history,s,cfg) {
 tr<-fh %>% filter(season<s) %>% inner_join(history,by=c('season','team_id'))
 # First history year is a burn-in, not a cohort of promoted teams.
 tr<-tr %>% filter(season>min(cfg$history_seasons))
 if(cfg$exclude_2020)tr<-tr %>% filter(season!=2020)
 assert(nrow(tr)>=200,paste('Insufficient preseason training before',s))
 design<-prepare_design(tr,c('prev_off','prev_def','promoted',cfg$features))
 co<-qr.coef(qr(design$X),tr$eff_off);cd<-qr.coef(qr(design$X),tr$eff_def)
 names(co)<-names(cd)<-design$keep
 assert(all(is.finite(c(co,cd))),'Rank-deficient preseason fit survived rank audit.')
 # Contrast derivative for a +1 prior power change at fixed scoring environment:
 # prior offense +0.5, prior defensive burden -0.5.
 get<-function(v,t)if(t%in%names(v))v[[t]] else 0
 carry<-0.5*((get(co,'prev_off')-get(cd,'prev_off'))-(get(co,'prev_def')-get(cd,'prev_def')))
 list(off=co,def=cd,design=design,carryover=carry,n=nrow(tr),max_train_season=max(tr$season),
   rmse=sqrt(mean((tr$eff_power-as.numeric(design$X%*%(co-cd)))^2)))
}
predict_preseason <- function(pm,f) {
 X<-apply_design(f,pm$design);o<-as.numeric(X%*%pm$off);d<-as.numeric(X%*%pm$def)
 f %>% mutate(pre_off=o-mean(o),pre_def=d-mean(d),pre_power=pre_off-pre_def)
}
# Each fold retains the exact IDs supplied to the estimator, with timestamps.
audit_fold <- function(train,test,cutoff,preseason_max,season) {
 assert(!anyDuplicated(paste(train$game_id,train$team_id)),'Duplicate team-game training row.')
 assert(all(table(train$game_id)==2L),'Training game does not have exactly two team rows.')
 assert(length(intersect(train$game_id,test$game_id))==0,'LEAKAGE: target game in estimator input.')
 assert(all(train$available_at<cutoff),'LEAKAGE: training result unavailable at cutoff.')
 assert(all(test$kickoff>=cutoff),'LEAKAGE: prediction timestamp after kickoff.')
 assert(preseason_max<season,'LEAKAGE: preseason trained on target/future season.')
 TRUE
}
build_component_frame <- function(cfg,spec,schedules,features=NULL) {
 history<-bind_rows(lapply(cfg$history_seasons,function(s){
  g<-schedules[[as.character(s)]];ids<-fbs_ids(g)
  fit<-fit_efficiency(team_games(g,ids,spec$fcs_weight),ids,spec)
  fit$ratings %>% mutate(season=s,hfa=fit$hfa)
 }))
 fh<-bind_rows(lapply(cfg$history_seasons,function(s)features_for(s,fbs_ids(schedules[[as.character(s)]]),history,features,cfg)))
 preds<-list();ledger<-list();pre_fits<-list()
 for(s in cfg$history_seasons[cfg$history_seasons>=min(cfg$history_seasons)+3]) {
  message(spec$label,': component season ',s)
  g<-schedules[[as.character(s)]];ids<-fbs_ids(g)
  pm<-fit_preseason(fh,history,s,cfg);pre_fits[[as.character(s)]]<-pm
  pre<-predict_preseason(pm,fh %>% filter(season==s))
  hfa<-median(unique(history %>% filter(season<s) %>% select(season,hfa))$hfa)
  tg<-team_games(g,ids,spec$fcs_weight)
  weeks<-sort(unique(g$period[g$home_fbs|g$away_fbs]))
  for(j in seq_along(weeks)) {
   cut<-weeks[j];test<-g %>% filter(final,period==cut,home_fbs,away_fbs)
   if(!nrow(test))next
   tr<-tg %>% filter(available_at<cut)
   audit_fold(tr,test,cut,pm$max_train_season,s)
   fit<-fit_efficiency(tr,ids,spec,hfa)
   rr<-left_join(pre,fit$ratings,by='team_id')
   h<-rr[match(test$home_id,rr$team_id),];a<-rr[match(test$away_id,rr$team_id),]
   fold<-paste(s,as.character(cut),sep='_')
   preds[[length(preds)+1]]<-test %>% transmute(season,game_id,week,season_type,week_seq=j,
     kickoff,cutoff=cut,fold,neutral,home_id,away_id,actual_margin=home_points-away_points,
     eff_home=h$eff_power,eff_away=a$eff_power,pre_home=h$pre_power,pre_away=a$pre_power,
     gp_home=h$games_played,gp_away=a$games_played,promoted_home=h$promoted,promoted_away=a$promoted,
     pre_max_season=pm$max_train_season)
   ledger[[fold]]<-list(season=s,cutoff=cut,train=tr %>% select(game_id,team_id,opp_id,kickoff,available_at),
     test_ids=test$game_id,pre_max_season=pm$max_train_season)
  }
 }
 list(frame=bind_rows(preds),ledger=ledger,history=history,features=fh,pre_fits=pre_fits,spec=spec)
}
audit_leakage <- function(component) {
 d<-component$frame
 assert(!anyDuplicated(paste(d$season,d$game_id)),'Duplicate predictions.')
 for(f in unique(d$fold)) {
  l<-component$ledger[[f]];assert(!is.null(l),'Missing provenance ledger.')
  te<-d %>% filter(fold==f)
  assert(setequal(te$game_id,l$test_ids),'Ledger/test ID mismatch.')
  audit_fold(l$train,te,l$cutoff,l$pre_max_season,l$season)
  for(side in c('home','away')) {
   counts<-table(l$train$team_id);expected<-as.numeric(counts[as.character(te[[paste0(side,'_id')]])]);expected[is.na(expected)]<-0
   assert(all(expected==te[[paste0('gp_',side)]]),'Games-played count disagrees with actual input IDs.')
  }
 }
 tibble(check='temporal/game-ID audit',pass=TRUE,n_predictions=nrow(d),n_folds=length(unique(d$fold)))
}
# Bounded on OBSERVED weight endpoints, not asymptotic coefficients. a(0)=0;
# a(12)=C, b(0)=B, b(12)=B*q. g is capped at 12 consistently everywhere.
# shape in [0,1] spans constant-after-first-game through linear growth.
# q=0 is preseason-only-before-first-game; q=1 is a constant preseason weight.
# These are meaningful reduced models, not unidentified asymptotic limits.
# Positive monotone schedules, no requirement that their coefficients sum to 1.
blend_weights <- function(p,g) {
 t<-pmin(g,12)/12
 list(a=ifelse(t==0,0,p$C*t/(p$shape+(1-p$shape)*t)),
      b=ifelse(t==0,p$B,p$B*p$q/(p$q+(1-p$q)*t)))
}
margin_predict <- function(p,d) {
 h<-blend_weights(p,d$gp_home);a<-blend_weights(p,d$gp_away)
 h$a*d$eff_home-a$a*d$eff_away+h$b*d$pre_home-a$b*d$pre_away+p$hfa*as.numeric(!d$neutral)
}
calibrate_blend_core <- function(d,cfg) {
 if(cfg$exclude_2020)d<-d %>% filter(season!=2020)
 assert(nrow(d)>=500,'Blend needs at least 500 earlier games.')
 # Broad finite numerical guardrails; flag contact instead of silently expanding.
 lower<-c(C=0,shape=0,B=0,q=0,hfa=-5)
 upper<-c(C=6,shape=1,B=6,q=1,hfa=10)
 objective<-function(z)mean(abs(margin_predict(as.list(setNames(z,names(lower))),d)-d$actual_margin))
 starts<-expand.grid(C=c(1,2.5),shape=c(0,.5),B=c(1,2),q=c(.15,.6))
 fits<-lapply(seq_len(nrow(starts)),function(i){
  z<-as.numeric(starts[i,]);optim(c(z,3),objective,method='L-BFGS-B',lower=lower,upper=upper,
    control=list(maxit=600,factr=1e7))
 })
 good<-which(vapply(fits,function(f)f$convergence==0&&is.finite(f$value),logical(1)))
 assert(length(good)>0,'All blend optimizer starts failed to converge.')
 ix<-good[which.min(vapply(fits[good],function(f)f$value,numeric(1)))];best<-fits[[ix]]
 p<-as.list(setNames(best$par,names(lower)))
 edge<-names(lower)[abs(best$par-lower)<1e-3|abs(best$par-upper)<1e-3]
 guard<-intersect(edge,c('C','B','hfa'))
 if(length(guard))warning('Blend numerical guardrail contact: ',paste(guard,collapse=', '),'; inspect fold stability.',call.=FALSE)
 w<-blend_weights(p,0:12)
 list(par=p,training_mae=best$value,n=nrow(d),max_train_season=max(d$season),boundary=edge,
   optimizer=data.frame(start=seq_along(fits),convergence=vapply(fits,`[[`,integer(1),'convergence'),
      mae=vapply(fits,`[[`,numeric(1),'value')),
   schedule=tibble(games_played=0:12,current=w$a,preseason=w$b))
}
calibrate_blend <- function(d,cfg) {
  tag<-key_of(list('blend-v3-2',cfg$exclude_2020,
    d %>% select(season,game_id,neutral,actual_margin,eff_home,eff_away,pre_home,pre_away,gp_home,gp_away)))
  cache(cfg,paste0('blend_',tag),calibrate_blend_core(d,cfg))
}
score_frame <- function(d,blend) {
 d %>% mutate(pred_margin=margin_predict(blend$par,d),error=pred_margin-actual_margin,abs_error=abs(error))
}
summarize_predictions <- function(d, group = NULL) {
  core <- function(x) {
    if (nrow(x) == 0)
      return(tibble(n = 0L, mae = NA_real_, rmse = NA_real_, bias = NA_real_,
                    cor = NA_real_, calib_slope = NA_real_, su_rate = NA_real_))
    tibble(
      n = nrow(x),
      mae = mean(x$abs_error, na.rm = TRUE),
      rmse = sqrt(mean(x$error^2, na.rm = TRUE)),
      # bias = predicted minus actual. Positive means the model favors the home
      # team too much in this cell.
      bias = mean(x$error, na.rm = TRUE),
      cor = tryCatch(if (nrow(x)>1 && stats::sd(x$pred_margin) > 0 && stats::sd(x$actual_margin) > 0) stats::cor(x$pred_margin, x$actual_margin) else NA_real_,
                     error = function(e) NA_real_),
      calib_slope = tryCatch(unname(stats::coef(
        stats::lm(actual_margin ~ pred_margin, data = x))[2]),
        error = function(e) NA_real_),
      su_rate = mean(ifelse(x$actual_margin == 0, NA_real_, ifelse(x$pred_margin == 0, 0.5, as.numeric(sign(x$pred_margin) == sign(x$actual_margin)))), na.rm = TRUE))
  }
  if (is.null(group)) return(core(d))
  d %>% group_by(across(all_of(group))) %>% group_modify(~ core(.x)) %>% ungroup()
}

#' The headline table: MAE by early week, then weeks 5+, then overall.
week_table <- function(d, label = "model") {
  d <- d %>% mutate(bucket = ifelse(week_seq <= 4, paste0("W", week_seq), "W5+"))
  bind_rows(
    summarize_predictions(d, "bucket") %>% rename(cell = bucket),
    summarize_predictions(d) %>% mutate(cell = "ALL")
  ) %>% mutate(model = label, .before = 1) %>%
    arrange(match(cell, c("W1", "W2", "W3", "W4", "W5+", "ALL")))
}

# Season-cluster bootstrap: descriptive uncertainty, few seasons => weak precision.
cluster_interval <- function(d,value='abs_error',reps=2000,seed=9041) {
 z<-d %>% group_by(season) %>% summarise(total=sum(.data[[value]]),n=n(),.groups='drop')
 if(nrow(z)<2)return(tibble(estimate=mean(d[[value]]),low=NA_real_,high=NA_real_,seasons=nrow(z)))
 set.seed(seed);v<-replicate(reps,{i<-sample(seq_len(nrow(z)),nrow(z),replace=TRUE);sum(z$total[i])/sum(z$n[i])})
 tibble(estimate=mean(d[[value]]),low=unname(quantile(v,.025)),high=unname(quantile(v,.975)),seasons=nrow(z))
}
inner_select <- function(components,cfg,before) {
 # Every candidate assessed on exactly the same inner test IDs.
 seasons<-cfg$history_seasons[cfg$history_seasons>=cfg$inner_start&cfg$history_seasons<before]
 if(cfg$exclude_2020)seasons<-setdiff(seasons,2020)
 assert(length(seasons)>0,'No inner validation seasons before requested outer fold.')
 rows<-list();keys<-NULL
 for(n in names(components)) {
  d<-components[[n]]$frame;out<-list()
  for(s in seasons) {
   train<-d %>% filter(season<s);test<-d %>% filter(season==s)
   assert(nrow(test)>0,'Missing inner test season.')
   b<-calibrate_blend(train,cfg)
   assert(b$max_train_season<s,'Inner blend leakage.')
   out[[as.character(s)]]<-score_frame(test,b)
  }
  o<-bind_rows(out);k<-sort(paste(o$season,o$game_id))
  if(is.null(keys))keys<-k else assert(identical(k,keys),'Candidate inner samples differ.')
  rows[[n]]<-o %>% group_by(season) %>% summarise(n=n(),mae=mean(abs_error),.groups='drop') %>% mutate(candidate=.env$n)
 }
 by_season<-bind_rows(rows)
 tab<-by_season %>% group_by(candidate) %>% summarise(mae=weighted.mean(mae,n),.groups='drop')
 # Predeclared tolerance 0.05 points favors earlier (simpler) candidate. No outer outcomes.
 best<-min(tab$mae);eligible<-tab$candidate[tab$mae<=best+.05]
 selected<-names(components)[names(components)%in%eligible][1]
 list(selected=selected,table=tab,by_season=by_season,last_inner_season=max(seasons))
}
fit_baselines <- function(train,test,cfg) {
 if(cfg$exclude_2020)train<-train %>% filter(season!=2020)
 hi<-as.numeric(!train$neutral)
 hfa<-median(train$actual_margin[hi==1])
 z<-optim(c(1,3),function(p)mean(abs(train$actual_margin-p[1]*(train$pre_home-train$pre_away)-p[2]*hi)),
   method='Nelder-Mead',control=list(maxit=3000))
 assert(z$convergence==0,'Preseason baseline failed to converge.')
 make<-function(p,label)test %>% mutate(pred_margin=p,error=p-actual_margin,abs_error=abs(error),model=label)
 bind_rows(make(as.numeric(!test$neutral)*hfa,'home-only median'),
   make(z$par[1]*(test$pre_home-test$pre_away)+z$par[2]*as.numeric(!test$neutral),'preseason only'),
   make(rep(0,nrow(test)),'neutral zero'))
}
fit_model_artifacts <- function(cfg=cfb_config(),refresh=FALSE,target_season=max(cfg$history_seasons)+1L) {
 assert(all(cfg$history_seasons<target_season),'History includes target season or future.')
 assert(all(diff(cfg$history_seasons)==1),'History years must be consecutive.')
 assert(!anyDuplicated(vapply(cfg$candidates,`[[`,character(1),'label')),'Duplicate candidate labels.')
 schedules<-setNames(lapply(cfg$history_seasons,read_schedule,cfg=cfg,refresh=refresh),cfg$history_seasons)
 features<-load_features(cfg,schedules)
 components<-list()
 for(sp in cfg$candidates) {
   tag<-key_of(list(cfg$version,sp,cfg$features,features,cfg$history_seasons,cfg$exclude_2020,cfg$availability_hours,
     lapply(schedules,function(g)g %>% select(game_id,kickoff,home_id,away_id,home_fbs,away_fbs,neutral,home_points,away_points,final))))
   components[[sp$label]]<-cache(cfg,paste0('components_',tag),build_component_frame(cfg,sp,schedules,features),refresh)
   audit_leakage(components[[sp$label]])
 }
 selection<-inner_select(components,cfg,target_season)
 cp<-components[[selection$selected]];blend<-calibrate_blend(cp$frame,cfg)
 pm<-fit_preseason(cp$features,cp$history,target_season,cfg)
 a<-list(cfg=cfg,target_season=target_season,components=components,selection=selection,
   blend=blend,preseason_model=pm,feature_snapshots=features,history=cp$history,built_at=Sys.time())
 saveRDS(a,file.path(cfg$cache_dir,paste0('production_',target_season,'.rds')))
 a
}
run_validation <- function(cfg=cfb_config(),artifacts=NULL,include_market=TRUE,lines_file=NULL) {
 if(is.null(artifacts))artifacts<-fit_model_artifacts(cfg)
 cfg<-artifacts$cfg;cs<-artifacts$components;out<-list();base<-list();folds<-list();sched<-list();aud<-list()
 for(n in names(cs))aud[[n]]<-audit_leakage(cs[[n]]) %>% mutate(candidate=.env$n)
 for(s in cfg$outer_seasons) {
  assert(s%in%cfg$history_seasons,'Outer season missing from history.')
  selection<-inner_select(cs,cfg,s)
  c<-cs[[selection$selected]];tr<-c$frame %>% filter(season<s);te<-c$frame %>% filter(season==s)
  b<-calibrate_blend(tr,cfg)
  assert(b$max_train_season<s&&selection$last_inner_season<s,'Outer calibration/selection leakage.')
  assert(all(te$pre_max_season<s),'Outer preseason leakage.')
  out[[as.character(s)]]<-score_frame(te,b) %>% mutate(candidate=selection$selected,calibration_max_season=b$max_train_season)
  base[[as.character(s)]]<-fit_baselines(tr,te,cfg)
  folds[[as.character(s)]]<-tibble(season=s,candidate=selection$selected,inner_last=selection$last_inner_season,
    hfa=b$par$hfa,carryover=c$pre_fits[[as.character(s)]]$carryover,
    training_mae=b$training_mae,boundary=paste(b$boundary,collapse=','))
  sched[[as.character(s)]]<-b$schedule %>% mutate(season=s)
 }
 d<-bind_rows(out);baselines<-bind_rows(base)
 assert(nrow(d)>0,'No outer predictions.')
 # Diagnostics explain composition; no regression here changes predictions.
 early<-d %>% filter(week_seq<=4) %>% mutate(home_pre_favorite=pre_home>pre_away,
   promoted=promoted_home==1|promoted_away==1)
 rank_drops<-bind_rows(lapply(names(cs),function(n)bind_rows(lapply(names(cs[[n]]$pre_fits),function(s){
   dr<-cs[[n]]$pre_fits[[s]]$design$dropped
   tibble(candidate=n,season=as.integer(s),predictor=names(dr),reason=unlist(dr,use.names=FALSE))
 }))))
 result<-list(headline=summarize_predictions(d),mae_interval=cluster_interval(d,reps=cfg$bootstrap_reps,seed=cfg$seed),
  by_week_bucket=week_table(d),by_week=summarize_predictions(d,c('week_seq')),
  by_season=summarize_predictions(d,'season'),by_provider_week=summarize_predictions(d,c('season_type','week')),
  by_games_played=summarize_predictions(d %>% mutate(gp=pmin(gp_home,gp_away)),'gp'),folds=bind_rows(folds),weight_schedule=bind_rows(sched),
  early_site=summarize_predictions(early,c('week_seq','neutral')),
  early_composition=summarize_predictions(early,c('week_seq','home_pre_favorite','promoted')),
  baselines=summarize_predictions(baselines,'model'),scored=d,baseline_predictions=baselines,
  leakage_audit=bind_rows(aud),dropped_predictors=rank_drops,
  feature_status=tibble(feature=c('talent','returning_off','returning_def','coaching','portal','EPA'),
    status=c(ifelse(c('talent','returning_off','returning_def','coaching','portal')%in%cfg$features,
      'Enabled from user-supplied dated snapshot; inspect dropped_predictors',
      'Disabled: requires audited preseason snapshot'), 'Disabled: scoring-equivalent EPA not validated')))
 if(include_market) result$market<-benchmark_market(d,cfg,lines_file)
 result$checks<-tibble(check=c('All outer parameters fitted on earlier seasons','Finite predictions',
    'Overall calibration slope within 0.2 of 1','Overall absolute bias below 1.5','Early-week absolute bias below 1.5','No numerical blend guardrail contact'),
   pass=c(all(d$calibration_max_season<d$season&d$pre_max_season<d$season),all(is.finite(d$pred_margin)),
     abs(result$headline$calib_slope-1)<.2,abs(result$headline$bias)<1.5,
     all(abs(summarize_predictions(early,'week_seq')$bias)<1.5),
     !any(grepl('C|B|hfa',result$folds$boundary))))
 print(result$headline);print(result$by_season);print(result$folds)
 result
}
# CFBD spread benchmark is explicitly 'latest available', not verified closing.
# A verified closing file may have game_id,spread,provider,line_type='closing',
# recorded_at (ISO UTC). Confirm source semantics before labeling it closing.
benchmark_market <- function(scored,cfg,lines_file=NULL) {
 verified<-!is.null(lines_file)
 if(verified) raw<-read.csv(lines_file,stringsAsFactors=FALSE) else {
  raw<-tryCatch(cache(cfg,paste0('market_',min(scored$season),'_',max(scored$season)),{
    old<-file.path(cfg$source_cache,paste0('lines_',min(scored$season),'_',max(scored$season),'.rds'))
    if(file.exists(old))readRDS(old) else {
      assert(nzchar(Sys.getenv('CFBD_API_KEY')),'CFBD_API_KEY absent; provide a closing-line file or skip benchmark.')
      bind_rows(lapply(sort(unique(scored$season)),function(s)bind_rows(lapply(c('regular','postseason'),function(st)
        cfbfastR::cfbd_betting_lines(year=s,season_type=st)))))
    }
  }),error=function(e){warning(conditionMessage(e),call.=FALSE);NULL})
 }
 if(is.null(raw)||!nrow(raw))return(list(status='Unavailable',coverage=0))
 if(!'game_id'%in%names(raw)&&'id'%in%names(raw))names(raw)[names(raw)=='id']<-'game_id'
 assert(all(c('game_id','spread','provider')%in%names(raw)),'Market schema missing required fields.')
 raw<-as_tibble(raw) %>% mutate(game_id=as.character(game_id),spread=as.numeric(spread)) %>% filter(is.finite(spread))
 if(verified){
  assert(all(c('line_type','recorded_at')%in%names(raw)),'Closing file needs line_type and recorded_at.')
  assert(all(raw$line_type=='closing'),'Mixed/non-closing lines in closing file.')
  raw$recorded_at<-utc(raw$recorded_at)
  assert(!anyNA(raw$recorded_at),'Unknown line recording time.')
 }
 # Fixed provider priority, never selected using outcome performance.
 raw<-raw %>% mutate(priority=match(tolower(provider),c('consensus','draftkings','bovada','espn bet')),
  priority=coalesce(priority,99L)) %>% arrange(game_id,priority,provider)
 if(verified)raw<-raw %>% arrange(game_id,priority,provider,desc(recorded_at))
 assert(!anyDuplicated(paste(raw$game_id,raw$provider,if(verified)raw$recorded_at else '')),'Ambiguous duplicate market records.')
 raw<-raw %>% distinct(game_id,.keep_all=TRUE) %>% select(game_id,spread,provider,any_of(c('recorded_at','line_type')))
 d<-inner_join(scored,raw,by='game_id')
 if(verified)assert(all(d$recorded_at<=d$kickoff),'Closing timestamp after kickoff.')
 if(!nrow(d))return(list(status='No matched lines',coverage=0))
 m<-d %>% mutate(pred_margin=-spread,error=pred_margin-actual_margin,abs_error=abs(error))
 # Fixed documented home-spread sign. Never flip using test outcomes.
 dif<-d %>% mutate(delta=abs_error-abs(-spread-actual_margin))
 list(status=if(verified)'verified closing (user supplied source)' else 'CFBD latest available; closing status unverified',
   coverage=nrow(d)/nrow(scored),n=nrow(d),model_same_games=summarize_predictions(d),market=summarize_predictions(m),
   paired_mae_difference=cluster_interval(dif,'delta',cfg$bootstrap_reps,cfg$seed),
   by_season=summarize_predictions(m,'season'),predictions=m)
}

graph_diagnostics <- function(tg,ids) {
  n<-length(ids);adj<-matrix(FALSE,n,n)
  e<-tg %>% filter(team_id%in%ids,opp_id%in%ids) %>% distinct(team_id,opp_id)
  if(nrow(e))adj[cbind(match(e$team_id,ids),match(e$opp_id,ids))]<-TRUE
  adj<-adj|t(adj);component<-integer(n);k<-0L
  for(i in seq_len(n))if(component[i]==0L){
    k<-k+1L;todo<-i;component[i]<-k
    while(length(todo)){
      j<-todo[1];todo<-todo[-1];next_ids<-which(adj[j,]&component==0L)
      component[next_ids]<-k;todo<-c(todo,next_ids)
    }
  }
  largest<-as.integer(names(which.max(table(component))))
  tibble(team_id=ids,n_fbs_opponents=as.integer(rowSums(adj)),
    graph_component=component,in_main_component=component==largest)
}
build_power_ratings <- function(season,artifacts,as_of=period_start(Sys.time()),refresh_schedule=TRUE) {
 cfg<-artifacts$cfg
 assert(season==artifacts$target_season,'Production artifacts belong to a different season.')
 as_of<-as.POSIXct(as_of,tz='UTC');assert(length(as_of)==1&&!is.na(as_of),'Supply a valid as_of timestamp.')
 g<-read_schedule(season,cfg,refresh_schedule);ids<-fbs_ids(g)
 cp<-artifacts$components[[artifacts$selection$selected]]
 features<-load_features(cfg,setNames(list(g),season))
 f<-features_for(season,ids,cp$history,features,cfg)
 pre<-predict_preseason(artifacts$preseason_model,f)
 # Same conservative availability rule as historical folds, arbitrary explicit as_of allowed.
 tg<-team_games(g,ids,cp$spec$fcs_weight) %>% filter(available_at<as_of)
 hfa<-median(unique(cp$history %>% select(season,hfa))$hfa)
 ef<-fit_efficiency(tg,ids,cp$spec,hfa)
 r<-left_join(pre,ef$ratings,by='team_id');w<-blend_weights(artifacts$blend$par,r$games_played)
 r$w_current<-w$a;r$w_preseason<-w$b
 r$off_rating<-w$a*r$eff_off+w$b*r$pre_off;r$def_rating<-w$a*r$eff_def+w$b*r$pre_def
 r$off_center<-mean(r$off_rating);r$def_center<-mean(r$def_rating)
 r$off_rating<-r$off_rating-r$off_center;r$def_rating<-r$def_rating-r$def_center
 r$power_rating<-r$off_rating-r$def_rating
 # Explicit weighted component decomposition including the common centering term.
 r$current_contribution<-w$a*r$eff_power;r$preseason_contribution<-w$b*r$pre_power
 r$centering_contribution<- -r$off_center+r$def_center
 # SOS includes FCS only if the fitted pooled candidate includes them.
 opp<-setNames(r$eff_power,r$team_id)
 op<-as.numeric(opp[as.character(tg$opp_id)])
 if(!is.null(ef$fcs))op[!tg$opp_id%in%ids]<-ef$fcs
 sos<-tg %>% mutate(opp_power=op) %>% filter(team_id%in%ids) %>% group_by(team_id) %>%
 summarise(sos=mean(opp_power-2*hx*hfa),raw_margin_pg=mean(pf-pa),n_fcs_opp=sum(!opp_id%in%ids),.groups='drop')
 nm<-bind_rows(g %>% transmute(team_id=home_id,team=home_team),g %>% transmute(team_id=away_id,team=away_team)) %>% distinct(team_id,.keep_all=TRUE)
 r<-r %>% left_join(graph_diagnostics(tg,ids),by='team_id') %>% left_join(nm,by='team_id') %>% left_join(sos,by='team_id') %>% arrange(desc(power_rating)) %>%
 mutate(rank=row_number(),off_rank=min_rank(desc(off_rating)),def_rank=min_rank(def_rating))
 attr(r,'hfa')<-artifacts$blend$par$hfa;attr(r,'season')<-season;attr(r,'as_of')<-as_of
 attr(r,'training_ids')<-unique(tg$game_id)
 assert(all(is.finite(r$power_rating)),'Non-finite production ratings.')
 assert(abs(mean(r$power_rating))<1e-8,'Centering failed.')
 assert(max(abs(r$power_rating-r$current_contribution-r$preseason_contribution-r$centering_contribution))<1e-8,'Component identity failed.')
 r
}
predict_game <- function(ratings,home,away,neutral=FALSE) {
 get<-function(x){i<-if(is.numeric(x))which(ratings$team_id==x) else which(ratings$team==x)
   assert(length(i)==1,paste('Team not uniquely identified:',x));ratings$power_rating[i]}
 h<-get(home);a<-get(away);hf<-if(neutral)0 else attr(ratings,'hfa')
 tibble(home=home,away=away,neutral=neutral,home_rating=h,away_rating=a,hfa_applied=hf,
   projected_margin=h-a+hf,home_spread=-(h-a+hf))
}
run_sanity_checks <- function(ratings,artifacts=NULL) {
 tibble(check=c('Unique FBS IDs','Finite ratings','Zero-centered','power = off - def','Component contributions sum to power',
    'Rating SD between 7 and 22 (diagnostic)','HFA between 0.5 and 5 (diagnostic)'),
 pass=c(!anyDuplicated(ratings$team_id),all(is.finite(ratings$power_rating)),abs(mean(ratings$power_rating))<1e-8,
   max(abs(ratings$power_rating-ratings$off_rating+ratings$def_rating))<1e-8,
   max(abs(ratings$power_rating-ratings$current_contribution-ratings$preseason_contribution-ratings$centering_contribution))<1e-8,
   sd(ratings$power_rating)>7&&sd(ratings$power_rating)<22,attr(ratings,'hfa')>.5&&attr(ratings,'hfa')<5))
}
print_ratings <- function(ratings,n=25) {
 print(as.data.frame(head(ratings %>% select(rank,team,team_id,power_rating,off_rating,def_rating,games_played,w_current,w_preseason,sos),n)),digits=3,row.names=FALSE)
 invisible(ratings)
}
export_diagnostics <- function(v,artifacts,ratings=NULL,directory='diagnostics_v3') {
 dir.create(directory,recursive=TRUE,showWarnings=FALSE)
 write<-function(x,n)if(is.data.frame(x))write.csv(x,file.path(directory,paste0(n,'.csv')),row.names=FALSE)
 for(n in names(v))write(v[[n]],n)
 if(!is.null(v$market))for(n in names(v$market))write(v$market[[n]],paste0('market_',n))
 write(artifacts$blend$schedule,'production_weights')
 write(artifacts$selection$table,'production_inner_selection')
 write(artifacts$selection$by_season,'production_inner_by_season')
 write(data.frame(term=names(artifacts$preseason_model$off),off=artifacts$preseason_model$off,def=artifacts$preseason_model$def),'production_preseason_coefficients')
 if(!is.null(ratings)) {
  write(ratings,'ratings');write(run_sanity_checks(ratings),'rating_checks')
  write(tibble(n=nrow(ratings),mean=mean(ratings$power_rating),sd=sd(ratings$power_rating),
    min=min(ratings$power_rating),q10=quantile(ratings$power_rating,.1),median=median(ratings$power_rating),
    q90=quantile(ratings$power_rating,.9),max=max(ratings$power_rating)),'rating_distribution')
 }
 saveRDS(v,file.path(directory,'validation.rds'))
 capture.output(sessionInfo(),file=file.path(directory,'sessionInfo.txt'))
 capture.output(str(list(version=artifacts$cfg$version,selected=artifacts$selection$selected,
   blend=artifacts$blend$par,carryover=artifacts$preseason_model$carryover,
   market_status=v$market$status)),file=file.path(directory,'summary.txt'))
 invisible(directory)
}
# Features must be predeclared. These ablations compare complete nested pipelines
# on paired outer games; do not select the winner on these same outer outcomes.
compare_preseason_specs <- function(cfg=cfb_config(),reference=NULL) {
 if(is.null(reference))reference<-run_validation(cfg,include_market=FALSE)
 result<-list();pred<-list()
 if(!length(cfg$features))return(list(status='No optional features enabled. Scores-only is the strict default.',
   results=tibble(spec='carryover offense/defense',mae=reference$headline$mae)))
 for(t in cfg$features) {
  c2<-cfg;c2$features<-setdiff(cfg$features,t)
  v<-run_validation(c2,include_market=FALSE)
  p<-inner_join(reference$scored %>% select(season,game_id,reference=abs_error),
    v$scored %>% select(season,game_id,alternative=abs_error),by=c('season','game_id'))
  assert(nrow(p)==nrow(reference$scored),'Ablation changed validation sample.')
  p$delta<-p$alternative-p$reference
  result[[t]]<-cluster_interval(p,'delta',cfg$bootstrap_reps,cfg$seed) %>% mutate(spec=paste('without',t))
  pred[[t]]<-p %>% group_by(season) %>% summarise(delta_mae=mean(delta),.groups='drop') %>% mutate(spec=paste('without',t))
 }
 list(results=bind_rows(result),by_season=bind_rows(pred),interpretation='Positive delta favors full specification; few-season intervals are descriptive.')
}
tune_efficiency <- function(cfg=cfb_config(),artifacts=NULL) {
 if(is.null(artifacts))artifacts<-fit_model_artifacts(cfg)
 # This is prior-season inner tuning for the next production year, not a new headline score.
 artifacts$selection
}
tune_response <- function(...)stop('EPA disabled. Supply a separately audited points/EPA feature implementation and rerun nested selection before enabling it.',call.=FALSE)
