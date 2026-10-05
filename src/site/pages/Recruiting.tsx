import { useMemo, useState } from 'react'
import { DataGate, Info, PageHead, Segmented, Select, SortTh, sortRows, TeamLink, TeamLogo, useData, useTeams, type Sort } from '../components'
import { PlayerLink } from '../player'
import { Link, navigate, useQueryParam } from '../router'
import '../recruiting.css'
import { ATTRIBUTION, STAR_CHURN_INFO, rating, rowsOf, stars, type ClassDoc, type ClassRow, type DashboardDoc, type HsDoc, type Recruit } from '../recruiting'

// Recruiting (/recruiting/, /recruiting/high-school/; docs/website/PLAYER_DATA.md). Values are CollegeFootballData's
// (247Sports Composite) or counts of its rows made in R; nothing here is a CFPi+ rating.

export function RecruitingTabs({ active }: { active: 'overview' | 'hs' | 'transfers' }) {
  return <nav className="rc-tabs" aria-label="Recruiting section">
    <Link to="/recruiting/" className={active === 'overview' ? 'is-on' : ''} aria-current={active === 'overview' ? 'page' : undefined}>Overview</Link>
    <Link to="/recruiting/high-school/" className={active === 'hs' ? 'is-on' : ''} aria-current={active === 'hs' ? 'page' : undefined}>High School</Link>
    <Link to="/recruiting/transfers/" className={active === 'transfers' ? 'is-on' : ''} aria-current={active === 'transfers' ? 'page' : undefined}>Transfers</Link>
  </nav>
}

const UNRANKED = (y: number) => `CollegeFootballData has no team rankings for the ${y} class yet (it publishes them once the class is ranked), so teams are listed by 4- and 5-star commits, then average rating. That order is not a ranking.`
const Foot = () => <p className="cf-small cf-muted">{ATTRIBUTION} Counts and averages are made from those rows. Commitments carry no dates in the data, and a commitment is not a signing.</p>

const signedN = (v: number) => `${v > 0 ? '+' : ''}${v.toFixed(1)}`.replace('-', '−')
const C = { textAlign: 'center' } as const
const Th = ({ children, center }: { children?: React.ReactNode; center?: boolean }) => <th scope="col" className="cf-th-start" style={center ? C : undefined}>{children}</th>
const Section = ({ id, title, sub, to, link, children }: { id: string; title: string; sub: string; to: string; link: string; children: React.ReactNode }) =>
  <section aria-labelledby={id} className="rc-sec">
    <div className="rc-sec-h"><h2 id={id}>{title}</h2><Link to={to}>{link} →</Link><p>{sub}</p></div>
    {children}
  </section>
const Snap = ({ label, id, big, sub, to }: { label: string; id: string; big: string; sub: string; to: string }) =>
  <div><Link to={to} className="rc-snap-k">{label}</Link><TeamLink id={id} size={26} /><div className="rc-snap-v">{big}</div><div className="rc-snap-s">{sub}</div></div>
const Block = ({ id, title, children, note }: { id?: string; title: React.ReactNode; children: React.ReactNode; note?: React.ReactNode }) =>
  <section className="rc-blk" aria-labelledby={id}><h3 id={id}>{title}</h3>{children}{note && <p className="rc-note">{note}</p>}</section>

