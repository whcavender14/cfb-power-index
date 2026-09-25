# Round 15 predeclaration: Amendment 02 (pre-scoring), revision 2

- **First recorded:** 2026-09-25T14:03Z (UTC), commit `56fde0c`.
  - SHA-256 of that version: `5be7fc5b56811525bec5bd061fd83339c02a1b00e2dea877575ab33078269634`.
- **Revision 2:** 2026-09-25T14:07Z (UTC).
  - The user's formal decisions on A4 and A5 are added.
  - Labels now follow the user's approval: core rule, A4 (ties within a game), A5 (games without a qualifying primary).
  - The first version used A4 for the core rule, with (i) and (ii) as clarifications, and A5 for season-to-date ties.
  - The rules themselves are unchanged from the first version.
- **Approved by the user in session:**
  - the core QB-change transition rule, which the user specified;
  - A4, co-primary passers in tied games;
  - A5, comparison across games without a qualifying primary passer;
  - the season-to-date tie handling, a resolution approved earlier and now superseded.
- **Amends:** `ROUND15_PREDECLARATION_v2.md`, SHA-256
  `7e076b3ccea1e47f1dc6b1cd65b83e2eeb926531c7607953a3f8d46e7e914a7c`.
  - That file, the original signed `ROUND15_PREDECLARATION.md` (`9cedb999…977f`) and `AMENDMENT_01.md` stay untouched.
- **Binding text after this amendment:** `ROUND15_PREDECLARATION_v3.md`, revision 2. Its SHA-256 is recorded in
  `predeclaration.sha256`, beside the earlier hashes and the first-recorded hashes of this amendment.

## Confirmations

- **Timing.** Candidates C1–C3 had been built and their predictions frozen, but **no Round 15 candidate had been
  scored**, before this amendment or its revision.
- **No performance result informed this amendment.** No candidate's development, conditional, market or forward
  performance was computed or inspected, and no game outcome was read.
- **How the issues were found.** The core-rule discrepancy, A4 and A5 all came from construction-only checks of C3's
  QB-change events:
  - the detector was run on synthetic passer sequences;
  - events and ties were counted on the 2016–2025 play-text inputs.
  - The user asked for this conformance check before scoring.
- **Order of events for A4 and A5.**
  - Both clarifications were proposed during construction and implemented in the first version of this amendment,
    before the user explicitly confirmed them.
  - The user then approved both.
  - Throughout, no candidate was scored.
- **Superseded outputs.** The pre-Amendment-02 C3 outputs were never scored. They are archived as superseded in
  `output/dev/round15/cand/superseded_pre_A02/`:
  - predictions `94363c9f42a4691539f06877e982bcfee49bc1abd9c9bab604b2b370305bd155`;
  - tuning `65abb9ac3aaf0ec94bf75be879c0baa417c5c7a9ed5f279861629a7f9fd127a2`.
- **What is unchanged.** Only the rule that decides which games are QB-change events changes. These parts of Candidate 3
  are unchanged:
  - the q_QB grid {0, 4, 16, 36};
  - the §6.1 estimation procedure, objective, tie and fallback rules;
  - the q grid and the order of estimation;
  - the effect of an event (q_QB added once to offense state variance at the next cutoff);
  - σ²_row;
  - the primary-passer minimum of 10 dropbacks.
- **No other change.** No other candidate, metric, gate or threshold changes.

## Core rule: QB-change detection is a transition in the game-level primary passer

**Signed language replaced** (v2 §5.4 item 2, identical in the original signed file):

> **Detection:** a change is detected when a team's primary passer in its latest game (≥ 10 dropbacks) differs from its
> season-to-date primary passer. Detection uses play text only, from games before the cutoff.

**Amended language:**

> **Detection:**
> - Each team-game's primary passer is determined by the frozen definition (§4.2, with A4 for ties).
> - At the cutoff following a game, that game's primary passer is compared with the team's primary passer in its
>   preceding qualifying game (A5). If they differ, the game is a QB-change event.
> - The same primary in later games does not re-trigger the allowance.
> - A later change of primary passer, including a return to a previous starter, is a new event and receives the same
>   one-time allowance.
> - A team's first qualifying game of the season is not an event.
> - Detection uses play text only, from games before the cutoff.
> - The season-to-date primary passer no longer decides whether an event fires.

**Examples** (the unit tests in `tests/round15/test_qb_events.R` check them):

