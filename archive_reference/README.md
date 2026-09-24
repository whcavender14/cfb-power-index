# archive_reference/

A small set of historical documents kept here so they are close at hand. They are **reference only**: nothing in `R/` or `scripts/` reads them.

| Item | Why it is here |
|---|---|
| `PROJECT_CONTEXT_AND_ROUND_HISTORY.md` | The project's own decision record and governance rules. It existed only on git branch `codex/round13-tier-carry`. |
| `round_reports/R03…R12_*.md`, `side_*.md` | The final report of every round (plus the Round 4 model spec, feature audit, calibration decision and predeclaration) |
| `round_reports/R12_PREDECLARATION_template.md` | The most complete predeclaration, to copy as the template for the next round |
| `forward_validation_gate5/` | The **locked** v10_refined forward test: `gate5_2026.R` (verbatim, sha256 `69bf5372…`), the **signed** Amendment 2 (sha256 `2f0c6064…`, recovered from the Claude worktree), the hash file, the predeclaration and the interim reports |

About Gate 5:

- **Do not edit these files.** Their hashes are part of a locked protocol.
- `gate5_2026.R` still `setwd()`s into the old folder and reads snapshots from `outputs/round4/prospective`. See `docs/EVALUATION_PROTOCOL.md` §6 before the final look, which is on or after 2028-02-01.

Everything else from past rounds (code, CSVs, caches) is listed in `docs/legacy_file_manifest.md`.
