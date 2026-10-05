# =============================================================================
# CFPi+ Player Ratings v1: validation (predeclared in docs/website/PLAYER_RATINGS_PREDECLARATION.md).
# Compares the rating (posterior mean) with the recruiting-only comparator (rho * recruit z; monotone in the 247Sports
# rating) on cutoff-safe outcomes. Predictors are built through season a; outcomes come from season b > a.
# =============================================================================
rank_normal <- function(x) { r <- frank(x, ties.method = "average"); qnorm((r - 0.5) / length(x)) }

# Next-season production Y (season b): offense = PPA per play (qualified: n >= y_min); defense = the season-b evidence
# composite (qualified: at least 15 defensive actions).
production_outcome <- function(b, fbs_teams) {
  F <- season_evidence(b, fbs_teams, full = TRUE)
  e <- season_evidence(b, fbs_teams)
  F[, E := e$E[match(athlete_id, e$athlete_id)]]
  F[, y := fifelse(group %in% c("QB", "RB", "WR", "TE"), ppa, E)]
  F[, qual := n >= unname(RS$gate$y_min[group])]
  F[group %in% names(RS$gate$y_min) & qual & is.finite(y), .(athlete_id, group, yb = y)]
}

production_table <- function(pairs, ratings_by_season, fbs_teams) {
  rbindlist(lapply(pairs, function(pr) {
    a <- pr[1]; b <- pr[2]
    r <- ratings_by_season[[as.character(a)]][group %in% names(RS$gate$y_min), .(athlete_id, group, mu, prior = stars_prior)]
    y <- production_outcome(b, fbs_teams)
    d <- merge(r, y, by = c("athlete_id", "group")); d[, pair := paste(a, b, sep = "-")]
    d[, `:=`(mu_t = rank_normal(mu), prior_t = rank_normal(prior), y_t = rank_normal(yb)), by = .(group, pair)]
    d
  }))
}

# Cluster bootstrap over athletes. stat(d) -> numeric vector. Returns point estimate and 95% percentile CI per element.
boot_ci <- function(d, stat, B, seed) {
  set.seed(seed)
  pt <- stat(d); ids <- split(seq_len(nrow(d)), d$athlete_id); n <- length(ids)
  bs <- t(vapply(seq_len(B), function(i) stat(d[unlist(ids[sample.int(n, n, replace = TRUE)], use.names = FALSE)]), numeric(length(pt))))
  list(est = pt, lo = apply(bs, 2, quantile, 0.025, na.rm = TRUE), hi = apply(bs, 2, quantile, 0.975, na.rm = TRUE))
}

delta_corr <- function(d) {
  one <- function(x) cor(x$mu_t, x$y_t) - cor(x$prior_t, x$y_t)
  c(pooled = one(d), vapply(names(RS$gate$y_min), function(g) { x <- d[group == g]; if (nrow(x) < 10) NA_real_ else one(x) }, 0))
}

# Concordance (AUC) of predictor vs drafted within group-season, pooled over comparable pairs.
auc_pool <- function(d, col) {
  tot <- 0; conc <- 0
  for (k in split(seq_len(nrow(d)), paste(d$group, d$season))) {
    x <- d[k]; np <- sum(x$drafted); nn <- nrow(x) - np
    if (np == 0 || nn == 0) next
    r <- frank(x[[col]], ties.method = "average"); u <- sum(r[x$drafted]) - np * (np + 1) / 2
    conc <- conc + u; tot <- tot + np * nn
  }
  conc / tot
}
draft_table <- function(seasons, ratings_by_season) {
  rbindlist(lapply(seasons, function(s) {
    dr <- rd(sprintf("hist_draft_%d.rds", s + 1L)); ids <- as.character(dr$collegeAthleteId)
    r <- ratings_by_season[[as.character(s)]][class >= 3 & !is.na(class)]
    r[, .(athlete_id, group, season = s, mu, prior = stars_prior, drafted = athlete_id %in% ids)]
  }))
}
delta_auc <- function(d) c(delta = auc_pool(d, "mu") - auc_pool(d, "prior"), rating = auc_pool(d, "mu"), stars = auc_pool(d, "prior"))

# Distribution report for rating through season s (OVR via the frozen knots).
distribution_report <- function(p) {
  o <- p$ovr; pc <- function(x) round(100 * mean(o >= x), 1)
  list(n = nrow(p), mean = mean(o), median = median(o), sd = sd(o), min = min(o), max = max(o),
       pct = quantile(o, c(.01, .05, .1, .25, .5, .75, .9, .95, .99)), at = c(`95+` = pc(95), `90+` = pc(90), `85+` = pc(85), `80+` = pc(80), `75+` = pc(75), `70+` = pc(70)),
       bands = c(`95-99` = round(100 * mean(o >= 95), 1), `90-94` = round(100 * mean(o >= 90 & o < 95), 1), `85-89` = round(100 * mean(o >= 85 & o < 90), 1), `80-84` = round(100 * mean(o >= 80 & o < 85), 1),
                 `75-79` = round(100 * mean(o >= 75 & o < 80), 1), `70-74` = round(100 * mean(o >= 70 & o < 75), 1), `65-69` = round(100 * mean(o >= 65 & o < 70), 1), `60-64` = round(100 * mean(o >= 60 & o < 65), 1), `<60` = round(100 * mean(o < 60), 1)),
       by_group = p[, .(n = .N, mean = round(mean(ovr), 1), median = round(median(ovr), 1), sd = round(sd(ovr), 1), p90 = round(100 * mean(ovr >= 90), 1), p80 = round(100 * mean(ovr >= 80), 1), provisional = round(100 * mean(provisional), 1), estimated = round(100 * mean(estimated), 1)), by = group][order(-n)],
       provisional = c(n = sum(p$provisional), pct = round(100 * mean(p$provisional), 1)), estimated = c(n = sum(p$estimated), pct = round(100 * mean(p$estimated), 1)),
       evidence_means = p[r >= 0.5 & !estimated, .(n = .N, mean = round(mean(ovr), 1), sd = round(sd(ovr), 1)), by = group][order(group)])
}
