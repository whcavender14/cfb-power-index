import '../team.css'
import { STAT_GROUPS, StatRow, statValue } from '../stats'
import { teamTheme } from '../teamTheme'
import { lazy, Suspense, useEffect, useMemo, type ReactNode } from 'react'
const DepthChartSection = lazy(() => import('../DepthChart'))
const RecruitingCard = lazy(() => import('../RecruitingCard'))
import { RESUME_INFO } from './Resume'
import { Bump, DataGate, Freshness, Info, Missing, Movement, Num, Pct, pctText, TeamLink, TeamLogo, useData, useTeams } from '../components'
import NotFound from './NotFound'
import { PlayerLink } from '../player'
import type { EfficiencyDoc, Game, HistoryDoc, Leader, Leaders, NotableGame, PlayoffTeam, RecordCount, ScenarioDoc, TeamDoc, TeamMeta } from '../data'
import HistoryChart, { HistoryNote, HistoryTable } from '../HistoryChart'
import { kickoffText, projection, Quality, QUALITY_INFO, WINPROB_INFO } from '../games'
import { Link, useQueryParam } from '../router'
import { COUNTS_BELOW, decode, formatPicks, parsePicks, scenarioResults, WARN_BELOW, type Pick } from '../scenario'
import { Share } from '../ScenarioShare'

const LOC = { home: ['H', 'Home'], away: ['A', 'Away'], neutral: ['N', 'Neutral site'] } as const

/** One schedule row: opponent logo and name (linked for FBS teams; a monogram placeholder for teams without a logo),
 *  site (home / away / neutral), then the result or the forecast with this team's win probability. */
/** Tints the mobile browser chrome with the team color while a team page is open. */
function ThemeColorMeta({ color }: { color: string | null }) {
  useEffect(() => {
    if (!color) return
    const metas = [...document.querySelectorAll<HTMLMetaElement>('meta[name="theme-color"]')]
    const made = metas.length ? null : Object.assign(document.createElement('meta'), { name: 'theme-color' })
    if (made) document.head.appendChild(made)
    const list = made ? [made] : metas, prev = list.map(m => m.content)
    list.forEach(m => { m.content = color })
    return () => { list.forEach((m, i) => { m.content = prev[i] }); made?.remove() }
  }, [color])
  return null
}

function ScheduleRow({ g, id, pick }: { g: Game; id: string; pick?: ReactNode }) {
  const home = g.home_id === id
  const oppId = home ? g.away_id : g.home_id
  const oppName = home ? g.away_team : g.home_team
  const oppFbs = home ? g.away_fbs : g.home_fbs
  const loc = LOC[g.neutral ? 'neutral' : home ? 'home' : 'away']
  let outcome = <Missing />
  if (g.status === 'final') {
    const us = home ? g.home_points! : g.away_points!, them = home ? g.away_points! : g.home_points!
    const won = us > them
    outcome = <span className={`cf-result ${won ? 'is-win' : 'is-loss'}`}><b>{won ? 'W' : 'L'}</b> <span className="cf-num">{us}–{them}</span></span>
  } else {
    const p = projection(g)
    if (p) {
      const ours = p.favoriteId === id
      const prob = g.win_prob_home == null ? null : home ? g.win_prob_home : 1 - g.win_prob_home
      outcome = <span className="cf-proj"><span className="cf-num">{p.margin < 0.05 ? 'Even' : `${ours ? '−' : '+'}${p.margin.toFixed(1)}`}</span>
        <span className="cf-muted"> · </span><span className="cf-num">{pctText(prob, 0)}</span><span className="cf-muted cf-hide-xs"> to win</span></span>
    }
  }
  return <li className={`cf-sched-row${g.status === 'final' ? ' is-final' : ''}${pick ? ' has-pick' : ''}`}>
    <span className="cf-sched-wk cf-muted">Wk {g.week}</span>
    <span className="cf-sched-date cf-muted">{kickoffText(g)}</span>
    <span className="cf-sched-loc" title={loc[1]}><span aria-hidden="true">{loc[0]}</span><span className="cf-sr">{loc[1]}</span></span>
    <span className="cf-sched-opp"><TeamLink id={oppId} name={oppName} size={26} sub={[g.neutral ? 'Neutral site' : home ? 'Home' : 'Away', oppFbs ? null : 'FCS'].filter(Boolean).join(' · ')} /></span>
    <span className="cf-sched-out">{outcome}</span>
    <span className="cf-sched-q">{g.status === 'scheduled' ? <Quality value={g.quality} /> : null}</span>
    {pick}
  </li>
}

