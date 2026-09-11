import { useEffect, useMemo, useState } from 'react'
import { ArrowDown, ArrowUp, ArrowUpDown, Calculator, Clock3, Info, Search } from 'lucide-react'
import type { Dataset, Rating } from './data'
import { compareValues, difference, favoredSide, impliedSpread, lineLabel, signedPoints, valueSide } from './betting'
import './betting.css'

type Game = {
  game_id: string; week: number; season_type: string; kickoff: string | null; time_tbd: boolean;
  away_team_id: string; away_team: string; home_team_id: string; home_team: string;
  neutral_site: boolean | null; market_spread: number | null; market_provider: string | null;
  market_retrieved_at: string | null; market_updated_at: string | null;
}
type BettingData = {
  schema_version: number; season: number; week: number | null; updated_at: string;
  hfa: number | null; ratings_updated_at: string | null; schedule_updated_at: string | null;
  schedule_status: string; market_source: string; market_status: string; market_retrieved_at: string | null;
  games: Game[];
}
type Analyzed = Game & { away_rating: number | null; home_rating: number | null; model: number | null; delta: number | null; absolute: number | null; favored: string; value: string; site: string; matchup: string }
type SortKey = 'kickoff' | 'matchup' | 'away_team' | 'home_team' | 'site' | 'away_rating' | 'home_rating' | 'model' | 'market_spread' | 'delta' | 'absolute' | 'favored' | 'value'
const columns: {key: SortKey; label: string; explanation: string}[] = [
  {key:'kickoff',label:'Kickoff',explanation:'Scheduled kickoff in your local time zone. TBD times are explicitly labeled.'},
  {key:'away_team',label:'Away team',explanation:'Designated away team.'},
  {key:'home_team',label:'Home team',explanation:'Designated home team, including at neutral venues.'},
  {key:'site',label:'Site',explanation:'HFA applies only at a known home site.'},
  {key:'away_rating',label:'Away power',explanation:'Current production power rating; missing ratings are not replaced with zero.'},
  {key:'home_rating',label:'Home power',explanation:'Current production power rating.'},
  {key:'model',label:'Model line',explanation:'Home-team handicap = away power − home power − HFA (zero HFA at a neutral site).'},
  {key:'market_spread',label:'Market line',explanation:'One actual sportsbook quote, normalized to the same home-team perspective.'},
  {key:'delta',label:'Signed Δ',explanation:'Model line − market line. Negative: potential home value. Positive: potential away value.'},
  {key:'absolute',label:'Absolute Δ',explanation:'Absolute model-versus-market difference in points; default largest first.'},
  {key:'favored',label:'Model favors',explanation:'The outright favorite according to the power ratings and venue.'},
  {key:'value',label:'Potential value',explanation:'Side with the more favorable market handicap relative to this model. Not a win probability or guaranteed edge.'},
]
const date = (value: string | null | undefined) => value ? new Date(value).toLocaleString(undefined,{month:'short',day:'numeric',hour:'numeric',minute:'2-digit',timeZoneName:'short'}) : 'Data unavailable'
const number = (value: number | null) => value === null ? '—' : value.toFixed(1)

