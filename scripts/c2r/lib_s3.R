# C2 refinement research, Stage 3 helpers (sourced after lib_c2r.R). A generalized C2 capture whose only freedom is the
# treatment of non-FBS teams (docs/c2r/STAGE3_PLAN.md). With default options it is frozen C2 exactly.
#   opt$shift  : move every non-FBS prior mean down by `shift` power points (G arms)
#   opt$divmu  : division-specific prior pools (FCS / D-II / D-III+unknown) instead of the pooled non-FBS mean
#   opt$level  : add the group-level columns Delta_FCS (all non-FBS, informed by FBS-vs-non-FBS rows) and Delta_low
#                (lower divisions, informed by FCS-vs-lower rows); priors toward the anchors with n0 games' precision
#   opt$kf     : multiply lambda_FCS;  opt$flat: rho = 0 and lambda_FCS x 1e4 (every team at its group level)
#   opt$srlevel: an extra free level column on FBS-vs-non-FBS SR rows only
suppressPackageStartupMessages({ library(data.table); library(Matrix) })
s3_opt <- function(...) modifyList(list(shift = 0, divmu = FALSE, level = FALSE, n0 = 0, anchor_fcs = NA_real_, anchor_gap = NA_real_, kf = 1, flat = FALSE, srlevel = FALSE, lowcol = TRUE), list(...))
s3_div_of <- function(dv, y, ids) { x <- dv[season == y][match(ids, team_id), div]; x[is.na(x)] <- "unknown"; fifelse(x == "fcs", "fcs", fifelse(x == "ii", "ii", "low3")) }
s3_mu_pools <- function(c2, dv, k) { tr <- setdiff(2014:min(k - 1L, 2022L), 2020L)
  cur <- rbindlist(c2$eos_full[as.character(tr)])[fcs == TRUE]; cur[, g := s3_div_of(dv, season[1], team_id), by = season]
  m <- cur[, .(off = mean(eff_off), def = mean(eff_def)), by = g]; setNames(lapply(c("fcs", "ii", "low3"), function(z) c(off = m[g == z, off], def = m[g == z, def])), c("fcs", "ii", "low3")) }

