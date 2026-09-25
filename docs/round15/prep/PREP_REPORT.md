# Round 15 data preparation (P1–P5): results against the signed rules

The predeclaration was signed 2026-09-25 (SHA-256 `9cedb999…977f`). No candidate has been built or run, and no Round 15
outcome has been read. These steps touch data quality only.

| Step | Signed rule | Result | Verdict |
|---|---|---|---|
| P1 | Every FBS team present in each season's rushing and receiving stats (and the 2013 roster) | All present 2013–2026, **except New Mexico State 2020** | **FAIL (strict)** |
| P2 | 2025 fumble recovery ≥ 90% and 0 changed classifications 2013–2024 | 2025: 94.1%; 0 rows changed; live 2026: 92.5% (was 38.2%) | PASS |
| P3 | Passer parsed on ≥ 97% of dropbacks in every season | Minimum 97.7% (2024); live 2026: 98.8% | PASS |
| P4 | Unit tests pass; coverage reported; pooled r(`cont_def`, vendor defensive returning) ≥ 0.8 | 13/13 tests pass; coverage 95–100%; **r = 0.667** | **FAIL (strict)** |
| P5 | Fix and record the market-line vintage | 2026-09-25 pull, 9,784 game rows, hashed | RECORDED |

The signed response to a P1 or P4 failure is **"stop and report"**. The round is stopped at data preparation. Nothing
proceeds to candidate building until you decide.

## P1: New Mexico State, 2020

- **What happened.** NMSU's entire 2020 season was two spring games (February and March 2021) against non-FBS opponents.
  CFBD returns no 2020 player statistics for the team under any season type (`both` and `spring_regular` both checked).
  Every other team-season, 2013–2026, is present.
- **Consequence.** 2020 is never a target season. The gap only makes NMSU's 2021 continuity inputs (`cont_pass`,
  `cont_skill`, `cont_def`) missing. The signed missing-value rule already handles that: NMSU 2021 falls into a regime
  without those inputs, and nothing is zero-filled.
- **Amendment option A1.** Restate P1 as "every FBS team **that has CFBD season statistics** is present". Record NMSU 2020
  as a documented source gap handled by the missing-value rule. This changes no model definition.

## P4: defensive continuity versus the vendor figure

- **What happened.** Signed `cont_def` counts tackles by incoming transfers at their previous FBS school. The vendor
  figure counts returning players only. A report-only diagnostic (`p4_diag_def_agreement_REPORT_ONLY.csv`) recomputes the
  same machinery with own-team production only. It agrees with the vendor at **r = 0.955** pooled (0.86–0.996 by season).
- **Why the signed check fails.** The transfer component grows from 0.7% of tackles in 2017 to 19% in 2026. The check was
  meant to validate the ID matching and tackle shares, which it now confirms. It fails because it compared two different
  quantities: a check-design error made when the predeclaration was written.
- **Amendment option A2.** Apply the P4 agreement check to the own-team component, which is the concept the vendor
  measures. The signed `cont_def` definition, including transfers, stays unchanged.
- **Disclosure.** A2 would be chosen after seeing this check's result. That result involves no game outcome and no
  candidate.

**Other choice.** Keep either rule as signed. In that case the round stays stopped: a new round would need its own
predeclaration.

## Implementation notes recorded now (no specification change)

- **P2 parser.** The added 2025+ rules run only for seasons ≥ 2025, so earlier data are unchanged by construction.
  Parser SHA-256 `3b0121b6…`.
- **P3 passer parser.** Names in the two text formats are compared only within a team and season. SHA-256 `25f033f6…`.
- **P4 table.** `output/dev/round15/prep/preseason_inputs_2014_2026.csv`, SHA-256 `cdf040ea…`, 1,704 team-seasons.
- **Interpretation 1: conference level.** It is NA for FBS independents, which have no conference members, and so falls
  into the missing-value regime.
- **Interpretation 2: recruit counts.** `bluechip4` counts every recruit record CFBD returns for the team (all recruit
  types) with a known star rating.
- **Interpretation 3: 2020 success rate.** The Round 13 instrument code refuses 2020. §2 of the predeclaration makes 2020
  a previous-season input for 2021, so building last season's success rate for 2021 will bypass that guard for 2020 only,
  with an occurrence-asserted patch. This is noted now, before any candidate is built.
- **API use.** About 62 calls; 2,322 left this month.
