# Round 15 Candidate 1 (predeclaration v2 §5.2): information-rich preseason prior, turnover-scaled prior precision,
# the incumbent's in-season solve (v4_score_fit, FBS-vs-FBS points rows). Every quantity for season z is as-of z (§6.1).
suppressPackageStartupMessages(library(data.table))
R15_TERMS <- list(
  off = c("last_off", "last_def", "two_off", "two_def", "last_sr_off", "last_sr_def", "cont_pass", "cont_skill", "cp_x_lo", "cs_x_lo",
          "qb_xfer_in", "talent4", "bluechip4", "new_hc", "log_tenure", "conf_off", "promoted"),
  def = c("last_off", "last_def", "two_off", "two_def", "last_sr_off", "last_sr_def", "cont_def", "cd_x_ld",
          "talent4", "bluechip4", "new_hc", "log_tenure", "conf_def", "promoted"))
R15_RIDGE_GRID <- c(0.01, 0.03, 0.1, 0.3, 1, 3, 10)
R15_MIN_ROWS <- 80L

# Same arithmetic as the incumbent's v5_prepare/v5_ridge; the guard whitelists the predeclared Round 15 terms instead of the
# incumbent's, and keeps the incumbent's market and outcome checks.
r15_matrix_guard <- function(f, terms) {
  v5_no_market(f)
  assert(all(terms %in% unique(unlist(R15_TERMS))), "Forbidden Round 15 feature matrix predictor")
  assert(!any(grepl("^(games|wins|losses|ties|win_percentage|preseason_rank|postseason_rank|srs|sp_|epa|ppa|actual_margin|home_points|away_points)|elo", names(f))), "Outcome or vendor column in feature matrix")
}
r15_prepare <- function(tr, terms) {
  r15_matrix_guard(tr[, intersect(c("season", "team_id", terms), names(tr)), drop = FALSE], terms)
  d <- prepare_design(tr, terms); X <- d$X; mu <- colMeans(X); ss <- apply(X, 2, sd); mu["intercept"] <- 0; ss["intercept"] <- 1
  ss[!is.finite(ss) | ss == 0] <- 1; d$mu <- mu; d$sd <- ss; d$X <- sweep(sweep(X, 2, mu, "-"), 2, ss, "/"); d
}
r15_ridge <- function(tr, terms, target, lambda) {
  d <- r15_prepare(tr, terms); X <- d$X; y <- tr[[target]]; p <- rep(lambda, ncol(X)); p[1] <- 0
  list(design = d, beta = as.numeric(solve(crossprod(X) / nrow(X) + diag(p, ncol(X)), crossprod(X, y) / nrow(X))), lambda = lambda, n = nrow(tr))
}

r15_ids <- function(d, y) fbs_ids(d$sch[[as.character(y)]])
r15_name_to_id <- function(d, y) { g <- d$sch[[as.character(y)]]; unique(rbind(data.table(team = g$home_team, team_id = g$home_id), data.table(team = g$away_team, team_id = g$away_id))) }

# Predictor frame for season y (all inputs known before y), plus the end-of-season response of y when it exists.
r15_prior_frame <- function(d, y) {
  x <- d$inputs[season == y]
  sr <- merge(d$sr_eos[season == y - 1, .(team, last_sr_off = sr_off, last_sr_def = sr_def)], r15_name_to_id(d, y - 1), by = "team")[, .(team_id, last_sr_off, last_sr_def)]
  x <- merge(x, sr[!duplicated(team_id)], by = "team_id", all.x = TRUE)
  x[, `:=`(cp_x_lo = cont_pass * last_off, cs_x_lo = cont_skill * last_off, cd_x_ld = cont_def * last_def)]
  resp <- d$history[season == y, .(team_id, eff_off, eff_def)]
  x <- merge(x, resp, by = "team_id", all.x = TRUE)
  x[team_id %in% r15_ids(d, y)]
}

