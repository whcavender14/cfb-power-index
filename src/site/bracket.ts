// The projected 12-team bracket for the Playoff page and its PNG download, built only from published simulation
// output (playoff.json): the most likely complete field (representative_field) and each team's share of all simulated
// seasons in which it reached each round. Nothing is re-simulated or re-modelled in the browser.
//
// Bracket order matches cfbseedR and src/exportPlayoff.ts: first round 8v9, 5v12 (left half, feeding seeds 1 and 4)
// and 7v10, 6v11 (right half, feeding 2 and 3); quarterfinal top slot is the bye team; semifinals 1/8/9 v 4/5/12 and
// 2/7/10 v 3/6/11. In each game the team that reached the next round in more simulations advances (ties: higher seed).
import type { ConferencesDoc, PlayoffDoc, PlayoffTeam, ResumeDoc } from './data'

export type BracketTeam = { team_id: string; seed: number; bid: 'auto' | 'at-large'; conf_champ: boolean; wins?: number; losses?: number; odds: PlayoffTeam }
/** p: share of all simulations in which the team reached the round after this game (won it). */
export type BracketGame = { round: 0 | 1 | 2 | 3; top: BracketTeam; bottom: BracketTeam; pTop: number; pBottom: number; winner: BracketTeam }
export type SimBracket = { field: BracketTeam[]; rounds: BracketGame[][]; champion: BracketTeam; identical: number; sims: number | null }
/** 'odds': the team that reached the next round in more simulations advances. 'seed': the higher seed advances. */
type Advance = 'odds' | 'seed'

export const ROUND_LABELS = ['First round', 'Quarterfinals', 'Semifinals', 'National championship'] as const
const NEXT: (keyof PlayoffTeam)[] = ['p_qf', 'p_sf', 'p_final', 'p_champ']

function game(round: 0 | 1 | 2 | 3, top: BracketTeam, bottom: BracketTeam, advance: Advance): BracketGame {
  const pTop = Number(top.odds[NEXT[round]] ?? 0), pBottom = Number(bottom.odds[NEXT[round]] ?? 0)
  const topWins = advance === 'seed' ? top.seed < bottom.seed : pTop > pBottom || (pTop === pBottom && top.seed < bottom.seed)
  return { round, top, bottom, pTop, pBottom, winner: topWins ? top : bottom }
}

export function simBracket(doc: PlayoffDoc): SimBracket | null {
  const f = doc.representative_field
  if (!f || f.seeds.length !== 12) return null
  const odds = new Map(doc.teams.map(t => [t.team_id, t]))
  const field: BracketTeam[] = f.seeds.map(s => ({ team_id: s.team_id, seed: s.seed, bid: s.bid, conf_champ: s.conf_champ, wins: s.wins, losses: s.losses, odds: odds.get(s.team_id)! }))
  if (field.some(t => !t.odds)) return null
  return assemble(field, 'odds', f.sims_with_identical_field, doc.meta.sim_count)
}

function assemble(field: BracketTeam[], advance: Advance, identical: number, sims: number | null): SimBracket {
  const s = new Map(field.map(t => [t.seed, t]))
  const g = (round: 0 | 1 | 2 | 3, top: BracketTeam, bottom: BracketTeam) => game(round, top, bottom, advance)
  const fr = [g(0, s.get(8)!, s.get(9)!), g(0, s.get(5)!, s.get(12)!), g(0, s.get(7)!, s.get(10)!), g(0, s.get(6)!, s.get(11)!)]
  const qf = [g(1, s.get(1)!, fr[0].winner), g(1, s.get(4)!, fr[1].winner), g(1, s.get(2)!, fr[2].winner), g(1, s.get(3)!, fr[3].winner)]
  const sf = [g(2, qf[0].winner, qf[1].winner), g(2, qf[2].winner, qf[3].winner)]
  const fin = g(3, sf[0].winner, sf[1].winner)
  return { field, rounds: [fr, qf, sf, [fin]], champion: fin.winner, identical, sims }
}

const NOTRE_DAME = '87'
/** The bracket if the field were set today: teams are ranked by résumé (strength of record, resume.json) and picked
 *  under the same 2026 rules the simulation uses, with each Power 4 conference's current leader (best conference
 *  record, résumé rank breaking ties) standing in for its champion. Nothing is simulated; later rounds advance the
 *  higher seed. */
export function currentBracket(doc: PlayoffDoc, resume: ResumeDoc, confs: ConferencesDoc): SimBracket | null {
  const rank = new Map<string, number>(), rec = new Map<string, { wins: number | null; losses: number | null }>()
  for (const r of resume.teams) if (r.resume_rank != null) { rank.set(r.team_id, r.resume_rank); rec.set(r.team_id, r) }
  const byRank = (a: string, b: string) => (rank.get(a) ?? 1e9) - (rank.get(b) ?? 1e9)
  const auto = new Set<string>(), leaders = new Set<string>()
  for (const c of confs.conferences) {
    if (c.kind === 'Power 4') {
      const lead = [...(c.standings ?? [])].filter(t => rank.has(t.team_id)).sort((a, b) => {
        const pa = a.conf_wins + a.conf_losses ? a.conf_wins / (a.conf_wins + a.conf_losses) : 0
        const pb = b.conf_wins + b.conf_losses ? b.conf_wins / (b.conf_wins + b.conf_losses) : 0
        return pb - pa || b.conf_wins - a.conf_wins || byRank(a.team_id, b.team_id)
      })[0]
      if (lead) { auto.add(lead.team_id); leaders.add(lead.team_id) }
    }
  }
  const g6 = confs.conferences.filter(c => c.kind === 'Group of 6').flatMap(c => c.team_ids).filter(id => rank.has(id)).sort(byRank)[0]
  if (g6) auto.add(g6)
  if ((rank.get(NOTRE_DAME) ?? 99) <= 12) auto.add(NOTRE_DAME)
  const picked = new Set(auto)
  for (const id of [...rank.keys()].sort(byRank)) { if (picked.size >= 12) break; picked.add(id) }
  const odds = new Map(doc.teams.map(t => [t.team_id, t]))
  const field: BracketTeam[] = [...picked].sort(byRank).slice(0, 12).map((id, i) => ({
    team_id: id, seed: i + 1, bid: auto.has(id) ? 'auto' : 'at-large', conf_champ: leaders.has(id),
    wins: rec.get(id)?.wins ?? undefined, losses: rec.get(id)?.losses ?? undefined, odds: odds.get(id)!,
  }))
  if (field.length !== 12 || field.some(t => !t.odds)) return null
  return assemble(field, 'seed', 0, doc.meta.sim_count)
}