/** The schedule in week order with a bye entry for every week between the first and last game that the team does not play. */
type SchedItem = { bye: false; g: Game } | { bye: true; week: number }
function scheduleItems(schedule: Game[]): SchedItem[] {
  const games = [...schedule].sort((a, b) => a.week - b.week || a.kickoff.localeCompare(b.kickoff))
  const out: SchedItem[] = []
  games.forEach((g, i) => {
    const prev = games[i - 1]
    if (prev) for (let w = prev.week + 1; w < g.week; w++) out.push({ bye: true, week: w })
    out.push({ bye: false, g })
  })
  return out
}

/** Win / loss toggle for one upcoming game: a pick for the what-if segment (click again to clear). */
function PickToggle({ g, id, team, pick, onPick }: { g: Game; id: string; team: string; pick: Pick | undefined; onPick: (side: 'home' | 'away' | null) => void }) {
  const ours: 'home' | 'away' = g.home_id === id ? 'home' : 'away', theirs = ours === 'home' ? 'away' : 'home'
  const opp = ours === 'home' ? g.away_team : g.home_team
  const btn = (side: 'home' | 'away', text: string, label: string) => {
    const on = pick?.side === side
    return <button type="button" className={`cf-wl${on ? ' is-on' : ''}${side === ours ? ' is-w' : ' is-l'}`} aria-pressed={on} aria-label={label} title={label} onClick={() => onPick(on ? null : side)}>{text}</button>
  }
  return <span className="cf-sched-pick" role="group" aria-label={`What if: Week ${g.week} vs ${opp}`}>
    {btn(ours, 'W', `What if ${team} beats ${opp}`)}{btn(theirs, 'L', `What if ${team} loses to ${opp}`)}
  </span>
}

function Delta({ now, base }: { now: number; base: number | null | undefined }) {
  if (base == null) return null
  const d = now - base
  if (Math.abs(d) < 0.05) return <span className="cf-delta cf-muted"> ±0.0</span>
  return <span className={`cf-delta ${d > 0 ? 'is-up' : 'is-down'}`}> {d > 0 ? '▲' : '▼'}{Math.abs(d).toFixed(1)}</span>
}

/** This team's odds in the simulated seasons where every pick happened (same filter as the What If? page; nothing is
 *  re-simulated). Scenario data loads only once a pick exists. */
