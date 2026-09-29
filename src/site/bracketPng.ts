// Playoff page download: the projected bracket drawn by the shared bracket renderer (src/exportPlayoff.ts), fed with
// the simulation bracket the page shows (./bracket.ts), so the on-page bracket and the PNG match. Loaded on demand.
import { renderBracketPng } from '../exportPlayoff'
import { G6, type Game, type PlayoffTeam, type Seeded } from '../playoff'
import type { PlayoffDoc, TeamMeta } from './data'
import type { BracketTeam, SimBracket } from './bracket'

export async function bracketPng(doc: PlayoffDoc, b: SimBracket, dir: Map<string, TeamMeta>) {
  const team = (id: string, p: PlayoffDoc['teams'][number]): PlayoffTeam => {
    const t = dir.get(id)
    return { team_id: id, team: t?.team ?? id, conference: t?.conference ?? null, logo_url: t?.logo ?? null, power: 0,
      playoff: p.p_playoff, confTitle: p.p_conf, title: p.p_champ }
  }
  const seeded = new Map<string, Seeded>(b.field.map(f => {
    const base = { ...team(f.team_id, f.odds), record: f.wins != null ? `${f.wins}–${f.losses}` : undefined }
    const autoBid: Seeded['autoBid'] = f.bid !== 'auto' ? null : f.conf_champ ? (G6.includes(base.conference ?? '') ? 'g6' : 'champion') : base.team === 'Notre Dame' ? 'notre-dame' : 'g6'
    return [f.team_id, { ...base, seed: f.seed, autoBid }]
  }))
  const s = (t: BracketTeam) => seeded.get(t.team_id)!
  const rounds: Game[][] = b.rounds.map(games => games.map(g => {
    const top = s(g.top), bottom = s(g.bottom), winner = s(g.winner)
    return { round: g.round, top, bottom, home: g.round === 0 ? top : null, winner, loser: winner === top ? bottom : top,
      winProbability: g.winner === g.top ? g.pTop : g.pBottom, shown: [g.pTop, g.pBottom] }
  }))
  const m = doc.meta
  return renderBracketPng({
    field: [...seeded.values()], rounds, champion: s(b.champion), teams: doc.teams.map(p => team(p.team_id, p)),
    season: m.season, week: m.ratings_week, updatedAt: m.sim_updated_at, chip: 'CFPi+ SIMULATIONS',
    lede: `The most likely 12-team field across ${m.sim_count?.toLocaleString('en-US') ?? 'the'} simulated seasons.`,
    notes: [
      `Field: the single simulated season whose seeding best matches all the simulations (this exact seeding occurred in ${b.identical} of ${m.sim_count?.toLocaleString('en-US')}).`,
      'In each game the team that reached the next round in more simulations advances; shares count every simulated season, whatever the seed. Higher seed hosts the first round.',
    ],
    file: `cfpi-playoff-bracket-${m.season}-wk${String(m.ratings_week ?? 0).padStart(2, '0')}.png`,
  })
}
