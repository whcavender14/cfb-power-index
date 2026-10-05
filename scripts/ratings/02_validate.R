# Runs the predeclared validation (docs/website/PLAYER_RATINGS_PREDECLARATION.md). Usage: Rscript 02_validate.R dev|holdout
suppressMessages(library(jsonlite)); source("config/paths.R"); source("R/ratings/ratings_spec.R"); source("R/ratings/ratings_core.R"); source("R/ratings/ratings_eval.R")
mode <- commandArgs(TRUE)[1]; stopifnot(mode %in% c("dev", "holdout"))
fbs <- fromJSON("public/data/v2/teams.json")$teams$team
knots <- readRDS("R/ratings/ratings_knots.rds")
pairs <- if (mode == "dev") RS$gate$dev_pairs else RS$gate$holdout_pairs
dseasons <- if (mode == "dev") RS$gate$draft_dev else RS$gate$draft_holdout
need <- sort(unique(c(vapply(pairs, `[`, 0L, 1L), dseasons, 2025L)))
rb <- setNames(lapply(need, function(s) { p <- build_ratings(s, fbs); p[, ovr := to_ovr(mu, knots)]; p }), need)
B <- RS$gate$boot; seed <- RS$gate$seed
# ---- production
pt <- production_table(pairs, rb, fbs)
cat(sprintf("\n== %s production: %d player-pairs (%s)\n", mode, nrow(pt), paste(vapply(pairs, paste, "", collapse = "->"), collapse = ", ")))
print(pt[, .(n = .N), by = group][order(-n)])
ci <- boot_ci(pt, delta_corr, B, seed)
res <- data.frame(stat = names(ci$est), delta_corr = round(ci$est, 4), lo = round(ci$lo, 4), hi = round(ci$hi, 4))
cors <- pt[, .(rating_corr = round(cor(mu_t, y_t), 3), recruiting_corr = round(cor(prior_t, y_t), 3), n = .N), by = group]
print(res, row.names = FALSE); print(cors[order(-n)])
cat(sprintf("pooled corr: rating %.3f, recruiting %.3f\n", cor(pt$mu_t, pt$y_t), cor(pt$prior_t, pt$y_t)))
# ---- draft
dt <- draft_table(dseasons, rb)
cat(sprintf("\n== %s draft: %d JR/SR player-seasons, %d drafted\n", mode, nrow(dt), sum(dt$drafted)))
dci <- boot_ci(dt, delta_auc, B, seed + 1L)
print(data.frame(stat = names(dci$est), est = round(dci$est, 4), lo = round(dci$lo, 4), hi = round(dci$hi, 4)), row.names = FALSE)
print(dt[, .(n = .N, drafted = sum(drafted)), by = group][order(-drafted)])
# ---- distribution (rating through 2025 on the 2025 roster) and positional check
dist <- distribution_report(rb[["2025"]])
cat("\n== distribution, rating through 2025, 2025 FBS rosters\n"); print(dist[c("n", "mean", "median", "sd", "min", "max")]); print(round(dist$pct, 1)); print(dist$at); print(dist$bands)
cat("target bands: 95-99 1.2, 90-94 2.6, 85-89 5.4, 80-84 11.1, 75-79 15.9, 70-74 21.7, 65-69 21.5, 60-64 17.5, <60 3.1\n")
print(dist$by_group); cat("Provisional:", dist$provisional, " Estimated:", dist$estimated, "\n")
ev <- dist$evidence_means; pm <- rb[["2025"]][r >= 0.5 & !estimated, mean(ovr)]
ev[, diff := round(mean - pm, 1)]; cat(sprintf("\nevidence-based players (r >= 0.5, non-Estimated): pooled mean %.1f\n", pm)); print(ev)
# ---- gates
g1 <- ci$est["pooled"] >= RS$gate$min_delta_corr && ci$lo["pooled"] > 0
g2 <- sum(ci$est[names(RS$gate$y_min)] > 0, na.rm = TRUE) >= RS$gate$min_groups_positive
g3 <- dci$est["delta"] >= RS$gate$min_delta_auc && dci$lo["delta"] > 0
g4 <- all(abs(ev$diff) <= RS$gate$group_tol_points)
cat(sprintf("\nGATES (%s): G1 %s | G2 %s | G3 %s | G4 %s\n", mode, g1, g2, g3, g4))
saveRDS(list(mode = mode, production = res, cors = cors, draft = data.frame(stat = names(dci$est), est = dci$est, lo = dci$lo, hi = dci$hi), dist = dist, evidence = ev, gates = c(G1 = g1, G2 = g2, G3 = g3, G4 = g4)),
        file.path("output", sprintf("ratings_validation_%s.rds", mode)))
