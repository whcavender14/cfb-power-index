suppressPackageStartupMessages(source('cfb_v4_operations.R'))
f<-readRDS('outputs/round3/design_frozen.rds');o<-readRDS('outputs/round3/locked_outer.rds');d<-o$predictions
base<-d %>% filter(candidate=='baseline')
# Shared game and team covariates are strictly pre-cutoff for predictive diagnostics.
d<-d %>% mutate(period_bucket=ifelse(week_seq<=4,as.character(week_seq),'5+'),
 gp_bucket=ifelse(pmin(gp_home,gp_away)<=1,as.character(pmin(gp_home,gp_away)),ifelse(pmin(gp_home,gp_away)<=3,'2-3','4+')),
 favorite_bucket=cut(abs(f$scale$scale*(pre_home-pre_away)),c(-Inf,7,14,28,Inf)),
 prior_bucket=cut(abs(prior_home-prior_away),c(-Inf,7,14,28,Inf)),
 connectivity_bucket=cut(pmin(component_size_home,component_size_away),c(0,1,4,32,Inf)),
 promoted=promoted_home+promoted_away>0)
for(gr in c('period_bucket','gp_bucket','week','connectivity_bucket','favorite_bucket','prior_bucket','promoted'))
 v4_write(summarize_predictions(d,c('candidate',gr)),paste0('outer_by_',gr))
v4_write(summarize_predictions(d,c('candidate','period_bucket','neutral')),'outer_early_by_site')
v4_write(summarize_predictions(d,c('candidate','week_seq','week')),'outer_calendar_provider_crosswalk')
team<-bind_rows(lapply(c('home','away'),function(side){
 q<-d;sign<-if(side=='home')1 else -1
 q$team_id<-q[[paste0(side,'_id')]];q$conference<-q[[paste0(side,'_conference')]]
 q$pred_margin<-sign*q$pred_margin;q$actual_margin<-sign*q$actual_margin;q$error<-sign*q$error
 for(n in c('n_cross','n_fbs_opponents','n_p4','n_fcs','one_score','u','component_size','promoted'))q[[n]]<-q[[paste0(n,'_',side)]]
 q$team_gp<-q[[paste0('gp_',side)]];q$opp_pre<-q[[paste0('pre_',if(side=='home')'away' else 'home')]]
 q$side<-side;q
})) %>% mutate(cross_bucket=cut(n_cross,c(-1,0,1,3,Inf)),
 degree_bucket=cut(n_fbs_opponents,c(-1,0,1,3,6,Inf)),
 fcs_bucket=ifelse(n_fcs==0,'0','1+'),power_opp_bucket=cut(n_p4,c(-1,0,1,3,Inf)),
 close_bucket=cut(one_score,c(-.01,.25,.5,1)),uncertainty_bucket=cut(u,c(-Inf,.4,.6,Inf)),
 opp_bucket=cut(opp_pre,c(-Inf,-7,0,7,Inf)))
for(gr in c('conference','cross_bucket','degree_bucket','fcs_bucket','power_opp_bucket','close_bucket','uncertainty_bucket','opp_bucket','team_gp'))
 v4_write(summarize_predictions(team,c('candidate',gr)),paste0('outer_team_by_',gr))
v4_write(team %>% group_by(candidate,conference,season) %>% summarise(n=n(),mae=mean(abs_error),bias=mean(error),.groups='drop'),'conference_season')
# Same paired uncertainty for early and sparse groups; season-level precision remains weak.
v4_write(bind_rows(lapply(c('1','2','3','4','5+'),function(p){
 dd<-d %>% filter(period_bucket==p,candidate==f$selected);bb<-d %>% filter(period_bucket==p,candidate=='baseline')
 cbind(period=p,v4_paired(dd,bb))})),'selected_early_paired')
