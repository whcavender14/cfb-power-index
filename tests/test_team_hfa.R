source('team_hfa_experiment.R')
checks<-list();check<-function(name,ok){stopifnot(isTRUE(ok));checks[[name]]<<-data.frame(test=name,passed=TRUE)}
t0<-as.POSIXct('2019-09-01',tz='UTC')
h<-data.frame(game_id=1:13,home_id=c(rep(1,6),rep(2,6),3),away_id=11:23,season=2019,kickoff=t0,cutoff=t0-86400,available_at=t0+86400,neutral=FALSE,actual_margin=c(rep(10,6),rep(-10,6),10),pred_margin=0)
f<-hfa_fit(h,t0+2*86400,20)
check('Neutral HFA exactly zero',identical(hfa_lookup(f,c(1,2,99),rep(TRUE,3),3),rep(0,3)))
check('Unseen team falls back to global',hfa_lookup(f,99,FALSE,3)==3)
check('Equal-team zero-centered deviations',abs(sum(f$table$deviation))<1e-12)
check('Small sample receives greater shrinkage',f$table$shrinkage[f$table$team_id==3]<f$table$shrinkage[f$table$team_id==1])
fstrong<-hfa_fit(h,t0+2*86400,200)
check('Stronger penalty reduces deviation norm',sum(fstrong$table$deviation^2)<sum(f$table$deviation^2))
bad<-h;bad$actual_margin<-bad$actual_margin*10
check('Unusual residual samples shrink more',all(hfa_fit(bad,t0+2*86400,20)$table$shrinkage<f$table$shrinkage))
late<-h[1,];late$game_id<-999L;late$available_at<-t0+3*86400;late$actual_margin<-1e6
f2<-hfa_fit(rbind(h,late),t0+2*86400,20)
check('Later scores cannot change cutoff fit',identical(f$table,f2$table))
late$available_at<-t0+2*86400
check('Exact-cutoff results are excluded',identical(f$table,hfa_fit(rbind(h,late),t0+2*86400,20)$table))
r<-data.frame(team_id=c(1,2),power_rating=c(8,-2));attr(r,'hfa')<-3;original<-r
fg<-hfa_fit(h,t0+2*86400,Inf)
check('Global prediction exactly reproduces incumbent',identical(hfa_predict(r,1,2,FALSE,fg),v4_predict(r,1,2,FALSE)))
check('HFA applied once',abs(hfa_predict(r,1,2,FALSE,f)-(10+3+f$table$deviation[1]))<1e-12)
check('Neutral rating and matchup invariant',identical(r,original)&&hfa_predict(r,1,2,TRUE,f)==hfa_predict(r,1,2,TRUE,fg))
check('SOS venue applied once with correct sign',abs(hfa_sos(-2,1,FALSE,3,TRUE,f)-(-2-hfa_lookup(f,1,FALSE,3)))<1e-12&&hfa_sos(8,1,TRUE,3,FALSE,f)==8)
empty<-h[FALSE,]
check('No history safe fallback',hfa_lookup(hfa_fit(empty,t0,100),1,FALSE,3)==3)
b<-hfa_read('outputs/round5/development_predictions.csv')
changed<-b;changed$actual_margin[changed$season>=2021]<-1e6
check('Ridge tuning ignores target and later seasons',identical(hfa_tune(b,2021),hfa_tune(changed,2021)))
check('EB hyperparameters ignore target and later seasons',identical(hfa_eb(b,2021),hfa_eb(changed,2021)))
x<-hfa_score(b[b$season==2019,],b,100)$predictions;y<-hfa_score(b[b$season==2019,],changed,100)$predictions
check('Historical predictions unaffected by future seasons',identical(x$pred_margin,y$pred_margin))
check('Calibration removes applicable HFA once',max(abs((x$pred_margin-x$hfa*as.numeric(!x$neutral))-x$neutral_margin))<1e-12)
check('Historical neutral predictions unchanged',identical(x$pred_margin[x$neutral],b$pred_margin[match(x$game_id[x$neutral],b$game_id)]))
if(file.exists('outputs/team_hfa/development_fold_audits.rds')){
 a<-readRDS('outputs/team_hfa/development_fold_audits.rds')
 check('Every development fit uses strictly available evidence',all(vapply(unlist(a,recursive=FALSE),function(z)is.na(z$max_available)||z$max_available<z$cutoff,logical(1))))
}
write.csv(bind_rows(checks),'outputs/team_hfa/tests.csv',row.names=FALSE)
print(bind_rows(checks))
