# C2 refinement research: shared helpers (sourced from the round15-power-rating worktree root after the Round 15 candidate
# code). They rebuild C1/C2 with the frozen construction procedure on a substituted data object, and capture C2's solved
# system at every cutoff. Nothing here writes to the Round 15 caches.
suppressPackageStartupMessages({ library(data.table); library(Matrix) })
C2R <- "/Users/willcavender/Desktop/Revised CFB Modeling/.claude/worktrees/c2-refinement"
key22 <- function(k) as.character(if (k >= 2023) 2022 else k); keyof <- function(y) if (y >= 2023) 2023L else y   # E0's keys
c2r_S <- c(2017L, 2018L, 2019L, 2021L, 2022L, 2023L, 2024L, 2025L)
nkey <- function(x) gsub("[^A-Za-z0-9 &().'-]", "", iconv(x, "", "ASCII", sub = ""))

# Data object with the play-derived SR inputs of one treatment substituted: game x offense SR (in place, frozen row order;
# rows with SR only under the treatment are appended) and the end-of-season SR table (frozen team strings kept).
c2r_substitute_sr <- function(d, srT) {
  x <- copy(d); p <- copy(x$pbp)[, rid := .I]
  m <- srT$means[season >= 2014, .(season, game_id, offense, defense, sr_t = sr, sp_t = sr_plays)]
  p <- merge(p, m, by = c("season", "game_id", "offense", "defense"), all = TRUE)
  p[, `:=`(sr = sr_t, sr_plays = sp_t)][, c("sr_t", "sp_t") := NULL]
  setorder(p, rid, na.last = TRUE); p[, rid := NULL]; setattr(p, "sorted", NULL); setcolorder(p, intersect(names(x$pbp), names(p))); x$pbp <- p
  e <- copy(x$sr_eos)[, k := nkey(team)]; ef <- copy(srT$eff)[, k := nkey(team)]
  e[ef, on = .(season, k), `:=`(sr_off = i.sr_off, sr_def = i.sr_def, games_played = i.games_played)]
  stopifnot(nrow(e) == nrow(ef), !anyNA(e$sr_off)); e[, k := NULL]; x$sr_eos <- e
  x
}

# C1 components by the frozen construction procedure (scripts/round15/c1_build.R), without writing anything.
c2r_build_c1 <- function(d) {
  e <- r15_bind_incumbent(); Z <- c(2016L, 2017L, 2018L, 2019L, 2021L, 2022L); priors <- list()
  for (z in c(Z, 2023L)) priors[[as.character(z)]] <- r15_c1_prior(d, z, min(z - 1L, 2022L), e)
  for (z in 2024:2025) priors[[as.character(z)]] <- r15_c1_prior(d, z, 2022L, e)
  varm <- list(); for (z in c(Z[-1], 2023L)) varm[[as.character(z)]] <- r15_c1_variance(d, z, priors)
  varm[["2016"]] <- list(off = list(b = 0, train_means = c(a = NA, b = NA, c = NA, d = NA), vbar = NA), def = list(b = 0, train_means = c(a = NA, c = NA, d = NA), vbar = NA))
  scl <- sapply(c(Z, 2023L), function(z) r15_scale(d, z, priors, if (z >= 2023) R15C$frozen_hfa else r15_H(d, z))); names(scl) <- c(Z, 2023L)
  grid <- c(2, 3, 4, 6, 8, 12)
  inner <- rbindlist(lapply(Z, function(z) rbindlist(lapply(grid, function(v) {
    lam <- r15_c1_lambda(priors[[as.character(z)]], varm[[as.character(z)]], v)
    r15_predict_season_c1(d, z, priors[[as.character(z)]], scl[[as.character(z)]], lam, r15_H(d, z))[, grid_value := v] }))))
  sel <- r15_select(inner, d, grid, nesting = 4, targets = c(2017L, 2018L, 2019L, 2021L, 2022L))
  list(priors = priors, varm = varm, scl = scl, lam0 = setNames(c(4, sel$selected), c("2016", sel$target)), sel = sel)
}
c2r_lam <- function(c1, z, key = z) r15_c1_lambda(c1$priors[[as.character(z)]], c1$varm[[as.character(key)]], c1$lam0[[key22(key)]])
c2r_vb <- function(c1, z) { v <- c1$varm[[as.character(z)]]; list(off = v$off$vbar, def = v$def$vbar) }
c2r_H <- function(d, y) if (y >= 2023) R15C$frozen_hfa else r15_H(d, y)
c2r_predict_c1 <- function(d, c1) rbindlist(lapply(c2r_S, function(y) { k <- keyof(y)
  r15_predict_season_c1(d, y, c1$priors[[as.character(y)]], c1$scl[[as.character(k)]], c2r_lam(c1, y, k), c2r_H(d, y)) }))

