# Current C2 diagnostics (not part of the rating path). Requires R/c2/c2_current.R and a run with keep_system = TRUE.

# Stage 4 preseason influence: for every FBS team at a cutoff, the exact response of its rating to a unit shift of its
# own prior mean (power: offense +1/2, defense -1/2; and each side alone), plus the part of its rating contributed by all
# FBS prior means. "After X games, w_power of the rating is still the team's own preseason information."
c2_prior_influence <- function(ratings, sys) {
  if (is.null(sys)) return(NULL)
  Q <- sys$Q; nt <- sys$nt; ne <- sys$ne; ii <- seq_len(nt); lo <- sys$lo; ld <- sys$ld
  R <- sparseMatrix(i = c(1L + ii, 1L + ne + ii, 1L + ii, 1L + ne + ii), j = c(ii, ii, nt + ii, 2L * nt + ii),
                    x = c(0.5 * lo[ii], -0.5 * ld[ii], lo[ii], ld[ii]), dims = c(nrow(Q), 3L * nt))
  Sx <- as.matrix(solve(Q, R)); Op <- Sx[1L + ii, ii]; Dp <- Sx[1L + ne + ii, ii]
  rhs <- numeric(nrow(Q)); rhs[1L + ii] <- lo[ii] * sys$po[ii]; rhs[1L + ne + ii] <- ld[ii] * sys$pd[ii]
  pb <- as.numeric(solve(Q, rhs)); r <- ratings[fbs == TRUE]   # ratings are in entity order: FBS first
  data.table(season = r$season, cutoff = r$cutoff, team_id = r$team_id, gp = r$gp, lam_off = lo[ii], lam_def = ld[ii],
             w_power = diag(Op) - colMeans(Op) - (diag(Dp) - colMeans(Dp)), w_off = diag(Sx[1L + ii, nt + ii]), w_def = diag(Sx[1L + ne + ii, 2L * nt + ii]),
             prior_block = (pb[1L + ii] - mean(pb[1L + ii])) - (pb[1L + ne + ii] - mean(pb[1L + ne + ii])), power = r$power)
}
c2_influence_all <- function(run) {
  keys <- unique(run$ratings[, .(season, cutoff)])
  rbindlist(Map(function(sys, k) if (is.null(sys)) NULL else c2_prior_influence(run$ratings[season == k$season & cutoff == k$cutoff], sys),
                run$system, split(keys, seq_len(nrow(keys)))))
}