# Weight table: EB entries are conditional diagonal weights, not a global blend.
ns<-c(0,1,2,3,6,12)
w<-bind_rows(lapply(c('baseline','A','B','C','D'),function(n){
 if(n=='baseline'){ww<-blend_weights(f$baseline$par,ns);return(tibble(candidate=n,games=ns,current=ww$a,prior=ww$b,zero=0,semantics='exact scalar blend before centering'))}
 if(n%in%c('A','B')){b<-f$blends[[n]];return(tibble(candidate=n,games=ns,current=if(n=='A')b$C*ns/(ns+b$t) else ns/(ns+b$k),prior=b$k/(ns+b$k),zero=0,semantics='exact scalar blend of game-scaled preseason mean before centering'))}
 lam<-if(n=='C')8 else 8/1.5;zp<-if(n=='C')0 else 2
 tibble(candidate=n,games=ns,current=ns/(ns+lam+zp),prior=lam/(ns+lam+zp),zero=zp/(ns+lam+zp),
  semantics=if(n=='C')'conditional on opponents/intercept; joint solve has matrix weights' else 'conditional example u=.5 cross=0; prior already divided by1.5; joint matrix weights')
}))
v4_write(w,'handoff_weights')
# Full production distributions and additive decompositions, with no post-fit scaling.
pr<-list()
for(n in c('baseline','A','B','C','D')) {
 message('Production diagnostics ',n)
 r<-v4_build(candidate=n,as_of=as.POSIXct('2026-09-09T00:00:00',format='%Y-%m-%dT%H:%M:%S',tz='UTC'))
 r$candidate<-n;pr[[n]]<-r
 if(n==f$selected)saveRDS(r,'outputs/round3/production_2026_v4.rds')
}
r<-bind_rows(pr);v4_write(r,'production_all_candidates');v4_write(r %>% filter(candidate==f$selected),'ratings_2026_v4')
v4_write(r %>% filter(games_played<=1),'zero_one_game_teams')
v4_write(r %>% group_by(candidate) %>% summarise(n=n(),mean=mean(power_rating),sd=sd(power_rating),
 min=min(power_rating),q05=quantile(power_rating,.05),median=median(power_rating),q95=quantile(power_rating,.95),max=max(power_rating),
 prior_sd=sd(prior_contribution),current_sd=sd(current_contribution),
 prior_finish_correlation=cor(power_rating,prev_off-prev_def,use='complete.obs'),.groups='drop'),'rating_distribution')
v4_write(r %>% group_by(candidate,conference) %>% summarise(n=n(),mean_power=mean(power_rating),
 mean_prior=mean(prior_contribution),mean_current=mean(current_contribution),.groups='drop'),'production_by_conference')
