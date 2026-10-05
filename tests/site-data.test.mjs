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
  assert.ok(broken('scenario.json', d => { const b = Buffer.from(d.data, 'base64'); const n = d.n, nb = Math.ceil(n / 8), base = d.game_ids.length * nb; for (let s = 0; s < n; s++) b[base + s] = 1; d.data = b.toString('base64') }).some(e => e.includes('reproduce')))
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

test('rejects conference win odds that do not sum to the expected wins', () => {
  assert.ok(broken('conferences.json', d => { const t = d.conferences.find(c => c.standings?.length).standings[0]; t.avg_wins += 0.5 }).some(e => e.includes('p_ge sums')))
})

test('rejects a playoff swing that does not average back to the published odds', () => {
  assert.ok(broken('index.json', d => { const g = Object.values(d.top_swing)[0]; const side = g.home ?? g.away; side.win = Math.min(1, side.win + 0.3) }).some(e => e.includes('top_swing')))
})

// /players/ leaderboards
const leaders = cat => `players/leaders/${cat}.json`
test('rejects a qualified flag that does not follow from the counts', () => {
  assert.ok(broken(leaders('passing'), d => { const r = d.rows.find(x => x[5] === true); r[5] = false }).some(e => e.includes('qualified flag')))
})
test('rejects a leaderboard player without a profile file', () => {
  assert.ok(broken(leaders('rushing'), d => { d.rows[0][0] = '999999999' }).some(e => e.includes('no player/999999999.json')))
})
test('rejects PPA published from a pull that does not line up with the ratings week', () => {
  assert.ok(broken(leaders('receiving'), d => { d.ppa.available = false; d.ppa.reason = 'pulled after week 5 games had started' }).some(e => e.includes('PPA published')))
})
test('rejects a leaderboard for a different week', () => {
  assert.ok(broken(leaders('defense'), d => { d.through_week -= 1 }).some(e => e.includes('ratings week')))
})
test('rejects a leaderboard out of order', () => {
  assert.ok(broken(leaders('kicking'), d => { d.rows.reverse() }).some(e => e.includes('not sorted')))
})
test('accepts an unavailable board only when it lists no players', () => {
  assert.deepEqual(broken(leaders('punting'), d => { d.through_week = null; d.unavailable = 'no season player stats pulled'; d.rows = [] }), [])
  assert.ok(broken(leaders('punting'), d => { d.through_week = null; d.unavailable = 'x' }).some(e => e.includes('unavailable board')))
})

// Recruiting
test('rejects class counts that disagree with the recruit rows', () => {
  assert.ok(broken('recruiting/teams_2026.json', d => { d.rows[0][4] += 1 }).some(e => e.includes('differ from hs_2026.json')))
})
test('rejects a ranked open class', () => {
  assert.ok(broken('recruiting/teams_2027.json', d => { d.rows[0][1] = 1; d.ranked = true }).some(e => e.includes('open class cannot be ranked')))
})
test('rejects recruits out of national-rank order', () => {
  assert.ok(broken('recruiting/hs_2025.json', d => { [d.rows[0], d.rows[1]] = [d.rows[1], d.rows[0]] }).some(e => e.includes('national-rank order')))
})
test('rejects a blue-chip share that does not match its counts', () => {
  assert.ok(broken('recruiting/cards.json', d => { const c = d.teams.find(t => t.blue_chip.rated > 0); c.blue_chip.share = 0.999 }).some(e => e.includes('blue-chip share')))
})
test('rejects a team card rank that differs from the class file', () => {
  assert.ok(broken('recruiting/cards.json', d => { const c = d.teams.find(t => t.classes[3]?.rank); c.classes[3].rank += 1 }).some(e => e.includes('rank differs')))
})

// Transfer portal
test('rejects a Star Churn that does not follow from the rows', () => {
  assert.ok(broken('recruiting/portal_2026.json', d => { d.teams[0][9] += 1 }).some(e => e.includes('team totals differ')))
})
test('rejects a matched transfer without an athlete id', () => {
  assert.ok(broken('recruiting/portal_2026.json', d => { const r = d.rows.find(x => x[10] === 'destination'); r[11] = null }).some(e => e.includes('athlete_id must be set')))
})
test('rejects match counts that disagree with the rows', () => {
  assert.ok(broken('recruiting/portal_2025.json', d => { d.match.unmatched += 1 }).some(e => e.includes('match counts')))
})
test('rejects a team-card portal tile that differs from the portal file', () => {
  assert.ok(broken('recruiting/cards.json', d => { const c = d.teams.find(t => t.portal); c.portal.in += 1 }).some(e => e.includes('portal tile')))
})

// Player ratings beta
test('rejects a tight end in the rating lists', () => {
  assert.ok(broken('players/ratings/top.json', d => { d.rows[0][4] = 'TE' }).some(e => e.includes('tight ends')))
})
test('rejects an offensive lineman not flagged Estimated', () => {
  assert.ok(broken('players/ratings/team/333.json', d => { const r = d.rows.find(x => x[4] === 'OL'); r[9] = false }).some(e => e.includes('flags')))
})
test('rejects a rating outside 30-99', () => {
  assert.ok(broken('players/ratings/team/333.json', d => { d.rows[0][6] = 100 }).some(e => e.includes('ovr 100')))
})
test('rejects a list rating that differs from the team file', () => {
  assert.ok(broken('players/ratings/top.json', d => { d.rows[d.rows.length - 1][7] += 1 }).some(e => e.includes('differs from the team file')))
})
