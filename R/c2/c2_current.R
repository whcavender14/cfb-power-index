# =====================================================================================================================
# Current C2 (integrated post-Stage-4 baseline, tag c2-post-stage4-baseline). Authoritative description:
# docs/c2/C2_CURRENT_SPEC.md. Integration audit: docs/c2/C2_INTEGRATION_PLAN.md.
#
# C2 is a play-by-play-centred opponent-adjusted rating model. At every weekly cutoff it solves ONE ridge regression in
# which each team has an offense and a defense parameter:
#   * points rows  (one per team-game; final score, fumble-luck adjusted, home field removed; weight 1)
#   * SR rows      (one per game x offense; success rate / beta; weight omega; own intercept)
#   * priors       (FBS: C1 preseason prior x scale a, turnover-scaled precision, constant all season;
#                   non-FBS: division pool mean + rho x (last season's rating - pool mean), precision lambda_FCS)
#   * group levels (Stage 3): Delta_FCS moves every non-FBS team relative to FBS and is informed only by FBS-vs-non-FBS
#                   rows; Delta_low moves D-II / D-III / unknown teams relative to FCS and is informed only by
#                   FCS-vs-lower rows. Each has a ridge prior worth 20 games centred on last season's measured level.
# Ratings are centred on the FBS mean. Everything not listed as Stage 3 is the frozen Round 15 C2 unchanged; the frozen
# helpers (R/round15/candidates/*.R, never modified) are reused read-only.
#
# Frozen reference implementation (historical, untouched): R/round15/candidates/c2.R :: r15_predict_season_c2
# ("C2_frozen_round15"). The research arm this reproduces: scripts/c2r/lib_s3.R, arm L_last_n20 ("C2L").
# Requires (sourced by the caller): config/paths.R, config/production.R, PATHS$model_ops, R/round15/candidates/{data,c1,c2}.R
# =====================================================================================================================
suppressPackageStartupMessages({ library(data.table); library(Matrix) })

C2_SPEC <- list(
  version            = "c2-post-stage4-baseline",
  seasons            = c(2017L, 2018L, 2019L, 2021L, 2022L, 2023L, 2024L, 2025L),
  level_prior_games  = 20,     # Stage 3 (selected n0): each group level's prior precision = 2 * games (+ ridge floor)
  level_ridge_floor  = 1e-4,   # keeps the solve defined; with no informative rows a level equals its prior mean
  anchor_rule        = "last", # Stage 3 (selected): the latest season before the target, 2020 excluded
  anchor_excluded    = 2020L,  # 22 FCS teams, 36 linking games: not a usable level measurement
  eos_team_penalty   = 1       # end-of-season anchor fits: r15_eos_full's team penalty, both group levels free
)

# ---- construction inputs ---------------------------------------------------------------------------------------------
c2_key <- function(y) if (y >= 2023) 2023L else y                    # parameter key (2023-25 use parameters through 2022)
c2_key22 <- function(k) as.character(if (k >= 2023) 2022 else k)     # lambda0 / omega key
c2_H <- function(d, y) if (y >= 2023) R15C$frozen_hfa else r15_H(d, y)

# Division of every non-FBS team-season from the CFBD FCS-involved schedules ("fcs" wins when a team has several labels).
c2_divisions <- function(fcs_schedules) {
  fs <- as.data.table(fcs_schedules)
  dv <- unique(rbind(fs[, .(season, team_id = as.integer(home_id), div = tolower(home_division), conf = home_conference)],
                     fs[, .(season, team_id = as.integer(away_id), div = tolower(away_division), conf = away_conference)]))
  dv[, .(div = if (any(div %in% "fcs")) "fcs" else if (all(is.na(div))) "unknown" else paste(sort(unique(na.omit(div))), collapse = "/"),
         conf = if (all(is.na(conf))) NA_character_ else na.omit(conf)[1]), by = .(season, team_id)]
}
# Model group of a non-FBS team: "fcs", "ii" (D-II) or "low3" (D-III and unknown, pooled). Missing labels are "low3".
c2_group_of <- function(dv, y, ids) { x <- dv[season == y][match(ids, team_id), div]; x[is.na(x)] <- "unknown"
  fifelse(x == "fcs", "fcs", fifelse(x == "ii", "ii", "low3")) }
