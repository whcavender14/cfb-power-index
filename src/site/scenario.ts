// Filters the stored simulation outcomes (scenario.json) to the seasons matching a set of picks and aggregates them.
// Nothing is re-simulated: every number is a share of the stored seasons that satisfy the picks.
import type { ScenarioDoc } from './data'

export const WARN_BELOW = 100   // fewer matching seasons: show a reliability warning
export const COUNTS_BELOW = 25  // fewer matching seasons: show counts only, no percentages

export type Pick = { gameId: string; side: 'home' | 'away' }
export type TeamResult = { team_id: string; n: number; playoff: number; bye: number; conf: number; champ: number; sf: number; wins: number; seeds: number[] }
export type Decoded = { n: number; games: Map<string, number>; teams: string[]; teamGames: Map<string, number>; bytes: Uint8Array; nb: number }

export function decode(doc: ScenarioDoc): Decoded {
  const bin = atob(doc.data)
  const bytes = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i)
  return { n: doc.n, games: new Map(doc.game_ids.map((id, i) => [id, i])), teams: doc.team_ids, teamGames: new Map(doc.team_ids.map((id, i) => [id, doc.team_games[i]])), bytes, nb: Math.ceil(doc.n / 8) }
}

export function parsePicks(param: string): Pick[] {
  return param.split(',').map(s => s.trim()).filter(Boolean).map(s => { const [gameId, side] = s.split(':'); return { gameId, side: side === 'away' ? 'away' : 'home' } as Pick })
    .filter((p, i, all) => p.gameId && all.findIndex(q => q.gameId === p.gameId) === i)
}
export const formatPicks = (picks: Pick[]) => picks.map(p => `${p.gameId}:${p.side}`).join(',')

/** Indices of the simulations in which every pick happened. Unknown game ids are ignored (reported by the caller). */
export function matching(d: Decoded, picks: Pick[]): number[] {
  const mask = new Uint8Array(d.nb).fill(255)
  for (const p of picks) {
    const g = d.games.get(p.gameId)
    if (g === undefined) continue
    for (let b = 0; b < d.nb; b++) { const v = d.bytes[g * d.nb + b]; mask[b] &= p.side === 'home' ? v : ~v }
  }
  const out: number[] = []
  for (let s = 0; s < d.n; s++) if (mask[s >> 3] & (1 << (s & 7))) out.push(s)
  return out
}

/** Counts per team over the matching simulations (counts, not shares, so the page can show either). */
export function aggregate(d: Decoded, sims: number[]): Map<string, TeamResult> {
  const T = d.teams.length, base = d.games.size * d.nb
  const out = new Map<string, TeamResult>()
  d.teams.forEach((id, t) => {
    const r: TeamResult = { team_id: id, n: sims.length, playoff: 0, bye: 0, conf: 0, champ: 0, sf: 0, wins: 0, seeds: new Array(12).fill(0) }
    for (const s of sims) {
      const seed = d.bytes[base + t * d.n + s], f = d.bytes[base + 2 * T * d.n + t * d.n + s]
      if (seed) { r.playoff++; r.seeds[seed - 1]++; if (seed <= 4) r.bye++ }
      r.wins += d.bytes[base + T * d.n + t * d.n + s]
      if (f & 8) r.conf++
      if ((f & 7) >= 3) r.sf++
      if ((f & 7) === 5) r.champ++
    }
    out.set(id, r)
  })
  return out
}
