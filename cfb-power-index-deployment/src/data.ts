export type Team = { season: number; week: number | null; updated_at: string | null; team_id: string; team: string; conference: string | null; logo_url: string | null }
export type Rating = Team & { power_rating: number | null; offensive_rating: number | null; defensive_rating: number | null; weekly_change: number | null; preseason_change: number | null }
export type Simulation = Team & { projected_wins_current: number | null; projected_wins_preseason: number | null; playoff_probability: number | null; conference_title_probability: number | null; national_title_probability: number | null; vegas_win_total_preseason: number | null }
export type Dataset<T> = { schema_version: number; season: number; week: number | null; updated_at: string | null; status: 'available' | 'unavailable'; model: string; teams: T[]; rated_teams?: number; total_teams?: number; defensive_higher_is_better?: boolean; simulation_count?: number | null; playoff_format?: string | null; wins_scope?: string | null; unavailable_reason?: string | null; as_of?: string | null }

export async function fetchDataset<T>(name: 'ratings' | 'simulations'): Promise<Dataset<T>> {
  const response = await fetch(`${import.meta.env.BASE_URL}data/${name}.json`)
  if (!response.ok) throw new Error('Data unavailable')
  const data = await response.json()
  const numeric = name === 'ratings' ? ['power_rating', 'offensive_rating', 'defensive_rating', 'weekly_change', 'preseason_change'] : ['projected_wins_current', 'projected_wins_preseason', 'playoff_probability', 'conference_title_probability', 'national_title_probability', 'vegas_win_total_preseason']
  if (data.schema_version !== 1 || !Array.isArray(data.teams) || !Number.isInteger(data.season) || !['available', 'unavailable'].includes(data.status)) throw new Error('Invalid data contract')
  const ids = new Set<string>()
  for (const row of data.teams) {
    if (typeof row.team_id !== 'string' || typeof row.team !== 'string' || ids.has(row.team_id) || numeric.some(key => row[key] !== null && (typeof row[key] !== 'number' || !Number.isFinite(row[key])))) throw new Error('Invalid team data')
    for (const key of numeric.filter(key => key.endsWith('_probability'))) if (row[key] !== null && (row[key] < 0 || row[key] > 1)) throw new Error('Invalid probability')
    ids.add(row.team_id)
  }
  return data
}