function TeamWhatIf({ team, picks, base, nGames, onClear }: { team: TeamMeta; picks: Pick[]; base: PlayoffTeam; nGames: number; onClear: () => void }) {
  const scen = useData<ScenarioDoc>(picks.length ? 'scenario.json' : null)
  const decoded = useMemo(() => scen.data ? decode(scen.data) : null, [scen.data])
  const indep = team.conference === 'FBS Independents'
  const baseLosses = nGames - base.proj_wins
  const published = <dl className="cf-kv cf-wi-kv">
    <div><dt>Make playoff</dt><dd><Pct value={base.p_playoff} /></dd></div>
    <div><dt>First-round bye</dt><dd><Pct value={base.p_bye} /></dd></div>
    <div><dt>Conference title</dt><dd>{indep ? <Missing why="Independent: no conference title" /> : <Pct value={base.p_conf} />}</dd></div>
    <div><dt>Expected record</dt><dd className="cf-num">{base.proj_wins.toFixed(1)}–{baseLosses.toFixed(1)}</dd></div>
  </dl>
  const link = `/whatif/?pick=${formatPicks(picks)}`
  return <aside className="cf-wi" aria-labelledby="t-whatif">
    <div className="cf-panel-head"><h3 id="t-whatif" className="cf-h3">What If?</h3>{picks.length > 0 && <button type="button" className="cf-btn cf-btn-sm" onClick={onClear}>Clear picks</button>}</div>
    {picks.length === 0 ? <>
      <p className="cf-small cf-muted">Pick <b>W</b> or <b>L</b> on any remaining game to see how {team.team}’s odds change. These are the published odds.</p>
      {published}
    </> : <DataGate source={scen} label="Scenario data">{() => {
      const d = decoded!
      const valid = picks.filter(p => d.games.has(p.gameId))
      const { sims, res } = scenarioResults(d, valid), n = sims.length
      const r = res.get(team.team_id)
      const games = d.teamGames.get(team.team_id) ?? nGames
      return <>
        <p className={`cf-whatif-status${n < WARN_BELOW ? ' is-warn' : ''}`} role="status"><Bump on={n}><strong className="cf-num">{n.toLocaleString()}</strong></Bump> of {d.n.toLocaleString()} simulated seasons match.
          {n === 0 ? ' This combination never happened in the simulations. Remove a pick.'
            : n < COUNTS_BELOW ? ` Too few seasons for percentages (fewer than ${COUNTS_BELOW}); counts are shown instead. Treat them as anecdotes.`
            : n < WARN_BELOW ? ` Fewer than ${WARN_BELOW} seasons: a 50% figure could be off by about 10 points either way. Read changes loosely.` : ''}
          <Info text={`Each pick keeps only the simulated seasons in which that result happened; nothing is re-simulated and no rating changes. Below ${WARN_BELOW} matching seasons a warning appears; below ${COUNTS_BELOW} only counts are shown.`} label="About matching seasons" /></p>
        {r && n > 0 && <dl className="cf-kv cf-wi-kv">
          <div><dt>Make playoff</dt><dd><Bump on={r.playoff / n}><Share k={r.playoff} n={n} base={base.p_playoff} /></Bump></dd></div>
          <div><dt>First-round bye</dt><dd><Bump on={r.bye / n}><Share k={r.bye} n={n} base={base.p_bye} /></Bump></dd></div>
          <div><dt>Conference title</dt><dd>{indep ? <Missing why="Independent: no conference title" /> : <Bump on={r.conf / n}><Share k={r.conf} n={n} base={base.p_conf} /></Bump>}</dd></div>
          <div><dt>Expected record</dt><dd className="cf-num"><Bump on={r.wins / n}>{(r.wins / n).toFixed(1)}–{(games - r.wins / n).toFixed(1)}<Delta now={r.wins / n} base={base.proj_wins} /></Bump></dd></div>
        </dl>}
        <p className="cf-small cf-muted">▲▼ = change from the published odds (percentage points; wins for the record). <Link to={link}>Open these picks on the What If? page</Link> to add other games and see every team.</p>
      </>
    }}</DataGate>}
  </aside>
}

const SOS_INFO = 'Mean CFPi+ rating of the opponents (FBS and non-FBS, as the model rates them). Higher = harder. Rank is among FBS teams.'
const SOR_INFO = 'Strength of record: wins so far minus the wins a benchmark team (the No. 60 CFPi+ team, the same benchmark the simulation uses to rank teams for the playoff) would expect against the same opponents and sites. Rank is among FBS teams.'

function Notable({ g }: { g: NotableGame | null }) {
  if (!g) return <Missing why="None yet" />
  const site = g.loc > 0 ? 'vs' : g.loc < 0 ? 'at' : 'vs'
  return <span className="cf-notable"><span className="cf-at">{site}</span>{g.opp_fbs ? <TeamLink id={g.opp_id} name={g.opp} size={18} sub={g.opp_rank ? `No. ${g.opp_rank} · ${g.pts}–${g.opp_pts}` : `${g.pts}–${g.opp_pts}`} /> : <span>{g.opp} <span className="cf-muted cf-small">(non-FBS) {g.pts}–{g.opp_pts}</span></span>}</span>
}

