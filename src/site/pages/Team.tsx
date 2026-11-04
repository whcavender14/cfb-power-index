import '../team.css'
import { STAT_GROUPS, StatRow, statValue } from '../stats'
import { teamTheme } from '../teamTheme'
import { lazy, Suspense, useEffect, useMemo, type ReactNode } from 'react'
const DepthChartSection = lazy(() => import('../DepthChart'))
const RecruitingCard = lazy(() => import('../RecruitingCard'))
import { RESUME_INFO } from './Resume'
import { Bump, DataGate, Freshness, Info, InView, Missing, Movement, Num, Pct, pctText, TeamLink, TeamLogo, useData, useTeams } from '../components'
import NotFound from './NotFound'
import { PlayerLink } from '../player'
import type { ConferencesDoc, EfficiencyDoc, Game, HistoryDoc, IndexDoc, Leader, Leaders, NotableGame, PlayoffTeam, RecordCount, ScenarioDoc, Resume, TeamDoc, TeamMeta } from '../data'
import HistoryChart, { HistoryNote, HistoryTable } from '../HistoryChart'
import { kickoffText, phi, projection, QUALITY_INFO, qualityText, WINPROB_INFO } from '../games'
import { Link, useQueryParam } from '../router'
import { COUNTS_BELOW, decode, formatPicks, parsePicks, scenarioResults, WARN_BELOW, type Pick } from '../scenario'
import { Share } from '../ScenarioShare'

const LOC = { home: ['', 'Home'], away: ['@', 'Away'], neutral: ['N', 'Neutral site'] } as const

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

type OppRanks = Map<string, { rank: number | null; off_rank: number | null; def_rank: number | null; power: number | null }>
/** Strength of record counts each game as (win - the chance a benchmark team would win it); null when the opponent has no published rating (FCS). */
type BenchOdds = (g: Game, teamId: string) => number | null
const sorText = (v: number) => `${v > 0 ? '+' : v < 0 ? '−' : ''}${Math.abs(v).toFixed(2)}`
const shortDate = (g: Game) => new Date(g.kickoff).toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' })
/** Win probability as a tinted cell: green above a coin flip, red below, deeper the further from 50%. */
const probTint = (p: number) => ({ background: `color-mix(in srgb, var(${p >= 0.5 ? '--cf-up' : '--cf-down'}) ${Math.round(10 + 50 * Math.min(1, Math.abs(p - 0.5) * 2))}%, var(--cf-surface))` })

function ScheduleRow({ g, id, ranks, pb, pick, picked }: { g: Game; id: string; ranks: OppRanks; pb: BenchOdds; pick?: ReactNode; picked?: 'win' | 'loss' | null }) {
  const home = g.home_id === id
  const oppId = home ? g.away_id : g.home_id
  const oppName = home ? g.away_team : g.home_team
  const oppFbs = home ? g.away_fbs : g.home_fbs
  const loc = LOC[g.neutral ? 'neutral' : home ? 'home' : 'away']
  const r = oppFbs ? ranks.get(oppId) : undefined
  const rk = (n: number | null | undefined) => <td className="cf-num cf-sched-rk cf-hide-sm">{n ?? <span className="cf-muted">—</span>}</td>
  const final = g.status === 'final'
  const bench = pb(g, id)
  let result: ReactNode = <Missing />, prob: number | null = null, sor: ReactNode = null
  if (final) {
    const us = home ? g.home_points! : g.away_points!, them = home ? g.away_points! : g.home_points!
    const won = us > them
    result = <span className={`cf-pill ${won ? 'is-w' : 'is-l'}`}><b>{won ? 'W' : 'L'}</b> <span className="cf-num">{us}–{them}</span></span>
    if (bench != null) { const v = (won ? 1 : 0) - bench; sor = <b className={`cf-num ${v >= 0 ? 'is-up' : 'is-down'}`}>{sorText(v)}</b> }
  } else {
    // A What If? pick narrows the cell to that outcome: W shows only the gain, L only the loss.
    if (bench != null) sor = <span className="cf-sor">{picked !== 'loss' && <b className="is-up">{sorText(1 - bench)}</b>}{picked !== 'win' && <b className="is-down">{sorText(-bench)}</b>}</span>
    const p = projection(g)
    if (p) {
      const ours = p.favoriteId === id
      prob = g.win_prob_home == null ? null : home ? g.win_prob_home : 1 - g.win_prob_home
      result = <span className="cf-num">{p.margin < 0.05 ? 'Even' : `${ours ? '−' : '+'}${p.margin.toFixed(1)}`}</span>
    }
  }
  return <tr className={`cf-sched-row${final ? ' is-final' : ''}`}>
    <td className="cf-num cf-muted cf-sched-wk cf-hide-sm">{g.week}</td>
    <td className="cf-sched-loc" title={loc[1]}><span aria-hidden="true">{loc[0]}</span><span className="cf-sr">{loc[1]}</span></td>
    <td className="cf-sched-opp"><TeamLink id={oppId} name={oppName} size={26} sub={[final ? shortDate(g) : kickoffText(g), oppFbs ? null : 'FCS'].filter(Boolean).join(' · ')} /></td>
    {rk(r?.rank)}{rk(r?.off_rank)}{rk(r?.def_rank)}
    <td className="cf-sched-res">{result}</td>
    <td className="cf-sched-prob">{prob != null && <span className="cf-num cf-prob" style={probTint(prob)}>{pctText(prob, 0)}</span>}</td>
    <td className="cf-num cf-sched-q cf-hide-sm">{!final && (g.quality != null ? <span className="cf-num cf-prob" style={teamTint(g.quality / 10)}>{qualityText(g.quality)}</span> : <span className="cf-muted">—</span>)}</td>
    <td className="cf-num cf-sched-sor cf-hide-sm">{sor}</td>
    {pick !== undefined && <td className="cf-sched-pickcell">{pick}</td>}
  </tr>
}

