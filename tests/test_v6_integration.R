suppressPackageStartupMessages(source('cfb_v6_operations.R'))
f<-v6_frozen();z<-readRDS(file.path(v6_dir,'development_results.rds'));checks<-list();ad<-readRDS(file.path(v6_dir,'inputs.rds'))$advanced
for(n in names(z$cps)){
 cp<-z$cps[[n]];sn<-Filter(function(s)s$season==2022,cp$snap)[[3]];p<-z$parameters[[paste(n,2022)]]
 if(n=='full_preseason_current_efficiency_EB')sn<-Filter(function(s)s$season==2022,z$cps$v5_EB_features$snap)[[3]]
 if(n=='current_efficiency_EB')sn<-v6_current_snapshot(sn,ad,z$current[['2022']])
 if(identical(sn$new_active,FALSE))p<-z$incpars[['2022']]
 r<-v5_ratings(sn,v5_candidates()$EB_features,p);d<-z$predictions %>% filter(candidate==n,season==2022,cutoff==sn$cutoff)
 checks[[paste('snapshot prediction reconstruction',n)]]<-max(abs(v4_predict(r,d$home_id,d$away_id,d$neutral)-d$pred_margin))<1e-9
}
# Independent direct solve of the actual joint training objective.
ids<-1:3;pr<-data.frame(team_id=ids,pre_off=c(6,-3,-3),pre_def=c(-2,1,1))
g<-data.frame(game_id='g',season=2022,kickoff=as.POSIXct('2022-09-01',tz='UTC'),available_at=as.POSIXct('2022-09-02',tz='UTC'),period=as.POSIXct('2022-08-29',tz='UTC'),home_id=1,away_id=2,home_fbs=TRUE,away_fbs=TRUE,home_points=28,away_points=20,neutral=FALSE,final=TRUE)
tg<-team_games(g,ids,0);r<-v4_score_fit(tg,ids,pr,lambda=4,hfa=3)
X<-matrix(0,2,7);X[,1]<-1;X[cbind(1:2,1+tg$team_id)]<-1;X[cbind(1:2,4+tg$opp_id)]<-1;y<-tg$pf-3*tg$hx
b<-solve(crossprod(X)+diag(c(0,rep(4,6))),crossprod(X,y)+c(0,4*pr$pre_off,4*pr$pre_def))
reported<-mean(y-r$eff_off[tg$team_id]-r$eff_def[tg$opp_id])+r$eff_off[tg$team_id]+r$eff_def[tg$opp_id]
loss1<-sum((y-X%*%b)^2)+4*sum((b[2:4]-pr$pre_off)^2+(b[5:7]-pr$pre_def)^2)
loss2<-sum((y-reported)^2)+4*sum((r$eff_off-pr$pre_off)^2+(r$eff_def-pr$pre_def)^2)
checks[['EB objective equals independently reconstructed score loss and penalty']]<-abs(loss1-loss2)<1e-10
checks[['zero game EB algebra']]<-max(abs(v4_score_fit(tg[FALSE,],ids,pr,4,3)$eff_power-(pr$pre_off-pr$pre_def)))<1e-10
checks[['one game FBS clock']]<-identical(r$games_played,c(1L,1L,0L))
checks[['frozen legacy artifacts unchanged']]<-{m<-read.csv(file.path(v6_dir,'inherited_integrity.csv'));all(unname(tools::md5sum(m$path))==m$md5)}
if(file.exists(file.path(v6_dir,'conditional_results.rds'))){
 o<-readRDS(file.path(v6_dir,'conditional_results.rds'));sn<-o$cps$v5_EB_features$snap[[3]];a<-v6_build(2023,sn$cutoff);d<-o$predictions %>% filter(candidate==f$selected,season==2023,cutoff==sn$cutoff)
 checks[['full v6 production to frozen conditional parity']]<-max(abs(v4_predict(a,d$home_id,d$away_id,d$neutral)-d$pred_margin))<1e-9
 g<-v4_schedule(2023);ix<-g$available_at>=sn$cutoff;g$home_points[ix]<-999;g$away_points[ix]<-0;g$final[ix]<-TRUE;b<-v6_build(2023,sn$cutoff,schedule=g)
 checks[['future outcomes cannot change production']]<-identical(a$power_rating,b$power_rating)
 checks[['production target IDs excluded']]<-!any(attr(b,'training_ids')%in%g$game_id[g$kickoff>=sn$cutoff])
}
out<-data.frame(test=names(checks),pass=unlist(checks));v6_write(out,'integration_tests');print(out);stopifnot(all(out$pass))
