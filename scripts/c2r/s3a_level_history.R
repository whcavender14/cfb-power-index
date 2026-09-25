# C2 refinement research, Stage 3, part A: the FCS level over time and the prospective anchors (docs/c2r/STAGE3_PLAN.md §4).
# Run from the round15-power-rating worktree root. Uses points-only end-of-season fits (no model outcome metric).
source("config/paths.R"); source("config/production.R")
suppressPackageStartupMessages({ source(PATHS$model_ops); library(data.table); for (f in c("data", "c1", "c2")) source(sprintf("R/round15/candidates/%s.R", f)) })
source("/Users/willcavender/Desktop/Revised CFB Modeling/.claude/worktrees/c2-refinement/scripts/c2r/lib_c2r.R"); source(file.path(C2R, "scripts/c2r/lib_s3.R"))
out <- file.path(C2R, "output/c2r/stage3"); dir.create(out, recursive = TRUE, showWarnings = FALSE); OUT <- file.path(C2R, "docs/c2r/stage3"); dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
options(width = 220)
d <- r15_build_data(); dv <- readRDS(file.path(C2R, "output/c2r/stage1/divisions.rds"))
E <- lapply(2013:2025, function(s) s3_eos_levels(d, s, dv)); lv <- rbindlist(lapply(E, `[[`, "level")); tm <- rbindlist(lapply(E, `[[`, "teams"))
cat("== end-of-season FCS level (both group levels free) ==\n"); print(lv, digits = 3); fwrite(lv, file.path(OUT, "s3_level_by_season.csv"))

# ---- is the level drifting? (2020 excluded: 22 FCS teams, 36 linking games)
h <- lv[season != 2020]; wts <- 1 / h$se_fcs^2
f0 <- lm(fcs ~ 1, h, weights = wts); f1 <- lm(fcs ~ I(season - 2019), h, weights = wts)
Q0 <- sum(wts * (h$fcs - coef(f0)[1])^2); Q1 <- sum(wts * residuals(f1)^2)
tr <- data.table(seasons = paste(range(h$season), collapse = "-"), n = nrow(h), weighted_mean = coef(f0)[1], slope_per_season = coef(f1)[2],
                 slope_se_model = summary(f1)$coefficients[2, 2] / summary(f1)$sigma, slope_se_overdispersed = summary(f1)$coefficients[2, 2] * max(1, summary(f1)$sigma) / summary(f1)$sigma, slope_p_model = 2 * pnorm(-abs(coef(f1)[2] / (summary(f1)$coefficients[2, 2] / summary(f1)$sigma))),
                 Q_constant = Q0, p_constant = pchisq(Q0, nrow(h) - 1, lower.tail = FALSE), Q_linear = Q1, p_linear = pchisq(Q1, nrow(h) - 2, lower.tail = FALSE),
                 mean_2013_2016 = mean(h[season <= 2016, fcs]), mean_2017_2022 = mean(h[season %in% 2017:2022, fcs]), mean_2023_2025 = mean(h[season >= 2023, fcs]))
cat("\n== drift tests (SE-weighted; slope SE from the known measurement SEs) ==\n"); print(tr, digits = 3); fwrite(tr, file.path(OUT, "s3_level_trend.csv"))

# ---- composition
fcsm <- tm[grp == "fcs"]; seas <- setdiff(2014:2025, 2020)
panel <- fcsm[season %in% seas, .N, by = team_id][N == length(seas), team_id]
cmp <- fcsm[season %in% c(2013, seas), .(n_fcs = .N, all_fcs = mean(power), panel_fcs = mean(power[team_id %in% panel])), by = season]
ent <- rbindlist(lapply(seas, function(y) { prev <- if (y == 2021) 2019 else y - 1; a <- fcsm[season == y]; b <- tm[season == prev]
  new <- a[!team_id %in% b[grp == "fcs", team_id]]; up <- b[grp == "fcs" & team_id %in% fbs_ids(d$sch[[as.character(y)]])]
  data.table(season = y, entrants = nrow(new), entrants_power = if (nrow(new)) mean(new$power) else NA_real_, entrants_from_lower = sum(new$team_id %in% b[grp != "fcs" & grp != "fbs", team_id]),
             left_for_fbs = nrow(up), leavers_prev_power = if (nrow(up)) mean(up$power) else NA_real_) }))
cmp <- merge(cmp, ent, by = "season", all.x = TRUE)
sch <- rbindlist(lapply(c(2013, seas), function(y) { g <- d$games[[as.character(y)]][final == TRUE & xor(home_fbs %in% TRUE, away_fbs %in% TRUE)]
  nf <- fifelse(g$home_fbs %in% TRUE, g$away_id, g$home_id); p <- fcsm[season == y][match(nf, team_id), power]
  data.table(season = y, fbs_scheduled_fcs_power = mean(p, na.rm = TRUE)) }))
cmp <- merge(cmp, sch, by = "season"); cmp[, scheduling_selection := fbs_scheduled_fcs_power - all_fcs]
s1 <- readRDS(file.path(C2R, "output/c2r/stage1/eval_set.rds")); imp <- s1[, .(stage1_implied_level_all_games = mean(u)), by = season]
cmp <- merge(cmp, imp, by = "season", all.x = TRUE)
cat("\n== composition: panel of", length(panel), "FCS teams present every season; entrants/leavers; FBS scheduling ==\n"); print(cmp, digits = 3)
fwrite(cmp, file.path(OUT, "s3_level_composition.csv"))

# ---- anchors: FCS level and lower-vs-FCS gap, from seasons before the target only (2020 excluded)
an <- rbindlist(lapply(c2r_S, function(y) { pre <- h[season < y]; r3 <- tail(pre[order(season)], 3); la <- tail(pre[order(season)], 1); fx <- h[season <= 2016]
  data.table(season = y, anchor = c("fixed", "expanding", "rolling3", "last"), fcs = c(mean(fx$fcs), mean(pre$fcs), mean(r3$fcs), la$fcs),
             gap = c(mean(fx$gap), mean(pre$gap), mean(r3$gap), la$gap)) }))
cat("\n== anchors (FCS-division level; lower-vs-FCS gap) ==\n"); print(dcast(an, season ~ anchor, value.var = c("fcs", "gap")), digits = 3)
fwrite(an, file.path(OUT, "s3_anchors.csv")); saveRDS(list(levels = lv, teams = tm, anchors = an, trend = tr, composition = cmp), file.path(out, "level_history.rds"))
