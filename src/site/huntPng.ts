// Playoff page download: "The Playoff Hunt" graphic (odds against power rating, tiered: in the driver's seat / in the
// hunt / on the bubble / long shots), drawn by the shared renderer in src/exportPlayoff.ts. It needs each team's power
// rating, which lives in index.json, so that file is joined to the simulation odds here. Loaded on demand.
import { exportPlayoffHuntPng } from '../exportPlayoff'
import type { PlayoffTeam } from '../playoff'
import { load, type IndexDoc, type PlayoffDoc, type TeamMeta } from './data'

export async function huntPng(doc: PlayoffDoc, dir: Map<string, TeamMeta>) {
  const index = await load<IndexDoc>('index.json')
  const power = new Map(index.teams.map(t => [t.team_id, t.power]))
  const teams: PlayoffTeam[] = doc.teams.filter(p => power.get(p.team_id) != null).map(p => {
    const t = dir.get(p.team_id)
    return { team_id: p.team_id, team: t?.team ?? p.team_id, conference: t?.conference ?? null, logo_url: t?.logo ?? null,
      power: power.get(p.team_id)!, playoff: p.p_playoff, confTitle: p.p_conf, title: p.p_champ }
  })
  const m = doc.meta
  await exportPlayoffHuntPng({ teams, season: m.season, week: m.ratings_week, updatedAt: m.sim_updated_at, asOf: m.sim_as_of, simulations: m.sim_count })
}
