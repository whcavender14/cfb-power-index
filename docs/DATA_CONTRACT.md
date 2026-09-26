# Public data contract · version 1

> The CFPi+ pages (Home, Rankings, Games, Playoff, Teams, Conferences, Model) read the version-2 page datasets in `public/data/v2`: see [website/DATA_CONTRACT_V2.md](website/DATA_CONTRACT_V2.md). The version-1 files below are unchanged and still feed `/simulations/`, `/betting/` and the PNG exports.

The browser fetches `ratings.json` and `simulations.json` from `public/data/`. Each is an object containing a `teams` array, not a bare array. UTF-8 JSON, HTTPS logos, UTC ISO-8601 timestamps, and stable string team IDs are required. Team membership is the supplied season-specific FBS metadata, not a hard-coded count.

## Common envelope

| Field | Type | Meaning |
| --- | --- | --- |
| `schema_version` | integer | `1` |
| `season` | integer | Football season year; not necessarily the update’s calendar year |
| `week` | integer or null | Source’s latest completed week; 0 means actual preseason, null means unavailable |
| `updated_at` | string or null | Source result timestamp, formatted `YYYY-MM-DDTHH:mm:ssZ`; exporting never makes old data fresh |
| `status` | string | `available` if at least one current rating/projection exists; otherwise `unavailable` |
| `model` | string | Source model name, `vCurrent / <candidate>` (simulations append ` + cfbseedR`); the candidate is the production model that built the ratings: `C2_current` since 2026-09-26, `EB_features` before |
| `teams` | array | One row per supplied FBS team; unique `team_id` |

Ratings also publish `rated_teams`, `total_teams`, `defensive_higher_is_better`, `weekly_comparison_week`, and `preseason_source`. Simulation metadata includes `simulation_count`, `playoff_format`, `wins_scope`, `as_of` (model information cutoff), `assumptions`, and `unavailable_reason`. Missing metadata is null. A successfully executed simulation’s `updated_at` is its run time, while `as_of` is the earlier information cutoff.

## Identity fields in both team-row types

| Field | Type | Source |
| --- | --- | --- |
| `season` | integer | Envelope season |
| `week` | integer or null | Envelope week, independently determined for each dataset |
| `updated_at` | string or null | Envelope timestamp |
| `team_id` | string | `teams_<season>.rds$team_id`, normalized to string |
| `team` | string | Team metadata’s `school` |
| `conference` | string or null | Team metadata’s `conference` |
| `logo_url` | string or null | Original team metadata `logo`, currently CollegeFootballData’s CDN |

## `ratings.json` team metrics

| Field | Type | Definition / source mapping |
| --- | --- | --- |
| `power_rating` | number or null | Production snapshot `power_rating`; offense minus defense, measured in points relative to the model’s FBS average |
| `offensive_rating` | number or null | Production snapshot `off_rating`; positive is above-average offense |
| `defensive_rating` | number or null | Production snapshot `def_rating`, preserved without sign changes; lower (more negative) is better defense |
| `weekly_change` | number or null | Current power minus `production_ratings_<season>_wk<week-1>.rds` with matching candidate, design hash, and feature hash power for the same team; null if the exact prior week or either value is absent |
| `preseason_change` | number or null | Current power minus the same production row’s `pre_power`; null if either value is absent |

No rank is exported: the browser derives global rank from available power ratings before filtering. An unrated team remains in the table with null metrics and no rank. There is no fallback from missing current ratings to preseason values.

## `simulations.json` team metrics

| Field | Type | Definition / source mapping |
| --- | --- | --- |
| `projected_wins_current` | number or null | `sim$overall$wins`: mean overall wins, including conference championship games under the supplied cfbseedR rules |
| `projected_wins_preseason` | number or null | Matching `overall$wins` from an independently saved week-0 simulation, with an identical `wins_scope` |
| `playoff_probability` | number or null | `sim$overall$playoff`, a fraction in `[0,1]` |
| `conference_title_probability` | number or null | `sim$overall$conf_champ`, a fraction in `[0,1]` |
| `national_title_probability` | number or null | `sim$overall$won_natty`, a fraction in `[0,1]` |
| `vegas_win_total_preseason` | number or null | Independently supplied market total; not fitted, inferred, or copied from a model projection |

