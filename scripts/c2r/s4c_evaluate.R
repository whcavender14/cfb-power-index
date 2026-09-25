# C2 refinement research, Stage 4: evaluate the arms and apply docs/c2r/STAGE4_PLAN.md.
# Usage (round15-power-rating worktree root): Rscript <c2r>/scripts/c2r/s4c_evaluate.R scale | final
stage <- commandArgs(trailingOnly = TRUE)[1]; stopifnot(stage %in% c("scale", "final"))
suppressPackageStartupMessages({ source("config/paths.R"); source("config/production.R"); source(PATHS$model_ops); library(data.table)
  source("R/evaluation/evaluation_helpers.R"); for (f in c("data", "c1", "c2")) source(sprintf("R/round15/candidates/%s.R", f)) })
source("/Users/willcavender/Desktop/Revised CFB Modeling/.claude/worktrees/c2-refinement/scripts/c2r/lib_c2r.R"); source(file.path(C2R, "scripts/c2r/lib_s3.R"))
out <- file.path(C2R, "output/c2r/stage4"); OUT <- file.path(C2R, "docs/c2r/stage4"); w <- function(x, f) { fwrite(x, file.path(OUT, f)); invisible(x) }
options(width = 250, datatable.print.nrows = 500); DEV <- R15C$dev; NREP <- 4000L; SEED <- 15015L
d <- r15_build_data(); c1 <- readRDS(file.path(R15C$cache, "c1_components.rds"))
AR <- lapply(setNames(nm = sub("\\.rds$", "", list.files(file.path(out, "arms")))), function(a) readRDS(file.path(out, "arms", paste0(a, ".rds"))))
if (stage == "scale") AR <- AR[grepl("^(C2L|NP|S\\d|O\\d)", names(AR))]
AR$C0 <- readRDS(file.path(C2R, "output/c2r/stage3/arms/C0.rds"))   # frozen C2 (identical to the R15 predictions)
RA <- names(AR)

# ---------------- FBS-vs-FBS universe (all-games gp; see plan) ----------------
G <- readRDS(file.path(out, "G_frame.rds"))[, .(season, game_id, cutoff, neutral, home_id, away_id, home_conference, away_conference, gp_h, gp_a, gpmin, both0, split, hfa, site, win, actual, s_p4, I, s_I)]
for (a in RA) G <- merge(G, AR[[a]]$pred[, .(game_id, v = pred_margin)][, setnames(.SD, "v", a)], by = "game_id")
G[, gpb := fifelse(gpmin >= 7, "7+", fifelse(gpmin >= 4, "4-6", as.character(gpmin)))]; setorder(G, split, season, cutoff, game_id)
fit_sigma <- function(m, y) { f <- function(s) -sum(y * pnorm(m / s, log.p = TRUE) + (1 - y) * pnorm(-m / s, log.p = TRUE)); optimize(f, c(2, 80), tol = 1e-10)$minimum }
for (x in RA) { s <- numeric(nrow(G)); for (y in DEV) { g <- G[split == "dev" & season != y]; s[G$season == y] <- fit_sigma(g[[x]], g$win) }
  s[G$split == "cond"] <- fit_sigma(G[split == "dev"][[x]], G[split == "dev"]$win); set(G, j = paste0("s_", x), value = s) }
clip <- function(p) pmin(pmax(p, 1e-6), 1 - 1e-6)
MODS <- c(RA, "I")
for (x in MODS) { p <- clip(pnorm(G[[x]] / G[[paste0("s_", x)]])); set(G, j = paste0("ll_", x), value = -(G$win * log(p) + (1 - G$win) * log(1 - p))); set(G, j = paste0("br_", x), value = (p - G$win)^2) }
bmet <- function(h, x) { m <- h[[x]]; data.table(n = nrow(h), logloss = mean(h[[paste0("ll_", x)]]), brier = mean(h[[paste0("br_", x)]]), mae = mean(abs(m - h$actual)), rmse = sqrt(mean((m - h$actual)^2)),
  bias = mean(m - h$actual), calib_slope = unname(coef(lm(I(h$actual - h$site) ~ I(m - h$site)))[2]), pred_sd = sd(m), winners = mean(sign(m) == sign(h$actual))) }
BK <- list("0" = "0", "1" = "1", "2" = "2", "3" = "3", "0-3" = c("0", "1", "2", "3"), "4-6" = "4-6", "7+" = "7+", "all" = c("0", "1", "2", "3", "4-6", "7+"))
bytab <- function(xs) rbindlist(lapply(c("dev", "cond"), function(sp) rbindlist(lapply(xs, function(x) rbindlist(lapply(names(BK), function(b)
  cbind(data.table(split = sp, model = x, gp = b), bmet(G[split == sp & gpb %in% BK[[b]]], x))))))))

