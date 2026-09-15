import { useEffect, useMemo, useState } from 'react'
import { ArrowDown, ArrowUp, FileDown, Search, X } from 'lucide-react'
import type { Dataset, Rating } from './data'
import { compareValues, difference, favoriteLine, favoredSide, impliedSpread, lineLabel, signedPoints, valueLine, valueSide } from './betting'
import { formatLocal, formatUpdated, minus, num, signed, weekSlug } from './format'
import { toCsv } from './csv'
import { downloadCsv } from './download'
import { EmptyState, Kicker, Notice, SectionHead, SelectField, StatCell, TeamLogo } from './ui'
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
const fields: { key: SortKey; label: string; explanation: string }[] = [
  { key: 'absolute', label: 'Largest difference', explanation: 'Absolute model-versus-market difference in points; default largest first.' },
  { key: 'kickoff', label: 'Kickoff', explanation: 'Scheduled kickoff in your local time zone. TBD times are explicitly labeled.' },
  { key: 'delta', label: 'Signed Δ', explanation: 'Model line − market line. Negative: potential home value. Positive: potential away value.' },
  { key: 'model', label: 'Model line', explanation: 'Home-team handicap = away power − home power − HFA (zero HFA at a neutral site).' },
  { key: 'market_spread', label: 'Market line', explanation: 'One actual sportsbook quote, normalized to the same home-team perspective.' },
  { key: 'matchup', label: 'Matchup', explanation: 'Away team at home team.' },
  { key: 'away_team', label: 'Away team', explanation: 'Designated away team.' },
  { key: 'home_team', label: 'Home team', explanation: 'Designated home team, including at neutral venues.' },
  { key: 'away_rating', label: 'Away power', explanation: 'Current production power rating; missing ratings are not replaced with zero.' },
  { key: 'home_rating', label: 'Home power', explanation: 'Current production power rating.' },
  { key: 'site', label: 'Site', explanation: 'HFA applies only at a known home site.' },
  { key: 'favored', label: 'Model favors', explanation: 'The outright favorite according to the power ratings and venue.' },
  { key: 'value', label: 'Potential value', explanation: 'Side with the more favorable market handicap relative to this model. Not a win probability or guaranteed edge.' },
]
const textKeys: SortKey[] = ['kickoff', 'matchup', 'away_team', 'home_team', 'site', 'favored', 'value']
const display = (text: string) => text === 'Data unavailable' ? '—' : minus(text)
const dayLabel = (g: Game) => g.kickoff ? new Date(g.kickoff).toLocaleDateString(undefined, { weekday: 'long', month: 'long', day: 'numeric' }) : 'Date unavailable'

