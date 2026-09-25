# Round 15 formal scoring run (predeclaration v3 §7 metrics, §8 gates, advancement and verdict). RUN ONCE.
# Smoke mode (R15_SMOKE=1, R15_SMOKE_DIR=<dir>): every actual result is replaced by a synthetic draw, so the code can be
# exercised without reading any outcome; nothing is written to the results directory.
# Real run: refuses to start if docs/round15/eval/results already exists.
suppressPackageStartupMessages({ source("config/paths.R"); source("config/production.R"); source(PATHS$model_ops); library(data.table)
  source("R/evaluation/evaluation_helpers.R"); source("R/round15/candidates/data.R") })
SMOKE <- Sys.getenv("R15_SMOKE") == "1"
OUT <- if (SMOKE) Sys.getenv("R15_SMOKE_DIR") else "docs/round15/eval/results"
if (!SMOKE && dir.exists(OUT)) stop("results already exist: the formal scoring run is run once")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
w <- function(x, f) fwrite(x, file.path(OUT, f))
sha <- function(f) digest::digest(file = f, algo = "sha256")
R13 <- "/Users/willcavender/Desktop/Revised CFB Modeling/.claude/worktrees/round13-pbp-stack"
MODELS <- c("I", "K", "C1", "C2", "C3"); CANDS <- c("C1", "C2", "C3"); NREP <- 4000L; SEED <- 15015L

# ======================= 0. provenance: everything the run uses is the frozen state =======================================
prov <- list(); pv <- function(item, ok, detail) { prov[[length(prov) + 1L]] <<- data.table(item = item, ok = isTRUE(ok), detail = detail); if (!isTRUE(ok)) stop("provenance failed: ", item, " ", detail) }
hl <- function(f) { x <- readLines(f); x <- x[!grepl("^#", x) & nzchar(x)]; data.table(h = sub("  .*$", "", x), f = sub("^[0-9a-f]+  ", "", x)) }
pd <- hl("docs/round15/predeclaration.sha256")
pv("predeclaration hashes (original signed, v2, Amendment 01, v3, Amendment 02)", all(mapply(function(h, f) sha(file.path("docs/round15", f)) == h, pd$h, pd$f)),
   paste(sprintf("%s=%s", pd$f, substr(pd$h, 1, 12)), collapse = "; "))
pv("binding text is v3", "ROUND15_PREDECLARATION_v3.md" %in% pd$f, pd[f == "ROUND15_PREDECLARATION_v3.md", h])
fz <- hl("docs/round15/construction/CONSTRUCTION_FREEZE_A02.sha256")
pv("construction freeze CONSTRUCTION_FREEZE_A02 (code, tests, manifests, frozen predictions)", all(mapply(function(h, f) sha(f) == h, fz$h, fz$f)),
   sprintf("%d files; record sha256=%s", nrow(fz), sha("docs/round15/construction/CONSTRUCTION_FREEZE_A02.sha256")))
pv("freeze record hash equals the one recorded in predeclaration.sha256", any(grepl(sha("docs/round15/construction/CONSTRUCTION_FREEZE_A02.sha256"), readLines("docs/round15/predeclaration.sha256"))), "")
git <- function(...) system2("git", c(...), stdout = TRUE, stderr = TRUE)
tagc <- git("rev-list", "-n", "1", "round15-construction-final"); head_c <- git("rev-parse", "HEAD")
pv("tag round15-construction-final is commit fe345ed and an ancestor of HEAD", startsWith(tagc, "fe345ed") && system("git merge-base --is-ancestor round15-construction-final HEAD") == 0,
   sprintf("tag=%s HEAD=%s", substr(tagc, 1, 12), substr(head_c, 1, 12)))
cc <- git("diff", "--name-only", "round15-construction-final", "HEAD", "--", "R/round15/candidates", "scripts/round15/c0_build_data.R", "scripts/round15/c1_build.R", "scripts/round15/c2_build.R", "scripts/round15/c3_build.R")
pv("no candidate or build code changed since the construction tag", length(cc) == 0, paste(cc, collapse = ","))
for (k in 1:3) { m <- fread(sprintf("docs/round15/construction/c%d_manifest.csv", k))
  pv(sprintf("C%d frozen prediction manifest", k), all(mapply(function(f, h) sha(f) == h, m$file, m$sha256)), paste(substr(m$sha256, 1, 12), collapse = ",")) }
pv("C3 built under Amendment 02 (qb_primary.rds in the freeze; A02 detector in code)", any(grepl("qb_primary.rds", fz$f)) && any(grepl("Amendment 02", readLines("R/round15/candidates/c3.R"))), "")
k13 <- fread(file.path(R13, "docs/round13/freeze_manifest.csv"))
pv("Round 13 K frozen predictions match the Round 13 freeze manifest", all(sapply(c("predictions_dev.csv", "predictions_cond.csv"), function(f) sha(file.path(R13, "output/dev/round13", f)) == k13[file == f, sha256])),
   paste(substr(k13$sha256[1:2], 1, 12), collapse = ","))
p5 <- fread("docs/round15/prep/p5_market_vintage_manifest.csv")
pv("market lines are the P5 fixed vintage (2026-09-25 pull)", sha("output/dev/round15/market_lines_2017_2025.csv") == p5[file == "output/dev/round15/market_lines_2017_2025.csv", sha256], substr(p5$sha256[1], 1, 12))
e0 <- fread("docs/round15/eval/e0_manifest.csv"); pv("ratings replay (E0) matches its manifest", sha(e0$file) == e0$sha256, substr(e0$sha256, 1, 12))
pv("E0 replay reproduced every frozen prediction", all(fread("docs/round15/eval/e0_replay_check.csv")$pass), "")
g0 <- c(sapply(c("g0a_c1_vs_incumbent", "g0a_c2_vs_c1", "g0a_c3_vs_c2"), function(f) all(fread(sprintf("docs/round15/construction/%s.csv", f))$pass)),
        g0bc = all(fread("docs/round15/construction/g0b_g0c_tests.csv")$pass), l3 = all(fread("docs/round15/eval/g0b_l3_check.csv")$pass))
pv("G0 (G0a nesting, G0b L1-L6 incl. L3, G0c manifests) all pass", all(g0), paste(names(g0), g0, collapse = ";"))
w(rbindlist(prov), "provenance.csv"); cat("provenance verified\n")

