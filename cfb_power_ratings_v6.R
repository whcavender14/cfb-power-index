# Round 5. Legacy functions are read-only dependencies; sourcing never fits.
source('cfb_v5_operations.R')
v6_dir <- 'outputs/round5'
v6_write <- function(x,n) write.csv(x,file.path(v6_dir,paste0(n,'.csv')),row.names=FALSE,na='')
v6_config <- function() list(version='6.0.0',seed=9041L,reps=2000L,development=c(2019L,2021L,2022L),alpha=c(0,.5,1),penalty=c(.01,.1,1,10,100),L=2:4,half_life=1:3,minimum_rows=80L,current_weight=.25,max_training=2022L)
v6_candidates <- function() c('v5_EB_features','position_RP_EB','QB_position_RP_EB','efficiency_prior_EB','special_teams_prior_EB','multi_year_prior_EB','coordinator_EB','full_preseason_EB','current_efficiency_EB','full_preseason_current_efficiency_EB')
v6_guard <- function(x) {
 n<-setdiff(names(x),c('off_line_yds','off_line_yds_total','def_line_yds','def_line_yds_total','adj_off_line_yds','adj_def_line_yds'));assert(!any(grepl('market|spread|odds|betting|closing|vegas|consensus|implied|price|(^|_)line($|_)',n,ignore.case=TRUE)),'Market ingress prohibited')
 if(is.list(x)&&!is.data.frame(x))for(z in x)if(is.list(z))v6_guard(z)
 invisible(TRUE)
}
v6_manifest <- function(paths) {
 assert(all(file.exists(paths)),'Missing manifest input')
 data.frame(path=paths,md5=unname(tools::md5sum(paths)),sha256=vapply(paths,function(p)digest::digest(file=p,algo='sha256'),character(1)))
}
v6_verify <- function(m) assert(all(file.exists(m$path))&&identical(unname(tools::md5sum(m$path)),m$md5),'Frozen artifact changed')
v6_score_terms <- c('prev_off','prev_def','older_off','older_def','older_n','promoted')
v6_eff_metrics <- c('success_rate','passing_plays_success_rate','rushing_plays_success_rate','line_yds','stuff_rate')
v6_terms <- function(block,side) {
 if(block=='efficiency')return(paste0('adj_',side,'_',v6_eff_metrics))
 if(block=='field')return(c(paste0('field_',side),'kick_return_ypr','punt_return_ypr'))
 if(block=='multi')return(c('older_off','older_def','older_n'))
 character()
}
v6_prepare <- function(tr,terms) {
 v6_guard(tr);allowed<-c(v6_score_terms,v5_terms,'success_rate',unlist(lapply(c('off','def'),function(s)c(v6_terms('efficiency',s),v6_terms('field',s)))))
 assert(all(terms%in%allowed),'Predictor not allowed')
 ext<-setdiff(terms,v6_score_terms);assert(all(vapply(tr[ext],function(z)all(is.finite(z)),logical(1))),'External feature imputation prohibited')
 d<-prepare_design(tr,terms);d$mu<-colMeans(d$X);d$sd<-apply(d$X,2,sd);d$mu[1]<-0;d$sd[1]<-1;d$sd[!is.finite(d$sd)|d$sd==0]<-1
 d$X<-sweep(sweep(d$X,2,d$mu,'-'),2,d$sd,'/');d$training_seasons<-sort(unique(tr$season));d
}
v6_fit <- function(tr,terms,target,alpha,lambda) {
 d<-v6_prepare(tr,terms);X<-d$X;y<-tr[[target]];assert(all(is.finite(y)),'Missing response')
 if(alpha==0){p<-c(0,rep(lambda,ncol(X)-1));b<-as.numeric(solve(crossprod(X)/nrow(X)+diag(p,ncol(X)),crossprod(X,y)/nrow(X)))}else{
 xx<-X[,-1,drop=FALSE];single<-ncol(xx)==1;if(single)xx<-cbind(xx,.dummy=0)
 z<-glmnet::glmnet(xx,y,alpha=alpha,lambda=2*lambda,standardize=FALSE,intercept=TRUE,thresh=1e-12,maxit=100000)
 assert(z$jerr==0,'Elastic net failed');b<-as.numeric(coef(z,s=2*lambda));if(single)b<-head(b,-1)
 }
 err<-as.numeric(X%*%b-y);loss<-mean(err^2);pen<-lambda*((1-alpha)*sum(b[-1]^2)+2*alpha*sum(abs(b[-1])))
 list(design=d,beta=b,alpha=alpha,lambda=lambda,n=nrow(tr),max_train=max(tr$season),training_mse=loss,objective=loss+pen,status='converged',terms=terms)
}
v6_apply <- function(f,m) as.numeric(v5_apply(f,m$design)%*%m$beta)
v6_older <- function(rows,history,L,h) {
 out<-rows;out$older_off<-NA_real_;out$older_def<-NA_real_;out$older_n<-0L
 for(i in seq_len(nrow(rows))){s<-rows$season[i];z<-history[history$team_id==rows$team_id[i]&history$season%in%(s-(2:L)),];z<-z[is.finite(z$eff_off)&is.finite(z$eff_def),]
 if(nrow(z)){w<-2^(-(s-z$season-2)/h);out$older_off[i]<-weighted.mean(z$eff_off,w);out$older_def[i]<-weighted.mean(z$eff_def,w);out$older_n[i]<-nrow(z)}};out
}
v6_select <- function(options,terms,target) {
 cfg<-v6_config();val<-list()
 for(k in seq_along(options)){tt<-options[[k]]
 for(y in sort(unique(tt$season))){a<-tt[tt$season<y,,drop=FALSE];b<-tt[tt$season==y,,drop=FALSE];if(nrow(a)<cfg$minimum_rows)next
 for(al in cfg$alpha)for(lam in cfg$penalty){m<-v6_fit(a,terms,target,al,lam);err<-v6_apply(b,m)-b[[target]]
 val[[length(val)+1]]<-data.frame(option=k,year=y,alpha=al,lambda=lam,sse=sum(err^2),n=length(err),train_max=max(a$season))}}}
 cv<-bind_rows(val);if(!nrow(cv))return(NULL)
 rank<-cv %>% group_by(option,alpha,lambda) %>% summarise(mse=sum(sse)/sum(n),.groups='drop') %>% arrange(mse,desc(lambda),alpha,option)
 q<-rank[1,];m<-v6_fit(options[[q$option]],terms,target,q$alpha,q$lambda);m$option<-q$option;m$cv<-cv;m
}
v6_prior <- function(s,ids,history,features,blocks=character(),extra=NULL,Lfixed=NULL) {
 inc<-v5_prior(s,ids,history,features,'full');if(!length(blocks))return(inc)
 assert(all(blocks%in%c('efficiency','field','multi')),'Unavailable feature family')
 hs<-history %>% filter(season<s,season<=2022)
 tr<-bind_rows(lapply(sort(unique(hs$season)),function(y)features_for(y,hs$team_id[hs$season==y],hs,NULL,v4_config()))) %>% left_join(features,by=c('season','team_id')) %>% inner_join(hs %>% select(season,team_id,eff_off,eff_def),by=c('season','team_id')) %>% filter(season>2015,season!=2020)
 tar<-features_for(s,ids,history,NULL,v4_config()) %>% left_join(features,by=c('season','team_id'))
 if(!is.null(extra)){tr<-left_join(tr,extra,by=c('season','team_id'));tar<-left_join(tar,extra,by=c('season','team_id'))}
 grid<-if('multi'%in%blocks)expand.grid(h=1:3,L=if(is.null(Lfixed))2:4 else Lfixed) else data.frame(h=1,L=2)
 grid<-grid[order(grid$L,grid$h),]
 opts<-lapply(seq_len(nrow(grid)),function(k)if('multi'%in%blocks)v6_older(tr,history,grid$L[k],grid$h[k]) else tr)
 targets<-lapply(seq_len(nrow(grid)),function(k)if('multi'%in%blocks)v6_older(tar,history,grid$L[k],grid$h[k]) else tar)
 out<-inc$r;fits<-list();routes<-list()
 for(side in c('off','def')){
 add<-unlist(lapply(blocks,v6_terms,side=side));extadd<-setdiff(add,v6_score_terms)
 if(!all(extadd%in%names(tar)))next
 valid<-if(length(extadd))apply(as.matrix(tar[,extadd,drop=FALSE]),1,function(z)all(is.finite(z))) else rep(TRUE,nrow(tar))
 ext<-v5_feature_terms('full',side);pat<-vapply(seq_len(nrow(tar)),function(i)paste(ext[vapply(ext,function(t)is.finite(tar[[t]][i]),logical(1))],collapse='|'),character(1))
 for(pp in unique(pat[valid])){
 ee<-if(nzchar(pp))strsplit(pp,'|',fixed=TRUE)[[1]] else character();terms<-unique(c('prev_off','prev_def','promoted',ee,add));external<-setdiff(terms,v6_score_terms)
 tt<-lapply(opts,function(t)t[apply(as.matrix(t[,external,drop=FALSE]),1,function(z)all(is.finite(z))),,drop=FALSE]);if(nrow(tt[[1]])<80)next
 m<-v6_select(tt,terms,paste0('eff_',side));if(is.null(m))next
 m$history_grid<-grid;m$blocks<-blocks;ix<-which(valid&pat==pp)
 out[[paste0('pre_',side)]][ix]<-v6_apply(targets[[m$option]][ix,],m);fits[[paste(side,pp,sep=':')]]<-m
 routes[[length(routes)+1]]<-data.frame(season=s,team_id=tar$team_id[ix],side=side,regime=pp,route='new_block',alpha=m$alpha,lambda=m$lambda,L=grid$L[m$option],half_life=grid$h[m$option])
 }
 }
 if(length(fits)){out$pre_off<-out$pre_off-mean(out$pre_off);out$pre_def<-out$pre_def-mean(out$pre_def);out$pre_power<-out$pre_off-out$pre_def}
 route<-bind_rows(routes);complete<-expand.grid(team_id=ids,side=c('off','def'),stringsAsFactors=FALSE);complete$season<-s
 if(nrow(route))complete<-left_join(complete,route,by=c('season','team_id','side')) else complete$route<-NA_character_
 complete$route[is.na(complete$route)]<-'exact_v5_unit_prior'
 list(r=out,pm=inc$pm,fits=fits,routes=complete,max_train=min(s-1,2022),incumbent=inc)
}
v6_components <- function(base,history,features,blocks,extra,Lfixed=NULL) {
 cp<-base;cp$prior_fits<-list()
 for(s in unique(cp$frame$season)){sn<-Filter(function(z)z$season==s,cp$snap)[[1]];p<-v6_prior(s,sn$ids,history,features,blocks,extra,Lfixed);cp$prior_fits[[as.character(s)]]<-p
 for(k in names(cp$snap)){z<-cp$snap[[k]];if(z$season!=s)next;cp$snap[[k]]$pre<-p$r;cp$snap[[k]]$external_active<-TRUE;cp$snap[[k]]$new_active<-length(p$fits)>0
 ix<-which(cp$frame$season==s&cp$frame$cutoff==z$cutoff);cp$frame$pre_home[ix]<-p$r$pre_power[match(cp$frame$home_id[ix],p$r$team_id)];cp$frame$pre_away[ix]<-p$r$pre_power[match(cp$frame$away_id[ix],p$r$team_id)]}}
 cp
}
v6_calibrate <- function(cp,base,before,incpar) {
 tr<-cp$frame %>% filter(season<before,season<=2022,season!=2020);v6_guard(tr)
 p<-incpar
 if(!identical(tr$pre_home,base$frame$pre_home[match(tr$game_id,base$frame$game_id)])){
 z<-v5_scalar(function(a)mean(abs(a*(tr$pre_home-tr$pre_away)+p$scale$hfa*as.numeric(!tr$neutral)-tr$actual_margin)),c(.1,3),'preseason_scale')
 p$scale$scale<-z$value;p$profiles<-list(scale=z)
 }
 p$max_train<-max(tr$season);p
}
v6_current_model <- function(s,advanced) {
 tr<-advanced %>% filter(season<s,season<=2022,season!=2020,is.finite(success_rate)) %>% select(season,success_rate,pf)
 if(nrow(tr)<80)return(NULL)
 v6_select(list(tr),'success_rate','pf')
}
v6_current_snapshot <- function(sn,advanced,m) {
 if(is.null(m)||!nrow(sn$tg))return(sn)
 a<-advanced %>% filter(season==sn$season,available_at<sn$cutoff)
 assert(!any(a$game_id%in%sn$test$game_id),'Target advanced record in update')
 tg<-sn$tg;ix<-match(paste(tg$game_id,tg$team_id),paste(a$game_id,a$team_id));sr<-a$success_rate[ix]
 goodids<-names(which(tapply(is.finite(sr),tg$game_id,function(x)length(x)==2&&all(x))))
 use<-tg$game_id%in%goodids
 if(any(use)){f<-data.frame(success_rate=sr[use]);tg$pf[use]<-.75*tg$pf[use]+.25*v6_apply(f,m)
 oi<-match(paste(tg$game_id,tg$opp_id),paste(tg$game_id,tg$team_id));tg$pa<-tg$pf[oi]}
 sn$tg<-tg;sn
}
v6_evaluate <- function(cp,par,history,schedules,current=NULL,advanced=NULL,incpar=par) {
 out<-list();rr<-list();spec<-v5_candidates()$EB_features
 for(k in names(cp$snap)){
 sn<-cp$snap[[k]];p<-if(identical(sn$new_active,FALSE))incpar else par
 if(!is.null(current))sn<-v6_current_snapshot(sn,advanced,current[[as.character(sn$season)]])
 v6_guard(sn$tg);r<-v5_ratings(sn,spec,p);te<-cp$frame %>% filter(season==sn$season,cutoff==sn$cutoff)
 assert(!any(te$game_id%in%attr(r,'training_ids')),'Target ID in training');te$pred_margin<-v4_predict(r,te$home_id,te$away_id,te$neutral);te$hfa<-attr(r,'hfa');te$error<-te$pred_margin-te$actual_margin;te$abs_error<-abs(te$error)
 out[[k]]<-te;rr[[k]]<-mutate(r,season=sn$season,cutoff=sn$cutoff)
 }
 list(predictions=bind_rows(out),ratings=bind_rows(rr))
}
v6_gate <- function(candidate,incumbent,before) {
 a<-candidate %>% filter(season<before);b<-incumbent %>% filter(season<before)
 if(length(unique(a$season))<2)return(FALSE)
 assert(setequal(a$game_id,b$game_id),'Nested gate universe');d<-a$abs_error-b$abs_error[match(a$game_id,b$game_id)]
 mean(d)<= -.05&&sum(tapply(d,a$season,mean)<0)>=2
}
v6_advance <- function(d,b) {
 a<-v5_calibration(d);bb<-v5_calibration(b);p<-v5_paired(d,b)
 cbind(a,p,passes=p$estimate<= -.05&&abs(a$slope-1)<=abs(bb$slope-1)+.05&&abs(a$bias)<=abs(bb$bias)+.10&&a$rmse<=bb$rmse+.05&&p$improved>=2&&p$season_high<0&&p$block_high<0)
}
v6_probability_fit <- function(d,before) {
 v6_guard(d);d<-d[d$season<before&d$season<=2022&d$actual_margin!=0,];if(nrow(d)<500)return(NULL)
 m<-glm(I(actual_margin>0)~pred_margin,data=d,family=binomial(),control=glm.control(maxit=100))
 if(!m$converged||any(!is.finite(coef(m)))||any(abs(coef(m))>100))return(NULL)
 list(beta=coef(m),max_train=max(d$season),training_ids=d$game_id,training_hash=key_of(d),n=nrow(d))
}
v6_probability <- function(d,m) if(is.null(m))rep(NA_real_,nrow(d)) else plogis(m$beta[1]+m$beta[2]*d$pred_margin)