s3_capture <- function(d, y, A, dv, opt, pools = NULL) {
  ids <- fbs_ids(d$sch[[as.character(y)]]); games <- d$games[[as.character(y)]]; luck <- r15_luck(d, y); p2 <- A$p2; H <- A$H
  fcs_all <- setdiff(unique(c(games$home_id, games$away_id)), ids); last <- A$eos_full[[as.character(y - 1L)]]
  kf <- if (opt$flat) 1e4 else opt$kf
  lamf <- kf * c(off = A$lambda0 * A$vbar$off / p2$v_fcs[["off"]], def = A$lambda0 * A$vbar$def / p2$v_fcs[["def"]])
  lf <- last[match(fcs_all, last$team_id)]; grp <- s3_div_of(dv, y, fcs_all)
  mu_o <- if (opt$divmu) vapply(grp, function(g) pools[[g]][["off"]], 0) else rep(p2$mu[["off"]], length(fcs_all))
  mu_d <- if (opt$divmu) vapply(grp, function(g) pools[[g]][["def"]], 0) else rep(p2$mu[["def"]], length(fcs_all))
  ro <- if (opt$flat) 0 else p2$rho[["off"]]; rd <- if (opt$flat) 0 else p2$rho[["def"]]
  pof_all <- ifelse(is.finite(lf$eff_off), mu_o + ro * (lf$eff_off - mu_o), mu_o) - opt$shift / 2
  pdf_all <- ifelse(is.finite(lf$eff_def), mu_d + rd * (lf$eff_def - mu_d), mu_d) + opt$shift / 2
  if (!opt$divmu && !opt$flat) {   # frozen C2 computes the prior with the pooled mu exactly this way
    pof_all <- ifelse(is.finite(lf$eff_off), p2$mu[["off"]] + p2$rho[["off"]] * (lf$eff_off - p2$mu[["off"]]), p2$mu[["off"]]) - opt$shift / 2
    pdf_all <- ifelse(is.finite(lf$eff_def), p2$mu[["def"]] + p2$rho[["def"]] * (lf$eff_def - p2$mu[["def"]]), p2$mu[["def"]]) + opt$shift / 2 }
  isfcs <- grp == "fcs"; islow <- !isfcs
  pofb <- A$a * A$prior$pre_off[match(ids, A$prior$team_id)]; pdfb <- A$a * A$prior$pre_def[match(ids, A$prior$team_id)]
  prior_fbs_level <- mean(pofb - pdfb); prior_level_fcs <- mean((pof_all - pdf_all)[isfcs]) - prior_fbs_level
  prior_gap <- if (any(islow)) mean((pof_all - pdf_all)[islow]) - mean((pof_all - pdf_all)[isfcs]) else 0
  lamL <- 2 * opt$n0 + 1e-4
  mL <- if (opt$level) (opt$anchor_fcs - prior_level_fcs) / 2 else 0; mLow <- if (opt$level && opt$lowcol && any(islow)) (opt$anchor_gap - prior_gap) / 2 else 0
  snaps <- Filter(function(sn) sn$season == y, d$base$snap)
  lapply(snaps, function(sn) {
    g <- games[final == TRUE & available_at < sn$cutoff]; cut <- format(sn$cutoff, "%Y-%m-%d")
    rows <- rbind(g[, .(game_id, team_id = home_id, opp_id = away_id, pf = home_points, hx = ifelse(neutral, 0, 0.5))],
                  g[, .(game_id, team_id = away_id, opp_id = home_id, pf = away_points, hx = ifelse(neutral, 0, -0.5))])
    rows <- merge(rows, luck[, .(game_id, team_id, L)], by = c("game_id", "team_id"), all.x = TRUE); rows[is.na(L), L := 0]
    rows[, `:=`(adj = (p2$kappa / 2) * L, entity = as.character(team_id), opponent = as.character(opp_id))]
    fcs_teams <- intersect(fcs_all, unique(rows$team_id)); ents <- c(as.character(ids), as.character(fcs_teams)); nt <- length(ids); ne <- length(ents); n <- nrow(rows)
    fi <- match(fcs_teams, fcs_all)
    po <- c(pofb, pof_all[fi]); pd <- c(pdfb, pdf_all[fi])
    lo <- c(A$lam$off[match(ids, A$prior$team_id)], rep(lamf[["off"]], length(fi))); ld <- c(A$lam$def[match(ids, A$prior$team_id)], rep(lamf[["def"]], length(fi)))
    te <- as.data.table(d$base$frame)[season == y & cutoff == sn$cutoff]
    fp <- function(o_m, d_m, dL, dLow) data.table(season = y, cutoff = cut, team_id = fcs_all, grp = grp, in_solve = fcs_all %in% fcs_teams,
                                                  first_game_power = (pof_all - o_m) - (pdf_all - d_m) + 2 * dL + 2 * dLow * islow)
    if (!n) { p <- (pofb - mean(pofb)) - (pdfb - mean(pdfb))
      return(list(pred = te[, .(season, game_id, cutoff = cut, pred_margin = p[match(home_id, ids)] - p[match(away_id, ids)] + H * !neutral)],
                  ent = data.table(season = y, cutoff = cut, team_id = ids, fbs = TRUE, grp = "fbs", power = p, gp = 0L, gp_vs_fbs = 0L),
                  cut = data.table(season = y, cutoff = cut, n_rows = 0L, n_link = 0L, dL = mL, dLow = mLow, prior_level_fcs = prior_level_fcs),
                  fcs_prior = fp(mean(pofb), mean(pdfb), mL, mLow))) }
    ti <- match(rows$entity, ents); oi <- match(rows$opponent, ents)
    sr <- if (A$omega > 0) r15_sr_rows(d, y, sn$cutoff, p2$beta)[entity %in% ents & opponent %in% ents] else data.table()
    use_sr <- nrow(sr) > 0 && A$omega > 0; m <- if (use_sr) nrow(sr) else 0L; ncol_ <- 1L + 2L * ne + as.integer(use_sr)
    X <- sparseMatrix(i = rep(seq_len(n), 3), j = c(rep(1L, n), 1L + ti, 1L + ne + oi), x = 1, dims = c(n, ncol_))
    ytot <- rows$pf + rows$adj - H * rows$hx; w <- rep(1, n)
    if (use_sr) { si <- match(sr$entity, ents); sj <- match(sr$opponent, ents)
      X <- rbind(X, sparseMatrix(i = rep(seq_len(m), 3), j = c(1L + si, 1L + ne + sj, rep(ncol_, m)), x = 1, dims = c(m, ncol_))); ytot <- c(ytot, sr$y); w <- c(w, rep(A$omega, m)) }
    P <- c(0, lo, ld, if (use_sr) 0); prhs <- c(0, lo * po, ld * pd, if (use_sr) 0)
    nf <- ne - nt; lowe <- c(rep(FALSE, nt), islow[fi])
    extra <- NULL; pe <- NULL; me <- NULL; nm <- character()
    if (opt$level) {
      tL <- c(0, c(rep(0, nt), rep(1, nf)), c(rep(0, nt), rep(-1, nf)), if (use_sr) 0); tLow <- c(0, as.numeric(lowe), -as.numeric(lowe), if (use_sr) 0)
      extra <- cbind(as.numeric(X %*% tL), as.numeric(X %*% tLow)); pe <- c(lamL, lamL); me <- c(mL, mLow); nm <- c("dL", "dLow")
      if (!opt$lowcol) { extra <- extra[, 1, drop = FALSE]; pe <- lamL; me <- mL; nm <- "dL" } }
    if (opt$srlevel && use_sr) { tS <- c(0, c(rep(0, nt), rep(1, nf)), c(rep(0, nt), rep(-1, nf)), 0); zs <- as.numeric(X %*% tS); zs[seq_len(n)] <- 0
      extra <- cbind(extra, zs); pe <- c(pe, 1e-4); me <- c(me, 0); nm <- c(nm, "dSR") }
    if (!is.null(extra)) { X <- cbind(X, Matrix(extra, sparse = TRUE)); P <- c(P, pe); prhs <- c(prhs, pe * me) }
    Q <- crossprod(X, Diagonal(x = w) %*% X) + Diagonal(x = P)
    b <- as.numeric(solve(Q, crossprod(X, w * ytot) + prhs))
    dL <- if ("dL" %in% nm) b[ncol_ + match("dL", nm)] else 0; dLow <- if ("dLow" %in% nm) b[ncol_ + match("dLow", nm)] else 0
    o <- b[1L + seq_len(ne)]; dd <- b[1L + ne + seq_len(ne)]; mo <- mean(o[seq_len(nt)]); md <- mean(dd[seq_len(nt)])
    pw <- (o - mo) - (dd - md) + c(rep(0, nt), rep(2 * dL, nf)) + 2 * dLow * lowe
    p <- pw[seq_len(nt)]
    pred <- te[, .(season, game_id, cutoff = cut, pred_margin = p[match(home_id, ids)] - p[match(away_id, ids)] + H * !neutral)]
    gp <- rows[, .(gp = .N, gp_vs_fbs = sum(opp_id %in% ids)), by = team_id]
    ent <- data.table(season = y, cutoff = cut, team_id = as.integer(ents), fbs = c(rep(TRUE, nt), rep(FALSE, nf)), grp = c(rep("fbs", nt), grp[fi]), power = pw)
    ent <- merge(ent, gp, by = "team_id", all.x = TRUE)[is.na(gp), `:=`(gp = 0L, gp_vs_fbs = 0L)]
    list(pred = pred, ent = ent, cut = data.table(season = y, cutoff = cut, n_rows = n, n_link = g[xor(home_id %in% ids, away_id %in% ids), .N], dL = dL, dLow = dLow,
                                                  prior_level_fcs = prior_level_fcs, fcs_level = if (any(!lowe[-seq_len(nt)])) mean(pw[nt + which(!islow[fi])]) else NA_real_),
         fcs_prior = fp(mo, md, dL, dLow))
  })
}
s3_capture_all <- function(d, c1, c2, dv, opt, anchors = NULL, seasons = c2r_S) {
  cap <- unlist(lapply(seasons, function(y) { o <- opt
    if (o$level) { a <- anchors[season == y]; stopifnot(nrow(a) == 1); o$anchor_fcs <- a$fcs; o$anchor_gap <- a$gap }
    s3_capture(d, y, c2r_args(d, c1, c2, y), dv, o, if (o$divmu) s3_mu_pools(c2, dv, keyof(y)) else NULL) }), recursive = FALSE)
  pick <- function(nm) rbindlist(lapply(cap, `[[`, nm), fill = TRUE)
  list(pred = pick("pred"), ent = pick("ent"), cuts = pick("cut"), fcs_prior = pick("fcs_prior"))
}

