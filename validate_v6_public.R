suppressPackageStartupMessages(source('cfb_v6_operations.R'))
v6_market_report <- function(predictions,lines) {
 v6_guard(predictions)
 req<-c('game_id','spread','spread_semantics','closing_verified')
 assert(setequal(names(lines),req),'Line file requires only game_id, spread, spread_semantics, closing_verified')
 assert(!anyDuplicated(lines$game_id)&&!anyNA(lines),'Duplicate/incomplete line file')
 assert(all(lines$spread_semantics=='home_team_spread'),'Unverified home spread semantics')
 assert(is.logical(lines$closing_verified),'Closing verification status must be explicit TRUE/FALSE')
 assert(is.numeric(lines$spread)&&all(is.finite(lines$spread)),'Invalid line values')
 assert(setequal(as.character(predictions$game_id),as.character(lines$game_id)),'Incomplete or nonmatched line coverage')
 mm<- -lines$spread[match(predictions$game_id,lines$game_id)];actual<-predictions$actual_margin;pick<-sign(predictions$pred_margin-mm);result<-sign(actual-mm);ok<-pick!=0&result!=0
 q<-predictions;q$delta<-abs(predictions$pred_margin-actual)-abs(mm-actual)
 list(metrics=data.frame(n=nrow(q),coverage=1,ats_decisions=sum(ok),ats_wins=sum(pick[ok]==result[ok]),ats_rate=if(any(ok))mean(pick[ok]==result[ok]) else NA_real_,pushes=sum(result==0),model_line_ties=sum(pick==0),model_mae=mean(abs(q$pred_margin-actual)),market_mae=mean(abs(mm-actual)),all_closing_verified=all(lines$closing_verified)),paired=v5_boot(q))
}
if(sys.nframe()==0){
 f<-v6_frozen();v6_verify(read.csv(file.path(v6_dir,'prediction_freeze_manifest.csv')))
 path<-file.path(v6_dir,'conditional_predictions.csv');assert(file.exists(path),'Frozen conditional predictions must precede lines');p<-read.csv(path);p<-p[p$candidate==f$selected,];args<-commandArgs(TRUE)
 if(!length(args)){writeLines(c('# Market benchmark','', 'ATS and market MAE omitted: no complete, uniquely keyed line file with explicit home-team spread semantics and closing-verification labels was supplied to this command. This is a fail-closed reporting decision; no market file enters modeling.', 'Use Rscript validate_v6_public.R /absolute/path/to/lines.csv after prediction freeze. Schema: game_id,spread,spread_semantics,closing_verified; semantics must be home_team_spread. Closing status may honestly be FALSE; it must not be silently invented.', 'Market margin is -spread. Pushes and exact model/line ties are excluded. ATS is descriptive and does not establish profitability.'),file.path(v6_dir,'MARKET_BENCHMARK.md'))}else{
 lines<-read.csv(args[1]);r<-v6_market_report(p,lines);v6_write(r$metrics,'public_market_metrics');v6_write(r$paired,'public_market_uncertainty');v6_write(v6_manifest(args[1]),'market_source_manifest')
 }
}
