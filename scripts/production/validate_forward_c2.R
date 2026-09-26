# =====================================================================================================================
# scripts/production/validate_forward_c2.R: checks the forward-evidence plugins for Current C2 and frozen Round 15 C2.
#   H1  frozen C2's forward call reproduces frozen Round 15 C2's own 2025 predictions (the c2_build.R conditional path)
#   H2  fwd_model_c2() on archived-style inputs == the production build (Current C2) and == frozen C2 called directly
#   H3  plugin output passes the forward snapshot guards (no outcome/market/vendor fields) and carries late_pull
# Needs the research caches and the 2026 dry-run pulls (local only). Appends to docs/production/validation/.
# =====================================================================================================================
source("config/paths.R"); source("config/production.R"); source("config/production_model.R")
suppressPackageStartupMessages({ source(PATHS$model_ops); source(PATHS$production_model); library(data.table)
  source("R/forward/forward_lib.R"); source("R/forward/forward_models.R") })
c2p_load_model()
REF <- normalizePath(file.path(PATHS$root, "..", "c2-refinement")); MAIN <- normalizePath(file.path(PATHS$root, "..", "..", ".."))
R15WT <- file.path(MAIN, ".claude/worktrees/round15-power-rating"); LIVE <- file.path(MAIN, "output/state/production_live")
res <- list(); check <- function(section, what, value, pass) {
  res[[length(res) + 1L]] <<- data.table(section, check = what, value = format(value, digits = 6), pass = isTRUE(pass))
  cat(sprintf("[%s] %-4s %s: %s\n", section, if (isTRUE(pass)) "PASS" else "FAIL", what, format(value, digits = 6)))
}

# H1: frozen C2, 2025, with the season-input fields the plugin passes
d <- r15_build_data(); c1 <- readRDS(file.path(R15C$cache, "c1_components.rds")); c2 <- readRDS(file.path(R15C$cache, "c2_components.rds"))
dv <- c2_divisions(as.data.table(readRDS("output/dev/round15/prep/fcs_schedules_2013_2025.rds")))
lv <- rbindlist(lapply(2013:2025, function(s) c2_eos_levels(d, s, dv))); S <- c2_season_inputs(d, c1, c2, 2025L, dv, c2_anchors(lv, 2025L))
f25 <- r15_predict_season_c2(d, 2025L, S$prior, S$a, S$lam, S$H, S$p2, S$vbar, S$lambda0, S$eos_full, S$omega)
ref <- fread(file.path(R15C$cache, "c2_predictions.csv"), colClasses = list(character = "cutoff"))[season == 2025]
m <- merge(f25[, .(game_id = as.character(game_id), cutoff, a = pred_margin)], ref[, .(game_id = as.character(game_id), cutoff, b = pred_margin)], by = c("game_id", "cutoff"))
check("H1", "frozen C2 forward call vs frozen R15 C2 2025 predictions", sprintf("%d of %d, max %.2e", nrow(m), nrow(ref), max(abs(m$a - m$b))),
      nrow(m) == nrow(ref) && max(abs(m$a - m$b)) < 1e-9)

# H2: plugin on the 2026 dry-run pulls at the 2026-09-21 cutoff (week-4 targets)
CUT <- as.POSIXct("2026-09-21", tz = "UTC"); cfg <- v4_config(); cfg$cache_dir <- LIVE; sch26 <- read_schedule(2026L, cfg, FALSE)
raw26 <- readRDS(file.path(LIVE, "raw_schedule_2026.rds"))
fd <- file.path(tempdir(), "fcs26"); dir.create(fd, showWarnings = FALSE)
file.copy(file.path(REF, "output/live2026/raw/games_year2026_seasonTyperegular_classificationfcs.rds"), fd); fcs26 <- c2p_fcs_games(2026L, fd)
pf <- list.files(file.path(R15WT, "output/dev/round15/forward_dryrun/pbp/2026"), "^plays_regular_wk0[1-3]_.*[.]rds$", full.names = TRUE)
stamp <- sub("^.*_(\\d{8}T\\d{6}Z)[.]rds$", "\\1", basename(pf))
pulls <- data.table(file = pf, season_type = "regular", week = as.integer(sub("^.*_wk(\\d+)_.*$", "\\1", basename(pf))),
                    pulled_at = as.POSIXct(stamp, format = "%Y%m%dT%H%M%SZ", tz = "UTC"))
wk4 <- as.data.table(sch26)[week == 4 & season_type == "regular" & home_fbs & away_fbs]
out <- fwd_model_c2(sch26, raw26, pulls, fcs26, CUT, wk4, Sys.time())
plays <- rbindlist(lapply(seq_len(nrow(sel <- fwd_select_pulls(pulls, CUT))), function(i)
  as.data.table(readRDS(sel$file[i]))[, `:=`(season = 2026L, wk = sel$week[i], season_type = sel$season_type[i])]), fill = TRUE)
prod <- c2_production_build(2026L, CUT, sch26, raw26, tempdir(), fcs_games = fcs26, plays = plays, targets = wk4)
pp <- as.data.table(attr(prod, "predictions"))[, .(game_id = as.character(game_id), b = pred_margin)]
a <- merge(out$c2_current$pred[, .(game_id, a = pred_margin)], pp, by = "game_id")
check("H2", "plugin Current C2 == production build predictions (week 4)", sprintf("%d games, max %.2e", nrow(a), max(abs(a$a - a$b))),
      nrow(a) == nrow(wk4) && max(abs(a$a - a$b)) < 1e-12)
proto <- fread(file.path(REF, "docs/c2/live_2026_wk04/game_spreads_c2_vs_incumbent_2026_wk04.csv"))
q <- merge(out$c2_current$pred[, .(game_id, pm = pred_margin)], proto[, .(game_id = as.character(game_id), c2_implied_spread)], by = "game_id")
check("H2", "plugin Current C2 vs pre-promotion comparison (rounded 0.1)", max(abs(-q$pm - q$c2_implied_spread)), max(abs(-q$pm - q$c2_implied_spread)) <= 0.05 + 1e-9)
check("H2", "frozen R15 C2 predictions complete and finite", sum(is.finite(out$c2_frozen_r15$pred$pred_margin)), all(is.finite(out$c2_frozen_r15$pred$pred_margin)))
dd <- out$c2_frozen_r15$pred$pred_margin - out$c2_current$pred$pred_margin
check("H2", "frozen R15 C2 differs from Current C2 only modestly (FBS vs FBS)", sprintf("mean |diff| %.2f, max %.2f", mean(abs(dd)), max(abs(dd))), max(abs(dd)) < 10)

# H3: guard columns (the time guard is exercised in tests/forward; these targets are partly past kickoff now)
bad <- function(p) { n <- names(p); any(n %in% FWD$outcome_fields) || any(grepl(FWD$market_pattern, n, ignore.case = TRUE)) || any(grepl(FWD$vendor_pattern, n, ignore.case = TRUE)) }
check("H3", "plugin outputs carry no outcome/market/vendor fields", paste(names(out$c2_current$pred), collapse = ","), !bad(out$c2_current$pred) && !bad(out$c2_frozen_r15$pred))
check("H3", "late_pull recorded (dry-run pulls postdate the cutoff)", unique(out$c2_current$pred$late_pull), isTRUE(all(out$c2_current$pred$late_pull)))
x <- rbindlist(res); fwrite(x, "docs/production/validation/forward_c2_validation.csv")
cat(sprintf("\n%d checks, %d passed, %d failed\n", nrow(x), sum(x$pass), sum(!x$pass))); if (!all(x$pass)) quit(status = 1L)