# ---------------- FBS-vs-FCS (whole-system J and the Stage 3 interaction) ----------------
snaps <- unique(rbindlist(lapply(d$base$snap, function(sn) data.table(season = sn$season, cutoff = format(sn$cutoff, "%Y-%m-%d"), ct = sn$cutoff))))
snaps <- snaps[!duplicated(snaps[, .(season, cutoff)])]; setorder(snaps, season, ct); snaps[, wk := seq_len(.N), by = season]
FC0 <- rbindlist(lapply(c2r_S, function(y) { g <- d$games[[as.character(y)]][final == TRUE & xor(home_fbs %in% TRUE, away_fbs %in% TRUE)]
  cs <- snaps[season == y]; g[, ci := findInterval(as.numeric(kickoff), as.numeric(cs$ct))]; g <- g[ci >= 1]
  g[, .(season, game_id, neutral = as.logical(neutral), fbs_home = home_fbs %in% TRUE, fbs_id = fifelse(home_fbs %in% TRUE, home_id, away_id), fcs_id = fifelse(home_fbs %in% TRUE, away_id, home_id),
        actual = fifelse(home_fbs %in% TRUE, home_points - away_points, away_points - home_points), cutoff = cs$cutoff[ci])] }))
FC0[, split := fifelse(season >= 2023, "cond", "dev")][, H := vapply(season, function(y) c2r_H(d, y), 0)][, site := H * (!neutral) * fifelse(fbs_home, 1, -1)]
sgm <- unique(G[, .(season, split)]);
FC <- rbindlist(lapply(RA, function(a) { cp <- AR[[a]]; f <- merge(copy(FC0), cp$ent[fbs == TRUE, .(season, cutoff, fbs_id = team_id, fbs_r = power)], by = c("season", "cutoff", "fbs_id"))
  f <- merge(f, cp$ent[fbs == FALSE, .(season, cutoff, fcs_id = team_id, fcs_in = power)], by = c("season", "cutoff", "fcs_id"), all.x = TRUE)
  f <- merge(f, cp$fcs_prior[, .(season, cutoff, fcs_id = team_id, fg = first_game_power)], by = c("season", "cutoff", "fcs_id"))
  sg <- unique(G[, .(season, s = get(paste0("s_", a)))]); f <- merge(f, sg, by = "season")
  f[, `:=`(arm = a, first = !is.finite(fcs_in), pred = fbs_r - fifelse(is.finite(fcs_in), fcs_in, fg) + site)][, ll := { p <- clip(pnorm(pred / s)); y <- as.numeric(actual > 0); -(y * log(p) + (1 - y) * log(1 - p)) }] }))
J <- rbind(rbindlist(lapply(RA, function(a) G[, .(arm = a, season, split, ll = get(paste0("ll_", a)))])), FC[, .(arm, season, split, ll)])

# ---------------- selection ----------------
loso_fam <- function(cand) { picks <- sapply(DEV, function(sv) { v <- sapply(cand, function(a) mean(G[split == "dev" & season != sv][[paste0("ll_", a)]])); cand[which.min(v)] })
  h <- unlist(lapply(seq_along(DEV), function(i) G[split == "dev" & season == DEV[i]][[paste0("ll_", picks[i])]]))
  all5 <- cand[which.min(sapply(cand, function(a) mean(G[split == "dev"][[paste0("ll_", a)]])))]
  list(picks = paste(sprintf("%d:%s", DEV, picks), collapse = " "), honest = mean(h), all5 = all5) }
guard <- function(a) { b <- bytab(c(a, "C2L"))[split == "dev" & gp %in% c("0", "1", "2", "3", "4-6", "7+")]
  worst <- max(b[model == a, logloss] - b[model == "C2L", logloss]); jd <- J[split == "dev" & arm == a, mean(ll)] - J[split == "dev" & arm == "C2L", mean(ll)]
  list(worst_bucket = worst, dJ = jd, ok = worst <= 0.003 & jd <= 0) }
