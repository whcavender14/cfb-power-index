# Round 16 formal scoring (docs/round16/ROUND16_PREDECLARATION.md, frozen: docs/round16/predeclaration.sha256). RUN ONCE.
# Run from the c2-refinement worktree root (output/dev/round15 -> the frozen Round 15 caches).
# Smoke mode (R16_SMOKE=1, R16_SMOKE_DIR=<dir>): every game outcome (FBS-vs-FBS, FBS-vs-FCS, FCS-vs-FCS) is replaced by a
# synthetic draw from the incumbent's / Current C2's own prediction, and every outcome-free result input (market lines,
# stability ratings, FCS levels, FCS-credit ratings) by synthetic values, so no real Round 16 result is computed; only the integrity checks that read no outcome run (predeclaration §11a item 6). Nothing is written to
# docs/round16/results in smoke mode. Real run: refuses to start if docs/round16/results already exists.
suppressPackageStartupMessages({ source("config/paths.R"); source("config/production.R"); source(PATHS$model_ops); library(data.table)
  source("R/evaluation/evaluation_helpers.R"); for (f in c("data", "c1", "c2")) source(sprintf("R/round15/candidates/%s.R", f)); source("R/c2/c2_current.R") })
SMOKE <- Sys.getenv("R16_SMOKE") == "1"
OUT <- if (SMOKE) Sys.getenv("R16_SMOKE_DIR") else "docs/round16/results"
if (SMOKE && !nzchar(OUT)) stop("smoke mode needs R16_SMOKE_DIR")
if (!SMOKE && dir.exists(OUT)) stop("results already exist: the Round 16 scoring run is run once")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
w <- function(x, f) fwrite(x, file.path(OUT, f)); sha <- function(f) digest::digest(file = f, algo = "sha256")
WT <- dirname(normalizePath("."))                                     # .claude/worktrees
NREP <- 4000L; SEED <- 16016L; DEV <- c(2017L, 2018L, 2019L, 2021L, 2022L); COND <- 2023:2025
REF <- list(capture = c("output/c2r/stage1/capture.rds", "13c1687715202de40c8599a5cfdbace4e5e1f93e1a019493ce7c9fb3c3185be8"),
            replay = c("output/dev/round15/eval/ratings_replay.csv", "69016cf689e33508b7b54aa97ca62b4509d44f958d080a4b86d9c9540d8ec0bf"))

# ======================= G0: integrity (read no outcome) ==================================================================
g0 <- list(); gk <- function(id, check, pass, detail = "") { g0[[length(g0) + 1L]] <<- data.table(id = id, check = check, pass = isTRUE(pass), detail = detail); if (!isTRUE(pass)) stop("G0 failed: ", id, " ", check, " ", detail) }
ph <- readLines("docs/round16/predeclaration.sha256"); ph <- ph[!grepl("^#", ph)]
gk("G0a", "predeclaration and model manifest hashes", all(vapply(ph, function(l) { h <- sub("  .*$", "", l); f <- file.path("docs/round16", sub("^[0-9a-f]+  ", "", l)); sha(f) == h }, TRUE)), paste(substr(ph, 1, 12), collapse = "; "))
man <- fread("docs/round16/ROUND16_MODEL_MANIFEST.csv"); man[, path := fifelse(startsWith(file, "round13-pbp-stack/"), file.path(WT, file), file)]
man[, ok := vapply(path, function(f) file.exists(f) && sha(f) == sha256[match(f, path)], TRUE)]
gk("G0a", "every model artifact hash (ROUND16_MODEL_MANIFEST.csv)", all(man$ok), sprintf("%d of %d verify", sum(man$ok), nrow(man)))
for (r in REF) gk("G0a", paste("reference input", r[1]), sha(r[1]) == r[2])
gk("G0a", "E0 replay equals its Round 15 manifest", fread("docs/round15/eval/e0_manifest.csv")$sha256 == REF$replay[2])
d <- r15_build_data(); c1 <- readRDS(file.path(R15C$cache, "c1_components.rds")); c2 <- readRDS(file.path(R15C$cache, "c2_components.rds"))
dv <- c2_divisions(readRDS("output/dev/round15/prep/fcs_schedules_2013_2025.rds"))
run <- c2_run(d, c1, c2, dv); tmp <- tempfile("r16_rebuild"); dir.create(tmp)
fwrite(copy(run$pred)[, model := "C2"], file.path(tmp, "c2_predictions.csv")); fwrite(c2_fbs_vs_nonfbs(d, run), file.path(tmp, "c2_fbs_vs_nonfbs_predictions.csv"))
fwrite(run$ratings, file.path(tmp, "c2_ratings.csv")); fwrite(run$levels, file.path(tmp, "c2_group_levels.csv")); fwrite(run$anchors, file.path(tmp, "c2_anchors.csv"))
for (f in c("c2_predictions.csv", "c2_fbs_vs_nonfbs_predictions.csv", "c2_ratings.csv", "c2_group_levels.csv", "c2_anchors.csv"))
  gk("G0b", paste("Current C2 rebuild reproduces", f), sha(file.path(tmp, f)) == man[file == file.path("output/c2/current", f), sha256])
tests <- if (SMOKE) "tests/c2/test_c2_regression.R" else "tests/c2/run_all.R"
gk("G0c", paste("validation:", tests), system2("Rscript", tests, stdout = FALSE, stderr = FALSE) == 0, if (SMOKE) "smoke: outcome-free checks only; run_all.R runs in the real run" else "")
an <- fread("output/c2/current/c2_anchors.csv"); gk("G0d", "anchors use only earlier seasons, never 2020", an[, all(anchor_season < season & anchor_season != 2020)])
gk("G0d", "Round 15 leakage tests L1-L6 (shared inputs) pass", all(fread("docs/round15/construction/g0b_g0c_tests.csv")$pass) && all(fread("docs/round15/eval/g0b_l3_check.csv")$pass))
cc <- unlist(lapply(c("R/c2/c2_current.R", "R/c2/c2_diagnostics.R"), readLines))   # frozen R15 code: covered by its own L4 test (above)
gk("G0d", "no market data referenced by Current C2's code", !any(grepl("market|spread|closing|moneyline", cc, ignore.case = TRUE) & !grepl("^\\s*#", cc)))
gk("G0d", "construction parameters frozen through 2022 (2023-25 use key 2023 / 2022)", all(as.integer(names(c1$lam0)) <= 2022) && all(as.integer(names(c2$om)) <= 2022) && max(as.integer(names(c2$p2))) == 2023)
gpc <- c2_games_played(d); rr_ <- fread("output/c2/current/c2_ratings.csv", colClasses = list(character = "cutoff")); chk <- merge(rr_[gp > 0, .(season, cutoff, team_id, gp)], gpc, by = c("season", "cutoff", "team_id"), all.x = TRUE, suffixes = c("", "_avail"))
gk("G0d", "every rated team's games are all available before the cutoff", chk[, all(!is.na(gp_avail) & gp == gp_avail)], sprintf("%d team-cutoffs", nrow(chk)))