# ======================= 1. the scoring universe (identical game IDs for every model) =====================================
rd <- function(f) fread(f, colClasses = list(character = c("game_id", "cutoff")))
cols <- c("season", "game_id", "cutoff", "neutral", "home_id", "away_id", "home_conference", "away_conference", "gp_home", "gp_away", "hfa", "actual_margin", "pred_margin")
G <- rbind(rd("output/dev/round15/incumbent_replay_2017_2022.csv")[, ..cols][, split := "dev"], rd(PATHS$incumbent_cond)[, ..cols][, split := "cond"])
setnames(G, c("actual_margin", "pred_margin"), c("actual", "I")); G[, cutoff := substr(cutoff, 1, 10)]
for (k in 1:3) { p <- rd(sprintf("output/dev/round15/cand/c%d_predictions.csv", k))[, .(game_id, cc = substr(cutoff, 1, 10), v = pred_margin)]
  G <- merge(G, p, by = "game_id", all.x = TRUE); stopifnot(!anyNA(G$v), all(G$cc == G$cutoff)); setnames(G, "v", paste0("C", k)); G[, cc := NULL] }
kf <- rbind(rd(file.path(R13, "output/dev/round13/predictions_dev.csv")), rd(file.path(R13, "output/dev/round13/predictions_cond.csv")))[, .(game_id, K = pred_margin, ka = actual_margin, kc = substr(cutoff, 1, 10))]
G <- merge(G, kf, by = "game_id", all.x = TRUE)
stopifnot(G[split == "dev" & season >= 2018, !anyNA(K)], G[split == "cond", !anyNA(K)], G[split == "dev" & season == 2017, all(is.na(K))],
          G[!is.na(K), all(ka == actual & kc == cutoff)])
G[, c("ka", "kc") := NULL]
stopifnot(G[split == "dev", .N] == 3868, G[split == "cond", .N] == 2398, G[split == "dev" & !is.na(K), .N] == 3092, !anyDuplicated(G$game_id))
d <- r15_build_data()
cg <- rbindlist(lapply(2017:2025, function(y) as.data.table(d$sch[[as.character(y)]])[, .(game_id = as.character(game_id), conf_game = as.logical(conference_game))]))
G <- merge(G, cg, by = "game_id", all.x = TRUE); stopifnot(!anyNA(G$conf_game))
G[, `:=`(site = hfa * !as.logical(neutral), gp = pmin(gp_home, gp_away))]
G[, gpb := cut(gp, c(-Inf, 0, 1, 3, 6, Inf), labels = c("0", "1", "2-3", "4-6", "7+"))][, stage := ifelse(gp <= 3, "gp 0-3", "gp 4+")]
G[, `:=`(th = tier_of(home_conference, season), ta = tier_of(away_conference, season))]
G[, matchup := fifelse(th == "Other" | ta == "Other", "with independents", fifelse(th == "P4" & ta == "P4", "P4-P4", fifelse(th == "G5" & ta == "G5", "G5-G5", "P4-G5")))]
G[, s_p4 := p4_orientation(home_conference, away_conference, season)]
mk <- fread("output/dev/round15/market_lines_2017_2025.csv", colClasses = list(character = "game_id"))
G <- merge(G, mk[, .(game_id, mh = home_id, ma = away_id, open_home_spread, close_home_spread)], by = "game_id", all.x = TRUE)
flip <- G[!is.na(mh) & mh == away_id & ma == home_id, .N]; stopifnot(G[!is.na(mh), all((mh == home_id & ma == away_id) | (mh == away_id & ma == home_id))])
G[, sg := fifelse(!is.na(mh) & mh != home_id, -1, 1)][, `:=`(Mc = -sg * close_home_spread, Mo = -sg * open_home_spread)][, c("mh", "ma", "sg", "open_home_spread", "close_home_spread") := NULL]
cov <- G[, .(games = .N, close = sum(!is.na(Mc)), open = sum(!is.na(Mo))), by = split]; print(cov)
stopifnot(cov[split == "dev", close] == 3868, cov[split == "dev", open] == 1539, cov[split == "cond", close] == 2398, cov[split == "cond", open] == 2398)
if (SMOKE) { set.seed(1); G[, actual := round(I + rnorm(.N, 0, 15))][actual == 0, actual := 1] }
stopifnot(!any(G$actual == 0)); G[, win := as.numeric(actual > 0)]
setorder(G, split, season, cutoff, game_id)
w(data.table(item = c("home/away swapped vs market rows (sign flipped)", cov[, sprintf("%s: games %d, close %d, open %d", split, games, close, open)]), value = c(flip, rep(NA, 2))), "universe.csv")

# ======================= 2. probability scales sigma_X: one mechanical step, recorded and hashed first ====================
fit_sigma <- function(m, y) { f <- function(s) -sum(y * pnorm(m / s, log.p = TRUE) + (1 - y) * pnorm(-m / s, log.p = TRUE))
  o <- optimize(f, c(2, 80), tol = 1e-10); stopifnot(o$minimum > 2.01, o$minimum < 79.9); o$minimum }
DEV <- c(2017L, 2018L, 2019L, 2021L, 2022L)
sig <- rbindlist(lapply(c(MODELS, "Mc", "Mo"), function(x) { g <- G[split == "dev" & !is.na(get(x))]; ys <- sort(unique(g$season))
  rbind(rbindlist(lapply(ys, function(y) { t <- g[season != y]; data.table(model = x, split = "dev", season = y, sigma = fit_sigma(t[[x]], t$win), n_fit = nrow(t), fit_seasons = paste(unique(t$season), collapse = "+")) })),
        data.table(model = x, split = "cond", season = NA_integer_, sigma = fit_sigma(g[[x]], g$win), n_fit = nrow(g), fit_seasons = paste(ys, collapse = "+"))) }))
w(sig, "sigma.csv"); writeLines(sprintf("%s  sigma.csv", sha(file.path(OUT, "sigma.csv"))), file.path(OUT, "sigma.sha256"))
cat("sigma recorded and hashed before any loss is computed:", sha(file.path(OUT, "sigma.csv")), "\n")