fams <- list(S = c("C2L", grep("^S\\d", RA, value = TRUE)), O = c("C2L", grep("^O\\d", RA, value = TRUE)))
if (stage == "final") { sc <- readRDS(file.path(out, "selection_scale.rds")); fams$D <- c(sc$name, grep("^D\\d", RA, value = TRUE)) }
sel <- rbindlist(lapply(names(fams), function(fn) { r <- loso_fam(fams[[fn]]); g <- guard(r$all5)
  data.table(family = fn, picks = r$picks, honest_logloss = r$honest, selected = r$all5, worst_bucket_vs_C2L = g$worst_bucket, dJ_vs_C2L = g$dJ, eligible = g$ok | r$all5 == "C2L") }))
sel <- rbind(data.table(family = "C2L", picks = "", honest_logloss = mean(G[split == "dev", ll_C2L]), selected = "C2L", worst_bucket_vs_C2L = 0, dJ_vs_C2L = 0, eligible = TRUE), sel)
cat("== selection (development FBS-vs-FBS log-loss, leave-one-season-out) ==\n"); print(sel, digits = 6); w(sel, sprintf("s4_selection_%s.csv", stage))
if (stage == "scale") {
  el <- sel[family %in% c("C2L", "S", "O") & eligible == TRUE]; best <- min(el$honest_logloss); ord <- c(C2L = 0, S = 1, O = 2)
  ch <- el[honest_logloss <= best + 3e-4][order(ord[family])][1]; nm <- ch$selected
  saveRDS(list(name = nm, opt = AR[[nm]]$opt, family = ch$family), file.path(out, "selection_scale.rds")); cat("scale chosen:", ch$family, nm, "\n")
  bt <- bytab(c("C2L", "NP", grep("^(S|O)\\d", RA, value = TRUE))); print(dcast(bt, split + gp ~ model, value.var = "logloss"), digits = 4)
  print(dcast(bt, split + gp ~ model, value.var = "calib_slope"), digits = 3); w(bt, "s4_scale_by_gp.csv"); quit(save = "no")
}
el <- sel[eligible == TRUE]; best <- min(el$honest_logloss); ord <- c(C2L = 0, S = 1, O = 2, D = 3)
chosen <- el[honest_logloss <= best + 3e-4][order(ord[family])][1]; CH <- chosen$selected
cat("\n== chosen by the predeclared rule:", chosen$family, CH, "==\n")
saveRDS(list(chosen = chosen, sel = sel), file.path(out, "selection_final.rds"))
Dsel <- sel[family == "D", selected]; Ssel <- sc$name
KEY <- unique(c("C0", "C2L", "NP", Ssel, Dsel, CH))

# ---------------- by games played (every scored candidate) ----------------
bt <- bytab(c(KEY, "I", grep("^(S|O|D)\\d", RA, value = TRUE))); w(bt, "s4_by_gp_all.csv")
cat("\n== log-loss by games played ==\n"); print(dcast(bt[model %in% c(KEY, "I", grep("^D\\d", RA, value = TRUE))], split + gp ~ model, value.var = "logloss"), digits = 4)
cat("\n== calibration slope by games played ==\n"); print(dcast(bt[model %in% c(KEY, "I")], split + gp ~ model, value.var = "calib_slope"), digits = 3)
cat("\n== MAE by games played ==\n"); print(dcast(bt[model %in% c(KEY, "I")], split + gp ~ model, value.var = "mae"), digits = 4)
inc <- merge(bt[model %in% setdiff(KEY, "NP")], bt[model == "NP", .(split, gp, np_ll = logloss, np_mae = mae)], by = c("split", "gp"))[, `:=`(ll_gain_vs_noprior = np_ll - logloss, mae_gain_vs_noprior = np_mae - mae)]
cat("\n== incremental value of preseason information (no-prior log-loss minus arm log-loss; > 0 = preseason helps) ==\n"); print(dcast(inc, split + gp ~ model, value.var = "ll_gain_vs_noprior"), digits = 4)
w(inc, "s4_incremental_value_vs_noprior.csv")
# F diagnostic: shape of the ideal decay curve (overall dev log-loss and the affected bucket)
fd <- rbindlist(lapply(grep("^F_", RA, value = TRUE), function(a) { b <- sub("^F_gp(\\w+)_x.*$", "\\1", a); mu <- as.numeric(sub("^.*_x", "", a))
  bb <- if (b == "5p") c("4-6", "7+") else b
  data.table(bucket = b, multiplier = mu, dev_ll_all = mean(G[split == "dev"][[paste0("ll_", a)]]), dev_ll_bucket = mean(G[split == "dev" & gpb %in% bb][[paste0("ll_", a)]])) }))
