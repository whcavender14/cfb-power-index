# C2 refinement research, Stage 0 (read-only probe). Run from the round15-power-rating worktree root: it reads that worktree's
# untracked caches (output/dev/round15/...) and never writes to them. Nothing here is fitted, scored or tuned.
suppressPackageStartupMessages({library(data.table); library(tibble)})
c1 <- readRDS("output/dev/round15/cand/c1_components.rds"); c2 <- readRDS("output/dev/round15/cand/c2_components.rds")
d <- readRDS("output/dev/round15/cand/data.rds")
x <- rbindlist(lapply(c("2017","2018","2019","2021","2022","2023"), function(z) { v <- c1$varm[[z]]; p <- c2$p2[[z]]; l0 <- c1$lam0[[if (z == "2023") "2022" else z]]
  data.table(season = z, lambda0 = l0, vbar_off = v$off$vbar, vbar_def = v$def$vbar, lamFCS_off = l0 * v$off$vbar / p$v_fcs[["off"]], lamFCS_def = l0 * v$def$vbar / p$v_fcs[["def"]],
             mu_power = p$mu[["off"]] - p$mu[["def"]], rho_off = p$rho[["off"]]) }))
print(x, digits = 3)
f <- as.data.table(readRDS("output/dev/round15/prep/fcs_schedules_2013_2025.rds"))
div <- unique(rbind(f[, .(season, team_id = as.integer(home_id), div = home_division)], f[, .(season, team_id = as.integer(away_id), div = away_division)]))
suppressPackageStartupMessages({library(data.table)})
c2 <- readRDS("output/dev/round15/cand/c2_components.rds")
f <- as.data.table(readRDS("output/dev/round15/prep/fcs_schedules_2013_2025.rds")); str(f[, .(home_id, away_id, home_division)])
div <- unique(rbind(f[, .(season, team_id = as.integer(home_id), div = home_division)], f[, .(season, team_id = as.integer(away_id), div = away_division)]))
div <- div[, .(div = if (any(div %in% "fcs")) "fcs" else if (all(is.na(div))) "NA" else paste(unique(na.omit(div)), collapse = "/")), by = .(season, team_id)]
e <- rbindlist(c2$eos_full)[fcs == TRUE, .(season, team_id = as.integer(team_id), power = eff_off - eff_def)]
e <- merge(e, div, by = c("season", "team_id"), all.x = TRUE)
print(e[season %in% 2014:2022, .(entities = .N, mean_power = round(mean(power), 1)), by = div])
