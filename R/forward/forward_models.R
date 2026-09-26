# Forward-snapshot model plugins. Each returns list(pred = data.table, meta = list) for the target games at one cutoff.
#   incumbent  : frozen v5 EB_features via the production engine (v5_build); schema identical to v5_archive (Gate 5 compatible)
#   round13_K  : frozen Round 13 candidate, code vendored byte-for-byte from tag round13-frozen-c4819fd, frozen w_2026
#   round15_*  : refused until a signed Round 15 freeze manifest exists (config/forward/round15_freeze_manifest.csv)
# Requires config/paths.R, R/model/production_operations.R and R/forward/forward_lib.R.
R13_VENDOR <- file.path(PATHS$root, "R/forward/vendor/round13_sr_stack.R")
R13_VENDOR_BLOB <- "d9339f4bcb6dd9717dbce90ecdcd34317dbf17d5"   # git blob of R/model/round13_sr_stack.R at round13-frozen-c4819fd
R13_WEIGHT <- file.path(PATHS$root, "config/forward/round13_forward_weight.csv")
R13_WEIGHT_SHA256 <- "0cd5be8ff7bee487cd87ed53c509523afe7e1776000a08f0d60aed7bea4ca1c3"   # docs/round13/freeze_manifest.csv
R15_FREEZE <- file.path(PATHS$root, "config/forward/round15_freeze_manifest.csv")

fwd_git_blob <- function(path) system2("git", c("hash-object", shQuote(path)), stdout = TRUE)

fwd_model_incumbent <- function(g, cutoff, targets, now) {
  r <- v5_build(PRODUCTION$supported_season, cutoff, schedule = as.data.frame(g))
  f <- v5_frozen(); design <- unname(tools::md5sum(V5_FROZEN_DESIGN_FILE))
  fwd_assert(identical(design, attr(r, "design_hash")) && identical(f$feature_hash, attr(r, "feature_hash")), "Incumbent artifact mismatch")
  fwd_assert(!any(targets$game_id %in% attr(r, "training_ids")), "Target game in incumbent training")
  te <- as.data.frame(targets)
  p <- data.frame(game_id = te$game_id, season = te$season, kickoff = te$kickoff, predicted_at = now, information_cutoff = cutoff,
                  home_id = te$home_id, away_id = te$away_id, neutral = te$neutral, pred_margin = v4_predict(r, te$home_id, te$away_id, te$neutral),
                  candidate = attr(r, "candidate"), design_hash = design, feature_hash = f$feature_hash,
                  home_snapshot_id = r$feature_snapshot_id[match(te$home_id, r$team_id)], away_snapshot_id = r$feature_snapshot_id[match(te$away_id, r$team_id)])
  tg <- team_games(g, fbs_ids(g), 0); tg <- tg[tg$available_at < cutoff, ]
  list(pred = p, meta = list(design_md5 = design, feature_hash = f$feature_hash, engine_md5 = unname(tools::md5sum(PATHS$model_engine)),
                             training_games = length(unique(tg$game_id)), latest_training_available_at = fwd_iso(max(tg$available_at)),
                             information_rule = "FBS-vs-FBS final games with kickoff + 24 h < cutoff"))
}

# Latest play-by-play pull per week: the latest pulled before the cutoff if any (late_pull = FALSE), else the latest overall.
fwd_select_pulls <- function(pulls, cut_at) {
  pulls <- as.data.table(pulls)
  rbindlist(lapply(split(pulls, by = c("season_type", "week")), function(x) {
    pre <- x[pulled_at < cut_at]
    if (nrow(pre)) pre[which.max(pulled_at)][, late_pull := FALSE] else x[which.max(pulled_at)][, late_pull := TRUE]
  }))
}

