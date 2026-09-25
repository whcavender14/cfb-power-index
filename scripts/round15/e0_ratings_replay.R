# Round 15 evaluation step E0 (before scoring): replay the FROZEN predictions to capture each model's team ratings at
# every cutoff, for the predeclared rating-level diagnostics (§7.1: rating spread, tier means, stability, update
# efficiency, FBS-vs-FCS slice). No parameter is re-estimated: every frozen selection is read from the construction files.
# The candidate code is loaded with capture-only text patches (each asserted to occur once); the replay must reproduce
# every frozen, hashed prediction to <= 1e-9 or the script stops. No outcome metric is computed here.
source("config/paths.R"); source("config/production.R")
suppressPackageStartupMessages({ source(PATHS$model_ops); library(data.table); source("R/round15/candidates/data.R") })
out <- R15C$cache; ev <- "output/dev/round15/eval"; dir.create(ev, showWarnings = FALSE, recursive = TRUE)

# frozen inputs: verify the construction manifests first
for (k in 1:3) { m <- fread(sprintf("docs/round15/construction/c%d_manifest.csv", k))
  stopifnot(all(mapply(function(f, h) identical(digest::digest(file = f, algo = "sha256"), h), m$file, m$sha256))) }

.cap <- list(); .cap_model <- NA_character_; .fcs <- list(id = character(), r = numeric())
.fcs_set <- function(id, r) .fcs <<- list(id = id, r = r)
.cap_add <- function(z, cutoff, team_id, p, fcs) {
  x <- data.table(model = .cap_model, season = z, cutoff = format(cutoff, "%Y-%m-%d"), team_id = as.integer(team_id), rating = p, fbs = TRUE)
  if (!is.null(fcs) && length(fcs$id)) x <- rbind(x, data.table(model = .cap_model, season = z, cutoff = format(cutoff, "%Y-%m-%d"), team_id = as.integer(fcs$id), rating = fcs$r, fbs = FALSE))
  .cap[[length(.cap) + 1L]] <<- x }
load_patched <- function(file, patches) {
  s <- paste(readLines(file), collapse = "\n")
  for (p in patches) { n <- lengths(regmatches(s, gregexpr(p[1], s, fixed = TRUE))); if (n != 1L) stop(file, ": patch target found ", n, " times: ", p[1])
    s <- sub(p[1], p[2], s, fixed = TRUE) }
  eval(parse(text = s), envir = globalenv()) }
load_patched("R/round15/candidates/c1.R", list(
  c("    p <- ef$eff_off - mean(ef$eff_off) - (ef$eff_def - mean(ef$eff_def))",
    "    p <- ef$eff_off - mean(ef$eff_off) - (ef$eff_def - mean(ef$eff_def)); .cap_add(z, sn$cutoff, ef$team_id, p, NULL)")))
load_patched("R/round15/candidates/c2.R", list(
  c("  nt <- length(ids); ne <- length(ents); n <- nrow(rows)", "  .fcs_set(character(), numeric()); nt <- length(ids); ne <- length(ents); n <- nrow(rows)"),
  c("  o <- b[1L + seq_len(nt)]; dd <- b[1L + ne + seq_len(nt)]",
    "  o <- b[1L + seq_len(nt)]; dd <- b[1L + ne + seq_len(nt)]; fi <- nt + seq_len(ne - nt); if (length(fi)) .fcs_set(ents[fi], (b[1L + fi] - mean(o)) - (b[1L + ne + fi] - mean(dd)))"),
  c("    p <- ef$eff_off - ef$eff_def", "    p <- ef$eff_off - ef$eff_def; .cap_add(z, sn$cutoff, ef$team_id, p, .fcs)")))
source("R/round15/candidates/tune.R")
load_patched("R/round15/candidates/c3.R", list(
  c("  ne <- length(ents); nt <- length(ids); K <- k_now", "  .fcs_set(character(), numeric()); ne <- length(ents); nt <- length(ids); K <- k_now"),
  c("  o <- b[pos(col_o(seq_len(nt), K))]; dd <- b[pos(col_d(seq_len(nt), K))]",
    "  o <- b[pos(col_o(seq_len(nt), K))]; dd <- b[pos(col_d(seq_len(nt), K))]; fi <- nt + seq_len(ne - nt); if (length(fi)) .fcs_set(ents[fi], (b[pos(col_o(fi, K))] - mean(o)) - (b[pos(col_d(fi, K))] - mean(dd)))"),
  c("    p <- ef$eff_off - ef$eff_def", "    p <- ef$eff_off - ef$eff_def; .cap_add(z, sn$cutoff, ef$team_id, p, .fcs)")))