# Division prior pools (Stage 3): mean end-of-season offense/defense of each group over the key's training seasons
# (the same window as the frozen pooled mu: 2014 .. min(key-1, 2022), 2020 excluded).
c2_division_pools <- function(eos_full, dv, key) {
  tr <- setdiff(2014:min(key - 1L, 2022L), 2020L)
  cur <- rbindlist(eos_full[as.character(tr)])[fcs == TRUE]; cur[, g := c2_group_of(dv, season[1], team_id), by = season]
  m <- cur[, .(off = mean(eff_off), def = mean(eff_def)), by = g]
  setNames(lapply(c("fcs", "ii", "low3"), function(z) c(off = m[g == z, off], def = m[g == z, def])), c("fcs", "ii", "low3"))
}
# End-of-season fit of season s with both group levels free: the historical measurement the anchors are built from.
c2_eos_levels <- function(d, s, dv) {
  g <- d$games[[as.character(s)]]; ids <- fbs_ids(d$sch[[as.character(s)]]); rows <- r15_rows(g)
  fcs <- setdiff(unique(rows$team_id), ids); ents <- c(as.character(ids), as.character(fcs)); ne <- length(ents); nt <- length(ids); nf <- ne - nt
  low <- c2_group_of(dv, s, fcs) != "fcs"
  hf <- d$history[season == s, hfa][1]; n <- nrow(rows); ti <- match(rows$entity, ents); oi <- match(rows$opponent, ents)
  X <- sparseMatrix(i = rep(seq_len(n), 3), j = c(rep(1L, n), 1L + ti, 1L + ne + oi), x = 1, dims = c(n, 1L + 2L * ne))
  tL <- c(0, c(rep(0, nt), rep(1, nf)), c(rep(0, nt), rep(-1, nf))); tLow <- c(0, c(rep(0, nt), as.numeric(low)), c(rep(0, nt), -as.numeric(low)))
  Xa <- cbind(X, as.numeric(X %*% tL), as.numeric(X %*% tLow))
  P <- c(0, rep(C2_SPEC$eos_team_penalty, 2 * ne), C2_SPEC$level_ridge_floor, C2_SPEC$level_ridge_floor)
  b <- as.numeric(solve(crossprod(Xa) + Diagonal(x = P), crossprod(Xa, rows$pf - hf * rows$hx)))
  o <- b[1 + seq_len(ne)]; dd <- b[1 + ne + seq_len(ne)]; k <- 2L * ne + 1L
  pw <- (o - mean(o[seq_len(nt)])) - (dd - mean(dd[seq_len(nt)])) + c(rep(0, nt), 2 * b[k + 1] + 2 * b[k + 2] * low)
  data.table(season = s, fcs = mean(pw[nt + which(!low)]), gap = if (any(low)) mean(pw[nt + which(low)]) - mean(pw[nt + which(!low)]) else NA_real_)
}
# Anchors for each target season: the latest available season before it (2020 excluded), FCS level and lower gap.
c2_anchors <- function(levels, targets) {
  h <- levels[season != C2_SPEC$anchor_excluded]
  rbindlist(lapply(targets, function(y) { la <- tail(h[season < y][order(season)], 1); stopifnot(nrow(la) == 1)
    data.table(season = y, anchor_season = la$season, fcs = la$fcs, gap = la$gap) }))
}
# Everything C2 needs for season y. Frozen construction outputs (C1: prior, scale, lambda; C2: beta, kappa, FCS moments,
# omega, end-of-season fits) plus the Stage 3 inputs (division pools, anchors, divisions).
c2_season_inputs <- function(d, c1, c2, y, dv, anchors) {
  k <- c2_key(y); pr <- c1$priors[[as.character(y)]]; v <- c1$varm[[as.character(k)]]
  list(prior = pr, a = c1$scl[[as.character(k)]], lam = r15_c1_lambda(pr, v, c1$lam0[[c2_key22(k)]]), H = c2_H(d, y), p2 = c2$p2[[as.character(k)]],
       vbar = list(off = v$off$vbar, def = v$def$vbar), lambda0 = c1$lam0[[c2_key22(y)]], eos_full = c2$eos_full, omega = c2$om[[c2_key22(y)]],
       pools = c2_division_pools(c2$eos_full, dv, k), anchor = anchors[season == y], dv = dv)
}

