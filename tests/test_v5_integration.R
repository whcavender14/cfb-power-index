suppressPackageStartupMessages(source('cfb_v5_operations.R'))
checks<-list();f<-v5_frozen();dev<-readRDS('outputs/round4/development_results.rds');d<-dev$predictions
old<-read.csv('outputs/round3/development_predictions.csv');a<-d %>% filter(candidate=='B',season>=2021);b<-old %>% filter(candidate=='B')
checks[['exact legacy 2021-2022 B predictions']]<-max(abs(a$pred_margin-b$pred_margin[match(a$game_id,b$game_id)]))<1e-9
checks[['identical development IDs all candidates']]<-all(vapply(split(d,d$candidate),function(q)setequal(q$game_id,d$game_id[d$candidate=='B']),logical(1)))
for(s in v5_config()$development)for(n in names(f$specs)){
 par<-dev$parameters[[paste(n,s)]];cp<-dev$cps[[f$specs[[n]]$features]];tr<-cp$frame %>% filter(season<s,season!=2020)
 # Explicitly evaluate mathematical objective, guarding R negation precedence.
 w<-tr$gp_home/(tr$gp_home+par$blend$k);v<-tr$gp_away/(tr$gp_away+par$blend$k)
 latent<-w*tr$eff_home-v*tr$eff_away+par$scale$scale*((1-w)*tr$pre_home-(1-v)*tr$pre_away)
 expected<-mean(abs(par$gamma*latent+par$scale$hfa*as.numeric(!tr$neutral)-tr$actual_margin))
 if(n=='B_scale')checks[[paste('gamma objective agreement',s)]]<-abs(expected-par$profiles$gamma$objective)<1e-8
 if(!is.null(par$profiles$scale)){
 objective<-mean(abs(par$scale$scale*(tr$pre_home-tr$pre_away)+par$scale$hfa*as.numeric(!tr$neutral)-tr$actual_margin))
 checks[[paste('prior scale objective agreement',n,s)]]<-abs(objective-par$profiles$scale$objective)<1e-8
 }
}
# Shared ratings path evaluated independently from stored validation output.
for(n in names(f$specs)) {
 spec<-f$specs[[n]];cp<-dev$cps[[spec$features]];sn<-Filter(function(q)q$season==2022,cp$snap)[[2]];par<-dev$parameters[[paste(n,2022)]]
 sch<-setNames(lapply(2015:2022,v4_schedule),2015:2022)
 cf<-if(isTRUE(spec$conference))v5_conference(2022,dev$history,sch) else NULL
 rr<-v5_ratings(sn,spec,par,cf,v5_membership(sch[['2022']]))
 p<-d %>% filter(candidate==n,season==2022,cutoff==sn$cutoff)
 checks[[paste('validation reconstruction',n)]]<-max(abs(v4_predict(rr,p$home_id,p$away_id,p$neutral)-p$pred_margin))<1e-9
}
# Full feature-missing pipeline includes B's calibration/handoff, not only its prior.
sn<-dev$cps$none$snap[[1]];sn$external_active<-FALSE
for(n in c('RP','Talent_RP','Full','EB_features')) {
 a<-v5_ratings(sn,f$specs[[n]],f$parameters[[n]])
 b<-v5_ratings(sn,f$specs$B,f$parameters$B)
 checks[[paste('all external missing full prediction fallback',n)]]<-identical(a,b)
}
# Original tests execute in a child R process with only their OUTPUT paths redirected.
# This ports all Round 3 checks without rewriting a Round 3 artifact.
for(path in c('tests/test_v4.R','tests/test_v4_integration.R')) {
 txt<-readLines(path)
 txt<-gsub("'outputs/round3/tests.csv'","'outputs/round4/ported_v4_tests.csv'",txt,fixed=TRUE)
 txt<-gsub("'outputs/round3/integration_tests.csv'","'outputs/round4/ported_v4_integration_tests.csv'",txt,fixed=TRUE)
 temp<-tempfile(fileext='.R');writeLines(txt,temp)
 status<-system2('Rscript',temp,stdout=paste0('outputs/round4/',basename(path),'.log'),stderr=paste0('outputs/round4/',basename(path),'.log'))
 checks[[paste('ported original suite',path)]]<-status==0
}
# Full production-vs-validation parity on frozen-parameter conditional folds.
if(file.exists('outputs/round4/conditional_results.rds')) {
 o<-readRDS('outputs/round4/conditional_results.rds');sn<-o$cps$none$snap[[3]]
 for(n in names(f$specs)) {
  r<-v5_build(2023,sn$cutoff,candidate=n)
  q<-o$predictions %>% filter(candidate==n,season==2023,cutoff==sn$cutoff)
  checks[[paste('full production feature-snapshot parity',n)]]<-max(abs(v4_predict(r,q$home_id,q$away_id,q$neutral)-q$pred_margin))<1e-9
 }
 g<-v4_schedule(2023);a<-v5_build(2023,sn$cutoff,candidate='Full',schedule=g);future<-g$available_at>=sn$cutoff
 g$home_points[future]<-999;g$away_points[future]<-0;g$final[future]<-TRUE
 b<-v5_build(2023,sn$cutoff,candidate='Full',schedule=g)
 checks[['future and target results cannot affect production prediction']]<-identical(a$power_rating,b$power_rating)
 checks[['production target IDs excluded']]<-length(intersect(attr(b,'training_ids'),g$game_id[g$kickoff>=sn$cutoff]))==0
 old<-readRDS('outputs/round3/locked_outer.rds')$predictions %>% filter(candidate=='B');new<-o$predictions %>% filter(candidate=='B')
 checks[['exact conditional v4 B reproduction']]<-max(abs(new$pred_margin-old$pred_margin[match(new$game_id,old$game_id)]))<1e-9
}
checks[['Round 3 source manifest unchanged']]<-{
 m<-read.csv('outputs/round3/pre_outer_manifest.csv');all(unname(tools::md5sum(m$path))==m$md5)
}
q<-data.frame(test=names(checks),pass=unlist(checks));v5_write(q,'integration_tests');print(q[!q$pass,]);stopifnot(all(q$pass));cat(nrow(q),'integration checks passed\n')
