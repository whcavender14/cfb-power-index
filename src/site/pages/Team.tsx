import { RESUME_INFO } from './Resume'
import { DataGate, Freshness, Info, Missing, Movement, Num, Pct, pctText, TeamLink, TeamLogo, useData, useTeams } from '../components'
import NotFound from './NotFound'
import type { Game, HistoryDoc, Leader, Leaders, NotableGame, RecordCount, TeamDoc } from '../data'
import HistoryChart, { HistoryTable } from '../HistoryChart'
import { HistoryNote } from './Compare'
import { kickoffText, projection, Quality, QUALITY_INFO, WINPROB_INFO } from '../games'
import { Link } from '../router'

function ScheduleRow({ g, id }: { g: Game; id: string }) {
  const home = g.home_id === id
  const oppId = home ? g.away_id : g.home_id
  const oppName = home ? g.away_team : g.home_team
  const site = g.neutral ? 'vs' : home ? 'vs' : 'at'
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
      outcome = <span className="cf-proj"><span className="cf-num">{ours ? '' : '+'}{p.margin < 0.05 ? 'Even' : `${ours ? '−' : ''}${p.margin.toFixed(1)}`}</span>
        <span className="cf-muted"> · </span><span className="cf-num">{pctText(prob)}</span><span className="cf-muted"> to win</span></span>
    }
  }
  return <li className={`cf-sched-row${g.status === 'final' ? ' is-final' : ''}`}>
    <span className="cf-sched-wk cf-muted">Wk {g.week}</span>
    <span className="cf-sched-date cf-muted">{kickoffText(g)}</span>
    <span className="cf-sched-opp"><span className="cf-at">{site}</span><TeamLink id={oppId} name={oppName} size={22} sub={g.neutral ? 'Neutral site' : undefined} /></span>
    <span className="cf-sched-out">{outcome}</span>
    <span className="cf-sched-q">{g.status === 'scheduled' ? <Quality value={g.quality} /> : null}</span>
  </li>
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
        <thead><tr><th scope="col" className="cf-th-start">Final record</th><th scope="col" className="cf-th-end">Simulations</th><th scope="col" className="cf-th-end">Share</th><th scope="col" className="cf-th-end">This or better</th></tr></thead>
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
  return <section className="cf-panel" aria-labelledby="t-leaders">
    <h2 id="t-leaders" className="cf-h2">Statistical leaders <Info text="Season totals from CollegeFootballData through the same week as the ratings. Leaders are picked by fixed rules: passing yards, rushing yards (top 2), receiving yards (top 3), sacks (top 3) and interceptions. They are statistical leaders only; the data does not say who starts." label="About statistical leaders" /></h2>
    <div className="cf-leaders">
      {LEADER_GROUPS.map(g => <div key={g.key} className="cf-leader-group">
        <h3 className="cf-h3">{g.title}</h3>
        {leaders[g.key].length === 0 ? <p className="cf-muted cf-small">None yet</p> :
          <ol className="cf-leader-list">{leaders[g.key].map(p => <li key={p.athlete_id}>
            <span className="cf-leader-name">{p.player}{p.position ? <span className="cf-muted"> · {p.position}</span> : null}</span>
            <span className="cf-leader-line cf-num">{g.line(p)}</span>
          </li>)}</ol>}
      </div>)}
    </div>
    <p className="cf-small cf-muted">Weeks 1–{leaders.through_week}, regular season. Source: CollegeFootballData.</p>
  </section>
}

function TeamHistory({ id, name, slug }: { id: string; name: string; slug: string }) {
  const doc = useData<HistoryDoc>('history.json')
  if (!doc.data) return null
  const h = doc.data.teams[id]
  if (!h) return null
  return <section className="cf-panel" aria-labelledby="t-hist">
    <div className="cf-panel-head"><h2 id="t-hist" className="cf-h2">Rating history</h2><Link to={`/compare/?teams=${slug}`} className="cf-more">Compare with other teams</Link></div>
    <HistoryChart points={doc.data.points} series={[{ id, name, slot: 1, power: h.power, rank: h.rank }]} height={220} label={`${name} CFPi+ rating by week`} />
    <HistoryNote points={doc.data.points} />
    <details className="cf-details"><summary>Show as a table</summary><HistoryTable points={doc.data.points} series={[{ id, name, slot: 1, power: h.power, rank: h.rank }]} /></details>
  </section>
}

