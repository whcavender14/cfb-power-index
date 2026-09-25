# Forward evidence: automated pre-kickoff snapshots (2026–2027)

**Purpose.** 2023–2025 are burned, so post-lock 2026 and 2027 are the only clean evidence. Their validity cannot depend on
someone remembering to run a command. This system **collects and archives evidence only**. It never retrains, refits,
promotes or deploys a model, and it never reads market data.

**Status (2026-09-25).**
- **Built and tested:** 24 unit checks pass, and live dry runs have been written to a scratch archive.
- **Not yet activated:** activation needs your approval (§6).

## 1. What runs, and when

| Task | Script | Schedule (US Eastern local time) | Why |
|---|---|---|---|
| Play-by-play pull | `scripts/forward/pull_pbp.R` | Sundays 16:00 and 18:00 | Round 13's forward rule: K's play-by-play must be pulled **before** the Monday 00:00 UTC cutoff (Sunday 20:00 EDT / 19:00 EST). A later pull is used but flagged `late_pull = TRUE` and excluded from K's forward gates. |
| Prediction snapshot | `scripts/forward/snapshot.R` | Daily 09:05 and 18:05 | Covers every kickoff window: weeknight games start after 19:00, Saturday games after 12:00. Rerunning is harmless: each run writes new files. |

The play pull fetches every regular-season or postseason week that has final games and either finished within the last 9
days or has never been pulled.

## 2. Rules each snapshot enforces (a violated rule stops the run with an error)

1. **Information cutoff.** The cutoff is Monday 00:00 UTC of the current week.
   - The incumbent uses only final FBS-vs-FBS games with kickoff + 24 h before the cutoff.
   - K uses plays of final games with kickoff + 12 h before the cutoff (Round 13 C3).
2. **Only games not yet started.**
   - Targets are this week's FBS-vs-FBS games that are not final and kick off more than 15 minutes after the snapshot.
   - Every row is re-checked against the snapshot time before writing.
   - Games already started are listed as excluded in the metadata.
3. **No backfilling.**
   - If more than 3 FBS-vs-FBS games that should be final at the cutoff have no result, no snapshot is written (exit 1).
   - If any final FBS-vs-FBS game before the cutoff lacks play-by-play, K is not written (exit 2); the incumbent is still archived.
4. **No outcomes, market or vendor-rating fields.** Scores, errors, spreads, odds, and vendor EPA/WP/Elo columns are
   rejected. Forward code cannot reference market files; a test enforces this.
5. **Frozen models only.**
   - The incumbent runs the frozen v5 design; its artifact hashes are checked.
   - K runs Round 13's code, copied byte-for-byte from tag `round13-frozen-c4819fd` (git blob `d9339f4b…`), with the frozen `w_2026 = 19.3141` (SHA-256 checked).
   - Round 15 candidates are refused until a signed Round 15 freeze manifest exists.
6. **Write-once, read-only files.** Each file is written to a temporary file, renamed atomically, then set read-only. An
   existing file is never overwritten.
7. **Hash-chained manifest.**
   - Every input and output is recorded in `manifest.csv` with its SHA-256 and the previous line's hash.
   - Each run first re-verifies the whole chain and every file's hash. An edited, deleted or altered file stops the run.
8. **Provenance.** Each snapshot's JSON records:
   - UTC snapshot time and information cutoff;
   - the input schedule pull (hash and retrieval time);
   - the play pulls used and whether each was pre-cutoff;
   - SHA-256 of every code file that ran, plus git commit, R version, package versions and host;
   - unresolved and excluded games, and fumble-parse recovery counts.

## 3. Archive layout (`$CFB_FORWARD_ARCHIVE`)

```
manifest.csv                     hash-chained, append-only record of every file
run_log.csv                      every step: ok / ok_late_pull / ok_no_targets / skipped / FAIL, with the reason
inputs/<task>_<UTC stamp>/raw_schedule_2026.rds       live schedule pulled by that run
pbp/2026/plays_<type>_wk<NN>_<UTC stamp>.rds           raw play-by-play pulls
snapshots/incumbent/2026/incumbent_2026_cut<YYYYMMDD>_<stamp>.csv (+ .md5, + .json)   v5_archive schema (Gate 5 compatible)
snapshots/round13_K/2026/round13_K_2026_cut<YYYYMMDD>_<stamp>.csv (+ .json)
logs/<stamp>_<task>.log          full console output of each run
```

## 4. Which snapshot scores a game (fixed now, before any forward result exists)

For each model and game, the scoring snapshot is the **latest** one with `information_cutoff` equal to the game's week
start and `predicted_at` at least 15 minutes before kickoff. If a game has no such snapshot, it is reported as missing and
never imputed. K's forward gates use only snapshots with `late_pull = FALSE` (Round 13 rule). Market lines for the
forward seasons are pulled after each season into a separate evaluation-only store and are never read by the snapshot code.

## 5. Failure handling

- A non-zero exit posts a macOS notification and writes the reason to `run_log.csv` and the run log.
- **Exit codes:** 0 ok; 1 nothing written (bad schedule, too many unresolved games, broken chain); 2 partial (incumbent
  written, a later model failed).
- A failed run writes nothing partial. The next scheduled run retries: twice a day for snapshots, twice each Sunday for play pulls.

## 6. Activation (needs your approval)

**Recommended: a local schedule on this Mac.**
- Run `bash scripts/forward/install_launchd.sh <commit>` after approval.
- It clones the repository at a pinned commit into `~/cfb-forward/code` and creates the archive at `~/cfb-forward/evidence`.
  Both live outside the iCloud Desktop, so macOS folder privacy cannot block the jobs and files are never evicted.
- It runs the unit tests into the install log, then loads two user LaunchAgents.
- **Limits:**
  - The Mac must be on. launchd runs a missed job once after the Mac wakes, but a Mac that is shut down misses the window.
  - Evidence timestamps are local. They can be made externally verifiable by pushing `manifest.csv` to a private
    repository after each run (optional, needs your approval).

**Alternative: a scheduled GitHub Actions job.**
- It runs without the Mac and gives third-party timestamps.
- It would add a workflow to the live site's repository (`whcavender14/cfb-power-index`) and commit evidence to a dedicated
  branch. That is a change to shared CI, so it is not done without your explicit approval.

**Known limits:**
- **2027 is blocked for the incumbent** until its frozen 2026-only design is extended (MIGRATION_AUDIT_REPORT). The
  snapshot script refuses other seasons.
- **Live fumble parsing** recovers about 38% of fumble plays in 2026 (dry run: 179 of 475). This affects K as frozen, and
  is recorded in each K snapshot's metadata.
