# Round 15 step 05: reproduce the incumbent (v5 EB_features) walk-forward replay for 2017-2022 with history from 2013,
# exactly as Round 6 built it, and decide whether 2017 can join the development window.
#
# Reproduction target: Round 6 `development_predictions.csv`, candidate v5_EB_features (the Round 13/14 dev incumbent is
# its 2018-2022 portion). Method (Round 6, cfb_power_ratings_v7.R): the frozen estimator's functions are re-bound to a
# config whose history is 2013:2022, and v5_prior()'s hard-coded prior-training start `season > 2015` becomes
# `season > min(history)`. At ratio = Inf Round 6's evaluator is the engine's own v4_score_fit path, so the engine's
# v5_evaluate() is used here.
#
# No outcome metric is computed: only predicted margins are compared, and fold information rules are audited.
# Usage (repo root): Rscript scripts/round15/05_replay_incumbent_2017.R
source("config/paths.R"); source("config/legacy_paths.R")
root <- PATHS$root
suppressPackageStartupMessages({ source(PATHS$model_engine); library(data.table) })
out_doc <- file.path(root, "docs/round15/replay"); dir.create(out_doc, recursive = TRUE, showWarnings = FALSE)
run <- file.path(root, "output/dev/round15/replay"); dir.create(file.path(run, "outputs/round6"), recursive = TRUE, showWarnings = FALSE)
lnk <- function(to, from) if (!file.exists(from)) file.symlink(to, from)
lnk(file.path(PATHS$frozen, "cfb_data_v3"), file.path(run, "cfb_data_v3"))
lnk(file.path(LEGACY_ROOTS[["backup"]], "CFB-Modeling-round6/outputs/round6/raw"), file.path(run, "outputs/round6/raw"))
r6_pred <- file.path(LEGACY_ROOTS[["old"]], "CFB-Modeling-round6/outputs/round6/development_predictions.csv")
r13_pred <- path.expand("~/Desktop/Revised CFB Modeling/.claude/worktrees/round13-pbp-stack/output/dev/round13/predictions_dev.csv")
setwd(run)

HISTORY <- 2013:2022; COMPONENTS <- c(2016L, 2017L, 2018L, 2019L, 2021L, 2022L); FOLDS <- c(2017L, 2018L, 2019L, 2021L, 2022L)

# ---- Round 6 re-binding (ported verbatim in logic from cfb_power_ratings_v7.R) ----
r15_patch_fn <- function(f, pattern, replacement, env) {
  src <- paste(deparse(f, width.cutoff = 500L), collapse = "\n")
  hits <- gregexpr(pattern, src, perl = TRUE)[[1]]
  assert(length(hits) == 1L && hits[1] > 0, paste("Expected exactly one occurrence of", pattern))
  g <- eval(parse(text = sub(pattern, replacement, src, perl = TRUE)), envir = env); environment(g) <- env; g
}
e <- new.env(parent = globalenv())
e$v4_config <- function() cfb_config(cache_dir = "outputs/round3/cache", source_cache = "cfb_data_v3", history_seasons = HISTORY, version = "7.0.0")
e$v4_pre <- local({ f <- v4_pre; environment(f) <- e; f })
e$v5_prior <- r15_patch_fn(v5_prior, "season\\s*>\\s*2015", "season > min(v4_config()$history_seasons)", e)
e$v4_components <- local({ f <- v4_components; environment(f) <- e; f })
e$v5_components <- local({ f <- v5_components; environment(f) <- e; f })

sched <- function(s) { if (s >= 2015) return(v4_schedule(s))
  cfg <- v4_config(); cfg$cache_dir <- "outputs/round6/raw"; cfg$source_cache <- "outputs/round6/raw"; read_schedule(s, cfg, FALSE) }
sch <- setNames(lapply(HISTORY, sched), HISTORY)
history <- v4_history(sch)
bundle <- readRDS(file.path(PATHS$frozen, "outputs/round4/features.rds"))
assert(unname(tools::md5sum(file.path(PATHS$frozen, "outputs/round4/features.rds"))) == "f18013897d21334c74af3550b77842fe", "features.rds hash")
feat <- v5_validate_features(bundle$features, setNames(lapply(2015:2026, v4_schedule), 2015:2026))
spec <- v5_candidates()$EB_features

