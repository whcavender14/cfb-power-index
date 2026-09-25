# Round 15 Candidate 3 (predeclaration v2 §5.4): C2 + within-season random walk (q per week, shared by offense and defense)
# + a one-time offensive variance allowance q_QB after a detected QB change. Solved exactly as the equivalent penalized
# system over period-specific strengths (the filtered state at a cutoff equals the last period's solution given data
# before that cutoff). Units: ridge units (score rows weight 1 <=> observation variance sigma2_row).
suppressPackageStartupMessages(library(data.table))

# sigma2_row as-of target y: pooled residual variance of FBS-vs-FBS score rows in end-of-season penalty-1 fits of seasons
# 2014 .. min(y-1, 2022) (2020 excluded), times n/(n - p).
r15_sigma2_row <- function(d, y) {
  tr <- setdiff(2014:min(y - 1L, 2022L), 2020L); ssr <- 0; n <- 0; p <- 0
  for (s in tr) { g <- d$sch[[as.character(s)]]; ids <- fbs_ids(g); hf <- d$history[season == s, hfa][1]
    tg <- team_games(g, ids, 0); f <- v4_score_fit(tg, ids, lambda = 1, hfa = hf)
    # fitted rows need the unpenalized intercept: recover it as mean(y - o - d)
    y <- tg$pf - hf * tg$hx; oe <- f$eff_off[match(tg$team_id, f$team_id)]; de <- f$eff_def[match(tg$opp_id, f$team_id)]
    mu <- mean(y - oe - de); r <- y - mu - oe - de
    ssr <- ssr + sum(r^2); n <- n + length(r); p <- p + 1 + 2 * length(ids) }
  ssr / n * n / (n - p)
}
# QB-change events (Amendment 02): a game whose primary passer differs from the team's primary passer in its preceding
# game (the most recent earlier game of the season with a primary). Co-primaries (a tie for the game's most dropbacks)
# differ only if the two games share no primary passer. Repeats of the same primary never re-trigger; the first game with
# a primary is not an event. Needs d$qb from r15_qb_primary().
r15_qb_events <- function(d, y) {
  stopifnot(!is.null(d$qb))
  g <- d$games[[as.character(y)]][final == TRUE, .(game_id, kickoff, available_at)]
  nm <- r15_all_names(d, y)
  q <- merge(d$qb[season == y, .(game_id, team = offense, primary)], g, by = "game_id")
  q <- merge(q, nm, by = "team")[order(team_id, kickoff)]
  q[, event := {
    s <- strsplit(primary, "|", fixed = TRUE)
    c(FALSE, vapply(seq_len(.N)[-1], function(k) !length(intersect(s[[k]], s[[k - 1L]])), logical(1))) }, by = team_id]
  q[event == TRUE, .(team_id, game_id, available_at)]
}

# One cutoff: period-specific strengths for periods 1..K (period k = data with available_at in [t_{k-1}, t_k)).
r15_solve3 <- function(rows, sr, ids, ents, po, pd, lo, ld, H, omega, cuts, k_now, q, qqb, qb_ev, s2) {
  ne <- length(ents); nt <- length(ids); K <- k_now
  per <- function(t) findInterval(as.numeric(t), as.numeric(cuts)) + 1L      # period of an availability time: 1 = before the first cutoff
  collapse <- q == 0 && (qqb == 0 || !nrow(qb_ev))
  np <- if (collapse) 1L else K
  pidx <- function(k) if (collapse) 1L else pmax(1L, pmin(K, k))
  col_o <- function(e, k) 2L + (pidx(k) - 1L) * 2L * ne + e                 # 1 = mu, 2 = SR intercept
  col_d <- function(e, k) 2L + (pidx(k) - 1L) * 2L * ne + ne + e
  ncol_ <- 2L + np * 2L * ne
  if (!nrow(rows)) { o <- po[seq_len(nt)]; dd <- pd[seq_len(nt)]; return(data.table(team_id = ids, eff_off = o - mean(o), eff_def = dd - mean(dd))) }
  ti <- match(rows$entity, ents); oi <- match(rows$opponent, ents); kk <- per(rows$available_at); n <- nrow(rows)
  I <- c(seq_len(n), seq_len(n), seq_len(n)); J <- c(rep(1L, n), col_o(ti, kk), col_d(oi, kk)); y <- rows$pf - H * rows$hx; w <- rep(1, n)
  use_sr <- !is.null(sr) && nrow(sr) > 0 && omega > 0
  if (use_sr) { m <- nrow(sr); si <- match(sr$entity, ents); sj <- match(sr$opponent, ents); sk <- per(sr$available_at)
    I <- c(I, n + seq_len(m), n + seq_len(m), n + seq_len(m)); J <- c(J, rep(2L, m), col_o(si, sk), col_d(sj, sk)); y <- c(y, sr$y); w <- c(w, rep(omega, m)) }
  X <- sparseMatrix(i = I, j = J, x = 1, dims = c(length(y), ncol_))
  keep <- if (use_sr) seq_len(ncol_) else setdiff(seq_len(ncol_), 2L)
  X <- X[, keep, drop = FALSE]
  Q <- crossprod(X, Diagonal(x = w) %*% X); rhs <- as.numeric(crossprod(X, w * y))
  pos <- function(cc) match(cc, keep)
  # prior on period-1 strengths
  pc_o <- pos(col_o(seq_len(ne), 1L)); pc_d <- pos(col_d(seq_len(ne), 1L))
  Q <- Q + sparseMatrix(i = c(pc_o, pc_d), j = c(pc_o, pc_d), x = c(lo, ld), dims = dim(Q)); rhs[pc_o] <- rhs[pc_o] + lo * po; rhs[pc_d] <- rhs[pc_d] + ld * pd
  if (!collapse && K > 1) {
    dw <- diff(as.numeric(cuts[seq_len(K)])) / (7 * 86400)                 # weeks between cutoffs k-1 -> k
    ii <- c(); jj <- c(); xx <- c()
    for (k in 2:K) { v_o <- rep(q * dw[k - 1], ne); v_d <- v_o
      if (qqb > 0 && nrow(qb_ev)) { hit <- unique(as.character(qb_ev$team_id[per(qb_ev$available_at) == k - 1])); v_o[ents %in% hit] <- v_o[ents %in% hit] + qqb }
      for (side in 1:2) { v <- if (side == 1) v_o else v_d; pen <- ifelse(v > 0, s2 / v, 1e12)
        a <- pos(if (side == 1) col_o(seq_len(ne), k - 1L) else col_d(seq_len(ne), k - 1L)); b <- pos(if (side == 1) col_o(seq_len(ne), k) else col_d(seq_len(ne), k))
        ii <- c(ii, a, b, a, b); jj <- c(jj, a, b, b, a); xx <- c(xx, pen, pen, -pen, -pen) } }
    Q <- Q + sparseMatrix(i = ii, j = jj, x = xx, dims = dim(Q))
  }
  b <- as.numeric(solve(Q, rhs))
  o <- b[pos(col_o(seq_len(nt), K))]; dd <- b[pos(col_d(seq_len(nt), K))]
  data.table(team_id = ids, eff_off = o - mean(o), eff_def = dd - mean(dd))
}