export default function Team({ slug }: { slug: string }) {
  const doc = useData<TeamDoc>(`team/${slug}.json`)
  const directory = useTeams()
  if (directory.size && ![...directory.values()].some(t => t.slug === slug)) return <NotFound />
  return <DataGate source={doc} label="Team">{({ meta, team, summary: s, schedule, record_dist, resume, seed_dist, playoff, leaders }) => {
    const played = schedule.filter(g => g.status === 'final')
    const upcoming = schedule.filter(g => g.status === 'scheduled')
    const sims = meta.sim_status === 'available'
    return <>
      <nav className="cf-crumbs" aria-label="Breadcrumb"><Link to="/teams/">Teams</Link><span aria-hidden="true"> / </span><span aria-current="page">{team.team}</span></nav>
      <header className="cf-teamhead" style={{ ['--team' as string]: team.color ?? 'transparent' }}>
        <TeamLogo id={team.team_id} name={team.team} size={72} />
        <div className="cf-teamhead-id">
          <h1>{team.team}</h1>
          <p className="cf-muted">{[team.mascot, team.conference].filter(Boolean).join(' · ')}</p>
        </div>
        <dl className="cf-teamhead-stats">
          <div><dt>CFPi+ rank <span className="cf-dt-note">(predictive)</span></dt><dd className="cf-big">{s.rank ?? '—'}</dd><dd className="cf-small"><Movement change={s.rank_change} compared={meta.movement_compared_to_week} /></dd></div>
          <div><dt>Record</dt><dd className="cf-big cf-num">{s.wins != null ? `${s.wins}–${s.losses}` : '—'}</dd><dd className="cf-small cf-muted">{s.conf_wins == null ? '' : (s.conf_wins + (s.conf_losses ?? 0)) > 0 ? `${s.conf_wins}–${s.conf_losses} conf.` : 'No conf. games yet'}</dd></div>
          <div><dt>Power <Info text="Opponent-adjusted strength in points relative to an average FBS team." label="About power" /></dt><dd className="cf-big"><Num value={s.power} signed /></dd><dd className="cf-small cf-muted">Δ week <Num value={s.rating_change} signed why="No comparable previous week" /></dd></div>
          <div><dt>Offense</dt><dd className="cf-big"><Num value={s.off} signed /></dd><dd className="cf-small cf-muted">{s.off_rank ? `No. ${s.off_rank}` : '—'} of FBS</dd></div>
          <div><dt>Defense <Info text="Points relative to an average FBS defense; lower (more negative) is better." label="About defense" /></dt><dd className="cf-big"><Num value={s.def} signed /></dd><dd className="cf-small cf-muted">{s.def_rank ? `No. ${s.def_rank}` : '—'} of FBS</dd></div>
        </dl>
      </header>
      <Freshness meta={meta} />

      <div className="cf-team-grid">
        <section className="cf-panel" aria-labelledby="t-outlook">
          <h2 id="t-outlook" className="cf-h2">Season outlook</h2>
          {sims && playoff ? <>
            <dl className="cf-kv">
              <div><dt>Projected wins <Info text="Mean regular-season wins across the simulated seasons (conference title games are not simulated; bowls and playoff games are excluded)." label="About projected wins" /></dt><dd><Num value={playoff.proj_wins} /></dd></div>
              <div><dt>Conference title</dt><dd>{team.conference === 'FBS Independents' ? <Missing why="Independent: no conference title" /> : <Pct value={playoff.p_conf} />}</dd></div>
              <div><dt>Make playoff</dt><dd><Pct value={playoff.p_playoff} /></dd></div>
              <div><dt>First-round bye</dt><dd><Pct value={playoff.p_bye} /></dd></div>
              <div><dt>Reach semifinal</dt><dd><Pct value={playoff.p_sf} /></dd></div>
              <div><dt>Win title</dt><dd><Pct value={playoff.p_champ} /></dd></div>
            </dl>
            {record_dist && meta.sim_count && <figure className="cf-dist">
              <figcaption className="cf-h3">Final record <span className="cf-muted cf-small">(share of {meta.sim_count.toLocaleString()} simulations)</span></figcaption>
              <RecordDist rows={record_dist} n={meta.sim_count} current={{ w: s.wins, l: s.losses }} />
            </figure>}
            {seed_dist && playoff.p_playoff > 0 && <p className="cf-small cf-muted">Most likely seed: No. {seed_dist.indexOf(Math.max(...seed_dist)) + 1} ({pctText(Math.max(...seed_dist), 0)}). <Link to="/playoff/">Playoff dashboard</Link></p>}
          </> : <p className="cf-muted">Simulation results are unavailable for this update.</p>}
        </section>

        <section className="cf-panel" aria-labelledby="t-resume">
          <h2 id="t-resume" className="cf-h2">Résumé</h2>
          {resume ? <dl className="cf-kv">
            <div><dt>Résumé rank <Info text={RESUME_INFO} label="About the résumé rank" /></dt><dd className="cf-num">{s.resume_rank ?? '—'} <span className="cf-small cf-muted"><Link to="/rankings/resume/">all</Link></span></dd></div>
            <div><dt>Record</dt><dd className="cf-num">{s.wins != null ? `${s.wins}–${s.losses}` : '—'}</dd></div>
            <div><dt>Strength of record <Info text={SOR_INFO} label="About strength of record" /></dt><dd><Num value={resume.sor} signed digits={2} /> <span className="cf-small cf-muted">{resume.sor_rank ? `No. ${resume.sor_rank}` : ''}</span></dd></div>
            <div><dt>Schedule strength, played <Info text={SOS_INFO} label="About schedule strength" /></dt><dd><Num value={resume.sos_played} signed /> <span className="cf-small cf-muted">{resume.sos_played_rank ? `No. ${resume.sos_played_rank}` : ''}</span></dd></div>
            <div><dt>Schedule strength, full season</dt><dd><Num value={resume.sos_all} signed /> <span className="cf-small cf-muted">{resume.sos_all_rank ? `No. ${resume.sos_all_rank}` : ''}</span></dd></div>
            <div><dt>Schedule strength, remaining</dt><dd><Num value={resume.sos_remaining} signed why="No games remaining" /> <span className="cf-small cf-muted">{resume.sos_remaining_rank ? `No. ${resume.sos_remaining_rank}` : ''}</span></dd></div>
            <div className="cf-kv-wide"><dt>Best win</dt><dd><Notable g={resume.best_win} /></dd></div>
            <div className="cf-kv-wide"><dt>Worst loss</dt><dd><Notable g={resume.worst_loss} /></dd></div>
          </dl> : <p className="cf-muted">Résumé unavailable for this update.</p>}
          <p className="cf-small cf-muted">Best win and worst loss are judged by the opponent’s current CFPi+ rating.</p>
        </section>

        {leaders && <StatLeaders leaders={leaders} />}

        <TeamHistory id={team.team_id} name={team.team} slug={team.slug} />

        <section className="cf-panel" aria-labelledby="t-sched">
          <h2 id="t-sched" className="cf-h2">Schedule</h2>
          {upcoming.length > 0 && <>
            <h3 className="cf-h3">Remaining <Info text={`Projected margin (negative = favored) and ${WINPROB_INFO.charAt(0).toLowerCase()}${WINPROB_INFO.slice(1)} ${QUALITY_INFO}`} label="About projections" /></h3>
            <ol className="cf-sched">{upcoming.map(g => <ScheduleRow key={g.game_id} g={g} id={team.team_id} />)}</ol>
          </>}
          {played.length > 0 && <>
            <h3 className="cf-h3">Results</h3>
            <ol className="cf-sched">{played.map(g => <ScheduleRow key={g.game_id} g={g} id={team.team_id} />)}</ol>
          </>}
          {schedule.length === 0 && <p className="cf-muted">Schedule unavailable.</p>}
          <p className="cf-small cf-muted"><Link to={`/games/?team=${team.slug}`}>All {team.team} games on the Games page</Link></p>
        </section>
      </div>
    </>
  }}</DataGate>
}