# End-of-season fit (r15_eos_full: points only, penalty 1 on teams, season HFA) with both group levels free; returns team
# power, the FCS-division and lower-division levels and the analytic SE of the FCS level (ridge sandwich).
s3_eos_levels <- function(d, s, dv) {
  g <- d$games[[as.character(s)]]; ids <- fbs_ids(d$sch[[as.character(s)]]); rows <- r15_rows(g)
  fcs <- setdiff(unique(rows$team_id), ids); ents <- c(as.character(ids), as.character(fcs)); ne <- length(ents); nt <- length(ids); nf <- ne - nt
  grp <- s3_div_of(dv, s, fcs); low <- grp != "fcs"
  hf <- d$history[season == s, hfa][1]; n <- nrow(rows); ti <- match(rows$entity, ents); oi <- match(rows$opponent, ents)
  X <- sparseMatrix(i = rep(seq_len(n), 3), j = c(rep(1L, n), 1L + ti, 1L + ne + oi), x = 1, dims = c(n, 1L + 2L * ne))
  tL <- c(0, c(rep(0, nt), rep(1, nf)), c(rep(0, nt), rep(-1, nf))); tLow <- c(0, c(rep(0, nt), as.numeric(low)), c(rep(0, nt), -as.numeric(low)))
  Xa <- cbind(X, as.numeric(X %*% tL), as.numeric(X %*% tLow)); P <- c(0, rep(1, 2 * ne), 1e-4, 1e-4); yy <- rows$pf - hf * rows$hx
  Q <- crossprod(Xa) + Diagonal(x = P); b <- as.numeric(solve(Q, crossprod(Xa, yy)))
  o <- b[1 + seq_len(ne)]; dd <- b[1 + ne + seq_len(ne)]; k <- 2L * ne + 1L
  pw <- (o - mean(o[seq_len(nt)])) - (dd - mean(dd[seq_len(nt)])) + c(rep(0, nt), 2 * b[k + 1] + 2 * b[k + 2] * low)
  cvec <- numeric(ncol(Xa)); jf <- nt + which(!low)   # functional: mean FCS-division power
  cvec[1 + jf] <- 1 / length(jf); cvec[1 + ne + jf] <- -1 / length(jf); cvec[1 + seq_len(nt)] <- cvec[1 + seq_len(nt)] - 1 / nt; cvec[1 + ne + seq_len(nt)] <- cvec[1 + ne + seq_len(nt)] + 1 / nt
  cvec[k + 1] <- 2; v <- as.numeric(solve(Q, cvec)); res <- yy - as.numeric(Xa %*% b); s2 <- sum(res^2) / (n - ncol(Xa) / 2)
  list(teams = data.table(season = s, team_id = as.integer(ents), grp = c(rep("fbs", nt), grp), power = pw),
       level = data.table(season = s, fcs = mean(pw[nt + which(!low)]), gap = if (any(low)) mean(pw[nt + which(low)]) - mean(pw[nt + which(!low)]) else NA_real_,
                          se_fcs = sqrt(s2 * sum(as.numeric(Xa %*% v)^2)), n_fcs = sum(!low), n_low = sum(low), n_link = sum(xor(g$home_id %in% ids, g$away_id %in% ids) & g$final %in% TRUE)))
}
