// The projected 12-team bracket for the Playoff page and its PNG download, built only from published simulation
// output (playoff.json): the most likely complete field (representative_field) and each team's share of all simulated
// seasons in which it reached each round. Nothing is re-simulated or re-modelled in the browser.
//
// Bracket order matches cfbseedR and src/exportPlayoff.ts: first round 8v9, 5v12 (left half, feeding seeds 1 and 4)
// and 7v10, 6v11 (right half, feeding 2 and 3); quarterfinal top slot is the bye team; semifinals 1/8/9 v 4/5/12 and
// 2/7/10 v 3/6/11. In each game the team that reached the next round in more simulations advances (ties: higher seed).
import type { PlayoffDoc, PlayoffTeam } from './data'

export type BracketTeam = { team_id: string; seed: number; bid: 'auto' | 'at-large'; conf_champ: boolean; wins?: number; losses?: number; odds: PlayoffTeam }
/** p: share of all simulations in which the team reached the round after this game (won it). */
export type BracketGame = { round: 0 | 1 | 2 | 3; top: BracketTeam; bottom: BracketTeam; pTop: number; pBottom: number; winner: BracketTeam }
export type SimBracket = { field: BracketTeam[]; rounds: BracketGame[][]; champion: BracketTeam; identical: number; sims: number | null }

export const ROUND_LABELS = ['First round', 'Quarterfinals', 'Semifinals', 'National championship'] as const
const NEXT: (keyof PlayoffTeam)[] = ['p_qf', 'p_sf', 'p_final', 'p_champ']

function game(round: 0 | 1 | 2 | 3, top: BracketTeam, bottom: BracketTeam): BracketGame {
  const pTop = Number(top.odds[NEXT[round]] ?? 0), pBottom = Number(bottom.odds[NEXT[round]] ?? 0)
  const topWins = pTop > pBottom || (pTop === pBottom && top.seed < bottom.seed)
  return { round, top, bottom, pTop, pBottom, winner: topWins ? top : bottom }
}

export function simBracket(doc: PlayoffDoc): SimBracket | null {
  const f = doc.representative_field
  if (!f || f.seeds.length !== 12) return null
  const odds = new Map(doc.teams.map(t => [t.team_id, t]))
  const field: BracketTeam[] = f.seeds.map(s => ({ team_id: s.team_id, seed: s.seed, bid: s.bid, conf_champ: s.conf_champ, wins: s.wins, losses: s.losses, odds: odds.get(s.team_id)! }))
  if (field.some(t => !t.odds)) return null
  const s = new Map(field.map(t => [t.seed, t]))
  const fr = [game(0, s.get(8)!, s.get(9)!), game(0, s.get(5)!, s.get(12)!), game(0, s.get(7)!, s.get(10)!), game(0, s.get(6)!, s.get(11)!)]
  const qf = [game(1, s.get(1)!, fr[0].winner), game(1, s.get(4)!, fr[1].winner), game(1, s.get(2)!, fr[2].winner), game(1, s.get(3)!, fr[3].winner)]
  const sf = [game(2, qf[0].winner, qf[1].winner), game(2, qf[2].winner, qf[3].winner)]
  const fin = game(3, sf[0].winner, sf[1].winner)
  return { field, rounds: [fr, qf, sf, [fin]], champion: fin.winner, identical: f.sims_with_identical_field, sims: doc.meta.sim_count }
}
