# Accessibility

## Automated check (Stage 5)

axe-core 4.10 with the WCAG 2.0/2.1 A and AA rules plus best practices. It ran on 16 pages in both themes: home, rankings, résumé, games, playoff, teams, two team pages, conferences, independents, changes, compare, what-if, model, simulations and betting.

| Issue found | Where | Fix |
|---|---|---|
| Links inside sentences distinguishable by colour only | Freshness lines, footer, notes, breadcrumbs | Underlined (`site.css`, "Links inside running text") |
| "Auto" bid badge contrast 4.4:1 (light), 4.2:1 (dark) | Playoff projected field | Darker/lighter badge text (≥ 5.8:1) |
| Muted text on selected pick / chips 4.0–4.4:1 | What if | Secondary ink colour |
| Team monograms: white on grey 2.9:1 in dark; white on light school colours | FCS opponents, missing logos | Darker neutral fallback; text colour picked by luminance (black or white) |
| No `<h1>` | `/simulations/`, `/betting/` | Visually hidden `<h1>` |
| Gold and faint text 2.8–4.4:1 | Legacy views | Legacy tokens darkened (light) / lightened (dark) |

Final result on the Stage 5 build: **0 violations on all 16 pages in both light and dark** (32 runs, including the legacy `/simulations/` and `/betting/` views).

## Conventions the site follows

- **Semantics:** one `<h1>` per page; sections labelled by their headings; tables with `<th scope>`; lists for rankings; `aria-current` on the active nav item and ranking tab; `aria-pressed` on What-if picks; `aria-sort` on sortable headers.
- **Keyboard:** every control is a native button, link, select or input. The history chart is focusable; ←/→ step through weeks and Escape closes the readout. Tooltips open on focus as well as hover. The skip link goes to the main content. The mobile menu closes on Escape and returns focus.
- **Charts have text alternatives:** the history chart has "Show as a table"; the record distribution has a full table of raw counts; bar charts carry an `aria-label` listing their values; the strength chart prints each value.
- **Never colour alone:** rank movement is an arrow plus a number plus hidden text ("Up 3"); rating changes are signed numbers; What-if changes show ▲/▼ plus the value; reconstructed history points are hollow and labelled; win/loss results show W/L.
- **Focus:** a visible 3 px focus ring on everything (`:focus-visible`).
- **Images:** team logos sit next to the team name, so they have empty `alt` (decorative); monograms are `aria-hidden`. Download buttons say what they produce.
- **Preferences:** `prefers-reduced-motion` (all transitions instant), `prefers-reduced-transparency` (solid header and What-if bar), `prefers-contrast: more` (stronger lines and borders), OS dark mode.
- **Touch:** controls are at least 44 pt tall on touch screens; small "?" and chip-remove buttons get an invisible 44 pt hit area.
