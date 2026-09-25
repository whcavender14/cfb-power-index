# C2 refinement research, Stage 1 (diagnosis only), part A: replay frozen C2 week by week and capture the whole solved
# system at every cutoff. Run from the round15-power-rating worktree root: it reads that worktree's untracked caches and
# writes only under the c2-refinement worktree. Nothing is fitted, tuned or selected. Every parameter is read from the
# frozen construction files, and the replay must reproduce every frozen C2 prediction to <= 1e-9 or the script stops.
#
# Captured per cutoff (all exact linear algebra on C2's own ridge system Q b = X'Wy + Lambda p):
#   * every entity's power rating (FBS and non-FBS), centered on the FBS mean as C2 does;
#   * an exact additive decomposition of each rating into contributions of the data blocks and the priors
#     (b is linear in y and p, and Q does not depend on either);
#   * level pass-through: the share of the non-FBS block's level set by its prior (pi_prior) vs by the FBS-vs-non-FBS
#     linking rows (pi_data = 1 - pi_prior, exactly);
#   * the free-level offset: the same system with one extra UNPENALIZED column that shifts every non-FBS power by a
#     common amount (it moves only linking rows), i.e. the level the in-sample data imply with C2's relative structure kept;
#   * the in-sample mean FBS-margin residual on linking games.
# The same free-level measurement is made on the end-of-season fits (r15_eos_full) that produce mu_FCS and last_eos.
source("config/paths.R"); source("config/production.R")
suppressPackageStartupMessages({ source(PATHS$model_ops); library(data.table); library(Matrix)
  for (f in c("data", "c1", "c2", "tune")) source(sprintf("R/round15/candidates/%s.R", f)) })
C2R <- "/Users/willcavender/Desktop/Revised CFB Modeling/.claude/worktrees/c2-refinement"
out <- file.path(C2R, "output/c2r/stage1"); dir.create(out, recursive = TRUE, showWarnings = FALSE)
d <- r15_build_data()
c1 <- readRDS(file.path(R15C$cache, "c1_components.rds")); c2 <- readRDS(file.path(R15C$cache, "c2_components.rds"))
key22 <- function(k) as.character(if (k >= 2023) 2022 else k); keyof <- function(y) if (y >= 2023) 2023L else y   # E0's keys
lam_of <- function(z, key = z) r15_c1_lambda(c1$priors[[as.character(z)]], c1$varm[[as.character(key)]], c1$lam0[[key22(key)]])
vb <- function(z) { v <- c1$varm[[as.character(z)]]; list(off = v$off$vbar, def = v$def$vbar) }
Hof <- function(y) if (y >= 2023) R15C$frozen_hfa else r15_H(d, y)

# division of every non-FBS team-season (CFBD schedule labels; "fcs" wins when a team carries more than one label)
fs <- as.data.table(readRDS("output/dev/round15/prep/fcs_schedules_2013_2025.rds"))
dv <- unique(rbind(fs[, .(season, team_id = as.integer(home_id), div = tolower(home_division), conf = home_conference)],
                   fs[, .(season, team_id = as.integer(away_id), div = tolower(away_division), conf = away_conference)]))
dv <- dv[, .(div = if (any(div %in% "fcs")) "fcs" else if (all(is.na(div))) "unknown" else paste(sort(unique(na.omit(div))), collapse = "/"),
             conf = if (all(is.na(conf))) NA_character_ else na.omit(conf)[1]), by = .(season, team_id)]
saveRDS(dv, file.path(out, "divisions.rds"))

# power of entity j from a coefficient vector (or matrix of them), centered on the FBS mean as r15_solve2 does
# FCS prior-mean pools by division, per parameter key (training seasons exactly as r15_c2_params)
mu_pool <- function(k, divs = NULL) { tr <- setdiff(2014:min(k - 1L, 2022L), 2020L)
  cur <- merge(rbindlist(c2$eos_full[as.character(tr)])[fcs == TRUE], dv[, .(season, team_id, div)], by = c("season", "team_id"), all.x = TRUE)
  cur[is.na(div), div := "unknown"]; if (!is.null(divs)) cur <- cur[div %in% divs]
  c(off = mean(cur$eff_off), def = mean(cur$eff_def), n = nrow(cur)) }