r15_predict_season_c3 <- function(d, z, prior, a, lam, H, p2, vbar, lambda0, eos_full, omega, q, qqb, s2) {
  ids <- fbs_ids(d$sch[[as.character(z)]]); games <- d$games[[as.character(z)]]; luck <- r15_luck(d, z)
  fcs_all <- setdiff(unique(c(games$home_id, games$away_id)), ids); last <- eos_full[[as.character(z - 1L)]]
  lamf <- if (is.null(vbar) || anyNA(unlist(vbar))) c(off = lambda0, def = lambda0) else c(off = lambda0 * vbar$off / p2$v_fcs[["off"]], def = lambda0 * vbar$def / p2$v_fcs[["def"]])
  snaps <- Filter(function(sn) sn$season == z, d$base$snap); cuts <- do.call(c, lapply(snaps, `[[`, "cutoff"))
  qb_ev <- if (qqb > 0) r15_qb_events(d, z) else data.table(team_id = integer(), game_id = character(), available_at = as.POSIXct(character()))
  rbindlist(lapply(seq_along(snaps), function(k) { sn <- snaps[[k]]
    rows <- r15_rows(games, sn$cutoff, luck, p2$kappa)
    fcs_teams <- intersect(fcs_all, unique(rows$team_id)); ents <- c(as.character(ids), as.character(fcs_teams))
    po <- a * prior$pre_off[match(ids, prior$team_id)]; pd <- a * prior$pre_def[match(ids, prior$team_id)]
    lo <- lam$off[match(ids, prior$team_id)]; ld <- lam$def[match(ids, prior$team_id)]
    if (length(fcs_teams)) { lf <- last[match(fcs_teams, last$team_id)]
      po <- c(po, ifelse(is.finite(lf$eff_off), p2$mu[["off"]] + p2$rho[["off"]] * (lf$eff_off - p2$mu[["off"]]), p2$mu[["off"]]))
      pd <- c(pd, ifelse(is.finite(lf$eff_def), p2$mu[["def"]] + p2$rho[["def"]] * (lf$eff_def - p2$mu[["def"]]), p2$mu[["def"]]))
      lo <- c(lo, rep(lamf[["off"]], length(fcs_teams))); ld <- c(ld, rep(lamf[["def"]], length(fcs_teams))) }
    sr <- if (omega > 0) { s <- r15_sr_rows(d, z, sn$cutoff, p2$beta); s <- merge(s, games[, .(game_id, available_at)], by = "game_id"); s[entity %in% ents & opponent %in% ents] } else NULL
    stopifnot(all(rows$available_at < sn$cutoff))
    ev <- if (nrow(qb_ev)) qb_ev[available_at < sn$cutoff] else qb_ev
    ef <- r15_solve3(rows, sr, ids, ents, po, pd, lo, ld, H, omega, cuts, k, q, qqb, ev, s2)
    p <- ef$eff_off - ef$eff_def
    te <- as.data.table(d$base$frame)[season == z & cutoff == sn$cutoff]
    te[, .(season, game_id, cutoff = format(cutoff, "%Y-%m-%d"), neutral, home_id, away_id,
           pred_margin = p[match(home_id, ef$team_id)] - p[match(away_id, ef$team_id)] + H * !neutral)] }))
}
