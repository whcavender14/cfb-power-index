# =============================================================================
# CFPi+ Player Ratings v1: construction (spec: R/ratings/ratings_spec.R; predeclaration:
# docs/website/PLAYER_RATINGS_PREDECLARATION.md). Display only; never feeds the team model.
# Cutoff-safe by construction: the rating "through season s" reads only season s and s-1 tables, rosters of s and
# recruiting classes up to s. Nothing here reads a later season.
# =============================================================================
suppressPackageStartupMessages(library(data.table))
CACHE <- file.path(PATHS$reference, "player_cache")
rd <- function(f) { p <- file.path(CACHE, f); if (file.exists(p)) as.data.table(readRDS(p)) else NULL }
grp_of <- function(pos) { out <- rep(NA_character_, length(pos)); for (g in names(RS$groups)) out[toupper(pos) %in% RS$groups[[g]]] <- g; out }
num <- function(x) { v <- suppressWarnings(as.numeric(x)); v }
zcap <- function(z) pmax(-RS$zcap, pmin(RS$zcap, z))
zfit <- function(x, qual) { ok <- qual & is.finite(x); m <- mean(x[ok]); s <- sd(x[ok]); if (!is.finite(s) || s == 0) return(rep(NA_real_, length(x))); zcap((x - m) / s) }

# ---- season tables ----------------------------------------------------------------------------------------------
# One row per athlete: group, team, opportunities n, evidence E (weighted z) for season s.
season_evidence <- function(s, fbs_teams, full = FALSE) {
  st <- rd(sprintf("hist_stats_%d.rds", s))
  st[, v := num(stat)][, key := paste(category, statType, sep = "_")]
  w <- dcast(st[team %in% fbs_teams], playerId + position ~ key, value.var = "v", fun.aggregate = sum, fill = 0)
  # one row per player: keep the team of the player's largest defensive/offensive volume row
  tm <- st[team %in% fbs_teams][, .(team = team[1]), by = playerId]
  w <- merge(w, tm, by = "playerId"); setnames(w, "playerId", "athlete_id"); w[, athlete_id := as.character(athlete_id)]
  w[, group := grp_of(position)]
  g <- function(k) if (k %in% names(w)) w[[k]] else rep(0, nrow(w))
  # team games (regular season) from the cached box scores, for per-team-game defensive rates
  gl <- rd(sprintf("games_%d.rds", s)); tgames <- gl[!(post %in% TRUE), .(tg = uniqueN(game_id)), by = team]
  w[, tg := tgames$tg[match(team, tgames$team)]]; w[is.na(tg) | tg < 8, tg := 12]
  ppa <- rd(sprintf("hist_ppa_%d.rds", s)); ppa[, id := as.character(id)]; ppa <- ppa[!duplicated(id)]
  us <- rd(sprintf("hist_usage_%d.rds", s)); us[, id := as.character(id)]; us <- us[!duplicated(id)]
  sc <- rd(sprintf("hist_success_%d.rds", s)); sc[, id := as.character(id)]; sc <- sc[!duplicated(id)]
  m <- function(d, col) num(d[[col]][match(w$athlete_id, d$id)])
  w[, `:=`(ppa_all = m(ppa, "averagePPA.all"), ppa_pass = m(ppa, "averagePPA.pass"), ppa_rush = m(ppa, "averagePPA.rush"),
           usg_pass = m(us, "usage.pass"), usg_rush = m(us, "usage.rush"),
           ps = m(sc, "passing.successes"), pp = m(sc, "passing.plays"), rs = m(sc, "rushing.successes"), rp = m(sc, "rushing.plays"))]
  att <- g("passing_ATT"); car <- g("rushing_CAR"); rec <- g("receiving_REC")
  act <- g("defensive_TOT") + g("defensive_TFL") + g("defensive_SACKS") + g("defensive_PD") + g("interceptions_INT")
  rate <- function(k) g(k) * 12 / w$tg
  F <- data.table(athlete_id = w$athlete_id, group = w$group, team = w$team)
  F[, n := fcase(group == "QB", att, group == "RB", car, group %in% c("WR", "TE"), rec, group %in% c("DL", "LB", "DB"), act,
                 group == "K", g("kicking_FGA"), group == "P", g("punting_NO"), default = 0)]
  F[, `:=`(ppa = fcase(group == "QB", w$ppa_all, group == "RB", w$ppa_rush, group %in% c("WR", "TE"), w$ppa_pass, default = NA_real_),
           sr = fifelse(w$pp > 0, w$ps / w$pp, NA_real_), ypa = fifelse(att > 0, g("passing_YDS") / att, NA_real_),
           tdint = fifelse(att > 0, (g("passing_TD") - g("passing_INT")) / att, NA_real_),
           ypc = fifelse(car > 0, g("rushing_YDS") / car, NA_real_), usage = fifelse(group == "RB", w$usg_rush, w$usg_pass),
           ypr = fifelse(rec > 0, g("receiving_YDS") / rec, NA_real_),
           tkl = rate("defensive_TOT"), tfl = rate("defensive_TFL"), sacks = rate("defensive_SACKS"), qbh = rate("defensive_QB HUR"),
           pd = rate("defensive_PD"), int = rate("interceptions_INT"),
           fgp = fifelse(g("kicking_FGA") >= 0, (g("kicking_FGM") + 3) / (g("kicking_FGA") + 4), NA_real_), long = g("kicking_LONG"),
           avg = fifelse(g("punting_NO") > 0, g("punting_YDS") / g("punting_NO"), NA_real_),
           in20 = fifelse(g("punting_NO") > 0, g("punting_In 20") / g("punting_NO"), NA_real_),
           tb = fifelse(g("punting_NO") > 0, g("punting_TB") / g("punting_NO"), NA_real_))]
  rb <- which(F$group == "RB"); F$sr[rb] <- ifelse(w$rp[rb] > 0, w$rs[rb] / w$rp[rb], NA_real_)
  F <- F[group %in% names(RS$w) & !is.na(group) & n > 0]
  E <- rep(NA_real_, nrow(F))
  for (gname in names(RS$w)) {
    i <- which(F$group == gname); if (!length(i)) next
    wt <- RS$w[[gname]]; num_ <- rep(0, length(i)); den <- rep(0, length(i)); qual <- F$n[i] >= RS$nmin[[gname]]
    for (f in names(wt)) { z <- zfit(F[[f]][i], qual); a <- !is.na(z); num_[a] <- num_[a] + wt[[f]] * z[a]; den[a] <- den[a] + abs(wt[[f]]) }
    E[i] <- ifelse(den > 0, num_ / den, NA_real_)
  }
  F[, E := E]
  if (full) return(F[!duplicated(athlete_id)])
  F[!is.na(E), .(athlete_id, group, team, n, E)][!duplicated(athlete_id)]
}

