import { useMemo, useState } from 'react'
import { DataGate, Info, PageHead, Segmented, Select, SortTh, sortRows, TeamLink, TeamLogo, useData, useTeams, type Sort } from '../components'
import { PlayerLink } from '../player'
import { navigate, useQueryParam } from '../router'
import { rowsOf, STAR_CHURN_INFO, stars, type DashboardDoc, type PortalDoc, type PortalTeam, type Transfer } from '../recruiting'
import { RecruitingTabs } from './Recruiting'

// Transfer portal (/recruiting/transfers/; docs/website/PLAYER_DATA.md). Rows are CollegeFootballData portal rows
// (247Sports transfer ratings); the team ordering is the CFPi+ Star Churn, a labelled derived metric.

type Tab = 'teams' | 'in' | 'out' | 'position' | 'team'   // 'team': one team's incoming and outgoing together (reached by clicking a team row)
const TABS: { value: Tab; label: string }[] = [{ value: 'teams', label: 'Team Rankings' }, { value: 'in', label: 'Incoming' }, { value: 'out', label: 'Outgoing' }, { value: 'position', label: 'By Position' }]
const GROUP: Record<string, string> = { DUAL: 'QB', PRO: 'QB', APB: 'RB', FB: 'RB', OT: 'OL', IOL: 'OL', OG: 'OL', C: 'OL', DT: 'DL', DE: 'DL', SDE: 'DL', WDE: 'DL', EDGE: 'DL', ILB: 'LB', OLB: 'LB', CB: 'DB', S: 'DB', SAF: 'DB', PK: 'K' }
const group = (p: string | null) => p ? GROUP[p] ?? p : '—'
const ORDER = ['QB', 'RB', 'WR', 'TE', 'OL', 'DL', 'LB', 'DB', 'ATH', 'K', 'P', 'LS']
const SHOW = 100
const signed = (v: number, d: number) => `${v > 0 ? '+' : ''}${v.toFixed(d)}`.replace('-', '−')

export default function Transfers() {
  const dash = useData<DashboardDoc>('recruiting/dashboard.json')
  const [yearParam, setYear] = useQueryParam('year')
  const [tabParam, setTab] = useQueryParam('tab', 'teams')
  const tab = (tabParam === 'team' || TABS.some(t => t.value === tabParam) ? tabParam : 'teams') as Tab
  return <>
    <PageHead title="Transfers" lede="The transfer portal by year from CollegeFootballData, with 247Sports transfer ratings: who came and went for each FBS program, and a CFPi+ Star Churn ranking."><RecruitingTabs active="transfers" /></PageHead>
    <DataGate source={dash} label="Portal years">{d => {
      const latest = d.portal_years[d.portal_years.length - 1]
      const year = d.portal_years.includes(Number(yearParam)) ? Number(yearParam) : latest
      return <>
        <div className="cf-toolbar" style={{ alignItems: 'end', marginTop: 12 }}>
          <Select label="Portal year" value={String(year)} onChange={v => setYear(v === String(latest) ? '' : v)}>{[...d.portal_years].reverse().map(y => <option key={y} value={y}>{y}</option>)}</Select>
          <div style={{ overflowX: 'auto', maxWidth: '100%' }}><Segmented label="View" value={tab} options={TABS} onChange={v => setTab(v)} /></div>
        </div>
        <PortalYear year={year} tab={tab} />
      </>
    }}</DataGate>
  </>
}

function PortalYear({ year, tab }: { year: number; tab: Tab }) {
  const doc = useData<PortalDoc>(`recruiting/portal_${year}.json`)
  const rows = useMemo(() => doc.data ? rowsOf<Transfer>(doc.data) : [], [doc.data])
  return <DataGate source={doc} label="Transfers">{d => {
    const m = d.match, matched = m.destination + m.origin
    return <>
      {tab === 'teams' ? <TeamTable doc={d} /> : tab === 'position' ? <ByPosition rows={rows} /> : <TransferList rows={rows} incoming={tab === 'in'} both={tab === 'team'} />}
      <p className="cf-small cf-muted">
        Portal data: CollegeFootballData; ratings and stars: 247Sports. {d.fbs_rows.toLocaleString()} of {d.rows_total.toLocaleString()} {year} portal entries involve an FBS program and are listed here.
        {' '}The portal data has no player id, so each entry is matched to a CollegeFootballData player by name: on the destination team’s {year} roster ({m.destination.toLocaleString()}), else on the origin team’s {year - 1} roster or box scores ({m.origin.toLocaleString()}).
        {' '}Matched: {matched.toLocaleString()} ({(100 * matched / Math.max(1, d.fbs_rows)).toFixed(1)}%). Not matched, but still listed: {m.ambiguous} ambiguous (two players fit), {m.conflict} conflicting (the two rosters disagree), {m.unmatched} with no fit. A name opens the player card only when it is matched and the player has one on this site.
      </p>
    </>
  }}</DataGate>
}

