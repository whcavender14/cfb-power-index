import test from 'node:test'
import assert from 'node:assert/strict'
import { currentBracket } from '../src/site/bracket.ts'

// 14 teams by résumé rank 1..14 (id = rank). Power 4 conferences P/Q/R/S each get a leader by conference record;
// "7" is the only Group of 6 team ranked, Notre Dame is id 87.
const ids = [...Array.from({ length: 13 }, (_, i) => String(i + 1)), '87']
const rankOf = id => id === '87' ? 3 : Number(id) >= 3 ? Number(id) + 1 : Number(id)
const resume = { teams: ids.map(id => ({ team_id: id, resume_rank: rankOf(id), wins: 4, losses: 1 })) }
const st = (team_id, w, l) => ({ team_id, conf_wins: w, conf_losses: l, conf_games: 8 })
const confs = { conferences: [
  { kind: 'Power 4', team_ids: ['1', '2'], standings: [st('1', 1, 1), st('2', 2, 0)] },        // leader: 2 (better record, not better résumé)
  { kind: 'Power 4', team_ids: ['4', '5'], standings: [st('4', 2, 0), st('5', 2, 0)] },        // tie on record: résumé rank breaks it -> 4
  { kind: 'Power 4', team_ids: ['6', '13'], standings: [st('6', 0, 0), st('13', 0, 0)] },      // no games yet: résumé rank -> 6
  { kind: 'Power 4', team_ids: ['8', '9'], standings: [st('8', 1, 0), st('9', 3, 0)] },        // leader: 9
  { kind: 'Group of 6', team_ids: ['12', '11'], standings: [st('12', 3, 0), st('11', 1, 1)] }, // highest-ranked G6 team: 11 (rank 12)
  { kind: 'Independents', team_ids: ['87'], standings: [] },
] }
const doc = { meta: { sim_count: 10000 }, teams: ids.map(id => ({ team_id: id, p_qf: 0, p_sf: 0, p_final: 0, p_champ: 0 })) }

test('current bracket: leaders, top G6 team and Notre Dame get in; at-large fills by résumé; seeded by résumé', () => {
  const b = currentBracket(doc, resume, confs)
  assert.equal(b.field.length, 12)
  const auto = b.field.filter(t => t.bid === 'auto').map(t => t.team_id).sort()
  assert.deepEqual(auto, ['11', '2', '4', '6', '87', '9'].sort())
  assert.deepEqual(b.field.filter(t => t.conf_champ).map(t => t.team_id).sort(), ['2', '4', '6', '9'].sort())
  const bySeed = [...b.field].sort((a, c) => a.seed - c.seed).map(t => rankOf(t.team_id))
  assert.deepEqual(bySeed, [...bySeed].sort((a, c) => a - c))            // seed order == résumé order
  assert.equal(b.field.find(t => t.seed === 1).team_id, '1')
  assert.ok(!b.field.some(t => t.team_id === '13'))                      // lowest at-large cut: last résumé rank missed
})

test('current bracket: higher seed advances every game, so the champion is the 1 seed', () => {
  const b = currentBracket(doc, resume, confs)
  assert.equal(b.champion.seed, 1)
  assert.equal(b.rounds[0].length, 4)
  for (const g of b.rounds.flat()) assert.ok(g.winner.seed === Math.min(g.top.seed, g.bottom.seed))
})