/** Final-record distribution: raw simulation counts; a rare losing tail is grouped in the chart only (the table keeps every record). */
function RecordDist({ rows, n, current }: { rows: RecordCount[]; n: number; current: { w: number | null; l: number | null } }) {
  const sorted = [...rows].sort((a, b) => b.wins - a.wins || a.losses - b.losses)
  let cut = sorted.length
  while (cut > 0 && sorted[cut - 1].count / n < 0.01) cut--
  const tail = sorted.slice(cut)
  const bars = tail.length >= 2
    ? [...sorted.slice(0, cut).map(r => ({ label: `${r.wins}–${r.losses}`, count: r.count })), { label: `${tail[0].wins}–${tail[0].losses} or worse`, count: tail.reduce((a, r) => a + r.count, 0) }]
    : sorted.map(r => ({ label: `${r.wins}–${r.losses}`, count: r.count }))
  const max = Math.max(...bars.map(b => b.count))
  let cum = 0
  return <>
    <div className="cf-dist-bars cf-rec-bars" role="img" aria-label={bars.map(b => `${b.label}: ${pctText(b.count / n, 1)}`).join(', ')}>
      {bars.map(b => <span key={b.label} className="cf-dist-col" title={`${b.label}: ${b.count.toLocaleString()} of ${n.toLocaleString()} simulations`}>
        <span className="cf-dist-val">{b.count / n >= 0.005 ? `${Math.round((b.count / n) * 100)}%` : '<1%'}</span>
        <i style={{ height: `${(b.count / max) * 100}%` }} />
        <b>{b.label.replace(' or worse', '')}{b.label.endsWith('or worse') ? <small>or worse</small> : null}</b>
      </span>)}
    </div>
    <details className="cf-details"><summary>All {sorted.length} final records ({n.toLocaleString()} simulations)</summary>
      <div className="cf-table-wrap"><table className="cf-table cf-table-compact">
        <thead><tr><th scope="col" className="cf-th-start">Final Record</th><th scope="col" className="cf-th-end">Simulations</th><th scope="col" className="cf-th-end">Share</th><th scope="col" className="cf-th-end">This or Better</th></tr></thead>
        <tbody>{sorted.map(r => { cum += r.count; return <tr key={`${r.wins}-${r.losses}`}>
          <td className="cf-num">{r.wins}–{r.losses}</td><td className="cf-td-end cf-num">{r.count.toLocaleString()}</td>
          <td className="cf-td-end cf-num">{pctText(r.count / n, 1)}</td><td className="cf-td-end cf-num">{pctText(cum / n, 1)}</td>
        </tr> })}</tbody>
      </table></div>
    </details>
    <p className="cf-small cf-muted">Regular-season record (all {rows[0] ? rows[0].wins + rows[0].losses : ''} games). Conference title games are not simulated, and bowls and playoff games are not counted.{current.w != null ? ` Current record ${current.w}–${current.l} is included.` : ''}</p>
  </>
}

const n = (p: Leader, k: string) => Number(p[k] ?? 0)
const LEADER_GROUPS: { key: keyof Omit<Leaders, 'through_week' | 'source'>; title: string; line: (p: Leader) => string }[] = [
  { key: 'passing', title: 'Passing', line: p => `${n(p, 'passing_completions')}/${n(p, 'passing_att')} · ${n(p, 'passing_yds').toLocaleString()} yds · ${n(p, 'passing_td')} TD · ${n(p, 'passing_int')} INT` },
  { key: 'rushing', title: 'Rushing', line: p => `${n(p, 'rushing_car')} car · ${n(p, 'rushing_yds').toLocaleString()} yds · ${n(p, 'rushing_td')} TD` },
  { key: 'receiving', title: 'Receiving', line: p => `${n(p, 'receiving_rec')} rec. · ${n(p, 'receiving_yds').toLocaleString()} yds · ${n(p, 'receiving_td')} TD` },
  { key: 'sacks', title: 'Sacks', line: p => `${n(p, 'defensive_sacks')} sack${n(p, 'defensive_sacks') === 1 ? '' : 's'} · ${n(p, 'defensive_tfl')} TFL · ${n(p, 'defensive_tot')} tackles` },
  { key: 'interceptions', title: 'Interceptions', line: p => `${n(p, 'interceptions_int')} INT · ${String(n(p, 'interceptions_yds')).replace('-', '−')} ret. yds${n(p, 'interceptions_td') ? ` · ${n(p, 'interceptions_td')} TD` : ''}` },
]

