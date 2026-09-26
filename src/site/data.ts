// Page datasets from public/data/v2 (R/publish/export_site_data.R; docs/website/DATA_CONTRACT_V2.md).
// The browser only displays these values. It never recomputes a rating, rank, spread or probability.

export type Meta = {
  schema_version: number; season: number; model: string | null
  ratings_week: number | null; ratings_as_of: string | null; ratings_updated_at: string | null
  sim_status: 'available' | 'unavailable'; sim_count: number | null; sim_updated_at: string | null; sim_as_of: string | null
  current_week: number | null; movement_compared_to_week: number | null; movement_source: HistorySource | null
  hfa: number | null; sigma: number | null; exported_at: string
}
export type TeamRow = {
  team_id: string; slug: string; rank: number | null; rank_prev: number | null; rank_change: number | null
  power: number | null; rating_change: number | null; off: number | null; def: number | null
  off_rank: number | null; def_rank: number | null; preseason_power: number | null; games_played: number | null
  wins: number | null; losses: number | null; conf_wins: number | null; conf_losses: number | null
  proj_wins: number | null; p_playoff: number | null; p_conf: number | null; p_champ: number | null
  sos: number | null; sos_rank: number | null; sor: number | null; sor_rank: number | null
  resume_rank: number | null; sos_played: number | null
}
export type Game = {
  game_id: string; week: number; kickoff: string; time_tbd: boolean | null; neutral: boolean; conference_game: boolean | null
  home_id: string; away_id: string; home_team: string; away_team: string; home_fbs: boolean; away_fbs: boolean
  home_conference: string | null; away_conference: string | null; status: 'final' | 'scheduled'
  home_points: number | null; away_points: number | null
  spread_home: number | null; win_prob_home: number | null; sim_home_win: number | null; quality: number | null
  in_ratings: boolean
}
export type TeamMeta = {
  team_id: string; slug: string; team: string; mascot: string | null; abbreviation: string | null; conference: string | null
  color: string | null; alt_color: string | null; logo: string | null; logo_dark: string | null
}
export type PlayoffTeam = {
  team_id: string; proj_wins: number; p_conf: number; p_playoff: number; p_auto: number; p_at_large: number
  p_bye: number; p_host: number; p_qf: number; p_sf: number; p_final: number; p_champ: number
  mean_seed: number | null; seed_dist?: number[]
}
export type IndexDoc = { meta: Meta; teams: TeamRow[]; top_games: Game[] | null }
export type TeamsDoc = { meta: Meta; teams: TeamMeta[] }
export type GamesDoc = { meta: Meta; games: Game[] }
export type PlayoffDoc = {
  meta: Meta
  format: { teams: number; byes: number; autobids: string; ranking: string; seeding: string; source: string }
  teams: PlayoffTeam[]
  representative_field: { sim: number; sims_with_identical_field: number; seeds: { seed: number; team_id: string; bid: 'auto' | 'at-large'; conf_champ: boolean }[] } | null
}
export type NotableGame = { game_id: string; opp_id: string; opp: string; opp_fbs: boolean; opp_rank: number | null; loc: number; pts: number; opp_pts: number }
export type Resume = {
  sos_played: number | null; sos_all: number | null; sos_remaining: number | null; sor: number | null
  sos_played_rank: number | null; sos_all_rank: number | null; sos_remaining_rank: number | null; sor_rank: number | null
  best_win: NotableGame | null; worst_loss: NotableGame | null
}
export type Leader = { athlete_id: string; player: string; position: string | null } & Record<string, number | string | null>
export type Leaders = { through_week: number; source: string; passing: Leader[]; rushing: Leader[]; receiving: Leader[]; sacks: Leader[]; interceptions: Leader[] }
export type RecordCount = { wins: number; losses: number; count: number }
export type TeamDoc = {
  meta: Meta; team: TeamMeta; summary: TeamRow; schedule: Game[]
  wins_dist: number[] | null; record_dist: RecordCount[] | null; resume: Resume | null; leaders?: Leaders | null
  seed_dist: number[] | null; playoff: PlayoffTeam | null
}
export type HistorySource = 'preseason' | 'reconstructed' | 'published'
export type HistoryPoint = { week: number | null; label: string; as_of: string | null; source: HistorySource }
export type HistorySeries = { power: (number | null)[]; rank: (number | null)[]; off: (number | null)[]; def: (number | null)[] }
export type HistoryDoc = { meta: Meta; points: HistoryPoint[]; teams: Record<string, HistorySeries> }
export type ChangeGame = { game_id: string; opp_id: string; opp: string; opp_fbs: boolean; opp_rank_prev: number | null; loc: number; pts: number; opp_pts: number; proj_margin: number | null; vs_projection: number | null; text: string }
export type TeamChange = { team_id: string; games: ChangeGame[]; off_change: number | null; def_change: number | null }
export type ChangesDoc = { meta: Meta; compared_to_week: number | null; compared_to_source: HistorySource | null; window_start: string | null; window_end: string | null; teams: TeamChange[] }
export type Conference = {
  slug: string; name: string; kind: string; is_conference: boolean; team_ids: string[]; n: number
  avg_power: number | null; median_power: number | null; top25: number; best_rank: number | null; avg_rank: number | null
  exp_playoff: number | null; sos_avg: number | null
  nonconf_wins: number | null; nonconf_losses: number | null; nonconf_fbs_wins: number | null; nonconf_fbs_losses: number | null
}
export type ScenarioDoc = { meta: Meta; n: number; game_ids: string[]; team_ids: string[]; team_games: number[]; layout: string; data: string }
export type ResumeRow = { team_id: string; resume_rank: number | null; sor: number | null; sos_played: number | null; sos_played_rank: number | null; wins: number | null; losses: number | null; games: number; predictive_rank: number | null; best_win: NotableGame | null; worst_loss: NotableGame | null }
export type ResumeDoc = { meta: Meta; method: { metric: string; benchmark: string; tiebreaks: string; proposal: string }; teams: ResumeRow[] }
export type ConferencesDoc = { meta: Meta; conferences: Conference[] }

const cache = new Map<string, Promise<unknown>>()

/** Fetches a v2 dataset once per page load; failures are not cached so Retry works. */
export function load<T>(path: string): Promise<T> {
  const hit = cache.get(path)
  if (hit) return hit as Promise<T>
  const request = fetch(`${import.meta.env.BASE_URL}data/v2/${path}`).then(async response => {
    if (!response.ok) throw new Error(`Data unavailable (${response.status})`)
    const body = await response.json()
    if (!body || typeof body !== 'object' || body.meta?.schema_version !== 2) throw new Error('Invalid data contract')
    return body as T
  })
  cache.set(path, request)
  request.catch(() => cache.delete(path))
  return request
}
