# Round 15 §6.1 inner walk-forward selection. `inner` holds as-of-date predictions of each inner season for each grid value
# (columns season, game_id, pred_margin, grid_value). Objective: winner log-loss pooled over Z(target), sigma profiled out.
# Ties within 1e-6 go to the value closest to the nesting value; fallback to the nesting value per §6.1 item 6.
suppressPackageStartupMessages(library(data.table))
r15_Z <- function(y) setdiff(2016:(y - 1L), 2020L)
r15_profiled_logloss <- function(m, w) {
  f <- function(s) { p <- pmin(pmax(pnorm(m / s), 1e-6), 1 - 1e-6); -mean(w * log(p) + (1 - w) * log(1 - p)) }
  o <- optimize(f, c(5, 40)); c(logloss = o$objective, sigma = o$minimum)
}
r15_actual <- function(d) as.data.table(d$base$frame)[, .(game_id, actual_margin)]
r15_select <- function(inner, d, grid, nesting, targets) {
  act <- r15_actual(d)
  x <- merge(inner, act, by = "game_id")[actual_margin != 0][, w := as.numeric(actual_margin > 0)]
  rbindlist(lapply(targets, function(y) {
    zz <- r15_Z(y); xs <- x[season %in% zz]
    if (!length(zz) || uniqueN(xs$game_id) < 500) return(data.table(target = y, selected = nesting, grid_edge = FALSE, fallback = TRUE, objective = list(NULL)))
    ob <- rbindlist(lapply(grid, function(v) { s <- xs[grid_value == v]; r <- r15_profiled_logloss(s$pred_margin, s$w)
      data.table(grid_value = v, logloss = r[["logloss"]], sigma = r[["sigma"]]) }))
    if (!any(is.finite(ob$logloss))) return(data.table(target = y, selected = nesting, grid_edge = FALSE, fallback = TRUE, objective = list(ob)))
    best <- min(ob$logloss, na.rm = TRUE); cand <- ob[is.finite(logloss) & logloss <= best + 1e-6]
    v <- cand$grid_value[which.min(abs(cand$grid_value - nesting))]
    data.table(target = y, selected = v, grid_edge = v %in% range(grid) & v != nesting, fallback = FALSE, objective = list(ob))
  }))
}