for (k in c(2017L, 2018L, 2019L, 2021L, 2022L, 2023L)) stopifnot(max(abs(mu_pool(k)[1:2] - c2$p2[[as.character(k)]]$mu)) < 1e-10)
pow <- function(B, nt, ne, j) { B <- as.matrix(B); o <- B[1L + seq_len(ne), , drop = FALSE]; dd <- B[1L + ne + seq_len(ne), , drop = FALSE]
  sweep(o[j, , drop = FALSE], 2, colMeans(o[seq_len(nt), , drop = FALSE])) - sweep(dd[j, , drop = FALSE], 2, colMeans(dd[seq_len(nt), , drop = FALSE])) }

cap_season <- function(y) {
  k <- keyof(y); prior <- c1$priors[[as.character(y)]]; a <- c1$scl[[as.character(k)]]; lam <- lam_of(y, k); H <- Hof(y)
  p2 <- c2$p2[[as.character(k)]]; vbar <- vb(k); lambda0 <- c1$lam0[[key22(y)]]; omega <- c2$om[[key22(y)]]
  ids <- fbs_ids(d$sch[[as.character(y)]]); games <- d$games[[as.character(y)]]; luck <- r15_luck(d, y)
  fcs_all <- setdiff(unique(c(games$home_id, games$away_id)), ids); last <- c2$eos_full[[as.character(y - 1L)]]
  lamf <- c(off = lambda0 * vbar$off / p2$v_fcs[["off"]], def = lambda0 * vbar$def / p2$v_fcs[["def"]])
  lf_all <- last[match(fcs_all, last$team_id)]
  pof_all <- ifelse(is.finite(lf_all$eff_off), p2$mu[["off"]] + p2$rho[["off"]] * (lf_all$eff_off - p2$mu[["off"]]), p2$mu[["off"]])
  pdf_all <- ifelse(is.finite(lf_all$eff_def), p2$mu[["def"]] + p2$rho[["def"]] * (lf_all$eff_def - p2$mu[["def"]]), p2$mu[["def"]])
  # attribution counterfactuals for the prior pool (not candidates): cf1 = FCS-division entities take the FCS-only pool
  # mean, lower divisions unchanged; cf2 = every division takes its own pool mean (D-III and unknown pooled). rho unchanged.
  dall <- dv[season == y][match(fcs_all, team_id), div]; dall[is.na(dall)] <- "unknown"
  mu_f <- mu_pool(k, "fcs"); mu_2 <- mu_pool(k, "ii"); mu_3 <- mu_pool(k, c("iii", "unknown"))
  newmu <- function(side, which) { m <- rep(p2$mu[[side]], length(fcs_all)); m[dall == "fcs"] <- mu_f[[side]]
    if (which == 2) { m[dall == "ii"] <- mu_2[[side]]; m[!dall %in% c("fcs", "ii")] <- mu_3[[side]] }; m }
  dprior <- function(side, which) { lf <- lf_all[[paste0("eff_", side)]]; m1 <- newmu(side, which); m0 <- p2$mu[[side]]
    ifelse(is.finite(lf), (1 - p2$rho[[side]]) * (m1 - m0), m1 - m0) }
  dpo1 <- dprior("off", 1); dpd1 <- dprior("def", 1); dpo2 <- dprior("off", 2); dpd2 <- dprior("def", 2)
  snaps <- Filter(function(sn) sn$season == y, d$base$snap)
  lapply(snaps, function(sn) {
    g <- games[final == TRUE & available_at < sn$cutoff]
    rows <- rbind(g[, .(game_id, team_id = home_id, opp_id = away_id, pf = home_points, hx = ifelse(neutral, 0, 0.5))],
                  g[, .(game_id, team_id = away_id, opp_id = home_id, pf = away_points, hx = ifelse(neutral, 0, -0.5))])
    rows <- merge(rows, luck[, .(game_id, team_id, L)], by = c("game_id", "team_id"), all.x = TRUE); rows[is.na(L), L := 0]
    rows[, `:=`(adj = (p2$kappa / 2) * L, entity = as.character(team_id), opponent = as.character(opp_id))]
    fcs_teams <- intersect(fcs_all, unique(rows$team_id))
    ents <- c(as.character(ids), as.character(fcs_teams)); nt <- length(ids); ne <- length(ents); n <- nrow(rows)
    po <- a * prior$pre_off[match(ids, prior$team_id)]; pd <- a * prior$pre_def[match(ids, prior$team_id)]
    lo <- lam$off[match(ids, prior$team_id)]; ld <- lam$def[match(ids, prior$team_id)]
    fi <- match(fcs_teams, fcs_all)
    po <- c(po, pof_all[fi]); pd <- c(pd, pdf_all[fi]); lo <- c(lo, rep(lamf[["off"]], length(fi))); ld <- c(ld, rep(lamf[["def"]], length(fi)))
    te <- as.data.table(d$base$frame)[season == y & cutoff == sn$cutoff]
    cut <- format(sn$cutoff, "%Y-%m-%d")
    if (!n) {   # r15_solve2's no-games branch: ratings equal the prior
      p <- (po[seq_len(nt)] - mean(po[seq_len(nt)])) - (pd[seq_len(nt)] - mean(pd[seq_len(nt)]))
      fp <- data.table(season = y, cutoff = cut, team_id = fcs_all, div = dall, prior_power_c = (pof_all - mean(po[seq_len(nt)])) - (pdf_all - mean(pd[seq_len(nt)])),
                       d_prior_cf1 = dpo1 - dpd1, d_prior_cf2 = dpo2 - dpd2, in_solve = FALSE)
      return(list(pred = te[, .(season, game_id, cutoff = cut, pred_margin = p[match(home_id, ids)] - p[match(away_id, ids)] + H * !neutral)],
                  ent = NULL, cut = data.table(season = y, cutoff = cut, n_rows = 0L), fcs_prior = fp))
    }
    ti <- match(rows$entity, ents); oi <- match(rows$opponent, ents); stopifnot(!anyNA(ti), !anyNA(oi))
    sr <- r15_sr_rows(d, y, sn$cutoff, p2$beta)[entity %in% ents & opponent %in% ents]
    use_sr <- nrow(sr) > 0 && omega > 0; m <- if (use_sr) nrow(sr) else 0L
    ncol_ <- 1L + 2L * ne + as.integer(use_sr)
    X <- sparseMatrix(i = rep(seq_len(n), 3), j = c(rep(1L, n), 1L + ti, 1L + ne + oi), x = 1, dims = c(n, ncol_))
    ytot <- rows$pf + rows$adj - H * rows$hx; w <- rep(1, n)
    if (use_sr) { si <- match(sr$entity, ents); sj <- match(sr$opponent, ents); stopifnot(!anyNA(si), !anyNA(sj))
      X <- rbind(X, sparseMatrix(i = rep(seq_len(m), 3), j = c(1L + si, 1L + ne + sj, rep(ncol_, m)), x = 1, dims = c(m, ncol_)))
      ytot <- c(ytot, sr$y); w <- c(w, rep(omega, m)) }
    P <- c(0, lo, ld, if (use_sr) 0); Q <- crossprod(X, Diagonal(x = w) %*% X) + Diagonal(x = P)
    prhs <- c(0, lo * po, ld * pd, if (use_sr) 0)
    b <- as.numeric(solve(Q, crossprod(X, w * ytot) + prhs))
    # ---- tie-out against frozen C2 (same arithmetic as r15_solve2 + r15_predict_season_c2)
    o <- b[1L + seq_len(nt)]; dd <- b[1L + ne + seq_len(nt)]; p <- (o - mean(o)) - (dd - mean(dd))
    pred <- te[, .(season, game_id, cutoff = cut, pred_margin = p[match(home_id, ids)] - p[match(away_id, ids)] + H * !neutral)]
    # ---- row classes
    efbs <- rows$team_id %in% ids; ofbs <- rows$opp_id %in% ids
    cls <- fifelse(efbs & ofbs, "ff", fifelse(efbs | ofbs, "link", "nn"))
    srcls <- if (use_sr) fifelse(as.integer(sr$entity) %in% ids & as.integer(sr$opponent) %in% ids, "ff", "link") else character()
    ybar <- mean(rows$pf); srbar <- if (use_sr) mean(sr$y) else 0
    vpt <- function(v, cl = NULL) { z <- numeric(n + m); z[seq_len(n)] <- v; if (!is.null(cl)) z[seq_len(n)][!cls %in% cl] <- 0; z }
    vsr <- function(cl) { z <- numeric(n + m); if (use_sr) { v <- sr$y - srbar; v[!srcls %in% cl] <- 0; z[n + seq_len(m)] <- v }; z }
    Yb <- cbind(pts_ff = vpt(rows$pf - ybar, "ff"), pts_link = vpt(rows$pf - ybar, "link"), pts_nn = vpt(rows$pf - ybar, "nn"),
                luck_ff = vpt(rows$adj, "ff"), luck_link = vpt(rows$adj, "link"), hfa = vpt(-H * rows$hx),
                sr_ff = vsr("ff"), sr_link = vsr("link"))
    Rb <- as.matrix(crossprod(X, Diagonal(x = w) %*% Yb))
    Rp <- cbind(prior_fbs = prhs * c(0, rep(c(rep(1, nt), rep(0, ne - nt)), 2), if (use_sr) 0),
                prior_nonfbs = prhs * c(0, rep(c(rep(0, nt), rep(1, ne - nt)), 2), if (use_sr) 0))
    # level perturbations: t = +1 on every non-FBS offense, -1 on every non-FBS defense (non-FBS power +2)
    tvec <- c(0, rep(c(rep(0, nt), rep(1, ne - nt)), 1), rep(c(rep(0, nt), rep(-1, ne - nt)), 1), if (use_sr) 0)
    zc <- as.numeric(X %*% tvec)                                    # nonzero on linking rows only (points and SR)
    Rl <- cbind(lvl_prior = P * tvec, lvl_data = as.numeric(crossprod(X, w * zc)),
                lvl_data_pts = as.numeric(crossprod(X, w * c(zc[seq_len(n)], rep(0, m)))),
                cf1 = P * c(0, rep(0, nt), dpo1[fi], rep(0, nt), dpd1[fi], if (use_sr) 0),
                cf2 = P * c(0, rep(0, nt), dpo2[fi], rep(0, nt), dpd2[fi], if (use_sr) 0))
    S <- as.matrix(solve(Q, cbind(Rb, Rp, Rl)))
    allj <- seq_len(ne); PW <- pow(cbind(b, S), nt, ne, allj); colnames(PW) <- c("power", colnames(Rb), colnames(Rp), colnames(Rl))
    # free level: the same system plus one unpenalized column z = X t
    nlink <- g[xor(home_id %in% ids, away_id %in% ids), .N]
    dhat <- NA_real_; free_power <- rep(NA_real_, ne)
    if (nlink >= 1) {
      Xa <- cbind(X, zc); Qa <- crossprod(Xa, Diagonal(x = w) %*% Xa) + Diagonal(x = c(P, 0))
      ba <- as.numeric(solve(Qa, crossprod(Xa, w * ytot) + c(prhs, 0))); dhat <- ba[length(ba)]
      free_power <- as.numeric(pow(ba[-length(ba)], nt, ne, allj)) + 2 * dhat * c(rep(0, nt), rep(1, ne - nt))
    }
    # in-sample FBS-margin residual on linking games (model's own y: luck-adjusted, HFA removed)
    res <- (ytot - as.numeric(X %*% b))[seq_len(n)]
    lr <- data.table(game_id = rows$game_id, fbs_row = efbs, cls = cls, r = res)[cls == "link", .(e = sum(r[fbs_row]) - sum(r[!fbs_row])), by = game_id]
    gp <- rows[, .(gp = .N, gp_vs_fbs = sum(opp_id %in% ids)), by = team_id]
    ent <- data.table(season = y, cutoff = cut, team_id = as.integer(ents), fbs = c(rep(TRUE, nt), rep(FALSE, ne - nt)),
                      prior_power_c = (po - mean(o)) - (pd - mean(dd)), as.data.table(PW), free_power = free_power)
    ent <- merge(ent, gp, by = "team_id", all.x = TRUE)[is.na(gp), `:=`(gp = 0L, gp_vs_fbs = 0L)]
    nf <- ne - nt; fcsdiv <- if (nf) dv[season == y][match(as.integer(ents[nt + seq_len(nf)]), team_id), div] %in% "fcs" else logical()
    lvl <- function(col, sel) if (any(sel)) mean(PW[nt + which(sel), col]) / 2 else NA_real_
    cutrow <- data.table(season = y, cutoff = cut, n_rows = n, n_sr = m, n_fbs = nt, n_nonfbs = nf, n_fcsdiv = sum(fcsdiv), n_link_games = nlink,
                         n_nn_games = g[!home_id %in% ids & !away_id %in% ids, .N], H = H, omega = omega, lamf_off = lamf[["off"]], lamf_def = lamf[["def"]],
                         mean_o_fbs = mean(o), mean_d_fbs = mean(dd), mean_prior_fbs_power = mean(po[seq_len(nt)] - pd[seq_len(nt)]),
                         pi_prior_nonfbs = lvl("lvl_prior", rep(TRUE, nf)), pi_prior_fcsdiv = lvl("lvl_prior", fcsdiv),
                         pi_data_fcsdiv = lvl("lvl_data", fcsdiv), pi_data_pts_fcsdiv = lvl("lvl_data_pts", fcsdiv),
                         dhat = dhat, insample_link_resid = if (nrow(lr)) mean(lr$e) else NA_real_, insample_link_games = nrow(lr))
    fp <- data.table(season = y, cutoff = cut, team_id = fcs_all, div = dall, prior_power_c = (pof_all - mean(o)) - (pdf_all - mean(dd)),
                     d_prior_cf1 = dpo1 - dpd1, d_prior_cf2 = dpo2 - dpd2, in_solve = fcs_all %in% fcs_teams)
    list(pred = pred, ent = ent, cut = cutrow, fcs_prior = fp)
  })
}
S <- c(R15C$dev, 2023:2025)
cap <- unlist(lapply(S, function(y) { message("season ", y); cap_season(y) }), recursive = FALSE)
pick <- function(nm) rbindlist(lapply(cap, `[[`, nm), fill = TRUE)
pred <- pick("pred"); ent <- pick("ent"); cuts <- pick("cut"); fcsp <- pick("fcs_prior")