# ======================= 3. per-game losses ================================================================================
sg_of <- function(x, sp, ss) { s <- sig[model == x & split == sp]; if (sp == "dev") s$sigma[match(ss, s$season)] else rep(s$sigma, length(ss)) }
clip <- function(p) pmin(pmax(p, 1e-6), 1 - 1e-6)
for (x in c(MODELS, "Mc", "Mo")) { m <- G[[x]]; s <- numeric(nrow(G)); for (sp in c("dev", "cond")) { i <- G$split == sp; s[i] <- sg_of(x, sp, G$season[i]) }
  p <- clip(pnorm(m / s)); set(G, j = paste0("p_", x), value = p); set(G, j = paste0("ll_", x), value = -(G$win * log(p) + (1 - G$win) * log(1 - p)))
  set(G, j = paste0("br_", x), value = (p - G$win)^2); set(G, j = paste0("ae_", x), value = abs(m - G$actual)); set(G, j = paste0("se_", x), value = (m - G$actual)^2)
  for (fs in c(14, 16, 18)) { q <- clip(pnorm(m / fs)); set(G, j = sprintf("llf%d_%s", fs, x), value = -(G$win * log(q) + (1 - G$win) * log(1 - q))) } }

# ======================= 4. flat season x week block bootstrap (4,000 resamples, seed 15015, blocks = cutoff text) ========
mkboot <- function(g) { key <- paste(g$season, g$cutoff); lev <- sort(unique(key)); B <- length(lev); set.seed(SEED)
  idx <- matrix(sample.int(B, NREP * B, replace = TRUE), nrow = NREP); C <- t(apply(idx, 1, tabulate, nbins = B)); list(b = match(key, lev), B = B, C = C) }
bs <- function(bo, v) { s <- numeric(bo$B); t <- tapply(v, bo$b, sum); s[as.integer(names(t))] <- t; s }
qs <- function(x, lv) unname(quantile(x, c((1 - lv) / 2, 1 - (1 - lv) / 2), na.rm = TRUE))
bmean <- function(bo, v, sel = TRUE) { sel <- rep_len(sel, length(v)) & !is.na(v); vv <- ifelse(sel, v, 0)
  dr <- as.numeric(bo$C %*% bs(bo, vv)) / as.numeric(bo$C %*% bs(bo, as.numeric(sel))); list(est = mean(v[sel]), draws = dr, n = sum(sel)) }
bdiff_rmse <- function(bo, a, b, sel = TRUE) { sel <- rep_len(sel, length(a)); n <- as.numeric(bo$C %*% bs(bo, as.numeric(sel)))
  dr <- sqrt(as.numeric(bo$C %*% bs(bo, ifelse(sel, a, 0))) / n) - sqrt(as.numeric(bo$C %*% bs(bo, ifelse(sel, b, 0))) / n); list(est = sqrt(mean(a[sel])) - sqrt(mean(b[sel])), draws = dr, n = sum(sel)) }
bols <- function(bo, x, y, sel = TRUE) { sel <- rep_len(sel, length(x)) & !is.na(x) & !is.na(y); z <- function(v) bs(bo, ifelse(sel, v, 0))
  S <- cbind(z(1), z(x), z(y), z(x * x), z(x * y)); A <- bo$C %*% S
  dr <- (A[, 5] - A[, 2] * A[, 3] / A[, 1]) / (A[, 4] - A[, 2]^2 / A[, 1]); f <- coef(lm(y[sel] ~ x[sel]))
  list(est = unname(f[2]), intercept = unname(f[1]), draws = dr, n = sum(sel)) }
bols2 <- function(bo, x1, x2, y, sel = TRUE) { sel <- rep_len(sel, length(y)) & !is.na(x1) & !is.na(x2); X <- cbind(1, x1, x2); z <- function(v) bs(bo, ifelse(sel, v, 0))
  P <- list(); for (i in 1:3) for (j in i:3) P[[paste(i, j)]] <- z(X[, i] * X[, j]); Q <- lapply(1:3, function(i) z(X[, i] * y))
  PA <- sapply(P, function(s) as.numeric(bo$C %*% s)); QA <- sapply(Q, function(s) as.numeric(bo$C %*% s))
  dr <- t(sapply(seq_len(NREP), function(r) { M <- matrix(0, 3, 3); k <- 0; for (i in 1:3) for (j in i:3) { k <- k + 1; M[i, j] <- M[j, i] <- PA[r, k] }; solve(M, QA[r, ]) }))
  f <- coef(lm(y[sel] ~ x1[sel] + x2[sel])); list(est = unname(f), draws = dr, n = sum(sel)) }
blogit <- function(bo, x, y, sel = TRUE) { sel <- rep_len(sel, length(x)) & !is.na(x) & !is.na(y); X <- cbind(1, x[sel]); yy <- y[sel]; bb <- bo$b[sel]
  est <- glm.fit(X, yy, family = binomial())$coefficients[2]
  dr <- vapply(seq_len(NREP), function(r) { ww <- bo$C[r, bb]; if (sum(ww) == 0) return(NA_real_); suppressWarnings(glm.fit(X, yy, weights = ww, family = binomial())$coefficients[2]) }, numeric(1))
  list(est = unname(est), draws = dr, n = sum(sel)) }
wilson <- function(k, n, z = qnorm(0.975)) { if (n == 0) return(c(NA, NA)); p <- k / n; c0 <- p + z^2 / (2 * n); h <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)); (c(c0 - h, c0 + h)) / (1 + z^2 / n) }
row_ci <- function(r, extra = list()) { ci95 <- qs(r$draws, 0.95); ci98 <- qs(r$draws, 1 - 0.05 / 3)
  as.data.table(c(list(estimate = r$est[1], lo95 = ci95[1], hi95 = ci95[2], lo9833 = ci98[1], hi9833 = ci98[2], se = sd(r$draws, na.rm = TRUE), n = r$n), extra)) }
Gd <- G[split == "dev"]; Gc <- G[split == "cond"]; GdK <- Gd[!is.na(K)]
BO <- list(dev = mkboot(Gd), devK = mkboot(GdK), cond = mkboot(Gc))
blk <- sapply(BO, `[[`, "B"); print(blk); stopifnot(blk[["dev"]] == 106, blk[["devK"]] == 85, blk[["cond"]] == 65)
U <- list(dev = Gd, devK = GdK, cond = Gc)

