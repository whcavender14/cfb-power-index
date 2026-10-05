# =============================================================================
# CFPi+ Player Ratings, specification v1 (FROZEN before any validation metric was computed).
# Predeclaration: docs/website/PLAYER_RATINGS_PREDECLARATION.md. Display only: nothing here feeds the team model.
# Every constant below is fixed by hand or from data before the 2023 season (classes 2018-2020); none was tuned on
# validation results. Changing any of them is a NEW specification (v2) with its own predeclaration and validation.
# =============================================================================
RS <- list(
  version = "v1",
  # Position groups from CFBD roster positions. LS and ATH are not rated.
  groups = list(QB = "QB", RB = c("RB", "FB", "APB"), WR = "WR", TE = "TE", OL = c("OT", "IOL", "OL", "OG", "C", "G"),
                DL = c("DL", "DT", "DE", "EDGE", "NT"), LB = c("LB", "ILB", "OLB", "MLB"), DB = c("DB", "CB", "S", "SAF", "FS", "SS"),
                K = c("PK", "K"), P = "P"),
  # Recruit prior: 247Sports Composite rating, standardized with the mean and SD of the 2018-2020 high-school classes
  # (n = 11,921 rated). A missing rating (unrated, no recruiting record) is treated as Rz = -1.
  recruit = list(mean = 0.8248, sd = 0.0533, missing_z = -1),
  rho = c(QB = 0.25, RB = 0.25, WR = 0.25, TE = 0.25, DL = 0.25, LB = 0.25, DB = 0.25, OL = 0.30, K = 0.10, P = 0.10),
  depth_shift = 0.5,            # prior mean = rho * Rz - depth_shift: a rostered player is below the average qualified player
  zcap = 3,                     # evidence z-scores are capped at +-3
  prior_sd = 0.9,               # SD of true quality around the prior, in z units (posterior SD = prior_sd * sqrt(1 - r))
  carry = 0.5,                  # weight of last season's opportunities relative to this season's
  # Opportunity measure n, reliability constant k (r = n / (n + k)), minimum n for the z-score reference set.
  k = c(QB = 100, RB = 60, WR = 20, TE = 20, DL = 25, LB = 25, DB = 25, K = 12, P = 20),
  nmin = c(QB = 30, RB = 20, WR = 8, TE = 8, DL = 10, LB = 10, DB = 10, K = 5, P = 10),
  # Feature weights (renormalized over the features a player has).
  w = list(QB = c(ppa = .45, sr = .20, ypa = .20, tdint = .15),
           RB = c(ppa = .35, sr = .20, ypc = .30, usage = .15),
           WR = c(ppa = .40, ypr = .30, usage = .30),
           TE = c(ppa = .40, ypr = .30, usage = .30),
           DL = c(sacks = .30, tfl = .30, qbh = .20, tkl = .20),
           LB = c(tkl = .30, tfl = .25, sacks = .15, pd = .10, int = .10, qbh = .10),
           DB = c(tkl = .25, pd = .30, int = .25, tfl = .20),
           K = c(fgp = .70, long = .30),
           P = c(avg = .60, in20 = .25, tb = -.15)),
  # Offensive line: no individual production exists. mu = r_ol * unit_z + (1 - r_ol) * (rho*Rz + size_w*size_z + class_w*class_z) - depth_shift
  ol = list(r = 0.15, size_w = 0.25, class_w = 0.10, size_mean = 287, size_sd = 24.5, unit_w = c(sack = .5, ypc = .5)),
  # Gate thresholds (predeclared).
  gate = list(min_delta_corr = 0.03, min_delta_auc = 0.02, min_groups_positive = 5L, boot = 2000L, seed = 20261005L,
              dev_pairs = list(c(2021L, 2022L), c(2022L, 2023L)), holdout_pairs = list(c(2023L, 2024L), c(2024L, 2025L)),
              draft_dev = c(2021L, 2022L), draft_holdout = c(2023L, 2024L, 2025L),
              y_min = c(QB = 100, RB = 40, WR = 15, TE = 15, DL = 15, LB = 15, DB = 15), group_tol_points = 4),
  # OVR scale: fixed monotone map from posterior mean (z units) to 30-99, calibrated ONCE on the development
  # seasons' rosters (2021, 2022) so that the pooled development distribution meets the target quantiles below,
  # then frozen (R/ratings/ratings_knots.rds). Between knots the map is a monotone cubic (PCHIP): no bunching at thresholds.
  target_cum = c(0.0005, 0.031, 0.206, 0.421, 0.638, 0.797, 0.908, 0.962, 0.988, 0.9985),
  target_ovr = c(35, 60, 65, 70, 75, 80, 85, 90, 95, 99)
)