# ---- tie-out 1: frozen C2 predictions
ref <- fread(file.path(R15C$cache, "c2_predictions.csv"), colClasses = list(character = "game_id"))
mm <- merge(pred, ref[, .(game_id, r = pred_margin)], by = "game_id")
chk <- data.table(games = nrow(mm), frozen_games = nrow(ref[season %in% S]), max_abs_diff = max(abs(mm$pred_margin - mm$r)))
print(chk); stopifnot(chk$games == chk$frozen_games, chk$max_abs_diff <= 1e-9)
# ---- tie-out 2: the block decomposition sums to the rating; pi_prior + pi_data = 1
blk <- c("pts_ff", "pts_link", "pts_nn", "luck_ff", "luck_link", "hfa", "sr_ff", "sr_link", "prior_fbs", "prior_nonfbs")
dec_err <- max(abs(ent$power - rowSums(ent[, ..blk])))
lvl_err <- max(abs(cuts$pi_prior_fcsdiv + cuts$pi_data_fcsdiv - 1), na.rm = TRUE)
# ---- tie-out 3: the E0 ratings replay (FCS ratings captured there by source patching)
rr <- fread("output/dev/round15/eval/ratings_replay.csv", colClasses = list(character = "cutoff"))[model == "C2"]
e0 <- merge(ent[, .(season, cutoff, team_id, fbs, power)], rr[, .(season, cutoff, team_id, fbs, rating)], by = c("season", "cutoff", "team_id", "fbs"))
cat(sprintf("decomposition max error %.2e | pi_prior + pi_data - 1 max %.2e | E0 replay rows matched %d of %d, max diff %.2e\n",
            dec_err, lvl_err, nrow(e0), nrow(rr), max(abs(e0$power - e0$rating))))