export function RecruitingHome() {
  const doc = useData<DashboardDoc>('recruiting/dashboard.json')
  return <>
    <PageHead title="Recruiting" lede="Who is landing the best classes, who won the transfer portal, and whose rosters hold the most recruiting talent."><RecruitingTabs active="overview" /></PageHead>
    <DataGate source={doc} label="Recruiting">{d => {
      const o1 = d.open_top[0], l1 = d.latest_top[0], p1 = d.portal.top[0], t1 = d.talent[0]
      const hs = '/recruiting/high-school/', portalLink = '/recruiting/transfers/'
      return <>
      <div className="rc-snap" role="group" aria-label="Recruiting snapshot">
        {o1 && <Snap label={`Best ${d.open_class} class`} id={o1.team_id} big={`${o1.five + o1.four} blue-chip commits`} sub={`${o1.five} five-star · ${o1.four} four-star · ${o1.commits} total`} to={`${hs}?year=${d.open_class}`} />}
        {l1 && <Snap label={`Top ${d.latest_ranked_class} class`} id={l1.team_id} big={`${l1.points?.toFixed(2) ?? '—'} points`} sub={`${l1.five} five-star · ${l1.four} four-star · ${l1.commits} total`} to={`${hs}?year=${d.latest_ranked_class}`} />}
        {p1 && <Snap label={`${d.portal.year} portal leader`} id={p1.team_id} big={`${signedN(p1.star_churn)} Star Churn`} sub={`${p1.in} in · ${p1.out} out · CFPi+ metric`} to={portalLink} />}
        {t1 && <Snap label={`Top roster talent, ${d.talent_season}`} id={t1.team_id} big={t1.talent.toFixed(1)} sub={`247Sports talent score · CFPi+ rank ${t1.cfpi_rank ?? '—'}`} to={`${hs}?tab=teams`} />}
      </div>

      <Section id="r-hs" title="High School" sub={`The ${d.open_class} class as it fills in, the ${d.latest_ranked_class} final rankings, and the top players in the class.`} to={hs} link="All classes">
        <div className="rc-grid">
          <Block id="r-open" title={`${d.open_class} Class Leaders`} note={<>Not an official ranking: CollegeFootballData has not published {d.open_class} team rankings, so teams are ordered by 4- and 5-star commits, then average rating. <Link to={`${hs}?year=${d.open_class}`}>All teams</Link></>}>
            <table className="cf-table cf-table-compact rc-tbl"><thead><tr><Th center>#</Th><Th>Team</Th><Th center>Commits</Th><Th center>5★</Th><Th center>4★</Th><Th center>Avg</Th></tr></thead>
              <tbody>{d.open_top.map((t, i) => <tr key={t.team_id} style={{ cursor: 'pointer' }} title="Show this team’s recruiting class" onClick={e => { if (!(e.target as HTMLElement).closest('a')) navigate(`${hs}?year=${d.open_class}&tab=commits&team=${t.team_id}`) }}><td className="cf-num" style={C}>{i + 1}</td><td><TeamLink id={t.team_id} size={20} /></td><td className="cf-num" style={C}>{t.commits}</td><td className="cf-num" style={C}>{t.five}</td><td className="cf-num" style={C}>{t.four}</td><td className="cf-num" style={C}>{rating(t.avg_rating)}</td></tr>)}</tbody></table>
          </Block>
          {d.latest_ranked_class && <Block id="r-latest" title={`${d.latest_ranked_class} Final Rankings`} note={<><Link to={`${hs}?year=${d.latest_ranked_class}`}>Full ranking</Link></>}>
            <table className="cf-table cf-table-compact rc-tbl"><thead><tr><Th center>#</Th><Th>Team</Th><Th center>Points</Th><Th center>Commits</Th><Th center>5★ / 4★</Th></tr></thead>
              <tbody>{d.latest_top.map(t => <tr key={t.team_id} style={{ cursor: 'pointer' }} title="Show this team’s recruiting class" onClick={e => { if (!(e.target as HTMLElement).closest('a')) navigate(`${hs}?year=${d.latest_ranked_class}&tab=commits&team=${t.team_id}`) }}><td className="cf-num" style={C}>{t.rank}</td><td><TeamLink id={t.team_id} size={20} /></td><td className="cf-num" style={C}>{t.points?.toFixed(2) ?? '—'}</td><td className="cf-num" style={C}>{t.commits}</td><td className="cf-num" style={C}>{t.five} / {t.four}</td></tr>)}</tbody></table>
          </Block>}
          <div className="rc-wide"><Block id="r-top" title={`Top Players, ${d.open_class}`} note={<>National rank in the class (247Sports Composite). <Link to={`${hs}?year=${d.open_class}&tab=players`}>All {d.open_class} players</Link></>}>
            <table className="cf-table cf-table-compact rc-tbl"><thead><tr><Th center>#</Th><Th>Recruit</Th><Th center>Stars</Th><Th center>Rating</Th><Th center>High School</Th><Th center>Committed</Th></tr></thead>
              <tbody>{d.open_players.map(r => <tr key={r.id}><td className="cf-num" style={C}>{r.ranking ?? '—'}</td><td>{r.name}<span className="cf-muted cf-small"> · {r.position}</span></td><td className="cf-nowrap" style={C}>{stars(r.stars)}</td><td className="cf-num" style={C}>{rating(r.rating)}</td><td className="cf-small" style={C}>{[r.school, r.state].filter(Boolean).join(', ')}</td><td style={C}>{r.team_id ? <TeamLink id={r.team_id} size={20} /> : r.committed_other ?? <span className="cf-muted">Uncommitted</span>}</td></tr>)}</tbody></table>
          </Block></div>
        </div>
      </Section>

      <Section id="r-portal" title={`${d.portal.year} Transfer Portal`} sub="Teams ranked by CFPi+ Star Churn: stars² coming in minus stars² going out. Derived, not an official ranking." to={portalLink} link="All teams and transfers">
        <div className="rc-grid">
          {([['Biggest Gains', d.portal.top], ['Biggest Losses', d.portal.bottom]] as const).map(([label, list]) => <Block key={label} title={<>{label} <Info text={STAR_CHURN_INFO} label="How Star Churn works" /></>}>
            <table className="cf-table cf-table-compact rc-tbl"><thead><tr><Th center>#</Th><Th>Team</Th><Th center>In</Th><Th center>Out</Th><Th center>Star Churn</Th></tr></thead>
              <tbody>{list.map(t => <tr key={t.team_id} style={{ cursor: 'pointer' }} title="Show this team’s incoming and outgoing transfers" onClick={e => { if (!(e.target as HTMLElement).closest('a')) navigate(`${portalLink}?year=${d.portal.year}&tab=team&team=${t.team_id}`) }}><td className="cf-num" style={C}>{t.rank}</td><td><TeamLink id={t.team_id} size={20} /></td><td className="cf-num" style={C}>{t.in}</td><td className="cf-num" style={C}>{t.out}</td><td className="cf-num" style={{ ...C, fontWeight: 600, color: t.star_churn > 0 ? 'var(--cf-up)' : 'var(--cf-down)' }}>{signedN(t.star_churn)}</td></tr>)}</tbody></table>
          </Block>)}
        </div>
      </Section>

      <Section id="r-talent" title={`Roster Talent, ${d.talent_season}`} sub="The 247Sports Team Talent Composite beside this week’s CFPi+ rank. Shown side by side, never combined." to={`${hs}?tab=teams`} link="Team classes">
        <div className="rc-grid">
          {[d.talent.slice(0, Math.ceil(d.talent.length / 2)), d.talent.slice(Math.ceil(d.talent.length / 2))].map((part, k) => <Block key={k} title={k ? 'Talent Rank 16–30' : 'Talent Rank 1–15'}>
            <table className="cf-table cf-table-compact rc-tbl"><thead><tr><Th center>#</Th><Th>Team</Th><Th center>Talent</Th><Th center>CFPi+ Rank</Th></tr></thead>
              <tbody>{part.map(t => <tr key={t.team_id}><td className="cf-num" style={C}>{t.talent_rank}</td><td><TeamLink id={t.team_id} size={20} /></td><td className="cf-num" style={C}>{t.talent.toFixed(1)}</td><td className="cf-num" style={C}>{t.cfpi_rank ?? '—'}</td></tr>)}</tbody></table>
          </Block>)}
        </div>
        <p className="rc-note">Talent measures the recruiting ratings on a roster. A CFPi+ rank much better than the talent rank means a team is winning more than its recruiting alone would suggest.</p>
      </Section>
      <Foot />
    </>}}</DataGate>
  </>
}

