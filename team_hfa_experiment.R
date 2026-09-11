# Isolated diagnostic. Sourcing this file does not alter any production function.
suppressPackageStartupMessages(source('cfb_power_ratings_v6.R'))
hfa_read <- function(path) {
 d<-read.csv(path,stringsAsFactors=FALSE)
 d<-d[d$candidate=='v5_EB_features',]
 stopifnot(nrow(d)>0,!anyDuplicated(d$game_id))
 d$kickoff<-as.POSIXct(d$kickoff,tz='UTC');d$cutoff<-as.POSIXct(d$cutoff,tz='UTC')
 d$available_at<-d$kickoff+24*3600
 stopifnot(all(d$cutoff<=d$kickoff),all(is.finite(d$pred_margin)))
 d
}
hfa_stats <- function(history,cutoff) {
 tr<-history[history$available_at<cutoff & !history$neutral & history$season!=2020,]
 stopifnot(!anyDuplicated(tr$game_id),all(tr$cutoff<=tr$kickoff))
 rows<-lapply(split(tr,tr$home_id),function(z){
  e<-z$actual_margin-z$pred_margin;n<-nrow(z)
  q<-min(n,4*length(unique(z$season)),2*length(unique(z$away_id)))*min(1,256/max(mean(e^2),1e-12))
  data.frame(team_id=z$home_id[1],n=n,seasons=length(unique(z$season)),opponents=length(unique(z$away_id)),mean_residual=mean(e),effective_n=q)
 })
 tab<-if(length(rows))do.call(rbind,rows) else data.frame(team_id=integer(),n=integer(),seasons=integer(),opponents=integer(),mean_residual=numeric(),effective_n=numeric())
 attr(tab,'training_ids')<-tr$game_id;attr(tab,'max_available')<-if(nrow(tr))max(tr$available_at) else as.POSIXct(NA)
 tab
}
hfa_fit <- function(history,cutoff,lambda=Inf) {
 stopifnot(length(lambda)==1,!is.na(lambda),lambda>0)
 t<-hfa_stats(history,cutoff);q<-t$effective_n
 t$shrinkage<-if(is.infinite(lambda))rep(0,nrow(t)) else q/(q+lambda)
 t$deviation<-rep(0,nrow(t));t$centering_correction<-rep(0,nrow(t))
 if(nrow(t)&&is.finite(lambda)){
  c0<-sum(q*t$mean_residual/(q+lambda))/sum(1/(q+lambda))
  t$centering_correction<-c0/(q+lambda)
  t$deviation<-t$shrinkage*t$mean_residual-t$centering_correction
 }
 stopifnot(abs(sum(t$deviation))<1e-8)
 list(table=t,lambda=lambda,cutoff=cutoff,training_ids=attr(t,'training_ids'),max_available=attr(t,'max_available'))
}
hfa_lookup <- function(fit,home_id,neutral,global_hfa) {
 d<-fit$table$deviation[match(home_id,fit$table$team_id)];d[is.na(d)]<-0
 ifelse(neutral,0,global_hfa+d)
}
hfa_predict <- function(ratings,home_id,away_id,neutral,fit) {
 ratings$power_rating[match(home_id,ratings$team_id)]-ratings$power_rating[match(away_id,ratings$team_id)]+hfa_lookup(fit,home_id,neutral,attr(ratings,'hfa'))
}
hfa_sos <- function(opponent_rating,home_id,neutral,global_hfa,is_home,fit) {
 opponent_rating-ifelse(is_home,1,-1)*hfa_lookup(fit,home_id,neutral,global_hfa)
}
hfa_score <- function(target,history,lambda) {
 out<-list();audit<-list()
 for(cut in unique(as.numeric(target$cutoff))){
  cutoff<-as.POSIXct(cut,origin='1970-01-01',tz='UTC');z<-target[target$cutoff==cutoff,]
  f<-hfa_fit(history,cutoff,lambda)
  stopifnot(!any(z$game_id%in%f$training_ids))
  z$global_hfa<-z$hfa;z$hfa_applied<-hfa_lookup(f,z$home_id,z$neutral,z$global_hfa)
  z$neutral_margin<-z$pred_margin-z$global_hfa*as.numeric(!z$neutral)
  # Preserve exact floating-point incumbent output in fallback/global mode.
  z$pred_margin<-z$pred_margin+(z$hfa_applied-z$global_hfa*as.numeric(!z$neutral))
  z$hfa<-z$hfa_applied;z$error<-z$pred_margin-z$actual_margin;z$abs_error<-abs(z$error)
  out[[length(out)+1]]<-z
  audit[[length(audit)+1]]<-list(cutoff=cutoff,lambda=lambda,training_ids=f$training_ids,max_available=f$max_available,table=f$table)
 }
 list(predictions=bind_rows(out),audit=audit)
}
hfa_grid <- c(Inf,200,100,50,20)
hfa_tune <- function(history,before) {
 tr<-history[history$season<before & history$season<=2022,]
 if(!nrow(tr))return(list(lambda=100,cv=data.frame(),reason='cold_start_fixed_100'))
 cv<-bind_rows(lapply(hfa_grid,function(l){z<-hfa_score(tr,tr,l)$predictions;data.frame(lambda=l,n=nrow(z),mae=mean(z$abs_error))}))
 list(lambda=cv$lambda[which(cv$mae<=min(cv$mae)+1e-10)[1]],cv=cv,reason='earlier_forward_MAE')
}
hfa_eb <- function(history,before) {
 tr<-history[history$season<before & history$season<=2022,]
 s<-hfa_stats(tr,as.POSIXct(paste0(before,'-01-01'),tz='UTC'))
 tau<-if(nrow(s)<20)0 else max(0,var(s$mean_residual)-mean(256/s$effective_n))
 list(lambda=if(tau>0)256/tau else Inf,tau2=tau,n_teams=nrow(s),max_season=if(nrow(tr))max(tr$season) else NA)
}
hfa_metrics <- function(d) {
 bind_rows(lapply(unique(d$candidate),function(n){z<-d[d$candidate==n,]
  bind_rows(cbind(candidate=n,split='overall',value='all',v5_calibration(z)),
   bind_rows(lapply(sort(unique(z$season)),function(s)cbind(candidate=n,split='season',value=as.character(s),v5_calibration(z[z$season==s,])))),
   bind_rows(lapply(c(FALSE,TRUE),function(b)cbind(candidate=n,split='site',value=if(b)'neutral' else 'home',v5_calibration(z[z$neutral==b,])))))
 }))
}
