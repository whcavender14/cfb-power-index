# Round 15 P4 unit tests for the preseason reconstruction (R/round15/prep/reconstruct.R). No outcomes are read.
# Run from the repo root: Rscript tests/round15/test_reconstruct.R
source("config/paths.R"); source("config/production.R")
suppressPackageStartupMessages({ source(PATHS$model_ops); library(data.table); source("R/round15/prep/reconstruct.R") })
n <- 0L; check <- function(ok, what) { if (!isTRUE(ok)) stop("FAIL: ", what, call. = FALSE); n <<- n + 1L; cat("ok -", what, "\n") }
eq <- function(a, b) isTRUE(all.equal(a, b, tolerance = 1e-12))

# continuity: returning players count, transfers-in count at their new team, drafted players do not, cap 1.5, promoted NA
stats <- data.table(playerId = c("1", "2", "3", "4", "5"), team = c("A", "A", "A", "B", "B"), statType = "ATT",
                    stat = as.character(c(300, 100, 50, 400, 20)))
prod <- r15_prod(stats, "ATT", c("A", "B"))
roster <- data.table(id = c("1", "3", "4", "5", "9"), team = c("A", "A", "A", "B", "C"))
c1 <- r15_continuity(prod, roster, drafted_ids = "3", teams_y = c("A", "B", "C"))
check(eq(c1[team == "A", cont], pmin(1.5, (300 + 400) / 450)), "continuity: returning + transfer-in counted, drafted excluded, capped at 1.5")
check(eq(c1[team == "B", cont], 20 / 420), "continuity: players who left are not counted")
check(is.na(c1[team == "C", cont]), "continuity: team without prior FBS production is NA, not 0")
c2 <- r15_continuity(prod, roster, drafted_ids = character(), teams_y = "A", cap = 10)
check(eq(c2$cont, (300 + 50 + 400) / 450), "continuity: uncapped arithmetic")
check(eq(r15_continuity(prod, roster[id != "4"], character(), "A")$cont, 350 / 450), "continuity: no transfer, plain returning share")

# [A2] returning-player component (validation only): transfers-in and drafted players excluded, no cap
co <- r15_continuity_own(prod, roster, drafted_ids = "3", teams_y = c("A", "B", "C"))
check(eq(co[team == "A", cont_own], 300 / 450) && eq(co[team == "B", cont_own], 20 / 420) && is.na(co[team == "C", cont_own]),
      "cont_own: own-team returning production only (transfer-in and drafted excluded)")

# QB transfer-in
q <- r15_qb_xfer_in(prod, roster, c("A", "B", "C"))
check(q[team == "A", qb_xfer_in] == 1 && q[team == "B", qb_xfer_in] == 0, "qb_xfer_in: >=100-attempt passer from another FBS team")
check(r15_qb_xfer_in(prod, data.table(id = "1", team = "A"), "A")$qb_xfer_in == 0, "qb_xfer_in: own returning QB is not a transfer")

# recruiting
cl <- data.table(year = c(2019, 2020, 2021, 2022, 2022, 2019, 2021), team = c("A", "A", "A", "A", "B", "C", "C"), points = c(200, 220, 240, 260, 150, 100, 120))
t4 <- r15_talent4(cl, 2022, c("A", "B", "C"))
check(is.na(t4[team == "B", talent4]), "talent4: fewer than 2 of the 4 classes gives NA")
raw <- c(A = mean(c(200, 220, 240, 260)), C = mean(c(100, 120)))
check(eq(t4[team == "A", talent4], unname((raw["A"] - mean(raw)) / sd(raw))), "talent4: mean of classes y-3..y, z-scored within season")
rc <- data.table(year = c(2020, 2021, 2022, 2018), committedTo = c("A", "A", "A", "A"), stars = c(5, 3, 4, 5))
check(eq(r15_bluechip4(rc, 2022, "A")$bluechip4, 2 / 3), "bluechip4: classes y-3..y only; share of 4-5 star")

# conference level excludes the team; independents NA
mem <- data.table(team_id = 1:4, conf = c("X", "X", "X", "FBS Independents"))
last <- data.table(team_id = 1:4, eff_off = c(1, 2, 3, 9), eff_def = c(0, 1, 2, 9))
cf <- r15_conf_level(mem, last)
check(eq(cf[team_id == 1, conf_off], 2.5) && eq(cf[team_id == 1, conf_def], 1.5), "conference level: mean of the other members")
check(is.na(cf[team_id == 4, conf_off]), "conference level: FBS independents are NA")

# coaching port reproduces the incumbent's frozen features exactly (2015-2026)
feat <- as.data.table(readRDS(file.path(PATHS$frozen, "outputs/round4/features.rds"))$features)
co <- as.data.table(readRDS(file.path(PATHS$frozen, "cfb_data_v2/coaches_1989_2026.rds")))
mm <- rbindlist(lapply(2015:2026, function(y) { g <- v4_schedule(y); k <- min(g$kickoff[g$home_fbs | g$away_fbs])
  merge(feat[season == y, .(team_id = as.integer(team_id), f_lt = log_tenure, f_nc = new_coach)], r15_coach(co, y, k), by = "team_id", all.x = TRUE) }))
check(identical(is.na(mm$f_lt), is.na(mm$log_tenure)) && eq(mm$f_lt[!is.na(mm$f_lt)], mm$log_tenure[!is.na(mm$log_tenure)]) &&
      eq(mm$f_nc[!is.na(mm$f_nc)], mm$new_hc[!is.na(mm$new_hc)]), "coaching port equals the frozen incumbent features for 2015-2026")
cat(sprintf("\n%d checks passed\n", n))