base <- e$v4_components(sch, history, COMPONENTS)
inc <- e$v5_components(base, history, feat, "full")
pars <- setNames(lapply(FOLDS, function(s) v5_fit_parameters(inc, base, spec, s)), FOLDS)
pred <- rbindlist(lapply(FOLDS, function(s) as.data.table(v5_evaluate(v4_subset(inc, s), spec, pars[[as.character(s)]], history, sch)$predictions)))
pred <- pred[, .(season, game_id = as.character(game_id), cutoff = format(cutoff, "%Y-%m-%d"), kickoff, neutral, home_id, away_id,
                 home_conference, away_conference, gp_home, gp_away, pre_home, pre_away, hfa, pred_margin, actual_margin)]

# ---- Reproduction checks (predicted margins only) ----
r6 <- fread(r6_pred, colClasses = list(character = c("game_id")))[candidate == "v5_EB_features"]
m <- merge(pred[, .(season, game_id, p = pred_margin)], r6[, .(season, game_id, p6 = pred_margin)], by = c("season", "game_id"), all = TRUE)
repro <- m[, .(games_replay = sum(!is.na(p)), games_round6 = sum(!is.na(p6)), unmatched = sum(is.na(p) | is.na(p6)),
               max_abs_diff = max(abs(p - p6), na.rm = TRUE)), by = season][order(season)]
r13 <- fread(r13_pred, colClasses = list(character = c("game_id")))
m13 <- merge(pred[, .(game_id, p = pred_margin)], r13[, .(game_id, p13 = incumbent_margin)], by = "game_id")
repro13 <- data.table(check = "replay vs Round 13 dev incumbent_margin (2018-2022)", games = nrow(m13), r13_rows = nrow(r13),
                      max_abs_diff = max(abs(m13$p - m13$p13)))

# ---- Information-rule audit per fold (what each fold was allowed to see) ----
audit <- rbindlist(lapply(FOLDS, function(s) {
  p <- pars[[as.character(s)]]; pf <- inc$prior_fits[[as.character(s)]]; rt <- as.data.table(pf$routes)
  snaps <- Filter(function(z) z$season == s, inc$snap)
  data.table(fold = s, prior_train_seasons = paste(range(setdiff((min(HISTORY) + 1):(s - 1), 2020)), collapse = "-"),
             prior_max_train_season = pf$max_train, feature_regimes = if (nrow(rt)) uniqueN(rt[, paste(side, regime)]) else 0L,
             feature_regime_min_rows = if (nrow(rt)) min(rt$n_train) else NA_integer_,
             feature_regime_lambdas = if (nrow(rt)) paste(sort(unique(rt$lambda)), collapse = "/") else "",
             teams_on_base_prior_off = sum(!pf$r$team_id %in% rt[side == "off", team_id]),
             teams_on_base_prior_def = sum(!pf$r$team_id %in% rt[side == "def", team_id]),
             calibration_seasons = paste(sort(unique(inc$frame$season[inc$frame$season < s & inc$frame$season != 2020])), collapse = ","),
             calibration_games = sum(inc$frame$season < s & inc$frame$season != 2020),
             prior_scale = p$scale$scale, hfa = p$scale$hfa, calibration_max_season = p$max_train,
             weekly_snapshots = length(snaps), max_training_game_available_before_cutoff = all(vapply(snaps, function(z) all(z$tg$available_at < z$cutoff), TRUE)))
}))
spread <- pred[, .(games = .N, sd_pred_margin = sd(pred_margin), sd_pre_power_diff = sd(pre_home - pre_away), median_gp = median(pmin(gp_home, gp_away))), by = season]

fwrite(repro, file.path(out_doc, "replay_reproduction_by_season.csv")); fwrite(repro13, file.path(out_doc, "replay_vs_round13_incumbent.csv"))
fwrite(audit, file.path(out_doc, "replay_fold_information_audit.csv")); fwrite(spread, file.path(out_doc, "replay_prediction_spread_no_outcomes.csv"))
f_out <- file.path(root, "output/dev/round15/incumbent_replay_2017_2022.csv"); fwrite(pred, f_out)
fwrite(data.table(file = "output/dev/round15/incumbent_replay_2017_2022.csv", md5 = unname(tools::md5sum(f_out)), rows = nrow(pred),
                  engine_md5 = unname(tools::md5sum(PATHS$model_engine)), created_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")),
       file.path(out_doc, "replay_manifest.csv"))
print(repro); print(repro13); print(audit, width = 250); print(spread)