function StatLeaders({ leaders }: { leaders: Leaders }) {
  return <section className="cf-panel cf-span-all" aria-labelledby="t-leaders">
    <h2 id="t-leaders" className="cf-h2">Statistical Leaders <Info text="Season totals from CollegeFootballData through the same week as the ratings. Leaders are picked by fixed rules: passing yards, rushing yards (top 2), receiving yards (top 3), sacks (top 3) and interceptions. They are statistical leaders only; the data does not say who starts." label="About statistical leaders" /></h2>
    <div className="cf-leaders">
      {LEADER_GROUPS.map(g => <div key={g.key} className="cf-leader-group">
        <h3 className="cf-h3">{g.title}</h3>
        {leaders[g.key].length === 0 ? <p className="cf-muted cf-small">None yet</p> :
          <ol className="cf-leader-list">{leaders[g.key].map(p => <li key={p.athlete_id}>
            <span className="cf-leader-name"><PlayerLink id={p.athlete_id}>{p.player}</PlayerLink>{p.position ? <span className="cf-muted"> · {p.position}</span> : null}</span>
            <span className="cf-leader-line cf-num">{g.line(p)}</span>
          </li>)}</ol>}
      </div>)}
    </div>
    <p className="cf-small cf-muted">Weeks 1–{leaders.through_week}, regular season. Source: CollegeFootballData.</p>
  </section>
}

/** Stats: standard team stats and raw efficiency, each with its FBS rank (definitions in ../stats.tsx). */
function TeamStats({ id }: { id: string }) {
  const doc = useData<EfficiencyDoc>('efficiency.json')
  if (!doc.data) return null
  const e = doc.data.teams.find(t => t.team_id === id)
  if (!e) return null
  const total = doc.data.teams.filter(t => t.plays != null || t.games != null).length
  const m = doc.data.method, b = doc.data.basic_method
  const groups = STAT_GROUPS.filter(g => g.defs.some(d => statValue(e, d.key) != null))
  if (!groups.length) return null
  return <section className="cf-panel cf-span-all cf-unthemed" aria-labelledby="t-stats">
    <div className="cf-panel-head"><h2 id="t-stats" className="cf-h2">Stats</h2></div>
    <div className="cf-stats">{[['scoring', 'offense'], ['defense', 'efficiency']].map(ids => <div key={ids[0]} className="cf-stats-col">
      {groups.filter(g => ids.includes(g.id)).map(g => <div key={g.id} className="cf-eff-group">
        <h3 className="cf-h3">{g.title}{g.note && <span className="cf-eff-note"> · {g.note}</span>}{g.raw && <span className="cf-tag">{m.adjusted ? 'Opponent-adjusted' : 'Raw, not opponent-adjusted'}</span>}</h3>
        <dl className="cf-eff-rows">{g.defs.map(d => <StatRow key={d.key} d={d} e={e} total={total} />)}</dl>
      </div>)}
    </div>)}</div>
    <p className="cf-small cf-muted cf-eff-foot">
      {b && e.games != null && <>Per game over the {e.games} game{e.games === 1 ? '' : 's'} in the Week {doc.data.meta.ratings_week} ratings (all opponents); turnover margin is a season total. </>}
      Ranks among {total} FBS teams, No. 1 = best; “↓ better” marks stats where lower is better, and bars always fill toward better. None of these are adjusted for opponent strength or used by the CFPi+ rating.
      <Info text={`${b ? `Standard stats: ${b.source}. ` : ''}Efficiency: ${m.source}; ${m.plays}.`} label="Sources and definitions" /></p>
  </section>
}