fd[, base_all := mean(G[split == "dev"][[paste0("ll_", Ssel)]])][, d_all := dev_ll_all - base_all]
cat("\n== F diagnostic: dev log-loss change vs the selected scale when one gp bucket's prior precision is multiplied ==\n"); print(dcast(fd, bucket ~ multiplier, value.var = "d_all"), digits = 3)
w(fd, "s4_flexible_decay_diagnostic.csv")
# influence curves of the decay arms
infc <- rbindlist(lapply(grep("^D\\d", RA, value = TRUE), function(a) if (!is.null(AR[[a]]$inf) && nrow(AR[[a]]$inf)) AR[[a]]$inf[season %in% DEV, .(arm = a, w = mean(w_power)), by = .(gp = pmin(gp, 6))] else NULL))
c2linf <- readRDS(file.path(out, "arms", "C2L.rds"))$inf[season %in% DEV, .(arm = "C2L", w = mean(w_power)), by = .(gp = pmin(gp, 6))]
if (nrow(infc)) { infc <- rbind(c2linf, infc); cat("\n== own-prior influence by games played ==\n"); print(dcast(infc, gp ~ arm, value.var = "w"), digits = 3); w(infc, "s4_influence_decay_arms.csv") }

# ---------------- deltas vs C2L, frozen C2 and the incumbent ----------------
mkboot <- function(k) { lev <- sort(unique(k)); B <- length(lev); set.seed(SEED); idx <- matrix(sample.int(B, NREP * B, replace = TRUE), nrow = NREP); list(b = match(k, lev), B = B, C = t(apply(idx, 1, tabulate, nbins = B))) }
bs <- function(bo, v) { s <- numeric(bo$B); t <- tapply(v, bo$b, sum); s[as.integer(names(t))] <- t; s }
bm <- function(bo, v) { dr <- as.numeric(bo$C %*% bs(bo, v)) / as.numeric(bo$C %*% bs(bo, rep(1, length(v)))); c(est = mean(v), lo = unname(quantile(dr, .025)), hi = unname(quantile(dr, .975))) }
dl <- rbindlist(lapply(c("dev", "cond"), function(sp) { g <- G[split == sp]; bo <- mkboot(paste(g$season, g$cutoff))
  rbindlist(lapply(setdiff(KEY, "C0"), function(a) rbindlist(lapply(c("C2L", "C0", "I"), function(b) { if (a == b) return(NULL)
    r <- rbind(bm(bo, g[[paste0("ll_", a)]] - g[[paste0("ll_", b)]]), bm(bo, g[[paste0("br_", a)]] - g[[paste0("br_", b)]]), bm(bo, abs(g[[a]] - g$actual) - abs(g[[b]] - g$actual)))
    data.table(split = sp, arm = a, vs = b, metric = c("logloss", "brier", "mae"), delta = r[, 1], lo95 = r[, 2], hi95 = r[, 3]) })))) }))
cat("\n== FBS-vs-FBS deltas (block bootstrap; negative = better) ==\n"); print(dl, digits = 3); w(dl, "s4_deltas.csv")
ov <- rbindlist(lapply(c("dev", "cond"), function(sp) rbindlist(lapply(c(KEY, "I"), function(x) cbind(data.table(split = sp, model = x), bmet(G[split == sp], x),
  p4g5 = mean(((G[split == sp]$actual - G[split == sp][[x]]) * G[split == sp]$s_p4)[G[split == sp]$s_p4 != 0]), J = if (x == "I") NA_real_ else J[split == sp & arm == x, mean(ll)])))))
cat("\n== overall absolute metrics ==\n"); print(ov, digits = 5); w(ov, "s4_overall.csv")

