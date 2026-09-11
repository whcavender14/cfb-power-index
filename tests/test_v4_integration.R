suppressPackageStartupMessages(source('cfb_v4_operations.R'))
f<-readRDS('outputs/round3/design_frozen.rds');o<-readRDS('outputs/round3/locked_outer.rds')
checks<-list()
for(n in c('baseline','A','B','C','D')) {
 sn<-o$cp$snap[[1]]
 r<-v4_build(2023,sn$cutoff,candidate=n)
 p<-o$predictions %>% filter(candidate==n,season==2023,cutoff==sn$cutoff)
 checks[[paste('full production reconstruction',n)]]<-max(abs(v4_predict(r,p$home_id,p$away_id,p$neutral)-p$pred_margin))<1e-9
}
sn<-o$cp$snap[[3]];g<-v4_schedule(2023)
r<-v4_build(2023,sn$cutoff,candidate='B',schedule=g)
changed<-g;ix<-changed$available_at>=sn$cutoff
changed$home_points[ix]<-999;changed$away_points[ix]<-0;changed$final[ix]<-TRUE
rr<-v4_build(2023,sn$cutoff,candidate='B',schedule=changed)
checks[['future-score counterfactual leaves production unchanged']]<-identical(r$power_rating,rr$power_rating)
checks[['production target IDs excluded']]<-length(intersect(attr(r,'training_ids'),g$game_id[g$kickoff>=sn$cutoff]))==0
fake<-sn$tg;fake$spread<-999;fake$market_rating<-999
checks[['extra market columns do not affect score design']]<-identical(v4_score_fit(fake,sn$ids,lambda=1),v4_score_fit(sn$tg,sn$ids,lambda=1))
x<-data.frame(x=1:20,y=(1:20)+1e-12*sin(1:20))
checks[['near collinearity removed']]<-'y'%in%names(prepare_design(x,c('x','y'))$dropped)
gf<-v4_schedule(2022);fi<-fbs_ids(gf);tf<-team_games(gf,fi,.25)
z<-v4_score_fit(tf,fi,lambda=8)
ct<-table(tf$team_id[tf$team_id%in%fi & tf$opp_id%in%fi]);expected<-as.integer(ct[as.character(fi)]);expected[is.na(expected)]<-0L
checks[['pooled FCS does not count as FBS evidence']]<-identical(z$games_played,expected)
checks[['frozen source integrity']]<-identical(f$source_md5,unname(tools::md5sum('cfb_power_ratings_v4.R')))
manifest<-read.csv('outputs/round3/pre_outer_manifest.csv')
checks[['pre outer code manifest unchanged']]<-all(unname(tools::md5sum(manifest$path))==manifest$md5)
q<-data.frame(test=names(checks),pass=unlist(checks));write.csv(q,'outputs/round3/integration_tests.csv',row.names=FALSE)
stopifnot(all(q$pass));cat(nrow(q),'integration tests passed\n')