# Team unit quality for offensive linemen: mean of z(-sack rate allowed) and z(yards per carry) across FBS teams.
unit_quality <- function(s, fbs_teams) {
  t <- rd(sprintf("hist_teamstats_%d.rds", s)); t[, v := num(statValue)]
  w <- dcast(t[team %in% fbs_teams], team ~ statName, value.var = "v", fun.aggregate = sum)
  sack <- w$sacksOpponent / (w$passAttempts + w$sacksOpponent); ypc <- w$rushingYards / w$rushingAttempts
  z <- function(x) { v <- (x - mean(x, na.rm = TRUE)) / sd(x, na.rm = TRUE); zcap(v) }
  data.table(team = w$team, unit_z = RS$ol$unit_w[["sack"]] * z(-sack) + RS$ol$unit_w[["ypc"]] * z(ypc))
}

# All FBS roster players of season s with the recruit prior: athlete_id, name, team, group, class year, Rz, size_z.
# Amendment A1 (operational, math unchanged): r = a roster table to use instead of the cached roster_<s>.rds (the
# current season's roster lives in output/state).
roster_pool <- function(s, fbs_teams, r = NULL) {
  r <- (if (is.null(r)) rd(sprintf("roster_%d.rds", s)) else as.data.table(r))[team %in% fbs_teams]
  r[, `:=`(athlete_id = as.character(athlete_id), group = grp_of(position), class = suppressWarnings(as.integer(year)))]
  r <- r[!is.na(group) & !duplicated(athlete_id)]
  rec <- rbindlist(lapply(2016:s, function(y) { x <- rd(sprintf("recruits_%d.rds", y)); if (is.null(x)) NULL else x[, .(athlete_id = as.character(athlete_id), rating = num(rating), weight = num(weight), year = as.integer(year))] }), fill = TRUE)
  rec <- rec[!is.na(athlete_id)][order(-year)][!duplicated(athlete_id)]
  r[, `:=`(rating = rec$rating[match(athlete_id, rec$athlete_id)], rweight = rec$weight[match(athlete_id, rec$athlete_id)])]
  r[, Rz := fifelse(is.na(rating), RS$recruit$missing_z, (rating - RS$recruit$mean) / RS$recruit$sd)]
  r[, size_z := fifelse(is.na(rweight), 0, zcap((rweight - RS$ol$size_mean) / RS$ol$size_sd))]
  r[, name := paste(first_name, last_name)]
  r[, .(athlete_id, name, team, position, group, class, rating, Rz, size_z)]
}

