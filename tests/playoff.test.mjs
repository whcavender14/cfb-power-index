import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { buildBracket, huntTeams, joinTeams, normalCdf, relax, selectField, tierOf, winProbability } from '../src/playoff.ts'

const team = (name, conference, playoff, power, extra = {}) => ({ team_id: name, team: name, conference, logo_url: null, power, playoff, confTitle: 0, title: 0, ...extra })
const model = { hfa: 3, sigma: 15 }

// 14 teams: SEC and Big Ten strong at the top, a weak ACC/Big 12 champion, one G6 and Notre Dame.
function league() {
  return [
    team('S1', 'SEC', 0.95, 28, { confTitle: 0.5 }), team('S2', 'SEC', 0.9, 27), team('S3', 'SEC', 0.7, 22), team('S4', 'SEC', 0.6, 20),
    team('B1', 'Big Ten', 0.93, 27, { confTitle: 0.6 }), team('B2', 'Big Ten', 0.8, 24), team('B3', 'Big Ten', 0.55, 19), team('B4', 'Big Ten', 0.5, 18),
    team('A1', 'ACC', 0.3, 12, { confTitle: 0.4 }), team('X1', 'Big 12', 0.25, 11, { confTitle: 0.35 }), team('X2', 'Big 12', 0.26, 13, { confTitle: 0.3 }),
    team('G1', 'Mountain West', 0.12, 4, { confTitle: 0.5 }), team('G2', 'Sun Belt', 0.08, 2, { confTitle: 0.6 }),
    team('Notre Dame', 'FBS Independents', 0.45, 21),
  ]
}

test('normal CDF matches known values and is symmetric', () => {
  assert.ok(Math.abs(normalCdf(0) - 0.5) < 1e-9)
  assert.ok(Math.abs(normalCdf(1.96) - 0.975) < 1e-4)
  assert.ok(Math.abs(normalCdf(-1) + normalCdf(1) - 1) < 1e-9)
})

test('win probability uses the power gap, residual SD and home advantage', () => {
  const a = team('a', 'SEC', 1, 10), b = team('b', 'SEC', 1, 10)
  assert.equal(winProbability(a, b, model), 0.5)
  assert.ok(Math.abs(winProbability(a, b, model, true) - normalCdf(3 / 15)) < 1e-12)
  assert.ok(Math.abs(winProbability(team('c', 'SEC', 1, 25), b, model) - normalCdf(1)) < 1e-12)
})

test('2026 field: P4 champions, top G6 and ranked Notre Dame get automatic bids', () => {
  const field = selectField(league())
  const names = field.map(t => t.team)
  assert.equal(field.length, 12)
  // A1 (ACC) and X1 (Big 12, likeliest champion despite lower odds than X2) are in as champions.
  for (const t of ['A1', 'X1', 'G1', 'Notre Dame', 'S1', 'B1']) assert.ok(names.includes(t), t)
  assert.equal(field.find(t => t.team === 'X1').autoBid, 'champion')
  assert.equal(field.find(t => t.team === 'G1').autoBid, 'g6')
  assert.equal(field.find(t => t.team === 'Notre Dame').autoBid, 'notre-dame')
  // The best G6 by rank gets the bid, not the likeliest G6 conference champion.
  assert.ok(!names.includes('G2'))
  // At-large X2 is displaced by automatic qualifiers ranked below it.
  assert.ok(!names.includes('X2'))
  // Straight seeding by rank: automatic qualifiers are not promoted.
  assert.deepEqual(names, ['S1', 'B1', 'S2', 'B2', 'S3', 'S4', 'B3', 'B4', 'Notre Dame', 'A1', 'X1', 'G1'])
  assert.deepEqual(field.map(t => t.seed), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])
})

test('Notre Dame outside the top 12 gets no automatic bid; ineligible teams are skipped', () => {
  const teams = league().map(t => t.team === 'Notre Dame' ? { ...t, playoff: 0.01 } : t)
  assert.ok(!selectField(teams).some(t => t.team === 'Notre Dame'))
  const field = selectField(league(), { ineligible: ['S1'] })
  assert.ok(!field.some(t => t.team === 'S1'))
  assert.equal(field[0].team, 'B1')
})

test('bracket pairs 5–12, 6–11, 7–10, 8–9 and byes meet the right winners', () => {
  const b = buildBracket(selectField(league()), model)
  assert.deepEqual(b.rounds.map(r => r.length), [4, 4, 2, 1])
  assert.deepEqual(b.rounds[0].map(g => [g.top.seed, g.bottom.seed].sort((x, y) => x - y)), [[8, 9], [5, 12], [7, 10], [6, 11]])
  assert.deepEqual(b.rounds[1].map(g => g.top.seed), [1, 4, 2, 3])
  b.rounds[1].forEach((g, i) => assert.equal(g.bottom.team_id, b.rounds[0][i].winner.team_id))
  assert.equal(b.champion.team_id, b.rounds[3][0].winner.team_id)
  for (const g of b.rounds.flat()) assert.ok(g.winProbability >= 0.5 && g.winProbability < 1)
})

test('home advantage applies to the first round only', () => {
  // Seed 8 and seed 9 with equal power: the host (seed 8) is the favourite.
  const teams = league().map(t => t.team === 'B4' ? { ...t, power: 21 } : t)
  const b = buildBracket(selectField(teams), model)
  const g = b.rounds[0][0]
  assert.equal(g.home.seed, 8)
  assert.equal(g.winner.seed, 8)
  assert.ok(Math.abs(g.winProbability - normalCdf(3 / 15)) < 1e-12)
  assert.ok(b.rounds.slice(1).flat().every(x => x.home === null))
})

test('the published snapshot yields a valid 12-team bracket', () => {
  const read = name => JSON.parse(readFileSync(new URL(`../public/data/${name}.json`, import.meta.url), 'utf8'))
  const sims = read('simulations'), ratings = read('ratings')
  if (sims.status !== 'available') return
  const teams = joinTeams(sims.teams, ratings.teams)
  const field = selectField(teams, { ineligible: sims.assumptions?.cfp_ineligible_teams ?? [] })
  assert.equal(new Set(field.map(t => t.team_id)).size, 12)
  const b = buildBracket(field, { hfa: sims.assumptions.hfa, sigma: sims.assumptions.resid_sd })
  assert.ok(field.some(t => t.team_id === b.champion.team_id))
  for (const t of huntTeams(teams)) assert.ok(t.playoff >= 0.05)
})

test('tiers and logo relaxation', () => {
  assert.equal(tierOf(0.8).key, 'driver')
  assert.equal(tierOf(0.79).key, 'hunt')
  assert.equal(tierOf(0.2).key, 'bubble')
  assert.equal(tierOf(0.05).key, 'long')
  const pts = relax([{ x: 50, y: 50 }, { x: 50, y: 50 }, { x: 52, y: 51 }], 10, { x0: 0, y0: 0, x1: 200, y1: 200 })
  for (let i = 0; i < pts.length; i++) for (let j = i + 1; j < pts.length; j++) assert.ok(Math.hypot(pts[i].x - pts[j].x, pts[i].y - pts[j].y) >= 19.5)
})