# ======================= 1. FBS-vs-FBS universe (identical game IDs) ======================================================
rd <- function(f) fread(f, colClasses = list(character = c("game_id", "cutoff")))
cols <- c("season", "game_id", "cutoff", "neutral", "home_id", "away_id", "home_conference", "away_conference", "gp_home", "gp_away", "hfa", "actual_margin", "pred_margin")
G <- rbind(rd("output/dev/round15/incumbent_replay_2017_2022.csv")[, ..cols][, split := "dev"], rd(PATHS$incumbent_cond)[, ..cols][, split := "cond"])
setnames(G, c("actual_margin", "pred_margin", "gp_home", "gp_away"), c("actual", "I", "gp_fbs_home", "gp_fbs_away")); G[, cutoff := substr(cutoff, 1, 10)]
G <- merge(G, rd("output/dev/round15/cand/c2_predictions.csv")[, .(game_id, C2f = pred_margin, c1 = substr(cutoff, 1, 10))], by = "game_id", all.x = TRUE)
G <- merge(G, rd("output/c2/current/c2_predictions.csv")[, .(game_id, C = pred_margin, c2 = substr(cutoff, 1, 10))], by = "game_id", all.x = TRUE)
R13 <- file.path(WT, "round13-pbp-stack")
G <- merge(G, rbind(rd(file.path(R13, "output/dev/round13/predictions_dev.csv")), rd(file.path(R13, "output/dev/round13/predictions_cond.csv")))[, .(game_id, K = pred_margin)], by = "game_id", all.x = TRUE)
gk("G0e", "identical FBS-vs-FBS game IDs and cutoffs for I, C2f and C (3,868 / 2,398)", G[, !anyNA(C2f) & !anyNA(C) & all(c1 == cutoff) & all(c2 == cutoff)] && G[split == "dev", .N] == 3868 && G[split == "cond", .N] == 2398 && !anyDuplicated(G$game_id))
G[, c("c1", "c2") := NULL]
w(rbindlist(g0), "g0_integrity.csv"); cat("G0 integrity passed\n")
# games played: all completed games (primary) and FBS-vs-FBS only (R15 frame count; sensitivity)
G <- merge(G, gpc[, .(season, cutoff, home_id = team_id, gh = gp)], by = c("season", "cutoff", "home_id"), all.x = TRUE); G <- merge(G, gpc[, .(season, cutoff, away_id = team_id, ga = gp)], by = c("season", "cutoff", "away_id"), all.x = TRUE)
G[is.na(gh), gh := 0L][is.na(ga), ga := 0L]
bucket <- function(x) as.character(cut(x, c(-Inf, 0, 1, 3, 6, Inf), labels = c("0", "1", "2-3", "4-6", "7+")))
G[, `:=`(gpb = bucket(pmin(gh, ga)), stage = fifelse(pmin(gh, ga) <= 3, "gp 0-3", "gp 4+"), gpb_fbs = bucket(pmin(gp_fbs_home, gp_fbs_away)), stage_fbs = fifelse(pmin(gp_fbs_home, gp_fbs_away) <= 3, "gp 0-3", "gp 4+"))]
G[, site := hfa * !as.logical(neutral)][, s_p4 := p4_orientation(home_conference, away_conference, season)]
G[, `:=`(th = tier_of(home_conference, season), ta = tier_of(away_conference, season))]
mk <- fread("output/dev/round15/market_lines_2017_2025.csv", colClasses = list(character = "game_id"))
G <- merge(G, mk[, .(game_id, mh = home_id, ma = away_id, open_home_spread, close_home_spread)], by = "game_id", all.x = TRUE)
G[, sg := fifelse(!is.na(mh) & mh != home_id, -1, 1)][, `:=`(Mc = -sg * close_home_spread, Mo = -sg * open_home_spread)][, c("mh", "ma", "sg", "open_home_spread", "close_home_spread") := NULL]
if (SMOKE) { set.seed(1); tr <- Sys.getenv("R16_SMOKE_TRUTH", "I"); stopifnot(tr %in% c("I", "C")); G[, actual := round(get(tr) + rnorm(.N, 0, 15))][actual == 0, actual := 1]   # R16_SMOKE_TRUTH=C exercises the pass path
  G[!is.na(Mc), Mc := round(2 * (I + rnorm(.N, 0, 4))) / 2]; G[!is.na(Mo), Mo := Mc + round(2 * rnorm(.N, 0, 1.5)) / 2] }
stopifnot(!any(G$actual == 0)); G[, win := as.numeric(actual > 0)]; setorder(G, split, season, cutoff, game_id)
MODELS <- c("I", "C2f", "C", "K")

# ======================= 2. sigma per model (one mechanical step, recorded and hashed before any loss) =====================
fit_sigma <- function(m, y) { f <- function(s) -sum(y * pnorm(m / s, log.p = TRUE) + (1 - y) * pnorm(-m / s, log.p = TRUE))
  o <- optimize(f, c(2, 80), tol = 1e-10); stopifnot(o$minimum > 2.01, o$minimum < 79.9); o$minimum }
sig <- rbindlist(lapply(MODELS, function(x) { g <- G[split == "dev" & !is.na(get(x))]; ys <- sort(unique(g$season))
  rbind(rbindlist(lapply(ys, function(y) { t <- g[season != y]; data.table(model = x, split = "dev", season = y, sigma = fit_sigma(t[[x]], t$win), n_fit = nrow(t)) })),
        data.table(model = x, split = "cond", season = NA_integer_, sigma = fit_sigma(g[[x]], g$win), n_fit = nrow(g))) }))
w(sig, "sigma.csv"); writeLines(sprintf("%s  sigma.csv", sha(file.path(OUT, "sigma.csv"))), file.path(OUT, "sigma.sha256"))
sg_of <- function(x, sp, ss) { s <- sig[model == x & split == sp]; if (sp == "dev") s$sigma[match(ss, s$season)] else rep(s$sigma, length(ss)) }
sgv <- function(x, split_, season_) { out <- numeric(length(split_)); for (sp in c("dev", "cond")) { i <- split_ == sp; if (any(i)) out[i] <- sg_of(x, sp, season_[i]) }; out }
clip <- function(p) pmin(pmax(p, 1e-6), 1 - 1e-6)
llf <- function(m, s, y) { p <- clip(pnorm(m / s)); -(y * log(p) + (1 - y) * log(1 - p)) }
for (x in MODELS) { m <- G[[x]]; s <- sgv(x, G$split, G$season); p <- clip(pnorm(m / s)); set(G, j = paste0("p_", x), value = p)
  set(G, j = paste0("ll_", x), value = -(G$win * log(p) + (1 - G$win) * log(1 - p))); set(G, j = paste0("br_", x), value = (p - G$win)^2)
  set(G, j = paste0("ae_", x), value = abs(m - G$actual)); set(G, j = paste0("se_", x), value = (m - G$actual)^2)
  for (fs in c(14, 16, 18)) set(G, j = sprintf("llf%d_%s", fs, x), value = llf(m, fs, G$win)) }