# C2 components by the frozen construction procedure (scripts/round15/c2_build.R); eos_full is points-only and reused.
c2r_build_c2 <- function(d, c1, eos_full) {
  Z <- c(2016L, 2017L, 2018L, 2019L, 2021L, 2022L)
  p2 <- setNames(lapply(c(Z, 2023L), function(z) r15_c2_params(d, z, eos_full)), c(Z, 2023L))
  grid <- c(0, 0.25, 0.5, 1, 2)
  inner <- rbindlist(lapply(Z, function(z) rbindlist(lapply(grid, function(v) {
    om <- if (isTRUE(p2[[as.character(z)]]$beta_ok)) v else 0
    r15_predict_season_c2(d, z, c1$priors[[as.character(z)]], c1$scl[[as.character(z)]], c2r_lam(c1, z), r15_H(d, z), p2[[as.character(z)]], c2r_vb(c1, z),
                          c1$lam0[[as.character(z)]], eos_full, om)[, grid_value := v] }))))
  sel <- r15_select(inner, d, grid, nesting = 0, targets = R15C$dev)
  sel[, selected := mapply(function(t, s) if (isTRUE(p2[[as.character(t)]]$beta_ok)) s else 0, target, selected)]
  list(p2 = p2, om = setNames(c(0, sel$selected), c("2016", sel$target)), eos_full = eos_full, sel = sel)
}
# The per-season C2 argument set used by the frozen predictions and the E0 replay.
c2r_args <- function(d, c1, c2, y) { k <- keyof(y)
  list(prior = c1$priors[[as.character(y)]], a = c1$scl[[as.character(k)]], lam = c2r_lam(c1, y, k), H = c2r_H(d, y), p2 = c2$p2[[as.character(k)]],
       vbar = c2r_vb(c1, k), lambda0 = c1$lam0[[key22(y)]], eos_full = c2$eos_full, omega = c2$om[[key22(y)]]) }

