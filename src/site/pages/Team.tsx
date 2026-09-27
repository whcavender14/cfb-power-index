import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { RESUME_INFO } from './Resume'
import { DataGate, fmtSigned, Freshness, Info, Missing, Movement, Num, Pct, pctText, TeamLink, TeamLogo, useData, useTeams } from '../components'
import NotFound from './NotFound'
import type { DepthRow, DepthSeason, UsageDef, UsageDoc, Efficiency, EfficiencyDoc, Game, HistoryDoc, Leader, Leaders, NotableGame, PlayoffTeam, RecordCount, ScenarioDoc, TeamDoc, TeamMeta } from '../data'
import HistoryChart, { HistoryTable } from '../HistoryChart'
import { HistoryNote } from './Compare'
import { kickoffText, projection, Quality, QUALITY_INFO, WINPROB_INFO } from '../games'
import { Link, useQueryParam } from '../router'
import { COUNTS_BELOW, decode, formatPicks, parsePicks, scenarioResults, WARN_BELOW, type Pick } from '../scenario'
import { Share } from '../ScenarioShare'
import { PlayerLink } from '../player'

const LOC = { home: ['H', 'Home'], away: ['A', 'Away'], neutral: ['N', 'Neutral site'] } as const

/** One schedule row: opponent logo and name (linked for FBS teams; a monogram placeholder for teams without a logo),
 *  site (home / away / neutral), then the result or the forecast with this team's win probability. */
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

/** This team's odds in the simulated seasons where every pick happened (same filter as the What if? page; nothing is
 *  re-simulated). Scenario data loads only once a pick exists. */