# ---- the ridge core ----------------------------------------------------------------------------------------------------
# Solves C2's system at one cutoff. `groups` is a list of group-level columns, each list(member = logical over ents,
# mean, precision): the column is X t with t = +1 on members' offense and -1 on members' defense, so it moves every
# member's power by 2 x coefficient and is informed only by rows between members and non-members. The frozen Round 15
# system is the special case groups = list() (tests/c2/test_c2_regression.R). Returns centred FBS-normalized ratings.
c2_ridge_solve <- function(rows, sr, ents, nt, po, pd, lo, ld, H, omega, groups = list(), keep_system = FALSE) {
  ne <- length(ents); n <- nrow(rows); ti <- match(rows$entity, ents); oi <- match(rows$opponent, ents); stopifnot(!anyNA(ti), !anyNA(oi))
  use_sr <- !is.null(sr) && nrow(sr) > 0 && omega > 0; m <- if (use_sr) nrow(sr) else 0L; ncol_ <- 1L + 2L * ne + as.integer(use_sr)
  X <- sparseMatrix(i = rep(seq_len(n), 3), j = c(rep(1L, n), 1L + ti, 1L + ne + oi), x = 1, dims = c(n, ncol_))
  y <- rows$pf + rows$adj - H * rows$hx; w <- rep(1, n)
  if (use_sr) { si <- match(sr$entity, ents); sj <- match(sr$opponent, ents); stopifnot(!anyNA(si), !anyNA(sj))
    X <- rbind(X, sparseMatrix(i = rep(seq_len(m), 3), j = c(1L + si, 1L + ne + sj, rep(ncol_, m)), x = 1, dims = c(m, ncol_))); y <- c(y, sr$y); w <- c(w, rep(omega, m)) }
  P <- c(0, lo, ld, if (use_sr) 0); rhs_p <- c(0, lo * po, ld * pd, if (use_sr) 0)
  if (length(groups)) {
    Z <- sapply(groups, function(gr) as.numeric(X %*% c(0, as.numeric(gr$member), -as.numeric(gr$member), if (use_sr) 0)))
    X <- cbind(X, Matrix(matrix(Z, ncol = length(groups)), sparse = TRUE))
    pg <- vapply(groups, `[[`, 0, "precision"); P <- c(P, pg); rhs_p <- c(rhs_p, pg * vapply(groups, `[[`, 0, "mean")) }
  Q <- crossprod(X, Diagonal(x = w) %*% X) + Diagonal(x = P)
  b <- as.numeric(solve(Q, crossprod(X, w * y) + rhs_p))
  gcoef <- if (length(groups)) b[ncol_ + seq_along(groups)] else numeric()
  o <- b[1L + seq_len(ne)]; dd <- b[1L + ne + seq_len(ne)]; mo <- mean(o[seq_len(nt)]); md <- mean(dd[seq_len(nt)])
  shift <- if (length(groups)) Reduce(`+`, Map(function(gr, cf) cf * as.numeric(gr$member), groups, gcoef)) else rep(0, ne)
  out <- list(eff_off = (o - mo) + shift, eff_def = (dd - md) - shift, group_coef = gcoef, o_mean = mo, d_mean = md)
  out$power <- out$eff_off - out$eff_def
  if (keep_system) out$system <- list(Q = Q, P = P, lo = lo, ld = ld, po = po, pd = pd, nt = nt, ne = ne, use_sr = use_sr)
  out
}

