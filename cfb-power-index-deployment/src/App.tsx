import { useEffect, useMemo, useState } from 'react'
import { Activity, ArrowDown, ArrowUp, ArrowUpDown, BarChart3, ChevronLeft, ChevronRight, CircleHelp, Clock3, Download, ExternalLink, Info, Search, Shield, SlidersHorizontal, Target, Trophy, X, Zap } from 'lucide-react'
import type { Dataset, Rating, Simulation, Team } from './data'
import { fetchDataset } from './data'

type Tab = 'ratings' | 'simulations'
type Row = Rating | Simulation
type Column = { key: string; label: string; tip: string; kind?: 'probability' | 'change' | 'text' }
const ratingColumns: Column[] = [
  { key: 'team', label: 'Team', tip: 'FBS membership and team identity from the supplied team metadata.', kind: 'text' },
  { key: 'conference', label: 'Conference', tip: 'Conference affiliation in the season’s source metadata.', kind: 'text' },
  { key: 'power_rating', label: 'Power', tip: 'Opponent-adjusted team strength in points relative to the model’s average FBS team. Offense minus defense; higher power is better.' },
  { key: 'offensive_rating', label: 'Offense', tip: 'Opponent-adjusted offensive strength in points above the model’s FBS average. Higher is better.' },
  { key: 'defensive_rating', label: 'Defense', tip: 'Production-model defensive rating in points. Lower (more negative) is better; power equals offense minus defense.' },
  { key: 'weekly_change', label: 'vs. last week', tip: 'Power rating minus the prior numbered week’s rating. Unavailable when either snapshot or team rating is missing.', kind: 'change' },
  { key: 'preseason_change', label: 'vs. preseason', tip: 'Current power rating minus the same production model’s pre_power baseline. These are rating-point changes, not rank changes.', kind: 'change' },
]
const simulationColumns: Column[] = [
  ...ratingColumns.slice(0, 2),
  { key: 'projected_wins_current', label: 'Proj. wins', tip: 'Mean overall wins from the current simulation. Includes conference championship games according to cfbseedR’s standings rules.' },
  { key: 'projected_wins_preseason', label: 'Preseason wins', tip: 'Mean wins from a saved preseason simulation with the same win-count definition. Never reconstructed using current ratings.' },
  { key: 'vegas_win_total_preseason', label: 'Vegas preseason', tip: 'Separately supplied preseason sportsbook win total. No market data has been inferred.' },
  { key: 'playoff_probability', label: 'Make playoff', tip: 'Fraction of simulated seasons in which the team receives a College Football Playoff seed.', kind: 'probability' },
  { key: 'conference_title_probability', label: 'Win conference', tip: 'Fraction of simulated seasons in which cfbseedR identifies the team as conference champion.', kind: 'probability' },
  { key: 'national_title_probability', label: 'Win national title', tip: 'Fraction of simulated seasons in which the team wins the generated playoff bracket.', kind: 'probability' },
]
const formatDate = (value?: string | null) => value ? new Date(value).toLocaleString('en-US', { month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit', timeZone: 'UTC' }) + ' UTC' : 'Data unavailable'
function Logo({ team, large = false }: { team: Team; large?: boolean }) {
  const [failed, setFailed] = useState(false)
  return <span className={`team-logo ${large ? 'large' : ''}`} aria-hidden="true">{team.logo_url && !failed ? <img src={team.logo_url} alt="" loading="lazy" onError={() => setFailed(true)} /> : <span>{team.team.split(/\s+/).slice(0, 2).map(x => x[0]).join('')}</span>}</span>
}
function Tip({ text }: { text: string }) {
  return <span className="tip"><button className="tip-trigger" aria-label={text} type="button"><CircleHelp size={12} /></button><span role="tooltip">{text}</span></span>
}
function Value({ value, kind }: { value: unknown; kind?: Column['kind'] }) {
  if (typeof value !== 'number' || !Number.isFinite(value)) return <span className="missing" aria-label="Data unavailable" title="Data unavailable">—</span>
  if (kind === 'probability') return <div className="probability"><span>{(value * 100).toFixed(1)}<small>%</small></span><span className="prob-track"><span style={{ width: `${value * 100}%` }} /></span></div>
  if (kind === 'change') return <span className={`movement ${value > 0 ? 'positive' : value < 0 ? 'negative' : 'neutral'}`}>{value > 0 ? <ArrowUp size={12} /> : value < 0 ? <ArrowDown size={12} /> : null}{value > 0 ? '+' : ''}{value.toFixed(1)}</span>
  return <span className="number">{value > 0 ? '+' : ''}{value.toFixed(1)}</span>
}
function App() {
  const [tab, setTab] = useState<Tab>(location.hash === '#simulations' ? 'simulations' : 'ratings')
  const [ratings, setRatings] = useState<Dataset<Rating> | null>(null)
  const [simulations, setSimulations] = useState<Dataset<Simulation> | null>(null)
  const [errors, setErrors] = useState<Partial<Record<Tab, boolean>>>({})
  const [loading, setLoading] = useState(true)
  const [query, setQuery] = useState('')
  const [conference, setConference] = useState('All conferences')
  const [ratedOnly, setRatedOnly] = useState(false)
  const [sort, setSort] = useState({ key: 'power_rating', desc: true })
  const [page, setPage] = useState(0)
  const [retry, setRetry] = useState(0)
  useEffect(() => {
    let active = true
    setLoading(true); setErrors({})
    Promise.allSettled([fetchDataset<Rating>('ratings'), fetchDataset<Simulation>('simulations')]).then(([r, s]) => {
      if (!active) return
      if (r.status === 'fulfilled') setRatings(r.value); else { setRatings(null); setErrors(e => ({ ...e, ratings: true })) }
      if (s.status === 'fulfilled') setSimulations(s.value); else { setSimulations(null); setErrors(e => ({ ...e, simulations: true })) }
      setLoading(false)
    })
    return () => { active = false }
  }, [retry])
  useEffect(() => { const change = () => { if (location.hash === '#simulations') setTab('simulations'); else if (location.hash === '#ratings') setTab('ratings') }; window.addEventListener('hashchange', change); return () => window.removeEventListener('hashchange', change) }, [])
  useEffect(() => { setSort({ key: tab === 'ratings' ? 'power_rating' : 'projected_wins_current', desc: true }); setPage(0); setRatedOnly(false) }, [tab])
  useEffect(() => { setPage(0) }, [query, conference, ratedOnly, sort])
  const data = tab === 'ratings' ? ratings : simulations
  const rows: Row[] = data?.teams ?? []
  const columns = tab === 'ratings' ? ratingColumns : simulationColumns
  const conferences = [...new Set(rows.map(r => r.conference).filter((c): c is string => !!c))].sort()
  const ranked = useMemo(() => [...(ratings?.teams ?? [])].filter(r => r.power_rating !== null).sort((a, b) => b.power_rating! - a.power_rating! || a.team.localeCompare(b.team)), [ratings])
  const ranks = new Map(ranked.map((r, i) => [r.team_id, i + 1]))
  const filtered = rows.filter(row => row.team.toLocaleLowerCase().includes(query.trim().toLocaleLowerCase()) && (conference === 'All conferences' || row.conference === conference) && (!ratedOnly || ('power_rating' in row && row.power_rating !== null))).sort((a, b) => {
    const av = (a as unknown as Record<string, unknown>)[sort.key]; const bv = (b as unknown as Record<string, unknown>)[sort.key]
    if (av == null && bv == null) return a.team.localeCompare(b.team)
    if (av == null) return 1
    if (bv == null) return -1
    const comparison = typeof av === 'number' && typeof bv === 'number' ? av - bv : String(av).localeCompare(String(bv))
    return comparison === 0 ? a.team.localeCompare(b.team) : comparison * (sort.desc ? -1 : 1)
  })
  const maxPage = Math.max(0, Math.ceil(filtered.length / 25) - 1)
  const safePage = Math.min(page, maxPage)
  const visible = filtered.slice(safePage * 25, (safePage + 1) * 25)
  const pickLeader = (key: 'power_rating' | 'offensive_rating' | 'defensive_rating') => [...(ratings?.teams ?? [])].filter(r => r[key] !== null).sort((a, b) => key === 'defensive_rating' ? a[key]! - b[key]! : b[key]! - a[key]!)[0]
  const navigate = (next: Tab) => { location.hash = next; setTab(next) }
  return <>
    <a href="#main" className="skip-link">Skip to dashboard</a>
    <header className="site-header"><div className="header-inner">
      <a className="brand" href="#ratings" onClick={() => navigate('ratings')} aria-label="CFB Power Index home"><span className="brand-icon"><BarChart3 size={23} strokeWidth={2.8} /></span><span>CFB <strong>POWER INDEX</strong><small>COLLEGE FOOTBALL. QUANTIFIED.</small></span></a>
      <div className="header-right"><a href="#methodology">Behind the numbers <ExternalLink size={12} /></a><span className="season-chip"><span />{ratings?.season ?? data?.season ?? '—'} SEASON</span></div>
    </div></header>
    <main id="main" className="shell">
      <section className="hero">
        <div className="hero-copy"><div className="eyebrow"><span className="accent-line" /> THE INDEPENDENT FOOTBALL INDEX</div><h1>Beyond the scoreboard<span>.</span></h1><p>Every team. Every edge. A clearer view of college football<br className="desktop-break" /> through opponent-adjusted ratings and season projections.</p>
          <div className="update-line"><span className="week-tag">{data?.season ?? ratings?.season ?? '—'} · {data?.week != null ? `WEEK ${String(data.week).padStart(2, '0')}` : 'WEEK UNAVAILABLE'}</span><span><Clock3 size={13} /> Last updated: {loading ? 'Loading…' : formatDate(data?.updated_at)}</span></div>
        </div>
        <div className="index-visual" aria-label="Top three available power ratings"><div className="visual-heading"><Activity size={14} /><span>THE TOP OF THE INDEX</span><span>PTS</span></div>{ranked.slice(0, 3).map((r, i) => <div key={r.team_id} className="mini-row"><span className="mini-rank">0{i + 1}</span><span className="mini-name">{r.team}</span><div className="mini-track"><span style={{ width: `${Math.max(3, (r.power_rating! / Math.max(1, ranked[0].power_rating!)) * 100)}%` }} /></div><strong>{r.power_rating?.toFixed(1)}</strong></div>)}{!ranked.length && <p>Data unavailable</p>}<div className="visual-caption">Relative strength. Absolute perspective.</div></div>
      </section>
      <nav className="page-tabs" aria-label="Analytics views"><button onClick={() => navigate('ratings')} aria-current={tab === 'ratings' ? 'page' : undefined} className={tab === 'ratings' ? 'active' : ''}><BarChart3 size={17} />Power Ratings<span className="tab-count">{ratings?.teams.length ?? '—'}</span></button><button onClick={() => navigate('simulations')} aria-current={tab === 'simulations' ? 'page' : undefined} className={tab === 'simulations' ? 'active' : ''}><Target size={17} />Season Simulations</button><span className="tabs-note">INDEPENDENT MODEL · OPEN DATA</span></nav>
      {tab === 'ratings' ? <section className="summary-grid" aria-label="Leaders among available ratings">{([
        ['power_rating', 'Overall leader', Trophy, 'The strongest complete team'],
        ['offensive_rating', 'Highest-rated offense', Zap, 'Setting the offensive standard'],
        ['defensive_rating', 'Highest-rated defense', Shield, 'The model’s top defensive unit'],
      ] as const).map(([key, label, Icon, caption], i) => { const leader = pickLeader(key); return <article className={`summary-card ${i === 0 ? 'featured' : ''}`} key={key}><div className="card-label"><span><Icon size={14} />{label}</span><span>0{i + 1}</span></div>{leader ? <><div className="card-team"><Logo team={leader} large /><div><h2>{leader.team}</h2><span>{leader.conference}</span></div><strong>{leader[key]! > 0 ? '+' : ''}{leader[key]!.toFixed(1)}<small>{key === 'power_rating' ? 'POWER RATING' : key === 'offensive_rating' ? 'OFFENSIVE RATING' : 'DEFENSIVE RATING'}</small></strong></div><div className="card-caption">{caption}<span>Among {ratings?.rated_teams ?? ranked.length} rated teams</span></div></> : <p className="card-empty">{loading ? 'Loading ratings…' : 'Data unavailable'}</p>}</article> })}</section> : <section className="simulation-intro"><div className="simulation-symbol"><Target size={28} /></div><div><div className="eyebrow">A SEASON OF POSSIBILITIES</div><h2>Where could your team finish?</h2><p>Expected wins and postseason odds from the supplied simulation model.</p></div><div className="simulation-count"><strong>{simulations?.simulation_count?.toLocaleString() ?? '—'}</strong><span>SIMULATED SEASONS</span></div></section>}
      <section className="table-panel" aria-labelledby="table-heading">
        <div className="panel-title"><div><h2 id="table-heading">{tab === 'ratings' ? 'FBS Power Ratings' : 'Season Projections'}<span>{data?.season ?? '—'}</span></h2><p>{tab === 'ratings' ? 'Power & offense: higher is better. Defense: lower is better.' : 'Model-based expectations. Probabilities are not guarantees.'}</p></div>{data && <a className="download" href={`${import.meta.env.BASE_URL}data/${tab}.json`} download><Download size={14} /><span>Export JSON</span></a>}</div>
        <div className="filters"><label className="search"><Search size={17} /><span className="sr-only">Search teams</span><input value={query} onChange={e => setQuery(e.target.value)} placeholder="Search teams…" type="search" />{query && <button aria-label="Clear search" onClick={() => setQuery('')}><X size={14} /></button>}</label><label className="conference-filter"><SlidersHorizontal size={15} /><span className="sr-only">Conference</span><select value={conference} onChange={e => setConference(e.target.value)}><option>All conferences</option>{conferences.map(c => <option key={c}>{c}</option>)}</select></label>{tab === 'ratings' && <label className="rated-toggle"><input type="checkbox" checked={ratedOnly} onChange={e => setRatedOnly(e.target.checked)} />Rated teams only</label>}<span className="result-count" aria-live="polite">{filtered.length} teams</span></div>
        {!loading && !errors[tab] && (tab === 'ratings' && ranked.length < rows.length ? <div className="data-notice"><Info size={15} /><span><strong>Partial coverage.</strong> The supplied snapshot has ratings for {ranked.length} of {rows.length} FBS teams. Unrated teams and missing comparisons display — (Data unavailable).</span></div> : tab === 'simulations' && simulations?.status === 'unavailable' ? <div className="data-notice"><Info size={15} /><span><strong>Data unavailable.</strong> No completed simulation output was supplied. Projections and odds will appear after a successful simulation run.</span></div> : null)}
        {loading ? <div className="empty-state" role="status"><Activity size={30} /><h3>Loading the index</h3><p>Reading the latest published snapshots…</p></div> : errors[tab] ? <div className="empty-state" role="alert"><Info size={30} /><h3>Data unavailable</h3><p>This dataset could not be loaded. Please try again.</p><button onClick={() => setRetry(x => x + 1)}>Retry loading</button></div> : <>
          <div className="table-scroll" role="region" aria-label={`${tab === 'ratings' ? 'Power ratings' : 'Season projections'} table, scroll horizontally on smaller screens`} tabIndex={0}><table><caption className="sr-only">{tab === 'ratings' ? 'FBS power ratings; ranks apply only to teams with ratings.' : 'FBS simulation results. A dash means Data unavailable.'}</caption><thead><tr>{tab === 'ratings' && <th className="rank-col" scope="col">RK<Tip text="Rank among teams with available power ratings; this is not a complete national ranking when coverage is partial." /></th>}{columns.map(c => <th scope="col" key={c.key} aria-sort={sort.key === c.key ? sort.desc ? 'descending' : 'ascending' : 'none'} className={`${c.kind === 'text' ? 'text-col' : ''} ${c.key === 'power_rating' ? 'power-col' : ''}`}><div className="th-content"><button onClick={() => setSort(old => ({ key: c.key, desc: old.key === c.key ? !old.desc : c.kind !== 'text' }))}>{c.label}{sort.key === c.key ? sort.desc ? <ArrowDown size={12} /> : <ArrowUp size={12} /> : <ArrowUpDown size={11} className="sort-idle" />}</button><Tip text={c.tip} /></div></th>)}</tr></thead><tbody>{visible.map(row => <tr key={row.team_id} className={'power_rating' in row && row.power_rating === null ? 'unrated-row' : ''}>{tab === 'ratings' && <td className="rank-col"><span className={ranks.get(row.team_id) === 1 ? 'top-rank' : ''}>{ranks.get(row.team_id) ?? '—'}</span></td>}{columns.map(c => <td key={c.key} className={`${c.kind === 'text' ? 'text-col' : ''} ${c.key === 'power_rating' ? 'power-col' : ''}`}>{c.key === 'team' ? <div className="team-cell"><Logo team={row} /><span>{row.team}{'power_rating' in row && row.power_rating === null && <small>Data unavailable</small>}</span></div> : c.key === 'conference' ? <span className="conference-badge">{row.conference ?? '—'}</span> : c.key.includes('wins') || c.key === 'vegas_win_total_preseason' ? <span className="number">{((row as unknown as Record<string, number | null>)[c.key])?.toFixed(1) ?? <span aria-label="Data unavailable">—</span>}</span> : <Value value={(row as unknown as Record<string, unknown>)[c.key]} kind={c.kind} />}</td>)}</tr>)}</tbody></table>{filtered.length === 0 && <div className="empty-state"><Search size={28} /><h3>No teams found</h3><p>Try another team name or conference.</p><button onClick={() => { setQuery(''); setConference('All conferences'); setRatedOnly(false) }}>Reset filters</button></div>}</div>
          <div className="table-footer"><span>Showing <strong>{filtered.length ? safePage * 25 + 1 : 0}–{Math.min((safePage + 1) * 25, filtered.length)}</strong> of {filtered.length} teams</span><span className="movement-legend"><i /> Up <i /> Down <i /> Unchanged</span><div className="pagination"><button aria-label="Previous page" disabled={safePage === 0} onClick={() => setPage(safePage - 1)}><ChevronLeft size={16} /></button><span>{safePage + 1} / {maxPage + 1}</span><button aria-label="Next page" disabled={safePage >= maxPage} onClick={() => setPage(safePage + 1)}><ChevronRight size={16} /></button></div></div>
        </>}
      </section>
      <section id="methodology" className="methodology"><div className="methodology-heading"><span className="method-icon"><Info size={18} /></span><div><h2>Understand the index</h2><p>Context matters as much as the numbers.</p></div></div><div className="method-grid"><article><h3>{tab === 'ratings' ? 'How to read the ratings' : 'Simulation assumptions'}</h3><p>{tab === 'ratings' ? 'Ratings come from run_2026_rankings.R using the frozen vCurrent production model. Power equals offense minus defense. Higher power and offense are better; lower, more negative defensive ratings indicate a better defense.' : simulations?.status === 'available' ? `${simulations.simulation_count?.toLocaleString() ?? 'Unknown count'} simulations. ${simulations.playoff_format ?? 'Playoff format unavailable'}. ${simulations.wins_scope ?? 'Win-count definition unavailable'}.` : 'The supplied script configures 1,000 simulations and a 12-team playoff using 2026 automatic-bid rules and static power rankings. No completed run is available, so these are configured assumptions, not published results.'}</p></article><article><h3>{tab === 'ratings' ? 'Movement & source coverage' : 'Model & update policy'}</h3><p>{tab === 'ratings' ? 'Movement is a change in rating points. Weekly changes require the previous numbered week; preseason changes use the same model’s pre_power baseline. Missing teams are never assigned a zero rating. Leaders reflect available ratings only.' : 'Simulations use vCurrent / EB_features; the ratings tab uses the frozen candidate selected by run_2026_rankings.R. The script assumes normal game margins, 3.0685 points of home advantage, 15.7875 residual SD, and −25 FCS power. Completed results are held fixed. Missing preseason projections and Vegas totals remain unavailable.'}</p></article></div><div className="source-line"><span>Sources: supplied R model outputs · Team metadata & logos via <a href="https://collegefootballdata.com/" target="_blank" rel="noreferrer">CollegeFootballData <ExternalLink size={11} /></a></span><span>{tab === 'simulations' ? `Simulation updated: ${formatDate(simulations?.updated_at)}` : 'Refreshed weekly during the season'}</span></div></section>
      <footer className="site-footer"><span><BarChart3 size={15} /><strong>CFB POWER INDEX</strong><span>Independent college football analytics.</span></span><span>Built on data. Made for Saturdays.</span></footer>
    </main>
  </>
}
export default App
