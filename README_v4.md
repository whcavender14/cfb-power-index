# College football ratings, round 3

Read [the report](outputs/round3/REPORT.md) first. The development-selected convex blend has locked MAE12.830 versus frozen-v3 MAE12.938 and market12.019. The improvement is modest and uncertain under period-block resampling. Early bias, compressed margins and conference residual differences remain. This is a research candidate; the requested final production standard is not met.

The separately versioned `cfb_power_ratings_v4.R` retains legacy helpers for comparison and implements the new `v4_*` model functions. Source `cfb_v4_operations.R` for build/update/archive operations. Do not call the inherited v3 public build/validation functions by mistake. V3 itself is unchanged.

- [Audit](outputs/round3/AUDIT.md)
- [Formulas and interpretation](outputs/round3/MODEL_SPEC.md)
- [Candidate ledger](outputs/round3/CANDIDATES.md)
- [Zero/one-game teams](outputs/round3/ZERO_ONE.md)
- [Feature status](outputs/round3/FEATURES.md)
- [Commands](outputs/round3/COMMANDS.md)
- [Test results](outputs/round3/tests.csv) and [integration checks](outputs/round3/integration_tests.csv)

All predictions, metrics, graphs, component snapshots, frozen design and prospective archive are in `outputs/round3/`.
