// After `vite build`: give every route its own dist/<route>/index.html so direct loads and refreshes of
// nested URLs (e.g. /cfb-power-index/teams/alabama/) return 200 on GitHub Pages, with a route-specific
// <title> and description. dist/404.html is the same app shell for any other path (it renders "not found").
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'

const dist = new URL('../dist/', import.meta.url)
const shell = readFileSync(new URL('index.html', dist), 'utf8')
const teams = JSON.parse(readFileSync(new URL('../public/data/v2/teams.json', import.meta.url), 'utf8')).teams
const conferences = JSON.parse(readFileSync(new URL('../public/data/v2/conferences.json', import.meta.url), 'utf8')).conferences

const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;')
function page(title, description) {
  return shell
    .replace(/<title>[^<]*<\/title>/, `<title>${esc(title)}</title>`)
    .replace(/<meta name="description" content="[^"]*"/, `<meta name="description" content="${esc(description)}"`)
}
const routes = [
  ['rankings', 'Rankings | CFPi+', 'CFPi+ power ratings for every FBS team: rank, movement, offense, defense and playoff odds.'],
  ['games', 'Games | CFPi+', 'Every FBS game with CFPi+ projections, win probabilities and matchup quality.'],
  ['playoff', 'Playoff | CFPi+', 'College Football Playoff odds, seed probabilities and a projected 12-team field from CFPi+ simulations.'],
  ['teams', 'Teams | CFPi+', 'Every FBS team, searchable and sortable by CFPi+ power rating, offense, defense, schedule strength and strength of record.'],
  ['conferences', 'Conferences | CFPi+', 'How each FBS conference compares as a group in CFPi+: average and median rating, top-25 depth and expected playoff teams.'],
  ['compare', 'Rating history | CFPi+', 'CFPi+ rating history by week. Compare up to five teams.'],
  ['rankings/resume', 'Résumé ranking | CFPi+', 'CFPi+ résumé ranking: FBS teams ordered by strength of record, shown next to the predictive CFPi+ rank.'],
  ['whatif', 'What if? | CFPi+', 'Pick winners of upcoming games and see CFPi+ playoff, bye, conference-title and seed odds from the matching simulated seasons.'],
  ['changes', 'What changed | CFPi+', 'This week in CFPi+: biggest rank movers and rating changes, with the results behind them.'],
  ...conferences.map(c => [`conferences/${c.slug}`, `${c.is_conference ? c.name : 'Independents'} | CFPi+`, `${c.is_conference ? c.name : 'FBS independents'} in CFPi+: team ratings, strength distribution, schedule strength and playoff outlook.`]),
  ['model', 'Model | CFPi+', 'How the Cavender Football Power Index (CFPi+) rates teams and simulates the season.'],
  ['simulations', 'Season simulations | CFPi+', 'CFPi+ season simulation table and shareable graphics.'],
  ['betting', 'Betting lines | CFPi+', 'CFPi+ model lines compared with sportsbook lines, for reference.'],
  ...teams.map(t => [`teams/${t.slug}`, `${t.team} | CFPi+`, `${t.team} ${t.mascot ?? ''}: CFPi+ rating, schedule, projections and playoff odds.`.replace(/\s+/g, ' ')]),
]
for (const [path, title, description] of routes) {
  const dir = new URL(`${path}/`, dist)
  mkdirSync(dir, { recursive: true })
  writeFileSync(new URL('index.html', dir), page(title, description))
}
writeFileSync(new URL('404.html', dist), page('Page not found | CFPi+', 'CFPi+ college football power ratings.'))
console.log(`Prerendered ${routes.length} routes + 404.html`)
