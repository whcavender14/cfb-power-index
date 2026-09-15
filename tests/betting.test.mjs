import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { impliedSpread, lineLabel, favoredSide, difference, valueSide, compareValues, signedPoints, favoriteLine, valueLine } from '../src/betting.ts'

test('Home handicap, neutral venues, and favored side use the same sign', () => {
  assert.equal(impliedSpread(20,25,false,3),-8)
  assert.equal(impliedSpread(20,25,true,3),-5)
  assert.equal(impliedSpread(25,20,false,3),2)
  assert.equal(lineLabel('Texas',-4.5),'Texas -4.5')
  assert.equal(lineLabel('Oklahoma',3),'Oklahoma +3.0')
  assert.equal(favoredSide('Texas','Oklahoma',2),'Oklahoma')
  assert.equal(favoredSide('Texas','Oklahoma',-2),'Texas')
  assert.equal(lineLabel('Texas',0),'Texas PK')
  assert.equal(favoredSide('Texas','Oklahoma',0),'Pick’em')
  assert.equal(signedPoints(-0.001),'0.0')
})
test('Missing inputs stay unavailable, while a neutral site does not need HFA', () => {
  assert.equal(impliedSpread(null,10,false,3),null)
  assert.equal(impliedSpread(0,10,false,3),-13)
  assert.equal(impliedSpread(0,10,false,null),null)
  assert.equal(impliedSpread(0,10,true,null),-10)
  assert.equal(impliedSpread(0,10,null,3),null)
  assert.equal(impliedSpread(NaN,10,true,3),null)
})
test('Signed discrepancy identifies value independently of the outright favorite', () => {
  const model = impliedSpread(20,24,false,3)
  assert.equal(difference(model,-3),-4)
  assert.equal(valueSide('Home','Away',difference(model,-3)),'Home')
  assert.equal(valueSide('Home','Away',difference(model,-10)),'Away')
  assert.equal(difference(model,null),null)
  assert.equal(valueSide('Home','Away',null),'Data unavailable')
  assert.equal(valueSide('Home','Away',0),'No difference')
})
test('Card labels restate home spreads from the favorite and value sides', () => {
  assert.equal(favoriteLine('Georgia','Arkansas',-25.3),'Georgia -25.3')
  assert.equal(favoriteLine('Arkansas','Georgia',25.3),'Georgia -25.3')
  assert.equal(favoriteLine('Home','Away',0.01),'Pick’em')
  assert.equal(favoriteLine('Home','Away',null),'Data unavailable')
  // Model home -7, market home -3: delta -4 points to the home side at the market price.
  assert.equal(valueLine('Home','Away',-4,-3),'Home -3.0')
  // Model home -7, market home -10: delta +3 points to the away side, who gets +10.
  assert.equal(valueLine('Home','Away',3,-10),'Away +10.0')
  assert.equal(valueLine('Home','Away',0,-3),'No difference')
  assert.equal(valueLine('Home','Away',null,-3),'Data unavailable')
})
test('Largest absolute discrepancies first, null always last in either direction', () => {
  assert.deepEqual([null,2,9,0].sort((a,b)=>compareValues(a,b,true)),[9,2,0,null])
  assert.deepEqual([null,2,-9,0].sort((a,b)=>compareValues(a,b,false)),[-9,0,2,null])
  assert.ok(compareValues('2026-09-11','2026-09-12',false)<0)
})
test('Real betting snapshot shares ratings/HFA provenance and valid quotes', () => {
  const betting = JSON.parse(readFileSync(new URL('../public/data/betting.json',import.meta.url),'utf8'))
  const ratings = JSON.parse(readFileSync(new URL('../public/data/ratings.json',import.meta.url),'utf8'))
  assert.equal(betting.schema_version,1)
  assert.equal(betting.season,ratings.season)
  assert.equal(betting.ratings_updated_at,ratings.updated_at)
  assert.ok(betting.hfa === null || Number.isFinite(betting.hfa))
  assert.equal(new Set(betting.games.map(g=>g.game_id)).size,betting.games.length)
  for (const g of betting.games) {
    assert.equal(g.week,betting.week)
    assert.notEqual(g.away_team_id,g.home_team_id)
    assert.ok(g.neutral_site === null || typeof g.neutral_site === 'boolean')
    assert.ok(g.kickoff === null || Number.isFinite(Date.parse(g.kickoff)))
    if (g.market_spread !== null) {
      assert.ok(Number.isFinite(g.market_spread))
      assert.ok(g.market_provider)
      assert.ok(Number.isFinite(Date.parse(g.market_retrieved_at)))
    } else assert.equal(g.market_retrieved_at,null)
  }
})
