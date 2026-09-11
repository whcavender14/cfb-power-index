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

# ============================================================================
# V4 audited entry points. Legacy helpers above are retained for v3 comparison.
# Use v4_* functions only; no work is performed on source().
# ============================================================================
v4_config <- function() cfb_config(cache_dir='outputs/round3/cache',
 source_cache='cfb_data_v3',history_seasons=2015:2022,version='4.0.0')
v4_schedule <- function(s) {
 cfg<-v4_config(); f<-file.path('cfb_data_v3',paste0('raw_schedule_',s,'.rds'))
 assert(file.exists(f),paste('Missing audited local schedule',f))
 # Read-only adapter; never copy unknown fields into the model design.
 cfg$cache_dir<-'cfb_data_v3';read_schedule(s,cfg,FALSE)
}
v4_graph <- function(g,ids,cutoff) {
 g<-g %>% filter(final,available_at<cutoff)
 nm<-bind_rows(g %>% transmute(team_id=home_id,conf=home_conference),
              g %>% transmute(team_id=away_id,conf=away_conference)) %>% distinct(team_id,.keep_all=TRUE)
 tg<-team_games(g,ids,0);z<-graph_diagnostics(tg,ids)
 z$component_size<-as.integer(table(z$graph_component)[as.character(z$graph_component)])
 edges<-bind_rows(g %>% transmute(team_id=home_id,opp_id=away_id,fbs=away_fbs,
    conf=home_conference,opp_conf=away_conference,margin=home_points-away_points),
   g %>% transmute(team_id=away_id,opp_id=home_id,fbs=home_fbs,
    conf=away_conference,opp_conf=home_conference,margin=away_points-home_points))
 p4<-c('SEC','Big Ten','Big 12','ACC','Pac-12') # Historical power-conference bucket, not predictor.
 q<-edges %>% filter(team_id%in%ids) %>% group_by(team_id) %>% summarise(
   n_cross=n_distinct(opp_id[fbs & !is.na(opp_conf)&!is.na(conf)&opp_conf!=conf]),
   n_p4=sum(fbs & opp_conf%in%p4),n_fcs=sum(!fbs),
   one_score=ifelse(sum(fbs)>0,mean(abs(margin[fbs])<=8),0),.groups='drop')
 z<-left_join(z,q,by='team_id')
 for(n in c('n_cross','n_p4','n_fcs','one_score'))z[[n]][is.na(z[[n]])]<-0
 left_join(z,nm,by='team_id')
}
# Posterior mean solves the penalized score likelihood directly. Fixed HFA
# contributes +H/2 to home PF and -H/2 to away PF: exactly H in margin.
v4_score_fit <- function(tg,ids,prior=NULL,lambda=8,hfa=3,zero_penalty=NULL,
                         cap=Inf,def_lambda=lambda,variance=FALSE,half_life=Inf,cutoff=NULL) {
 nt<-length(ids);extra<-unique(c(tg$entity,tg$opponent));extra<-setdiff(extra,as.character(ids))
 ents<-c(as.character(ids),extra);ne<-length(ents)
 if(is.null(prior))prior<-tibble(team_id=ids,pre_off=0,pre_def=0)
 prior<-prior[match(ids,prior$team_id),];assert(!anyNA(prior$team_id),'Prior IDs missing')
 po<-c(prior$pre_off,rep(0,length(extra)));pd<-c(prior$pre_def,rep(0,length(extra)))
 lo<-c(rep_len(lambda,nt),rep(8,length(extra)));ld<-c(rep_len(def_lambda,nt),rep(8,length(extra)))
 zp<-c(if(is.null(zero_penalty))rep(0,nt) else zero_penalty,rep(0,length(extra)))
 if(!nrow(tg)) {
  o<-po[seq_len(nt)]*lo[seq_len(nt)]/(lo[seq_len(nt)]+zp[seq_len(nt)])
  d<-pd[seq_len(nt)]*ld[seq_len(nt)]/(ld[seq_len(nt)]+zp[seq_len(nt)])
  vv<-1/(lo[seq_len(nt)]+zp[seq_len(nt)])+1/(ld[seq_len(nt)]+zp[seq_len(nt)])
 } else {
  n<-nrow(tg);ti<-match(tg$entity,ents);oi<-match(tg$opponent,ents)
  X<-sparseMatrix(i=rep(seq_len(n),3),j=c(rep(1L,n),1L+ti,1L+ne+oi),x=1,dims=c(n,1L+2L*ne))
  y<-(tg$pf+tg$pa)/2+pmax(-cap,pmin(cap,tg$pf-tg$pa))/2-hfa*tg$hx
  w<-tg$weight
  if(is.finite(half_life))w<-w*2^(-as.numeric(difftime(cutoff,tg$available_at,units='weeks'))/half_life)
  P<-c(0,lo+zp,ld+zp);Q<-crossprod(X,Diagonal(x=w)%*%X)+Diagonal(x=P)
  b<-as.numeric(solve(Q,crossprod(X,w*y)+c(0,lo*po,ld*pd)))
  o<-b[1L+seq_len(nt)];d<-b[1L+ne+seq_len(nt)]
  vv<-rep(NA_real_,nt)
  if(variance) {
   # Centered power contrast removes unidentified common scoring level.
   Z<-matrix(0,1+2*ne,nt);Z[1+seq_len(nt),]<-diag(nt)-1/nt
   Z[1+ne+seq_len(nt),]<- -(diag(nt)-1/nt)
   vv<-colSums(Z*as.matrix(solve(Q,Z)))
  }
 }
 counts<-table(tg$team_id[tg$team_id%in%ids & tg$opp_id%in%ids]);gp<-as.integer(counts[as.character(ids)]);gp[is.na(gp)]<-0L
 tibble(team_id=ids,eff_off=o-mean(o),eff_def=d-mean(d),eff_power=eff_off-eff_def,
        games_played=gp,variance=vv)
}
v4_history <- function(schedules) bind_rows(lapply(names(schedules),function(sn){
 g<-schedules[[sn]];ids<-fbs_ids(g)
 # Same historical estimator as v3 for HFA; no use of target-season HFA in predictions.
 hf<-fit_efficiency(team_games(g,ids,0),ids,list(lambda=1,cap=Inf,fcs_weight=0))$hfa
 r<-v4_score_fit(team_games(g,ids,0),ids,lambda=1,hfa=hf,variance=TRUE)
 r %>% mutate(season=as.integer(sn),hfa=hf)
}))
v4_pre <- function(s,ids,history,max_training=min(s-1,2022)) {
 cfg<-v4_config();hs<-history %>% filter(season<=max_training)
 fh<-bind_rows(lapply(sort(unique(hs$season)),function(y)features_for(y,hs$team_id[hs$season==y],hs,NULL,cfg)))
 pm<-fit_preseason(fh,hs,max_training+1,cfg)
 f<-features_for(s,ids,history,NULL,cfg);r<-predict_preseason(pm,f)
 vv<-history %>% filter(season==s-1) %>% select(team_id,variance)
 r<-left_join(r,vv,by='team_id');med<-median(r$variance,na.rm=TRUE)
 r$u<-0.5*r$variance/med;r$u[!is.finite(r$u)]<-2
 list(r=r,pm=pm)
}
v4_components <- function(schedules,history,seasons) {
 out<-list();snap<-list()
 for(s in seasons) {
  message('v4 components ',s);g<-schedules[[as.character(s)]];ids<-fbs_ids(g)
  pp<-v4_pre(s,ids,history);pre<-pp$r
  hf<-median(unique(history %>% filter(season<min(s,2023)) %>% select(season,hfa))$hfa)
  weeks<-sort(unique(g$period[g$home_fbs|g$away_fbs]))
  for(j in seq_along(weeks)) {
   cut<-weeks[j];te<-g %>% filter(final,home_fbs,away_fbs,period==cut)
   if(!nrow(te))next
   tg<-team_games(g,ids,0) %>% filter(available_at<cut)
   audit_fold(tg,te,cut,pp$pm$max_train_season,s)
   ef<-v4_score_fit(tg,ids,lambda=1,hfa=hf)
   rr<-left_join(pre,ef %>% select(-variance),by='team_id')
   gr<-v4_graph(g,ids,cut);rr<-left_join(rr,gr,by='team_id')
   h<-rr[match(te$home_id,rr$team_id),];a<-rr[match(te$away_id,rr$team_id),]
   row<-te %>% select(season,game_id,week,kickoff,neutral,home_id,away_id,home_conference,away_conference) %>%
    mutate(cutoff=cut,week_seq=j,actual_margin=te$home_points-te$away_points,
           eff_home=h$eff_power,eff_away=a$eff_power,pre_home=h$pre_power,pre_away=a$pre_power,
           gp_home=h$games_played,gp_away=a$games_played)
   for(n in c('u','component_size','n_fbs_opponents','n_cross','n_p4','n_fcs','one_score','promoted')) {
    row[[paste0(n,'_home')]]<-h[[n]];row[[paste0(n,'_away')]]<-a[[n]]
   }
   row$prior_home<-h$prev_off-h$prev_def;row$prior_away<-a$prev_off-a$prev_def
   key<-paste(s,j,sep='_');out[[key]]<-row
   snap[[key]]<-list(season=s,cutoff=cut,ids=ids,pre=pre,tg=tg,graph=gr,test=te,
                    rows=rr,hfa=hf,pre_max=pp$pm$max_train_season)
  }
 }
 list(frame=bind_rows(out),snap=snap)
}
v4_scale <- function(d) {
 assert(all(d$season<=2022),'Locked outcome in scale fitting')
 d<-d %>% filter(season!=2020)
 X<-cbind(pre=d$pre_home-d$pre_away,site=as.numeric(!d$neutral))
 assert(qr(X)$rank==2,'Preseason calibration rank deficient')
 f<-quantreg::rq.fit.fnb(X,d$actual_margin,tau=.5)
 assert(all(is.finite(f$coefficients)) && f$coefficients[1]>0,'Preseason scale fit failed')
 list(scale=unname(f$coefficients[1]),hfa=unname(f$coefficients[2]),max_train=max(d$season))
}
v4_blend <- function(d,kind,scale) {
 assert(all(d$season<=2022),'Locked outcome in handoff fitting')
 d<-d %>% filter(season!=2020)
 pred<-function(z) {
  n<-d$gp_home;m<-d$gp_away;k<-exp(z[1]);w<-n/(n+k);v<-m/(m+k)
  if(kind=='A') {
   t<-exp(z[2]);C<-exp(z[3]);w<-C*n/(n+t);v<-C*m/(m+t)
   b<-k/(n+k);c<-k/(m+k)
  } else {b<-1-w;c<-1-v}
  w*d$eff_home-v*d$eff_away+scale$scale*(b*d$pre_home-c*d$pre_away)+scale$hfa*!d$neutral
 }
 if(kind=='B') {
  # Search compact log-k domain, audit boundary; no observed weight exceeds 1.
  f<-optimize(function(z)mean(abs(pred(z)-d$actual_margin)),interval=c(-8,10),tol=1e-8)
  assert(abs(f$minimum+8)>1e-4 && abs(f$minimum-10)>1e-4,'B optimum at search guardrail')
  return(list(kind=kind,k=exp(f$minimum),t=NA_real_,C=1,scale=scale))
 }
 fs<-lapply(c(2,8,20),function(k)optim(if(kind=='A')log(c(k,2,1.5)) else log(k),
   function(z)mean(abs(pred(z)-d$actual_margin)),method='Nelder-Mead',control=list(maxit=3000)))
 fs<-Filter(function(x)x$convergence==0&&is.finite(x$value),fs);assert(length(fs)>0,'Handoff optimizer failed')
 z<-fs[[which.min(sapply(fs,`[[`,'value'))]]$par
 list(kind=kind,k=exp(z[1]),t=if(kind=='A')exp(z[2]) else NA_real_,C=if(kind=='A')exp(z[3]) else 1,scale=scale)
}
v4_specs <- function() list(
 A=list(kind='A'),B=list(kind='B'),C=list(kind='EB',lambda=8),D=list(kind='EB',lambda=8,structural=TRUE),
 C4=list(kind='EB',lambda=4),C12=list(kind='EB',lambda=12),
 Ccap32=list(kind='EB',lambda=8,cap=32),Casym=list(kind='EB',lambda=4,def_lambda=12),
 Crecent=list(kind='EB',lambda=8,half_life=8),CFCS=list(kind='EB',lambda=8,fcs_weight=.25),
 no_prior=list(kind='EB',lambda=8,no_prior=TRUE),pre_only=list(kind='pre'))
