# =====================================================================================================================
# scripts/production/c2_freeze_season_inputs.R: ONE-TIME build of Current C2's frozen 2026 season inputs.
#
# Round 16 §9: "The 2026 C1 prior and 2025 end-of-season inputs are computed by the frozen code. The forward build is
# committed and hashed before its first snapshot." This script does exactly that and nothing else:
#   * the 2026 C1 preseason prior: r15_c1_prior(), parameters through 2022; preseason information only (2026 preseason
#     inputs, history through 2025, and 2026 FBS membership from the frozen 2026 schedule);
#   * the 2025 end-of-season group level (the 2026 anchor): c2_eos_levels() + c2_anchors();
#   * the season-input list c2_season_inputs() returns (C1 scale and precisions, C2's beta/kappa/FCS moments/omega,
#     end-of-season fits, division pools, anchor), all from the canonical code with no modification.
# The weekly production build (R/production/c2_production.R) reads this file and verifies its MD5. It never recomputes
# any of it. Needs the research caches under output/dev/round15 (not available in CI) and refuses to overwrite.
#
# Usage (project root): Rscript scripts/production/c2_freeze_season_inputs.R
# Writes: data/frozen/c2/c2_season_inputs_2026.rds, c2_prior_2026.csv (inspection copy), provenance_2026.csv
# =====================================================================================================================
source("config/paths.R"); source("config/production.R")
suppressPackageStartupMessages({ source(PATHS$model_ops); library(data.table); library(digest)
  for (f in c("data", "c1", "c2")) source(sprintf("R/round15/candidates/%s.R", f)); source("R/c2/c2_current.R") })
Y <- 2026L
out <- file.path(PATHS$frozen, "c2"); f_s <- file.path(out, sprintf("c2_season_inputs_%d.rds", Y))
stopifnot(!file.exists(f_s)); dir.create(out, recursive = TRUE, showWarnings = FALSE)
sha <- function(p) digest(file = p, algo = "sha256")

src <- c(data = file.path(R15C$cache, "data.rds"), c1 = file.path(R15C$cache, "c1_components.rds"),
         c2 = file.path(R15C$cache, "c2_components.rds"), fcs = "output/dev/round15/prep/fcs_schedules_2013_2025.rds")
d <- r15_build_data(); c1 <- readRDS(src[["c1"]]); c2 <- readRDS(src[["c2"]])
dv <- c2_divisions(as.data.table(readRDS(src[["fcs"]])))

# 2026 C1 prior (preseason information only).
d2 <- d; d2$sch[[as.character(Y)]] <- v4_schedule(Y)
c1x <- c1; c1x$priors[[as.character(Y)]] <- r15_c1_prior(d2, Y, 2022L, r15_bind_incumbent())

# End-of-season levels 2013-2025 and the 2026 anchor (latest season before 2026, 2020 excluded): the c2_run() path.
levels <- rbindlist(lapply(2013:(Y - 1L), function(s) c2_eos_levels(d, s, dv)))
canon <- fread("../c2-refinement/output/c2/current/c2_anchor_history.csv")
chk <- merge(levels, canon, by = "season", suffixes = c("", "_canon"))
stopifnot(nrow(chk) == nrow(levels), max(abs(chk$fcs - chk$fcs_canon)) < 1e-9,
          max(abs(chk$gap - chk$gap_canon), na.rm = TRUE) < 1e-9)
anch <- c2_anchors(levels, Y)

S <- c2_season_inputs(d2, c1x, c2, Y, dv, anch)
S$frozen <- list(season = Y, spec = C2_SPEC, research_tag = "c2-post-stage4-baseline",
                 built_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                 git_commit = system2("git", c("rev-parse", "HEAD"), stdout = TRUE),
                 note = "S$dv holds divisions through 2025; the production build appends the current season's divisions from its live FCS pull.")
saveRDS(S, f_s)
fwrite(S$prior, file.path(out, sprintf("c2_prior_%d.csv", Y)))
prov <- data.table(item = c("season_inputs", "prior_csv", names(src), "c2_current.R", "c1.R", "c2.R", "data.R", "frozen_schedule_2026"),
                   path = c(f_s, file.path(out, sprintf("c2_prior_%d.csv", Y)), src, "R/c2/c2_current.R", "R/round15/candidates/c1.R",
                            "R/round15/candidates/c2.R", "R/round15/candidates/data.R", frozen_path("cfb_data_v3", "raw_schedule_2026.rds")))
prov[, `:=`(md5 = unname(tools::md5sum(path)), sha256 = vapply(path, sha, ""), bytes = file.size(path))]
fwrite(prov, file.path(out, sprintf("provenance_%d.csv", Y)))
cat(sprintf("Froze C2 %d inputs: %d FBS priors; a = %.6f; anchor season %d (FCS level %.4f, gap %.4f); omega %.4f\n", Y, nrow(S$prior),
            S$a, S$anchor$anchor_season, S$anchor$fcs, S$anchor$gap, S$omega))
print(prov[, .(item, md5, bytes)])
