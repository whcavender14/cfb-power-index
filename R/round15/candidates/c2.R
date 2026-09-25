# Round 15 Candidate 2 (predeclaration v2 §5.3): C1 + success-rate measurement rows + FCS teams as parameters + fumble luck.
# The solver mirrors v4_score_fit line for line; with no SR rows, no FCS teams and no luck it builds the identical system.
suppressPackageStartupMessages(library(data.table))

# Team-game points rows from a full games table (FBS and FCS), optionally before a cutoff, with fumble-luck adjustment.
r15_rows <- function(games, cutoff = NULL, luck = NULL, kappa = 0, fbs_only = FALSE) {
  g <- games[final == TRUE]
  if (fbs_only) g <- g[home_fbs & away_fbs]
  if (!is.null(cutoff)) g <- g[available_at < cutoff]
  r <- rbind(g[, .(game_id, available_at, team_id = home_id, opp_id = away_id, pf = home_points, hx = ifelse(neutral, 0, 0.5))],
             g[, .(game_id, available_at, team_id = away_id, opp_id = home_id, pf = away_points, hx = ifelse(neutral, 0, -0.5))])
  if (!is.null(luck) && kappa != 0) {
    r <- merge(r, luck[, .(game_id, team_id, L)], by = c("game_id", "team_id"), all.x = TRUE)
    r[is.na(L), L := 0][, pf := pf + (kappa / 2) * L][, L := NULL]
  }
  r[, `:=`(entity = as.character(team_id), opponent = as.character(opp_id))][]
}
# Fumble luck per team-game: L_A = (lost_A - 0.5 fum_A) - (lost_B - 0.5 fum_B); games without play-by-play get L = 0.
r15_luck <- function(d, y) {
  g <- d$games[[as.character(y)]][final == TRUE]; nm <- r15_all_names(d, y)
  p <- d$pbp[season == y & !is.na(fumbles), .(game_id, team = offense, x = lost - 0.5 * fumbles)]
  p <- merge(p, nm, by = "team")
  a <- merge(g[, .(game_id, home_id, away_id)], p[, .(game_id, home_id = team_id, xh = x)], by = c("game_id", "home_id"), all.x = TRUE)
  a <- merge(a, p[, .(game_id, away_id = team_id, xa = x)], by = c("game_id", "away_id"), all.x = TRUE)
  a[is.na(xh), xh := 0][is.na(xa), xa := 0]
  rbind(a[, .(game_id, team_id = home_id, L = xh - xa)], a[, .(game_id, team_id = away_id, L = xa - xh)])
}
r15_all_names <- function(d, y) { g <- d$games[[as.character(y)]]
  unique(rbind(data.table(team = g$home_team, team_id = g$home_id), data.table(team = g$away_team, team_id = g$away_id)))[!duplicated(team)] }
# SR rows: game x offense success rate, mapped to points by 1/beta (alpha is absorbed by the SR-row intercept).
r15_sr_rows <- function(d, y, cutoff, beta) {
  g <- d$games[[as.character(y)]][final == TRUE & available_at < cutoff, .(game_id, available_at)]
  nm <- r15_all_names(d, y)
  s <- d$pbp[season == y & !is.na(sr) & game_id %in% g$game_id, .(game_id, off = offense, def = defense, sr)]
  s <- merge(merge(s, nm[, .(off = team, off_id = team_id)], by = "off"), nm[, .(def = team, def_id = team_id)], by = "def")
  s[, .(game_id, entity = as.character(off_id), opponent = as.character(def_id), y = sr / beta)]
}

# Ridge solve (v4_score_fit arithmetic) with optional SR rows (weight omega, own unpenalized intercept) and per-entity priors.
r15_solve2 <- function(rows, ids, ents, po, pd, lo, ld, hfa, sr = NULL, omega = 0) {
  nt <- length(ids); ne <- length(ents); n <- nrow(rows)
  if (!n) { o <- po[seq_len(nt)]; dd <- pd[seq_len(nt)]   # v4_score_fit's no-games branch: ratings equal the prior
    return(data.table(team_id = ids, eff_off = o - mean(o), eff_def = dd - mean(dd))) }
  ti <- match(rows$entity, ents); oi <- match(rows$opponent, ents)
  stopifnot(!anyNA(ti), !anyNA(oi))
  use_sr <- !is.null(sr) && nrow(sr) > 0 && omega > 0
  ncol_ <- 1L + 2L * ne + as.integer(use_sr)
  X <- sparseMatrix(i = rep(seq_len(n), 3), j = c(rep(1L, n), 1L + ti, 1L + ne + oi), x = 1, dims = c(n, ncol_))
  y <- rows$pf - hfa * rows$hx; w <- rep(1, n)
  if (use_sr) {
    m <- nrow(sr); si <- match(sr$entity, ents); sj <- match(sr$opponent, ents); stopifnot(!anyNA(si), !anyNA(sj))
    X <- rbind(X, sparseMatrix(i = rep(seq_len(m), 3), j = c(1L + si, 1L + ne + sj, rep(ncol_, m)), x = 1, dims = c(m, ncol_)))
    y <- c(y, sr$y); w <- c(w, rep(omega, m))
  }
  P <- c(0, lo, ld, if (use_sr) 0); Q <- crossprod(X, Diagonal(x = w) %*% X) + Diagonal(x = P)
  b <- as.numeric(solve(Q, crossprod(X, w * y) + c(0, lo * po, ld * pd, if (use_sr) 0)))
  o <- b[1L + seq_len(nt)]; dd <- b[1L + ne + seq_len(nt)]
  data.table(team_id = ids, eff_off = o - mean(o), eff_def = dd - mean(dd))
}