/** The schedule as a table in week order (bye weeks show as gaps in the week numbers). Opponent ranks are today's. */
function ScheduleTable({ schedule, id, ranks, pb, renderPick, pickedOf }: { schedule: Game[]; id: string; ranks: OppRanks; pb: BenchOdds; renderPick?: (g: Game) => ReactNode; pickedOf?: (g: Game) => 'win' | 'loss' | null }) {
  const games = [...schedule].sort((a, b) => a.week - b.week || a.kickoff.localeCompare(b.kickoff))
  return <div className="cf-table-wrap"><table className="cf-table cf-sched-t">
    <caption className="cf-sr">Schedule with results, projected margin, win probability and game quality</caption>
    <thead><tr>
      <th scope="col" className="cf-th-start cf-hide-sm">Wk</th><th scope="col"><span className="cf-sr">Site</span></th><th scope="col" className="cf-th-start">Opponent</th>
      <th scope="col" className="cf-hide-sm" title="Opponent's national rank">Rk</th><th scope="col" className="cf-hide-sm" title="Opponent's offense rank">Off</th><th scope="col" className="cf-hide-sm" title="Opponent's defense rank">Def</th>
      <th scope="col">Result</th><th scope="col">Win %</th><th scope="col" className="cf-hide-sm">Quality</th><th scope="col" className="cf-hide-sm" title="Strength of record: what the game added (played) or would add if won / lost (upcoming)">SOR</th>{renderPick && <th scope="col">What if</th>}
    </tr></thead>
    <tbody>{games.map(g => <ScheduleRow key={g.game_id} g={g} id={id} ranks={ranks} pb={pb} pick={renderPick ? renderPick(g) : undefined} picked={pickedOf?.(g)} />)}</tbody>
  </table></div>
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

/** Chance of at least `n` wins, from a distribution over win counts (index = wins). */
const atLeast = (dist: number[], n: number) => dist.slice(Math.max(0, n)).reduce((t, x) => t + x, 0)
/** A probability as a team-colored tint: the likelier, the deeper (ink flips to the team's contrast color once it is dark). */
const teamTint = (p: number) => ({ background: `color-mix(in srgb, var(--team-a) ${Math.round(8 + 62 * p)}%, var(--cf-surface))`, ...(p > 0.6 ? { color: 'var(--team-ink)' } : null) })

/** One row of "chance to win at least N": a title, the projected record, and one tinted box per threshold. */
function WinOdds({ title, wins, games, odds }: { title: string; wins: number; games: number; odds: { n: number; p: number }[] }) {
  return <div className="cf-wo">
    <div className="cf-wo-h"><span>{title}</span><span className="cf-muted">proj. {wins.toFixed(1)}–{(games - wins).toFixed(1)}</span></div>
    <ol className="cf-wo-row" style={{ gridTemplateColumns: `repeat(${odds.length}, minmax(0, 1fr))` }}>
      {odds.map(o => <li key={o.n}><span className="cf-wo-n">{o.n}+</span><b className="cf-num" style={teamTint(o.p)}>{pctText(o.p, 0)}</b></li>)}
    </ol>
  </div>
}

/** Compact Resume and Outlook cards: strength of record with the best win and worst loss, and the chance of reaching a
 *  few win totals overall and in conference (the conference numbers come from conferences.json, the same simulations). */
function ResumeOutlook({ team, resume, playoff, winsDist, games }: { team: TeamMeta; resume: Resume | null; playoff: PlayoffTeam | null; winsDist: number[] | null; games: number }) {
  const conf = useData<ConferencesDoc>(playoff ? 'conferences.json' : null)
  const st = conf.data?.conferences.find(c => c.name === team.conference)?.standings?.find(x => x.team_id === team.team_id)
  const first = games - 2 > 0 ? Math.max(1, Math.min(Math.floor(playoff?.proj_wins ?? 0), games - 2)) : 1
  const reachable = (o: { n: number; p: number }, i: number) => i === 0 || o.p >= 0.001   // drop totals the team can no longer reach
  const allOdds = winsDist && playoff ? [0, 1, 2].map(i => first + i).filter(n => n <= games).map(n => ({ n, p: atLeast(winsDist, n) })).filter(reachable) : []
  const cFirst = st && st.conf_games > 1 ? Math.max(1, Math.min(Math.ceil(st.avg_wins), st.conf_games - 1)) : 1
  const confOdds = st ? [0, 1].map(i => cFirst + i).filter(n => n <= st.conf_games).map(n => ({ n, p: st.p_ge[n] ?? 0 })).filter(reachable) : []
  if (!resume && !allOdds.length) return null
  return <div className="cf-ol-side">
    {resume && <section className="cf-panel" aria-labelledby="t-rc">
      <h2 id="t-rc" className="cf-h2">Resume</h2>
      <div className="cf-rc-lead">
        <b className={`cf-num ${(resume.sor ?? 0) >= 0 ? 'is-up' : 'is-down'}`}><Num value={resume.sor} signed digits={2} /></b>
        <span><strong>{resume.sor_rank ? `No. ${resume.sor_rank} SOR` : 'SOR'}</strong><small>wins above a No. 60 team <Info text={SOR_INFO} label="About strength of record" /></small></span>
      </div>
      <dl className="cf-rc-best">
        <div><dt>Best win</dt><dd><Notable g={resume.best_win} /></dd></div>
        <div><dt>Worst loss</dt><dd><Notable g={resume.worst_loss} /></dd></div>
      </dl>
      <p className="cf-small cf-muted">Best win and worst loss are judged by the opponent’s current CFPi+ rating.</p>
    </section>}
    {allOdds.length > 0 && <section className="cf-panel" aria-labelledby="t-oc">
      <h2 id="t-oc" className="cf-h2">Outlook</h2>
      <WinOdds title="All games" wins={playoff!.proj_wins} games={games} odds={allOdds} />
      {st && confOdds.length > 0 && <WinOdds title={`${team.conference} games`} wins={st.avg_wins} games={st.conf_games} odds={confOdds} />}
      <p className="cf-small cf-muted">Chance to win at least N games, from the simulated seasons.</p>
    </section>}
  </div>
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
    <InView key={rows.map(r => r.count).join(',')} className="cf-dist-bars cf-rec-bars" role="img" aria-label={bars.map(b => `${b.label}: ${pctText(b.count / n, 1)}`).join(', ')}>
      {bars.map(b => <span key={b.label} className="cf-dist-col" title={`${b.label}: ${b.count.toLocaleString()} of ${n.toLocaleString()} simulations`}>
        <span className="cf-dist-val">{b.count / n >= 0.005 ? `${Math.round((b.count / n) * 100)}%` : '<1%'}</span>
        <i style={{ height: `${(b.count / max) * 100}%` }} />
        <b>{b.label.replace(' or worse', '')}{b.label.endsWith('or worse') ? <small>or worse</small> : null}</b>
      </span>)}
    </InView>
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
        <InView as="dl" key={`${g.id}:${g.defs.map(d => statValue(e, d.key)).join(',')}`} className="cf-eff-rows">{g.defs.map(d => <StatRow key={d.key} d={d} e={e} total={total} />)}</InView>
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
  const index = useData<IndexDoc>('index.json')
  const ranks = useMemo<OppRanks>(() => new Map((index.data?.teams ?? []).map(t => [t.team_id, t])), [index.data])
  // Chance the benchmark team (the No. 60 team, as in the simulation's strength of record) would win this team's game.
  const pb = useMemo<BenchOdds>(() => {
    const bench = (index.data?.teams ?? []).find(t => t.rank === 60)?.power, { hfa, sigma } = index.data?.meta ?? {}
    return (g, id) => {
      const home = g.home_id === id, opp = ranks.get(home ? g.away_id : g.home_id)?.power
      if (bench == null || opp == null || hfa == null || !sigma || !(home ? g.away_fbs : g.home_fbs)) return null
      return phi((bench - opp + hfa * (g.neutral ? 0 : home ? 1 : -1)) / sigma)
    }
  }, [index.data, ranks])
  if (directory.size && ![...directory.values()].some(t => t.slug === slug)) return <NotFound />
  return <DataGate source={doc} label="Team">{({ meta, team, summary: s, schedule, wins_dist, record_dist, resume, seed_dist, playoff, leaders }) => {
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
        <div className="cf-span-all cf-ol-row">
          <section className="cf-panel" aria-labelledby="t-outlook">
            <h2 id="t-outlook" className="cf-h2">Season Outlook</h2>
            {sims && playoff ? <>
              <div className="cf-ol">
                <div className="cf-ol-lead">
                  <div><b className="cf-num"><Num value={playoff.proj_wins} /></b><span>Projected wins <Info text="Mean regular-season wins across the simulated seasons (conference title games are not simulated; bowls and playoff games are excluded)." label="About projected wins" /></span></div>
                  <div><b className="cf-num">{team.conference === 'FBS Independents' ? <Missing why="Independent: no conference title" /> : <Pct value={playoff.p_conf} />}</b><span>Conference title</span></div>
                </div>
                <InView as="ol" key={team.team_id} className="cf-ol-ladder" aria-label="Playoff path odds">{([['Make playoff', playoff.p_playoff], ['First-round bye', playoff.p_bye], ['Reach semifinal', playoff.p_sf], ['Win title', playoff.p_champ]] as const).map(([label, v]) =>
                  <li key={`${team.team_id}:${label}`} ><span>{label}</span><span className="cf-ol-track" aria-hidden="true"><i style={{ width: `${Math.max(0, Math.min(1, v ?? 0)) * 100}%` }} /></span><b className="cf-num"><Pct value={v} /></b></li>)}</InView>
              </div>
              {record_dist && meta.sim_count && <figure className="cf-dist">
                <figcaption className="cf-h3">Final Record <span className="cf-muted cf-small">(share of {meta.sim_count.toLocaleString()} simulations)</span></figcaption>
                <RecordDist rows={record_dist} n={meta.sim_count} current={{ w: s.wins, l: s.losses }} />
              </figure>}
              {seed_dist && playoff.p_playoff > 0 && <p className="cf-small cf-muted">Most likely seed: No. {seed_dist.indexOf(Math.max(...seed_dist)) + 1} ({pctText(Math.max(...seed_dist), 0)}). <Link to="/playoff/">Playoff dashboard</Link></p>}
            </> : <p className="cf-muted">Simulation results are unavailable for this update.</p>}
          </section>
          <ResumeOutlook team={team} resume={resume} playoff={sims ? playoff : null} winsDist={wins_dist} games={schedule.length} />
        </div>

        <section className="cf-panel" aria-labelledby="t-resume">
          <h2 id="t-resume" className="cf-h2">Résumé</h2>
          {resume ? <div className="cf-res">
            <div className="cf-res-tiles">
              <div><b className="cf-num">{s.resume_rank ?? '—'}</b><span>Résumé rank <Info text={RESUME_INFO} label="About the résumé rank" /></span><small><Link to="/rankings/resume/">See all</Link></small></div>
              <div><b className="cf-num">{s.wins != null ? `${s.wins}–${s.losses}` : '—'}</b><span>Record</span><small>{s.conf_wins != null && s.conf_losses != null && s.conf_wins + s.conf_losses > 0 ? `${s.conf_wins}–${s.conf_losses} in conference` : 'No conf. games yet'}</small></div>
              <div><b className="cf-num">{sims && playoff ? `${playoff.proj_wins.toFixed(1)}–${(schedule.length - playoff.proj_wins).toFixed(1)}` : '—'}</b><span>Projected record <Info text="Mean regular-season record across the simulated seasons (conference title games are not simulated; bowls and playoff games are excluded)." label="About the projected record" /></span><small>{sims && playoff ? `${schedule.length} regular-season games` : 'Simulation unavailable'}</small></div>
            </div>
            <div className="cf-res-sec"><h3 className="cf-h3">Schedule strength <Info text={SOS_INFO} label="About schedule strength" /></h3>
              <InView as="dl" key={team.team_id} className="cf-res-sos">{([['Played', resume.sos_played, resume.sos_played_rank], ['Full season', resume.sos_all, resume.sos_all_rank], ['Remaining', resume.sos_remaining, resume.sos_remaining_rank]] as const).map(([label, v, r]) =>
                <div key={label}><dt>{label}</dt><dd className="cf-num"><Num value={v} signed why="No games remaining" /></dd>
                  <span className="cf-bar" aria-hidden="true"><i style={{ width: `${r ? Math.max(4, 100 - (r - 1) / 1.36) : 0}%` }} /></span>
                  <span className="cf-small cf-muted cf-res-rk">{r ? `No. ${r}` : '—'}</span></div>)}</InView>
            </div>
          </div> : <p className="cf-muted">Résumé unavailable for this update.</p>}
        </section>

        <TeamStats id={team.team_id} />

        <TeamHistory id={team.team_id} name={team.team} />

        {leaders && <StatLeaders leaders={leaders} />}

        <Suspense fallback={null}><DepthChartSection slug={team.slug} team={team} /></Suspense>

        <Suspense fallback={null}><RecruitingCard id={team.team_id} /></Suspense>

        <section className="cf-panel cf-sched-panel" aria-labelledby="t-sched">
          <h2 id="t-sched" className="cf-h2">Schedule <Info text={`Rk, Off and Def are the opponent’s current national rank overall, on offense and on defense. Result is the score for played games and the projected margin (negative = favored) for the rest. SOR is what the game added to strength of record (played) or would add if won or lost (upcoming): a win is worth 1 minus the chance a No. 60 team would win it, a loss costs that chance. Win % is the ${WINPROB_INFO.charAt(0).toLowerCase()}${WINPROB_INFO.slice(1)} ${QUALITY_INFO}${whatIf ? ' W / L: pick a result for the What If? panel.' : ''}`} label="About projections" /></h2>
          <div className={whatIf ? 'cf-sched-layout' : undefined}>
          <div className="cf-sched-rem">
          {schedule.length === 0 ? <p className="cf-muted">Schedule unavailable.</p>
            : <ScheduleTable schedule={schedule} id={team.team_id} ranks={ranks} pb={pb}
                pickedOf={g => { const p = picks.find(x => x.gameId === g.game_id); return p ? (p.side === (g.home_id === team.team_id ? 'home' : 'away') ? 'win' : 'loss') : null }}
                renderPick={whatIf ? g => g.status === 'scheduled'
                  ? <PickToggle g={g} id={team.team_id} team={team.team} pick={picks.find(p => p.gameId === g.game_id)} onPick={side => setPick(g, side)} />
                  : null : undefined} />}
          <p className="cf-small cf-muted"><Link to={`/games/?team=${team.slug}`}>All {team.team} games on the Games page</Link></p>
          </div>
          {whatIf && <TeamWhatIf team={team} picks={picks} base={playoff!} nGames={schedule.length} onClear={() => setParam('')} />}
          </div>
        </section>
      </div>
    </div>
  }}</DataGate>
}