type Tab = 'teams' | 'players' | 'commits'
const TABS: { value: Tab; label: string }[] = [{ value: 'teams', label: 'Team Rankings' }, { value: 'players', label: 'Players' }, { value: 'commits', label: 'Commitments' }]
const SHOW = 100

export function HighSchool() {
  const dash = useData<DashboardDoc>('recruiting/dashboard.json')
  const [yearParam, setYear] = useQueryParam('year')
  const [tabParam, setTab] = useQueryParam('tab', 'teams')
  const tab = (TABS.some(t => t.value === tabParam) ? tabParam : 'teams') as Tab
  return <>
    <PageHead title="High School Recruiting" lede="Team class rankings, every rated recruit and where each has committed, by class, from CollegeFootballData (247Sports Composite)."><RecruitingTabs active="hs" /></PageHead>
    <DataGate source={dash} label="Recruiting classes">{d => {
      const year = d.classes.includes(Number(yearParam)) ? Number(yearParam) : d.open_class
      return <>
        <div className="cf-toolbar" style={{ alignItems: 'end', marginTop: 12 }}>
          <Select label="Class" value={String(year)} onChange={v => setYear(v === String(d.open_class) ? '' : v)}>{[...d.classes].reverse().map(y => <option key={y} value={y}>{y}{y === d.open_class ? ' (in progress)' : ''}</option>)}</Select>
          <Segmented label="View" value={tab} options={TABS} onChange={v => setTab(v)} />
        </div>
        {tab === 'teams' ? <ClassTable year={year} /> : <RecruitList year={year} committedOnly={tab === 'commits'} />}
        <Foot />
      </>
    }}</DataGate>
  </>
}

