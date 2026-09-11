suppressPackageStartupMessages(source('cfb_v5_operations.R'))
f<-v5_frozen();specs<-f$specs;bundle<-readRDS('outputs/round4/features.rds')
# Joint block resampling provides consistent diagnostic uncertainty for all cells.
block_weights<-function(d,reps=2000){
 keys<-unique(paste(d$season,d$cutoff));first<-match(keys,paste(d$season,d$cutoff));bs<-d$season[first];seasons<-unique(bs)
 set.seed(9041);W<-matrix(0,reps,length(keys))
 for(i in seq_len(reps)){ix<-unlist(lapply(sample(seasons,length(seasons),TRUE),function(s){jj<-which(bs==s);sample(jj,length(jj),TRUE)}));W[i,]<-tabulate(ix,nbins=length(keys))}
 list(W=W,keys=keys)
}
diag_table<-function(d,group,bw){
 d$cell<-paste(d$candidate,as.character(d[[group]]),sep='::');cells<-unique(d$cell);j<-match(d$cell,cells);i<-match(paste(d$season,d$cutoff),bw$keys)
 x<-d$pred_margin-d$hfa*as.numeric(!d$neutral);y<-d$actual_margin-d$hfa*as.numeric(!d$neutral)
 vals<-list(n=rep(1,nrow(d)),ae=d$abs_error,se=d$error^2,error=d$error,x=x,y=y,xx=x*x,xy=x*y)
 totals<-lapply(vals,function(v)as.matrix(Matrix::sparseMatrix(i=i,j=j,x=v,dims=c(length(bw$keys),length(cells)))))
 point<-lapply(totals,colSums);boot<-lapply(totals,function(t)bw$W%*%t)
 slope<-function(t)(t$xy-t$x*t$y/t$n)/(t$xx-t$x*t$x/t$n)
 si<-slope(point);sb<-slope(boot);ib<-boot$y/boot$n-sb*boot$x/boot$n
 rows<-d[match(cells,d$cell),c('candidate',group)]
 ci<-function(m,p)apply(m,2,function(v){v<-v[is.finite(v)];if(length(v))unname(quantile(v,p)) else NA_real_})
 cbind(rows,tibble(n=point$n,mae=point$ae/point$n,rmse=sqrt(point$se/point$n),bias=point$error/point$n,
 slope=si,intercept=point$y/point$n-si*point$x/point$n,
 mae_low=ci(boot$ae/boot$n,.025),mae_high=ci(boot$ae/boot$n,.975),slope_low=ci(sb,.025),slope_high=ci(sb,.975),intercept_low=ci(ib,.025),intercept_high=ci(ib,.975),bias_low=ci(boot$error/boot$n,.025),bias_high=ci(boot$error/boot$n,.975)))
}
allpars<-list();allcoefs<-list();alldrops<-list();allroutes<-list();allcv<-list();allconfs<-list()
for(stage in c('development','conditional')){
 z<-readRDS(paste0('outputs/round4/',stage,'_results.rds'));d<-z$predictions
 d$period_bucket<-ifelse(d$week_seq<=4,as.character(d$week_seq),'5+')
 d$gp_bucket<-cut(pmin(d$gp_home,d$gp_away),c(-1,0,1,3,6,Inf))
 # Magnitudes use each fold's already fitted prior scale, never outcome-derived cutpoints.
 d$pre_scale<-vapply(seq_len(nrow(d)),function(i)if(stage=='conditional')f$parameters[[d$candidate[i]]]$scale$scale else z$parameters[[paste(d$candidate[i],d$season[i])]]$scale$scale,numeric(1))
 d$favorite_bucket<-cut(abs(d$pre_scale*(d$pre_home-d$pre_away)),c(-Inf,7,14,28,Inf))
 d$prior_bucket<-cut(abs(d$prior_home-d$prior_away),c(-Inf,7,14,28,Inf));d$promotion<-d$promoted_home+d$promoted_away>0
 d$connectivity_bucket<-cut(pmin(d$component_size_home,d$component_size_away),c(0,1,15,63,Inf))
 d$site<-ifelse(d$neutral,'neutral','nonneutral');d$global<-'all';d$period_site<-paste(d$period_bucket,d$site)
 bw<-block_weights(d)
 for(group in c('global','site','period_bucket','period_site','week','gp_bucket','favorite_bucket','prior_bucket','promotion','connectivity_bucket'))
  v5_write(diag_table(d,group,bw),paste0(stage,'_calibration_',group))
 d$reliability_bin<-cut(d$pred_margin-d$hfa*as.numeric(!d$neutral),c(-Inf,-28,-14,-7,0,7,14,28,Inf))
 v5_write(d %>% group_by(candidate,reliability_bin) %>% summarise(n=n(),predicted_neutral=mean(pred_margin-hfa*as.numeric(!neutral)),actual_neutral=mean(actual_margin-hfa*as.numeric(!neutral)),.groups='drop'),paste0(stage,'_reliability'))
 baseline<-d %>% filter(candidate=='B')
 v5_write(bind_rows(lapply(names(specs),function(n)cbind(candidate=n,v5_paired(d %>% filter(candidate==n),baseline)))),paste0(stage,'_paired'))
 v5_write(bind_rows(lapply(names(specs),function(n){q<-d %>% filter(candidate==n);q$delta<-q$abs_error-baseline$abs_error[match(q$game_id,baseline$game_id)];q %>% group_by(season) %>% summarise(delta_mae=mean(delta),.groups='drop') %>% mutate(candidate=n)})),paste0(stage,'_paired_seasons'))
 v5_write(z$ratings %>% group_by(candidate,season,cutoff) %>% summarise(rating_sd=sd(power_rating),prior_contribution_sd=sd(prior_contribution),current_contribution_sd=sd(current_contribution),.groups='drop'),paste0(stage,'_rating_distribution'))
 # Network exposure includes only already-played opponents.
 net<-bind_rows(lapply(z$cps$none$snap,function(sn){
  cur<-v4_score_fit(sn$tg,sn$ids,lambda=1,hfa=sn$hfa,variance=TRUE)
  op<-sn$tg %>% select(team_id,opp_id) %>% distinct() %>% filter(opp_id%in%sn$ids)
  op$prior<-sn$pre$pre_power[match(op$opp_id,sn$pre$team_id)];op$uncertainty<-cur$variance[match(op$opp_id,cur$team_id)]
  q<-op %>% group_by(team_id) %>% summarise(faced_prior=mean(prior),faced_uncertainty=mean(uncertainty),.groups='drop')
  sn$graph %>% left_join(q,by='team_id') %>% mutate(season=sn$season,cutoff=sn$cutoff)
 }))
 v5_write(net,paste0(stage,'_network_states'))
 team<-bind_rows(lapply(c('home','away'),function(side){
  q<-d;sgn<-if(side=='home')1 else -1;q$team_id<-q[[paste0(side,'_id')]];q$conference<-q[[paste0(side,'_conference')]]
  q$pred_margin<-sgn*q$pred_margin;q$actual_margin<-sgn*q$actual_margin;q$error<-sgn*q$error;q$hfa<-sgn*q$hfa
  for(n in c('n_cross','n_fbs_opponents','n_p4','n_fcs','one_score','u','component_size'))q[[n]]<-q[[paste0(n,'_',side)]]
  q$team_gp<-q[[paste0('gp_',side)]];q
 })) %>% left_join(net %>% select(season,cutoff,team_id,faced_prior,faced_uncertainty),by=c('season','cutoff','team_id'))
 team$cross<-cut(team$n_cross,c(-1,0,1,Inf));team$degree<-cut(team$n_fbs_opponents,c(-1,0,1,3,6,Inf));team$fcs<-cut(team$n_fcs,c(-1,0,1,Inf))
 team$component<-cut(team$component_size,c(0,1,15,63,Inf));team$one_score_bucket<-cut(team$one_score,c(-.01,.25,.5,1));team$prior_uncertainty<-cut(team$u,c(-Inf,.5,1,Inf))
 team$opponent_prior<-cut(abs(team$faced_prior),c(-Inf,7,14,Inf));team$state<-cut(team$team_gp,c(-1,0,1,3,6,Inf));team$power_conference_opponents<-cut(team$n_p4,c(-1,0,1,Inf))
 team$current_opponent_uncertainty<-cut(team$faced_uncertainty,c(-Inf,.5,1,Inf))
 for(group in c('conference','cross','degree','fcs','component','one_score_bucket','prior_uncertainty','opponent_prior','current_opponent_uncertainty','state','power_conference_opponents'))
  v5_write(diag_table(team,group,bw),paste0(stage,'_network_',group))
 for(fam in setdiff(names(z$cps),'none'))for(ss in names(z$cps[[fam]]$prior_fits)){
  p<-z$cps[[fam]]$prior_fits[[ss]]
  if(nrow(p$routes))allroutes[[length(allroutes)+1]]<-mutate(p$routes,stage=stage,family=fam)
  for(reg in names(p$fits)){
   m<-p$fits[[reg]];allcoefs[[length(allcoefs)+1]]<-tibble(stage=stage,family=fam,season=as.integer(ss),regime=reg,term=m$design$keep,beta_standardized=m$beta,train_mean=m$design$mu,train_sd=m$design$sd,lambda=m$lambda,n_train=m$n,max_train=m$max_train,gradient=m$gradient)
   if(length(m$design$dropped))alldrops[[length(alldrops)+1]]<-tibble(stage=stage,family=fam,season=as.integer(ss),regime=reg,term=names(m$design$dropped),reason=unlist(m$design$dropped))
   allcv[[length(allcv)+1]]<-mutate(m$cv,stage=stage,family=fam,season=as.integer(ss),regime=reg)
  }
 }
 sch<-setNames(lapply(2015:max(d$season),v4_schedule),2015:max(d$season))
 for(s in unique(d$season))allconfs[[paste(stage,s)]]<-mutate(v5_conference(s,z$history,sch),stage=stage,season=s)
 if(stage=='development')allpars<-z$parameters
}
for(n in names(f$parameters))allpars[[paste(n,'frozen')]]<-f$parameters[[n]]
profiles<-list();optimizer<-list()
for(n in names(allpars))for(k in names(allpars[[n]]$profiles)){
 q<-allpars[[n]]$profiles[[k]];profiles[[length(profiles)+1]]<-mutate(q$profile,fit=n)
 optimizer[[length(optimizer)+1]]<-tibble(fit=n,parameter=k,value=q$value,objective=q$objective,status=q$status,boundary=q$boundary,finite_difference=q$derivative)
}
v5_write(bind_rows(profiles),'optimizer_profiles');v5_write(bind_rows(optimizer),'optimizer_diagnostics');v5_write(bind_rows(allcoefs),'prior_coefficients');v5_write(bind_rows(alldrops),'dropped_predictors');v5_write(bind_rows(allroutes),'feature_coverage_routes');v5_write(bind_rows(allcv),'nested_penalty_validation');v5_write(bind_rows(allconfs),'conference_effect_distribution')
ns<-c(0,1,2,3,6,12)
weights<-bind_rows(lapply(names(specs),function(n){p<-f$parameters[[n]];s<-specs[[n]]
 if(s$kind=='B')return(tibble(candidate=n,games=ns,prior=p$blend$k/(ns+p$blend$k),current=ns/(ns+p$blend$k),gamma=p$gamma,semantics='exact convex weights before gamma and centering'))
 zp<-if(isTRUE(s$uncertainty))1 else 0
 tibble(candidate=n,games=ns,prior=4/(ns+4+zp),current=ns/(ns+4+zp),gamma=1,semantics=if(zp>0)'conditional example u=.5 component1 cross0; zero share=1/(n+5); joint matrix weights' else 'conditional on known opponents/intercept only; exact joint update uses matrix weights')
}));v5_write(weights,'component_schedules')
# Current production diagnostics share the same code and frozen feature IDs.
pr<-list();cf<-list();asof<-as.POSIXct('2026-09-09',tz='UTC')
for(n in names(specs)){
 message('Production ',n);r<-v5_build(2026,asof,candidate=n);pr[[n]]<-mutate(r,candidate=n)
 rr<-v5_build(2026,asof,candidate=n,counterfactual=TRUE);cf[[n]]<-tibble(candidate=n,team_id=rr$team_id,power_prior_inputs_at_mean=rr$power_rating,pre_power_prior_inputs_at_mean=rr$pre_power)
 if(n==f$selected){saveRDS(r,'outputs/round4/production_2026_v5.rds');v5_write(r,'ratings_2026_v5')}
}
r<-bind_rows(pr);r<-left_join(r,bind_rows(cf),by=c('candidate','team_id'));r$prior_input_power_departure<-r$power_rating-r$power_prior_inputs_at_mean
v5_write(r,'production_all_candidates');v5_write(r %>% filter(team%in%c('Indiana','Ohio State','James Madison','South Florida','Old Dominion')),'requested_team_components')
v5_write(r %>% group_by(candidate) %>% summarise(n=n(),rating_sd=sd(power_rating),preseason_sd=sd(pre_power),pearson=cor(pre_power,prev_off-prev_def,use='complete.obs'),spearman=cor(pre_power,prev_off-prev_def,use='complete.obs',method='spearman'),power_pearson=cor(power_rating,prev_off-prev_def,use='complete.obs'),power_spearman=cor(power_rating,prev_off-prev_def,use='complete.obs',method='spearman'),.groups='drop'),'production_distribution')
# Market enters only this post-freeze reporting script after all predictions are saved.
mpath<-'/Users/willcavender/Documents/Codex/2026-09-09/i-have-attached-an-r-script/outputs/local_validation/market_predictions.csv'
mp<-read.csv(mpath);lines<-mp %>% transmute(game_id=as.character(game_id),spread,provider);stopifnot(!anyDuplicated(lines$game_id))
o<-readRDS('outputs/round4/conditional_results.rds')$predictions
market<-inner_join(o,lines,by='game_id') %>% mutate(market_error=-spread-actual_margin,delta=abs_error-abs(market_error))
v5_write(v5_hashes(mpath),'market_source_manifest')
v5_write(market %>% group_by(candidate) %>% summarise(n=n(),coverage=n()/sum(o$candidate==first(candidate)),model_mae=mean(abs_error),market_mae=mean(abs(market_error)),delta_mae=mean(delta),.groups='drop'),'market_benchmark')
v5_write(market %>% group_by(candidate,season) %>% summarise(n=n(),model_mae=mean(abs_error),market_mae=mean(abs(market_error)),delta_mae=mean(delta),.groups='drop'),'market_paired_seasons')
v5_write(market %>% filter(candidate==f$selected) %>% count(provider),'market_providers');v5_write(v5_boot(market %>% filter(candidate==f$selected)),'market_paired_uncertainty')
# Genuine future-only archive, distinct name on each execution.
rsel<-readRDS('outputs/round4/production_2026_v5.rds');v5_archive_upcoming(rsel,file.path('outputs/round4/prospective',paste0('predictions_',format(Sys.time(),'%Y%m%dT%H%M%S'),'.csv')))
# Standalone scientific figure.
png('outputs/round4/diagnostics.png',width=1600,height=1100,res=140)
par(mfrow=c(2,2),mar=c(7,4,3,1))
l<-read.csv('outputs/round4/candidate_ledger.csv');plot(seq_len(nrow(l)),l$estimate,ylim=range(l$block_low,l$block_high),xaxt='n',xlab='',ylab='Development MAE difference vs B',pch=19);axis(1,seq_len(nrow(l)),l$candidate,las=2);arrows(seq_len(nrow(l)),l$block_low,seq_len(nrow(l)),l$block_high,angle=90,code=3,length=.03);abline(h=0,col='gray')
q<-subset(r,candidate%in%c('B',f$selected));boxplot(power_rating~candidate,q,ylab='Neutral-field rating points',main='2026 rating distribution')
q<-read.csv('outputs/round4/development_calibration_period_bucket.csv');q<-q[q$candidate%in%c('B',f$selected),];plot(as.numeric(factor(q$period_bucket)),q$slope,col=ifelse(q$candidate=='B',1,4),pch=19,xlab='Calendar period (5 = 5+)',ylab='Development calibration slope');abline(h=1,col='gray');legend('topright',c('B',f$selected),col=c(1,4),pch=19,bty='n')
q<-r[r$candidate==f$selected,];plot(q$prev_off-q$prev_def,q$pre_power,xlab='Prior-season score power',ylab='Feature preseason power',main='2026 preseason departures');abline(0,1,col='gray');dev.off()
cat('Reporting complete\n')
