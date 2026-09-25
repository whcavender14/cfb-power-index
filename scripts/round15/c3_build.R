# Round 15 construction: Candidate 3. G0a(C3 with q = q_QB = 0 reduces to C2), sigma2_row as-of each season, q then q_QB
# selection (§6.1, as-of-date), frozen predictions. NO development or conditional metric is computed or printed.
source("config/paths.R"); source("config/production.R")
suppressPackageStartupMessages({ source(PATHS$model_ops); library(data.table); for (f in c("data", "c1", "c2", "c3", "tune")) source(sprintf("R/round15/candidates/%s.R", f)) })
out <- R15C$cache; d <- r15_build_data(); d$qb <- r15_qb_primary(); c1 <- readRDS(file.path(out, "c1_components.rds")); c2 <- readRDS(file.path(out, "c2_components.rds"))
Z <- c(2016L, 2017L, 2018L, 2019L, 2021L, 2022L)
s2 <- sapply(c(Z, 2023L), function(z) r15_sigma2_row(d, z)); names(s2) <- c(Z, 2023L)
vb <- function(z) { v <- c1$varm[[as.character(z)]]; list(off = v$off$vbar, def = v$def$vbar) }
lam_of <- function(z, key = z) r15_c1_lambda(c1$priors[[as.character(z)]], c1$varm[[as.character(key)]], c1$lam0[[as.character(if (key >= 2023) 2022 else key)]])
run <- function(z, q, qqb, key = z) { kk <- as.character(key); l0 <- c1$lam0[[as.character(if (key >= 2023) 2022 else key)]]
  om <- c2$om[[as.character(if (key >= 2023) 2022 else key)]]
  r15_predict_season_c3(d, z, c1$priors[[as.character(z)]], c1$scl[[kk]], lam_of(z, key), if (key >= 2023) R15C$frozen_hfa else r15_H(d, z),
                        c2$p2[[kk]], vb(key), l0, c2$eos_full, om, q, qqb, s2[[kk]]) }

# ---- G0a(C3): q = q_QB = 0 => identical to C2's frozen predictions (tolerance 1e-6)
c2p <- fread(file.path(out, "c2_predictions.csv"), colClasses = list(character = "game_id"))
g0 <- rbindlist(lapply(R15C$dev, function(y) { p <- run(y, 0, 0); m <- merge(p, c2p[, .(game_id, ref = pred_margin)], by = "game_id")
  data.table(season = y, games = nrow(m), c2_games = c2p[season == y, .N], max_abs_diff = max(abs(m$pred_margin - m$ref))) }))
g0[, pass := games == c2_games & max_abs_diff <= 1e-6]; fwrite(g0, "docs/round15/construction/g0a_c3_vs_c2.csv"); print(g0); stopifnot(all(g0$pass))

# ---- q selection (q_QB = 0), then q_QB given each season's own selected q (§6.1 item 2)
gq <- c(0, 0.25, 0.5, 1, 2); gqb <- c(0, 4, 16, 36)
inner_q <- rbindlist(lapply(Z, function(z) rbindlist(lapply(gq, function(v) run(z, v, 0)[, grid_value := v]))))
sel_q <- r15_select(inner_q, d, gq, nesting = 0, targets = R15C$dev); qz <- setNames(c(0, sel_q$selected), c("2016", sel_q$target))
qb_ok <- fread("docs/round15/prep/p3_verdict.csv")$pass
inner_qb <- rbindlist(lapply(Z, function(z) rbindlist(lapply(gqb, function(v) run(z, qz[[as.character(z)]], if (qb_ok) v else 0)[, grid_value := v]))))
sel_qb <- r15_select(inner_qb, d, gqb, nesting = 0, targets = R15C$dev); if (!qb_ok) sel_qb[, selected := 0]
qbz <- setNames(c(0, sel_qb$selected), c("2016", sel_qb$target))
saveRDS(list(inner_q = inner_q, sel_q = sel_q, inner_qb = inner_qb, sel_qb = sel_qb), file.path(out, "c3_tuning.rds"))

# ---- frozen C3 predictions: development folds and 2023-2025 (parameters through 2022)
pred <- rbindlist(c(lapply(R15C$dev, function(y) run(y, qz[[as.character(y)]], qbz[[as.character(y)]])),
                    lapply(2023:2025, function(y) run(y, qz[["2022"]], qbz[["2022"]], key = 2023L))))
pred[, candidate := "C3"]; fwrite(pred, file.path(out, "c3_predictions.csv"))
params <- data.table(season = c(Z, 2023L), sigma2_row = s2, q = c(qz[as.character(Z)], qz[["2022"]]), q_qb = c(qbz[as.character(Z)], qbz[["2022"]]))
fwrite(params, "docs/round15/construction/c3_parameters.csv")
fwrite(rbind(sel_q[, .(parameter = "q", target, selected, grid_edge, fallback)], sel_qb[, .(parameter = "q_QB", target, selected, grid_edge, fallback)]), "docs/round15/construction/c3_selection.csv")
fwrite(data.table(file = file.path(out, c("c3_predictions.csv", "c3_tuning.rds")), sha256 = sapply(file.path(out, c("c3_predictions.csv", "c3_tuning.rds")), function(f) digest::digest(file = f, algo = "sha256"))),
       "docs/round15/construction/c3_manifest.csv")
qbn <- rbindlist(lapply(c(Z, R15C$dev, 2023:2025)[!duplicated(c(Z, R15C$dev, 2023:2025))], function(y) data.table(season = y, qb_change_events = nrow(r15_qb_events(d, y)))))
fwrite(qbn, "docs/round15/construction/c3_qb_events_by_season.csv"); print(qbn)
print(params); print(rbind(sel_q[, .(parameter = "q", target, selected, grid_edge)], sel_qb[, .(parameter = "q_QB", target, selected, grid_edge)])); cat("C3 predictions:", nrow(pred), "rows (not scored)\n")
