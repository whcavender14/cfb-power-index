import { test } from 'node:test'
import assert from 'node:assert/strict'
import { cpSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { validateSiteData } from '../scripts/validate_site_data.mjs'

const src = new URL('../public/data/v2/', import.meta.url)

test('committed public/data/v2 passes validation', () => {
  assert.deepEqual(validateSiteData(), [])
})

// Copy the real data, break one thing, and check the validator catches it.
function broken(file, mutate) {
  const dir = mkdtempSync(join(tmpdir(), 'cfpi-')) + '/'
  cpSync(src, dir, { recursive: true })
  const doc = JSON.parse(readFileSync(dir + file, 'utf8'))
  mutate(doc)
  writeFileSync(dir + file, JSON.stringify(doc))
  return validateSiteData(dir)
}

test('rejects a probability above 1', () => {
  assert.ok(broken('index.json', d => { d.teams[0].p_playoff = 1.2 }).some(e => e.includes('outside [0,1]')))
})
test('rejects duplicate ranks', () => {
  assert.ok(broken('index.json', d => { const r = d.teams.filter(t => t.rank); r[1].rank = r[0].rank }).length > 0)
})
test('rejects playoff odds that do not sum to 12 teams', () => {
  assert.ok(broken('playoff.json', d => { d.teams[0].p_playoff += 0.5 }).some(e => e.includes('sum to')))
})
test('rejects a completed game that still carries a projection', () => {
  assert.ok(broken('games.json', d => { const g = d.games.find(x => x.status === 'final'); g.spread_home = 3 }).some(e => e.includes('projection')))
})
test('rejects files from different exports', () => {
  assert.ok(broken('games.json', d => { d.meta.exported_at = '2000-01-01T00:00:00Z' }).some(e => e.includes('mixed update')))
})
test('rejects a record distribution that does not sum to the simulation count', () => {
  assert.ok(broken('team/alabama.json', d => { d.record_dist[0].count += 1 }).some(e => e.includes('record counts')))
})
test('rejects expected wins that differ from the distribution mean', () => {
  assert.ok(broken('team/alabama.json', d => { const r = d.record_dist; r[0].count += 5; r[r.length - 1].count -= 5 }).some(e => e.includes('mean wins')))
})
test('rejects statistical leaders out of order', () => {
  assert.ok(broken('team/alabama.json', d => { d.leaders.receiving.reverse() }).some(e => e.includes('not sorted')))
})
test('rejects leaders from a different week than the ratings', () => {
  assert.ok(broken('team/alabama.json', d => { d.leaders.through_week = 2 }).some(e => e.includes('leaders cover week')))
})
test('rejects a scenario file that does not reproduce the published odds', () => {
  assert.ok(broken('scenario.json', d => { const b = Buffer.from(d.data, 'base64'); const n = d.n, nb = Math.ceil(n / 8), base = d.game_ids.length * nb; const T = d.team_ids.length; for (let s = 0; s < n; s++) b[base + T * n + s] = 0; d.data = b.toString('base64') }).some(e => e.includes('reproduce')))
})
test('rejects resume ranks out of the approved order', () => {
  assert.ok(broken('resume.json', d => { const a = d.teams.find(t => t.resume_rank === 1), b = d.teams.find(t => t.resume_rank === 2); a.resume_rank = 2; b.resume_rank = 1 }).some(e => e.includes('tie-break order') || e.includes('disagree')))
})
test('rejects conference expected playoff teams that differ from the member sum', () => {
  assert.ok(broken('conferences.json', d => { d.conferences[0].exp_playoff += 0.1 }).some(e => e.includes('exp_playoff')))
})
test('rejects a history whose current point disagrees with the rankings', () => {
  assert.ok(broken('history.json', d => { const k = Object.keys(d.teams)[0]; d.teams[k].power[d.points.length - 1] += 1 }).some(e => e.includes('current point')))
})
test('rejects movement that does not come from the history previous week', () => {
  assert.ok(broken('index.json', d => { const r = d.teams.find(t => t.rank_prev); r.rank_prev += 1; r.rank_change += 1 }).some(e => e.includes('movement')))
})