The simulation function’s result fields and conference-championship win semantics are documented in [cfbseedR](https://github.com/sportsdataverse/cfbseedR). The application calls these **overall** projected wins. A supplied regular-season Vegas line can have a different counting basis; it is displayed separately and never subtracted from the model projection.

Production snapshots are lists containing `season`, `week`, `updated_at`, `as_of`, `candidate`, `design_hash`, `feature_hash`, and a `ratings` data frame. `run_2026_rankings.R` writes both latest and numbered-week files. The exporter never falls back to legacy weekly-model RDS or preseason CSV files.

## `betting.json`

This separate schema-version-1 envelope contains `season`, upcoming `week`, `season_type`, export `updated_at`, `ratings_updated_at`, `hfa`, `hfa_source`, `schedule_updated_at`, `schedule_status`, `schedule_source`, `market_source`, `market_retrieved_at`, `market_status`, `provider_policy`, and a `games` array. Latest and season/week archives are exported. Ratings timestamps must match before the browser combines ratings with this HFA. Missing HFA prevents home-site calculations; neutral-site calculations still work.

Each game contains unique string `game_id`; integer `week`; string `season_type`; UTC `kickoff` or null; boolean `time_tbd`; string `away_team_id`, `away_team`, `home_team_id`, `home_team`; boolean or null `neutral_site`; number or null `market_spread`; and nullable `market_provider`, `market_retrieved_at`, `market_updated_at`. Missing venue information is not assumed to be a home site. FCS opponents remain in the schedule but do not receive invented power ratings.

`market_spread` is the home-team handicap in points, normalized against the provider's formatted team line. Quotes with inconsistent team identities or magnitudes and synthetic zero fallbacks are rejected. `market_updated_at` is null because this source does not expose the bookmaker's timestamp; retrieval time is reported separately. No client requests require credentials.

The browser computes model spread as away power minus home power minus HFA (zero on neutral sites), using the exact same function for both sections. Signed difference is model minus market and absolute difference is its magnitude. Negative difference indicates potential home-side value; positive indicates away-side value. Missing operands yield null. Display rounds to one decimal, while sorting uses full precision and always puts unavailable values last.

## R simulation input

`cfb_data/simulations_<season>_latest.rds` must contain `overall` (data frame), `season`, `week`, `updated_at`, `as_of`, `simulation_count`, `playoff_format`, `wins_scope`, and `simulation_assumptions`. `overall` uses `team` or `team_id` and the exact cfbseedR column names above. The updated supplied simulation script writes this file automatically. FCS opponents are retained inside the simulation but excluded from public FBS rows.

An optional `simulations_<season>_preseason.rds` uses the same structure, with `week = 0L` and a matching season. It must be a genuinely archived preseason result. The exporter will not generate one using current information or reinterpret a current snapshot as preseason.

An optional `cfb_data/vegas_<season>_preseason.csv` contains:

```text
season,team_id,vegas_win_total_preseason
```

Only real supplied rows belong in this file. `team` may be used instead of `team_id` if it exactly matches a metadata name or supplied alias. Every team with no line stays null. This CSV is excluded from automatic public commits; its exported allowlisted column is included in JSON.

## Identity, validation, and failure rules

The ratings/simulations exporter joins by team ID, using exact metadata names and supplied aliases only when an input lacks IDs. It rejects duplicate resolved IDs, wrong seasons, nonfinite numeric values, and probabilities outside `[0,1]`. It does not call providers or fit models. The separate betting exporter uses the server-side CFBD environment credential to request the official API; it never exports credentials or scrapes sportsbooks.

When the weekly runner records a failed simulation attempt, the exporter hides any older cached current simulation, emits null current metrics, and clears its timestamp. An independently supplied preseason or Vegas baseline may still appear. Historical JSON archives are not deleted. If team membership itself cannot be established, export fails. If a JSON fetch fails or the browser rejects its schema, the affected view displays “Data unavailable” and offers a retry.