function ClassTable({ year }: { year: number }) {
  const doc = useData<ClassDoc>(`recruiting/teams_${year}.json`)
  const teams = useTeams()
  const [conf, setConf] = useQueryParam('conf')
  const [sk, setSk] = useQueryParam('sort')
  const [sd, setSd] = useQueryParam('dir')
  return <DataGate source={doc} label="Team classes">{d => {
    const rows = rowsOf<ClassRow>(d).map((r, i) => ({ ...r, order: i + 1 }))
    const confs = [...new Set(rows.map(r => teams.get(r.team_id)?.conference).filter(Boolean) as string[])].sort()
    const val: Record<string, (r: ClassRow & { order: number }) => number | null> = { order: r => -r.order, points: r => r.points, commits: r => r.commits, five: r => r.five, four: r => r.four, three: r => r.three, avg: r => r.avg_rating }
    const sort: Sort = { key: val[sk] ? sk : 'order', desc: sd !== 'asc' }
    const shown = sortRows(rows.filter(r => !conf || teams.get(r.team_id)?.conference === conf), val[sort.key], sort.desc)
    const onSort = (s: Sort) => { setSk(s.key === 'order' ? '' : s.key); setSd(s.desc ? '' : 'asc') }
    return <>
      <div className="cf-toolbar" style={{ alignItems: 'end' }}>
        <Select label="Conference" value={conf} onChange={setConf}><option value="">All FBS</option>{confs.map(c => <option key={c} value={c}>{c}</option>)}</Select>
      </div>
      {!d.ranked && <p className="cf-note cf-small">{UNRANKED(year)}</p>}
      <div className="cf-table-wrap"><table className="cf-table">
        <thead><tr>
          <SortTh label={d.ranked ? 'Rank' : '#'} sortKey="order" sort={sort} onSort={onSort} align="start" info={d.ranked ? 'CollegeFootballData team class ranking (247Sports Composite), among all programs.' : 'Order in this list (not a ranking).'} />
          <th scope="col" className="cf-th-start">Team</th>
          {d.ranked && <SortTh label="Points" sortKey="points" sort={sort} onSort={onSort} info="CollegeFootballData team class points (247Sports Composite)." />}
          <SortTh label="Commits" sortKey="commits" sort={sort} onSort={onSort} />
          <SortTh label="5★" sortKey="five" sort={sort} onSort={onSort} />
          <SortTh label="4★" sortKey="four" sort={sort} onSort={onSort} />
          <SortTh label="3★" sortKey="three" sort={sort} onSort={onSort} className="cf-hide-sm" />
          <SortTh label="Avg Rating" sortKey="avg" sort={sort} onSort={onSort} className="cf-hide-sm" info="Average 247Sports Composite rating of the team’s rated commits in this class." />
        </tr></thead>
        <tbody>{shown.map(r => <tr key={r.team_id} className="cf-row-click" style={{ cursor: 'pointer' }} title="Show this team’s recruiting class" onClick={e => { if ((e.target as HTMLElement).closest('a')) return; const q = new URLSearchParams(location.search); q.set('tab', 'commits'); q.set('team', r.team_id); q.delete('conf'); q.delete('sort'); q.delete('dir'); navigate(`${location.pathname}?${q}`, { keepScroll: true }) }}>
          <td className="cf-num">{d.ranked ? r.rank ?? '—' : r.order}</td><td><TeamLink id={r.team_id} size={22} /></td>
          {d.ranked && <td className="cf-num cf-td-end">{r.points?.toFixed(2) ?? '—'}</td>}
          <td className="cf-num cf-td-end">{r.commits}</td><td className="cf-num cf-td-end">{r.five}</td><td className="cf-num cf-td-end">{r.four}</td>
          <td className="cf-num cf-td-end cf-hide-sm">{r.three}</td><td className="cf-num cf-td-end cf-hide-sm">{rating(r.avg_rating)}</td>
        </tr>)}</tbody>
      </table></div>
      <p className="cf-small cf-muted">FBS programs only. Commit counts are this class’s recruits whose commitment is the team, so a program’s total can differ from its signed class.</p>
    </>
  }}</DataGate>
}

