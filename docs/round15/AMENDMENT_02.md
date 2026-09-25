# Round 15 predeclaration: Amendment 02 (pre-scoring)

- **Recorded:** 2026-09-25T14:03Z (UTC).
- **Approved by the user in session:**
  - A4, the Candidate 3 QB-change transition rule, which the user specified;
  - A5, the tie handling for the season-to-date lead (approved), recorded here for completeness.
- **Amends:** `ROUND15_PREDECLARATION_v2.md`, SHA-256
  `7e076b3ccea1e47f1dc6b1cd65b83e2eeb926531c7607953a3f8d46e7e914a7c`.
  - That file, the original signed `ROUND15_PREDECLARATION.md` (`9cedb999…977f`) and `AMENDMENT_01.md` stay untouched.
- **Binding text after this amendment:** `ROUND15_PREDECLARATION_v3.md`. Its SHA-256 is recorded in
  `predeclaration.sha256` beside the earlier hashes.

## Confirmations

- **Timing.** Candidates C1–C3 had been built and their predictions frozen, but **no Round 15 candidate had been
  scored**.
- **No performance result informed this amendment.** No candidate's development, conditional, market or forward
  performance was computed or inspected, and no game outcome was read.
- **How the discrepancy was found.** It came from construction-only checks of C3's QB-change events:
  - the detector was run on synthetic passer sequences;
  - events were counted on the 2016–2025 play-text inputs.
  - The user asked for this conformance check before scoring.
- **What is unchanged.** Only the rule that decides which games are QB-change events changes. These parts of Candidate 3
  are unchanged:
  - the q_QB grid {0, 4, 16, 36};
  - the §6.1 estimation procedure, objective, tie and fallback rules;
  - the q grid and the order of estimation;
  - the effect of an event (q_QB added once to offense state variance at the next cutoff);
  - σ²_row;
  - the primary-passer definition (most dropbacks, ≥ 10).
- **No other change.** No other candidate, metric, gate or threshold changes.

## A4: QB-change detection is a transition in the game-level primary passer

**Signed language replaced** (v2 §5.4 item 2, identical in the original signed file):

> **Detection:** a change is detected when a team's primary passer in its latest game (≥ 10 dropbacks) differs from its
> season-to-date primary passer. Detection uses play text only, from games before the cutoff.

**Amended language:**

> **Detection:**
> - Each team-game's primary passer is determined by the frozen definition (§4.2).
> - At the cutoff following a game, that game's primary passer is compared with the team's primary passer in its
>   preceding game. If they differ, the game is a QB-change event.
> - The same primary in later games does not re-trigger the allowance.
> - A later change of primary passer, including a return to a previous starter, is a new event and receives the same
>   one-time allowance.
> - A team's first game of the season with a primary passer is not an event.
> - Detection uses play text only, from games before the cutoff.
> - The season-to-date primary passer no longer decides whether an event fires.
>
> Two clarifications, needed because the frozen definition does not cover these cases:
> - **(i) Preceding game.** The preceding game is the team's most recent earlier game that season with a primary passer.
>   A game without a passer who has ≥ 10 dropbacks, or without play-by-play, has no primary passer: it is skipped and
>   is never an event.
> - **(ii) Ties within a game.** If passers tie for a game's most dropbacks, they are all that game's primary passers
>   (co-primaries). Two games' primaries differ only if they share no passer. No name-based or play-order tie-break is
>   used.

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
- **Scale.**
  - 511 events are added under A4. 510 are returns to the passer who led the season in dropbacks, in games without a
    tie; 1 involves a tied game.
  - 21 events are removed; all involve a tie within a game (see clarification (ii) below).

**Why clarification (ii).** It extends the tie principle the user approved in A5 to ties within a game. In 2016–2025,
excluding 2020, 55 of 15,690 team-games have a tie for the most dropbacks. Resolving those ties by play order instead
would change 25 events.

**Why clarification (i).** "The preceding game" needs a primary passer to compare with. In 2016–2025, excluding 2020:
- 279 comparisons span one or more earlier games without a primary passer;
- 91 of those comparisons are events.

**Historical event classifications changed** (inputs only; `construction/a02_qb_event_counts.csv`):

| Seasons 2016–2019, 2021–2025 | Count |
|---|---|
| Team-games with a primary passer | 15,690 |
| Events before A4 (v2 rule with A5 tie handling) | 1,786 |
| Events under A4 | 2,276 |
| Classifications changed | 532 (511 added, 21 removed) |

## A5: ties for the season-to-date lead (approved; recorded)

- **The case.** The v2 rule needed a season-to-date primary passer, and the signed text did not define it when two
  passers were exactly tied in accumulated dropbacks.
- **First build.** It broke such ties by the alphabetical order of player names.
- **Approved resolution.** No alphabetical, name-based or other arbitrary ordering decides whether an event fires. A
  passer tied for the season-to-date lead does not differ from it. This is the conservative nesting direction: no shock.
- **Effect.**
  - It changed exactly one observed construction event: 2017, team 2084, game 400945007.
  - C3 was rebuilt and frozen (commit `afa860a`, tag `round15-construction-frozen`).
  - The first build (C3 predictions `d50f4a28…cd54`) was never scored.
- **Status under A4.** The season-to-date primary no longer decides events, so A5 has no effect on the rule. Its principle
  carries into A4 clarification (ii).

## Construction hashes

- **Original construction (before this amendment):**
  - `construction/CONSTRUCTION_FREEZE.sha256`, SHA-256
    `48f8bfe36c47326ed5eb8e411819a206d650b7a947a8f9b343e65f8604223085` (commit `afa860a`, tag
    `round15-construction-frozen`).
  - C3 predictions `94363c9f…d155`, never scored. That file is kept at
    `output/dev/round15/cand/superseded_pre_A02/`.
- **Post-amendment construction:**
  - C3 is rebuilt from scratch after this record is committed.
  - Its freeze record is `construction/CONSTRUCTION_FREEZE_A02.sha256`.
  - The SHA-256 of that freeze record is added to `predeclaration.sha256` after the rebuild, so this file is not edited
    once hashed.
