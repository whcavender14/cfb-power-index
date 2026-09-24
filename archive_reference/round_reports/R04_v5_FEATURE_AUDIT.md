# Round 4 source audit

User instructions control eligibility. Round 3's missing-timestamp exclusions are historical findings, not Round 4 rules. No Round 3 file is changed.

## Returning production: eligible, historical vintage unverified

The installed cfbfastR loader and [official documentation](https://cfbfastr.sportsdataverse.org/reference/load_cfb_returning_production.html) identify these as shares of preceding-season production returning, indexed by the entering season. The loader reads season-named SportsDataverse release parquet files. The cache has separate off_returning and def_returning fractions, with no target-season outcomes. Season keys are unique and shares are in [0,1]. Inspection identified no target-season contamination. Use these observations in primary RP models. This assessment is consistent with the documented construction; it is not independent authentication of every historical roster state or every contributor. Historical revisions and exact production weights cannot be fully reconstructed from the aggregate cache.

FBS-only coverage is in feature_coverage.csv. The raw 2021 count (146) is misleading: 128/130 FBS teams have offense, 47/130 defense. Defense is wholly absent before 2017 and sparse through 2021. Missing defense never eliminates available offense. Missing unit features use an earlier-trained eligible subset, or B for that unit. No unavailable feature is assigned zero.

Exclude overall_returning (redundant/ambiguous unit aggregation), n_returning (unit definition insufficiently specific), and is_estimated from football predictors. Preserve is_estimated as provenance: it is missing for all pre-2026 observations, FALSE for 2026 records. It does not establish a higher-provenance historical subset. No independently stronger historical vintage or contributor-construction subset was supplied or recovered, so that sensitivity has zero supported forward folds. This limitation does not exclude the main historical feature. RP, offense-only, defense-only, and B comparisons are implemented.

## Talent/recruiting: eligible, historical vintage unverified

The [official talent loader](https://cfbfastr.sportsdataverse.org/reference/load_cfb_team_talent.html) and installed implementation read season-indexed SportsDataverse talent composites. Cached fields are talent_composite, blue_chip_ratio, n_recruits and talent_rank. No outcome fields exist. Use log1p(composite), raw blue-chip fraction, log1p(recruit count), all standardized only on fold training rows. Drop talent_rank rather than adding a redundant rank representation. No target-season outcome normalization. Eligibility assumes documented season-specific recruiting/talent construction describes entering-season information; no concrete retrospective outcome contamination was identified. The cache lacks contributor roster vintages, so pre-cutoff roster revision cannot be independently authenticated. This is disclosed uncertainty, not invented publication provenance.

## Coaching: field-level whitelist and substantive timing filter

Raw coaches contain games, wins, losses, ties, win_percentage, preseason_rank, postseason_rank, srs and sp_* target-season measures. All are mechanically excluded before any transformation. Never choose a coach by games coached or wins. Retain only year, team_id, identity and hire date. A candidate opening coach must have a legitimate hire date before the global first FBS kickoff and be the unique plausible opening identity for the team-season. Unknown hire state and multiple plausible identities route to B/remaining features. Late hires are logged as known_post_cutoff. Derive log1p(tenure entering season) and first-season indicator; neither uses target outcomes. Coordinator and QB continuity remain unknown. Coaching resolution ledger records all exclusions. Hire date establishes an event, not publication of this database row.

## Portal: event accounting implemented; no primary effect fit

CFBD cache begins in 2021. With 2021 as first training year only 2022 is available as a pre-2023 forward test, below the declared three-season requirement. Effects are therefore exploratory and not fitted for candidate selection. This decision concerns historical evidence, not missing publication dates.

Portal event ledger logs origin and destination separately, exact normalized name resolution, missing/unmatched/ambiguous IDs, and excluded duplicate/ambiguous player keys. No fuzzy assignment. No manual overrides were needed or invented; the resolver supports explicit overrides. Keys use season/name/position/origin because no player IDs are supplied; colliding keys are excluded as ambiguous, not merged. Dates must fall between August 1 of the preceding year and the global cutoff. A missing destination cannot erase a resolved outgoing event. Preserve observed rating/stars means, event counts, and observed-value counts; no zero player value for missing ratings. Aggregates describe matched observed records, not complete roster flows. Destination state and rating revision timing are not independently authenticated. Do not install these aggregates as historical features without resolving that substantive event-state uncertainty and obtaining enough forward evidence. Net counts may be derived from separate in/out tables but are not evidence of complete net talent.

## QB and conference membership

No historical preseason starter/continuity snapshot supplied. unknown_QB remains explicit; no inference from starts, snaps or depth charts. No QB coefficients estimated.

Season-specific schedule conference labels supply membership; conflicting team-season labels are unknown. They plausibly describe historical membership but independent announced-pre-kickoff membership archives were not recovered. Conference diagnostics and the declared hierarchy retain this source limitation. Past-edge graph statistics use only available final results; P4/Pac-12 labels are descriptive only.

## Provenance and raw separation

Original raw RDS copies remain separate under raw/, with matching content hashes. FEATURE_PROVENANCE_MANIFEST.csv retains every source record, source query/URL, provider and content hash; team_features.csv retains each derived snapshot ID, values, vintage and leakage flags. Source retrieval identifiers not supplied remain blank. cfbfastR_timestamp is explicitly retrieval_timestamp_not_publication. All historical_available_at_if_verified entries in these caches remain missing. No scrape time, file mtime, transfer/hire event date or 2026 retrieval time has been substituted.

Global preseason cutoff is the first kickoff involving FBS in each season. Verified observations must precede it; unverified season-appropriate values do not need fabricated cutoff dates. Explicit contamination or post-cutoff state always overrides a superficially valid timestamp. Ingress validates evidence types and references; it cannot authenticate a dishonest human assertion of original publication without reviewing the referenced evidence.