fwd_model_r13K <- function(raw_schedule, pulls, cutoff, targets, incumbent_pred, now) {
  cut_at <- cutoff   # g13 has its own `cutoff` column; never refer to the run cutoff by that name inside g13[...]
  fwd_assert(identical(fwd_git_blob(R13_VENDOR), R13_VENDOR_BLOB), "Vendored Round 13 code differs from the frozen tag")
  fwd_assert(identical(fwd_sha256(R13_WEIGHT), R13_WEIGHT_SHA256), "Round 13 forward weight differs from its freeze manifest")
  e <- new.env(); sys.source(R13_VENDOR, envir = e)
  w <- fread(R13_WEIGHT)$w_2026; fwd_assert(length(w) == 1 && is.finite(w), "Invalid frozen weight")
  g13 <- e$r13_schedule(as.data.frame(raw_schedule))
  sel <- fwd_select_pulls(pulls, cut_at)
  need <- g13[final & (home_fbs | away_fbs) & available_at < cut_at]
  plays <- rbindlist(lapply(sel$file, function(f) { x <- readRDS(f); keep <- names(x)[!grepl(e$r13_vendor_pattern, names(x), ignore.case = TRUE)]
    x <- as.data.table(as.data.frame(x)[, keep, drop = FALSE]); x[, season := unique(g13$season)]; x[, e$r13_play_fields, with = FALSE] }), fill = TRUE)
  plays[, game_id := as.character(game_id)]
  plays <- plays[game_id %in% need$game_id]
  miss_fbs <- need[home_fbs & away_fbs & !game_id %in% plays$game_id, game_id]
  fwd_assert(!length(miss_fbs), paste("Play-by-play missing for final FBS-vs-FBS games before the cutoff:", paste(miss_fbs, collapse = ", ")))
  sm <- e$r13_season_means(plays, g13, vocab = "r8")
  ids <- sort(unique(c(g13$home_team[g13$home_fbs], g13$away_team[g13$away_fbs])))
  eff <- e$r13_effects(sm$means, ids, cut_at)
  te <- g13[match(targets$game_id, game_id)]
  h <- eff[match(te$home_team, eff$team)]; a <- eff[match(te$away_team, eff$team)]
  inc <- as.data.table(incumbent_pred)[match(te$game_id, game_id), pred_margin]
  fwd_assert(all(is.finite(inc)), "Incumbent margin missing for a K target")
  SRnet <- (h$sr_off + h$sr_def) - (a$sr_off + a$sr_def); gp <- pmin(h$games_played, a$games_played)
  p <- data.table(game_id = te$game_id, season = te$season, kickoff = te$kickoff, predicted_at = now, information_cutoff = cutoff,
                  home_team = te$home_team, away_team = te$away_team, home_id = te$home_id, away_id = te$away_id, neutral = te$neutral,
                  incumbent_margin = inc, SRnet = SRnet, gp = gp, w = w, pred_margin = e$r13_apply(inc, SRnet, gp, w), candidate = "round13_K",
                  late_pull = any(sel$late_pull))
  e$r13_forward_guard(p[, !c("late_pull")], now)
  list(pred = p, meta = list(vendored_code_blob = R13_VENDOR_BLOB, weight_sha256 = R13_WEIGHT_SHA256, w_2026 = w, vocab = "r8",
                             late_pull = any(sel$late_pull), pulls_used = sel[, .(season_type, week, file = basename(file), pulled_utc = fwd_iso(pulled_at), late_pull)],
                             pbp_games = uniqueN(plays$game_id), final_games_needed = nrow(need),
                             fbs_vs_fcs_missing = need[xor(home_fbs, away_fbs) & !game_id %in% plays$game_id, .N],
                             fumbles_total = sm$fumbles$total, fumbles_recovered = sm$fumbles$recovered,
                             information_rule = "plays of final games with kickoff + 12 h < cutoff (Round 13 C3); pull must precede the cutoff or late_pull = TRUE"))
}

fwd_model_round15 <- function(...) {
  fwd_assert(file.exists(R15_FREEZE), "Round 15 candidates are not frozen: no snapshot until a signed freeze manifest exists")
  stop("Round 15 plugin is added only at the Round 15 freeze, with its own reviewed code", call. = FALSE)
}