# Paired benchmark only; no market input was read until design and outer predictions existed.
mp<-read.csv('/Users/willcavender/Documents/Codex/2026-09-09/i-have-attached-an-r-script/outputs/local_validation/market_predictions.csv',stringsAsFactors=FALSE)
stopifnot(all(c('game_id','spread','provider')%in%names(mp)));mp$game_id<-as.character(mp$game_id)
lines<-mp %>% select(game_id,spread,provider);stopifnot(!anyDuplicated(lines$game_id))
market<-inner_join(d,lines,by='game_id') %>% mutate(market_error=-spread-actual_margin,delta=abs_error-abs(market_error))
v4_write(market %>% group_by(candidate) %>% summarise(n=n(),coverage=n()/2398,model_mae=mean(abs_error),market_mae=mean(abs(market_error)),delta_mae=mean(delta),.groups='drop'),'market_matched')
v4_write(market %>% group_by(candidate,season) %>% summarise(n=n(),model_mae=mean(abs_error),market_mae=mean(abs(market_error)),delta_mae=mean(delta),.groups='drop'),'market_paired_seasons')
v4_write(market %>% filter(candidate==f$selected) %>% count(provider),'market_providers')
v4_write(cluster_interval(market %>% filter(candidate==f$selected),'delta'),'market_paired_interval')
# Cached feature inventory: actual timestamps/provenance cannot be inferred from event dates.
inv<-list()
for(type in c('talent','returning','portal','coaches')) {
 file<-list.files('cfb_data_v2',pattern=paste0('^',type,'_'),full.names=TRUE)[1];x<-readRDS(file)
 ss<-if('season'%in%names(x))x$season else x$year
 for(s in sort(unique(ss))) {
  z<-x[ss==s,,drop=FALSE]
  inv[[paste(type,s)]]<-tibble(feature=type,season=s,rows=nrow(z),team_ids=if('team_id'%in%names(z))length(unique(z$team_id)) else NA_integer_,
   has_available_at='available_at'%in%names(z),has_source='source'%in%names(z),has_team_id='team_id'%in%names(z),
   event_dates=if('transfer_date'%in%names(z))sum(!is.na(z$transfer_date)) else if('hire_date'%in%names(z))sum(!is.na(z$hire_date)) else 0,
   file=file,status='DISABLED: publication vintage/provenance missing')
 }
}
v4_write(bind_rows(inv),'feature_inventory')
# Historical vs predictive HFA: same input sample, varying ridge, exact conditional normal equation.
hfas<-list()
for(s in 2015:2025) {
 g<-v4_schedule(s);ids<-fbs_ids(g);tg<-team_games(g,ids,0)
 for(l in c(.1,1,6,12)) {
  ef<-fit_efficiency(tg,ids,list(lambda=l,cap=Inf,fcs_weight=0));te<-g %>% filter(final,home_fbs,away_fbs,!neutral)
  p<-ef$ratings$eff_power[match(te$home_id,ef$ratings$team_id)]-ef$ratings$eff_power[match(te$away_id,ef$ratings$team_id)]
  res<-te$home_points-te$away_points-p
  hfas[[paste(s,l)]]<-tibble(season=s,lambda=l,n_home=nrow(te),n_neutral=sum(g$final&g$home_fbs&g$away_fbs&g$neutral),
    fitted_hfa=ef$hfa,conditional_hfa=(sum(res)+60)/(nrow(te)+20),
    raw_home_mean=mean(te$home_points-te$away_points),conditional_mean=mean(res),conditional_median=median(res))
 }
}
v4_write(bind_rows(hfas),'hfa_audit')
# Preseason coefficient / design audit.
pp<-v4_pre(2026,fbs_ids(v4_schedule(2026)),o$history)
v4_write(tibble(term=names(pp$pm$off),off=pp$pm$off,def=pp$pm$def),'preseason_coefficients')
v4_write(tibble(dropped=names(pp$pm$design$dropped),reason=unlist(pp$pm$design$dropped)),'preseason_rank_audit')
# Reproducible base-R figures (PDF and PNG) avoid dependencies on plotting packages.
plot_diagnostics<-function(){
 par(mfrow=c(2,2),mar=c(4,4,2,1))
 boxplot(power_rating~candidate,data=r,ylab='Neutral-field points',main='2026 rating distributions')
 for_plot<-subset(w,candidate%in%c('baseline','B'))
 plot(ns,for_plot$prior[for_plot$candidate=='baseline'],type='b',ylim=c(0,max(for_plot$prior)),xlab='Counted FBS games',ylab='Preseason coefficient',main='Exact scalar handoff')
 lines(ns,for_plot$prior[for_plot$candidate=='B'],type='b',col=4);legend('topright',c('Frozen v3','B (on calibrated prior)'),col=c(1,4),lty=1,bty='n')
 rr<-subset(r,candidate==f$selected);plot(rr$prior_contribution,rr$power_rating,xlab='Prior contribution',ylab='Power rating',main='Selected 2026 decomposition');abline(0,1,col='gray')
 z<-summarize_predictions(d %>% filter(candidate%in%c('baseline',f$selected)),c('candidate','week_seq'))
 plot(z$week_seq,z$bias,col=ifelse(z$candidate=='baseline',1,4),pch=16,xlab='Calendar period',ylab='Prediction minus actual',main='Locked-period bias');abline(h=0,col='gray')
}
png('outputs/round3/diagnostics.png',width=1500,height=1100,res=130);plot_diagnostics();dev.off()
pdf('outputs/round3/diagnostics.pdf',width=11,height=8);plot_diagnostics();dev.off()
capture.output(sessionInfo(),file='outputs/round3/sessionInfo.txt')
cat('Diagnostics complete\n')