# ======================= 5. absolute metrics, deltas, slices ==============================================================
auc <- function(m, y) { r <- rank(m); n1 <- sum(y == 1); n0 <- sum(y == 0); (sum(r[y == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0) }
slope_of <- function(g, x, sel = TRUE) { sel <- rep_len(sel, nrow(g)); if (sum(sel) < 3) return(NA_real_); yv <- g$actual[sel] - g$site[sel]; xv <- g[[x]][sel] - g$site[sel]; unname(coef(lm(yv ~ xv))[2]) }
absm <- function(g, x) { m <- g[[x]]; nz <- m != 0
  data.table(n = nrow(g), logloss = mean(g[[paste0("ll_", x)]]), brier = mean(g[[paste0("br_", x)]]), mae = mean(g[[paste0("ae_", x)]]), rmse = sqrt(mean(g[[paste0("se_", x)]])),
             bias = mean(m - g$actual), winner_pct = mean(sign(m[nz]) == sign(g$actual[nz])), zero_preds = sum(!nz), auc = auc(m, g$win),
             slope = unname(slope_of(g, x)), pred_sd = sd(m)) }
UNIV <- list(list("dev", "dev", c("I", "C1", "C2", "C3")), list("devK", "devK", MODELS), list("cond", "cond", MODELS))
ov <- rbindlist(lapply(UNIV, function(u) { g <- U[[u[[1]]]]; rbindlist(lapply(u[[3]], function(x) {
  s <- if (u[[1]] == "cond") sig[model == x & split == "cond", sigma] else mean(sig[model == x & split == "dev", sigma])
  sl <- bols(BO[[u[[2]]]], g[[x]] - g$site, g$actual - g$site)
  cbind(data.table(universe = u[[1]], model = x), absm(g, x), data.table(slope_lo95 = qs(sl$draws, .95)[1], slope_hi95 = qs(sl$draws, .95)[2], sigma = s))[, sigma_over_rmse := sigma / rmse] })) }))
w(ov, "metrics_overall.csv")
# market's own accuracy beside the models (sigma by the same rule)
mo <- rbindlist(lapply(c("dev", "cond"), function(sp) { g <- U[[sp]]; rbindlist(lapply(c("Mc", "Mo"), function(x) { h <- g[!is.na(get(x))]
  data.table(universe = sp, line = ifelse(x == "Mc", "close", "open"), n = nrow(h), logloss = mean(h[[paste0("ll_", x)]]), brier = mean(h[[paste0("br_", x)]]), mae = mean(h[[paste0("ae_", x)]]), rmse = sqrt(mean(h[[paste0("se_", x)]]))) })) }))
w(mo, "market_own_accuracy.csv")
# paired deltas
MET <- c(logloss = "ll_", brier = "br_", mae = "ae_")
pairs <- rbind(data.table(a = CANDS, b = "I", uni = "dev", kind = "vs I"), data.table(a = CANDS, b = "I", uni = "cond", kind = "vs I"),
               data.table(a = c("I", CANDS), b = "K", uni = "devK", kind = "vs K"), data.table(a = c("I", CANDS), b = "K", uni = "cond", kind = "vs K"),
               data.table(a = c("C2", "C3", "C3"), b = c("C1", "C2", "C1"), uni = "dev", kind = "layer"), data.table(a = c("C2", "C3", "C3"), b = c("C1", "C2", "C1"), uni = "cond", kind = "layer"),
               data.table(a = "C1", b = "I", uni = c("dev", "cond"), kind = "layer"))
delta_rows <- function(g, bo, a, b, sel = TRUE, extra = list()) rbind(
  rbindlist(lapply(names(MET), function(mt) row_ci(bmean(bo, g[[paste0(MET[[mt]], a)]] - g[[paste0(MET[[mt]], b)]], sel), c(list(metric = mt), extra)))),
  row_ci(bdiff_rmse(bo, g[[paste0("se_", a)]], g[[paste0("se_", b)]], sel), c(list(metric = "rmse"), extra)))
dl <- rbindlist(lapply(seq_len(nrow(pairs)), function(i) with(pairs[i], cbind(data.table(comparison = paste(a, "-", b), kind = kind, universe = uni), delta_rows(U[[uni]], BO[[uni]], a, b)))))
dl <- dl[!duplicated(dl[, .(comparison, universe, metric)])]   # "C1 - I" is both the vs-I comparison and the first layer
zc <- c(logloss = qnorm(1 - 0.05 / 6), other = qnorm(0.975)); dl[, mde80 := (ifelse(metric == "logloss" & kind == "vs I" & universe == "dev", zc[["logloss"]], zc[["other"]]) + qnorm(0.8)) * se]
w(dl, "deltas.csv")
# fixed-sigma sensitivity (report only)
sens <- rbindlist(lapply(c(14, 16, 18), function(fs) rbindlist(lapply(CANDS, function(x) { r <- bmean(BO$dev, Gd[[sprintf("llf%d_%s", fs, x)]] - Gd[[sprintf("llf%d_I", fs)]])
  cbind(data.table(sigma_fixed = fs, comparison = paste(x, "- I")), row_ci(r))[, g1_verdict_under_sensitivity := estimate <= -0.002 & hi9833 < 0] }))))
w(sens, "sensitivity_fixed_sigma.csv")
# slices: season, gp bucket, stage, conference game, matchup; absolute metrics for every model and deltas vs I and vs previous layer
SL <- list(season = "season", gp_bucket = "gpb", stage = "stage", conference_game = "conf_game", matchup = "matchup")
slices <- rbindlist(lapply(c("dev", "cond"), function(sp) { g <- U[[sp]]; rbindlist(lapply(names(SL), function(sn) { v <- as.character(g[[SL[[sn]]]])
  rbindlist(lapply(sort(unique(v)), function(lv) { h <- g[v == lv]; rbindlist(lapply(MODELS, function(x) { if (anyNA(h[[x]])) { h2 <- h[!is.na(get(x))]; if (!nrow(h2)) return(NULL) } else h2 <- h
    cbind(data.table(universe = sp, slice_type = sn, slice = lv, model = x), absm(h2, x)) })) })) })) }))
w(slices, "slices.csv")
slice_d <- rbindlist(lapply(c("dev", "cond"), function(sp) { g <- U[[sp]]; rbindlist(lapply(names(SL), function(sn) { v <- as.character(g[[SL[[sn]]]])
  rbindlist(lapply(sort(unique(v)), function(lv) { sel <- v == lv
    rbindlist(lapply(list(c("C1", "I"), c("C2", "I"), c("C3", "I"), c("C2", "C1"), c("C3", "C2")), function(ab) rbindlist(lapply(c("logloss", "brier", "mae"), function(mt)
      cbind(data.table(universe = sp, slice_type = sn, slice = lv, comparison = paste(ab[1], "-", ab[2]), metric = mt), row_ci(bmean(BO[[sp]], g[[paste0(MET[[mt]], ab[1])]] - g[[paste0(MET[[mt]], ab[2])]], sel))))))) })) })) }))
w(slice_d, "slice_deltas.csv")
# calibration slope by gp bucket and stage (raw margins)
calib <- rbindlist(lapply(c("dev", "cond"), function(sp) { g <- U[[sp]]; rbindlist(lapply(MODELS, function(x) { h <- !is.na(g[[x]])
  rbindlist(lapply(c(levels(g$gpb), "gp 0-3", "gp 4+", "pooled"), function(lv) { sel <- h & (if (lv == "pooled") TRUE else if (lv %in% c("gp 0-3", "gp 4+")) g$stage == lv else as.character(g$gpb) == lv)
    r <- bols(BO[[sp]], g[[x]] - g$site, g$actual - g$site, sel); data.table(universe = sp, model = x, bucket = lv, n = r$n, slope = r$est, lo95 = qs(r$draws, .95)[1], hi95 = qs(r$draws, .95)[2]) })) })) }))
w(calib, "calibration_slopes.csv")
# predicted-margin distribution and winner disagreement vs the incumbent
pdist <- rbindlist(lapply(c("dev", "cond"), function(sp) { g <- U[[sp]]; rbindlist(lapply(MODELS, function(x) { m <- g[[x]]; ok <- !is.na(m)
  q <- quantile(m[ok], c(.05, .1, .25, .5, .75, .9, .95)); data.table(universe = sp, model = x, n = sum(ok), sd = sd(m[ok]), mean_abs = mean(abs(m[ok])), q05 = q[1], q10 = q[2], q25 = q[3], q50 = q[4], q75 = q[5], q90 = q[6], q95 = q[7],
    sd_gp0 = sd(m[ok & g$gpb == "0"]), sd_gp1 = sd(m[ok & g$gpb == "1"]), sd_gp2_3 = sd(m[ok & g$gpb == "2-3"]), sd_gp4_6 = sd(m[ok & g$gpb == "4-6"]), sd_gp7p = sd(m[ok & g$gpb == "7+"]),
    winner_disagree_vs_I = if (x == "I") NA_integer_ else sum(ok & sign(m) != sign(g$I)), actual_sd = sd(g$actual[ok])) })) }))
w(pdist, "pred_distribution.csv")
# tier separation on cross-tier games (oriented P4-vs-G5 bias and log-loss)
tier <- rbindlist(lapply(c("dev", "cond"), function(sp) { g <- U[[sp]]; rbindlist(lapply(MODELS, function(x) { h <- g[!is.na(get(x)) & s_p4 != 0]
  r <- bmean(BO[[sp]], (g$actual - g[[x]]) * g$s_p4, !is.na(g[[x]]) & g$s_p4 != 0)
  data.table(universe = sp, model = x, n = nrow(h), p4g5_bias = r$est, lo95 = qs(r$draws, .95)[1], hi95 = qs(r$draws, .95)[2], abs_bias = abs(r$est), logloss_cross_tier = mean(h[[paste0("ll_", x)]]), mae_cross_tier = mean(h[[paste0("ae_", x)]])) })) }))
w(tier, "tier_separation.csv")
cat("core metrics done\n")

# ======================= 6. rating-level diagnostics (from the E0 replay of the frozen predictions) =======================
rat <- fread("output/dev/round15/eval/ratings_replay.csv", colClasses = list(character = "cutoff")); snaps <- rbindlist(lapply(d$base$snap, function(sn) data.table(season = sn$season, cutoff = format(sn$cutoff, "%Y-%m-%d"), ct = sn$cutoff)))
snaps <- snaps[!duplicated(snaps[, .(season, cutoff)])]; rat <- merge(rat, snaps, by = c("season", "cutoff"))
tg <- rbindlist(lapply(2017:2025, function(y) { g <- d$games[[as.character(y)]][final == TRUE]; rbind(g[, .(season, team_id = home_id, available_at)], g[, .(season, team_id = away_id, available_at)]) }))
cg2 <- unique(snaps[season >= 2017, .(season, cutoff, ct)])
tgp <- tg[cg2, on = .(season), allow.cartesian = TRUE][available_at < ct, .(gp_team = .N), by = .(season, cutoff, team_id)]
rat <- merge(rat, tgp, by = c("season", "cutoff", "team_id"), all.x = TRUE)[is.na(gp_team), gp_team := 0L]
tconf <- rbindlist(lapply(2017:2025, function(y) { g <- as.data.table(d$sch[[as.character(y)]]); unique(rbind(g[home_fbs %in% TRUE, .(season = y, team_id = home_id, conf = home_conference)], g[away_fbs %in% TRUE, .(season = y, team_id = away_id, conf = away_conference)]))[!duplicated(team_id)] }))
rat <- merge(rat, tconf, by = c("season", "team_id"), all.x = TRUE); rat[, tier := fifelse(fbs, tier_of(conf, season), "FCS")][tier == "Other" & fbs, tier := "Independent"]
rat[, split := fifelse(season >= 2023, "cond", "dev")]; fb <- rat[fbs == TRUE]
spread <- fb[, .(sd = sd(rating)), by = .(model, split, season, cutoff)][, .(cutoffs = .N, mean_sd = mean(sd), first_cutoff_sd = sd[1], last_cutoff_sd = sd[.N]), by = .(model, split, season)]
tmean <- fb[, .(m = mean(rating)), by = .(model, split, season, cutoff, tier)][, .(mean_rating = mean(m)), by = .(model, split, tier)]
setorder(fb, model, season, team_id, ct); fb[, `:=`(prev = shift(rating), prev_cut = shift(cutoff)), by = .(model, season, team_id)]
stab <- fb[!is.na(prev), .(abs_change = abs(rating - prev), gpb = cut(gp_team, c(-Inf, 0, 1, 3, 6, Inf), labels = c("0", "1", "2-3", "4-6", "7+"))), by = .(model, split)]
stab <- rbind(stab[, .(n = .N, mean_abs_change = mean(abs_change)), by = .(model, split, gp_bucket = as.character(gpb))], stab[, .(gp_bucket = "all", n = .N, mean_abs_change = mean(abs_change)), by = .(model, split)])
kend <- fb[, { cs <- sort(unique(cutoff)); out <- list(); for (i in seq_along(cs)[-1]) { a <- .SD[cutoff == cs[i - 1]]; b <- .SD[cutoff == cs[i]]; top <- a[order(-rating)][1:25, team_id]
    ra <- a$rating[match(top, a$team_id)]; rb <- b$rating[match(top, b$team_id)]; ok <- !is.na(rb); pr <- combn(which(ok), 2)
    disc <- mean(sign(ra[pr[1, ]] - ra[pr[2, ]]) != sign(rb[pr[1, ]] - rb[pr[2, ]])); turn <- sum(!top %in% b[order(-rating)][1:25, team_id])
    out[[length(out) + 1L]] <- data.table(kendall = disc, turnover = turn) }; rbindlist(out) }, by = .(model, split, season)][, .(transitions = .N, kendall_top25 = mean(kendall), top25_turnover = mean(turnover)), by = .(model, split)]
w(spread, "rating_spread.csv"); w(tmean, "rating_tier_means.csv"); w(stab, "stability_abs_change.csv"); w(kend, "stability_kendall_top25.csv")
# update efficiency: residual (actual - m) on the change in the pair's rating difference since the previous cutoff
ue <- rbindlist(lapply(c("I", CANDS), function(x) { r <- rat[model == x & fbs == TRUE, .(season, cutoff, team_id, rating)]
  cuts <- unique(r[, .(season, cutoff)])[order(season, cutoff)][, prev_cutoff := shift(cutoff), by = season]
  rbindlist(lapply(c("dev", "cond"), function(sp) { g <- U[[sp]]; if (x == "I" && sp == "cond") return(NULL)
    h <- merge(g[, .(i = .I, season, cutoff, home_id, away_id)], cuts, by = c("season", "cutoff"))[!is.na(prev_cutoff)]
    gt <- function(cc, id) r[.(h$season, cc, id), on = .(season, cutoff, team_id), rating]
    dd <- (gt(h$cutoff, h$home_id) - gt(h$cutoff, h$away_id)) - (gt(h$prev_cutoff, h$home_id) - gt(h$prev_cutoff, h$away_id))
    x_ <- rep(NA_real_, nrow(g)); x_[h$i] <- dd; o <- bols(BO[[sp]], x_, g$actual - g[[x]])
    data.table(universe = sp, model = x, n = o$n, beta_upd = o$est, lo95 = qs(o$draws, .95)[1], hi95 = qs(o$draws, .95)[2]) })) }))
w(ue, "update_efficiency.csv")
# FBS-vs-FCS slice (predictions at the week's cutoff; I and C1 use -25 for every FCS team; C2/C3 their own FCS ratings)
fc <- rbindlist(lapply(2017:2025, function(y) { if (y == 2020) return(NULL); g <- d$games[[as.character(y)]][final == TRUE & xor(home_fbs %in% TRUE, away_fbs %in% TRUE)]
  cs <- snaps[season == y][order(ct)]; g[, ci := findInterval(as.numeric(kickoff), as.numeric(cs$ct))]; g <- g[ci >= 1]
  g[, .(season, game_id, kickoff, neutral, home_id, away_id, home_fbs = home_fbs %in% TRUE, cutoff = cs$cutoff[ci], actual = home_points - away_points)] }))
fr <- as.data.table(d$base$frame)[season %in% c(2017:2019, 2021:2025)]
cut_rule_agree <- mean(unlist(lapply(unique(fr$season), function(y) { cs <- snaps[season == y][order(ct)]; h <- fr[season == y]
  cs$cutoff[findInterval(as.numeric(h$kickoff), as.numeric(cs$ct))] == format(h$cutoff, "%Y-%m-%d") })))
if (SMOKE) { set.seed(2); fc[, actual := round(20 * (2 * home_fbs - 1) + rnorm(.N, 0, 15))][actual == 0, actual := 1] }
H <- unique(G[, .(season, hfa)]); fc <- merge(fc, H, by = "season"); fc[, site := hfa * !as.logical(neutral)]
fcs_pred <- function(x) { r <- rat[model == x, .(season, cutoff, team_id, rating, fbs)]
  look <- function(id, want_fbs) r[.(fc$season, fc$cutoff, id, want_fbs), on = .(season, cutoff, team_id, fbs), rating]
  fbs_side <- ifelse(fc$home_fbs, look(fc$home_id, TRUE), look(fc$away_id, TRUE))
  fcs_side <- if (x %in% c("I", "C1")) rep(-25, nrow(fc)) else ifelse(fc$home_fbs, look(fc$away_id, FALSE), look(fc$home_id, FALSE))
  ifelse(fc$home_fbs, fbs_side - fcs_side, fcs_side - fbs_side) + fc$site }
for (x in c("I", CANDS)) set(fc, j = x, value = fcs_pred(x))
fcs <- rbindlist(lapply(c("dev", "cond"), function(sp) { h <- fc[(season >= 2023) == (sp == "cond") & !is.na(C2) & !is.na(C3) & !is.na(C1)]
  rbindlist(lapply(c("I", CANDS), function(x) { if (anyNA(h[[x]])) return(NULL); s <- sg_of(x, sp, h$season); p <- clip(pnorm(h[[x]] / s)); yw <- as.numeric(h$actual > 0)
    data.table(universe = sp, model = x, n = nrow(h), mae = mean(abs(h[[x]] - h$actual)), bias = mean(h[[x]] - h$actual), logloss = mean(-(yw * log(p) + (1 - yw) * log(1 - p))), winner_pct = mean(sign(h[[x]]) == sign(h$actual))) })) }))
fcs[, cutoff_rule_agreement_on_fbs_games := cut_rule_agree]; w(fcs, "fbs_vs_fcs.csv")
cat("rating diagnostics done\n")

# ======================= 7. market value (evaluation only): T1-T5, encompassing, per split and line ======================
BK <- c(0, 1, 2, 3, 5, 7, Inf); BL <- c("[0,1)", "[1,2)", "[2,3)", "[3,5)", "[5,7)", ">=7")
mkt <- list(T1 = list(), T2 = list(), T3 = list(), T4 = list(), T5 = list(), EN = list())
for (sp in c("dev", "cond")) for (x in MODELS) { g <- U[[if (x == "K" && sp == "dev") "devK" else sp]]; bo <- BO[[if (x == "K" && sp == "dev") "devK" else sp]]
  for (ln in c("close", "open")) { M <- g[[if (ln == "close") "Mc" else "Mo"]]; sel <- !is.na(M) & !is.na(g[[x]]); E <- g[[x]] - M; res <- g$actual - M
    t1 <- bols(bo, E, res, sel); mkt$T1[[length(mkt$T1) + 1L]] <- data.table(universe = sp, model = x, line = ln, n = t1$n, alpha = t1$intercept, beta_E = t1$est, lo95 = qs(t1$draws, .95)[1], hi95 = qs(t1$draws, .95)[2], se = sd(t1$draws))
    c_ <- res * sign(E); bk <- cut(abs(E), BK, labels = BL, right = FALSE)
    for (b in BL) { s2 <- sel & (bk %in% b); if (!any(s2)) next; r <- bmean(bo, c_, s2); nz <- s2 & E != 0 & c_ != 0; k <- sum(c_[nz] > 0); n <- sum(nz); wl <- wilson(k, n)
      mkt$T2[[length(mkt$T2) + 1L]] <- data.table(universe = sp, model = x, line = ln, bucket = b, n = r$n, mean_c = r$est, lo95 = qs(r$draws, .95)[1], hi95 = qs(r$draws, .95)[2])
      mkt$T4[[length(mkt$T4) + 1L]] <- data.table(universe = sp, model = x, line = ln, bucket = b, n_decided = n, wins = k, ats_pct = k / n, wilson_lo = wl[1], wilson_hi = wl[2]) }
    gm <- bols(bo, pmin(abs(E), 10), c_, sel); mkt$T2[[length(mkt$T2) + 1L]] <- data.table(universe = sp, model = x, line = ln, bucket = "trend gamma", n = gm$n, mean_c = gm$est, lo95 = qs(gm$draws, .95)[1], hi95 = qs(gm$draws, .95)[2])
    nz <- sel & E != 0 & c_ != 0; k <- sum(c_[nz] > 0); n <- sum(nz); wl <- wilson(k, n)
    mkt$T4[[length(mkt$T4) + 1L]] <- data.table(universe = sp, model = x, line = ln, bucket = "pooled", n_decided = n, wins = k, ats_pct = k / n, wilson_lo = wl[1], wilson_hi = wl[2])
    t5 <- blogit(bo, pmin(abs(E), 10), as.numeric(c_ > 0), nz); mkt$T5[[length(mkt$T5) + 1L]] <- data.table(universe = sp, model = x, line = ln, n = t5$n, slope = t5$est, lo95 = qs(t5$draws, .95)[1], hi95 = qs(t5$draws, .95)[2])
    if (ln == "close") { en <- bols2(bo, M, g[[x]], g$actual, sel)
      mkt$EN[[length(mkt$EN) + 1L]] <- data.table(universe = sp, model = x, line = ln, n = en$n, a = en$est[1], b_M = en$est[2], b_M_lo95 = qs(en$draws[, 2], .95)[1], b_M_hi95 = qs(en$draws[, 2], .95)[2],
                                                   b_m = en$est[3], b_m_lo95 = qs(en$draws[, 3], .95)[1], b_m_hi95 = qs(en$draws[, 3], .95)[2]) } }
  # T3: line movement toward the model (games with open and close)
  sel <- !is.na(g$Mo) & !is.na(g$Mc) & !is.na(g[[x]]); Eo <- g[[x]] - g$Mo; mv <- g$Mc - g$Mo; clv <- sign(Eo) * mv; bk <- cut(abs(Eo), BK, labels = BL, right = FALSE)
  t3 <- bols(bo, Eo, mv, sel); big <- sel & abs(mv) >= 0.5 & Eo != 0; k <- sum(sign(mv[big]) == sign(Eo[big])); wl <- wilson(k, sum(big)); cl <- bmean(bo, clv, sel)
  mkt$T3[[length(mkt$T3) + 1L]] <- data.table(universe = sp, model = x, bucket = "pooled", n = t3$n, beta_mv = t3$est, beta_lo95 = qs(t3$draws, .95)[1], beta_hi95 = qs(t3$draws, .95)[2],
                                              moves_ge_half = sum(big), toward_share = k / sum(big), toward_lo = wl[1], toward_hi = wl[2], mean_clv = cl$est, clv_lo95 = qs(cl$draws, .95)[1], clv_hi95 = qs(cl$draws, .95)[2])
  for (b in BL) { s2 <- sel & (bk %in% b); if (!any(s2)) next; b2 <- s2 & abs(mv) >= 0.5 & Eo != 0; k <- sum(sign(mv[b2]) == sign(Eo[b2])); wl <- wilson(k, sum(b2)); cl <- bmean(bo, clv, s2)
    mkt$T3[[length(mkt$T3) + 1L]] <- data.table(universe = sp, model = x, bucket = b, n = sum(s2), beta_mv = NA_real_, beta_lo95 = NA_real_, beta_hi95 = NA_real_,
                                                moves_ge_half = sum(b2), toward_share = k / sum(b2), toward_lo = wl[1], toward_hi = wl[2], mean_clv = cl$est, clv_lo95 = qs(cl$draws, .95)[1], clv_hi95 = qs(cl$draws, .95)[2]) } }
for (t in names(mkt)) w(rbindlist(mkt[[t]]), sprintf("market_%s.csv", t))
T1 <- rbindlist(mkt$T1); cat("market done\n")

# ======================= 8. gates, layer values, recommendation (mechanical) ==============================================
D <- function(cmp, uni, mt) dl[comparison == cmp & universe == uni & metric == mt]
gates <- rbindlist(lapply(CANDS, function(x) { cm <- paste(x, "- I"); r <- list(); a <- function(g, thr, obs, ci, pass) r[[length(r) + 1L]] <<- data.table(candidate = x, gate = g, threshold = thr, observed = obs, interval = ci, pass = isTRUE(pass))
  ll <- D(cm, "dev", "logloss"); a("G1", "dLL(X-I) <= -0.0020 and 98.33% upper < 0", sprintf("%+.5f", ll$estimate), sprintf("98.33%% [%+.5f, %+.5f]", ll$lo9833, ll$hi9833), ll$estimate <= -0.002 & ll$hi9833 < 0)
  ma <- D(cm, "dev", "mae"); a("G2a", "dMAE <= +0.020 and 95% lower <= 0", sprintf("%+.4f", ma$estimate), sprintf("95%% [%+.4f, %+.4f]", ma$lo95, ma$hi95), ma$estimate <= 0.020 & ma$lo95 <= 0)
  rm <- D(cm, "dev", "rmse"); a("G2b", "dRMSE <= +0.030", sprintf("%+.4f", rm$estimate), sprintf("95%% [%+.4f, %+.4f]", rm$lo95, rm$hi95), rm$estimate <= 0.030)
  br <- D(cm, "dev", "brier"); a("G2c", "dBrier <= 0", sprintf("%+.5f", br$estimate), sprintf("95%% [%+.5f, %+.5f]", br$lo95, br$hi95), br$estimate <= 0)
  cs <- calib[universe == "dev" & model == x]; pooled <- cs[bucket == "pooled", slope]; bks <- cs[bucket %in% c("0", "1", "2-3", "4-6", "7+")]
  a("G2d", "raw slope pooled in [0.90,1.10]; each gp bucket in [0.80,1.20]", sprintf("pooled %.3f; buckets %s", pooled, paste(sprintf("%s:%.3f", bks$bucket, bks$slope), collapse = " ")), "",
    pooled >= 0.90 & pooled <= 1.10 & all(bks$slope >= 0.80 & bks$slope <= 1.20))
  tb <- tier[universe == "dev"]; a("G2e", "|P4-vs-G5 bias| <= incumbent's", sprintf("|%.3f| vs I |%.3f|", tb[model == x, p4g5_bias], tb[model == "I", p4g5_bias]), "", tb[model == x, abs_bias] <= tb[model == "I", abs_bias])
  sd_ <- slice_d[universe == "dev" & slice_type == "season" & comparison == cm & metric == "logloss"]
  a("G2f", "every dev season dLL <= +0.003", paste(sprintf("%s:%+.4f", sd_$slice, sd_$estimate), collapse = " "), "", all(sd_$estimate <= 0.003))
  st <- slice_d[universe == "dev" & slice_type == "stage" & comparison == cm & metric == "logloss"]
  a("G2g", "gp 0-3 and gp 4+ dLL <= +0.001", paste(sprintf("%s:%+.4f", st$slice, st$estimate), collapse = " "), "", nrow(st) == 2 & all(st$estimate <= 0.001))
  bx <- T1[universe == "dev" & line == "close" & model == x]; bi <- T1[universe == "dev" & line == "close" & model == "I"]
  a("G2h", "beta_E(X) >= beta_E(I) - 0.10 and 95% upper >= 0 (close, dev)", sprintf("beta_E %.3f vs I %.3f", bx$beta_E, bi$beta_E), sprintf("95%% [%.3f, %.3f]", bx$lo95, bx$hi95), bx$beta_E >= bi$beta_E - 0.10 & bx$hi95 >= 0)
  c3 <- D(cm, "cond", "logloss"); a("G3-ll", "cond dLL <= +0.001", sprintf("%+.5f", c3$estimate), sprintf("95%% [%+.5f, %+.5f]", c3$lo95, c3$hi95), c3$estimate <= 0.001)
  cm3 <- D(cm, "cond", "mae"); a("G3-mae", "cond dMAE <= +0.030", sprintf("%+.4f", cm3$estimate), sprintf("95%% [%+.4f, %+.4f]", cm3$lo95, cm3$hi95), cm3$estimate <= 0.030)
  cp <- calib[universe == "cond" & model == x & bucket == "pooled", slope]; a("G3-slope", "cond raw pooled slope in [0.90,1.10]", sprintf("%.3f", cp), "", cp >= 0.90 & cp <= 1.10)
  tc <- tier[universe == "cond"]; a("G3-tier", "cond |P4-vs-G5 bias| <= incumbent's", sprintf("|%.3f| vs I |%.3f|", tc[model == x, p4g5_bias], tc[model == "I", p4g5_bias]), "", tc[model == x, abs_bias] <= tc[model == "I", abs_bias])
  bxc <- T1[universe == "cond" & line == "close" & model == x]; bic <- T1[universe == "cond" & line == "close" & model == "I"]
  a("G3-market", "cond beta_E(X) >= beta_E(I) - 0.10 (close)", sprintf("beta_E %.3f vs I %.3f", bxc$beta_E, bic$beta_E), sprintf("95%% [%.3f, %.3f]", bxc$lo95, bxc$hi95), bxc$beta_E >= bic$beta_E - 0.10)
  a("G0", "integrity (G0a, G0b L1-L6, G0c)", "all pass", "", all(g0))
  rbindlist(r) }))
w(gates, "gates.csv")
gsum <- gates[, .(G0 = all(pass[gate == "G0"]), G1 = all(pass[gate == "G1"]), G2 = all(pass[grepl("^G2", gate)]), G3 = all(pass[grepl("^G3", gate)])), by = candidate][, all_gates := G0 & G1 & G2 & G3]
layer <- function(a, b) { r <- D(paste(a, "-", b), "dev", "logloss"); data.table(layer = paste(a, "over", b), dLL = r$estimate, lo95 = r$lo95, hi95 = r$hi95, upper_lt_0 = r$hi95 < 0, passes_G2 = gsum[candidate == a, G2])[, established := upper_lt_0 & passes_G2] }
lay <- rbind(layer("C2", "C1"), layer("C3", "C2"), layer("C3", "C1")); w(lay, "layers.csv")
R <- NA_character_; trace <- character()
for (x in CANDS) { ok <- gsum[candidate == x, all_gates]
  if (!ok) { trace <- c(trace, sprintf("%s: fails G0-G3 -> not recommended", x)); next }
  if (is.na(R)) { R <- x; trace <- c(trace, sprintf("%s: passes G0-G3 and R is empty -> R = %s", x, x)); next }
  lv <- layer(x, R); if (lv$established) { trace <- c(trace, sprintf("%s: passes G0-G3; layer over %s established (upper %.5f < 0) -> R = %s", x, R, lv$hi95, x)); R <- x }
  else trace <- c(trace, sprintf("%s: passes G0-G3; layer over %s NOT established (upper %.5f) -> R stays %s", x, R, lv$hi95, R)) }
verdict <- if (is.na(R)) "INCUMBENT RETAINED" else sprintf("PRODUCTION CANDIDATE (historical): %s", R)
w(gsum, "gate_summary.csv"); w(data.table(step = seq_along(trace), rule = trace), "recommendation_trace.csv"); w(data.table(verdict = verdict, R = R, smoke = SMOKE), "verdict.csv")
cat("\nVERDICT:", verdict, "\n"); print(gsum); print(lay)

# ======================= 9. freeze: hash every result file ===============================================================
fs <- setdiff(list.files(OUT, full.names = TRUE), file.path(OUT, "results.sha256"))
writeLines(sprintf("%s  %s", sapply(fs, sha), basename(fs)), file.path(OUT, "results.sha256"))
cat("results frozen:", length(fs), "files\n")
