import { DataGate, fmt, Freshness, PageHead, useData } from '../components'
import type { GamesDoc, HistoryDoc, IndexDoc } from '../data'
import { useReview } from '../games'
import { Link } from '../router'

type Tally = { w: number; l: number; p: number }
const rec = (t: Tally) => `${t.w}–${t.l}${t.p ? `–${t.p}` : ''}`
const share = (t: Tally) => t.w + t.l ? `${(100 * t.w / (t.w + t.l)).toFixed(1)}%` : '—'

/** The model's season record in picks: straight up (its projected winner won) and against the spread (the side it
 *  likes more than the sportsbook line covered). Every game is graded from its pre-game projection and line; games
 *  without a projection (non-FBS opponents) or, for ATS, without a stored line are not counted. */
function PickRecord({ season, hfa }: { season: number; hfa: number | null }) {
  const games = useData<GamesDoc>('games.json')
  const history = useData<HistoryDoc>('history.json')
  const review = useReview(games.data?.games ?? [], history.data, season, hfa)
  if (!games.data || !history.data) return null
  const su: Tally = { w: 0, l: 0, p: 0 }, ats: Tally = { w: 0, l: 0, p: 0 }, big: Tally = { w: 0, l: 0, p: 0 }
  let finals = 0, withLine = 0
  for (const g of games.data.games) {
    if (g.status !== 'final' || g.home_points == null || g.away_points == null) continue
    finals++
    const r = review.get(g.game_id), m = r?.model
    if (m == null) continue
    const actual = g.home_points - g.away_points
    if (m !== 0 && actual !== 0) (Math.sign(m) === Math.sign(actual) ? su.w++ : su.l++)
    const k = r?.market
    if (k == null) continue
    withLine++
    const edge = m + k, cover = actual + k   // both from the home side: >0 favors the home team
    if (edge === 0) continue
    for (const t of Math.abs(edge) >= 3 ? [ats, big] : [ats]) cover === 0 ? t.p++ : Math.sign(edge) === Math.sign(cover) ? t.w++ : t.l++
  }
  if (su.w + su.l === 0) return null
  return <>
    <h2>Track record this season</h2>
    <dl className="cf-statgrid">
      <div><dt>Straight up</dt><dd className="cf-big cf-num">{rec(su)}</dd><dd className="cf-small cf-muted">{share(su)} of projected winners</dd></div>
      <div><dt>Against the spread</dt><dd className="cf-big cf-num">{rec(ats)}</dd><dd className="cf-small cf-muted">{share(ats)} · {withLine} games with a line</dd></div>
      <div><dt>ATS, edge of 3+ points</dt><dd className="cf-big cf-num">{rec(big)}</dd><dd className="cf-small cf-muted">{share(big)} when it disagreed most</dd></div>
    </dl>
    <p className="cf-small cf-muted">Picks are graded from the ratings published before each game’s week (projected margin = home power − away power + home field{hfa != null ? ` of ${hfa.toFixed(1)}` : ''}), across {su.w + su.l} of {finals} finished games; games with a non-FBS opponent are not graded. Against the spread, the model’s side is the team it likes more than the line; only games with a recorded opening spread count, and the opening spread (the first line CollegeFootballData recorded, not the closing line) is the one used. Pushes are excluded from the percentages. Lines are never a model input, and this is a record of the model’s output, not betting advice.</p>
  </>
}

export default function Model() {
  const index = useData<IndexDoc>('index.json')
  return <>
    <PageHead title="Model" lede={<>CFPi+ is the production version of the <strong>Cavender Football Power Index</strong>. It rates every FBS team in points relative to an average FBS team, then plays out the rest of the season many times.</>} />
    <DataGate source={index} label="Model details">{({ meta }) => <div className="cf-prose">
      <Freshness meta={meta} sims />
      <PickRecord season={meta.season} hfa={meta.hfa} />
      <h2>What drives the ratings</h2>
      <p>Every team gets an offense rating and a defense rating, both in points against an average FBS team. They are re-solved every week in one opponent-adjusted regression that blends three kinds of evidence.</p>
      <h3>1. Final scores</h3>
      <p>Each team’s points in each game are explained by its own offense, its opponent’s defense and home field. Fumbles are treated as luck: who recovered a loose ball is not credited to either team, so a fumble bounce does not move a rating.</p>
      <h3>2. Play-by-play success rate</h3>
      <p>The model also grades every play. A play is a success if it gains 50% of the needed yards on 1st down, 70% on 2nd down, or all of them on 3rd or 4th down. Success rate is steadier than the scoreboard, so it is what keeps one lucky bounce or a late meaningless touchdown from swinging a rating. Garbage time (a lopsided score late in the game), overtime, kneels, spikes, penalties and special teams are left out.</p>
      <h3>3. The preseason prior</h3>
      <p>Before a game is played, each team’s rating comes entirely from its prior: last season’s ratings, last season’s success rate, returning production, recruiting and coaching. The prior is weaker for teams with more roster turnover. It never decays on a schedule. It fades only because games pile up: about half of a team’s rating is still preseason after three games, and about a quarter after six.</p>
      <h3>Opponent adjustment and level</h3>
      <p>Every game involves both teams’ ratings, so beating a strong opponent is worth more than beating a weak one and a team is measured against the schedule it actually played. FCS and lower-division opponents are rated in the same system, with their overall level relative to FBS learned from FBS-vs-FCS games, so a win over an FCS team counts for far less than a win over an FBS team.</p>
      <p><strong>Power</strong> = offense − defense. A lower defensive number is better. A neutral-site margin between two teams is roughly the difference in their power. The home team gets <span className="cf-num">{fmt(meta.hfa, 2) ?? '—'}</span> points.</p>
      <p>Only results available before each Monday 00:00 UTC cutoff are used, so “Ratings Through Week {meta.ratings_week ?? '—'}” means exactly the games the model had seen at that cutoff.</p>
      <h2>Game projections</h2>
      <p>Projected margin = home power − away power + home field (zero at neutral sites). Win probability comes from the same normal model the simulation uses, with a standard deviation of <span className="cf-num">{fmt(meta.sigma, 2) ?? '—'}</span> points. Matchup quality combines how highly both teams rank with how close the game projects (<Link to="/games/">Games</Link> explains the formula).</p>
      <h2>Season simulation and the playoff</h2>
      <p>The rest of the regular season is simulated {meta.sim_count ? `${meta.sim_count.toLocaleString()} times` : 'many times'}. Conference title games are not played in the simulation: each conference’s champion is the team that finishes first in its conference standings (with cfbseedR’s tiebreakers). In each simulated season, teams are ranked by a résumé score fitted to past committee rankings: wins above a benchmark team, opponent-adjusted margin, and a conference title. The 12-team field is then built with the 2026 rules: power-conference champions, the top-ranked team from the other conferences, Notre Dame when ranked in the top 12, and at-large teams. Seeding is straight, the top four get byes, and the bracket is played out. Every percentage on this site is the share of simulated seasons in which something happened.</p>
      <h2>What the site does not show</h2>
      <p>Betting lines are never a model input, and neither are polls, rankings or the committee’s opinion. TV networks and line movement are not in the model output and are omitted rather than estimated. CFPi+ ratings for weeks before it became the published model are reconstructions (the unchanged model re-run at each past cutoff) and are labelled wherever they appear.</p>
    </div>}</DataGate>
  </>
}
