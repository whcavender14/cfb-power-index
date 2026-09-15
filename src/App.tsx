import { useEffect, useMemo, useState } from 'react'
import { Info, Moon, Sun } from 'lucide-react'
import type { Dataset, Rating, Simulation } from './data'
import { fetchDataset } from './data'
import BettingAnalysis from './BettingAnalysis'
import PowerRatings from './PowerRatings'
import SeasonSimulations from './SeasonSimulations'
import { Kicker, TeamLogo } from './ui'
import { formatUpdated, signed, weekLabel } from './format'

type Tab = 'ratings' | 'simulations' | 'betting'
const TABS: { id: Tab; label: string; short: string }[] = [
  { id: 'ratings', label: 'Power Ratings', short: 'Ratings' },
  { id: 'simulations', label: 'Season Simulations', short: 'Simulations' },
  { id: 'betting', label: 'Betting Line Analysis', short: 'Betting Lines' },
]
const tabFromHash = (): Tab | null => {
  const hash = location.hash.slice(1)
  return hash === 'ratings' || hash === 'simulations' || hash === 'betting' ? hash : null
}

type Theme = 'light' | 'dark'
function useTheme(): [Theme, () => void] {
  // index.html applies a stored choice before first paint; light is the default.
  const [theme, setTheme] = useState<Theme>(() => document.documentElement.dataset.theme === 'dark' ? 'dark' : 'light')
  useEffect(() => {
    document.documentElement.dataset.theme = theme
    document.querySelector('meta[name="theme-color"]')?.setAttribute('content', theme === 'dark' ? '#0f1115' : '#f7f4ec')
    try { localStorage.setItem('cfb-theme', theme) } catch { /* storage unavailable */ }
  }, [theme])
  return [theme, () => setTheme(t => t === 'dark' ? 'light' : 'dark')]
}