# ---- one season --------------------------------------------------------------------------------------------------------
# Weekly C2 for season y. Returns predictions (frozen schema), ratings of every entity, the solved group levels, and the
# first-game rating of every non-FBS team not yet in the solve (its prior deviation + the current group levels).
c2_predict_season <- function(d, y, S, keep_system = FALSE) {
  ids <- fbs_ids(d$sch[[as.character(y)]]); games <- d$games[[as.character(y)]]; luck <- r15_luck(d, y); p2 <- S$p2; H <- S$H
  nonfbs <- setdiff(unique(c(games$home_id, games$away_id)), ids); grp <- c2_group_of(S$dv, y, nonfbs); low <- grp != "fcs"
  last <- S$eos_full[[as.character(y - 1L)]][match(nonfbs, S$eos_full[[as.character(y - 1L)]]$team_id)]
  mu_o <- vapply(grp, function(g) S$pools[[g]][["off"]], 0); mu_d <- vapply(grp, function(g) S$pools[[g]][["def"]], 0)
  pof <- ifelse(is.finite(last$eff_off), mu_o + p2$rho[["off"]] * (last$eff_off - mu_o), mu_o)      # non-FBS prior means
  pdf <- ifelse(is.finite(last$eff_def), mu_d + p2$rho[["def"]] * (last$eff_def - mu_d), mu_d)
  lamf <- c(off = S$lambda0 * S$vbar$off / p2$v_fcs[["off"]], def = S$lambda0 * S$vbar$def / p2$v_fcs[["def"]])
  pofb <- S$a * S$prior$pre_off[match(ids, S$prior$team_id)]; pdfb <- S$a * S$prior$pre_def[match(ids, S$prior$team_id)]   # FBS prior means
  lofb <- S$lam$off[match(ids, S$prior$team_id)]; ldfb <- S$lam$def[match(ids, S$prior$team_id)]
  # group-level prior means: put the FCS-division mean power at the anchor and the lower-minus-FCS gap at the anchored gap
  prior_level_fcs <- mean((pof - pdf)[!low]) - mean(pofb - pdfb)
  prior_gap <- if (any(low)) mean((pof - pdf)[low]) - mean((pof - pdf)[!low]) else 0
  lamL <- 2 * C2_SPEC$level_prior_games + C2_SPEC$level_ridge_floor
  mL <- (S$anchor$fcs - prior_level_fcs) / 2; mLow <- if (any(low)) (S$anchor$gap - prior_gap) / 2 else 0
  frame <- as.data.table(d$base$frame)[season == y]
  snaps <- Filter(function(sn) sn$season == y, d$base$snap)
  lapply(snaps, function(sn) {
    cut <- format(sn$cutoff, "%Y-%m-%d"); g <- games[final == TRUE & available_at < sn$cutoff]; te <- frame[cutoff == sn$cutoff]
    first_game <- function(o_m, d_m, dL, dLow) data.table(season = y, cutoff = cut, team_id = nonfbs, group = grp,
      power = (pof - o_m) - (pdf - d_m) + 2 * dL + 2 * dLow * low)
    if (!nrow(g)) {   # no game yet: every rating is its prior (frozen C2's no-games branch); levels sit at their prior means
      p <- (pofb - mean(pofb)) - (pdfb - mean(pdfb))
      return(list(pred = te[, .(season, game_id, cutoff = cut, neutral, home_id, away_id, pred_margin = p[match(home_id, ids)] - p[match(away_id, ids)] + H * !neutral)],
                  ratings = data.table(season = y, cutoff = cut, team_id = ids, fbs = TRUE, group = "fbs", eff_off = pofb - mean(pofb), eff_def = pdfb - mean(pdfb), power = p, gp = 0L),
                  levels = data.table(season = y, cutoff = cut, n_games = 0L, n_link = 0L, delta_fcs = mL, delta_low = mLow, fcs_level = NA_real_),
                  first_game = first_game(mean(pofb), mean(pdfb), mL, mLow)))
    }
    rows <- rbind(g[, .(game_id, team_id = home_id, opp_id = away_id, pf = home_points, hx = ifelse(neutral, 0, 0.5))],
                  g[, .(game_id, team_id = away_id, opp_id = home_id, pf = away_points, hx = ifelse(neutral, 0, -0.5))])
    rows <- merge(rows, luck[, .(game_id, team_id, L)], by = c("game_id", "team_id"), all.x = TRUE); rows[is.na(L), L := 0]
    rows[, `:=`(adj = (p2$kappa / 2) * L, entity = as.character(team_id), opponent = as.character(opp_id))]
    fi <- match(intersect(nonfbs, unique(rows$team_id)), nonfbs)   # non-FBS teams with a game: entities
    ents <- c(as.character(ids), as.character(nonfbs[fi])); nt <- length(ids); nf <- length(fi)
    sr <- if (S$omega > 0) r15_sr_rows(d, y, sn$cutoff, p2$beta)[entity %in% ents & opponent %in% ents] else NULL
    groups <- list(fcs = list(member = c(rep(FALSE, nt), rep(TRUE, nf)), mean = mL, precision = lamL),
                   low = list(member = c(rep(FALSE, nt), low[fi]), mean = mLow, precision = lamL))
    fit <- c2_ridge_solve(rows, sr, ents, nt, c(pofb, pof[fi]), c(pdfb, pdf[fi]), c(lofb, rep(lamf[["off"]], nf)), c(ldfb, rep(lamf[["def"]], nf)),
                          H, S$omega, groups, keep_system)
    p <- fit$power[seq_len(nt)]; gpc <- rows[, .N, by = team_id]
    ratings <- data.table(season = y, cutoff = cut, team_id = as.integer(ents), fbs = c(rep(TRUE, nt), rep(FALSE, nf)), group = c(rep("fbs", nt), grp[fi]),
                          eff_off = fit$eff_off, eff_def = fit$eff_def, power = fit$power)
    ratings[, gp := gpc$N[match(team_id, gpc$team_id)]][is.na(gp), gp := 0L]
    list(pred = te[, .(season, game_id, cutoff = cut, neutral, home_id, away_id, pred_margin = p[match(home_id, ids)] - p[match(away_id, ids)] + H * !neutral)],
         ratings = ratings,
         levels = data.table(season = y, cutoff = cut, n_games = nrow(g), n_link = g[xor(home_id %in% ids, away_id %in% ids), .N], delta_fcs = fit$group_coef[1], delta_low = fit$group_coef[2],
                             fcs_level = if (any(!low[fi])) mean(fit$power[nt + which(!low[fi])]) else NA_real_),
         first_game = first_game(fit$o_mean, fit$d_mean, fit$group_coef[1], fit$group_coef[2]),
         system = if (keep_system) fit$system else NULL)
  })
}

