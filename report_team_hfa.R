source('team_hfa_experiment.R')
out<-'outputs/team_hfa';f<-readRDS(file.path(out,'design_frozen.rds'))
b<-hfa_read('outputs/round5/development_predictions.csv')
# Correct illustrative reporting cutoff: the frozen 2023 baseline and ridge
# tuning include season-2022 postseason games played during January 2023.
# February 1 is after those games; January 1 would not be a valid as-of label.
cut<-as.POSIXct('2023-02-01',tz='UTC')
g<-v4_schedule(2022);nm<-unique(bind_rows(transmute(g,team_id=home_id,team=home_team),transmute(g,team_id=away_id,team=away_team)))
ff<-readRDS('outputs/round4/design_frozen.rds');hf<-ff$parameters$EB_features$scale$hfa
ex<-bind_rows(lapply(c('ridge','eb'),function(n){fit<-hfa_fit(b,cut,f$parameters[[n]]);t<-fit$table
 t$global_HFA<-hf;t$team_HFA<-hf+t$deviation;t$candidate<-n;t$as_of<-cut
 away<-b[b$available_at<cut & !b$neutral,];av<-aggregate(pred_margin-actual_margin~away_id,away,mean);names(av)<-c('team_id','away_mean_residual')
 left_join(left_join(t,nm,by='team_id'),av,by='team_id')}))
write.csv(ex,file.path(out,'team_estimates_20230201.csv'),row.names=FALSE)
# Retain initial example artifact as an explicitly invalid diagnostic, never a prediction.
dir.create(file.path(out,'invalid_examples'),showWarnings=FALSE)
p<-file.path(out,'team_estimates_end2022.csv');if(file.exists(p))stopifnot(file.rename(p,file.path(out,'invalid_examples','team_estimates_end2022.csv')))
writeLines(c('# Example cutoff correction', '', 'The initial runner combined pre-January-1 residual counts with the frozen 2023 global baseline and tuning, which include January postseason labels. That is not a valid January-1 historical estimate. It is retained only in invalid_examples/. Use team_estimates_20230201.csv: all season-2022 results and frozen parameters were available by February 1, 2023. No validation prediction, hyperparameter, selection decision, pre-fit design, or production file changed. The report script makes this reporting-only correction reproducible.'),file.path(out,'EXAMPLE_CORRECTION.md'))
write.csv(data.frame(path=c('report_team_hfa.R','tests/test_team_hfa.R'),md5=unname(tools::md5sum(c('report_team_hfa.R','tests/test_team_hfa.R')))),file.path(out,'report_test_manifest.csv'),row.names=FALSE)
print(ex[ex$team%in%c('LSU','Massachusetts','Alabama','Ohio State','Boise State','Clemson') & ex$candidate=='ridge',c('team','team_HFA','n','effective_n','shrinkage','away_mean_residual')],row.names=FALSE)