# ======================= 3. bootstrap (flat season x week blocks keyed on cutoff text; 4,000; seed 16016) ===================
mkboot <- function(key) { lev <- sort(unique(key)); B <- length(lev); set.seed(SEED)
  idx <- matrix(sample.int(B, NREP * B, replace = TRUE), nrow = NREP); list(b = match(key, lev), B = B, C = t(apply(idx, 1, tabulate, nbins = B))) }
bs <- function(bo, v) { s <- numeric(bo$B); t <- tapply(v, bo$b, sum); s[as.integer(names(t))] <- t; s }
qs <- function(x, lv) unname(quantile(x, c((1 - lv) / 2, 1 - (1 - lv) / 2), na.rm = TRUE))
bmean <- function(bo, v, sel = TRUE) { sel <- rep_len(sel, length(v)) & !is.na(v); vv <- ifelse(sel, v, 0)
  list(est = mean(v[sel]), draws = as.numeric(bo$C %*% bs(bo, vv)) / as.numeric(bo$C %*% bs(bo, as.numeric(sel))), n = sum(sel)) }
bdiff_rmse <- function(bo, a, b, sel = TRUE) { sel <- rep_len(sel, length(a)); n <- as.numeric(bo$C %*% bs(bo, as.numeric(sel)))
  list(est = sqrt(mean(a[sel])) - sqrt(mean(b[sel])), draws = sqrt(as.numeric(bo$C %*% bs(bo, ifelse(sel, a, 0))) / n) - sqrt(as.numeric(bo$C %*% bs(bo, ifelse(sel, b, 0))) / n), n = sum(sel)) }
bols <- function(bo, x, y, sel = TRUE) { sel <- rep_len(sel, length(x)) & !is.na(x) & !is.na(y); z <- function(v) bs(bo, ifelse(sel, v, 0))
  A <- bo$C %*% cbind(z(1), z(x), z(y), z(x * x), z(x * y)); f <- coef(lm(y[sel] ~ x[sel]))
  list(est = unname(f[2]), intercept = unname(f[1]), draws = (A[, 5] - A[, 2] * A[, 3] / A[, 1]) / (A[, 4] - A[, 2]^2 / A[, 1]), n = sum(sel)) }
bols2 <- function(bo, x1, x2, y, sel = TRUE) { sel <- rep_len(sel, length(y)) & !is.na(x1) & !is.na(x2); X <- cbind(1, x1, x2); z <- function(v) bs(bo, ifelse(sel, v, 0))
  P <- list(); for (i in 1:3) for (j in i:3) P[[paste(i, j)]] <- z(X[, i] * X[, j]); Q <- lapply(1:3, function(i) z(X[, i] * y))
  PA <- sapply(P, function(s) as.numeric(bo$C %*% s)); QA <- sapply(Q, function(s) as.numeric(bo$C %*% s))
  dr <- t(sapply(seq_len(NREP), function(r) { M <- matrix(0, 3, 3); k <- 0; for (i in 1:3) for (j in i:3) { k <- k + 1; M[i, j] <- M[j, i] <- PA[r, k] }; solve(M, QA[r, ]) }))
  list(est = unname(coef(lm(y[sel] ~ x1[sel] + x2[sel]))), draws = dr, n = sum(sel)) }
blogit <- function(bo, x, y, sel = TRUE) { sel <- rep_len(sel, length(x)) & !is.na(x) & !is.na(y); X <- cbind(1, x[sel]); yy <- y[sel]; bb <- bo$b[sel]
  est <- glm.fit(X, yy, family = binomial())$coefficients[2]
  dr <- vapply(seq_len(NREP), function(r) { ww <- bo$C[r, bb]; if (sum(ww) == 0) return(NA_real_); suppressWarnings(glm.fit(X, yy, weights = ww, family = binomial())$coefficients[2]) }, numeric(1))
  list(est = unname(est), draws = dr, n = sum(sel)) }
wilson <- function(k, n, z = qnorm(0.975)) { if (n == 0) return(c(NA, NA)); p <- k / n; c0 <- p + z^2 / (2 * n); h <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)); (c(c0 - h, c0 + h)) / (1 + z^2 / n) }
ci <- function(r) data.table(estimate = r$est[1], lo95 = qs(r$draws, .95)[1], hi95 = qs(r$draws, .95)[2], lo90 = qs(r$draws, .90)[1], hi90 = qs(r$draws, .90)[2], se = sd(r$draws, na.rm = TRUE), n = r$n)
U <- list(dev = G[split == "dev"], cond = G[split == "cond"]); U$devK <- U$dev[!is.na(K)]; U$condK <- U$cond[!is.na(K)]
BO <- lapply(U, function(g) mkboot(paste(g$season, g$cutoff))); print(sapply(BO, `[[`, "B")); stopifnot(BO$dev$B == 106, BO$cond$B == 65)

# ======================= 4. FBS-vs-FBS metrics, deltas, slices, calibration ================================================
absm <- function(g, x) { m <- g[[x]]; nz <- m != 0
  data.table(n = nrow(g), logloss = mean(g[[paste0("ll_", x)]]), brier = mean(g[[paste0("br_", x)]]), mae = mean(g[[paste0("ae_", x)]]), rmse = sqrt(mean(g[[paste0("se_", x)]])),
             bias = mean(m - g$actual), winner_pct = mean(sign(m[nz]) == sign(g$actual[nz])), pred_sd = sd(m), slope = unname(coef(lm(I(g$actual - g$site) ~ I(m - g$site)))[2])) }
uni_of <- function(x, sp) if (x == "K") paste0(sp, "K") else sp
ov <- rbindlist(lapply(c("dev", "cond"), function(sp) rbindlist(lapply(MODELS, function(x) { g <- U[[uni_of(x, sp)]]
  s <- if (sp == "cond") sig[model == x & split == "cond", sigma] else mean(sig[model == x & split == "dev", sigma])
  recal <- glm(g$win ~ qlogis(g[[paste0("p_", x)]]), family = binomial())
  cbind(data.table(universe = uni_of(x, sp), model = x), absm(g, x), data.table(sigma = s, recal_slope = unname(coef(recal)[2]), citl = mean(g[[paste0("p_", x)]] - g$win))) }))))
w(ov, "metrics_overall.csv")
rel <- rbindlist(lapply(c("dev", "cond"), function(sp) rbindlist(lapply(MODELS, function(x) { g <- U[[uni_of(x, sp)]]; p <- g[[paste0("p_", x)]]
  g[, .(universe = uni_of(x, sp), model = x, n = .N, mean_p = mean(p), win_rate = mean(win)), by = .(decile = cut(p, quantile(p, 0:10 / 10), include.lowest = TRUE, labels = 1:10))] }))))
