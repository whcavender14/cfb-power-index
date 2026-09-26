// Filters the stored simulation outcomes (scenario.json) to the seasons matching a set of picks and aggregates them.
// Nothing is re-simulated: every number is a share of the stored seasons that satisfy the picks.
import type { ScenarioDoc } from './data'

export const WARN_BELOW = 100   // fewer matching seasons: show a reliability warning
export const COUNTS_BELOW = 25  // fewer matching seasons: show counts only, no percentages

export type Pick = { gameId: string; side: 'home' | 'away' }
export type TeamResult = { team_id: string; n: number; playoff: number; bye: number; conf: number; champ: number; sf: number; wins: number; seeds: number[] }
export type Decoded = { n: number; games: Map<string, number>; teams: string[]; teamGames: Map<string, number>; bytes: Uint8Array; nb: number; format: number
  /** format 2: per team, its remaining games as [game index, 1 if home]; plus wins already banked */
  teamSched: [number, number][][]; known: number[] }

export function decode(doc: ScenarioDoc): Decoded {
  const bin = atob(doc.data)
  const bytes = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i)
  const teamSched: [number, number][][] = doc.team_ids.map(() => [])
  doc.game_home?.forEach((t, g) => { if (t >= 0) teamSched[t].push([g, 1]) })
  doc.game_away?.forEach((t, g) => { if (t >= 0) teamSched[t].push([g, 0]) })
  return { n: doc.n, games: new Map(doc.game_ids.map((id, i) => [id, i])), teams: doc.team_ids, teamGames: new Map(doc.team_ids.map((id, i) => [id, doc.team_games[i]])), bytes, nb: Math.ceil(doc.n / 8), format: doc.format ?? 1, teamSched, known: doc.known_wins ?? [] }
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
      let seed: number, wins: number, conf: boolean, exit: number
      if (d.format === 2) {   // packed byte: seed | 16 * conf title | 32 * exit round; wins = banked + remaining games won
        const p = d.bytes[base + t * d.n + s]
        seed = p & 15; conf = (p & 16) !== 0; exit = p >> 5
        wins = d.known[t]
        for (const [g, home] of d.teamSched[t]) if (((d.bytes[g * d.nb + (s >> 3)] >> (s & 7)) & 1) === home) wins++
      } else {                // format 1: seed, wins, flags (8 = conf title, low 3 bits = exit round)
        seed = d.bytes[base + t * d.n + s]; wins = d.bytes[base + T * d.n + t * d.n + s]; const f = d.bytes[base + 2 * T * d.n + t * d.n + s]
        conf = (f & 8) !== 0; exit = f & 7
      }
      if (seed) { r.playoff++; r.seeds[seed - 1]++; if (seed <= 4) r.bye++ }
      r.wins += wins
      if (conf) r.conf++
      if (exit >= 3) r.sf++
      if (exit === 5) r.champ++
    }
    out.set(id, r)
  })
  return out
}

/** matching + aggregate, cached per decoded file and pick set: with 10,000 seasons an aggregate takes ~50-100 ms,
 *  too slow to repeat on every re-render (row clicks, the seed-odds team select). */
const memo = new WeakMap<Decoded, { key: string; sims: number[]; res: Map<string, TeamResult> }>()
export function scenarioResults(d: Decoded, picks: Pick[]): { sims: number[]; res: Map<string, TeamResult> } {
  const key = formatPicks(picks)
  const hit = memo.get(d)
  if (hit && hit.key === key) return hit
  const sims = matching(d, picks)
  const out = { key, sims, res: aggregate(d, sims) }
  memo.set(d, out)
  return out
}
