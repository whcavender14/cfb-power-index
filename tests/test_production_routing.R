# Production model selection (R/production/production_model.R) and the exporter's model-change rules. No network, no
# research caches. Run from the project root: Rscript tests/test_production_routing.R
source("config/paths.R"); source("config/production.R"); source("config/production_model.R")
suppressPackageStartupMessages({ source(PATHS$model_ops); source(PATHS$production_model) })
errs <- function(expr) inherits(try(expr, silent = TRUE), "try-error")

# frozen artifacts of both models
v <- rbind(v5_verify_frozen_inputs(), c2p_verify_frozen()); stopifnot(all(v$ok))

# selection: C2 by default, the incumbent only when asked for explicitly, anything else refused
Sys.unsetenv("CFB_PRODUCTION_MODEL"); stopifnot(identical(production_model_id(), "C2_current"))
Sys.setenv(CFB_PRODUCTION_MODEL = "EB_features"); stopifnot(identical(production_model_id(), "EB_features"))
Sys.setenv(CFB_PRODUCTION_MODEL = "incumbent"); stopifnot(errs(production_model_id())); Sys.unsetenv("CFB_PRODUCTION_MODEL")
stopifnot(errs(c2p_season_inputs(2027L)))

# simulation routing follows the model that produced the ratings
seed <- readRDS(file.path(PATHS$snapshot_seed, "production_ratings_2026_wk01.rds"))
eb <- production_build(2026L, seed$as_of, model = "EB_features")
stopifnot(identical(eb, v5_build(2026L, seed$as_of)))                               # routed incumbent == direct incumbent
stopifnot(identical(production_sim_params(eb)$fcs_power, -25), identical(production_sim_params(eb)$resid_sd, PRODUCTION$sim_resid_sd),
          all(production_nonfbs_power(eb, c(1L, 2L)) == -25))
c2r <- data.frame(team_id = 1:2, power_rating = c(1, -1)); attr(c2r, "candidate") <- "C2_current"; attr(c2r, "hfa") <- PRODUCTION_MODEL$c2$hfa
attr(c2r, "nonfbs_ratings") <- data.frame(team_id = c(10L, 11L), power = c(-20.5, -31.2))
sp <- production_sim_params(c2r)
stopifnot(identical(sp$resid_sd, 15.6500874177702), is.na(sp$fcs_power), identical(sp$hfa, 3.06853968902663),
          identical(production_nonfbs_power(c2r, c(11L, 10L)), c(-31.2, -20.5)), errs(production_nonfbs_power(c2r, 12L)))
attr(c2r, "candidate") <- "unknown"; stopifnot(errs(production_sim_params(c2r)))

# exporter: model names come from the outputs; a model change never fakes weekly change or rewrites a published week
scratch <- tempfile("cfb-routing-"); input <- file.path(scratch, "input"); output <- file.path(scratch, "public"); dir.create(input, recursive = TRUE)
file.copy(file.path(PATHS$teams_dir, "teams_2026.rds"), input)
inc <- readRDS(file.path(PATHS$snapshot_seed, "production_ratings_2026_wk03.rds")); c2s <- inc; c2s$week <- 4L
c2s$candidate <- "C2_current"; c2s$design_hash <- PRODUCTION_MODEL$c2$season_inputs_md5; c2s$feature_hash <- PRODUCTION_MODEL$c2$code_md5[[1]]
saveRDS(inc, file.path(input, "production_ratings_2026_wk03.rds")); saveRDS(c2s, file.path(input, "production_ratings_2026_latest.rds"))
sim <- list(season = 2026L, week = 4L, updated_at = Sys.time(), as_of = Sys.time(), simulation_count = 10L, playoff_format = "x", wins_scope = "x",
            overall = data.frame(team_id = inc$ratings$team_id, wins = 6, playoff = 0.1, conf_champ = 0.1, won_natty = 0.01),
            simulation_assumptions = list(hfa = 3.0685, resid_sd = 15.65), model_metadata = list(candidate = "C2_current"))
saveRDS(sim, file.path(input, "simulations_2026_latest.rds"))
old <- file.path(output, "2026", "week-04"); dir.create(old, recursive = TRUE)
jsonlite::write_json(list(model = "vCurrent / EB_features", marker = "published"), file.path(old, "ratings.json"), auto_unbox = TRUE)
Sys.setenv(CFB_SEASON = "2026"); PATHS$state <- input; PATHS$public_data <- output; PATHS$teams_dir <- input
sys.source(PATHS$export_public, envir = new.env(parent = globalenv()))
r <- jsonlite::fromJSON(file.path(output, "ratings.json")); s <- jsonlite::fromJSON(file.path(output, "simulations.json"))
stopifnot(r$model == "vCurrent / C2_current", s$model == "vCurrent / C2_current + cfbseedR",
          all(is.na(r$teams$weekly_change)),                                          # previous week is the incumbent: no comparison
          identical(jsonlite::fromJSON(file.path(old, "ratings.json"))$marker, "published"),   # different-model week archive kept
          jsonlite::fromJSON(file.path(output, "2026", "week-04", "simulations.json"))$model == s$model)   # new archive written
sys.source(PATHS$export_public, envir = new.env(parent = globalenv()))               # same-model rerun still refreshes
stopifnot(identical(jsonlite::fromJSON(file.path(old, "ratings.json"))$marker, "published"))
cat("PASS: frozen artifacts, model selection, simulation routing, exporter model names and week-archive protection.\n")
