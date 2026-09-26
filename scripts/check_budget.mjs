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
for (const f of assets.filter(f => f.endsWith('.css'))) check('CSS (all pages)', gz(`${dist}assets/${f}`), 20)
check('Home data (index + teams)', gz(`${data}index.json`) + gz(`${data}teams.json`), 30)
check('games.json (Games, What if)', gz(`${data}games.json`), 50)
check('scenario.json (What if, lazy)', gz(`${data}scenario.json`), 250)
const teamFiles = readdirSync(`${data}team`)
check('Largest team file', Math.max(...teamFiles.map(f => gz(`${data}team/${f}`))), 5)
const sm = readdirSync(here('../public/logos/sm/'))
check('Largest small logo', Math.max(...sm.map(f => statSync(here(`../public/logos/sm/${f}`)).size)), 40)

console.log(lines.join('\n'))
if (errors.length) { console.error(`Performance budget exceeded:\n  ${errors.join('\n  ')}`); process.exit(1) }
console.log('Performance budget met.')