# Capture one season of C2: predictions (must equal r15_predict_season_c2), every entity's power and its exact block
# decomposition, level pass-through, in-sample linking residuals of the points and SR rows, and every non-FBS prior mean.
c2r_capture <- function(d, y, A, dv) {
  ids <- fbs_ids(d$sch[[as.character(y)]]); games <- d$games[[as.character(y)]]; luck <- r15_luck(d, y); p2 <- A$p2; H <- A$H
  fcs_all <- setdiff(unique(c(games$home_id, games$away_id)), ids); last <- A$eos_full[[as.character(y - 1L)]]
  lamf <- c(off = A$lambda0 * A$vbar$off / p2$v_fcs[["off"]], def = A$lambda0 * A$vbar$def / p2$v_fcs[["def"]])
  lf_all <- last[match(fcs_all, last$team_id)]
  pof_all <- ifelse(is.finite(lf_all$eff_off), p2$mu[["off"]] + p2$rho[["off"]] * (lf_all$eff_off - p2$mu[["off"]]), p2$mu[["off"]])
  pdf_all <- ifelse(is.finite(lf_all$eff_def), p2$mu[["def"]] + p2$rho[["def"]] * (lf_all$eff_def - p2$mu[["def"]]), p2$mu[["def"]])
  dall <- dv[season == y][match(fcs_all, team_id), div]; dall[is.na(dall)] <- "unknown"
  pow <- function(B, nt, ne) { B <- as.matrix(B); o <- B[1L + seq_len(ne), , drop = FALSE]; dd <- B[1L + ne + seq_len(ne), , drop = FALSE]
    sweep(o, 2, colMeans(o[seq_len(nt), , drop = FALSE])) - sweep(dd, 2, colMeans(dd[seq_len(nt), , drop = FALSE])) }
  snaps <- Filter(function(sn) sn$season == y, d$base$snap)
  lapply(snaps, function(sn) {
    g <- games[final == TRUE & available_at < sn$cutoff]; cut <- format(sn$cutoff, "%Y-%m-%d")
    rows <- rbind(g[, .(game_id, team_id = home_id, opp_id = away_id, pf = home_points, hx = ifelse(neutral, 0, 0.5))],
                  g[, .(game_id, team_id = away_id, opp_id = home_id, pf = away_points, hx = ifelse(neutral, 0, -0.5))])
    rows <- merge(rows, luck[, .(game_id, team_id, L)], by = c("game_id", "team_id"), all.x = TRUE); rows[is.na(L), L := 0]
    rows[, `:=`(adj = (p2$kappa / 2) * L, entity = as.character(team_id), opponent = as.character(opp_id))]
    fcs_teams <- intersect(fcs_all, unique(rows$team_id)); ents <- c(as.character(ids), as.character(fcs_teams)); nt <- length(ids); ne <- length(ents); n <- nrow(rows)
    po <- A$a * A$prior$pre_off[match(ids, A$prior$team_id)]; pd <- A$a * A$prior$pre_def[match(ids, A$prior$team_id)]
    lo <- A$lam$off[match(ids, A$prior$team_id)]; ld <- A$lam$def[match(ids, A$prior$team_id)]; fi <- match(fcs_teams, fcs_all)
    po <- c(po, pof_all[fi]); pd <- c(pd, pdf_all[fi]); lo <- c(lo, rep(lamf[["off"]], length(fi))); ld <- c(ld, rep(lamf[["def"]], length(fi)))
    te <- as.data.table(d$base$frame)[season == y & cutoff == sn$cutoff]
    if (!n) { p <- (po[seq_len(nt)] - mean(po[seq_len(nt)])) - (pd[seq_len(nt)] - mean(pd[seq_len(nt)]))
      return(list(pred = te[, .(season, game_id, cutoff = cut, pred_margin = p[match(home_id, ids)] - p[match(away_id, ids)] + H * !neutral)],
                  ent = data.table(season = y, cutoff = cut, team_id = ids, fbs = TRUE, power = p, gp = 0L, gp_vs_fbs = 0L), cut = data.table(season = y, cutoff = cut, n_rows = 0L),
                  fcs_prior = data.table(season = y, cutoff = cut, team_id = fcs_all, div = dall, prior_power_c = (pof_all - mean(po[seq_len(nt)])) - (pdf_all - mean(pd[seq_len(nt)])), in_solve = FALSE))) }
    ti <- match(rows$entity, ents); oi <- match(rows$opponent, ents); stopifnot(!anyNA(ti), !anyNA(oi))
    sr <- if (A$omega > 0) r15_sr_rows(d, y, sn$cutoff, p2$beta)[entity %in% ents & opponent %in% ents] else data.table()
    use_sr <- nrow(sr) > 0 && A$omega > 0; m <- if (use_sr) nrow(sr) else 0L; ncol_ <- 1L + 2L * ne + as.integer(use_sr)
    X <- sparseMatrix(i = rep(seq_len(n), 3), j = c(rep(1L, n), 1L + ti, 1L + ne + oi), x = 1, dims = c(n, ncol_))
    ytot <- rows$pf + rows$adj - H * rows$hx; w <- rep(1, n)
    if (use_sr) { si <- match(sr$entity, ents); sj <- match(sr$opponent, ents)
      X <- rbind(X, sparseMatrix(i = rep(seq_len(m), 3), j = c(1L + si, 1L + ne + sj, rep(ncol_, m)), x = 1, dims = c(m, ncol_))); ytot <- c(ytot, sr$y); w <- c(w, rep(A$omega, m)) }
    P <- c(0, lo, ld, if (use_sr) 0); Q <- crossprod(X, Diagonal(x = w) %*% X) + Diagonal(x = P); prhs <- c(0, lo * po, ld * pd, if (use_sr) 0)
    b <- as.numeric(solve(Q, crossprod(X, w * ytot) + prhs))
    o <- b[1L + seq_len(nt)]; dd <- b[1L + ne + seq_len(nt)]; p <- (o - mean(o)) - (dd - mean(dd))
    pred <- te[, .(season, game_id, cutoff = cut, pred_margin = p[match(home_id, ids)] - p[match(away_id, ids)] + H * !neutral)]
    efbs <- rows$team_id %in% ids; ofbs <- rows$opp_id %in% ids; cls <- fifelse(efbs & ofbs, "ff", fifelse(efbs | ofbs, "link", "nn"))
    srcls <- if (use_sr) fifelse(as.integer(sr$entity) %in% ids & as.integer(sr$opponent) %in% ids, "ff", "link") else character()
    ybar <- mean(rows$pf); srbar <- if (use_sr) mean(sr$y) else 0
    vpt <- function(v, cl = NULL) { z <- numeric(n + m); z[seq_len(n)] <- v; if (!is.null(cl)) z[seq_len(n)][!cls %in% cl] <- 0; z }
    vsr <- function(cl) { z <- numeric(n + m); if (use_sr) { v <- sr$y - srbar; v[!srcls %in% cl] <- 0; z[n + seq_len(m)] <- v }; z }
    Yb <- cbind(pts_ff = vpt(rows$pf - ybar, "ff"), pts_link = vpt(rows$pf - ybar, "link"), pts_nn = vpt(rows$pf - ybar, "nn"), luck = vpt(rows$adj), hfa = vpt(-H * rows$hx),
                sr_ff = vsr("ff"), sr_link = vsr("link"))
    Rp <- cbind(prior_fbs = prhs * c(0, rep(c(rep(1, nt), rep(0, ne - nt)), 2), if (use_sr) 0), prior_nonfbs = prhs * c(0, rep(c(rep(0, nt), rep(1, ne - nt)), 2), if (use_sr) 0))
    tvec <- c(0, c(rep(0, nt), rep(1, ne - nt)), c(rep(0, nt), rep(-1, ne - nt)), if (use_sr) 0)
    Sm <- as.matrix(solve(Q, cbind(as.matrix(crossprod(X, Diagonal(x = w) %*% Yb)), Rp, lvl_prior = P * tvec)))
    PW <- pow(cbind(b, Sm), nt, ne); colnames(PW) <- c("power", colnames(Yb), colnames(Rp), "lvl_prior")
    res <- ytot - as.numeric(X %*% b)
    lr <- data.table(game_id = rows$game_id, f = efbs, r = res[seq_len(n)])[cls == "link", .(e = sum(r[f]) - sum(r[!f]), k = .N), by = game_id][k == 2]
    srr <- if (use_sr) data.table(game_id = sr$game_id, f = as.integer(sr$entity) %in% ids, cl = srcls, r = res[n + seq_len(m)]) else data.table(game_id = character(), f = logical(), cl = character(), r = numeric())
    slr <- srr[cl == "link", .(e = sum(r[f]) - sum(r[!f]), k = .N), by = game_id][k == 2]
    gp <- rows[, .(gp = .N, gp_vs_fbs = sum(opp_id %in% ids)), by = team_id]
    ent <- data.table(season = y, cutoff = cut, team_id = as.integer(ents), fbs = c(rep(TRUE, nt), rep(FALSE, ne - nt)), prior_power_c = (po - mean(o)) - (pd - mean(dd)), as.data.table(PW))
    ent <- merge(ent, gp, by = "team_id", all.x = TRUE)[is.na(gp), `:=`(gp = 0L, gp_vs_fbs = 0L)]
    fcsdiv <- if (ne > nt) dall[fi] == "fcs" else logical()
    cutrow <- data.table(season = y, cutoff = cut, n_rows = n, n_sr = m, n_link_games = g[xor(home_id %in% ids, away_id %in% ids), .N], omega = A$omega, beta = p2$beta,
                         pi_prior_fcsdiv = if (any(fcsdiv)) mean(PW[nt + which(fcsdiv), "lvl_prior"]) / 2 else NA_real_,
                         pts_link_resid = if (nrow(lr)) mean(lr$e) else NA_real_, sr_link_resid = if (nrow(slr)) mean(slr$e) else NA_real_, n_sr_link_games = nrow(slr),
                         sr_ff_resid_sd = if (use_sr) sd(srr[cl == "ff", r]) else NA_real_)
    fp <- data.table(season = y, cutoff = cut, team_id = fcs_all, div = dall, prior_power_c = (pof_all - mean(o)) - (pdf_all - mean(dd)), in_solve = fcs_all %in% fcs_teams)
    list(pred = pred, ent = ent, cut = cutrow, fcs_prior = fp)
  })
}
c2r_capture_all <- function(d, c1, c2, dv) {
  cap <- unlist(lapply(c2r_S, function(y) c2r_capture(d, y, c2r_args(d, c1, c2, y), dv)), recursive = FALSE)
  pick <- function(nm) rbindlist(lapply(cap, `[[`, nm), fill = TRUE)
  list(pred = pick("pred"), ent = pick("ent"), cuts = pick("cut"), fcs_prior = pick("fcs_prior"))
}