function TeamTable({ doc }: { doc: PortalDoc }) {
  const teams = useTeams()
  const [conf, setConf] = useQueryParam('conf')
  const [sk, setSk] = useQueryParam('sort')
  const [sd, setSd] = useQueryParam('dir')
  const rows = doc.teams.map(r => Object.fromEntries(doc.team_columns.map((k, i) => [k, r[i]])) as unknown as PortalTeam)
  const val: Record<string, (r: PortalTeam) => number | null> = { in: r => r.in, out: r => r.out, churn: r => r.churn, star2_in: r => r.star2_in, star2_out: r => r.star2_out, star_churn: r => r.star_churn }
  const sort: Sort = { key: val[sk] ? sk : 'star_churn', desc: sd !== 'asc' }   // opens ordered by Star Churn, best first (teams without one last)
  const onSort = (s: Sort) => { setSk(s.key === 'star_churn' ? '' : s.key); setSd(s.desc ? '' : 'asc') }
  const confs = [...new Set(rows.map(r => teams.get(r.team_id)?.conference).filter(Boolean) as string[])].sort()
  const shown = sortRows(rows.filter(r => !conf || teams.get(r.team_id)?.conference === conf), val[sort.key], sort.desc)
  return <>
    <div className="cf-toolbar" style={{ alignItems: 'end' }}>
      <Select label="Conference" value={conf} onChange={setConf}><option value="">All FBS</option>{confs.map(c => <option key={c} value={c}>{c}</option>)}</Select>
    </div>
    <p className="cf-note cf-small"><strong>Modelled, not official.</strong> Teams are ranked by CFPi+ Star Churn (derived): the average stars² of incoming transfers minus that of outgoing ones. CollegeFootballData publishes no transfer team ranking. <Info text={STAR_CHURN_INFO} label="How Star Churn works" /></p>
    <div className="cf-table-wrap"><table className="cf-table">
      <thead><tr>
        <th scope="col" className="cf-th-start">Team</th>
        <SortTh label="In" sortKey="in" sort={sort} onSort={onSort} align="start" style={{ textAlign: 'center' }} info="Players who transferred to this team through the portal (withdrawn entries excluded)." />
        <SortTh label="Out" sortKey="out" sort={sort} onSort={onSort} align="start" style={{ textAlign: 'center' }} info="Players who transferred from this team through the portal (withdrawn entries excluded)." />
        <SortTh label="Churn" sortKey="churn" sort={sort} onSort={onSort} align="start" style={{ textAlign: 'center' }} info="Net volume change: transfers in minus transfers out. Positive (green) means the team added more players than it lost." />
        <SortTh label="Star² In" sortKey="star2_in" sort={sort} onSort={onSort} align="start" style={{ textAlign: 'center' }} className="cf-hide-sm" info="Average stars² of incoming transfers that have a star rating (5★ = 25, 4★ = 16, 3★ = 9, 2★ = 4)." />
        <SortTh label="Star² Out" sortKey="star2_out" sort={sort} onSort={onSort} align="start" style={{ textAlign: 'center' }} className="cf-hide-sm" info="Average stars² of outgoing transfers that have a star rating. Higher means the team is losing higher-rated players on average." />
        <SortTh label="Star Churn" sortKey="star_churn" sort={sort} onSort={onSort} align="start" style={{ textAlign: 'center' }} info={STAR_CHURN_INFO} />
      </tr></thead>
      <tbody>{shown.map(r => <tr key={r.team_id} style={{ cursor: 'pointer' }} title="Show this team’s incoming and outgoing transfers" onClick={e => { if ((e.target as HTMLElement).closest('a')) return; const q = new URLSearchParams(location.search); q.set('tab', 'team'); q.set('team', r.team_id); for (const k of ['conf', 'sort', 'dir']) q.delete(k); navigate(`${location.pathname}?${q}`, { keepScroll: true }) }}>
        <td><TeamLink id={r.team_id} size={22} /></td>
        <td className="cf-num" style={{ textAlign: 'center' }}>{r.in}</td><td className="cf-num" style={{ textAlign: 'center' }}>{r.out}</td>
        <td className="cf-num" style={{ textAlign: 'center', color: r.churn > 0 ? 'var(--cf-up)' : r.churn < 0 ? 'var(--cf-down)' : undefined }}>{signed(r.churn, 0)}</td>
        <td className="cf-num cf-hide-sm" style={{ textAlign: 'center' }}>{r.star2_in == null ? '—' : r.star2_in.toFixed(1)}</td>
        <td className="cf-num cf-hide-sm" style={{ textAlign: 'center' }}>{r.star2_out == null ? '—' : r.star2_out.toFixed(1)}</td>
        <td className="cf-num cf-strong" style={{ textAlign: 'center', color: r.star_churn == null ? undefined : r.star_churn > 0 ? 'var(--cf-up)' : r.star_churn < 0 ? 'var(--cf-down)' : undefined }}>{r.star_churn == null ? '—' : signed(r.star_churn, 1)}</td>
      </tr>)}</tbody>
    </table></div>
  </>
}

