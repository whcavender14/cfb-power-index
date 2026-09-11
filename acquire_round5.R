suppressPackageStartupMessages(library(cfbfastR))
args<-commandArgs(TRUE);years<-if(length(args)&&args[1]=='conditional')2023:2025 else 2015:2022
for(s in years) {
 p<-sprintf('outputs/round5/raw/advanced_game_%s.rds',s)
 if(!file.exists(p)){message('Historical game statistics ',s);r<-cfbd_stats_game_advanced(s,excl_garbage_time=FALSE,season_type='both');stopifnot(nrow(r)>0);saveRDS(r,p)}
}
if(length(args)&&args[1]=='conditional')for(s in years){
 p<-sprintf('outputs/round5/raw/drives_%s.rds',s)
 if(!file.exists(p)){r<-dplyr::bind_rows(lapply(c('regular','postseason'),function(st)cfbd_drives(s,season_type=st)));stopifnot(nrow(r)>0);saveRDS(r,p)}
 p<-sprintf('outputs/round5/raw/team_stats_%s.rds',s)
 if(!file.exists(p)){r<-cfbd_stats_season_team(s);stopifnot(nrow(r)>0);saveRDS(r,p)}
}