# C1 prior as-of target y (training rows: team-seasons 2014 .. min(y-1, max_train), 2020 never a response).
r15_c1_prior <- function(d, y, max_train = min(y - 1L, 2022L), e = NULL) {
  if (is.null(e)) e <- r15_bind_incumbent()
  ids <- r15_ids(d, y); f <- as.data.frame(r15_prior_frame(d, y)); f <- f[match(ids, f$team_id), ]
  tr <- as.data.frame(rbindlist(lapply(setdiff(2014:max_train, 2020), function(z) r15_prior_frame(d, z)), fill = TRUE))
  base <- e$v4_pre(y, ids, as_tibble(d$history), max_train)$r
  out <- data.table(team_id = ids, pre_off = base$pre_off[match(ids, base$team_id)], pre_def = base$pre_def[match(ids, base$team_id)],
                    route_off = "base", route_def = "base")
  fitted_any <- FALSE
  for (side in c("off", "def")) {
    target <- paste0("eff_", side); terms <- R15_TERMS[[side]]
    pat <- vapply(seq_len(nrow(f)), function(i) paste(terms[vapply(terms, function(t) is.finite(f[[t]][i]), TRUE)], collapse = "|"), "")
    for (pp in unique(pat)) {
      tt_terms <- strsplit(pp, "|", fixed = TRUE)[[1]]
      tt <- tr[is.finite(tr[[target]]) & apply(as.matrix(tr[, tt_terms, drop = FALSE]), 1, function(z) all(is.finite(z))), , drop = FALSE]
      if (nrow(tt) < R15_MIN_ROWS) next
      cv <- rbindlist(lapply(sort(unique(tt$season)), function(yy) { a <- tt[tt$season < yy, , drop = FALSE]; b <- tt[tt$season == yy, , drop = FALSE]
        if (nrow(a) < R15_MIN_ROWS || !nrow(b)) return(NULL)
        rbindlist(lapply(R15_RIDGE_GRID, function(l) { m <- r15_ridge(a, tt_terms, target, l)
          data.table(year = yy, lambda = l, sse = sum((as.numeric(v5_apply(b, m$design) %*% m$beta) - b[[target]])^2), n = nrow(b)) })) }))
      if (!nrow(cv)) next
      tab <- cv[, .(mse = sum(sse) / sum(n)), by = lambda][order(mse, -lambda)]
      m <- r15_ridge(tt, tt_terms, target, tab$lambda[1])
      ix <- which(pat == pp)
      out[ix, paste0("pre_", side) := as.numeric(v5_apply(f[ix, , drop = FALSE], m$design) %*% m$beta)]
      out[ix, paste0("route_", side) := sprintf("%s (n=%d, lambda=%g)", pp, nrow(tt), tab$lambda[1])]
      fitted_any <- TRUE
    }
  }
  if (fitted_any) out[, `:=`(pre_off = pre_off - mean(pre_off), pre_def = pre_def - mean(pre_def))]
  out[, pre_power := pre_off - pre_def]
  attr(out, "frame") <- f
  out[]
}

