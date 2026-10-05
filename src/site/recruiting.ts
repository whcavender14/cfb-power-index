// Recruiting datasets (public/data/v2/recruiting; R/publish/recruiting.R; docs/website/DATA_CONTRACT_V2.md). Every value is a
// CollegeFootballData recruiting value (247Sports Composite) or a count / average of those rows done in R.
import type { Meta } from './data'

type Stamp = { meta: Meta; source: string; pulled_at: string }
export type HsDoc = Stamp & { year: number; open: boolean; columns: string[]; rows: (string | number | null)[][] }
export type Recruit = { id: string; profile_id: string | null; ranking: number | null; name: string; position: string | null; stars: number | null; rating: number | null
  school: string | null; state: string | null; height: number | null; weight: number | null; team_id: string | null; committed_other: string | null }
export type ClassDoc = Stamp & { year: number; ranked: boolean; columns: string[]; rows: (string | number | null)[][] }
export type ClassRow = { team_id: string; rank: number | null; points: number | null; commits: number; five: number; four: number; three: number; avg_rating: number | null }
export type Card = { team_id: string; classes: { year: number; rank: number | null }[]; avg_rank_4yr: number | null
  blue_chip: { share: number | null; blue: number; rated: number }; open_class: { year: number; commits: number; five: number; four: number; avg_rating: number | null }
  talent: { value: number; rank: number } | null
  portal?: { year: number; in: number; out: number; churn: number; star_churn: number | null; rank: number; teams: number } | null }
export type CardsDoc = Stamp & { season: number; last4: number[]; open_class: number; classes: number[]; teams: Card[] }
export type DashboardDoc = Stamp & { open_class: number; latest_ranked_class: number | null; classes: number[]; talent_season: number
  open_top: { team_id: string; commits: number; five: number; four: number; avg_rating: number | null }[]
  open_players: { id: string; ranking: number | null; name: string; position: string | null; stars: number | null; rating: number | null; school: string | null; state: string | null; team_id: string | null; committed_other: string | null }[]
  latest_top: { team_id: string; rank: number; points: number | null; commits: number; five: number; four: number }[]
  talent: { team_id: string; talent: number; talent_rank: number; cfpi_rank: number | null }[]
  portal_years: number[]; portal: { year: number; fbs_rows: number; match: PortalDoc['match']; top: { team_id: string; rank: number; in: number; out: number; churn: number; star_churn: number }[]; bottom: { team_id: string; rank: number; in: number; out: number; churn: number; star_churn: number }[] } }

export type PortalDoc = Stamp & { year: number; open: boolean; rows_total: number; fbs_rows: number
  match: { destination: number; origin: number; ambiguous: number; conflict: number; unmatched: number }
  columns: string[]; rows: (string | number | boolean | null)[][]; team_columns: string[]; teams: (string | number)[][] }
export type Transfer = { name: string; position: string | null; origin_id: string | null; origin_other: string | null; dest_id: string | null; dest_other: string | null
  date: string | null; stars: number | null; rating: number | null; eligibility: string | null; match: string; athlete_id: string | null; profile: boolean }
export type PortalTeam = { team_id: string; rank: number; in: number; out: number; churn: number; in_stars: number; out_stars: number; star2_in: number | null; star2_out: number | null; star_churn: number | null }
export const STAR_CHURN_INFO = 'CFPi+ Star Churn (derived, methodology v2; not a CollegeFootballData or 247Sports ranking): Star² In minus Star² Out, the ranking metric. Star² is the average of stars squared (5★ = 25, 4★ = 16, 3★ = 9, 2★ = 4) over the incoming (or outgoing) transfers that have a 247Sports star rating; squaring widens the gap between elite and average players. Positive means the team upgraded its average talent tier through the portal; negative means it lost higher-rated players than it gained. Withdrawn entries count for neither side. Transfers without stars are left out of the averages, and a team with no star-rated transfer on one side has no Star Churn and is ranked last. Averages over a handful of players swing a lot.'
export const rowsOf = <T,>(doc: { columns: string[]; rows: (string | number | boolean | null)[][] }) =>
  doc.rows.map(r => Object.fromEntries(doc.columns.map((k, i) => [k, r[i]])) as unknown as T)
export const stars = (n: number | null) => n ? '★'.repeat(n) : '—'
export const rating = (v: number | null) => v == null ? '—' : v.toFixed(4)
export const ATTRIBUTION = 'Recruiting data: CollegeFootballData, from the 247Sports Composite (stars, ratings, rankings, team class rankings, team talent).'
