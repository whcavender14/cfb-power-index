# Run every current-C2 validation from the c2-refinement worktree root: Rscript tests/c2/run_all.R
# (1) equivalence with the selected research model C2L, (2) regression against frozen Round 15 C2, (3) reproduction of the
# established Stage 3/4 results. Each script stops on failure. Requires output/dev/round15 -> the frozen Round 15 caches.
for (f in c("tests/c2/test_c2_equivalence.R", "tests/c2/test_c2_regression.R", "scripts/c2/c2_verify_performance.R")) {
  message("== ", f); st <- system2("Rscript", f, stdout = FALSE, stderr = FALSE); if (st != 0) stop(f, " FAILED") }
message("ALL C2 VALIDATIONS PASSED")