w(rel, "reliability_deciles.csv")
MET <- c(logloss = "ll_", brier = "br_", mae = "ae_")
drow <- function(g, bo, a, b, sel = TRUE) rbind(rbindlist(lapply(names(MET), function(mt) cbind(data.table(metric = mt), ci(bmean(bo, g[[paste0(MET[[mt]], a)]] - g[[paste0(MET[[mt]], b)]], sel))))),
                                               cbind(data.table(metric = "rmse"), ci(bdiff_rmse(bo, g[[paste0("se_", a)]], g[[paste0("se_", b)]], sel))))
PAIRS <- list(c("C", "I", ""), c("C", "C2f", ""), c("C2f", "I", ""), c("C", "K", "K"), c("K", "I", "K"))
dl <- rbindlist(lapply(c("dev", "cond"), function(sp) rbindlist(lapply(PAIRS, function(p) { u <- paste0(sp, p[3]); cbind(data.table(comparison = paste(p[1], "-", p[2]), universe = u), drow(U[[u]], BO[[u]], p[1], p[2])) }))))
w(dl, "deltas.csv")
D <- function(cmp, uni, mt) dl[comparison == cmp & universe == uni & metric == mt]
SL <- list(season = "season", gp_bucket = "gpb", stage = "stage", gp_bucket_fbs_only = "gpb_fbs", stage_fbs_only = "stage_fbs")
sld <- rbindlist(lapply(c("dev", "cond"), function(sp) { g <- U[[sp]]; rbindlist(lapply(names(SL), function(sn) { v <- as.character(g[[SL[[sn]]]])
  rbindlist(lapply(sort(unique(v)), function(lv) { sel <- v == lv; rbindlist(lapply(list(c("C", "I"), c("C", "C2f"), c("C2f", "I")), function(ab)
    cbind(data.table(universe = sp, slice_type = sn, slice = lv, comparison = paste(ab[1], "-", ab[2])), drow(g, BO[[sp]], ab[1], ab[2], sel)))) })) })) }))
w(sld, "slice_deltas.csv")
cal <- rbindlist(lapply(c("dev", "cond"), function(sp) rbindlist(lapply(c("I", "C2f", "C"), function(x) { g <- U[[sp]]
  rbindlist(lapply(list(c("pooled", ""), c("0", "gpb"), c("1", "gpb"), c("2-3", "gpb"), c("4-6", "gpb"), c("7+", "gpb"), c("0", "gpb_fbs"), c("1", "gpb_fbs"), c("2-3", "gpb_fbs"), c("4-6", "gpb_fbs"), c("7+", "gpb_fbs")), function(b) {
    sel <- if (b[1] == "pooled") rep(TRUE, nrow(g)) else g[[b[2]]] == b[1]; r <- bols(BO[[sp]], g[[x]] - g$site, g$actual - g$site, sel)
    cbind(data.table(universe = sp, model = x, gp_definition = if (b[2] == "gpb_fbs") "FBS-only (R15, sensitivity)" else "all games", bucket = b[1]), ci(r)) })) }))))
w(cal, "calibration_slopes.csv")
tier <- rbindlist(lapply(c("dev", "cond"), function(sp) rbindlist(lapply(MODELS, function(x) { g <- U[[uni_of(x, sp)]]; r <- bmean(BO[[uni_of(x, sp)]], (g$actual - g[[x]]) * g$s_p4, g$s_p4 != 0)
  cbind(data.table(universe = uni_of(x, sp), model = x, p4g5_bias = r$est), ci(r)[, .(lo95, hi95)]) }))))
w(tier, "tier_separation.csv")
seas_q <- sld[universe == "dev" & slice_type == "season" & comparison == "C - I" & metric == "logloss"][, .(Q = sum(((estimate - weighted.mean(estimate, 1 / se^2)) / se)^2), df = .N - 1)][, p := pchisq(Q, df, lower.tail = FALSE)]
w(seas_q, "season_heterogeneity.csv")
sens <- rbindlist(lapply(c(14, 16, 18), function(fs) rbindlist(lapply(list(c("C", "I"), c("C", "C2f")), function(ab) cbind(data.table(sigma_fixed = fs, comparison = paste(ab[1], "-", ab[2])),
  ci(bmean(BO$dev, U$dev[[sprintf("llf%d_%s", fs, ab[1])]] - U$dev[[sprintf("llf%d_%s", fs, ab[2])]])))))))