export default function BettingAnalysis({ ratings }: { ratings: Dataset<Rating> | null }) {
  const [data, setData] = useState<BettingData | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(false)
  const [retry, setRetry] = useState(0)
  const [query, setQuery] = useState('')
  const [sort, setSort] = useState<{ key: SortKey; desc: boolean }>({ key: 'kickoff', desc: false })
  const [awayId, setAwayId] = useState('')
  const [homeId, setHomeId] = useState('')
  const [neutral, setNeutral] = useState(false)
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
    }).catch(() => { if (alive) { setError(true); setData(null) } }).finally(() => { if (alive) setLoading(false) })
    return () => { alive = false }
  }, [retry])
  const teams = useMemo(() => [...(ratings?.teams ?? [])].sort((a, b) => a.team.localeCompare(b.team)), [ratings])
  const byId = useMemo(() => new Map(teams.map(t => [t.team_id, t])), [teams])
  // HFA belongs to a specific rating snapshot. Do not mix partial deployments.
  const compatible = !!ratings && !!data && ratings.season === data.season && ratings.updated_at === data.ratings_updated_at
  const hfa = compatible ? data.hfa : null
  const away = byId.get(awayId); const home = byId.get(homeId)
  const duplicate = awayId !== '' && awayId === homeId
  const calculated = !duplicate && away && home ? impliedSpread(away.power_rating, home.power_rating, neutral, hfa) : null
  const now = Date.now()
  const upcoming: Analyzed[] = (data?.games ?? []).filter(g => {
    if (!g.kickoff) return true
    if (g.time_tbd && new Date(g.kickoff).toDateString() === new Date().toDateString()) return true
    return Date.parse(g.kickoff) > now
  }).map(g => {
    const away_rating = compatible ? byId.get(g.away_team_id)?.power_rating ?? null : null
    const home_rating = compatible ? byId.get(g.home_team_id)?.power_rating ?? null : null
    const model = impliedSpread(away_rating, home_rating, g.neutral_site, hfa)
    const delta = difference(model, g.market_spread)
    return { ...g, away_rating, home_rating, model, delta, absolute: delta === null ? null : Math.abs(delta),
      favored: favoredSide(g.home_team, g.away_team, model), value: valueSide(g.home_team, g.away_team, delta),
      site: g.neutral_site === null ? 'Data unavailable' : g.neutral_site ? 'Neutral Site' : 'Home Site', matchup: `${g.away_team} at ${g.home_team}` }
  })
  const rows = upcoming.filter(g => g.matchup.toLowerCase().includes(query.toLowerCase())).sort((a, b) => compareValues(a[sort.key], b[sort.key], sort.desc) || a.game_id.localeCompare(b.game_id))
  const stale = data?.market_retrieved_at && now - Date.parse(data.market_retrieved_at) > 24 * 60 * 60 * 1000

  // Day headings only make sense while the board is in kickoff order.
  const groups: { label: string | null; games: Analyzed[] }[] = []
  for (const g of rows) {
    const label = sort.key === 'kickoff' ? dayLabel(g) : null
    const last = groups[groups.length - 1]
    if (last && last.label === label) last.games.push(g); else groups.push({ label, games: [g] })
  }
  const quoted = upcoming.filter(g => g.market_spread !== null).length
  const biggest = upcoming.filter(g => g.absolute !== null).sort((a, b) => b.absolute! - a.absolute!)[0]
  const pickSort = (key: SortKey) => setSort({ key, desc: !textKeys.includes(key) })
  const logo = (id: string) => byId.get(id)?.logo_url ?? null

  const exportCsv = () => downloadCsv(toCsv(
    ['game_id', 'kickoff', 'time_tbd', 'away_team', 'home_team', 'site', 'away_power', 'home_power', 'model_line_home', 'market_line_home', 'market_provider', 'market_retrieved_at', 'signed_delta', 'absolute_delta', 'model_favors', 'potential_value'],
    rows.map(g => [g.game_id, g.kickoff, g.time_tbd, g.away_team, g.home_team, g.site, g.away_rating, g.home_rating, g.model, g.market_spread, g.market_provider, g.market_retrieved_at, g.delta, g.absolute, g.favored, g.value]),
  ), `cfb-betting-lines-${data?.season ?? ''}-${weekSlug(data?.week)}.csv`)

  return <section className="view" aria-labelledby="betting-heading">
    <SectionHead index="03" eyebrow={`Model vs. market · ${data?.season ?? ratings?.season ?? '—'}`} title={data?.week != null ? `Week ${data.week} Lines` : 'Upcoming Lines'} id="betting-heading">
      <p>Model-implied lines from the power ratings, set against one published sportsbook quote per game. Kickoffs are shown in your local time.</p>
    </SectionHead>

    {data && <div className="tiles" aria-label="Board summary">
      <StatCell label="Yearly model performance (ATS)"><span className="stat-value">—</span><span className="stat-unit">Data unavailable</span></StatCell>
      <StatCell label="Model performance (Outright)"><span className="stat-value">—</span><span className="stat-unit">Data unavailable</span></StatCell>
      <StatCell label="Largest difference">{biggest ? <><span className="stat-team">{biggest.away_team} at {biggest.home_team}</span><span className="stat-value">{num(biggest.absolute)}</span></> : <span className="stat-team muted">Data unavailable</span>}</StatCell>
    </div>}

    <div className="board board-plain">
      <div className="toolbar">
        <div className="toolbar-filters">
          <label className="field search"><Search size={16} aria-hidden="true" /><span className="visually-hidden">Search matchups</span>
            <input type="search" aria-label="Search matchups" value={query} onChange={e => setQuery(e.target.value)} placeholder="Search teams or matchups" />
            {query && <button type="button" className="field-clear" aria-label="Clear search" onClick={() => setQuery('')}><X size={14} /></button>}
          </label>
          <SelectField label="Sort matchups" value={sort.key} onChange={key => pickSort(key as SortKey)}>{fields.map(f => <option key={f.key} value={f.key}>Sort: {f.label}</option>)}</SelectField>
          <button type="button" className="btn btn-icon" aria-label={sort.desc ? 'Sorted descending; switch to ascending' : 'Sorted ascending; switch to descending'} onClick={() => setSort(s => ({ ...s, desc: !s.desc }))}>{sort.desc ? <ArrowDown size={15} /> : <ArrowUp size={15} />}</button>
        </div>
        <div className="toolbar-end">
          <span className="count" aria-live="polite">{rows.length} games</span>
          {data && <button type="button" className="btn" onClick={exportCsv} disabled={rows.length === 0}><FileDown size={15} aria-hidden="true" /><span>CSV</span></button>}
        </div>
      </div>
      <Notice>Large numbers are each team's <strong>power rating</strong>. <em>Potential value</em> is the side whose market handicap is more favorable than the model's — a rating discrepancy, not a win probability. Missing ratings or lines stay unavailable.</Notice>
      {!compatible && !loading && <Notice role="alert">Ratings/HFA snapshot unavailable or out of sync. Refresh the page after the next data publication.</Notice>}
      {stale && <Notice role="alert"><strong>Snapshot is over 24 hours old.</strong> Lines are published snapshots, not a live feed.</Notice>}
    </div>

    {loading ? <EmptyState role="status" title="Loading matchup analysis">Reading the latest schedule and market snapshot…</EmptyState>
      : error ? <EmptyState role="alert" title="Data unavailable" action={<button type="button" className="btn" onClick={() => setRetry(r => r + 1)}>Retry matchup data</button>}>The matchup dataset could not be loaded.</EmptyState>
      : rows.length === 0 ? <EmptyState title={query ? 'No matching games' : 'No upcoming games in this snapshot'}>{query ? 'Try another team name.' : 'The schedule will update on the next weekly or manual refresh.'}</EmptyState>
      : groups.map((group, i) => <div key={`${group.label}-${i}`} className="game-group">
        {group.label && <div className="day-head"><h3>{group.label}</h3><span>{group.games.length} {group.games.length === 1 ? 'game' : 'games'}</span></div>}
        <ul className="game-grid">{group.games.map(g => <li key={g.game_id}><GameCard g={g} logo={logo} /></li>)}</ul>
      </div>)}

    <section className="calc" aria-labelledby="calculator-title">
      <div className="calc-inputs">
        <Kicker>Matchup calculator</Kicker>
        <h3 id="calculator-title">Build your own line</h3>
        <p>Choose two teams. Let the ratings set the line.</p>
        <div className="calc-grid">
          <SelectField hideLabel={false} label="Away team" ariaLabel="Calculator away team" value={awayId} onChange={setAwayId}><option value="">Select away team</option>{teams.map(t => <option key={t.team_id} value={t.team_id} disabled={t.team_id === homeId}>{t.team}</option>)}</SelectField>
          <SelectField hideLabel={false} label="Home team" ariaLabel="Calculator home team" value={homeId} onChange={setHomeId}><option value="">Select home team</option>{teams.map(t => <option key={t.team_id} value={t.team_id} disabled={t.team_id === awayId}>{t.team}</option>)}</SelectField>
          <SelectField hideLabel={false} label="Venue" ariaLabel="Calculator venue" value={neutral ? 'neutral' : 'home'} onChange={v => setNeutral(v === 'neutral')}><option value="home">Home Site</option><option value="neutral">Neutral Site</option></SelectField>
        </div>
      </div>
      <div className="calc-result" aria-live="polite">
        <div className="micro-label">Model line · home perspective</div>
        <strong>{duplicate ? 'Choose two different teams' : home && away ? display(lineLabel(home.team, calculated)) : 'Select a matchup'}</strong>
        <p>{home && away && calculated !== null ? `Model favors: ${favoredSide(home.team, away.team, calculated)}` : 'Both teams need an available power rating.'}</p>
        <div className="calc-meta">
          <span>{neutral ? 'Neutral site · No HFA applied' : hfa === null ? 'HFA unavailable' : `${hfa.toFixed(4)} points of HFA applied to home team`}</span>
          <span>Ratings updated: {formatLocal(ratings?.updated_at)}</span>
        </div>
      </div>
    </section>

    <section id="methodology" className="method" aria-labelledby="method-title">
      <div className="method-intro"><Kicker index="—">Methodology</Kicker><h2 id="method-title">How the lines work</h2></div>
      <div className="method-cols">
        <article><h3>One convention, throughout</h3><p>Home line = away power − home power − home-field advantage. Neutral games use zero HFA. A negative line means the home team is favored; cards restate each line from the favorite's side. The calculator and cards use the same function and the production model's HFA setting. Games involving a team without a production rating retain their schedule and market line but have no model line.</p></article>
        <article><h3>Reading the discrepancy</h3><p>Signed Δ = model home line − market home line. For example, a model line of home −7.0 against a market line of home −3.0 gives Δ −4.0, pointing to the home side. This is a rating discrepancy, not a calibrated expected return. One sportsbook quote is chosen per game; its name appears beside the line. The next provider week with future games is selected at export time.</p></article>
      </div>
      <details className="glossary"><summary>Field definitions</summary><dl>{fields.map(f => <div key={f.key}><dt>{f.label}</dt><dd>{f.explanation}</dd></div>)}</dl></details>
      <div className="sources sources-stack">
        <span><strong>{data?.market_source ?? 'CollegeFootballData'}</strong> — {data?.market_status ?? 'Market data unavailable.'}</span>
        <span>Last retrieved: {formatLocal(data?.market_retrieved_at)} · Sportsbook update time: unavailable (not supplied by the source).</span>
        <span>Schedule as of: {formatLocal(data?.schedule_updated_at)} · {data?.schedule_status ?? 'Schedule status unavailable'}. Export updated {formatUpdated(data?.updated_at)}. Lines are published snapshots, not a live feed.</span>
      </div>
    </section>
  </section>
}

