# CFPi+ follow-ups

## Model enhancement: add title-game simulation

- **Found:** Stage 3 of the website (2026-09-26).
- **Current behavior:** the season simulation plays no conference championship games. cfbseedR names each conference's regular-season standings leader champion (with its tiebreakers). `sim$games` holds only regular-season and CFP games, and every simulated record is regular season only.
- **Metadata bug:** `sim$wins_scope` (`R/simulation/simulate_season.R`) says wins include conference championships. They do not. Fix the string, or make it true.
- **What changes if title games are added:** conference-title odds, CFP selection and seed distributions (a title-game loss would change résumés), projected wins and final-record distributions (records such as 12–1 and 11–2 would appear).
- **Scope:** R simulation code, not the website. The site already describes the current behavior (Model page, team pages, `LIMITATIONS.md`). If the simulation starts playing title games, update that text and `DATA_CONTRACT_V2.md` (`wins_dist`, `record_dist`).
- **Owner:** your decision (a model change).