# ---- Current C2 (production model since 2026-09-26) and frozen Round 15 C2 (the builds Round 16 §9 names) ----------------
# Both run on the committed, hashed 2026 forward build (data/frozen/c2 + model code; c2p_verify_frozen() before every run)
# and on this snapshot's own archived inputs only:
#   * the schedule this run pulled;
#   * the archived play-by-play pulls (fwd_select_pulls: latest pre-cutoff pull per week, else late_pull = TRUE, as for K);
#   * the FCS-involved schedule this run pulled and archived.
# Information rule: C2's own (final games with kickoff + 24 h before the cutoff). Nothing is refitted or tuned.
# Frozen C2 is called exactly as its 2023-25 predictions were produced (scripts/round15/c2_build.R): the C1 prior, scale
# and precisions keyed to 2023; p2 and vbar keyed to 2023; lambda0 and omega keyed to 2022.
# fwd_model_round15() still refuses Round 15 candidates in general; these are the two C2 builds Round 16 §9 names.
fwd_c2_pulls <- function(archive, yr) {
  pulls <- fwd_read_manifest(archive)[kind == "pbp" & season == yr]
  fwd_assert(nrow(pulls) > 0, "No play-by-play pulls archived for this season")
  pulls[, `:=`(file = file.path(archive, path), pulled_at = as.POSIXct(recorded_utc, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
               season_type = sub("^plays_([a-z]+)_wk.*$", "\\1", basename(path)), week = as.integer(sub("^.*_wk(\\d+)_.*$", "\\1", basename(path))))][]
}

fwd_model_c2 <- function(g, raw_schedule, pulls, fcs_games, cutoff, targets, now) {
  if (!exists("c2p_run")) source(PATHS$production_model)
  v <- c2p_verify_frozen(); fwd_assert(all(v$ok), "Current C2 frozen build differs from its recorded checksums")
  cut_at <- cutoff; y <- PRODUCTION_MODEL$c2$supported_season
  sel <- fwd_select_pulls(pulls, cut_at)
  plays <- rbindlist(lapply(seq_len(nrow(sel)), function(i) as.data.table(readRDS(sel$file[i]))[, `:=`(season = y, wk = sel$week[i], season_type = sel$season_type[i])]), fill = TRUE)
  te <- as.data.table(targets)
  x <- c2p_run(y, cut_at, as.data.frame(g), raw_schedule, cache_dir = tempfile("c2fwd"), fcs_games = fcs_games, plays = plays, targets = te)
  fwd_assert(!any(te$game_id %in% x$games[final == TRUE & available_at < cut_at, game_id]), "Target game in C2 training")
  S <- x$S
  f2 <- r15_predict_season_c2(x$d, y, S$prior, S$a, S$lam, S$H, S$p2, S$vbar, S$lambda0, S$eos_full, S$omega)
  mk <- function(pred, cand) {
    pm <- as.data.table(pred)[, .(game_id = as.character(game_id), pred_margin)]
    data.table(game_id = as.character(te$game_id), season = te$season, kickoff = te$kickoff, predicted_at = now, information_cutoff = cut_at,
               home_id = te$home_id, away_id = te$away_id, neutral = te$neutral, pred_margin = pm$pred_margin[match(as.character(te$game_id), pm$game_id)],
               candidate = cand, late_pull = any(sel$late_pull))
  }
  meta <- list(frozen_build = list(season_inputs_md5 = PRODUCTION_MODEL$c2$season_inputs_md5, code_md5 = as.list(PRODUCTION_MODEL$c2$code_md5),
                                   research_tag = PRODUCTION_MODEL$c2$research_tag),
               late_pull = any(sel$late_pull), pulls_used = sel[, .(season_type, week, file = basename(file), pulled_utc = fwd_iso(pulled_at), late_pull)],
               coverage = x$coverage, information_rule = "final games (all divisions) with kickoff + 24 h < cutoff (Current C2's rule)")
  list(c2_current = list(pred = mk(x$cur$pred, "C2_current"), meta = c(meta, list(group_levels = x$cur$levels))),
       c2_frozen_r15 = list(pred = mk(f2, "C2_frozen_round15"), meta = meta))
}
