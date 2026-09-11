# Supplementary development-only audit of already declared fixed specifications.
# Does not select a winner, rewrite the freeze, or evaluate locked games.
suppressPackageStartupMessages(source('cfb_v4_operations.R'))
f<-readRDS('outputs/round3/design_frozen.rds');x<-readRDS('outputs/round3/development_components.rds')
assert(all(x$cp$frame$season<=2022),'Secondary audit received locked data')
oldhash<-unname(tools::md5sum('outputs/round3/design_frozen.rds'));out<-list()
for(s in 2021:2022)for(n in c('C4','C12','Ccap32','Casym','Crecent','CFCS')) {
 out[[paste(s,n)]]<-v4_evaluate(v4_subset(x$cp,s),f$specs[[n]],f$development_parameters[[as.character(s)]]$scale,NULL,x$sch) %>% mutate(candidate=n)
}
d<-bind_rows(out);dev<-read.csv('outputs/round3/development_predictions.csv');dev$game_id<-as.character(dev$game_id);base<-dev %>% filter(candidate=='B')
v4_write(d,'secondary_audit_predictions');v4_write(summarize_predictions(d,'candidate'),'secondary_audit_metrics')
v4_write(summarize_predictions(d,c('candidate','season')),'secondary_audit_by_season')
v4_write(bind_rows(lapply(unique(d$candidate),function(n)cbind(candidate=n,v4_paired(d %>% filter(candidate==n),base)))),'secondary_audit_paired_vs_B')
assert(identical(oldhash,unname(tools::md5sum('outputs/round3/design_frozen.rds'))),'Frozen design changed')
writeLines(c('Supplementary development diagnostics only; run after primary outer report.',
 'Specifications were declared before outer evaluation. Original secondary selection gate was closed.',
 'No winner selected, no outer evaluations, no parameter or production change.',
 'These results are outside the primary preregistered execution protocol and must not be used to revise its locked claim.'),
 'outputs/round3/secondary_audit_status.txt')
print(summarize_predictions(d,'candidate'))
