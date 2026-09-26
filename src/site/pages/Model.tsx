import { DataGate, fmt, Freshness, PageHead, useData } from '../components'
import type { IndexDoc } from '../data'
import { Link } from '../router'

export default function Model() {
  const index = useData<IndexDoc>('index.json')
  return <>
    <PageHead title="Model" lede={<>CFPi+ is the production version of the <strong>Cavender Football Power Index</strong>. It rates every FBS team in points relative to an average FBS team, then plays out the rest of the season many times.</>} />
    <DataGate source={index} label="Model details">{({ meta }) => <div className="cf-prose">
      <Freshness meta={meta} sims />
      <h2>Ratings</h2>
      <p>Each week the model solves one opponent-adjusted regression over every game played so far. Each team gets an offense and a defense value. The regression uses final scores (adjusted for fumble luck, with home field removed) and play-by-play success rates. Early in the season a preseason prior based on last season, returning production, talent and coaching carries most of the weight, and it fades as games are played. FCS and lower-division opponents are rated too, so games against them count.</p>
      <p><strong>Power</strong> = offense − defense. A lower defensive number is better. A neutral-site margin between two teams is roughly the difference in their power. The home team gets <span className="cf-num">{fmt(meta.hfa, 2) ?? '—'}</span> points.</p>
      <p>Only results available before each Monday 00:00 UTC cutoff are used, so “Ratings through Week {meta.ratings_week ?? '—'}” means exactly the games the model had seen at that cutoff.</p>
      <h2>Game projections</h2>
      <p>Projected margin = home power − away power + home field (zero at neutral sites). Win probability comes from the same normal model the simulation uses, with a standard deviation of <span className="cf-num">{fmt(meta.sigma, 2) ?? '—'}</span> points. Matchup quality combines both teams’ rating percentiles with how close the game projects (<Link to="/games/">Games</Link> explains the formula).</p>
      <h2>Season simulation and the playoff</h2>
      <p>The rest of the regular season is simulated {meta.sim_count ? `${meta.sim_count.toLocaleString()} times` : 'many times'}. Conference title games are not played in the simulation: each conference’s champion is the team that finishes first in its conference standings (with cfbseedR’s tiebreakers). In each simulated season, teams are ranked by a résumé score fitted to past committee rankings: wins above a benchmark team, opponent-adjusted margin, and a conference title. The 12-team field is then built with the 2026 rules: power-conference champions, the top-ranked team from the other conferences, Notre Dame when ranked in the top 12, and at-large teams. Seeding is straight, the top four get byes, and the bracket is played out. Every percentage on this site is the share of simulated seasons in which something happened.</p>
      <h2>What the site does not show</h2>
      <p>Betting lines are never a model input. TV networks, line movement, and per-team EPA or success rate are not in the model output and are omitted rather than estimated. CFPi+ ratings for weeks before it became the published model are reconstructions (the unchanged model re-run at each past cutoff) and are labelled wherever they appear.</p>
    </div>}</DataGate>
  </>
}