# Turnover index u (§5.2); components missing in the training rows are dropped, other missing values take the training mean.
r15_u <- function(fr, side, train_means) {
  comp <- if (side == "off") list(a = 1 - fr$cont_skill, b = 1 - fr$cont_pass, c = fr$new_hc, d = fr$promoted) else
    list(a = 1 - fr$cont_def, c = fr$new_hc, d = fr$promoted)
  keep <- intersect(names(comp), names(train_means)[is.finite(train_means)])
  if (!length(keep)) return(rep(0, length(comp[[1]])))
  Reduce(`+`, lapply(keep, function(k) { v <- comp[[k]]; v[!is.finite(v)] <- train_means[[k]]; v }))
}
r15_u_means <- function(fr, side) {
  comp <- if (side == "off") list(a = 1 - fr$cont_skill, b = 1 - fr$cont_pass, c = fr$new_hc, d = fr$promoted) else
    list(a = 1 - fr$cont_def, c = fr$new_hc, d = fr$promoted)
  vapply(comp, function(v) if (any(is.finite(v))) mean(v, na.rm = TRUE) else NA_real_, 0)
}
# Variance model for target y: walk-forward prior residuals of seasons 2016 .. min(y-1, max_train), 2020 excluded.
r15_c1_variance <- function(d, y, priors, max_train = min(y - 1L, 2022L)) {
  zs <- setdiff(2016:max_train, 2020)
  rr <- rbindlist(lapply(zs, function(z) { p <- priors[[as.character(z)]]; fr <- as.data.table(attr(p, "frame"))
    merge(p[, .(team_id, pre_off, pre_def)], fr, by = "team_id")[, season := z] }), fill = TRUE)
  res <- list()
  for (side in c("off", "def")) {
    r <- rr[[paste0("eff_", side)]] - rr[[paste0("pre_", side)]]
    tm <- r15_u_means(rr, side); u <- r15_u(rr, side, tm); ok <- is.finite(r) & is.finite(u) & r != 0
    stopifnot(sum(ok) >= 30)
    fit <- lm(log(r[ok]^2) ~ u[ok])
    res[[side]] <- list(b = unname(coef(fit)[2]), train_means = tm, n = sum(ok), vbar = mean(r[ok]^2))
  }
  res
}
# Team-specific prior precision for season z: lambda_i = lambda0 * exp(-b (u_i - ubar)).
r15_c1_lambda <- function(prior_z, var_model, lambda0) {
  fr <- as.data.table(attr(prior_z, "frame"))[match(prior_z$team_id, team_id)]
  sapply(c("off", "def"), function(side) { u <- r15_u(fr, side, var_model[[side]]$train_means)
    lambda0 * exp(-var_model[[side]]$b * (u - mean(u))) }, simplify = FALSE)
}
# Prior scale a_X(y): LAD on games of seasons 2016 .. min(y-1, 2022), 2020 excluded, each with its own as-of prior; H(y) shared.
r15_scale <- function(d, y, priors, H) {
  if (y <= 2016) return(1)
  zs <- setdiff(2016:min(y - 1L, 2022L), 2020)
  fr <- as.data.table(d$base$frame)[season %in% zs]
  pw <- rbindlist(lapply(zs, function(z) priors[[as.character(z)]][, .(season = z, team_id, pre_power)]))
  fr <- merge(fr, pw[, .(season, home_id = team_id, ph = pre_power)], by = c("season", "home_id"))
  fr <- merge(fr, pw[, .(season, away_id = team_id, pa = pre_power)], by = c("season", "away_id"))
  v5_scalar(function(a) mean(abs(a * (fr$ph - fr$pa) + H * as.numeric(!fr$neutral) - fr$actual_margin)), c(.1, 3), "c1_scale")$value
}
# Shared prediction HFA H(z) (§5.1 and Amendment 01 §6.1 item 7).
r15_H <- function(d, z) {
  if (z >= 2023) return(R15C$frozen_hfa)
  if (z == 2016) return(median(unique(d$history[season %in% 2013:2015, .(season, hfa)])$hfa))
  d$pars[[as.character(z)]]$scale$hfa
}
# Weekly predictions of season z with a given prior table (unscaled), scale a, lambda vectors, H.
r15_predict_season_c1 <- function(d, z, prior, a, lam, H) {
  snaps <- Filter(function(sn) sn$season == z, d$base$snap)
  rbindlist(lapply(snaps, function(sn) {
    pr <- tibble(team_id = sn$ids, pre_off = a * prior$pre_off[match(sn$ids, prior$team_id)], pre_def = a * prior$pre_def[match(sn$ids, prior$team_id)])
    lo <- lam$off[match(sn$ids, prior$team_id)]; ld <- lam$def[match(sn$ids, prior$team_id)]
    stopifnot(all(sn$tg$available_at < sn$cutoff))
    ef <- v4_score_fit(sn$tg, sn$ids, pr, lambda = lo, def_lambda = ld, hfa = H)
    p <- ef$eff_off - mean(ef$eff_off) - (ef$eff_def - mean(ef$eff_def))
    te <- as.data.table(d$base$frame)[season == z & cutoff == sn$cutoff]
    te[, .(season, game_id, cutoff = format(cutoff, "%Y-%m-%d"), neutral, home_id, away_id,
           pred_margin = p[match(home_id, ef$team_id)] - p[match(away_id, ef$team_id)] + H * !neutral)]
  }))
}