export default function BettingAnalysis({ratings}: {ratings: Dataset<Rating> | null}) {
  const [data,setData] = useState<BettingData | null>(null)
  const [loading,setLoading] = useState(true)
  const [error,setError] = useState(false)
  const [retry,setRetry] = useState(0)
  const [query,setQuery] = useState('')
  const [sort,setSort] = useState<{key: SortKey; desc: boolean}>({key:'absolute',desc:true})
  const [awayId,setAwayId] = useState('')
  const [homeId,setHomeId] = useState('')
  const [neutral,setNeutral] = useState(false)
  useEffect(() => {
    let alive = true
    setLoading(true); setError(false)
    fetch(`${import.meta.env.BASE_URL}data/betting.json`).then(r => { if (!r.ok) throw new Error('Unavailable'); return r.json() }).then((body: BettingData) => {
      if (body.schema_version !== 1 || !Array.isArray(body.games) || (body.hfa !== null && !Number.isFinite(body.hfa)) || !Number.isInteger(body.season)) throw new Error('Invalid data')
      const ids = new Set<string>()
      for (const g of body.games) {
        if (typeof g.game_id !== 'string' || ids.has(g.game_id) || typeof g.home_team !== 'string' || typeof g.away_team !== 'string' ||
            (g.market_spread !== null && !Number.isFinite(g.market_spread)) ||
            (g.neutral_site !== null && typeof g.neutral_site !== 'boolean')) throw new Error('Invalid game')
        ids.add(g.game_id)
      }
      if (alive) setData(body)
    }).catch(() => { if (alive) {setError(true);setData(null)} }).finally(() => { if (alive) setLoading(false) })
    return () => {alive=false}
  },[retry])
  const teams = useMemo(() => [...(ratings?.teams ?? [])].sort((a,b) => a.team.localeCompare(b.team)),[ratings])
  const byId = useMemo(() => new Map(teams.map(t => [t.team_id,t])),[teams])
  // HFA belongs to a specific rating snapshot. Do not mix partial deployments.
  const compatible = !!ratings && !!data && ratings.season === data.season && ratings.updated_at === data.ratings_updated_at
  const hfa = compatible ? data.hfa : null
  const away = byId.get(awayId); const home = byId.get(homeId)
  const duplicate = awayId !== '' && awayId === homeId
  const calculated = !duplicate && away && home ? impliedSpread(away.power_rating,home.power_rating,neutral,hfa) : null
  const now = Date.now()
  const rows: Analyzed[] = (data?.games ?? []).filter(g => {
    if (!g.kickoff) return true
    if (g.time_tbd && new Date(g.kickoff).toDateString() === new Date().toDateString()) return true
    return Date.parse(g.kickoff) > now
  }).map(g => {
    const away_rating = compatible ? byId.get(g.away_team_id)?.power_rating ?? null : null
    const home_rating = compatible ? byId.get(g.home_team_id)?.power_rating ?? null : null
    const model = impliedSpread(away_rating,home_rating,g.neutral_site,hfa)
    const delta = difference(model,g.market_spread)
    return {...g,away_rating,home_rating,model,delta,absolute:delta === null ? null : Math.abs(delta),
      favored:favoredSide(g.home_team,g.away_team,model),value:valueSide(g.home_team,g.away_team,delta),
      site:g.neutral_site === null ? 'Data unavailable' : g.neutral_site ? 'Neutral Site' : 'Home Site',matchup:`${g.away_team} at ${g.home_team}`}
  }).filter(g => g.matchup.toLowerCase().includes(query.toLowerCase())).sort((a,b) => compareValues(a[sort.key],b[sort.key],sort.desc) || a.game_id.localeCompare(b.game_id))
  const stale = data?.market_retrieved_at && now-Date.parse(data.market_retrieved_at) > 24*60*60*1000
  const renderCell = (g: Analyzed,key: SortKey) => {
    if (key === 'kickoff') return g.time_tbd ? `${g.kickoff ? new Date(g.kickoff).toLocaleDateString() : 'Date unavailable'} · Time TBD` : date(g.kickoff)
    if (key === 'model') return <span className="bet-model">{lineLabel(g.home_team,g.model)}</span>
    if (key === 'market_spread') return <div>{lineLabel(g.home_team,g.market_spread)}<small className="bet-quote">{g.market_provider ?? 'No quote'}{g.market_retrieved_at && <> · Retrieved {date(g.market_retrieved_at)}</>}</small></div>
    if (key === 'delta') return <span className={g.delta === null ? 'missing' : g.delta < 0 ? 'bet-home-edge' : 'bet-away-edge'}>{g.delta === null ? '—' : signedPoints(g.delta)}</span>
    if (key === 'absolute' || key === 'away_rating' || key === 'home_rating') return <span title={g[key] === null ? 'Data unavailable' : undefined}>{number(g[key])}</span>
    return g[key]
  }
  return <div className="betting-view">
    <section className="line-calculator" aria-labelledby="calculator-title">
      <div className="calculator-heading"><span className="method-icon"><Calculator size={22}/></span><div><div className="eyebrow">PUT THE MATCHUP IN PERSPECTIVE</div><h2 id="calculator-title">Custom implied-line calculator</h2><p>Choose two teams. Let the ratings set the line.</p></div></div>
      <div className="calculator-grid"><label>Away team<select aria-label="Calculator away team" value={awayId} onChange={e => setAwayId(e.target.value)}><option value="">Select away team</option>{teams.map(t => <option key={t.team_id} value={t.team_id} disabled={t.team_id === homeId}>{t.team}</option>)}</select></label><label>Home team<select aria-label="Calculator home team" value={homeId} onChange={e => setHomeId(e.target.value)}><option value="">Select home team</option>{teams.map(t => <option key={t.team_id} value={t.team_id} disabled={t.team_id === awayId}>{t.team}</option>)}</select></label><label>Venue<select aria-label="Calculator venue" value={neutral ? 'neutral' : 'home'} onChange={e => setNeutral(e.target.value==='neutral')}><option value="home">Home Site</option><option value="neutral">Neutral Site</option></select></label></div>
      <div className="calculator-result" aria-live="polite"><div><span className="eyebrow">MODEL LINE · HOME PERSPECTIVE</span><strong>{duplicate ? 'Choose two different teams' : home && away ? lineLabel(home.team,calculated) : 'Select a matchup'}</strong><p>{home && away && calculated !== null ? `Model favors: ${favoredSide(home.team,away.team,calculated)}` : 'Both teams need an available power rating.'}</p></div><div className="hfa-detail"><span>{neutral ? 'Neutral site · No HFA applied' : hfa === null ? 'HFA unavailable' : `${hfa.toFixed(4)} points of HFA applied to home team`}</span><small>Ratings updated: {date(ratings?.updated_at)}</small></div></div>
    </section>
    <section className="table-panel" aria-labelledby="betting-heading"><div className="panel-title"><div><h2 id="betting-heading">Upcoming Week Matchups <span>{data?.season ?? ratings?.season ?? '—'} · {data?.week != null ? `WEEK ${data.week}` : 'WEEK UNAVAILABLE'}</span></h2><p>Largest model–market discrepancies first. All lines use the designated home team.</p></div></div>
      <div className="filters"><label className="search"><Search size={16}/><span className="sr-only">Search matchups</span><input aria-label="Search matchups" value={query} onChange={e => setQuery(e.target.value)} placeholder="Search teams or matchups…"/></label><label className="conference-filter">Sort by<select aria-label="Sort matchups" value={sort.key} onChange={e => setSort({key:e.target.value as SortKey,desc:!['kickoff','matchup','away_team','home_team','site','favored','value'].includes(e.target.value)})}><option value="matchup">Matchup</option>{columns.map(c => <option key={c.key} value={c.key}>{c.label}</option>)}</select></label><span className="result-count" aria-live="polite">{rows.length} games</span></div>
      <div className="data-notice"><Info size={15}/><span>Model − market: <strong>negative = potential home value; positive = potential away value.</strong> Missing ratings or lines stay unavailable. Model lines and differences are rounded to 0.1 points for display only.</span></div>
      {!compatible && !loading && <div className="data-notice">Ratings/HFA snapshot unavailable or out of sync. Refresh the page after the next data publication.</div>}
      {loading ? <div className="empty-state" role="status">Loading matchup analysis…</div> : error ? <div className="empty-state" role="alert"><h3>Data unavailable</h3><p>The matchup dataset could not be loaded.</p><button onClick={() => setRetry(r=>r+1)}>Retry matchup data</button></div> : <div className="table-scroll" role="region" aria-label="Betting matchup table, scroll horizontally" tabIndex={0}><table className="betting-table"><caption className="sr-only">Upcoming matchups, home-perspective spreads, and signed model minus market differences</caption><thead><tr>{columns.map(c => <th scope="col" key={c.key} aria-sort={sort.key===c.key ? sort.desc ? 'descending' : 'ascending' : 'none'}><div className="th-content"><button title={c.explanation} onClick={() => setSort({key:c.key,desc:sort.key===c.key ? !sort.desc : !['kickoff','away_team','home_team','site','favored','value'].includes(c.key)})}>{c.label}{sort.key===c.key ? sort.desc ? <ArrowDown size={12}/> : <ArrowUp size={12}/> : <ArrowUpDown size={11}/>}</button></div></th>)}</tr></thead><tbody>{rows.map(g => <tr key={g.game_id}>{columns.map(c => <td key={c.key}>{renderCell(g,c.key)}</td>)}</tr>)}</tbody></table>{rows.length===0 && <div className="empty-state"><h3>{query ? 'No matching games' : 'No upcoming games in this snapshot'}</h3><p>{query ? 'Try another team name.' : 'The schedule will update on the next weekly or manual refresh.'}</p></div>}</div>}
      <div className="betting-sources"><p><Clock3 size={13}/><strong>{data?.market_source ?? 'CollegeFootballData'}</strong></p><p>{data?.market_status ?? 'Market data unavailable.'} {stale && <strong>Snapshot is over 24 hours old.</strong>}</p><p>Last retrieved: {date(data?.market_retrieved_at)} · Sportsbook update time: unavailable (not supplied by the source).</p><p>Schedule as of: {date(data?.schedule_updated_at)} · {data?.schedule_status}. Lines are published snapshots, not a live feed.</p></div>
    </section>
    <section className="methodology" id="methodology"><h2>How the lines work</h2><div className="method-grid"><article><h3>One convention, throughout</h3><p>Home line = away power − home power − home-field advantage. Neutral games use zero HFA. A negative line means the home team is favored. The calculator and table use the same function and the production model’s HFA setting. Games involving a team without a production rating retain their schedule and market line but have no model line.</p></article><article><h3>Reading the discrepancy</h3><p>Signed Δ = model home line − market home line. For example, a model line of home −7.0 against a market line of home −3.0 gives Δ −4.0, pointing to the home side. This is a rating discrepancy, not a calibrated expected return. One sportsbook quote is chosen per game; its name appears beside the line. The next provider week with future games is selected at export time.</p></article></div></section>
  </div>
}
