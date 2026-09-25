# Round 15 construction: Candidate 2. G0a(C2 reduces to C1), nuisance parameters as-of each season, omega selection (§6.1)
# and frozen predictions. NO development or conditional metric is computed or printed.
source("config/paths.R"); source("config/production.R")
suppressPackageStartupMessages({ source(PATHS$model_ops); library(data.table); for (f in c("data", "c1", "c2", "tune")) source(sprintf("R/round15/candidates/%s.R", f)) })
out <- R15C$cache; d <- r15_build_data(); c1 <- readRDS(file.path(out, "c1_components.rds"))
Z <- c(2016L, 2017L, 2018L, 2019L, 2021L, 2022L)
eos_full <- setNames(lapply(2013:2025, function(s) r15_eos_full(d, s)), 2013:2025)
p2 <- setNames(lapply(c(Z, 2023L), function(z) r15_c2_params(d, z, eos_full)), c(Z, 2023L))
vb <- function(z) { v <- c1$varm[[as.character(z)]]; list(off = v$off$vbar, def = v$def$vbar) }
lam_of <- function(z, key = z) r15_c1_lambda(c1$priors[[as.character(z)]], c1$varm[[as.character(key)]], c1$lam0[[as.character(if (key >= 2023) 2022 else key)]])

# ---- G0a(C2): omega = 0, no FCS teams, no fumble luck => identical to C1's frozen predictions
c1p <- fread(file.path(out, "c1_predictions.csv"), colClasses = list(character = "game_id"))
g0 <- rbindlist(lapply(R15C$dev, function(y) {
  p <- r15_predict_season_c2(d, y, c1$priors[[as.character(y)]], c1$scl[[as.character(y)]], lam_of(y), r15_H(d, y), p2[[as.character(y)]], vb(y), c1$lam0[[as.character(y)]], eos_full, 0, use_fcs = FALSE, use_luck = FALSE)
  m <- merge(p, c1p[, .(game_id, ref = pred_margin)], by = "game_id")
  data.table(season = y, games = nrow(m), c1_games = c1p[season == y, .N], max_abs_diff = max(abs(m$pred_margin - m$ref))) }))
g0[, pass := games == c1_games & max_abs_diff <= 1e-9]; fwrite(g0, "docs/round15/construction/g0a_c2_vs_c1.csv"); print(g0); stopifnot(all(g0$pass))

# ---- omega selection: inner predictions for every (season, omega), everything else as-of that season
grid <- c(0, 0.25, 0.5, 1, 2)
inner <- rbindlist(lapply(Z, function(z) rbindlist(lapply(grid, function(v) {
  om <- if (isTRUE(p2[[as.character(z)]]$beta_ok)) v else 0
  r15_predict_season_c2(d, z, c1$priors[[as.character(z)]], c1$scl[[as.character(z)]], lam_of(z), r15_H(d, z), p2[[as.character(z)]], vb(z), c1$lam0[[as.character(z)]], eos_full, om)[, grid_value := v] }))))
sel <- r15_select(inner, d, grid, nesting = 0, targets = R15C$dev)
sel[, selected := mapply(function(t, s) if (isTRUE(p2[[as.character(t)]]$beta_ok)) s else 0, target, selected)]
saveRDS(list(inner = inner, sel = sel), file.path(out, "c2_tuning.rds"))
om <- setNames(c(0, sel$selected), c("2016", sel$target))

# ---- frozen C2 predictions: development folds and 2023-2025 (parameters through 2022)
pred <- rbindlist(c(
  lapply(R15C$dev, function(y) r15_predict_season_c2(d, y, c1$priors[[as.character(y)]], c1$scl[[as.character(y)]], lam_of(y), r15_H(d, y), p2[[as.character(y)]], vb(y), c1$lam0[[as.character(y)]], eos_full, om[[as.character(y)]])),
  lapply(2023:2025, function(y) r15_predict_season_c2(d, y, c1$priors[[as.character(y)]], c1$scl[["2023"]], lam_of(y, 2023L), R15C$frozen_hfa, p2[["2023"]], vb(2023), c1$lam0[["2022"]], eos_full, om[["2022"]]))))
pred[, candidate := "C2"]; fwrite(pred, file.path(out, "c2_predictions.csv"))
saveRDS(list(p2 = p2, om = om, eos_full = eos_full), file.path(out, "c2_components.rds"))
params <- rbindlist(lapply(names(p2), function(z) with(p2[[z]], data.table(season = as.integer(z), beta = beta, beta_ok = beta_ok, beta_rows = beta_rows, kappa_fum = kappa,
  mu_fcs_off = mu[["off"]], mu_fcs_def = mu[["def"]], rho_off = rho[["off"]], rho_def = rho[["def"]], v_fcs_off = v_fcs[["off"]], v_fcs_def = v_fcs[["def"]],
  omega = if (as.integer(z) >= 2023) om[["2022"]] else om[[z]]))))
fwrite(params, "docs/round15/construction/c2_parameters.csv"); fwrite(sel[, .(target, selected, grid_edge, fallback)], "docs/round15/construction/c2_omega_selection.csv")
fwrite(data.table(file = file.path(out, c("c2_predictions.csv", "c2_tuning.rds")), sha256 = sapply(file.path(out, c("c2_predictions.csv", "c2_tuning.rds")), function(f) digest::digest(file = f, algo = "sha256"))),
       "docs/round15/construction/c2_manifest.csv")
print(params, digits = 4); print(sel[, .(target, selected, grid_edge, fallback)]); cat("C2 predictions:", nrow(pred), "rows (not scored)\n")