# End-of-season fit of season s over FBS and FCS teams (penalty 1, season HFA), centered over FBS.
r15_eos_full <- function(d, s) {
  g <- d$games[[as.character(s)]]; ids <- fbs_ids(d$sch[[as.character(s)]]); rows <- r15_rows(g)
  fcs <- setdiff(unique(c(rows$team_id)), ids); ents <- c(as.character(ids), as.character(fcs)); ne <- length(ents)
  hf <- d$history[season == s, hfa][1]
  n <- nrow(rows); ti <- match(rows$entity, ents); oi <- match(rows$opponent, ents)
  X <- sparseMatrix(i = rep(seq_len(n), 3), j = c(rep(1L, n), 1L + ti, 1L + ne + oi), x = 1, dims = c(n, 1L + 2L * ne))
  Q <- crossprod(X) + Diagonal(x = c(0, rep(1, 2 * ne))); b <- as.numeric(solve(Q, crossprod(X, rows$pf - hf * rows$hx)))
  o <- b[1 + seq_len(ne)]; dd <- b[1 + ne + seq_len(ne)]; mo <- mean(o[seq_along(ids)]); md <- mean(dd[seq_along(ids)])
  data.table(season = s, team_id = as.integer(ents), fcs = !ents %in% as.character(ids), eff_off = o - mo, eff_def = dd - md)
}

# C2 nuisance parameters as-of target y (training seasons 2014 .. min(y-1, 2022), 2020 never a response).
r15_c2_params <- function(d, y, eos_full) {
  tr <- setdiff(2014:min(y - 1L, 2022L), 2020L)
  # beta: pooled OLS of game SR on end-of-season (o_A + d_B), FBS-vs-FBS game-offense rows
  b <- rbindlist(lapply(tr, function(s) { nm <- r15_all_names(d, s); h <- d$history[season == s]
    p <- d$pbp[season == s & !is.na(sr)]; p <- merge(merge(p, nm[, .(offense = team, oid = team_id)], by = "offense"), nm[, .(defense = team, did = team_id)], by = "defense")
    p <- merge(merge(p, h[, .(oid = team_id, o = eff_off)], by = "oid"), h[, .(did = team_id, dd = eff_def)], by = "did"); p[, .(sr, x = o + dd)] }))
  fb <- if (nrow(b) >= 1000) coef(lm(sr ~ x, b)) else c(NA, NA)
  beta <- unname(fb[2]); beta_ok <- nrow(b) >= 1000 && is.finite(beta) && beta > 0
  # kappa: joint end-of-season points regression over training seasons with season-specific effects (penalty 1) and one
  # unpenalized coefficient on -L/2 per team-game row
  blocks <- lapply(tr, function(s) { g <- d$games[[as.character(s)]]; ids <- fbs_ids(d$sch[[as.character(s)]])
    r <- r15_rows(g, fbs_only = TRUE); r <- merge(r, r15_luck(d, s), by = c("game_id", "team_id"), all.x = TRUE); r[is.na(L), L := 0]
    list(r = r, ents = as.character(ids), hf = d$history[season == s, hfa][1]) })
  cols <- 0L; Xs <- list(); ys <- list(); pen <- c()
  for (bl in blocks) { ne <- length(bl$ents); n <- nrow(bl$r); ti <- match(bl$r$entity, bl$ents); oi <- match(bl$r$opponent, bl$ents)
    Xs[[length(Xs) + 1]] <- list(i = rep(seq_len(n), 3), j = cols + c(rep(1L, n), 1L + ti, 1L + ne + oi), n = n, xk = -bl$r$L / 2)
    ys[[length(ys) + 1]] <- bl$r$pf - bl$hf * bl$r$hx; pen <- c(pen, 0, rep(1, 2 * ne)); cols <- cols + 1L + 2L * ne }
  N <- sum(vapply(Xs, `[[`, 0L, "n")); off <- cumsum(c(0L, vapply(Xs, `[[`, 0L, "n")))
  X <- sparseMatrix(i = c(unlist(lapply(seq_along(Xs), function(k) Xs[[k]]$i + off[k])), seq_len(N)),
                    j = c(unlist(lapply(Xs, `[[`, "j")), rep(cols + 1L, N)), x = c(rep(1, 3 * N), unlist(lapply(Xs, `[[`, "xk"))), dims = c(N, cols + 1L))
  Q <- crossprod(X) + Diagonal(x = c(pen, 0)); kappa <- as.numeric(solve(Q, crossprod(X, unlist(ys))))[cols + 1L]
  # FCS moments from end-of-season fits (FBS and FCS teams)
  ef <- rbindlist(eos_full[as.character(c(min(tr) - 1L, tr))])
  cur <- ef[fcs == TRUE & season %in% tr]
  mu <- c(off = mean(cur$eff_off), def = mean(cur$eff_def))
  pr <- merge(cur, ef[fcs == TRUE, .(season = season + 1L, team_id, lo = eff_off, ld = eff_def)], by = c("season", "team_id"))
  rho <- c(off = unname(coef(lm(I(eff_off - mu["off"]) ~ 0 + I(lo - mu["off"]), pr))), def = unname(coef(lm(I(eff_def - mu["def"]) ~ 0 + I(ld - mu["def"]), pr))))
  v <- c(off = var(pr$eff_off - mu["off"] - rho["off"] * (pr$lo - mu["off"])), def = var(pr$eff_def - mu["def"] - rho["def"] * (pr$ld - mu["def"])))
  list(beta = beta, beta_ok = beta_ok, beta_rows = nrow(b), kappa = kappa, mu = mu, rho = rho, v_fcs = v)
}

