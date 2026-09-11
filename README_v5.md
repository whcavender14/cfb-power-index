# CFB ratings v5 — Round 4

Start with [the Round 4 report](outputs/round4/REPORT.md), [feature audit](outputs/round4/FEATURE_AUDIT.md), [model specification](outputs/round4/MODEL_SPEC.md), and [reproducible commands](outputs/round4/COMMANDS.md).

Selected on 2019/2021/2022 matched development: EB_features, a precision4 joint score update with separately fitted offense/defensive-burden offseason priors. Development MAE 12.920 versus B 13.238; conditional 2023–2025 MAE 12.518 versus B 12.830. Conditional seasons are previously exposed. The matched market still leads, 12.019 MAE.

Use `source('cfb_v5_operations.R')` and `v5_build()`, `v5_weekly_update()`, `v5_validate_features()`, `v5_validation()`, or `v5_archive_upcoming()`. Model and feature hashes are frozen; new feature snapshots require separate versioning. Exact historical publication times remain unverified, rather than fabricated or used as an automatic exclusion. Missing external inputs fall back to B.

Files in v4 and outputs/round3 remain unchanged. The initial invalid Round 4 scale calculation is preserved and disclosed under outputs/round4/pre_fix_invalid_run and IMPLEMENTATION_CORRECTION.md; use only the corrected final results.
