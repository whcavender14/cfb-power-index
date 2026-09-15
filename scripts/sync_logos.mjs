// Mirror team logos into public/logos/<team_id>.png so the PNG export can draw them.
// The CollegeFootballData CDN sends no CORS headers: browsers can display those images
// but cannot read their pixels (fetch or canvas). Same-origin copies avoid that.
// Usage: node scripts/sync_logos.mjs [--force]
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'

const root = new URL('../public/', import.meta.url)
const outDir = new URL('logos/', root)
const force = process.argv.includes('--force')
const PNG = [0x89, 0x50, 0x4e, 0x47]

const teams = new Map()
for (const name of ['ratings', 'simulations']) {
  const file = new URL(`data/${name}.json`, root)
  if (!existsSync(file)) continue
  for (const team of JSON.parse(readFileSync(file, 'utf8')).teams) {
    if (/^\d+$/.test(team.team_id) && team.logo_url?.startsWith('https://cdn.collegefootballdata.com/')) teams.set(team.team_id, team.logo_url)
  }
}
mkdirSync(outDir, { recursive: true })

let saved = 0, kept = 0
const failed = []
const queue = [...teams]
async function worker() {
  for (let next = queue.shift(); next; next = queue.shift()) {
    const [id, url] = next
    const target = new URL(`${id}.png`, outDir)
    if (!force && existsSync(target)) { kept++; continue }
    try {
      const response = await fetch(url, { signal: AbortSignal.timeout(15000) })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const bytes = new Uint8Array(await response.arrayBuffer())
      if (!PNG.every((b, i) => bytes[i] === b)) throw new Error('not a PNG')
      writeFileSync(target, bytes)
      saved++
    } catch (error) {
      failed.push(`${id} (${error.message})`)
    }
  }
}
await Promise.all(Array.from({ length: 8 }, worker))
console.log(`Logos: ${saved} downloaded, ${kept} already present, ${failed.length} failed of ${teams.size}.`)
// A missing logo only falls back to a monogram in the export; never fail the build for it.
if (failed.length) console.warn(`Unavailable: ${failed.join(', ')}`)