auc <- function(m, y) { r <- rank(m); n1 <- sum(y == 1); n0 <- sum(y == 0); (sum(r[y == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0) }
sens <- rbind(sens, rbindlist(lapply(c("dev", "cond"), function(sp) data.table(sigma_fixed = NA, comparison = paste("AUC", sp), estimate = NA, model_auc = paste(sprintf("%s %.4f", c("I", "C2f", "C"), sapply(c("I", "C2f", "C"), function(x) auc(U[[sp]][[x]], U[[sp]]$win))), collapse = "; ")))), fill = TRUE)
w(sens, "sensitivity_report_only.csv")

# ======================= 5. rating stability (development; incumbent ratings exist only in the E0 development replay) =======
rat <- fread(REF$replay[1], colClasses = list(character = "cutoff"))
stab_of <- function(r) { r <- copy(r); setorder(r, season, team_id, cutoff); r[, prev := shift(rating), by = .(season, team_id)]
  ch <- r[!is.na(prev), mean(abs(rating - prev))]
  kd <- r[, { cs <- sort(unique(cutoff)); out <- numeric(); for (i in seq_along(cs)[-1]) { a <- .SD[cutoff == cs[i - 1]]; b <- .SD[cutoff == cs[i]]; top <- a[order(-rating)][1:25, team_id]
    ra <- a$rating[match(top, a$team_id)]; rb <- b$rating[match(top, b$team_id)]; ok <- !is.na(rb); pr <- combn(which(ok), 2); out <- c(out, mean(sign(ra[pr[1, ]] - ra[pr[2, ]]) != sign(rb[pr[1, ]] - rb[pr[2, ]]))) }; .(k = mean(out)) }, by = season][, mean(k)]
  c(mean_abs_change = ch, kendall_top25 = kd) }
cr <- fread("output/c2/current/c2_ratings.csv", colClasses = list(character = "cutoff"))[fbs == TRUE & season %in% DEV, .(season, cutoff, team_id, rating = power)]
if (SMOKE) { set.seed(4); rat[, rating := rnorm(.N, 0, 12)]; cr[, rating := rnorm(.N, 0, 12)] }
stab <- rbind(data.table(model = "I", t(stab_of(rat[model == "I" & fbs == TRUE & season %in% DEV, .(season, cutoff, team_id, rating)]))),
              data.table(model = "C2f", t(stab_of(rat[model == "C2" & fbs == TRUE & season %in% DEV, .(season, cutoff, team_id, rating)]))), data.table(model = "C", t(stab_of(cr))))
w(stab, "stability.csv")

# ======================= 6. FBS-vs-FCS, FCS-vs-FCS, FCS level ==============================================================
fcC <- fread("output/c2/current/c2_fbs_vs_nonfbs_predictions.csv", colClasses = list(character = "cutoff"))[final == TRUE]
fcC[, split := fifelse(season >= 2023, "cond", "dev")]
stopifnot(fcC[split == "dev", .N] == 561, fcC[split == "cond", .N] == 365)
cap <- readRDS(REF$capture[1]); fp <- cap$fcs_prior[, .(season, cutoff, nonfbs_id = team_id, prior_c = prior_power_c)]
FC <- fcC[, .(season, split, game_id, cutoff, neutral, fbs_home, fbs_id, nonfbs_id, group, H, first_game, actual = actual_fbs_margin, C = pred_fbs_margin)]
FC[, site := H * (!neutral) * fifelse(fbs_home, 1, -1)]
FC <- merge(FC, rat[model == "C2" & fbs == TRUE, .(season, cutoff, fbs_id = team_id, f2 = rating)], by = c("season", "cutoff", "fbs_id"), all.x = TRUE)
FC <- merge(FC, rat[model == "C2" & fbs == FALSE, .(season, cutoff, nonfbs_id = team_id, n2 = rating)], by = c("season", "cutoff", "nonfbs_id"), all.x = TRUE)
FC <- merge(FC, fp, by = c("season", "cutoff", "nonfbs_id"), all.x = TRUE)
FC[, C2f := f2 - fifelse(is.finite(n2), n2, prior_c) + site]
FC <- merge(FC, rat[model == "I" & fbs == TRUE, .(season, cutoff, fbs_id = team_id, fi = rating)], by = c("season", "cutoff", "fbs_id"), all.x = TRUE)
FC[, I := fi + 25 + site]; stopifnot(FC[, !anyNA(C) & !anyNA(C2f)], FC[split == "dev", !anyNA(I)])
if (SMOKE) { set.seed(2); FC[, actual := round(C + rnorm(.N, 0, 16))][actual == 0, actual := 1] }
FC[, win := as.numeric(actual > 0)]; setorder(FC, split, season, cutoff, game_id)
for (x in c("I", "C2f", "C")) { ok <- is.finite(FC[[x]]); s <- sgv(x, FC$split, FC$season); set(FC, j = paste0("ll_", x), value = ifelse(ok, llf(FC[[x]], s, FC$win), NA_real_)) }
fcs_m <- rbindlist(lapply(c("dev", "cond"), function(sp) rbindlist(lapply(c("I", "C2f", "C"), function(x) rbindlist(lapply(c("all", "first game", "later"), function(gs) {
  h <- FC[split == sp & is.finite(get(x)) & (gs == "all" | first_game == (gs == "first game"))]; if (!nrow(h)) return(NULL)
  data.table(universe = sp, model = x, games = gs, n = nrow(h), bias = mean(h[[x]] - h$actual), mae = mean(abs(h[[x]] - h$actual)), rmse = sqrt(mean((h[[x]] - h$actual)^2)),
             logloss = mean(h[[paste0("ll_", x)]]), winner_pct = mean(sign(h[[x]]) == sign(h$actual))) }))))))
w(fcs_m, "fbs_vs_fcs.csv")
FCb <- lapply(c(dev = "dev", cond = "cond"), function(sp) mkboot(paste(FC[split == sp]$season, FC[split == sp]$cutoff)))
fcs_d <- rbindlist(lapply(c("dev", "cond"), function(sp) { g <- FC[split == sp]; bo <- FCb[[sp]]
  rbind(cbind(data.table(universe = sp, comparison = "C - C2f", metric = "abs error"), ci(bmean(bo, abs(g$C - g$actual) - abs(g$C2f - g$actual)))),
        cbind(data.table(universe = sp, comparison = "C - C2f", metric = "logloss"), ci(bmean(bo, g$ll_C - g$ll_C2f))),
        cbind(data.table(universe = sp, comparison = "C", metric = "bias"), ci(bmean(bo, g$C - g$actual))),
        cbind(data.table(universe = sp, comparison = "C first games", metric = "bias"), ci(bmean(bo, g$C - g$actual, g$first_game)))) }))
w(fcs_d, "fbs_vs_fcs_deltas.csv")
# FCS vs FCS (both FCS-division, both rated at the cutoff)
snaps <- unique(rbindlist(lapply(d$base$snap, function(sn) data.table(season = sn$season, cutoff = format(sn$cutoff, "%Y-%m-%d"), ct = sn$cutoff))))
snaps <- snaps[!duplicated(snaps[, .(season, cutoff)])]; setorder(snaps, season, ct)
FF <- rbindlist(lapply(c(DEV, COND), function(y) { g <- d$games[[as.character(y)]][final == TRUE & !(home_fbs %in% TRUE) & !(away_fbs %in% TRUE)]
  cs <- snaps[season == y]; g[, ci := findInterval(as.numeric(kickoff), as.numeric(cs$ct))]; g <- g[ci >= 1]
  g[, .(season, game_id, neutral = as.logical(neutral), home_id, away_id, actual = home_points - away_points, cutoff = cs$cutoff[ci])] }))
FF <- merge(FF, dv[, .(season, home_id = team_id, dh = div)], by = c("season", "home_id"), all.x = TRUE); FF <- merge(FF, dv[, .(season, away_id = team_id, da = div)], by = c("season", "away_id"), all.x = TRUE)
FF <- FF[dh %in% "fcs" & da %in% "fcs"][, H := vapply(season, function(y) c2_H(d, y), 0)][, split := fifelse(season >= 2023, "cond", "dev")]
rc <- fread("output/c2/current/c2_ratings.csv", colClasses = list(character = "cutoff"))[fbs == FALSE, .(season, cutoff, team_id, r = power)]; r2 <- rat[model == "C2" & fbs == FALSE, .(season, cutoff, team_id, r = rating)]
FF <- merge(merge(FF, rc[, .(season, cutoff, home_id = team_id, ch = r)], by = c("season", "cutoff", "home_id")), rc[, .(season, cutoff, away_id = team_id, ca = r)], by = c("season", "cutoff", "away_id"))
FF <- merge(merge(FF, r2[, .(season, cutoff, home_id = team_id, fh = r)], by = c("season", "cutoff", "home_id")), r2[, .(season, cutoff, away_id = team_id, fa = r)], by = c("season", "cutoff", "away_id"))
FF[, `:=`(C = ch - ca + H * (!neutral), C2f = fh - fa + H * (!neutral))]
if (SMOKE) { set.seed(3); FF[, actual := round(C + rnorm(.N, 0, 16))] }
ffm <- FF[, rbindlist(lapply(c("C2f", "C"), function(x) { m <- get(x); data.table(model = x, n = .N, mae = mean(abs(m - actual)), rmse = sqrt(mean((m - actual)^2)), bias = mean(m - actual),
  calib_slope = unname(coef(lm(actual ~ m))[2]), spearman = cor(m, actual, method = "spearman")) })), by = .(universe = split)]
w(ffm, "fcs_vs_fcs.csv")
wks <- copy(snaps)[, wk := seq_len(.N), by = season]
lv <- merge(fread("output/c2/current/c2_group_levels.csv", colClasses = list(character = "cutoff")), wks[, .(season, cutoff, wk)], by = c("season", "cutoff"))
if (SMOKE) { set.seed(6); lv[is.finite(fcs_level), fcs_level := -28 + rnorm(.N, 0, 1)] }
lvs <- lv[is.finite(fcs_level)][order(season, wk)][, .(final_level = fcs_level[.N], mean_abs_change_from_cutoff4 = mean(abs(diff(fcs_level[wk >= 4])))), by = season]
lvs <- merge(lvs, an[, .(season, anchor = fcs)], by = "season")[, gap_to_anchor := final_level - anchor]
w(lvs, "fcs_level_stability.csv")
# FBS rating change vs frozen C2 by number of FCS opponents (final cutoff)
nfo <- rbindlist(lapply(c(DEV, COND), function(y) { g <- d$games[[as.character(y)]][final == TRUE]; ids <- fbs_ids(d$sch[[as.character(y)]])
  r <- rbind(g[, .(team_id = home_id, opp = away_id)], g[, .(team_id = away_id, opp = home_id)])[team_id %in% ids]; r[, .(season = y, n_fcs = sum(!opp %in% ids)), by = team_id] }))
fr <- merge(fread("output/c2/current/c2_ratings.csv", colClasses = list(character = "cutoff"))[fbs == TRUE, .(season, cutoff, team_id, p = power)], rat[model == "C2" & fbs == TRUE, .(season, cutoff, team_id, p0 = rating)], by = c("season", "cutoff", "team_id"))
fr <- fr[, .SD[cutoff == max(cutoff)], by = season]; fr <- merge(fr, nfo, by = c("season", "team_id")); if (SMOKE) { set.seed(7); fr[, `:=`(p = rnorm(.N), p0 = rnorm(.N))] }
w(fr[, .(team_seasons = .N, mean_change_vs_C2f = mean(p - p0)), by = .(universe = fifelse(season >= 2023, "cond", "dev"), n_fcs_opponents = pmin(n_fcs, 2))][order(universe, n_fcs_opponents)], "fcs_credit.csv")

# ======================= 7. whole-system log-loss (FBS-vs-FBS + FBS-vs-FCS): the Stage 3 objective J ======================
J <- rbind(G[, .(split, season, cutoff, game_id, set = "FBS-FBS", ll_C, ll_C2f)], FC[, .(split, season, cutoff, game_id, set = "FBS-FCS", ll_C, ll_C2f)])
Jd <- rbindlist(lapply(c("dev", "cond"), function(sp) { g <- J[split == sp]; cbind(data.table(universe = sp, comparison = "C - C2f", metric = "whole-system logloss", J_C = mean(g$ll_C), J_C2f = mean(g$ll_C2f)),
  ci(bmean(mkboot(paste(g$season, g$cutoff)), g$ll_C - g$ll_C2f))) }))
w(Jd, "whole_system_J.csv")

# ======================= 8. market (evaluation only; after every prediction and manifest verified) =========================
BK <- c(0, 1, 2, 3, 5, 7, Inf); BL <- c("[0,1)", "[1,2)", "[2,3)", "[3,5)", "[5,7)", ">=7")
mkt <- list(T1 = list(), T2 = list(), T3 = list(), T4 = list(), T5 = list(), EN = list())
for (sp in c("dev", "cond")) for (x in MODELS) { u <- uni_of(x, sp); g <- U[[u]]; bo <- BO[[u]]
  for (ln in c("close", "open")) { M <- g[[if (ln == "close") "Mc" else "Mo"]]; sel <- !is.na(M) & !is.na(g[[x]]); E <- g[[x]] - M; res <- g$actual - M
    t1 <- bols(bo, E, res, sel); mkt$T1[[length(mkt$T1) + 1L]] <- data.table(universe = u, model = x, line = ln, n = t1$n, alpha = t1$intercept, beta_E = t1$est, lo95 = qs(t1$draws, .95)[1], hi95 = qs(t1$draws, .95)[2])
    c_ <- res * sign(E); bk <- cut(abs(E), BK, labels = BL, right = FALSE)
    for (b in BL) { s2 <- sel & (bk %in% b); if (!any(s2)) next; r <- bmean(bo, c_, s2); nz <- s2 & E != 0 & c_ != 0; k <- sum(c_[nz] > 0); n <- sum(nz); wl <- wilson(k, n)
      mkt$T2[[length(mkt$T2) + 1L]] <- data.table(universe = u, model = x, line = ln, bucket = b, n = r$n, mean_c = r$est, lo95 = qs(r$draws, .95)[1], hi95 = qs(r$draws, .95)[2])
      mkt$T4[[length(mkt$T4) + 1L]] <- data.table(universe = u, model = x, line = ln, bucket = b, n_decided = n, wins = k, ats_pct = k / n, wilson_lo = wl[1], wilson_hi = wl[2]) }
    gm <- bols(bo, pmin(abs(E), 10), c_, sel); mkt$T2[[length(mkt$T2) + 1L]] <- data.table(universe = u, model = x, line = ln, bucket = "trend gamma", n = gm$n, mean_c = gm$est, lo95 = qs(gm$draws, .95)[1], hi95 = qs(gm$draws, .95)[2])
    nz <- sel & E != 0 & c_ != 0; k <- sum(c_[nz] > 0); n <- sum(nz); wl <- wilson(k, n)
    mkt$T4[[length(mkt$T4) + 1L]] <- data.table(universe = u, model = x, line = ln, bucket = "pooled", n_decided = n, wins = k, ats_pct = k / n, wilson_lo = wl[1], wilson_hi = wl[2])
    t5 <- blogit(bo, pmin(abs(E), 10), as.numeric(c_ > 0), nz); mkt$T5[[length(mkt$T5) + 1L]] <- data.table(universe = u, model = x, line = ln, n = t5$n, slope = t5$est, lo95 = qs(t5$draws, .95)[1], hi95 = qs(t5$draws, .95)[2])
    if (ln == "close") { en <- bols2(bo, M, g[[x]], g$actual, sel)
      mkt$EN[[length(mkt$EN) + 1L]] <- data.table(universe = u, model = x, line = ln, n = en$n, a = en$est[1], b_M = en$est[2], b_M_lo95 = qs(en$draws[, 2], .95)[1], b_M_hi95 = qs(en$draws[, 2], .95)[2],
                                                   b_m = en$est[3], b_m_lo95 = qs(en$draws[, 3], .95)[1], b_m_hi95 = qs(en$draws[, 3], .95)[2]) } }
  sel <- !is.na(g$Mo) & !is.na(g$Mc) & !is.na(g[[x]]); Eo <- g[[x]] - g$Mo; mv <- g$Mc - g$Mo; clv <- sign(Eo) * mv
  t3 <- bols(bo, Eo, mv, sel); big <- sel & abs(mv) >= 0.5 & Eo != 0; k <- sum(sign(mv[big]) == sign(Eo[big])); wl <- wilson(k, sum(big)); cl <- bmean(bo, clv, sel)
  mkt$T3[[length(mkt$T3) + 1L]] <- data.table(universe = u, model = x, n = t3$n, beta_mv = t3$est, beta_lo95 = qs(t3$draws, .95)[1], beta_hi95 = qs(t3$draws, .95)[2],
                                              moves_ge_half = sum(big), toward_share = k / sum(big), toward_lo = wl[1], toward_hi = wl[2], mean_clv = cl$est, clv_lo95 = qs(cl$draws, .95)[1], clv_hi95 = qs(cl$draws, .95)[2]) }
for (t in names(mkt)) w(rbindlist(mkt[[t]]), sprintf("market_%s.csv", t))
T1 <- rbindlist(mkt$T1)

# ======================= 9. gates (predeclaration §5-§8), secondary claim, verdict (mechanical) ============================
gl <- list(); a <- function(g, thr, obs, pass) gl[[length(gl) + 1L]] <<- data.table(gate = g, rule = thr, observed = obs, pass = isTRUE(pass))
ll <- D("C - I", "dev", "logloss"); a("G1", "dLL(C-I) dev <= -0.0020 and 95% upper < 0", sprintf("%+.5f [95%% %+.5f, %+.5f]", ll$estimate, ll$lo95, ll$hi95), ll$estimate <= -0.002 & ll$hi95 < 0)
br <- D("C - I", "dev", "brier"); a("G2a", "dBrier(C-I) dev <= 0", sprintf("%+.5f [95%% %+.5f, %+.5f]", br$estimate, br$lo95, br$hi95), br$estimate <= 0)
oc <- ov[universe == "dev" & model == "C"]; oi <- ov[universe == "dev" & model == "I"]
a("G2b", "recalibration slope in [0.90,1.10] and |CITL| <= 0.02 (dev)", sprintf("slope %.3f; CITL %+.4f", oc$recal_slope, oc$citl), oc$recal_slope >= 0.90 & oc$recal_slope <= 1.10 & abs(oc$citl) <= 0.02)
ma <- D("C - I", "dev", "mae"); a("G3a", "dMAE <= +0.020 and 95% lower <= 0", sprintf("%+.4f [95%% %+.4f, %+.4f]", ma$estimate, ma$lo95, ma$hi95), ma$estimate <= 0.020 & ma$lo95 <= 0)
rm_ <- D("C - I", "dev", "rmse"); a("G3b", "dRMSE <= +0.030", sprintf("%+.4f", rm_$estimate), rm_$estimate <= 0.030)
a("G3c", "|bias(C)| <= |bias(I)| + 0.50 (dev)", sprintf("|%.3f| vs |%.3f| + 0.50", oc$bias, oi$bias), abs(oc$bias) <= abs(oi$bias) + 0.50)
cp <- cal[universe == "dev" & model == "C" & bucket == "pooled"]; a("G3d", "pooled raw slope in [0.90,1.10] (dev)", sprintf("%.3f", cp$estimate), cp$estimate >= 0.90 & cp$estimate <= 1.10)
cb <- cal[universe == "dev" & model == "C" & gp_definition == "all games" & bucket != "pooled"]
cb[, fail := (estimate > 1.20 & lo90 > 1.20) | (estimate < 0.80 & hi90 < 0.80)]
a("G4", "no all-games gp bucket with slope outside [0.80,1.20] AND 90% interval wholly outside on that side", paste(sprintf("%s:%.3f[%.3f,%.3f]", cb$bucket, cb$estimate, cb$lo90, cb$hi90), collapse = " "), !any(cb$fail))
fd <- fcs_m[universe == "dev" & games == "all"]; ff1 <- fcs_m[universe == "dev" & games == "first game"]
a("G5a", "|FBS-vs-FCS bias| <= 3.0 (dev)", sprintf("%+.3f", fd[model == "C", bias]), abs(fd[model == "C", bias]) <= 3.0)
a("G5b", "FBS-vs-FCS MAE(C) <= MAE(C2f) and <= MAE(I at -25) + 0.25 (dev)", sprintf("%.3f vs C2f %.3f, I %.3f", fd[model == "C", mae], fd[model == "C2f", mae], fd[model == "I", mae]),
  fd[model == "C", mae] <= fd[model == "C2f", mae] & fd[model == "C", mae] <= fd[model == "I", mae] + 0.25)
a("G5c", "first-game |bias| <= 4.0 (dev)", sprintf("%+.3f", ff1[model == "C", bias]), abs(ff1[model == "C", bias]) <= 4.0)
g5d <- function(sp) { f <- ffm[universe == sp]; c_ <- f[model == "C"]; o <- f[model == "C2f"]
  list(obs = sprintf("slope %.3f; MAE %.3f vs C2f %.3f; Spearman %.3f vs %.3f", c_$calib_slope, c_$mae, o$mae, c_$spearman, o$spearman),
       pass = c_$calib_slope >= 0.90 & c_$calib_slope <= 1.10 & c_$mae <= o$mae + 0.10 & c_$spearman >= o$spearman - 0.02) }
x5 <- g5d("dev"); a("G5d", "FCS-vs-FCS slope [0.90,1.10], MAE <= C2f + 0.10, Spearman >= C2f - 0.02 (dev)", x5$obs, x5$pass)
g5e <- function(ss) { l <- lvs[season %in% ss]; list(obs = paste(sprintf("%d:%+.2f/%.2f", l$season, l$gap_to_anchor, l$mean_abs_change_from_cutoff4), collapse = " "),
  pass = nrow(l) == length(ss) && all(abs(l$gap_to_anchor) <= 4.0 & l$mean_abs_change_from_cutoff4 <= 0.50)) }
x5 <- g5e(DEV); a("G5e", "every dev season: |final level - anchor| <= 4.0 and mean |dlevel| from cutoff 4 <= 0.50", x5$obs, x5$pass)
season_rule <- function(sp) { s <- sld[universe == sp & slice_type == "season" & comparison == "C - I" & metric == "logloss"]; s[, fail := estimate > 0.003 & lo90 > 0]
  list(obs = paste(sprintf("%s:%+.4f[90%% %+.4f,%+.4f]%s", s$slice, s$estimate, s$lo90, s$hi90, fifelse(s$estimate > 0.003, " FLAG", "")), collapse = " "), pass = !any(s$fail)) }
x6 <- season_rule("dev"); a("G6a", "no dev season with dLL > +0.003 AND 90% lower > 0", x6$obs, x6$pass)
st <- sld[universe == "dev" & slice_type == "stage" & comparison == "C - I" & metric == "logloss"]; st[, fail := estimate > 0.001 & lo90 > 0]
a("G6b", "gp 0-3 and gp 4+ (all games): fail only if dLL > +0.001 AND 90% lower > 0", paste(sprintf("%s:%+.4f[90%% %+.4f,%+.4f]", st$slice, st$estimate, st$lo90, st$hi90), collapse = " "), nrow(st) == 2 & !any(st$fail))
tb <- tier[universe == "dev"]; a("G6c", "|P4-vs-G5 bias(C)| <= |bias(I)| (dev)", sprintf("|%.3f| vs |%.3f|", tb[model == "C", p4g5_bias], tb[model == "I", p4g5_bias]), abs(tb[model == "C", p4g5_bias]) <= abs(tb[model == "I", p4g5_bias]))
a("G6d", "stability: mean |dP| and top-25 Kendall <= 1.25 x incumbent (dev)", sprintf("|dP| %.3f vs %.3f; Kendall %.4f vs %.4f", stab[model == "C", mean_abs_change], stab[model == "I", mean_abs_change], stab[model == "C", kendall_top25], stab[model == "I", kendall_top25]),
  stab[model == "C", mean_abs_change] <= 1.25 * stab[model == "I", mean_abs_change] & stab[model == "C", kendall_top25] <= 1.25 * stab[model == "I", kendall_top25])
bx <- T1[universe == "dev" & line == "close" & model == "C"]; bi <- T1[universe == "dev" & line == "close" & model == "I"]
a("G6e", "market safety: beta_E(C) >= beta_E(I) - 0.10 and 95% upper >= 0 (close, dev)", sprintf("%.3f vs %.3f [95%% %.3f, %.3f]", bx$beta_E, bi$beta_E, bx$lo95, bx$hi95), bx$beta_E >= bi$beta_E - 0.10 & bx$hi95 >= 0)
c7 <- D("C - I", "cond", "logloss"); a("G7-ll", "2023-25 dLL <= +0.001", sprintf("%+.5f", c7$estimate), c7$estimate <= 0.001)
m7 <- D("C - I", "cond", "mae"); a("G7-mae", "2023-25 dMAE <= +0.030", sprintf("%+.4f", m7$estimate), m7$estimate <= 0.030)
p7 <- cal[universe == "cond" & model == "C" & bucket == "pooled"]; a("G7-slope", "2023-25 pooled raw slope in [0.90,1.10]", sprintf("%.3f", p7$estimate), p7$estimate >= 0.90 & p7$estimate <= 1.10)
tc <- tier[universe == "cond"]; a("G7-tier", "2023-25 |P4-vs-G5 bias| <= incumbent's", sprintf("|%.3f| vs |%.3f|", tc[model == "C", p4g5_bias], tc[model == "I", p4g5_bias]), abs(tc[model == "C", p4g5_bias]) <= abs(tc[model == "I", p4g5_bias]))
bxc <- T1[universe == "cond" & line == "close" & model == "C"]; bic <- T1[universe == "cond" & line == "close" & model == "I"]
a("G7-market", "2023-25 beta_E(C) >= beta_E(I) - 0.10 (close)", sprintf("%.3f vs %.3f", bxc$beta_E, bic$beta_E), bxc$beta_E >= bic$beta_E - 0.10)
x7 <- season_rule("cond"); a("G7-seasons", "no 2023-25 season with dLL > +0.003 AND 90% lower > 0", x7$obs, x7$pass)
fc7 <- fcs_m[universe == "cond" & model == "C"]; a("G7-G5a", "2023-25 |FBS-vs-FCS bias| <= 3.0", sprintf("%+.3f", fc7[games == "all", bias]), abs(fc7[games == "all", bias]) <= 3.0)
a("G7-G5c", "2023-25 first-game |bias| <= 4.0", sprintf("%+.3f", fc7[games == "first game", bias]), abs(fc7[games == "first game", bias]) <= 4.0)
x5 <- g5d("cond"); a("G7-G5d", "2023-25 FCS-vs-FCS slope / MAE / Spearman", x5$obs, x5$pass)
x5 <- g5e(COND); a("G7-G5e", "every 2023-25 season: FCS level within 4.0 of anchor, stable from cutoff 4", x5$obs, x5$pass)
a("G0", "integrity (G0a-G0e)", "all pass", all(rbindlist(g0)$pass))
gates <- rbindlist(gl); w(gates, "gates.csv"); print(gates[, .(gate, pass, observed)])
verdict_of <- function(gates) { g1 <- gates[gate == "G1", pass]; guard <- all(gates[grepl("^G[2-7]", gate), pass])
  if (!g1) "INCUMBENT RETAINED (G1 not met)" else if (!guard) sprintf("INCUMBENT RETAINED (guardrail failed: %s)", paste(gates[grepl("^G[2-7]", gate) & !pass, gate], collapse = ", ")) else
  "QUALIFIED (historical): PRODUCTION CANDIDATE - may advance to independent forward confirmation; not independent proof of superiority (historical data influenced development)" }
if (SMOKE) {   # exercise every verdict branch on mock gate tables (no data involved)
  mock <- copy(gates)[, pass := TRUE]; stopifnot(startsWith(verdict_of(mock), "QUALIFIED (historical)"))
  stopifnot(verdict_of(copy(mock)[gate == "G1", pass := FALSE]) == "INCUMBENT RETAINED (G1 not met)", verdict_of(copy(mock)[gate == "G6a", pass := FALSE]) == "INCUMBENT RETAINED (guardrail failed: G6a)")
  cat("verdict branches verified on mock gates\n") }
g1 <- gates[gate == "G1", pass]; verdict <- verdict_of(gates)
jd <- Jd[universe == "dev"]; fb2 <- D("C - C2f", "dev", "logloss")
sec <- data.table(claim = "Stage 3 adds value (C vs C2f), fixed sequence after G1", tested = g1, whole_system_dLL = jd$estimate, whole_system_hi95 = jd$hi95, fbs_fbs_dLL = fb2$estimate, fbs_fbs_hi95 = fb2$hi95,
                  result = if (!g1) "NOT TESTED (G1 not met)" else if (jd$hi95 < 0 & fb2$hi95 < 0.001) "CONFIRMED" else "NOT CONFIRMED")
w(sec, "secondary_claim.csv"); w(data.table(verdict = verdict, smoke = SMOKE, scored_at_utc = format(Sys.time(), tz = "UTC")), "verdict.csv")
cat("\nVERDICT:", verdict, "\nSecondary claim:", sec$result, "\n")

# ======================= 10. freeze: hash every result file ===============================================================
fs <- setdiff(list.files(OUT, full.names = TRUE), file.path(OUT, "results.sha256"))
writeLines(sprintf("%s  %s", sapply(fs, sha), basename(fs)), file.path(OUT, "results.sha256")); cat("results frozen:", length(fs), "files\n")