# ---------------- descriptive subgroups (gp 0-3, where preseason information matters most) ----------------
fr <- rbindlist(lapply(c2r_S, function(y) { f <- as.data.table(attr(c1$priors[[as.character(y)]], "frame")); f[, .(season = y, team_id, new_hc, cont = rowMeans(cbind(cont_pass, cont_skill, cont_def), na.rm = TRUE))] }))
pp <- rbindlist(lapply(c2r_S, function(y) { A <- c2r_args(d, c1, readRDS(file.path(R15C$cache, "c2_components.rds")), y); data.table(season = y, team_id = A$prior$team_id, pw = A$a * (A$prior$pre_off - A$prior$pre_def)) }))
Gs <- merge(G, fr[, .(season, home_id = team_id, nh = new_hc, ch = cont)], by = c("season", "home_id"), all.x = TRUE); Gs <- merge(Gs, fr[, .(season, away_id = team_id, na_ = new_hc, ca = cont)], by = c("season", "away_id"), all.x = TRUE)
Gs <- merge(Gs, pp[, .(season, home_id = team_id, ph = pw)], by = c("season", "home_id"), all.x = TRUE); Gs <- merge(Gs, pp[, .(season, away_id = team_id, pa = pw)], by = c("season", "away_id"), all.x = TRUE)
Gs[, `:=`(th = tier_of(home_conference, season), ta = tier_of(away_conference, season))]
Gs[, matchup := fifelse(th == "Other" | ta == "Other", "with independents", fifelse(th == "P4" & ta == "P4", "P4-P4", fifelse(th == "G5" & ta == "G5", "G5-G5", "P4-G5")))]
Gs[, coach := fifelse((nh %in% 1) | (na_ %in% 1), "a new head coach", "both returning")][, cm := (ch + ca) / 2][, continuity := fifelse(cm >= median(cm, na.rm = TRUE), "high continuity", "low continuity"), by = season]
Gs[, fav := fifelse(abs(ph - pa) >= 21, "large preseason favourite (>= 21)", "other")]
subarms <- unique(c("C2L", "NP", Ssel, grep("^D\\d", RA, value = TRUE), CH))
sg <- rbindlist(lapply(c("matchup", "coach", "continuity", "fav"), function(v) Gs[split == "dev" & gpmin <= 3, c(.(n = .N), lapply(setNames(paste0("ll_", subarms), subarms), function(cn) mean(get(cn)))), by = .(level = get(v))][, slice := v]))
fcf <- FC[first == TRUE & split == "dev" & arm %in% subarms, .(ll = mean(ll)), by = arm]; sg <- rbind(sg, cbind(data.table(slice = "FBS-vs-FCS first games", level = "all", n = FC[first == TRUE & split == "dev" & arm == "C2L", .N]), as.data.table(as.list(setNames(fcf$ll, fcf$arm)))), fill = TRUE)
cat("\n== descriptive subgroups: development log-loss, games with min gp <= 3 ==\n"); print(sg, digits = 4); w(sg, "s4_subgroups.csv")

# ---------------- interaction with Stage 3 ----------------
lvl <- rbindlist(lapply(unique(c("C2L", Ssel, CH)), function(a) merge(AR[[a]]$cuts[n_rows > 0, .(arm = a, season, cutoff, fcs_level)], snaps[, .(season, cutoff, wk)], by = c("season", "cutoff"))))
lv <- unique(lvl)[season %in% DEV & wk <= 5, .(fcs_level = mean(fcs_level, na.rm = TRUE)), by = .(arm, wk)]
fcb <- FC[arm %in% c("C0", "C2L", Ssel, CH), .(n = .N, bias = mean(pred - actual), mae = mean(abs(pred - actual))), by = .(split, arm, game = fifelse(first, "first game", "later"))]
nfcs <- rbindlist(lapply(c2r_S, function(y) { g <- d$games[[as.character(y)]][final == TRUE]; ids <- fbs_ids(d$sch[[as.character(y)]])
  r <- rbind(g[, .(team_id = home_id, opp = away_id)], g[, .(team_id = away_id, opp = home_id)])[team_id %in% ids]; r[, .(season = y, n_fcs_opp = sum(!opp %in% ids)), by = team_id] }))
fin <- function(a) { e <- AR[[a]]$ent[fbs == TRUE]; e[, last := cutoff == max(cutoff), by = season]; e[last == TRUE, .(season, team_id, p = power)] }
cr <- rbindlist(lapply(unique(c("C2L", Ssel, CH)), function(a) { m <- merge(merge(fin(a), fin("C0"), by = c("season", "team_id"), suffixes = c("", "0")), nfcs, by = c("season", "team_id"))
  m[season %in% DEV, .(arm = a, change_vs_C0 = mean(p - p0)), by = .(n_fcs = pmin(n_fcs_opp, 2))] }))
cat("\n== interaction with Stage 3: FCS level at cutoffs 1-5 (dev) ==\n"); print(dcast(unique(lv), wk ~ arm, value.var = "fcs_level"), digits = 3)
cat("\n== FBS-vs-FCS first vs later games ==\n"); print(dcast(fcb, split + game ~ arm, value.var = c("bias", "mae")), digits = 3)
cat("\n== FBS rating change vs frozen C2 by number of FCS opponents (final cutoff, dev) ==\n"); print(dcast(cr, n_fcs ~ arm, value.var = "change_vs_C0"), digits = 3)
w(unique(lv), "s4_fcs_level_early.csv"); w(fcb, "s4_fbsfcs_first_later.csv"); w(cr, "s4_fcs_credit.csv")