const GROUPS: Record<string, string> = { QB: 'QB', RB: 'RB', APB: 'RB', WR: 'WR', TE: 'TE', OT: 'OL', IOL: 'OL', OL: 'OL', OG: 'OL', OC: 'OL', DL: 'DL', DT: 'DL', SDE: 'DL', WDE: 'DL', EDGE: 'DL', LB: 'LB', ILB: 'LB', OLB: 'LB', CB: 'DB', S: 'DB', DB: 'DB', ATH: 'ATH', K: 'K', P: 'P', LS: 'LS' }
const ORDER = ['QB', 'RB', 'WR', 'TE', 'OL', 'DL', 'LB', 'DB', 'ATH', 'K', 'P', 'LS']

/** ESPN headshot for a recruit who has reached college (profile id = athlete id); a plain circle when there is none, so rows stay aligned. */
function Face({ id }: { id: string | null }) {
  const [broken, setBroken] = useState(false)
  if (!id || broken) return <span aria-hidden="true" style={{ width: 32, height: 32, borderRadius: '50%', background: 'var(--cf-fill-2)', flex: 'none', display: 'inline-block' }} />
  return <img src={`https://a.espncdn.com/i/headshots/college-football/players/full/${id}.png`} alt="" loading="lazy" decoding="async" width={32} height={32}
    style={{ width: 32, height: 32, borderRadius: '50%', objectFit: 'cover', objectPosition: 'top', background: 'var(--cf-fill-2)', flex: 'none' }} onError={() => setBroken(true)} />
}

