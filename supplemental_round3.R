suppressPackageStartupMessages(source('cfb_v4_operations.R'))
set.seed(9041)
intervals<-list()
for(stage in c('development','locked_outer')) {
 d<-read.csv(paste0('outputs/round3/',stage,'_predictions.csv'),stringsAsFactors=FALSE)
 base<-d %>% filter(candidate=='baseline') %>% select(game_id,base_error=abs_error)
 for(n in setdiff(unique(d$candidate),'baseline')) {
  q<-d %>% filter(candidate==n) %>% left_join(base,by='game_id') %>% mutate(delta=abs_error-base_error)
  iid<-replicate(2000,mean(sample(q$delta,nrow(q),replace=TRUE)))
  # Hierarchical season then within-season calendar-period block bootstrap.
  blocks<-q %>% group_by(season,week_seq) %>% summarise(total=sum(delta),n=n(),.groups='drop')
  ss<-unique(blocks$season)
  v<-replicate(2000,{
   z<-bind_rows(lapply(sample(ss,length(ss),replace=TRUE),function(s){b<-blocks %>% filter(season==s);b[sample(nrow(b),nrow(b),replace=TRUE),]}))
   sum(z$total)/sum(z$n)
  })
  intervals[[paste(stage,n)]]<-tibble(stage=stage,candidate=n,estimate=mean(q$delta),
    paired_game_low=quantile(iid,.025),paired_game_high=quantile(iid,.975),
    season_period_low=quantile(v,.025),season_period_high=quantile(v,.975))
 }
}
v4_write(bind_rows(intervals),'paired_sensitivity_intervals')
# Development breakdowns on matched game covariates.
d<-read.csv('outputs/round3/development_predictions.csv',stringsAsFactors=FALSE)
cp<-readRDS('outputs/round3/development_components.rds')$cp$frame
for(n in intersect(names(cp),names(d))) {
 ix<-which(is.na(d[[n]]));if(length(ix))d[[n]][ix]<-cp[[n]][match(d$game_id[ix],cp$game_id)]
}
d<-d %>% mutate(period_bucket=ifelse(week_seq<=4,as.character(week_seq),'5+'),
 gp_bucket=ifelse(pmin(gp_home,gp_away)<=1,as.character(pmin(gp_home,gp_away)),ifelse(pmin(gp_home,gp_away)<=3,'2-3','4+')),
 connectivity_bucket=cut(pmin(component_size_home,component_size_away),c(0,1,4,32,Inf)))
for(gr in c('period_bucket','gp_bucket','connectivity_bucket','home_conference'))
 v4_write(summarize_predictions(d,c('candidate',gr)),paste0('development_by_',gr))
# Source audit and deterministic replay manifests include the exact raw schedules.
paths<-c(list.files('cfb_data_v3',pattern='^raw_schedule_.*rds$',full.names=TRUE),
 'cfb_power_ratings_v3.R','cfb_power_ratings_v4.R','cfb_v4_operations.R','run_round3.R',
 'report_round3.R','supplemental_round3.R','outputs/round3/design_frozen.rds')
v4_write(data.frame(path=paths,md5=unname(tools::md5sum(paths))),'input_manifest')
r<-readRDS('outputs/round3/production_2026_v4.rds')
p<-paste0('outputs/round3/prospective/',format(Sys.time(),'%Y%m%dT%H%M%S',tz='UTC'),'.csv')
v4_archive_upcoming(r,path=p)
Sys.chmod(c(p,paste0(p,'.md5')),mode='0444')
cat('Prospective archive:',p,'\n')
