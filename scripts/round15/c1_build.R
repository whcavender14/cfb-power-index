# Round 15 construction: Candidate 1. G0a reproduction of the incumbent through C1's code path; then priors, variance
# models, scales, lambda0 selection (§6.1) and frozen predictions. NO development or conditional metric is computed here;
# inner-tuning objective values are written to a hashed file and not printed.
source("config/paths.R"); source("config/production.R")
suppressPackageStartupMessages({ source(PATHS$model_ops); library(data.table); source("R/round15/candidates/data.R"); source("R/round15/candidates/c1.R"); source("R/round15/candidates/tune.R") })
out <- R15C$cache; d <- r15_build_data(); e <- r15_bind_incumbent()

# ---- G0a(C1): with the incumbent's prior, lambda = 4 and the incumbent's fold scale and HFA, C1's path reproduces the replay
rep <- fread("output/dev/round15/incumbent_replay_2017_2022.csv", colClasses = list(character = "game_id"))
g0 <- rbindlist(lapply(R15C$dev, function(y) {
  pf <- d$inc$prior_fits[[as.character(y)]]; stopifnot(length(pf$fits) > 0)
  pr <- as.data.table(pf$r)[, .(team_id, pre_off, pre_def)]
  lam <- list(off = rep(4, nrow(pr)), def = rep(4, nrow(pr))); par <- d$pars[[as.character(y)]]
  p <- r15_predict_season_c1(d, y, pr, par$scale$scale, lam, par$scale$hfa)
  m <- merge(p, rep[, .(game_id, ref = pred_margin)], by = "game_id")
  data.table(season = y, games = nrow(m), replay_games = rep[season == y, .N], max_abs_diff = max(abs(m$pred_margin - m$ref)))
}))
g0[, pass := games == replay_games & max_abs_diff <= 1e-9]
fwrite(g0, "docs/round15/construction/g0a_c1_vs_incumbent.csv"); print(g0)
stopifnot(all(g0$pass))

# ---- C1 components, each as-of its own season (§6.1 item 2)
Z <- c(2016L, 2017L, 2018L, 2019L, 2021L, 2022L)
priors <- list()
for (z in c(Z, 2023L)) priors[[as.character(z)]] <- r15_c1_prior(d, z, min(z - 1L, 2022L), e)
for (z in 2024:2025) priors[[as.character(z)]] <- r15_c1_prior(d, z, 2022L, e)
varm <- list(); for (z in c(Z[-1], 2023L)) varm[[as.character(z)]] <- r15_c1_variance(d, z, priors)
varm[["2016"]] <- list(off = list(b = 0, train_means = c(a = NA, b = NA, c = NA, d = NA), vbar = NA), def = list(b = 0, train_means = c(a = NA, c = NA, d = NA), vbar = NA))  # no residual seasons before 2016: nesting value
scl <- sapply(c(Z, 2023L), function(z) r15_scale(d, z, priors, if (z >= 2023) R15C$frozen_hfa else r15_H(d, z))); names(scl) <- c(Z, 2023L)

# ---- inner predictions for every (season, lambda0) and the lambda0 selection per target
grid <- c(2, 3, 4, 6, 8, 12)
inner <- rbindlist(lapply(Z, function(z) rbindlist(lapply(grid, function(v) {
  lam <- r15_c1_lambda(priors[[as.character(z)]], varm[[as.character(z)]], v)
  r15_predict_season_c1(d, z, priors[[as.character(z)]], scl[[as.character(z)]], lam, r15_H(d, z))[, grid_value := v] }))))
sel <- r15_select(inner, d, grid, nesting = 4, targets = c(2017L, 2018L, 2019L, 2021L, 2022L))
saveRDS(list(inner = inner, sel = sel), file.path(out, "c1_tuning.rds"))
lam0 <- setNames(c(4, sel$selected), c("2016", sel$target))

# ---- frozen C1 predictions: development folds and 2023-2025 (parameters through 2022; H frozen)
pred <- rbindlist(c(
  lapply(R15C$dev, function(y) { lam <- r15_c1_lambda(priors[[as.character(y)]], varm[[as.character(y)]], lam0[[as.character(y)]])
    r15_predict_season_c1(d, y, priors[[as.character(y)]], scl[[as.character(y)]], lam, r15_H(d, y)) }),
  lapply(2023:2025, function(y) { lam <- r15_c1_lambda(priors[[as.character(y)]], varm[["2023"]], lam0[["2022"]])
    r15_predict_season_c1(d, y, priors[[as.character(y)]], scl[["2023"]], lam, R15C$frozen_hfa) })))
pred[, candidate := "C1"]
saveRDS(list(priors = priors, varm = varm, scl = scl, lam0 = lam0), file.path(out, "c1_components.rds"))
fwrite(pred, file.path(out, "c1_predictions.csv"))
params <- data.table(season = c(Z, 2023L), scale = scl, b_off = sapply(varm[as.character(c(Z, 2023L))], function(v) v$off$b),
                     b_def = sapply(varm[as.character(c(Z, 2023L))], function(v) v$def$b), lambda0 = c(lam0[as.character(Z)], lam0[["2022"]]), H = sapply(c(Z, 2023L), function(z) r15_H(d, z)))
fwrite(params, "docs/round15/construction/c1_parameters.csv"); fwrite(sel[, .(target, selected, grid_edge, fallback)], "docs/round15/construction/c1_lambda0_selection.csv")
routes <- rbindlist(lapply(names(priors), function(z) priors[[z]][, .(season = as.integer(z), route_off, route_def)]))
fwrite(routes[, .(n = .N), by = .(season, off_regime = route_off != "base", def_regime = route_def != "base")], "docs/round15/construction/c1_prior_routes.csv")
fwrite(data.table(file = c(file.path(out, "c1_predictions.csv"), file.path(out, "c1_tuning.rds")),
                  sha256 = c(digest::digest(file = file.path(out, "c1_predictions.csv"), algo = "sha256"), digest::digest(file = file.path(out, "c1_tuning.rds"), algo = "sha256"))),
       "docs/round15/construction/c1_manifest.csv")
print(params); print(sel[, .(target, selected, grid_edge, fallback)]); cat("C1 predictions:", nrow(pred), "rows (not scored)\n")