function RecruitList({ year, committedOnly }: { year: number; committedOnly: boolean }) {
  const doc = useData<HsDoc>(`recruiting/hs_${year}.json`)
  const teams = useTeams()
  const [conf, setConf] = useQueryParam('conf')
  const [team, setTeam] = useQueryParam('team')
  const [pos, setPos] = useQueryParam('pos')
  const [st, setSt] = useQueryParam('state')
  const [minStars, setMinStars] = useQueryParam('stars')
  const [commit, setCommit] = useQueryParam('commit')
  const [more, setMore] = useState(false)
  const all = useMemo(() => doc.data ? rowsOf<Recruit>(doc.data) : [], [doc.data])
  // Rank within the same listed position in this class (by national rank), computed from the rows.
  const posRank = useMemo(() => {
    const m = new Map<string, number>(), n = new Map<string, number>()
    for (const r of [...all].filter(x => x.ranking != null && x.position).sort((a, b) => a.ranking! - b.ranking!)) { const k = (n.get(r.position!) ?? 0) + 1; n.set(r.position!, k); m.set(r.id, k) }
    return m
  }, [all])
  return <DataGate source={doc} label="Recruits">{() => {
    const states = [...new Set(all.map(r => r.state).filter(Boolean) as string[])].sort()
    const confs = [...new Set(all.map(r => r.team_id && teams.get(r.team_id)?.conference).filter(Boolean) as string[])].sort()
    const teamOpts = [...new Set(all.map(r => r.team_id).filter(Boolean) as string[])].filter(id => !conf || teams.get(id)?.conference === conf)
      .sort((a, b) => (teams.get(a)?.team ?? '').localeCompare(teams.get(b)?.team ?? ''))
    const shown = all.filter(r => (!committedOnly || r.team_id) && (!pos || GROUPS[r.position ?? ''] === pos) && (!st || r.state === st)
      && (!minStars || (r.stars ?? 0) >= Number(minStars)) && (committedOnly || !commit || (commit === 'no' ? !r.team_id && !r.committed_other : !!(r.team_id || r.committed_other)))
      && (!conf || (r.team_id && teams.get(r.team_id)?.conference === conf)) && (!team || r.team_id === team))
    const list = more ? shown : shown.slice(0, SHOW)
    const groupCounts = team ? ORDER.map(g => [g, shown.filter(r => GROUPS[r.position ?? ''] === g).length] as const).filter(([, n]) => n > 0) : []
    return <>
      <div className="cf-toolbar" style={{ alignItems: 'end' }}>
        <Select label="Conference" value={conf} onChange={v => { setConf(v); setTeam('') }}><option value="">All</option>{confs.map(c => <option key={c} value={c}>{c}</option>)}</Select>
        <Select label="Team" value={team} onChange={setTeam}><option value="">All</option>{teamOpts.map(id => <option key={id} value={id}>{teams.get(id)?.team ?? id}</option>)}</Select>
        <Select label="Position" value={pos} onChange={setPos}><option value="">All</option>{ORDER.map(g => <option key={g} value={g}>{g}</option>)}</Select>
        <Select label="State" value={st} onChange={setSt}><option value="">All</option>{states.map(s => <option key={s} value={s}>{s}</option>)}</Select>
        <Select label="Stars" value={minStars} onChange={setMinStars}><option value="">Any</option>{[5, 4, 3].map(n => <option key={n} value={n}>{n}{n < 5 ? '+' : ''} ★</option>)}</Select>
        {!committedOnly && <Select label="Commitment" value={commit} onChange={setCommit}><option value="">Any</option><option value="yes">Committed</option><option value="no">Uncommitted</option></Select>}
        <p className="cf-muted cf-small cf-toolbar-end" style={{ margin: 0, paddingBottom: 8 }} role="status">{shown.length} recruits</p>
      </div>
      {groupCounts.length > 0 && <p className="cf-small" style={{ margin: '14px 0 16px' }}>{teams.get(team)?.team} {year} commits by position: {groupCounts.map(([g, n]) => `${g} ${n}`).join(' · ')}</p>}
      {shown.length === 0 ? <div className="cf-state"><p className="cf-state-title">No recruits match</p></div> :
      <div className="cf-table-wrap"><table className="cf-table">
        <thead><tr><th scope="col" className="cf-th-start" style={{ textAlign: 'center' }}>Rank</th><th scope="col" className="cf-th-start">Recruit</th><th scope="col" className="cf-th-start cf-hide-sm">Stars</th>
          <th scope="col" className="cf-th-start" style={{ textAlign: 'center' }}>Rating</th><th scope="col" className="cf-th-start cf-hide-sm">High School</th><th scope="col" className="cf-th-start">Committed</th></tr></thead>
        <tbody>{list.map(r => {
          const t = r.team_id ? teams.get(r.team_id) : null
          const inches = r.height ? Math.round(r.height) : 0
          const size = [inches ? `${Math.floor(inches / 12)}′${inches % 12}″` : null, r.weight ? `${r.weight} lb` : null].filter(Boolean).join(', ')
          return <tr key={r.id}>
            <td className="cf-num" style={{ textAlign: 'center' }}>{r.ranking ?? '—'}{posRank.get(r.id) != null && <span className="cf-muted cf-small"> ({posRank.get(r.id)})</span>}</td>
            <td><span className="cf-team"><Face id={r.profile_id} /><span className="cf-team-text"><span><PlayerLink id={r.profile_id} className="" style={{ textDecoration: 'none' }}>{r.name}</PlayerLink><span className="cf-muted cf-small"> · {[r.position, size].filter(Boolean).join(' · ')}</span></span></span></span></td>
            <td className="cf-nowrap cf-hide-sm">{stars(r.stars)}</td><td className="cf-num" style={{ textAlign: 'center' }}>{rating(r.rating)}</td>
            <td className="cf-hide-sm cf-small">{[r.school, r.state].filter(Boolean).join(', ')}</td>
            <td>{t ? <span className="cf-team"><TeamLogo id={r.team_id} name={t.team} size={20} /><span className="cf-team-text"><span className="cf-team-name">{t.abbreviation ?? t.team}</span></span></span> : r.committed_other ?? <span className="cf-muted">Uncommitted</span>}</td>
          </tr>
        })}</tbody>
      </table></div>}
      {shown.length > SHOW && <p><button type="button" className="cf-btn" onClick={() => setMore(m => !m)}>{more ? `Show top ${SHOW}` : `Show all ${shown.length}`}</button></p>}
      <p className="cf-small cf-muted">Rank: national rank in the class, with the rank among the same listed position in grey. Unrated recruits (no stars in the composite) are listed last. A name opens the player card when the recruit has one on this site.</p>
    </>
  }}</DataGate>
}