# Weekly C2 predictions of season z.
r15_predict_season_c2 <- function(d, z, prior, a, lam, H, p2, vbar, lambda0, eos_full, omega, use_fcs = TRUE, use_luck = TRUE) {
  ids <- fbs_ids(d$sch[[as.character(z)]]); games <- d$games[[as.character(z)]]
  luck <- if (use_luck) r15_luck(d, z) else NULL
  fcs_all <- setdiff(unique(c(games$home_id, games$away_id)), ids)
  last <- eos_full[[as.character(z - 1L)]]
  lamf <- if (is.null(vbar) || anyNA(unlist(vbar))) c(off = lambda0, def = lambda0) else c(off = lambda0 * vbar$off / p2$v_fcs[["off"]], def = lambda0 * vbar$def / p2$v_fcs[["def"]])
  snaps <- Filter(function(sn) sn$season == z, d$base$snap)
  rbindlist(lapply(snaps, function(sn) {
    rows <- r15_rows(games, sn$cutoff, luck, if (use_luck) p2$kappa else 0, fbs_only = !use_fcs)
    fcs_teams <- if (use_fcs) intersect(fcs_all, unique(rows$team_id)) else integer()
    ents <- c(as.character(ids), as.character(fcs_teams))
    po <- a * prior$pre_off[match(ids, prior$team_id)]; pd <- a * prior$pre_def[match(ids, prior$team_id)]
    lo <- lam$off[match(ids, prior$team_id)]; ld <- lam$def[match(ids, prior$team_id)]
    if (length(fcs_teams)) { lf <- last[match(fcs_teams, last$team_id)]  # `last` has a column named fcs: index explicitly
      po <- c(po, ifelse(is.finite(lf$eff_off), p2$mu[["off"]] + p2$rho[["off"]] * (lf$eff_off - p2$mu[["off"]]), p2$mu[["off"]]))
      pd <- c(pd, ifelse(is.finite(lf$eff_def), p2$mu[["def"]] + p2$rho[["def"]] * (lf$eff_def - p2$mu[["def"]]), p2$mu[["def"]]))
      lo <- c(lo, rep(lamf[["off"]], length(fcs_teams))); ld <- c(ld, rep(lamf[["def"]], length(fcs_teams))) }
    sr <- if (omega > 0) { s <- r15_sr_rows(d, z, sn$cutoff, p2$beta); s[entity %in% ents & opponent %in% ents] } else NULL
    stopifnot(all(rows$available_at < sn$cutoff))
    ef <- r15_solve2(rows, ids, ents, po, pd, lo, ld, H, sr, omega)
    p <- ef$eff_off - ef$eff_def
    te <- as.data.table(d$base$frame)[season == z & cutoff == sn$cutoff]
    te[, .(season, game_id, cutoff = format(cutoff, "%Y-%m-%d"), neutral, home_id, away_id,
           pred_margin = p[match(home_id, ef$team_id)] - p[match(away_id, ef$team_id)] + H * !neutral)]
  }))
}
