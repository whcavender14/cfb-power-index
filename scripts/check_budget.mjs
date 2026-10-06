// Performance budget, checked after `vite build` (gzip sizes, as GitHub Pages serves them). Fails the build when exceeded.
// Budgets and the before/after measurements: docs/website/PERFORMANCE.md.
import { readdirSync, readFileSync, statSync } from 'node:fs'
import { gzipSync } from 'node:zlib'
import { fileURLToPath } from 'node:url'

const here = rel => fileURLToPath(new URL(rel, import.meta.url))

const KB = 1024
const gz = path => gzipSync(readFileSync(path), { level: 9 }).length
const dist = here('../dist/')
const data = here('../public/data/v2/')
const assets = readdirSync(`${dist}assets`)
const js = assets.filter(f => f.endsWith('.js'))
const entry = js.find(f => /^index-/.test(f))
const errors = [], lines = []
const check = (label, bytes, limit) => { lines.push(`${label.padEnd(34)} ${(bytes / KB).toFixed(1).padStart(7)} KB  (budget ${limit} KB)`); if (bytes > limit * KB) errors.push(`${label}: ${(bytes / KB).toFixed(1)} KB > ${limit} KB`) }

check('Entry JS (every page)', gz(`${dist}assets/${entry}`), 90)
for (const f of js.filter(f => f !== entry)) check(`Chunk ${f.replace(/-[\w-]{8}\.js$/, '')}`, gz(`${dist}assets/${f}`), f.startsWith('Legacy') ? 25 : 12)
for (const f of assets.filter(f => f.endsWith('.css'))) check('CSS (all pages)', gz(`${dist}assets/${f}`), 25)   // was 20; raised for the Compare teams panel, phone layout rules and gold matchup outlines
check('Home data (index + teams)', gz(`${data}index.json`) + gz(`${data}teams.json`), 30)
check('games.json (Games, What if)', gz(`${data}games.json`), 50)
check('scenario.json (What if, lazy)', gz(`${data}scenario.json`), 1200)   // 10,000 simulations (was 250 KB at 1,000)
const teamFiles = readdirSync(`${data}team`)
check('Largest team file', Math.max(...teamFiles.map(f => gz(`${data}team/${f}`))), 5)
const usageDir = `${data}usage/`
try { const uf = readdirSync(usageDir); if (uf.length) check('Largest usage/depth-chart file', Math.max(...uf.map(f => gz(`${usageDir}${f}`))), 8) } catch { /* no usage files */ }
// /players/ leaderboards (lazy, one category per view): docs/website/PLAYER_FEATURES_STAGE0.md §7.
const leadersDir = `${data}players/leaders/`
try { for (const f of readdirSync(leadersDir)) check(`Leaders ${f}`, gz(`${leadersDir}${f}`), 25) } catch { /* no leaderboards */ }
// Player ratings beta (lazy): the Ratings view's list and one team file per player card.
try {
  check('players/ratings/top.json', gz(`${data}players/ratings/top.json`), 15)
  const rt = readdirSync(`${data}players/ratings/team/`)
  check('Largest players/ratings/team file', Math.max(...rt.map(f => gz(`${data}players/ratings/team/${f}`))), 5)
} catch { /* no ratings */ }
// Recruiting (lazy): one class's recruits load only on the Players / Commitments views; the rest are small.
const recDir = `${data}recruiting/`
try {
  const rf = readdirSync(recDir)
  check('Largest recruiting hs_<year>.json', Math.max(...rf.filter(f => f.startsWith('hs_')).map(f => gz(`${recDir}${f}`))), 130)
  check('Largest recruiting teams_<year>.json', Math.max(...rf.filter(f => f.startsWith('teams_')).map(f => gz(`${recDir}${f}`))), 10)
  check('Largest recruiting portal_<year>.json', Math.max(...rf.filter(f => f.startsWith('portal_')).map(f => gz(`${recDir}${f}`))), 110)
  check('recruiting cards.json (team pages)', gz(`${recDir}cards.json`), 10)
  check('recruiting dashboard.json', gz(`${recDir}dashboard.json`), 5)
} catch { /* no recruiting files */ }
const sm = readdirSync(here('../public/logos/sm/'))
check('Largest small logo', Math.max(...sm.map(f => statSync(here(`../public/logos/sm/${f}`)).size)), 40)

console.log(lines.join('\n'))
if (errors.length) { console.error(`Performance budget exceeded:\n  ${errors.join('\n  ')}`); process.exit(1) }
console.log('Performance budget met.')
