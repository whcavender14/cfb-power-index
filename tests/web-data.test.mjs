import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync, readdirSync } from 'node:fs'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = new URL('../public/data/', import.meta.url)
const read = name => JSON.parse(readFileSync(new URL(name, root), 'utf8'))
const common = ['season','week','updated_at','team_id','team','conference','logo_url']
const fields = {
  ratings: ['power_rating','offensive_rating','defensive_rating','weekly_change','preseason_change'],
  simulations: ['projected_wins_current','projected_wins_preseason','playoff_probability','conference_title_probability','national_title_probability','vegas_win_total_preseason'],
}
for (const [name, metrics] of Object.entries(fields)) test(`${name}: public contract, unique identities, finite values and source timestamps`, () => {
  const data = read(`${name}.json`)
  assert.equal(data.schema_version, 1)
  assert.ok(['available', 'unavailable'].includes(data.status))
  assert.ok(Number.isInteger(data.season))
  assert.ok(data.week === null || Number.isInteger(data.week))
  assert.ok(data.updated_at === null || Number.isFinite(Date.parse(data.updated_at)))
  assert.ok(data.teams.length > 0)
  assert.equal(new Set(data.teams.map(row => row.team_id)).size, data.teams.length)
  for (const row of data.teams) {
    assert.deepEqual(Object.keys(row).sort(), [...common, ...metrics].sort())
    assert.equal(row.season, data.season)
    assert.equal(row.week, data.week)
    assert.equal(row.updated_at, data.updated_at)
    assert.equal(typeof row.team_id, 'string')
    assert.ok(row.team.length)
    assert.ok(row.logo_url === null || row.logo_url.startsWith('https://cdn.collegefootballdata.com/'))
    for (const key of metrics) {
      assert.ok(row[key] === null || Number.isFinite(row[key]), `${row.team}: ${key}`)
      if (key.endsWith('_probability') && row[key] !== null) assert.ok(row[key] >= 0 && row[key] <= 1)
    }
  }
  if (data.status === 'available') assert.ok(data.updated_at !== null)
})
test('Ratings coverage and missing weekly comparisons are honest', () => {
  const data = read('ratings.json')
  assert.equal(data.rated_teams, data.teams.filter(r => r.power_rating !== null).length)
  assert.equal(data.total_teams, data.teams.length)
  assert.equal(data.defensive_higher_is_better, false)
  if (data.weekly_comparison_week === null) assert.ok(data.teams.every(r => r.weekly_change === null))
  for (const row of data.teams.filter(r => r.power_rating !== null && r.offensive_rating !== null && r.defensive_rating !== null)) assert.ok(Math.abs(row.power_rating - row.offensive_rating + row.defensive_rating) < 0.00001)
})
test('Unavailable simulations cannot contain current forecasts', () => {
  const data = read('simulations.json')
  if (data.status === 'unavailable') {
    assert.equal(data.updated_at, null)
    for (const row of data.teams) for (const key of ['projected_wins_current', 'playoff_probability', 'conference_title_probability', 'national_title_probability']) assert.equal(row[key], null)
  } else {
    assert.ok(data.simulation_count > 0)
    assert.ok(data.playoff_format)
    assert.ok(data.wins_scope)
  }
})
test('Public files contain only the allowlisted JSON artifacts', () => {
  const walk = path => readdirSync(path, { withFileTypes: true }).flatMap(e => e.isDirectory() ? walk(join(path, e.name)) : [join(path, e.name)])
  for (const file of walk(fileURLToPath(root))) {
    assert.match(file, /\/(ratings|simulations|betting)\.json$/)
    const content = readFileSync(file, 'utf8')
    assert.doesNotMatch(content, /CFBD_API_KEY|Bearer\s|\/Users\/|training_ids|source_manifest/)
  }
})
