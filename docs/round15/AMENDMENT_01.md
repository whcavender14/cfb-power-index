# Round 15 predeclaration: Amendment 01 (pre-candidate)

- **Recorded:** 2026-09-25T01:20Z (UTC).
- **Approved by the user in session:** A1 and A2 explicitly; A3 as a formal resolution of the 2020 success-rate guard,
  which the user requested.
- **Amends:** `ROUND15_PREDECLARATION.md`, signed 2026-09-25, SHA-256
  `9cedb999541d7cdf7f2a576ed860e09483d2e46e19210f0b59455d913a6a977f`. That file and its hash stay untouched.
- **Binding text after this amendment:** `ROUND15_PREDECLARATION_v2.md`. Its SHA-256 is recorded in
  `predeclaration.sha256` next to the original.

## Confirmations

- When this amendment was made, **no Round 15 candidate had been built, run or scored**.
- **No Round 15 candidate outcome and no game-outcome analysis informed any amendment.**
  - A1 and A2 respond to preparation checks P1 and P4, which examine data availability and data fidelity only.
  - A3 resolves a code guard before Candidate 2 is built.
- **Disclosure:** A2's replacement validation target was chosen after the report-only diagnostic showed its value
  (r = 0.955). That diagnostic compares two data series and involves no game outcome and no candidate.

## A1: P1 completeness rule (data availability)

- **Why it was necessary.** The signed rule required every FBS team in every season. CFBD has no 2020 statistics for New
  Mexico State under any season type.
  - NMSU's entire 2020 season was two spring games against non-FBS opponents (2021-02-21 vs Tarleton State; 2021-03-07 vs
    Utah Tech).
  - The team-specific queries with `seasonType` = `both` and `spring_regular` return 0 rows.
  - The rule assumed a completeness the source cannot provide.
- **Amended rule.**
  - Every FBS team-season **for which CFBD provides the required statistics** must be present.
  - A team-season missing from the season pulls counts as a **source gap** only if team-specific queries for that team,
    season and category (`seasonType` = `both` and `spring_regular`) return no rows.
  - Every source gap is listed in the preparation report and the final methodology. It is handled by the existing
    missing-data rule (§5.2): the affected inputs are missing and the team uses the regime without them.
  - Source gaps are **never** zero-filled, imputed from later information, or manually fabricated.
- **Known source gap:** New Mexico State 2020.
  - 2020 is not an evaluation season.
  - The only consequence is that NMSU's 2021 continuity inputs (`cont_pass`, `cont_skill`, `cont_def`) are missing.

## A2: P4 defensive-continuity validation target (validation only; the feature is unchanged)

- **Why it was necessary.** The signed check compared the Round 15 variable `cont_def` with the vendor's defensive
  returning-production series, but the two measure different things:
  - `cont_def` includes incoming transfers' prior production;
  - the vendor series counts returning players only.
  The transfer share grows from 0.7% of tackles (2017) to 19% (2026). The full comparison therefore gave r = 0.667, a
  mismatch of concepts, not a reconstruction error.
- **Amended rule.** The agreement test applies to the **returning-player component** of the reconstruction:

  `cont_def_own` = team *i*'s *y*−1 tackles by players who were on team *i* in *y*−1, are on its *y* roster, and were not
  drafted in April *y*, divided by team *i*'s *y*−1 tackle total.

  - **Pass:** pooled Pearson r(`cont_def_own`, vendor defensive returning) ≥ 0.8 wherever both exist. The per-season
    range is reported.
  - **Diagnostic value (already observed):** r = 0.955 pooled (n = 850), 0.861–0.996 by season.
- **Unchanged.** The candidate input `cont_def` stays exactly as signed, transfers included. Only the validation target changes.

## A3: 2020 success rate as a previous-season input (resolves the Round 13 guard)

- **Why Round 13 refused 2020.** Round 13's predeclaration excluded 2020 "throughout". Its success-rate measure was only a
  current-season input for 2017+ targets and never needed 2020. Its fidelity gate also had no Round 8 reference cache for
  2020. The instrument code enforces this with three guards:
  - `r13_schedule`: asserts no 2020 rows;
  - `r13_eligible`: drops 2020 plays as `excluded_2020`;
  - `r13_effects`: asserts the season is not 2020.
- **Why Round 15 needs it.** Predeclaration §4.1 uses `last_sr_off` and `last_sr_def` (season *y*−1's end-of-season
  success rate) in the prior. §2 already makes 2020 a previous-season input for 2021 but never a target or response
  season. That is the project-wide rule (`docs/EVALUATION_PROTOCOL.md`), which the incumbent follows for its 2020
  score ratings.
- **Permitted data:**
  - the plays of 2020-season games: every CFBD 2020 game, including its postseason and spring 2021 games, all completed
    before the 2021 season;
  - the 2020 frozen schedule (`data/frozen/cfb_data_v3/raw_schedule_2020.rds`), used for official finals in the scoreboard
    repair.
- **Calculation.** The Round 13 instrument, frozen (eligibility, garbage filter, P2 fumble parser, λ 0.5/0.5, no decay,
  FBS+FCS plays), with one end-of-season cutoff: 1 second after the latest `available_at` of any 2020 game.
- **Code change.** Only the three 2020 guards above are neutralized. This is done by a source patch that asserts each
  guard occurs exactly once, and it applies **only** to the call that builds 2020 end-of-season effects. Every other rule
  stays in force.
- **Scope.**
  - 2020 remains excluded as a target, response, scoring, tuning, calibration or inner-tuning outcome season, exactly as signed.
  - The exception only builds the past information available entering 2021.
  - No data from 2021 or later enters the 2020 calculation.
- **Compatibility criteria.** These are fixed now, before any 2020 success rate is computed.
  - **(a) Game coverage:** the share of final 2020 FBS-vs-FBS games in which both offenses have ≥ 1 eligible play is at
    least the minimum over 2014–2019, minus 0.02.
  - **(b) Play volume:** mean eligible plays per covered game is within 0.85–1.15 × the median of the 2014–2019 seasonal means.
  - **(c) Parsing:** 2020 fumble-play recovery ≥ 90% and passer parsing ≥ 97%. The P2/P3 results already show 98.5% and
    98.4%, so (c) holds.
  - **(d) Leakage:** a test confirms that altering any 2021+ datum leaves 2020 effects unchanged.
- **If any criterion fails:** stop and report. No workaround; 2021's `last_sr` is not silently treated as missing.