const Side = ({ id, other }: { id: string | null; other: string | null }) => {
  const t = useTeams().get(id ?? '')
  return t ? <span className="cf-team"><TeamLogo id={id} name={t.team} size={18} /><span className="cf-team-text"><span className="cf-team-name">{t.abbreviation ?? t.team}</span></span></span>
    : <span className="cf-small">{other ?? <span className="cf-muted">No destination</span>}</span>
}

function TransferList({ rows, incoming, both = false }: { rows: Transfer[]; incoming: boolean; both?: boolean }) {
  const teams = useTeams()
  const [conf, setConf] = useQueryParam('conf')
  const [team, setTeam] = useQueryParam('team')
  const [pos, setPos] = useQueryParam('pos')
  const [minStars, setMinStars] = useQueryParam('stars')
  const [more, setMore] = useState(false)
  const side = (r: Transfer) => incoming ? r.dest_id : r.origin_id
  const pool = rows.filter(r => both ? r.dest_id || r.origin_id : side(r))
  const involves = (r: Transfer, id: string) => r.dest_id === id || r.origin_id === id
  const sides = (r: Transfer) => (both ? [r.dest_id, r.origin_id] : [side(r)]).filter(Boolean) as string[]
  const confs = [...new Set(pool.flatMap(r => sides(r).map(id => teams.get(id)?.conference)).filter(Boolean) as string[])].sort()
  const teamOpts = [...new Set(pool.flatMap(sides))].filter(id => !conf || teams.get(id!)?.conference === conf).sort((a, b) => (teams.get(a!)?.team ?? '').localeCompare(teams.get(b!)?.team ?? '')) as string[]
  const shown = pool.filter(r => (!conf || sides(r).some(id => teams.get(id)?.conference === conf)) && (!team || (both ? involves(r, team) : side(r) === team)) && (!pos || group(r.position) === pos) && (!minStars || (r.stars ?? 0) >= Number(minStars)))
  const list = more ? shown : shown.slice(0, SHOW)
  return <>
    <div className="cf-toolbar" style={{ alignItems: 'end' }}>
      <Select label="Conference" value={conf} onChange={v => { setConf(v); setTeam('') }}><option value="">All FBS</option>{confs.map(c => <option key={c} value={c}>{c}</option>)}</Select>
      <Select label="Team" value={team} onChange={setTeam}><option value="">All</option>{teamOpts.map(id => <option key={id} value={id}>{teams.get(id)?.team ?? id}</option>)}</Select>
      <Select label="Position" value={pos} onChange={setPos}><option value="">All</option>{ORDER.map(g => <option key={g} value={g}>{g}</option>)}</Select>
      <Select label="Stars" value={minStars} onChange={setMinStars}><option value="">Any</option>{[5, 4, 3].map(n => <option key={n} value={n}>{n}{n < 5 ? '+' : ''} ★</option>)}</Select>
      <p className="cf-muted cf-small cf-toolbar-end" style={{ margin: 0, paddingBottom: 8 }} role="status">{shown.length} transfers</p>
    </div>
    {shown.length === 0 ? <div className="cf-state"><p className="cf-state-title">No transfers match</p></div> :
    <div className="cf-table-wrap"><table className="cf-table">
      <thead><tr><th scope="col" className="cf-th-start">Player</th>{both && team && <th scope="col" className="cf-th-start">Direction</th>}<th scope="col" className="cf-th-start">From</th><th scope="col" className="cf-th-start">To</th>
        <th scope="col" className="cf-th-start cf-hide-sm">Stars</th><th scope="col" className="cf-th-end">Rating</th><th scope="col" className="cf-th-end cf-hide-sm">Date</th></tr></thead>
      <tbody>{list.map((r, i) => <tr key={`${r.name}-${r.origin_id ?? r.origin_other}-${i}`}>
        <td><PlayerLink id={r.profile ? r.athlete_id : null}>{r.name}</PlayerLink><span className="cf-muted cf-small"> · {r.position ?? '—'}{r.eligibility === 'Withdrawn' ? ' · withdrew' : ''}{r.match === 'destination' || r.match === 'origin' ? '' : ' · not matched'}</span></td>
        {both && team && <td className="cf-small" style={{ fontWeight: 600, color: r.dest_id === team ? 'var(--cf-up)' : 'var(--cf-down)' }}>{r.dest_id === team ? 'In' : 'Out'}</td>}
        <td><Side id={r.origin_id} other={r.origin_other} /></td><td><Side id={r.dest_id} other={r.dest_other} /></td>
        <td className="cf-nowrap cf-hide-sm">{stars(r.stars)}</td><td className="cf-num cf-td-end">{r.rating?.toFixed(2) ?? '—'}</td><td className="cf-num cf-td-end cf-hide-sm cf-small">{r.date ?? '—'}</td>
      </tr>)}</tbody>
    </table></div>}
    {shown.length > SHOW && <p><button type="button" className="cf-btn" onClick={() => setMore(m => !m)}>{more ? `Show top ${SHOW}` : `Show all ${shown.length}`}</button></p>}
  </>
}