`%or%` <- function(x,y)if(is.null(x))y else x
v4_ratings <- function(sn,spec,scale,blend=NULL) {
 pre<-sn$pre;pre$pre_off<-pre$pre_off*scale$scale;pre$pre_def<-pre$pre_def*scale$scale
 if(isTRUE(spec$no_prior)){pre$pre_off[]<-0;pre$pre_def[]<-0}
 n<-sn$rows$games_played
 if(spec$kind%in%c('A','B','pre')) {
  if(spec$kind=='pre'){a<-rep(0,length(n));b<-rep(1,length(n))} else {
   b<-blend$k/(n+blend$k)
   a<-if(spec$kind=='A')blend$C*n/(n+blend$t) else 1-b
  }
  # A uses ridge6 with scale calibration, B uses ridge1.
  ef<-if(spec$kind=='A')v4_score_fit(sn$tg,sn$ids,lambda=6,hfa=sn$hfa) else sn$rows
  o<-a*ef$eff_off+b*pre$pre_off;d<-a*ef$eff_def+b*pre$pre_def
  pc<-b*(pre$pre_off-pre$pre_def);current<-a*ef$eff_power
  r<-tibble(team_id=sn$ids,games_played=n,raw_off=o,raw_def=d,
            prior_contribution=pc,current_contribution=current,w_current=a,w_preseason=b)
 } else {
  lam<-rep(spec$lambda,length(n));dl<-rep(spec$def_lambda%or%spec$lambda,length(n));zp<-NULL
  if(isTRUE(spec$structural)) {
   pre$pre_off<-pre$pre_off/(1+pre$u);pre$pre_def<-pre$pre_def/(1+pre$u)
   lam<-lam/(1+pre$u);dl<-dl/(1+pre$u);zp<-2/(1+sn$graph$n_cross)
  }
  args<-list(tg=sn$tg,ids=sn$ids,prior=pre,lambda=lam,def_lambda=dl,hfa=scale$hfa,
             zero_penalty=zp,cap=spec$cap%or%Inf,half_life=spec$half_life%or%Inf,cutoff=sn$cutoff)
  ef<-do.call(v4_score_fit,args)
  # Exact linear decomposition through the coupled score solve, including intercept.
  zero<-pre;zero$pre_off[]<-0;zero$pre_def[]<-0;args$prior<-zero
  dat<-do.call(v4_score_fit,args)
  r<-ef %>% transmute(team_id,games_played,raw_off=eff_off,raw_def=eff_def,
     prior_contribution=eff_power-dat$eff_power,current_contribution=dat$eff_power,
     w_current=NA_real_,w_preseason=NA_real_)
 }
 r$centering_contribution<- -mean(r$raw_off)+mean(r$raw_def)
 r$off_rating<-r$raw_off-mean(r$raw_off);r$def_rating<-r$raw_def-mean(r$raw_def)
 r$power_rating<-r$off_rating-r$def_rating
 attr(r,'hfa')<-scale$hfa;attr(r,'as_of')<-sn$cutoff
 attr(r,'training_ids')<-unique(sn$tg$game_id)
 assert(max(abs(r$power_rating-r$prior_contribution-r$current_contribution-r$centering_contribution))<1e-7,'Contribution mismatch')
 r
}
v4_predict <- function(r,h,a,neutral) r$power_rating[match(h,r$team_id)]-r$power_rating[match(a,r$team_id)]+attr(r,'hfa')*!neutral
v4_evaluate <- function(cp,spec,scale,blend=NULL,schedules=NULL) {
 out<-list()
 for(k in names(cp$snap)) {
  sn<-cp$snap[[k]]
  if((spec$fcs_weight%or%0)>0)sn$tg<-team_games(schedules[[as.character(sn$season)]],sn$ids,spec$fcs_weight) %>% filter(available_at<sn$cutoff)
  r<-v4_ratings(sn,spec,scale,blend)
  te<-cp$frame %>% filter(season==sn$season,cutoff==sn$cutoff)
  te$pred_margin<-v4_predict(r,te$home_id,te$away_id,te$neutral)
  te$error<-te$pred_margin-te$actual_margin;te$abs_error<-abs(te$error);out[[k]]<-te
 }
 bind_rows(out)
}
v4_subset <- function(cp,seasons)list(frame=cp$frame %>% filter(season%in%seasons),
 snap=Filter(function(x)x$season%in%seasons,cp$snap))
v4_write <- function(x,name)write.csv(x,file.path('outputs/round3',paste0(name,'.csv')),row.names=FALSE)
v4_paired <- function(d,base) {
 assert(setequal(d$game_id,base$game_id),'Paired samples differ')
 q<-d %>% left_join(base %>% select(game_id,baseline_error=abs_error),by='game_id') %>% mutate(delta=abs_error-baseline_error)
 cbind(cluster_interval(q,'delta'),improved=sum(tapply(q$delta,q$season,mean)<0))
}
v4_archive <- function(predictions,path) {
 assert(!file.exists(path),'Archive exists: refusing overwrite')
 assert(all(predictions$kickoff>Sys.time()),'Prospective archive contains games already started')
 assert(!any(c('actual_margin','home_points','away_points','spread','line')%in%names(predictions)),'Outcomes/market fields prohibited in prospective archive')
 dir.create(dirname(path),recursive=TRUE,showWarnings=FALSE)
 con<-file(path,open='wx');on.exit(close(con));write.csv(predictions,con,row.names=FALSE)
 # Application-level append-only plus integrity digest; not hardware WORM storage.
 writeLines(unname(tools::md5sum(path)),paste0(path,'.md5'))
}
