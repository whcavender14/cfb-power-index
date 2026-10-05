// CFPi+ Player Ratings v1 beta (public/data/v2/players/ratings; scripts/export_player_ratings.R;
// docs/website/PLAYER_RATINGS_PREDECLARATION.md). Modelled, not official: a CFPi+ derived metric, not a
// CollegeFootballData, NCAA, 247Sports, Madden or EA Sports rating. Display only; never a CFPi+ model input.
import type { Meta } from './data'

export type RatingRow = { athlete_id: string; name: string; team_id: string; position: string | null; group: string; class: number | null
  ovr: number; band: number; provisional: boolean; estimated: boolean; profile: boolean; rs: boolean }
type Est = { est: number; lo: number; hi: number }
export type RatingsMethod = { version: string; label: string; rated_through: number; roster_season: number; note: string
  counts: { rated: number; provisional: number; estimated: number }
  distribution: { mean: number; median: number; sd: number; at: Record<string, number> }
  left_out: Record<string, string>
  validation: { holdout: { production: Record<string, Est>; draft: Record<string, Est> }; development: { production: Record<string, Est>; draft: Record<string, Est> } } }
export type RatingsTop = { meta: Meta; source: string; method: RatingsMethod; columns: string[]; rows: (string | number | boolean | null)[][] }
export type RatingsTeam = { meta: Meta; team_id: string; rated_through: number; version: string; columns: string[]; rows: (string | number | boolean | null)[][] }

export const ratingRows = (d: { columns: string[]; rows: (string | number | boolean | null)[][] }) =>
  d.rows.map(r => Object.fromEntries(d.columns.map((k, i) => [k, r[i]])) as unknown as RatingRow)
export const LABEL = 'Modelled, not official'
export const RATING_INFO = 'CFPi+ Player Rating (beta, v1): a CFPi+ modelled rating on a 30-99 scale, not an official, 247Sports, Madden or EA Sports rating. Built from CollegeFootballData production through last season (PPA, success rate, per-play and per-game stats, usage), shrunk toward a prior from the 247Sports recruiting rating. ± is one standard deviation of uncertainty.'
export const FLAG_INFO = {
  provisional: 'Provisional: little recorded production, so the rating is mostly the recruiting prior and the band is wide.',
  estimated: 'Estimated: offensive linemen, kickers and punters. CollegeFootballData has no individual blocking, snap or pressure data, and kicking data is thin, so these rest mostly on recruiting, size, class and (OL) a small team-unit adjustment.',
}
export const TIER = (o: number) => o >= 99 ? 'Generational / national superstar' : o >= 90 ? 'Elite national player' : o >= 80 ? 'High-end P4 starter' : o >= 70 ? 'Solid FBS starter'
  : o >= 60 ? 'Average FBS contributor' : o >= 50 ? 'Replacement / depth player' : o >= 40 ? 'Low-end / developmental player' : 'Bottom of the FBS player pool'