function GameCard({ g, logo }: { g: Analyzed; logo: (id: string) => string | null }) {
  const pickem = g.model !== null && Math.abs(g.model) < 0.05
  const favorite = g.model === null || pickem ? null : g.model < 0 ? 'home' : 'away'
  const when = g.time_tbd ? `${g.kickoff ? new Date(g.kickoff).toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' }) : 'Date unavailable'} · Time TBD`
    : g.kickoff ? new Date(g.kickoff).toLocaleString(undefined, { weekday: 'short', hour: 'numeric', minute: '2-digit', timeZoneName: 'short' }) : 'Kickoff unavailable'
  const side = (who: 'away' | 'home') => {
    const name = who === 'away' ? g.away_team : g.home_team
    const rating = who === 'away' ? g.away_rating : g.home_rating
    return <div className={`game-team${favorite === who ? ' is-fav' : ''}`}>
      <TeamLogo name={name} src={logo(who === 'away' ? g.away_team_id : g.home_team_id)} size={40} />
      <div className="game-name"><span className="team-name">{name}</span><span className="game-sub">{who === 'away' ? 'Away' : g.neutral_site ? 'Home · neutral' : 'Home'}</span></div>
      <span className="game-proj" aria-label={`${name} power rating ${rating === null ? 'unavailable' : signedPoints(rating)}`}>{rating === null ? '—' : signed(rating)}</span>
    </div>
  }
  const value = display(valueLine(g.home_team, g.away_team, g.delta, g.market_spread))
  return <article className="game card" aria-label={g.matchup}>
    <header className="game-top">
      <span className="tag">{when}</span>
      <span className="tag">{g.site === 'Data unavailable' ? 'Site unavailable' : g.site}</span>
      <span className={`gap-badge${g.absolute === null ? ' is-empty' : ''}`} title={g.delta === null ? 'Data unavailable' : `Signed Δ (model − market, home perspective): ${signedPoints(g.delta)}`}>
        <small>Gap</small>{g.absolute === null ? '—' : num(g.absolute)}
      </span>
    </header>
    <div className="game-teams"><div className="game-colhead" aria-hidden="true">Power ratings</div>{side('away')}{side('home')}</div>
    <dl className="game-compare">
      <div><dt>Market{g.market_provider && <em>{g.market_provider}</em>}</dt><dd>{g.market_spread === null ? 'No quote' : display(favoriteLine(g.home_team, g.away_team, g.market_spread))}</dd></div>
      <div className="is-model"><dt>Model</dt><dd>{display(favoriteLine(g.home_team, g.away_team, g.model))}</dd></div>
    </dl>
    <footer className="game-pick"><span className="pick-label">Potential value</span><span className={value === '—' || value === 'No difference' ? 'tag' : 'tag tag-navy pick-value'}>{value}</span></footer>
  </article>
}