function TeamHistory({ id, name }: { id: string; name: string }) {
  const doc = useData<HistoryDoc>('history.json')
  if (!doc.data) return null
  const h = doc.data.teams[id]
  if (!h) return null
  return <section className="cf-panel cf-span-all" aria-labelledby="t-hist">
    <div className="cf-panel-head"><h2 id="t-hist" className="cf-h2">Rating History</h2></div>
    <HistoryChart points={doc.data.points} series={[{ id, name, slot: 1, power: h.power, rank: h.rank }]} height={220} label={`${name} CFPi+ rating by week`} />
    <HistoryNote points={doc.data.points} />
    <details className="cf-details"><summary>Show as a table</summary><HistoryTable points={doc.data.points} series={[{ id, name, slot: 1, power: h.power, rank: h.rank }]} /></details>
  </section>
}

export default function Team({ slug }: { slug: string }) {
  const doc = useData<TeamDoc>(`team/${slug}.json`)
  const [param, setParam] = useQueryParam('pick')
  const directory = useTeams()
  if (directory.size && ![...directory.values()].some(t => t.slug === slug)) return <NotFound />
  return <DataGate source={doc} label="Team">{({ meta, team, summary: s, schedule, record_dist, resume, seed_dist, playoff, leaders }) => {
    const upcoming = schedule.filter(g => g.status === 'scheduled')
    const sims = meta.sim_status === 'available'
    const upcomingIds = new Set(upcoming.map(g => g.game_id))
    const picks = parsePicks(param).filter(p => upcomingIds.has(p.gameId))   // this team's remaining games only
    const setPick = (g: Game, side: 'home' | 'away' | null) => setParam(formatPicks([...picks.filter(p => p.gameId !== g.game_id), ...(side ? [{ gameId: g.game_id, side }] : [])]))
    const whatIf = sims && playoff && upcoming.length > 0
    const theme = teamTheme(team.color, team.alt_color)
    return <div className="cf-themed" style={theme}>
      <ThemeColorMeta color={team.color} />
      <nav className="cf-crumbs" aria-label="Breadcrumb"><Link to="/teams/">Teams</Link><span aria-hidden="true"> / </span><span aria-current="page">{team.team}</span></nav>
      <header className="cf-teamhead">
        <TeamLogo id={team.team_id} name={team.team} size={72} />
        <div className="cf-teamhead-id">
          <h1>{team.team}</h1>
          <p className="cf-muted">{[team.mascot, team.conference].filter(Boolean).join(' · ')}</p>
        </div>
        <dl className="cf-teamhead-stats">
          <div><dt>CFPi+ rank</dt><dd className="cf-big">{s.rank ?? '—'}</dd><dd className="cf-small"><Movement change={s.rank_change} compared={meta.movement_compared_to_week} /></dd></div>
          <div><dt>Record</dt><dd className="cf-big cf-num">{s.wins != null ? `${s.wins}–${s.losses}` : '—'}</dd><dd className="cf-small cf-muted">{s.conf_wins == null ? '' : (s.conf_wins + (s.conf_losses ?? 0)) > 0 ? `${s.conf_wins}–${s.conf_losses} conf.` : 'No conf. games yet'}</dd></div>
          <div><dt>Power <Info text="Opponent-adjusted strength in points relative to an average FBS team." label="About power" /></dt><dd className="cf-big"><Num value={s.power} signed /></dd><dd className="cf-small cf-muted">Δ week <Num value={s.rating_change} signed why="No comparable previous week" /></dd></div>
          <div><dt>Offense</dt><dd className="cf-big"><Num value={s.off} signed /></dd><dd className="cf-small cf-muted">{s.off_rank ? `No. ${s.off_rank}` : '—'} of FBS</dd></div>
          <div><dt>Defense <Info text="Points relative to an average FBS defense; lower (more negative) is better." label="About defense" /></dt><dd className="cf-big"><Num value={s.def} signed /></dd><dd className="cf-small cf-muted">{s.def_rank ? `No. ${s.def_rank}` : '—'} of FBS</dd></div>
        </dl>
      </header>
      <Freshness meta={meta} />

      <div className="cf-team-grid">
        <section className="cf-panel" aria-labelledby="t-outlook">
          <h2 id="t-outlook" className="cf-h2">Season Outlook</h2>
          {sims && playoff ? <>
            <div className="cf-ol">
              <div className="cf-ol-lead">
                <div><b className="cf-num"><Num value={playoff.proj_wins} /></b><span>Projected wins <Info text="Mean regular-season wins across the simulated seasons (conference title games are not simulated; bowls and playoff games are excluded)." label="About projected wins" /></span></div>
                <div><b className="cf-num">{team.conference === 'FBS Independents' ? <Missing why="Independent: no conference title" /> : <Pct value={playoff.p_conf} />}</b><span>Conference title</span></div>
              </div>
              <ol className="cf-ol-ladder" aria-label="Playoff path odds">{([['Make playoff', playoff.p_playoff], ['First-round bye', playoff.p_bye], ['Reach semifinal', playoff.p_sf], ['Win title', playoff.p_champ]] as const).map(([label, v]) =>
                <li key={label}><span>{label}</span><span className="cf-ol-track" aria-hidden="true"><i style={{ width: `${Math.max(0, Math.min(1, v ?? 0)) * 100}%` }} /></span><b className="cf-num"><Pct value={v} /></b></li>)}</ol>
            </div>
            {record_dist && meta.sim_count && <figure className="cf-dist">
              <figcaption className="cf-h3">Final Record <span className="cf-muted cf-small">(share of {meta.sim_count.toLocaleString()} simulations)</span></figcaption>
              <RecordDist rows={record_dist} n={meta.sim_count} current={{ w: s.wins, l: s.losses }} />
            </figure>}
            {seed_dist && playoff.p_playoff > 0 && <p className="cf-small cf-muted">Most likely seed: No. {seed_dist.indexOf(Math.max(...seed_dist)) + 1} ({pctText(Math.max(...seed_dist), 0)}). <Link to="/playoff/">Playoff dashboard</Link></p>}
          </> : <p className="cf-muted">Simulation results are unavailable for this update.</p>}
        </section>


        <section className="cf-panel" aria-labelledby="t-resume">
          <h2 id="t-resume" className="cf-h2">Résumé</h2>
          {resume ? <div className="cf-res">
            <div className="cf-res-tiles">
              <div><b className="cf-num">{s.resume_rank ?? '—'}</b><span>Résumé rank <Info text={RESUME_INFO} label="About the résumé rank" /></span><small><Link to="/rankings/resume/">See all</Link></small></div>
              <div><b className="cf-num">{s.wins != null ? `${s.wins}–${s.losses}` : '—'}</b><span>Record</span><small>{s.conf_wins != null && s.conf_losses != null && s.conf_wins + s.conf_losses > 0 ? `${s.conf_wins}–${s.conf_losses} in conference` : 'No conf. games yet'}</small></div>
              <div><b><Num value={resume.sor} signed digits={2} /></b><span>Strength of record <Info text={SOR_INFO} label="About strength of record" /></span><small>{resume.sor_rank ? `No. ${resume.sor_rank} of FBS` : ' '}</small></div>
            </div>
            <div className="cf-res-sec"><h3 className="cf-h3">Schedule strength <Info text={SOS_INFO} label="About schedule strength" /></h3>
              <dl className="cf-res-sos">{([['Played', resume.sos_played, resume.sos_played_rank], ['Full season', resume.sos_all, resume.sos_all_rank], ['Remaining', resume.sos_remaining, resume.sos_remaining_rank]] as const).map(([label, v, r]) =>
                <div key={label}><dt>{label}</dt><dd className="cf-num"><Num value={v} signed why="No games remaining" /></dd>
                  <span className="cf-bar" aria-hidden="true"><i style={{ width: `${r ? Math.max(4, 100 - (r - 1) / 1.36) : 0}%` }} /></span>
                  <span className="cf-small cf-muted cf-res-rk">{r ? `No. ${r}` : '—'}</span></div>)}</dl>
            </div>
            <div className="cf-res-sec"><h3 className="cf-h3">Results so far</h3>
              {(() => { const done = schedule.filter(g => g.status === 'final' && g.home_points != null && g.away_points != null)
                return done.length === 0 ? <p className="cf-small cf-muted">No games played yet.</p> : <ul className="cf-res-games">{done.map(g => {
                  const home = g.home_id === team.team_id, my = (home ? g.home_points : g.away_points)!, th = (home ? g.away_points : g.home_points)!
                  const oid = home ? g.away_id : g.home_id, oname = home ? g.away_team : g.home_team
                  return <li key={g.game_id} className={my > th ? 'is-w' : 'is-l'}><b>{my > th ? 'W' : 'L'}</b><TeamLogo id={oid} name={oname} size={22} /><span className="cf-res-opp">{oname}</span><span className="cf-num cf-small">{my}–{th}</span></li> })}</ul> })()}
            </div>
            <div className="cf-res-best">
              <div><span className="cf-res-k">Best win</span><Notable g={resume.best_win} /></div>
              <div><span className="cf-res-k">Worst loss</span><Notable g={resume.worst_loss} /></div>
            </div>
          </div> : <p className="cf-muted">Résumé unavailable for this update.</p>}
          <p className="cf-small cf-muted">Best win and worst loss are judged by the opponent’s current CFPi+ rating.</p>
        </section>

        <TeamStats id={team.team_id} />

        <TeamHistory id={team.team_id} name={team.team} />

        {leaders && <StatLeaders leaders={leaders} />}

        <Suspense fallback={null}><DepthChartSection slug={team.slug} team={team} /></Suspense>

        <Suspense fallback={null}><RecruitingCard id={team.team_id} /></Suspense>

        <section className="cf-panel cf-sched-panel" aria-labelledby="t-sched">
          <h2 id="t-sched" className="cf-h2">Schedule <Info text={`Results for played games; for the rest, projected margin (negative = favored) and ${WINPROB_INFO.charAt(0).toLowerCase()}${WINPROB_INFO.slice(1)} ${QUALITY_INFO}${whatIf ? ' W / L: pick a result for the What If? panel.' : ''}`} label="About projections" /></h2>
          <div className={whatIf ? 'cf-sched-layout' : undefined}>
          <div className="cf-sched-rem">
          {schedule.length === 0 ? <p className="cf-muted">Schedule unavailable.</p>
            : <ol className="cf-sched">{scheduleItems(schedule).map(it => it.bye
              ? <li key={`bye-${it.week}`} className="cf-sched-row cf-sched-bye"><span className="cf-sched-wk cf-muted">Wk {it.week}</span><span className="cf-sched-byeline">Bye week</span></li>
              : <ScheduleRow key={it.g.game_id} g={it.g} id={team.team_id}
                  pick={whatIf ? (it.g.status === 'scheduled'
                    ? <PickToggle g={it.g} id={team.team_id} team={team.team} pick={picks.find(p => p.gameId === it.g.game_id)} onPick={side => setPick(it.g, side)} />
                    : <span className="cf-sched-pick" aria-hidden="true" />) : undefined} />)}</ol>}
          <p className="cf-small cf-muted"><Link to={`/games/?team=${team.slug}`}>All {team.team} games on the Games page</Link></p>
          </div>
          {whatIf && <TeamWhatIf team={team} picks={picks} base={playoff!} nGames={schedule.length} onClear={() => setParam('')} />}
          </div>
        </section>
      </div>
    </div>
  }}</DataGate>
}