function App() {
  const [tab, setTab] = useState<Tab>(() => tabFromHash() ?? 'ratings')
  const [theme, toggleTheme] = useTheme()
  const [ratings, setRatings] = useState<Dataset<Rating> | null>(null)
  const [simulations, setSimulations] = useState<Dataset<Simulation> | null>(null)
  const [errors, setErrors] = useState<Partial<Record<Tab, boolean>>>({})
  const [loading, setLoading] = useState(true)
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
  useEffect(() => {
    const change = () => { const next = tabFromHash(); if (next) setTab(next) }
    window.addEventListener('hashchange', change)
    return () => window.removeEventListener('hashchange', change)
  }, [])

  const ranked = useMemo(() => [...(ratings?.teams ?? [])].filter(r => r.power_rating !== null).sort((a, b) => b.power_rating! - a.power_rating! || a.team.localeCompare(b.team)), [ratings])
  const ranks = useMemo(() => new Map(ranked.map((r, i) => [r.team_id, i + 1])), [ranked])
  const leader = (key: 'offensive_rating' | 'defensive_rating' | 'preseason_change') => [...(ratings?.teams ?? [])].filter(r => r[key] !== null)
    .sort((a, b) => key === 'defensive_rating' ? a[key]! - b[key]! : b[key]! - a[key]!)[0]
  const leaders = [
    { label: 'No. 1 overall', unit: 'Power', team: ranked[0], value: ranked[0]?.power_rating },
    { label: 'Top offense', unit: 'Offense', team: leader('offensive_rating'), value: leader('offensive_rating')?.offensive_rating },
    { label: 'Top defense', unit: 'Defense', team: leader('defensive_rating'), value: leader('defensive_rating')?.defensive_rating },
    { label: 'Riser vs. preseason', unit: 'Δ Pre', team: leader('preseason_change'), value: leader('preseason_change')?.preseason_change },
  ]

  const navigate = (next: Tab) => {
    if (location.hash !== `#${next}`) location.hash = next
    setTab(next)
    const view = document.getElementById('main')
    if (view && view.getBoundingClientRect().top < 0) view.scrollIntoView({ block: 'start' })
  }
  const showMethodology = () => document.getElementById('methodology')?.scrollIntoView({ behavior: 'smooth', block: 'start' })
  const retryLoad = () => setRetry(x => x + 1)

  return <>
    <a href="#main" className="skip-link">Skip to content</a>
    <header className="site-header">
      <div className="wrap header-row">
        <a className="brand" href="#ratings" onClick={e => { e.preventDefault(); navigate('ratings') }} aria-label="CFB Power Index home">
          <span className="brand-mark" aria-hidden="true">PI</span>
          <span className="brand-name"><span className="brand-tag">CFB</span>Power Index</span>
        </a>
        <nav className="nav" aria-label="Analytics views">
          {TABS.map(t => <button key={t.id} type="button" aria-current={tab === t.id ? 'page' : undefined} onClick={() => navigate(t.id)}>
            <span className="nav-full">{t.label}</span><span className="nav-short">{t.short}</span>
          </button>)}
        </nav>
        <div className="header-actions">
          <span className="tag tag-gold season-tag">{ratings?.season ?? '—'} Season</span>
          <button type="button" className="icon-btn" onClick={showMethodology} aria-label="About the model and data sources" title="Methodology"><Info size={18} /></button>
          <button type="button" className="icon-btn" onClick={toggleTheme} aria-label={theme === 'dark' ? 'Switch to light theme' : 'Switch to dark theme'} title={theme === 'dark' ? 'Light theme' : 'Dark theme'}>{theme === 'dark' ? <Sun size={18} /> : <Moon size={18} />}</button>
        </div>
      </div>
    </header>

    <section className="hero">
      <div className="wrap hero-grid">
        <div className="hero-copy">
          <Kicker>{ratings?.season ?? '—'} College Football · {weekLabel(ratings?.week)}</Kicker>
          <h1>Beyond the <span className="hl">scoreboard</span></h1>
          <p className="hero-lede">Opponent-adjusted power ratings, season simulations, and model-versus-market lines for every FBS team.</p>
          <div className="hero-meta">
            <span className="tag">{ratings ? `${ratings.rated_teams ?? ranked.length} / ${ratings.total_teams ?? ratings.teams.length} teams rated` : loading ? 'Loading ratings…' : 'Ratings unavailable'}</span>
            <span className="tag">Updated {loading ? '…' : formatUpdated(ratings?.updated_at)}</span>
          </div>
        </div>
        <aside className="glance card" aria-label="Leaders among available ratings">
          <div className="glance-head"><span className="glance-title">At a glance</span><span className="tag tag-navy">{weekLabel(ratings?.week)}</span></div>
          <ul>{leaders.map(({ label, unit, team, value }) => <li key={label}>
            <span className="glance-label">{label}</span>
            {team ? <span className="glance-row"><TeamLogo name={team.team} src={team.logo_url} size={30} /><span className="glance-team">{team.team}</span><span className="glance-value"><small>{unit}</small>{signed(value)}</span></span>
              : <span className="glance-row muted">{loading ? 'Loading…' : 'Data unavailable'}</span>}
          </li>)}</ul>
        </aside>
      </div>
    </section>

    <main id="main" className="wrap main">
      {tab === 'ratings' && <PowerRatings ratings={ratings} ranked={ranked} ranks={ranks} loading={loading} error={!!errors.ratings} onRetry={retryLoad} />}
      {tab === 'simulations' && <SeasonSimulations simulations={simulations} loading={loading} error={!!errors.simulations} onRetry={retryLoad} />}
      {tab === 'betting' && <BettingAnalysis ratings={ratings} />}
    </main>

    <footer className="site-footer">
      <div className="wrap footer-row">
        <span className="footer-brand"><span className="brand-mark small" aria-hidden="true">PI</span><span className="brand-name"><span className="brand-tag">CFB</span>Power Index</span></span>
        <span>Independent college football analytics. Built on data, made for Saturdays.</span>
      </div>
    </footer>
  </>
}
export default App