# Rating through season s (posterior mean in z units, reliability, flags). Reads seasons s and s-1 only.
# Amendment A1: pool = a roster_pool() of another season (e.g. next season's roster rated with evidence through s,
# which is exactly the validated use: a rating through season s for the following season).
build_ratings <- function(s, fbs_teams, pool = NULL) {
  if (is.null(pool)) pool <- roster_pool(s, fbs_teams)
  e1 <- season_evidence(s, fbs_teams); e0 <- if (file.exists(file.path(CACHE, sprintf("hist_stats_%d.rds", s - 1L)))) season_evidence(s - 1L, fbs_teams) else NULL
  p <- copy(pool)
  p[, `:=`(n1 = 0, E1 = NA_real_, n0 = 0, E0 = NA_real_)]
  i1 <- match(p$athlete_id, e1$athlete_id); p[!is.na(i1), `:=`(n1 = e1$n[i1[!is.na(i1)]], E1 = e1$E[i1[!is.na(i1)]])]
  if (!is.null(e0)) { i0 <- match(p$athlete_id, e0$athlete_id); p[!is.na(i0), `:=`(n0 = e0$n[i0[!is.na(i0)]], E0 = e0$E[i0[!is.na(i0)]])] }
  # a prior-season row only counts for the same position group
  p[, n_eff := n1 + RS$carry * n0]
  p[, E := fifelse(n_eff > 0, (fifelse(is.na(E1), 0, n1 * E1) + RS$carry * fifelse(is.na(E0), 0, n0 * E0)) / n_eff, NA_real_)]
  p[, kk := unname(RS$k[group])]; p[, rho := unname(RS$rho[group])]
  p[, r := fifelse(group == "OL", RS$ol$r, fifelse(is.na(E), 0, n_eff / (n_eff + kk)))]
  p[, prior := rho * Rz]
  uq <- unit_quality(s, fbs_teams); p[, unit_z := fifelse(is.na(uq$unit_z[match(team, uq$team)]), 0, uq$unit_z[match(team, uq$team)])]
  p[group == "OL", prior := rho * Rz + RS$ol$size_w * size_z + RS$ol$class_w * zcap((fifelse(is.na(class), 2.5, class) - 2.5) / 1.1)]
  p[, ev := fifelse(group == "OL", unit_z, fifelse(is.na(E), 0, E))]
  p[, mu := r * ev + (1 - r) * (prior - RS$depth_shift)]
  p[, sd_z := RS$prior_sd * sqrt(1 - r)]
  p[, `:=`(estimated = group %in% c("OL", "K", "P"), provisional = r < 0.5, season = s)]
  p[, stars_prior := rho * Rz]   # the recruiting-only comparator (monotone in the recruit rating)
  p[]
}

# ---- OVR scale ------------------------------------------------------------------------------------------------
fit_knots <- function(mu) {
  q <- quantile(mu, RS$target_cum, names = FALSE, type = 7)
  ok <- !duplicated(q); list(x = q[ok], y = RS$target_ovr[ok])
}
to_ovr <- function(mu, knots) {
  f <- splinefun(knots$x, knots$y, method = "hyman")   # monotone cubic
  out <- f(pmax(min(knots$x), pmin(max(knots$x), mu)))
  # beyond the end knots: linear continuation at the end slope, capped to 30..99
  lo <- mu < min(knots$x); hi <- mu > max(knots$x)
  sl <- function(a) (f(a + 1e-3) - f(a - 1e-3)) / 2e-3
  out[lo] <- knots$y[1] + sl(min(knots$x)) * (mu[lo] - min(knots$x)); out[hi] <- tail(knots$y, 1) + sl(max(knots$x)) * (mu[hi] - max(knots$x))
  pmax(30, pmin(99, out))
}
