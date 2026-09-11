suppressPackageStartupMessages(source('cfb_v6_operations.R'))
f<-v6_frozen()
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
metric<-function(d){
 z<-v5_calibration(d);z$prediction_sd<-sd(d$pred_margin);z$actual_margin_sd<-sd(d$actual_margin);ok<-d$actual_margin!=0&d$pred_margin!=0;z$straight_up_accuracy<-mean(sign(d$pred_margin[ok])==sign(d$actual_margin[ok]));z
}
probmetric<-function(d){
 d<-d[is.finite(d$p_home)&d$actual_margin!=0,];if(!nrow(d))return(tibble(n=0,brier=NA_real_,log_loss=NA_real_,accuracy=NA_real_,intercept=NA_real_,slope=NA_real_))
 y<-as.numeric(d$actual_margin>0);p<-pmin(1-1e-6,pmax(1e-6,d$p_home));fit<-suppressWarnings(glm(y~qlogis(p),family=binomial()));tibble(n=nrow(d),brier=mean((p-y)^2),log_loss=-mean(y*log(p)+(1-y)*log(1-p)),accuracy=mean((p>.5)==y),intercept=unname(coef(fit)[1]),slope=unname(coef(fit)[2]))
}
fmt<-function(x)paste(capture.output(print(as.data.frame(x),row.names=FALSE,digits=4)),collapse='\n')
for(stage in c('development','conditional')){
 path<-file.path(v6_dir,paste0(stage,'_results.rds'));if(!file.exists(path))next;z<-readRDS(path);d<-z$predictions
 metrics<-d %>% group_by(candidate) %>% group_modify(~metric(.x)) %>% ungroup();v6_write(metrics,paste0(stage,'_metrics'))
 v6_write(d %>% group_by(candidate,season) %>% group_modify(~metric(.x)) %>% ungroup(),paste0(stage,'_by_season'))
 b<-d[d$candidate=='v5_EB_features',]
 v6_write(bind_rows(lapply(unique(d$candidate),function(n)cbind(candidate=n,v5_paired(d[d$candidate==n,],b)))),paste0(stage,'_paired'))
 d$period_bucket<-ifelse(d$week_seq<=4,as.character(d$week_seq),'5+');d$gp_bucket<-cut(pmin(d$gp_home,d$gp_away),c(-1,0,1,3,6,Inf));d$prior_bucket<-cut(abs(d$prior_home-d$prior_away),c(-Inf,7,14,28,Inf));d$promotion<-d$promoted_home+d$promoted_away>0;d$connectivity_bucket<-cut(pmin(d$component_size_home,d$component_size_away),c(0,1,15,63,Inf));d$site<-ifelse(d$neutral,'neutral','nonneutral');d$global<-'all';d$period_site<-paste(d$period_bucket,d$site)
 bw<-block_weights(d)
 for(g in c('global','site','period_bucket','period_site','gp_bucket','prior_bucket','promotion','connectivity_bucket'))v6_write(diag_table(d,g,bw),paste0(stage,'_calibration_',g))
 d$reliability_bin<-cut(d$pred_margin-d$hfa*as.numeric(!d$neutral),c(-Inf,-28,-14,-7,0,7,14,28,Inf))
 v6_write(d %>% group_by(candidate,reliability_bin) %>% summarise(n=n(),predicted=mean(pred_margin-hfa*as.numeric(!neutral)),actual=mean(actual_margin-hfa*as.numeric(!neutral)),.groups='drop'),paste0(stage,'_margin_reliability'))
 v6_write(z$ratings %>% group_by(candidate,season,cutoff) %>% summarise(n=n(),power_mean=mean(power_rating),power_sd=sd(power_rating),off_sd=sd(off_rating),def_sd=sd(def_rating),.groups='drop'),paste0(stage,'_rating_distribution'))
 teams<-bind_rows(lapply(c('home','away'),function(s){q<-d;sgn<-if(s=='home')1 else -1;for(n in c('pred_margin','actual_margin','error','hfa'))q[[n]]<-sgn*q[[n]];q$conference<-q[[paste0(s,'_conference')]];q$degree<-cut(q[[paste0('n_fbs_opponents_',s)]],c(-1,0,1,3,6,Inf));q$cross<-cut(q[[paste0('n_cross_',s)]],c(-1,0,1,Inf));q$fcs<-cut(q[[paste0('n_fcs_',s)]],c(-1,0,1,Inf));q}))
 for(g in c('conference','degree','cross','fcs'))v6_write(diag_table(teams,g,bw),paste0(stage,'_network_',g))
 v6_write(d %>% group_by(candidate) %>% group_modify(~probmetric(.x)) %>% ungroup(),paste0(stage,'_probability_metrics'))
 v6_write(d %>% group_by(candidate,season) %>% group_modify(~probmetric(.x)) %>% ungroup(),paste0(stage,'_probability_by_season'))
 v6_write(d %>% group_by(candidate,period_bucket) %>% group_modify(~probmetric(.x)) %>% ungroup(),paste0(stage,'_probability_by_period'))
 pp<-d[is.finite(d$p_home)&d$actual_margin!=0,];pp$bin<-cut(pp$p_home,seq(0,1,.1),include.lowest=TRUE)
 v6_write(pp %>% group_by(candidate,bin) %>% summarise(n=n(),predicted=mean(p_home),actual=mean(actual_margin>0),.groups='drop'),paste0(stage,'_probability_reliability'))
 uncertainty<-list()
 for(n in unique(pp$candidate)){q<-pp[pp$candidate==n,];p<-pmin(1-1e-6,pmax(1e-6,q$p_home));y<-as.numeric(q$actual_margin>0);q$brier<-(p-y)^2;q$log_loss<- -(y*log(p)+(1-y)*log(1-p));q$accuracy<-as.numeric((p>.5)==y)
 for(k in c('brier','log_loss','accuracy'))uncertainty[[paste(n,k)]]<-cbind(candidate=n,metric=k,v5_boot(q,k))}
 v6_write(bind_rows(uncertainty),paste0(stage,'_probability_uncertainty'))
 title<-if(stage=='development')'Earlier-only development: 2019, 2021, 2022' else '2023–2025 secondary conditional scoring — not a fresh outer test'
 writeLines(c(paste('#',title),'',paste('Frozen selection:',f$selected), '', '```',fmt(metrics),'```','',
 'All candidates share identical final FBS-versus-FBS IDs, including postseason. Candidate selection uses only development outcomes through2022. New families must clear every frozen safeguard; conditional performance cannot change selection.',
 '', 'The current-efficiency candidate replaces a fixed 25% of available past team-score evidence with a success-rate score mapping learned on earlier game rows. Added preseason blocks use fold-local elastic net and incumbent unit fallback. The special-teams family tests returns/field position; it does not cover kicking reliability or punting efficiency.',
 '', 'Position RP, valid QB starters/quality and coordinator continuity were not estimable from recovered historical state evidence. Their missing experiment is not a fitted zero effect. EPA/explosiveness are excluded because expected-points training/version provenance remains unresolved.',
 '', 'Probability coverage is reported separately. 2019 has no eligible earlier frozen margin predictions for this mapping; it remains missing. Brier/log loss and reliability apply only to rows with earlier-fitted probabilities. This layer never affects published margins or selection.',
 '', 'Diagnostics: separate calibration, probability, reliability, network and distribution CSVs. Fixed seed9041, 2000 season and season-then-Monday-block resamples. Only three principal development seasons limit precision. 2026 is prospective only.'),file.path(v6_dir,if(stage=='development')'DEVELOPMENT_REPORT.md' else 'SECONDARY_CONDITIONAL_REPORT.md'))
}
# Export fold designs, coefficients, CV decisions and coverage routes.
z<-readRDS(file.path(v6_dir,'development_results.rds'));co<-list();cv<-list();dr<-list();rt<-list();opt<-list()
for(n in names(z$cps))for(s in names(z$cps[[n]]$prior_fits)){
 p<-z$cps[[n]]$prior_fits[[s]];if(nrow(p$routes))rt[[length(rt)+1]]<-mutate(p$routes,candidate=n,target_season=as.integer(s))
 for(reg in names(p$fits)){m<-p$fits[[reg]];co[[length(co)+1]]<-data.frame(candidate=n,target_season=s,regime=reg,term=m$design$keep,beta=m$beta,train_mean=m$design$mu,train_sd=m$design$sd,alpha=m$alpha%or%0,lambda=m$lambda,max_train=m$max_train,objective=m$objective%or%NA_real_,training_mse=m$training_mse%or%NA_real_);cv[[length(cv)+1]]<-mutate(m$cv,candidate=n,target_season=s,regime=reg);if(length(m$design$dropped))dr[[length(dr)+1]]<-data.frame(candidate=n,target_season=s,regime=reg,term=names(m$design$dropped),reason=unlist(m$design$dropped))}
}
for(n in names(z$parameters))for(k in names(z$parameters[[n]]$profiles)){p<-z$parameters[[n]]$profiles[[k]];opt[[length(opt)+1]]<-data.frame(fit=n,parameter=k,value=p$value,objective=p$objective,boundary=p$boundary,status=p$status)}
v6_write(bind_rows(co),'prior_coefficients');v6_write(bind_rows(cv),'nested_penalty_validation');v6_write(bind_rows(dr),'dropped_predictors');v6_write(bind_rows(rt),'feature_coverage_routes');v6_write(bind_rows(opt),'optimizer_diagnostics')
writeLines(c('# Model specification','',readLines(file.path(v6_dir,'ROUND5_PREDECLARATION.md')),'',paste('Frozen selected operational candidate:',f$selected)),file.path(v6_dir,'MODEL_SPEC.md'))
writeLines(c('# Calibration decision','',paste('Selected:',f$selected),'','```',fmt(read.csv(file.path(v6_dir,'candidate_ledger.csv'))[,c('candidate','mae','rmse','bias','slope','estimate','season_high','block_high','passes','disposition')]),'```','','No held-out slope was forced to one. Absolute bias may worsen <=0.10 points and RMSE <=0.05 points under the pre-fit rule. EB precision remains4; HFA is additive and separate from neutral scale. Scalar objective values describe prior-margin calibration; unit-regression objectives include elastic-net penalties. Comparator k is unused by EB.','Three development seasons limit confidence. Conditional and market outcomes played no role in selection.'),file.path(v6_dir,'CALIBRATION_DECISION.md'))
writeLines(c('# Public validation','',paste('Frozen operational candidate:',f$selected),'','See DEVELOPMENT_REPORT.md and SECONDARY_CONDITIONAL_REPORT.md, with matching metrics/probability CSVs. 2026 remains prospective only.','Margin MAE, RMSE, bias, neutralized slope/intercept and SDs are in *_metrics.csv; straight-up accuracy excludes predicted/actual exact ties. Probabilities have separately reported coverage and never modify ratings.','ATS/market reporting is a separate post-freeze command. It fails closed unless line coverage, semantics and uniqueness pass. No line file is silently borrowed or reclassified as verified closing.'),file.path(v6_dir,'PUBLIC_VALIDATION.md'))
capture.output(sessionInfo(),file=file.path(v6_dir,'sessionInfo.txt'))