| Primary passer by game | Events |
|---|---|
| A → A → B → B | A → B |
| A → B → A | A → B, B → A |
| A → B → C | A → B, B → C |
| A → B → B → A | A → B, B → A |
| A ×5 → B → B → A | when B replaces A, and when A replaces B |

**Why.**
- **The user's intent.** The allowance is meant to follow a genuine transition in the team's game-level starter.
- **Why the signed text fell short.** It compared against the season-to-date dropback leader, so a return to a previous
  starter who still led the season got no allowance (A ×5 → B → B → A gave no event at the return to A).

## A4: tied game-level primary passers (co-primaries)

> - If several passers tie for a game's most dropbacks and each meets the frozen ≥ 10-dropback minimum, they are all that
>   game's primary passers (co-primaries).
> - Between consecutive qualifying games:
>   - if the two games share at least one primary passer, there is no QB-change event, even if another co-primary
>     differs;
>   - if the sets of primary passers do not overlap, there is a QB-change event.
> - No alphabetical order, player-ID order, play order or any other arbitrary tie-break creates or suppresses an event.

- **What it replaces.** The per-game primary had been the first tied passer in play-data order. Under the core rule, that
  choice would directly decide events.
- **What it achieves.** It removes name- and order-dependent behavior from QB-change detection.
- **Frequency.** In 2016–2025, excluding 2020, 55 of 15,690 team-games have a tie for the most dropbacks. Breaking those
  ties by play order instead would change 25 events.
- **Consistency.** It applies the same principle as the approved season-to-date tie handling below.

## A5: games without a qualifying primary passer

> - If the immediately preceding team game has no passer who meets the frozen primary-passer requirement (or has no
>   play-by-play), the current game's primary passers are compared with the team's most recent earlier game that season
>   that has a qualifying primary passer.
> - A game without a qualifying passer is never itself a QB-change event.
> - If no earlier qualifying game exists, there is no event.
> - Only games before the relevant cutoff are used.

- **Frequency.** In 2016–2025, excluding 2020:
  - 279 comparisons span one or more earlier games without a qualifying primary passer;
  - 91 of those comparisons are events.

## Historical event classifications changed

Inputs only, no outcomes read; per season in `construction/a02_qb_event_counts.csv`.

| Seasons 2016–2019, 2021–2025 | Count |
|---|---|
| Team-games with a qualifying primary passer | 15,690 |
| Events under the previous detector (v2 rule with season-to-date tie handling) | 1,786 |
| Events under Amendment 02 (core rule + A4 + A5) | 2,276 |
| Event classifications that differ | 532 |
| — added | 511 (510 are returns to the passer who led the season in dropbacks before that game, in untied games; 1 involves a tied game) |
| — removed | 21 (all involve a tie within a game, A4) |

## Season-to-date tie handling (approved earlier; recorded; superseded)

- **The case.** The v2 rule needed a season-to-date primary passer, and the signed text did not define it when two
  passers were exactly tied in accumulated dropbacks.
- **First build.** It broke such ties by the alphabetical order of player names.
- **Approved resolution.** No alphabetical, name-based or other arbitrary ordering decides whether an event fires. A
  passer tied for the season-to-date lead does not differ from it. This is the conservative nesting direction: no shock.
- **Effect.**
  - It changed exactly one observed construction event: 2017, team 2084, game 400945007.
  - C3 was rebuilt and frozen (commit `afa860a`, tag `round15-construction-frozen`).
  - The first build (C3 predictions `d50f4a28…cd54`) was never scored.
- **Status.** Under the core rule the season-to-date primary no longer decides events, so this resolution no longer
  affects detection. Its principle carries into A4.

## Construction hashes

- **Original construction (before this amendment):**
  - `construction/CONSTRUCTION_FREEZE.sha256`, SHA-256
    `48f8bfe36c47326ed5eb8e411819a206d650b7a947a8f9b343e65f8604223085` (commit `afa860a`, tag
    `round15-construction-frozen`).
- **Post-amendment construction:**
  - C3 is rebuilt from scratch under this amendment.
  - Its freeze record is `construction/CONSTRUCTION_FREEZE_A02.sha256`.
  - The SHA-256 of that freeze record is recorded in `predeclaration.sha256` and `construction/CONSTRUCTION_NOTES.md`,
    so this file is not edited again.
