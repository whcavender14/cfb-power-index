suppressPackageStartupMessages(source('cfb_power_ratings_v6.R'))
mode<-commandArgs(TRUE);years<-if(length(mode)&&mode[1]=='conditional')2015:2025 else 2015:2022
sch<-setNames(lapply(years,v4_schedule),years);advanced<-list();extras<-list();resolution<-list();derived<-list()
for(s in years){
 g<-sch[[as.character(s)]];ids<-fbs_ids(g);tg<-team_games(g,ids,0)
 lookup<-bind_rows(g %>% transmute(game_id,team=home_team,team_id=home_id),g %>% transmute(game_id,team=away_team,team_id=away_id))
 raw<-readRDS(sprintf('outputs/round5/raw/advanced_game_%s.rds',s));v6_guard(raw)
 a<-raw %>% mutate(game_id=as.character(game_id)) %>% left_join(lookup,by=c('game_id','team'))
 resolution[[paste0('a',s)]]<-a %>% transmute(season=s,game_id,team,team_id,status=ifelse(is.na(team_id),'unmatched','resolved_game_team'))
 assert(!anyDuplicated(paste(a$game_id,a$team)),'Duplicate raw advanced team game');resolved<-!is.na(a$team_id);assert(!anyDuplicated(paste(a$game_id[resolved],a$team_id[resolved])),'Duplicate resolved advanced team game')
 aa<-inner_join(tg,a %>% select(game_id,team_id,all_of(paste0('off_',v6_eff_metrics))),by=c('game_id','team_id'))
 aa$season<-s;aa$success_rate<-aa$off_success_rate
 advanced[[as.character(s)]]<-aa %>% select(season,game_id,team_id,opp_id,available_at,pf,success_rate)
 f<-data.frame(season=s+1L,team_id=ids)
 for(metric in v6_eff_metrics){q<-aa;value<-q[[paste0('off_',metric)]];ok<-is.finite(value)
 good<-names(which(tapply(ok,q$game_id,function(z)length(z)==2&&all(z))));q<-q[q$game_id%in%good,];q$pf<-q[[paste0('off_',metric)]];q$pa<-q$pf[match(paste(q$game_id,q$opp_id),paste(q$game_id,q$team_id))]
 r<-v4_score_fit(q,ids,lambda=1,hfa=0)
 for(side in c('off','def')){v<-r[[paste0('eff_',side)]];v[r$games_played==0]<-NA_real_;f[[paste0('adj_',side,'_',metric)]]<-v}
 }
 path<-sprintf('outputs/round5/raw/drives_%s.rds',s)
 if(file.exists(path)){
 d<-readRDS(path);v6_guard(d);d$game_id<-as.character(d$game_id)
 assert(!anyDuplicated(paste(d$game_id,d$drive_id)),'Duplicate drives')
 d<-d %>% inner_join(g %>% filter(final,home_fbs,away_fbs) %>% select(game_id,home_id,away_id,available_at),by='game_id') %>% filter(start_period<5,is.finite(start_yards_to_goal),start_yards_to_goal>=0,start_yards_to_goal<=100)
 d$team_id<-ifelse(d$is_home_offense,d$home_id,d$away_id);d$opp_id<-ifelse(d$is_home_offense,d$away_id,d$home_id)
 # Regulation only; equal drives; no EPA field-position transformation.
 for(side in c('off','def')){key<-if(side=='off')d$team_id else d$opp_id;v<-tapply(d$start_yards_to_goal,key,mean);f[[paste0('field_',side)]]<-as.numeric(v[as.character(ids)])}
 }
 statpath<-sprintf('outputs/round5/raw/team_stats_%s.rds',s)
 if(file.exists(statpath)){st<-readRDS(statpath);mp<-lookup %>% distinct(team,team_id);st<-left_join(st,mp,by='team');assert(!anyDuplicated(st$team_id[!is.na(st$team_id)]),'Ambiguous season team stats');ix<-match(ids,st$team_id);for(unit in c('kick','punt')){num<-st[[paste0(unit,'_return_yds')]][ix];den<-st[[paste0(unit,'_returns')]][ix];f[[paste0(unit,'_return_ypr')]]<-ifelse(den>0,num/den,NA_real_)}}
 extras[[as.character(s)]]<-f
}
extra<-bind_rows(extras);ad<-bind_rows(advanced);saveRDS(list(extra=extra,advanced=ad),file.path(v6_dir,if(max(years)>2022)'conditional_inputs.rds' else 'inputs.rds'))
v6_write(bind_rows(resolution),if(max(years)>2022)'conditional_team_resolution' else 'team_resolution')
if(max(years)>2022)quit(save='no')
# Preserve all inherited files before any legacy test executes.
paths<-c(Sys.glob('outputs/round3/*'),Sys.glob('outputs/round4/*'),Sys.glob('tests/*'),c('cfb_power_ratings_v4.R','cfb_power_ratings_v5.R','cfb_v4_operations.R','cfb_v5_operations.R','run_2026_rankings.R','validate_v5_public.R'))
paths<-paths[!file.info(paths)$isdir];v6_write(v6_manifest(paths),'inherited_integrity')
rawpaths<-c(Sys.glob('outputs/round5/raw/*'),sprintf('cfb_data_v3/raw_schedule_%s.rds',2015:2022),'outputs/round4/features.rds')
v6_write(v6_manifest(rawpaths),'source_manifest')
manifest<-bind_rows(lapply(rawpaths,function(p){d<-if(grepl('rds$',p))readRDS(p) else NULL;s<-suppressWarnings(as.integer(sub('.*_([0-9]{4})\\.rds$','\\1',p)))
 data.frame(season=s,team_id=NA_integer_,player_id=NA_character_,feature_snapshot_id=key_of(p),feature_values='raw source retained separately',source_url_query_provider_version=if(grepl('advanced_game',p))paste0('CFBD /stats/game/advanced year=',s,' excludeGarbageTime=false seasonType=both; cfbfastR 3.0.0.9000') else if(grepl('drives_',p))paste0('CFBD /drives year=',s,' regular+postseason; cfbfastR 3.0.0.9000') else p,raw_content_hash=digest::digest(file=p,algo='sha256'),historical_available_at_if_verified=NA_character_,timestamp_evidence_kind=NA_character_,timestamp_evidence_reference=NA_character_,retrieved_at_not_publication=as.character(if(is.null(attr(d,'cfbfastR_timestamp')))NA else attr(d,'cfbfastR_timestamp')),vintage_status='historical_vintage_unverified',leakage_risk_status='no_identified_leakage_in_whitelisted_fields',aggregation_rule='frozen protocol and FEATURE_AUDIT.md',source_to_team_resolution_status='see team_resolution.csv')
}))
v6_write(manifest,'FEATURE_PROVENANCE_MANIFEST')
for(i in seq_len(nrow(extra))){s<-extra$season[i];p<-rawpaths[grepl(paste0('_',s-1,'\\.rds$'),rawpaths)];derived[[i]]<-data.frame(season=s,team_id=extra$team_id[i],player_id=NA_character_,feature_snapshot_id=key_of(extra[i,]),feature_values=paste(names(extra)[-(1:2)],format(unlist(extra[i,-(1:2)]),digits=17),sep='=',collapse=';'),source_url_query_provider_version='CFBD game advanced and drives; exact queries in source manifest',raw_content_hash=paste(vapply(p,function(z)digest::digest(file=z,algo='sha256'),character(1)),collapse=';'),historical_available_at_if_verified=NA_character_,timestamp_evidence_kind=NA_character_,timestamp_evidence_reference=NA_character_,vintage_status='historical_vintage_unverified',leakage_risk_status='prior_season_only',aggregation_rule='game-level opponent ridge1 success/front; regulation mean starting yards to goal',source_to_team_resolution_status='resolved_game_team',calculation_hash=digest::digest(file='audit_round5.R',algo='sha256'))}
v6_write(bind_rows(derived),'DERIVED_FEATURE_PROVENANCE_MANIFEST')
v6_write(extra,'team_features');v6_write(extra %>% group_by(season) %>% summarise(across(everything(),~sum(is.finite(.x))),.groups='drop'),'feature_coverage')
p<-read.csv('outputs/round4/portal_event_ledger.csv');p<-p[p$season<=2022,];p$player_id<-NA_character_;p$resolution_status<-ifelse(is.na(p$destination_id)&!is.na(p$origin_id),'origin-only',ifelse(is.na(p$origin_id)&!is.na(p$destination_id),'destination-only','unmatched_player_id'));p$accepted_for_production<-FALSE;p$manual_override<-NA_character_;p$confidence<-NA_real_;v6_write(p,'player_resolution_event_ledger')
writeLines(c('# Feature audit — frozen eligibility before fitting','',
'Incumbent talent/aggregate returning/head-coach snapshots are reused unchanged with their Round 4 unverified historical vintage and strict whitelist. Blank publication dates remain blank. Only <=2022 responses enter development.',
'',
'CFBD game advanced records: 2015–2022, regular+postseason, excludeGarbageTime=false. Exact game/team name mapping uses that game\'s historical schedule IDs. Duplicate keys fail. FCS games excluded. Per-metric game pairs require both teams. Offense and opponent defensive burden are estimated jointly with fixed ridge1 and no HFA. A team with no metric evidence is missing, never a fabricated zero.',
'',
'The saved public app/stats/stats.service.js documents success thresholds: scoring succeeds except excluded play types; first down >=50% distance, second >=70%, later downs >=100%. Pass/rush types and penalty exclusions are provider SQL rules. Plays are restricted to non-null PPA, which is a coverage criterion, not use of its value. All periods, including overtime, are included by the game advanced query; garbage time is included. Line yards: negative yards *1.2, yards 0–4 full credit, 5–10 half credit beyond 4, above10 capped at7; stuff is rush yards<=0. This current source snapshot documents methodology but is not an authenticated historical deployed version. Historical revisions remain a limitation.',
'',
'EPA/PPA and explosiveness are blocked: the supplied team-game EPA cache cannot authenticate the training era or exact expected-points model version. The new query values are retained only in raw originals, excluded before modeling. Havoc and scoring-opportunity decomposition absent in this endpoint remain untested.',
'',
'Special-teams/field-position family uses the recoverable field-position and raw kick/punt return yards-per-return sub-blocks. Zero return attempts route to incumbent, not zero efficiency. Field position: regulation drives start_period<5, finite start_yards_to_goal in [0,100], mean per actual offensive and opposing drive. Include all regulation drive results, no garbage filter; raw penalties are reflected in recorded start positions. No EPA transformation or stadium effect. FG attempts/makes and punting efficiency absent from recovered season-stat fields; not invented. Special-teams continuity unavailable without preseason player snapshots.',
'',
'Position RP and QB: inherited aggregate RP has no contributors; inherited portal starts2021 and has no player IDs. Historical roster endpoint supplies year/team but no pre-cutoff state authentication. Do not infer starter/returner identity from target-season usage. No sufficiently broad valid historical preseason player/starter archive recovered; both primary families not estimable. All five QB states are retained in validation schema, no numeric unknown replacement. No transfer numerator fitted. Origin-only events remain in the ledger.',
'',
'Coordinator: no season-appropriate coordinator assignment source in supplied snapshots; head-coach API is not coordinator evidence. Family not estimable. The absence is a data limitation, not a negative fitted effect.',
'',
'Multi-year: declared score history only, immediate lag distinct; older count explicit, no target season. No external feature is imputed. Exact source and transformation hashes are in manifests.',
'',
'Eligibility decisions precede fitting. Missing publication dates alone exclude nothing. Stronger independently verified vintage subset has zero supported forward folds. Coverage/all-missing sensitivities are reported without changing scored IDs.',
'',
'Sources: https://raw.githubusercontent.com/CFBD/cfb-api/main/app/stats/stats.service.js ; https://cfbfastr.sportsdataverse.org/reference/cfbd_stats_game_advanced.html ; https://cfbfastr.sportsdataverse.org/reference/cfbd_drives.html ; https://cfbfastr.sportsdataverse.org/reference/load_cfb_rosters.html . Public methodological links in the user request were inspected, not imported as model values.'),file.path(v6_dir,'FEATURE_AUDIT.md'))