function ByPosition({ rows }: { rows: Transfer[] }) {
  const teams = useTeams()
  const [team, setTeam] = useQueryParam('team')
  const live = rows.filter(r => r.eligibility !== 'Withdrawn')
  const teamOpts = [...new Set(live.flatMap(r => [r.origin_id, r.dest_id]).filter(Boolean) as string[])].sort((a, b) => (teams.get(a)?.team ?? '').localeCompare(teams.get(b)?.team ?? ''))
  const stat = (rs: Transfer[]) => { const rt = rs.map(r => r.rating).filter((v): v is number => v != null); return { n: rs.length, rated: rt.length, avg: rt.length ? rt.reduce((a, b) => a + b, 0) / rt.length : null, blue: rs.filter(r => (r.stars ?? 0) >= 4).length } }
  const groups = ORDER.filter(g => live.some(r => group(r.position) === g))
  return <>
    <div className="cf-toolbar" style={{ alignItems: 'end' }}>
      <Select label="Team" value={team} onChange={setTeam}><option value="">All FBS</option>{teamOpts.map(id => <option key={id} value={id}>{teams.get(id)?.team ?? id}</option>)}</Select>
    </div>
    <div className="cf-table-wrap"><table className="cf-table">
      {team ? <><thead><tr><th scope="col" className="cf-th-start">Position</th><th scope="col" className="cf-th-end">In</th><th scope="col" className="cf-th-end">Out</th><th scope="col" className="cf-th-end">Net</th><th scope="col" className="cf-th-end cf-hide-sm">Avg Rating In</th><th scope="col" className="cf-th-end cf-hide-sm">Avg Rating Out</th></tr></thead>
        <tbody>{groups.map(g => { const i = stat(live.filter(r => r.dest_id === team && group(r.position) === g)), o = stat(live.filter(r => r.origin_id === team && group(r.position) === g))
          return i.n + o.n ? <tr key={g}><td>{g}</td><td className="cf-num cf-td-end">{i.n}</td><td className="cf-num cf-td-end">{o.n}</td><td className="cf-num cf-td-end cf-strong">{i.n - o.n > 0 ? '+' : ''}{i.n - o.n}</td><td className="cf-num cf-td-end cf-hide-sm">{i.avg?.toFixed(3) ?? '—'}</td><td className="cf-num cf-td-end cf-hide-sm">{o.avg?.toFixed(3) ?? '—'}</td></tr> : null })}</tbody></>
      : <><thead><tr><th scope="col" className="cf-th-start">Position</th><th scope="col" className="cf-th-end">Transfers</th><th scope="col" className="cf-th-end">Rated</th><th scope="col" className="cf-th-end">Avg Rating</th><th scope="col" className="cf-th-end">4–5★</th><th scope="col" className="cf-th-end cf-hide-sm">No Destination</th></tr></thead>
        <tbody>{groups.map(g => { const rs = live.filter(r => group(r.position) === g), s = stat(rs)
          return <tr key={g}><td>{g}</td><td className="cf-num cf-td-end">{s.n}</td><td className="cf-num cf-td-end">{s.rated}</td><td className="cf-num cf-td-end">{s.avg?.toFixed(3) ?? '—'}</td><td className="cf-num cf-td-end">{s.blue}</td><td className="cf-num cf-td-end cf-hide-sm">{rs.filter(r => !r.dest_id && !r.dest_other).length}</td></tr> })}</tbody></>}
    </table></div>
    <p className="cf-small cf-muted">Withdrawn entries are left out. Positions are the portal’s (grouped: e.g. EDGE and DT under DL, IOL and OT under OL). {team ? `${teams.get(team)?.team}: transfers in and out by position.` : 'All entries involving an FBS program.'}</p>
  </>
}