# ---- driver ----------------------------------------------------------------------------------------------------------
# Runs current C2 for `seasons`. c1 / c2: the frozen construction components (output/dev/round15/cand/c{1,2}_components.rds).
c2_run <- function(d, c1, c2, dv, seasons = C2_SPEC$seasons, keep_system = FALSE) {
  levels <- rbindlist(lapply(2013:max(seasons), function(s) c2_eos_levels(d, s, dv)))
  anchors <- c2_anchors(levels, seasons)
  res <- unlist(lapply(seasons, function(y) c2_predict_season(d, y, c2_season_inputs(d, c1, c2, y, dv, anchors), keep_system)), recursive = FALSE)
  pick <- function(nm) rbindlist(lapply(res, `[[`, nm), fill = TRUE)
  out <- list(pred = pick("pred"), ratings = pick("ratings"), levels = pick("levels"), first_game = pick("first_game"), anchors = anchors, eos_levels = levels)
  if (keep_system) out$system <- lapply(res, `[[`, "system")
  out
}

# FBS-vs-non-FBS predictions (Stage 3): at the latest cutoff before kickoff; the non-FBS team's in-solve rating, or before
# its first game its first-game rating. Margins are home-oriented (pred_margin) and FBS-oriented (pred_fbs_margin).
c2_fbs_vs_nonfbs <- function(d, run, seasons = C2_SPEC$seasons) {
  snaps <- unique(rbindlist(lapply(d$base$snap, function(sn) data.table(season = sn$season, cutoff = format(sn$cutoff, "%Y-%m-%d"), ct = sn$cutoff))))
  snaps <- snaps[!duplicated(snaps[, .(season, cutoff)])]; setorder(snaps, season, ct)
  g <- rbindlist(lapply(seasons, function(y) { x <- d$games[[as.character(y)]][xor(home_fbs %in% TRUE, away_fbs %in% TRUE)]
    cs <- snaps[season == y]; x[, ci := findInterval(as.numeric(kickoff), as.numeric(cs$ct))]; x <- x[ci >= 1]
    x[, .(season, game_id, kickoff, final, neutral = as.logical(neutral), home_id, away_id, fbs_home = home_fbs %in% TRUE, cutoff = cs$cutoff[ci],
          fbs_id = fifelse(home_fbs %in% TRUE, home_id, away_id), nonfbs_id = fifelse(home_fbs %in% TRUE, away_id, home_id),
          actual_fbs_margin = fifelse(home_fbs %in% TRUE, home_points - away_points, away_points - home_points))] }))
  g[, H := vapply(season, function(y) c2_H(d, y), 0)]
  r <- run$ratings; g <- merge(g, r[fbs == TRUE, .(season, cutoff, fbs_id = team_id, fbs_power = power)], by = c("season", "cutoff", "fbs_id"))
  g <- merge(g, r[fbs == FALSE, .(season, cutoff, nonfbs_id = team_id, nf_in = power)], by = c("season", "cutoff", "nonfbs_id"), all.x = TRUE)
  g <- merge(g, run$first_game[, .(season, cutoff, nonfbs_id = team_id, nf_first = power, group)], by = c("season", "cutoff", "nonfbs_id"))
  g[, `:=`(first_game = !is.finite(nf_in), nonfbs_power = fifelse(is.finite(nf_in), nf_in, nf_first))]
  g[, pred_fbs_margin := fbs_power - nonfbs_power + H * (!neutral) * fifelse(fbs_home, 1, -1)][, pred_margin := fifelse(fbs_home, pred_fbs_margin, -pred_fbs_margin)]
  g[, c("nf_in", "nf_first") := NULL][]
}

# Games played before each cutoff, counting ALL final games (FBS and non-FBS opponents). Evaluation/reporting helper
# (Stage 4 correction of R15's frame gp); the rating system itself never reads a games-played count.
c2_games_played <- function(d, seasons = C2_SPEC$seasons) {
  rbindlist(lapply(seasons, function(y) { g <- d$games[[as.character(y)]][final == TRUE]
    tg <- rbind(g[, .(team_id = home_id, available_at)], g[, .(team_id = away_id, available_at)])
    cs <- unique(vapply(Filter(function(sn) sn$season == y, d$base$snap), function(sn) format(sn$cutoff, "%Y-%m-%d %H:%M:%S"), ""))
    rbindlist(lapply(cs, function(ct) { t <- as.POSIXct(ct, tz = "UTC"); tg[available_at < t, .(gp = .N), by = team_id][, `:=`(season = y, cutoff = substr(ct, 1, 10))] })) }))
}