unm <- fsetdiff(rr[, .(season, cutoff)], e0[, .(season, cutoff)])           # E0 rows not captured here must be no-game cutoffs
stopifnot(dec_err < 1e-8, lvl_err < 1e-8, max(abs(e0$power - e0$rating)) < 1e-8,
          nrow(e0) + rr[unm, on = .(season, cutoff), .N] == nrow(rr), all(cuts[unm, on = .(season, cutoff), n_rows] == 0))

# ---- end-of-season fits (r15_eos_full) with the same free-level column; seasons 2013-2025
eos_diag <- function(s) {
  g <- d$games[[as.character(s)]]; ids <- fbs_ids(d$sch[[as.character(s)]]); rows <- r15_rows(g)
  fcs <- setdiff(unique(c(rows$team_id)), ids); ents <- c(as.character(ids), as.character(fcs)); ne <- length(ents); nt <- length(ids)
  hf <- d$history[season == s, hfa][1]; n <- nrow(rows); ti <- match(rows$entity, ents); oi <- match(rows$opponent, ents)
  X <- sparseMatrix(i = rep(seq_len(n), 3), j = c(rep(1L, n), 1L + ti, 1L + ne + oi), x = 1, dims = c(n, 1L + 2L * ne))
  P <- c(0, rep(1, 2 * ne)); Q <- crossprod(X) + Diagonal(x = P); yy <- rows$pf - hf * rows$hx
  b <- as.numeric(solve(Q, crossprod(X, yy)))
  tvec <- c(0, c(rep(0, nt), rep(1, ne - nt)), c(rep(0, nt), rep(-1, ne - nt))); zc <- as.numeric(X %*% tvec)
  Sl <- as.numeric(solve(Q, P * tvec))
  Xa <- cbind(X, zc); ba <- as.numeric(solve(crossprod(Xa) + Diagonal(x = c(P, 0)), crossprod(Xa, yy))); dh <- ba[length(ba)]
  pw <- as.numeric(pow(b, nt, ne, seq_len(ne))); fpw <- as.numeric(pow(ba[-length(ba)], nt, ne, seq_len(ne))) + 2 * dh * (seq_len(ne) > nt)
  lv <- as.numeric(pow(Sl, nt, ne, seq_len(ne))) / 2
  res <- yy - as.numeric(X %*% b); lk <- xor(rows$team_id %in% ids, rows$opp_id %in% ids)
  lr <- data.table(game_id = rows$game_id, f = rows$team_id %in% ids, r = res)[lk, .(e = sum(r[f]) - sum(r[!f])), by = game_id]
  data.table(season = s, team_id = as.integer(ents), fbs = seq_len(ne) <= nt, power = pw, free_power = fpw, pi_prior = lv, dhat = dh,
             n_link = nrow(lr), insample_link_resid = mean(lr$e))
}
eos <- rbindlist(lapply(2013:2025, eos_diag))
ef <- rbindlist(c2$eos_full)[, .(season, team_id, ref = eff_off - eff_def)]
em <- merge(eos, ef, by = c("season", "team_id")); cat(sprintf("eos replay: %d of %d rows, max diff %.2e\n", nrow(em), nrow(ef), max(abs(em$power - em$ref))))
stopifnot(nrow(em) == nrow(ef), max(abs(em$power - em$ref)) < 1e-8)

pools <- rbindlist(lapply(c(2017L, 2018L, 2019L, 2021L, 2022L, 2023L), function(k) rbindlist(lapply(list(all = NULL, fcs = "fcs", ii = "ii", iii = "iii", unknown = "unknown"),
  function(v) as.list(mu_pool(k, v))), idcol = "pool")[, key := k]))
saveRDS(list(pools = pools, pred = pred, ent = ent, cuts = cuts, fcs_prior = fcsp, eos = eos, checks = list(pred = chk, dec_err = dec_err, lvl_err = lvl_err,
             e0_rows = nrow(e0), e0_max = max(abs(e0$power - e0$rating)), eos_max = max(abs(em$power - em$ref)))), file.path(out, "capture.rds"))
cat("capture saved:", nrow(ent), "entity-cutoff rows,", nrow(cuts), "cutoffs\n")