d <- r15_build_data(); d$qb <- r15_qb_primary()
c1 <- readRDS(file.path(out, "c1_components.rds")); c2 <- readRDS(file.path(out, "c2_components.rds")); c3t <- readRDS(file.path(out, "c3_tuning.rds"))
key22 <- function(k) as.character(if (k >= 2023) 2022 else k)
lam_of <- function(z, key = z) r15_c1_lambda(c1$priors[[as.character(z)]], c1$varm[[as.character(key)]], c1$lam0[[key22(key)]])
vb <- function(z) { v <- c1$varm[[as.character(z)]]; list(off = v$off$vbar, def = v$def$vbar) }
Hof <- function(y) if (y >= 2023) R15C$frozen_hfa else r15_H(d, y)
keyof <- function(y) if (y >= 2023) 2023L else y
qz <- setNames(c(0, c3t$sel_q$selected), c("2016", c3t$sel_q$target)); qbz <- setNames(c(0, c3t$sel_qb$selected), c("2016", c3t$sel_qb$target))
S <- c(R15C$dev, 2023:2025)
runs <- list(
  I  = function(y) { pr <- as.data.table(d$inc$prior_fits[[as.character(y)]]$r)[, .(team_id, pre_off, pre_def)]; par <- d$pars[[as.character(y)]]
         r15_predict_season_c1(d, y, pr, par$scale$scale, list(off = rep(4, nrow(pr)), def = rep(4, nrow(pr))), par$scale$hfa) },
  C1 = function(y) r15_predict_season_c1(d, y, c1$priors[[as.character(y)]], c1$scl[[as.character(keyof(y))]], lam_of(y, keyof(y)), Hof(y)),
  C2 = function(y) r15_predict_season_c2(d, y, c1$priors[[as.character(y)]], c1$scl[[as.character(keyof(y))]], lam_of(y, keyof(y)), Hof(y), c2$p2[[as.character(keyof(y))]],
                                         vb(keyof(y)), c1$lam0[[key22(y)]], c2$eos_full, c2$om[[key22(y)]]),
  C3 = function(y) r15_predict_season_c3(d, y, c1$priors[[as.character(y)]], c1$scl[[as.character(keyof(y))]], lam_of(y, keyof(y)), Hof(y), c2$p2[[as.character(keyof(y))]],
                                         vb(keyof(y)), c1$lam0[[key22(y)]], c2$eos_full, c2$om[[key22(y)]], qz[[key22(y)]], qbz[[key22(y)]], r15_sigma2_row(d, keyof(y))))
ref <- list(I = fread("output/dev/round15/incumbent_replay_2017_2022.csv", colClasses = list(character = "game_id")))
for (k in 1:3) ref[[paste0("C", k)]] <- fread(file.path(out, sprintf("c%d_predictions.csv", k)), colClasses = list(character = "game_id"))
chk <- rbindlist(lapply(names(runs), function(mn) { .cap_model <<- mn; yrs <- if (mn == "I") R15C$dev else S
  p <- rbindlist(lapply(yrs, runs[[mn]])); m <- merge(p, ref[[mn]][, .(game_id, r = pred_margin)], by = "game_id")
  data.table(model = mn, games = nrow(m), frozen_games = nrow(ref[[mn]][season %in% yrs]), max_abs_diff = max(abs(m$pred_margin - m$r))) }))
chk[, pass := games == frozen_games & max_abs_diff <= 1e-9]; print(chk)
fwrite(chk, "docs/round15/eval/e0_replay_check.csv"); stopifnot(all(chk$pass))
rat <- rbindlist(.cap); rat <- rat[!duplicated(rat[, .(model, season, cutoff, team_id)])]
fwrite(rat, file.path(ev, "ratings_replay.csv"))
fwrite(data.table(file = file.path(ev, "ratings_replay.csv"), sha256 = digest::digest(file = file.path(ev, "ratings_replay.csv"), algo = "sha256")), "docs/round15/eval/e0_manifest.csv")
print(rat[, .(rows = .N, cutoffs = uniqueN(paste(season, cutoff)), fcs_rows = sum(!fbs)), by = model])