function TeamWhatIf({ team, picks, games, base, nGames, onClear }: { team: TeamMeta; picks: Pick[]; games: Game[]; base: PlayoffTeam; nGames: number; onClear: () => void }) {
  const scen = useData<ScenarioDoc>(picks.length ? 'scenario.json' : null)
  const decoded = useMemo(() => scen.data ? decode(scen.data) : null, [scen.data])
  const indep = team.conference === 'FBS Independents'
  const byId = new Map(games.map(g => [g.game_id, g]))
  const baseLosses = nGames - base.proj_wins
  const published = <dl className="cf-kv cf-wi-kv">
    <div><dt>Make playoff</dt><dd><Pct value={base.p_playoff} /></dd></div>
    <div><dt>First-round bye</dt><dd><Pct value={base.p_bye} /></dd></div>
    <div><dt>Conference title</dt><dd>{indep ? <Missing why="Independent: no conference title" /> : <Pct value={base.p_conf} />}</dd></div>
    <div><dt>Expected record</dt><dd className="cf-num">{base.proj_wins.toFixed(1)}–{baseLosses.toFixed(1)}</dd></div>
  </dl>
  const link = `/whatif/?pick=${formatPicks(picks)}`
  return <aside className="cf-wi" aria-labelledby="t-whatif">
    <div className="cf-panel-head"><h3 id="t-whatif" className="cf-h3">What if?</h3>{picks.length > 0 && <button type="button" className="cf-btn cf-btn-sm" onClick={onClear}>Clear picks</button>}</div>
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
        <ul className="cf-chips cf-wi-chips">{valid.map(p => { const g = byId.get(p.gameId); if (!g) return null
          const won = (p.side === 'home') === (g.home_id === team.team_id); const opp = g.home_id === team.team_id ? g.away_team : g.home_team
          return <li key={p.gameId} className="cf-chip">{won ? 'Beat' : 'Lose to'} {opp} <span className="cf-muted">(Wk {g.week})</span></li> })}</ul>
        <p className={`cf-whatif-status${n < WARN_BELOW ? ' is-warn' : ''}`} role="status"><strong className="cf-num">{n.toLocaleString()}</strong> of {d.n.toLocaleString()} simulated seasons match.
          {n === 0 ? ' This combination never happened in the simulations. Remove a pick.'
            : n < COUNTS_BELOW ? ` Too few seasons for percentages (fewer than ${COUNTS_BELOW}); counts are shown instead. Treat them as anecdotes.`
            : n < WARN_BELOW ? ` Fewer than ${WARN_BELOW} seasons: a 50% figure could be off by about 10 points either way. Read changes loosely.` : ''}
          <Info text={`Each pick keeps only the simulated seasons in which that result happened; nothing is re-simulated and no rating changes. Below ${WARN_BELOW} matching seasons a warning appears; below ${COUNTS_BELOW} only counts are shown.`} label="About matching seasons" /></p>
        {r && n > 0 && <dl className="cf-kv cf-wi-kv">
          <div><dt>Make playoff</dt><dd><Share k={r.playoff} n={n} base={base.p_playoff} /></dd></div>
          <div><dt>First-round bye</dt><dd><Share k={r.bye} n={n} base={base.p_bye} /></dd></div>
          <div><dt>Conference title</dt><dd>{indep ? <Missing why="Independent: no conference title" /> : <Share k={r.conf} n={n} base={base.p_conf} />}</dd></div>
          <div><dt>Expected record</dt><dd className="cf-num">{(r.wins / n).toFixed(1)}–{(games - r.wins / n).toFixed(1)}<Delta now={r.wins / n} base={base.proj_wins} /></dd></div>
        </dl>}
        <p className="cf-small cf-muted">▲▼ = change from the published odds (percentage points; wins for the record). <Link to={link}>Open these picks on the What if? page</Link> to add other games and see every team.</p>
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
  return <section className="cf-panel cf-span-all" aria-labelledby="t-leaders">
    <h2 id="t-leaders" className="cf-h2">Statistical leaders <Info text="Season totals from CollegeFootballData through the same week as the ratings. Leaders are picked by fixed rules: passing yards, rushing yards (top 2), receiving yards (top 3), sacks (top 3) and interceptions. They are statistical leaders only; the data does not say who starts." label="About statistical leaders" /></h2>
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

type EffKey = 'sr' | 'net_epa' | 'off_epa' | 'off_rush_epa' | 'off_pass_epa' | 'def_epa' | 'def_rush_epa' | 'def_pass_epa'
const EFF_GROUPS: { title: string; note?: string; rows: [EffKey, string][] }[] = [
  { title: 'Overall', rows: [['net_epa', 'Net EPA/play'], ['sr', 'Success rate']] },
  { title: 'Offense', note: 'EPA gained per play · higher is better', rows: [['off_epa', 'EPA/play'], ['off_rush_epa', 'Rushing'], ['off_pass_epa', 'Passing']] },
  { title: 'Defense', note: 'EPA allowed per play · lower is better', rows: [['def_epa', 'EPA/play allowed'], ['def_rush_epa', 'Rushing'], ['def_pass_epa', 'Passing']] },
]

/** Raw per-play efficiency with FBS ranks. Rank 1 is always best (for defense, the lowest EPA allowed), so the bar
 *  (share of FBS teams ranked below) and its colour mean the same thing on every row. */
function TeamEfficiency({ id }: { id: string }) {
  const doc = useData<EfficiencyDoc>('efficiency.json')
  if (!doc.data) return null
  const e = doc.data.teams.find(t => t.team_id === id)
  if (!e || e.plays == null) return null
  const total = doc.data.teams.filter(t => t.plays != null).length
  const value = (k: EffKey) => k === 'sr' ? (e.sr == null ? null : `${(e.sr * 100).toFixed(1)}%`) : fmtSigned(e[k], 2)
  const rank = (k: EffKey) => e[`${k}_rank` as keyof Efficiency] as number | null
  const m = doc.data.method
  return <section className="cf-panel" aria-labelledby="t-eff">
    <div className="cf-panel-head"><h2 id="t-eff" className="cf-h2">Efficiency <span className="cf-tag">{m.adjusted ? 'Opponent-adjusted' : 'Raw, not opponent-adjusted'}</span></h2></div>
    <div className="cf-eff">
      {EFF_GROUPS.map(g => <div key={g.title} className="cf-eff-group">
        <h3 className="cf-h3">{g.title}{g.note && <span className="cf-eff-note"> · {g.note}</span>}</h3>
        <dl className="cf-eff-rows">{g.rows.map(([k, label]) => { const r = rank(k); const good = r == null ? 0 : (total - r) / (total - 1)
          return <div key={k} className="cf-eff-row">
            <dt>{label}{k === 'sr' && <Info text={`Share of plays that gain enough: ${m.success.toLowerCase()}.`} label="About success rate" />}{k === 'net_epa' && <Info text="Offense EPA per play minus defense EPA per play allowed. EPA = expected points added (CFBD's ppa)." label="About net EPA" />}</dt>
            <dd className="cf-eff-val cf-num">{value(k) ?? <Missing />}</dd>
            <dd className="cf-eff-rank cf-num">{r ? `No. ${r}` : '—'}</dd>
            <dd className="cf-eff-bar" aria-hidden="true"><i className={good >= 2 / 3 ? 'is-good' : good < 1 / 3 ? 'is-bad' : ''} style={{ width: `${Math.max(3, good * 100)}%` }} /></dd>
          </div> })}</dl>
      </div>)}
    </div>
    <p className="cf-small cf-muted cf-eff-foot">Season averages over {m.scope.charAt(0).toLowerCase()}{m.scope.slice(1)}. {m.adjusted ? 'Adjusted for opponent strength.' : 'Not adjusted for opponent strength'}; not used by the CFPi+ rating. Ranks among {total} FBS teams, No. 1 = best; bars fill toward better. <Info text={`${m.plays}. Source: ${m.source}.`} label="Which plays count" /></p>
  </section>
}

const POS_NAMES: Record<string, string> = { QB: 'Quarterbacks', RB: 'Running backs', WR: 'Wide receivers', TE: 'Tight ends', DL: 'Defensive line', LB: 'Linebackers', DB: 'Defensive backs' }
const shortDate = (iso: string | null) => iso ? new Date(iso).toLocaleDateString(undefined, { month: 'short', day: 'numeric' }) : null

const heightText = (h: number | null | undefined) => h ? `${Math.floor(h / 12)}′${h % 12}″` : null
const shortName = (n: string) => { const parts = n.trim().split(/\s+/); return parts.length > 1 ? `${parts[0][0]}. ${parts.slice(1).join(' ')}` : n }

/** One slot in the formation: position label, headshot (initials if the photo fails), name, jersey · height, stat. */
type SlotPlayer = { name: string; athlete_id?: string | null; jersey?: number | null; height?: number | null; headshot?: string | null }
function Slot({ pos, p, stat, next, col, row, lift }: { pos: string; p?: SlotPlayer | null; stat?: string; next?: string; col?: number; row?: number; lift?: boolean }) {
  const [broken, setBroken] = useState(false)
  const initials = p ? p.name.split(/\s+/).map(w => w[0]).slice(0, 2).join('') : 'OL'
  const bits = p ? [p.jersey != null ? `#${p.jersey}` : null, heightText(p.height)].filter(Boolean).join(' · ') : 'No snap data'
  return <div className={`cf-dc-slot${p ? '' : ' is-empty'}${lift ? ' is-lift' : ''}`} style={col ? { gridColumn: col, gridRow: row } : undefined}>
    <span className="cf-dc-pos">{pos}</span>
    <span className="cf-dc-face">{p?.headshot && !broken ? <img src={p.headshot} alt="" loading="lazy" decoding="async" onError={() => setBroken(true)} /> : <span aria-hidden="true">{initials}</span>}</span>
    <span className="cf-dc-name" title={p?.name}>{p ? <PlayerLink id={p.athlete_id}>{shortName(p.name)}</PlayerLink> : '—'}</span>
    <span className="cf-dc-bits cf-num">{bits}</span>
    {stat && <span className="cf-dc-stat cf-num">{stat}</span>}
    {next && <span className="cf-dc-next" title={`Backup: ${next}`}>then {shortName(next)}</span>}
  </div>
}

const nameKey = (n: string) => n.toLowerCase().replace(/[^a-z]/g, '')
/** TWO·DEEP rows carry names only; players who also appear in the usage lists get their athlete id (for the player modal). */
const usageIds = (doc: UsageDoc) => new Map([...Object.values(doc.offense ?? {}), ...Object.values(doc.defense ?? {})].flat().map(p => [nameKey(p.name), p.athlete_id] as [string, string]))

/** A starter's season line: the stat group the player is used in most (passing, then receiving vs rushing, then defense). Blank when there are none. */
function statLine(s?: DepthSeason | null): string | undefined {
  if (!s) return undefined
  const yds = (v: number) => String(v).replace('-', '−')
  if (s.pass_att > 0 && s.pass_att >= s.rush_car) return `${s.pass_cmp}/${s.pass_att} · ${yds(s.pass_yds)} yds · ${s.pass_td} TD`
  if (s.rec > 0 && s.rec >= s.rush_car) return `${s.rec} rec · ${yds(s.rec_yds)} yds · ${s.rec_td} TD`
  if (s.rush_car > 0) return `${s.rush_car} car · ${yds(s.rush_yds)} yds · ${s.rush_td} TD`
  if (s.tkl + s.tfl + s.sacks + s.int + s.pd > 0) return [`${s.tkl} tkl`, s.sacks ? `${s.sacks} sk` : s.tfl ? `${s.tfl} TFL` : null, s.int ? `${s.int} INT` : s.pd ? `${s.pd} PD` : null].filter(Boolean).join(' · ')
  return undefined
}

const NICKEL = /^(NB|NCB|NICK|NICKEL|STAR|HUSKY|MONEY|SPUR|SLOT|DIME)/
/** Formation from TWO·DEEP rows: each team's own slot names; starters placed like a broadcast lineup graphic. */
function TwoDeepChart({ rows, team, ids }: { rows: DepthRow[]; team: TeamMeta; ids: Map<string, string> }) {
  const slot = (r: DepthRow) => <Slot key={`${r.group}-${r.slot}`} pos={r.slot} p={r.players[0] && { ...r.players[0], athlete_id: r.players[0].athlete_id ?? ids.get(nameKey(r.players[0].name)) }} stat={statLine(r.players[0]?.season)} />
  const g = (...names: string[]) => rows.filter(r => names.includes(r.group.split('-')[0].toUpperCase()))
  const ol = ['LT', 'LG', 'C', 'RG', 'RT'].map(k => g('OL').find(r => r.slot === k)).filter(Boolean) as DepthRow[]
  const olRest = g('OL').filter(r => !ol.includes(r))
  const wr = g('WR'), qb = g('QB')
  const tes = g('TE'), te = [...tes.filter(r => /^(Y|TE)$/.test(r.slot)), ...tes.filter(r => !/^(Y|TE)$/.test(r.slot))]   // in-line TE first
  const rbs = g('RB'), backs = [...rbs.slice(0, 1), ...g('FB', 'SB')]   // later RB rows are second-string slots, not formation spots
  const cbs = g('CB'), outside = cbs.filter(r => !NICKEL.test(r.slot)).slice(0, 2), inside = cbs.filter(r => !outside.includes(r))
  const edges = g('EDGE'), dl = g('DL')
  const front = [edges[0], ...dl, ...edges.slice(1, -1), edges.length > 1 ? edges[edges.length - 1] : undefined].filter(Boolean) as DepthRow[]
  const half = Math.ceil(backs.length / 2)
  const hasD = cbs.length + dl.length + edges.length + g('LB').length + g('S').length > 0
  const hasO = qb.length + ol.length + wr.length + backs.length > 0
  const box = useRef<HTMLDivElement>(null)
  useEffect(() => { const el = box.current; if (el && el.scrollWidth > el.clientWidth) el.scrollLeft = (el.scrollWidth - el.clientWidth) / 2 }, [rows])   // phones: open centred
  return <><p className="cf-small cf-muted cf-dc-hint">Swipe to see the whole formation.</p><div className="cf-dc-scroll" ref={box}><div className="cf-dc is-flex" role="img" aria-label={`${team.team} depth chart`}>
    {hasD && <>
      <div className="cf-dc-row">{g('S').map(slot)}</div>
      <div className="cf-dc-row">{inside.map(slot)}{g('LB').map(slot)}</div>
      <div className="cf-dc-row is-wide">{outside[0] && slot(outside[0])}<span className="cf-dc-mid">{front.map(slot)}</span>{outside[1] && slot(outside[1])}</div>
    </>}
    <div className="cf-dc-line"><span><TeamLogo id={team.team_id} name={team.team} size={18} /> Defense</span><i /><span>Offense <TeamLogo id={team.team_id} name={team.team} size={18} /></span></div>
    {hasO && <>
      <div className="cf-dc-row is-wide">
        {wr[0] && slot(wr[0])}
        {wr.length > 2 && <span className="cf-dc-group is-lift">{wr.slice(2).map(slot)}</span>}
        <span className="cf-dc-oline">
          <span className="cf-dc-mid">{[...ol, ...olRest].map(slot)}</span>
          {/* QB lines up behind the center: equal-width sides around it */}
          <span className="cf-dc-backfield"><span>{te.slice(1).map(slot)}{backs.slice(0, half).map(slot)}</span>{qb.slice(0, 1).map(slot)}<span>{backs.slice(half).map(slot)}</span></span>
        </span>
        {te[0] && slot(te[0])}
        {wr[1] && slot(wr[1])}
      </div>
    </>}
  </div></div></>
}

/** Formation graphic from usage (offense) and tackles (defense). Heuristic, not an official depth chart. */
function DepthChart({ doc, team }: { doc: UsageDoc; team: TeamMeta }) {
  const o = doc.offense, d = doc.defense
  const pct = (v: number) => `${Math.round(v * 100)}% of plays`
  const tk = (p?: UsageDef) => p ? `${p.tackles} tkl${p.sacks ? ` · ${p.sacks} sk` : ''}` : undefined
  const wr = o?.WR ?? [], dl = d?.DL ?? [], db = d?.DB ?? [], lb = d?.LB ?? []
  const edge = dl.filter(p => p.roster_pos === 'EDGE'), inside = dl.filter(p => p.roster_pos !== 'EDGE')
  const ends = [...edge, ...inside.slice(2)].slice(0, 2), tackles = [...inside, ...edge.slice(2)].filter(p => !ends.includes(p)).slice(0, 2)
  return <div className="cf-dc-scroll"><div className="cf-dc" role="img" aria-label={`${team.team} depth chart by usage`}>
    {d && <div className="cf-dc-grid">
      <Slot pos="DB" p={db[0]} stat={tk(db[0])} col={3} row={1} /><Slot pos="DB" p={db[1]} stat={tk(db[1])} col={7} row={1} />
      <Slot pos="DB" p={db[4]} stat={tk(db[4])} col={2} row={2} /><Slot pos="LB" p={lb[0]} stat={tk(lb[0])} col={4} row={2} /><Slot pos="LB" p={lb[1]} stat={tk(lb[1])} col={6} row={2} />
      <Slot pos="DB" p={db[2]} stat={tk(db[2])} col={1} row={3} /><Slot pos="DE" p={ends[0]} stat={tk(ends[0])} col={3} row={3} />
      <Slot pos="DT" p={tackles[0]} stat={tk(tackles[0])} col={4} row={3} /><Slot pos="DT" p={tackles[1]} stat={tk(tackles[1])} col={6} row={3} />
      <Slot pos="DE" p={ends[1]} stat={tk(ends[1])} col={7} row={3} /><Slot pos="DB" p={db[3]} stat={tk(db[3])} col={9} row={3} />
    </div>}
    <div className="cf-dc-line"><span><TeamLogo id={team.team_id} name={team.team} size={18} /> Defense</span><i /><span>Offense <TeamLogo id={team.team_id} name={team.team} size={18} /></span></div>
    {o && <div className="cf-dc-grid">
      <Slot pos="WR" p={wr[0]} stat={wr[0] && pct(wr[0].usg_overall)} col={1} row={1} /><Slot pos="WR" p={wr[2]} stat={wr[2] && pct(wr[2].usg_overall)} col={2} row={1} lift />
      {['LT', 'LG', 'C', 'RG', 'RT'].map((pos, i) => <Slot key={pos} pos={pos} p={null} col={3 + i} row={1} />)}
      <Slot pos="TE" p={o.TE[0]} stat={o.TE[0] && pct(o.TE[0].usg_overall)} col={8} row={1} /><Slot pos="WR" p={wr[1]} stat={wr[1] && pct(wr[1].usg_overall)} col={9} row={1} lift />
      <Slot pos="RB" p={o.RB[0]} stat={o.RB[0] && pct(o.RB[0].usg_overall)} col={4} row={2} /><Slot pos="QB" p={o.QB[0]} stat={o.QB[0] && pct(o.QB[0].usg_overall)} col={5} row={2} />
    </div>}
  </div></div>
}

/** Players by usage: who has actually played, by position. Not an official depth chart (CFBD publishes none). */
function PlayersByUsage({ slug, team }: { slug: string; team: TeamMeta }) {
  const doc = useData<UsageDoc>(`usage/${slug}.json`)
  if (!doc.data) return null
  const { offense, defense, offense_pulled_at, defense_through_week } = doc.data
  const pct = (v: number) => `${(v * 100).toFixed(1)}%`
  return <section className="cf-panel cf-span-all" aria-labelledby="t-usage">
    <div className="cf-panel-head"><h2 id="t-usage" className="cf-h2">Depth chart {!doc.data.depth?.length && <span className="cf-tag">By usage</span>} <Info text="Not an official depth chart; none is published in the data. Offense: share of the team’s plays on which the player was the passer, rusher or target (CFBD player usage). Defense: total tackles, then tackles for loss, sacks, interceptions and passes defended. Offensive linemen and special teams are not listed: the data has no snap counts." label="About players by usage" /></h2></div>
    {doc.data.depth?.length ? <TwoDeepChart rows={doc.data.depth} team={team} ids={usageIds(doc.data)} /> : <DepthChart doc={doc.data} team={team} />}
    <details className="cf-details"><summary>All players by usage</summary>
    <div className="cf-usage">
      {offense && <div className="cf-usage-side">
        <h3 className="cf-h3">Offense <span className="cf-eff-note">· share of team plays</span></h3>
        {(['QB', 'RB', 'WR', 'TE'] as const).map(g => offense[g]?.length ? <div key={g} className="cf-usage-group">
          <h4 className="cf-usage-pos">{POS_NAMES[g]}</h4>
          <ol className="cf-usage-list">{offense[g].map(p => <li key={p.athlete_id} className="cf-usage-row">
            <span className="cf-usage-name"><PlayerLink id={p.athlete_id}>{p.name}</PlayerLink></span>
            <span className="cf-usage-bar" aria-hidden="true"><i style={{ width: `${Math.min(100, p.usg_overall / 0.6 * 100)}%` }} /></span>
            <span className="cf-num cf-usage-val">{pct(p.usg_overall)}</span>
            <span className="cf-num cf-usage-sub cf-muted">{g === 'QB' ? `pass ${pct(p.usg_pass)}` : g === 'RB' ? `rush ${pct(p.usg_rush)}` : `targets ${pct(p.usg_pass)}`}</span>
          </li>)}</ol>
        </div> : null)}
      </div>}
      {defense && <div className="cf-usage-side">
        <h3 className="cf-h3">Defense <span className="cf-eff-note">· tackles · TFL · sacks · INT · PD</span></h3>
        {(['DL', 'LB', 'DB'] as const).map(g => defense[g]?.length ? <div key={g} className="cf-usage-group">
          <h4 className="cf-usage-pos">{POS_NAMES[g]}</h4>
          <ol className="cf-usage-list">{defense[g].map(p => <li key={p.athlete_id} className="cf-usage-row is-def">
            <span className="cf-usage-name"><PlayerLink id={p.athlete_id}>{p.name}</PlayerLink>{p.position ? <span className="cf-muted"> · {p.position}</span> : null}</span>
            <span className="cf-num cf-usage-val">{p.tackles}</span>
            <span className="cf-num cf-usage-sub cf-muted">{p.tfl} · {p.sacks} · {p.int} · {p.pd}</span>
          </li>)}</ol>
        </div> : null)}
      </div>}
    </div>
    <p className="cf-small cf-muted">Offense: share of team plays, season to date{offense_pulled_at ? ` (as of ${shortDate(offense_pulled_at)})` : ''}, so it can include games after the ratings week. Defense: {defense_through_week ? `Weeks 1–${defense_through_week}` : 'season to date'}. Source: CollegeFootballData.</p>
    </details>
    {doc.data.depth?.length && doc.data.depth_source
      ? <p className="cf-small cf-muted">Starters from <a href={doc.data.depth_source.url} target="_blank" rel="noreferrer">{doc.data.depth_source.name}</a>{doc.data.depth_source.fetched_at ? `, as of ${shortDate(doc.data.depth_source.fetched_at)}` : ''}, used with permission; slot names are the team’s own. Stat lines are CollegeFootballData box-score totals, regular season to date; blank where the player has none (offensive linemen). Photos and heights via CollegeFootballData roster.</p>
      : <p className="cf-small cf-muted">Not an official depth chart: offense is the most-used player at each spot, defense the leading tacklers (DB spots are not split into corners and safeties, which the data does not distinguish). Offensive line: no snap data{doc.data.ol_on_roster ? ` (${doc.data.ol_on_roster} on the roster)` : ''}. Photos via CollegeFootballData roster.</p>}

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
  const [param, setParam] = useQueryParam('pick')
  const directory = useTeams()
  if (directory.size && ![...directory.values()].some(t => t.slug === slug)) return <NotFound />
  return <DataGate source={doc} label="Team">{({ meta, team, summary: s, schedule, record_dist, resume, seed_dist, playoff, leaders }) => {
    const played = schedule.filter(g => g.status === 'final')
    const upcoming = schedule.filter(g => g.status === 'scheduled')
    const sims = meta.sim_status === 'available'
    const upcomingIds = new Set(upcoming.map(g => g.game_id))
    const picks = parsePicks(param).filter(p => upcomingIds.has(p.gameId))   // this team's remaining games only
    const setPick = (g: Game, side: 'home' | 'away' | null) => setParam(formatPicks([...picks.filter(p => p.gameId !== g.game_id), ...(side ? [{ gameId: g.game_id, side }] : [])]))
    const whatIf = sims && playoff && upcoming.length > 0
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


        <TeamEfficiency id={team.team_id} />

        <section className="cf-panel" aria-labelledby="t-resume">
          <h2 id="t-resume" className="cf-h2">Résumé</h2>
          {resume ? <dl className="cf-kv cf-kv-2">
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

        <TeamHistory id={team.team_id} name={team.team} slug={team.slug} />

        {leaders && <StatLeaders leaders={leaders} />}

        <PlayersByUsage slug={team.slug} team={team} />

        <section className="cf-panel cf-sched-panel" aria-labelledby="t-sched">
          <h2 id="t-sched" className="cf-h2">Schedule</h2>
          <div className={whatIf ? 'cf-sched-layout' : undefined}>
          <div className="cf-sched-rem">
          {upcoming.length > 0 && <>
            <h3 className="cf-h3">Remaining <Info text={`Projected margin (negative = favored) and ${WINPROB_INFO.charAt(0).toLowerCase()}${WINPROB_INFO.slice(1)} ${QUALITY_INFO}${whatIf ? ' W / L: pick a result for the What if? panel.' : ''}`} label="About projections" /></h3>
            <ol className="cf-sched">{upcoming.map(g => <ScheduleRow key={g.game_id} g={g} id={team.team_id}
              pick={whatIf ? <PickToggle g={g} id={team.team_id} team={team.team} pick={picks.find(p => p.gameId === g.game_id)} onPick={side => setPick(g, side)} /> : undefined} />)}</ol>
          </>}
          </div>
          {whatIf && <TeamWhatIf team={team} picks={picks} games={upcoming} base={playoff!} nGames={schedule.length} onClear={() => setParam('')} />}
          <div className="cf-sched-res">
          {played.length > 0 && <>
            <h3 className="cf-h3">Results</h3>
            <ol className="cf-sched">{played.map(g => <ScheduleRow key={g.game_id} g={g} id={team.team_id} pick={whatIf ? <span className="cf-sched-pick" aria-hidden="true" /> : undefined} />)}</ol>
          </>}
          {schedule.length === 0 && <p className="cf-muted">Schedule unavailable.</p>}
          <p className="cf-small cf-muted"><Link to={`/games/?team=${team.slug}`}>All {team.team} games on the Games page</Link></p>
          </div>
          </div>
        </section>
      </div>
    </>
  }}</DataGate>
}

