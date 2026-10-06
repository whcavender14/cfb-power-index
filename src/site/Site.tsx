import { lazy, Suspense, useEffect, useRef, useState, type ReactElement } from 'react'
import { ChevronDown, Menu, Moon, Sun, X } from 'lucide-react'
import { Skeleton, TeamsContext, useData } from './components'
import type { TeamsDoc } from './data'
import { Link, Redirect, useLegacyHashRedirect, useLocation } from './router'
import Home from './pages/Home'
const Rankings = lazy(() => import('./pages/Rankings'))
const Games = lazy(() => import('./pages/Games'))
const GameQuality = lazy(() => import('./pages/GameQuality'))
const Playoff = lazy(() => import('./pages/Playoff'))
const Teams = lazy(() => import('./pages/Teams'))
const Team = lazy(() => import('./pages/Team'))
const Matchup = lazy(() => import('./pages/Matchup'))
const ConferenceList = lazy(() => import('./pages/Conferences').then(m => ({ default: m.ConferenceList })))
const ConferenceVs = lazy(() => import('./pages/Conferences').then(m => ({ default: m.ConferenceVs })))
const ConferenceDetail = lazy(() => import('./pages/Conferences').then(m => ({ default: m.ConferenceDetail })))
const Resume = lazy(() => import('./pages/Resume'))
const WhatIf = lazy(() => import('./pages/WhatIf'))
const Model = lazy(() => import('./pages/Model'))
const Players = lazy(() => import('./pages/Players'))
const RatingsMethodology = lazy(() => import('./pages/PlayerRatings'))
const RecruitingHome = lazy(() => import('./pages/Recruiting').then(m => ({ default: m.RecruitingHome })))
const HighSchool = lazy(() => import('./pages/Recruiting').then(m => ({ default: m.HighSchool })))
const Transfers = lazy(() => import('./pages/Transfers'))
const LegacySimulations = lazy(() => import('./pages/Legacy').then(m => ({ default: m.LegacySimulations })))
const LegacyBetting = lazy(() => import('./pages/Legacy').then(m => ({ default: m.LegacyBetting })))
import NotFound from './pages/NotFound'
import { PlayerProvider } from './player'
import Search from './Search'

// Items marked `more` sit under the header's More menu on desktop, so the bar fits on one line; the phone menu lists all.
const NAV: { to: string; label: string; more?: boolean }[] = [
  { to: '/', label: 'Home' },
  { to: '/rankings/', label: 'Rankings' },
  { to: '/games/', label: 'Games' },
  { to: '/playoff/', label: 'Playoff' },
  { to: '/whatif/', label: 'What If?', more: true },
  { to: '/teams/', label: 'Teams' },
  { to: '/players/', label: 'Players' },
  { to: '/recruiting/', label: 'Recruiting' },
  { to: '/conferences/', label: 'Conferences', more: true },
  { to: '/model/', label: 'Model', more: true },
]

function route(path: string) {
  const team = path.match(/^\/teams\/([a-z0-9-]+)\/$/)
  if (team) return { page: <Team slug={team[1]} />, section: '/teams/', title: null }
  const game = path.match(/^\/games\/(\d+)\/$/)
  if (game) return { page: <Matchup id={game[1]} />, section: '/games/', title: 'Matchup' }
  const vs = path.match(/^\/conferences\/([a-z0-9-]+)\/vs\/([a-z0-9-]+)\/$/)
  if (vs) return { page: <ConferenceVs slug={vs[1]} other={vs[2]} />, section: '/conferences/', title: null }
  const conf = path.match(/^\/conferences\/([a-z0-9-]+)\/$/)
  if (conf) return { page: <ConferenceDetail slug={conf[1]} />, section: '/conferences/', title: null }
  const pages: Record<string, [ReactElement, string]> = {
    '/': [<Home />, 'College Football Power Ratings'],
    '/rankings/': [<Rankings />, 'Rankings'],
    '/games/': [<Games />, 'Games'],
    '/games/quality/': [<GameQuality />, 'Game Quality'],
    '/playoff/': [<Playoff />, 'Playoff'],
    '/teams/': [<Teams />, 'Teams'],
    '/players/': [<Players />, 'Players'],
    '/players/ratings/': [<RatingsMethodology />, 'CFPi+ Player Ratings'],
    '/recruiting/': [<RecruitingHome />, 'Recruiting'],
    '/recruiting/high-school/': [<HighSchool />, 'High School Recruiting'],
    '/recruiting/transfers/': [<Transfers />, 'Transfers'],
    '/conferences/': [<ConferenceList />, 'Conferences'],
    // History (rating comparison) was retired in Round 18; old links land on Home. Team pages keep their own chart.
    '/compare/': [<Redirect to="/" />, 'College Football Power Ratings'],
    '/history/': [<Redirect to="/" />, 'College Football Power Ratings'],
    // What changed now lives on Home; old links land on that section.
    '/changes/': [<Redirect to="/#changed" />, 'College Football Power Ratings'],
    '/changed/': [<Redirect to="/#changed" />, 'College Football Power Ratings'],
    '/rankings/resume/': [<Resume />, 'Résumé Ranking'],
    '/whatif/': [<WhatIf />, 'What If?'],
    '/model/': [<Model />, 'Model'],
    '/simulations/': [<LegacySimulations />, 'Season simulations'],
    '/betting/': [<LegacyBetting />, 'Betting lines'],
  }
  const hit = pages[path]
  return hit ? { page: hit[0], section: path, title: hit[1] } : { page: <NotFound />, section: '', title: 'Page not found' }
}

type Theme = 'light' | 'dark'
function useTheme(): [Theme, () => void] {
  const [theme, setTheme] = useState<Theme>(() => document.documentElement.dataset.theme === 'dark' ? 'dark' : 'light')
  useEffect(() => {
    document.documentElement.dataset.theme = theme
    document.querySelector('meta[name="theme-color"]')?.setAttribute('content', '#0a1830')
    try { localStorage.setItem('cfb-theme', theme) } catch { /* storage unavailable */ }
  }, [theme])
  return [theme, () => setTheme(t => (t === 'dark' ? 'light' : 'dark'))]
}

function MoreMenu({ items, isActive, path }: { items: typeof NAV; isActive: (to: string) => boolean; path: string }) {
  const [open, setOpen] = useState(false)
  const box = useRef<HTMLDivElement>(null)
  useEffect(() => { setOpen(false) }, [path])
  useEffect(() => {
    if (!open) return
    const away = (e: MouseEvent) => { if (!box.current?.contains(e.target as Node)) setOpen(false) }
    const esc = (e: KeyboardEvent) => { if (e.key === 'Escape') setOpen(false) }
    document.addEventListener('mousedown', away); document.addEventListener('keydown', esc)
    return () => { document.removeEventListener('mousedown', away); document.removeEventListener('keydown', esc) }
  }, [open])
  const active = items.some(n => isActive(n.to))
  return <div ref={box} className="cf-nav-more-wrap">
    <button type="button" className={`cf-nav-link cf-nav-more${active ? ' is-active' : ''}`} aria-expanded={open} aria-haspopup="true" onClick={() => setOpen(o => !o)}>
      More <ChevronDown size={14} aria-hidden="true" />
    </button>
    {open && <div className="cf-hs-pop cf-nav-pop">
      {items.map(n => <Link key={n.to} to={n.to} className="cf-hs-item" aria-current={isActive(n.to) ? 'page' : undefined}>{n.label}</Link>)}
    </div>}
  </div>
}

export default function Site() {
  const ready = useLegacyHashRedirect()
  const { path } = useLocation()
  const [theme, toggleTheme] = useTheme()
  const [menuOpen, setMenuOpen] = useState(false)
  const menuButton = useRef<HTMLButtonElement>(null)
  const teams = useData<TeamsDoc>('teams.json')
  const directory = new Map((teams.data?.teams ?? []).map(t => [t.team_id, t]))
  const { page, section, title } = route(path)

  useEffect(() => { setMenuOpen(false) }, [path])
  useEffect(() => { if (title) document.title = path === '/' ? `CFPi+ | ${title}` : `${title} | CFPi+` }, [path, title])
  useEffect(() => {
    if (!menuOpen) return
    const esc = (e: KeyboardEvent) => { if (e.key === 'Escape') { setMenuOpen(false); menuButton.current?.focus() } }
    document.addEventListener('keydown', esc)
    return () => document.removeEventListener('keydown', esc)
  }, [menuOpen])

  const isActive = (to: string) => to === '/' ? path === '/' : section.startsWith(to)
  const links = (cls: string, items = NAV) => items.map(n => <Link key={n.to} to={n.to} className={cls} aria-current={isActive(n.to) ? 'page' : undefined}>{n.label}</Link>)

  return <TeamsContext.Provider value={directory}><PlayerProvider>
    <a href="#cf-main" className="cf-skip">Skip to content</a>
    <header className="cf-header">
      <div className="cf-wrap cf-header-row">
        <Link to="/" className="cf-brand" aria-label="CFPi+ home"><img src={`${import.meta.env.BASE_URL}brand/logo-on-dark.png`} alt="CFPi+ Cavender Football Power Index" style={{ display: 'block', height: 38, width: 'auto' }} /></Link>
        <nav className="cf-nav" aria-label="Primary">{links('cf-nav-link', NAV.filter(n => !n.more))}<MoreMenu items={NAV.filter(n => n.more)} isActive={isActive} path={path} /></nav>
        <div className="cf-header-actions">
          <Search />
          <button type="button" className="cf-icon-btn" onClick={toggleTheme} aria-label={theme === 'dark' ? 'Switch to light appearance' : 'Switch to dark appearance'}>
            {theme === 'dark' ? <Sun size={17} /> : <Moon size={17} />}
          </button>
          <button type="button" ref={menuButton} className="cf-icon-btn cf-menu-btn" aria-expanded={menuOpen} aria-controls="cf-mobile-nav" aria-label={menuOpen ? 'Close menu' : 'Open menu'} onClick={() => setMenuOpen(o => !o)}>
            {menuOpen ? <X size={19} /> : <Menu size={19} />}
          </button>
        </div>
      </div>
      <nav id="cf-mobile-nav" className={`cf-mobile-nav${menuOpen ? ' is-open' : ''}`} aria-label="Primary" hidden={!menuOpen}>
        <div className="cf-wrap">{links('cf-mobile-link')}</div>
      </nav>
    </header>
    {menuOpen && <div className="cf-scrim" onClick={() => setMenuOpen(false)} aria-hidden="true" />}

    <main id="cf-main" className="cf-wrap cf-main" tabIndex={-1}>{ready ? <Suspense fallback={<Skeleton />}>{page}</Suspense> : null}</main>

    <footer className="cf-footer">
      <div className="cf-wrap cf-footer-row">
        <p><strong>CFPi+</strong> is the production model of the Cavender Football Power Index: opponent-adjusted power ratings and season simulations for every FBS team.</p>
        <p className="cf-muted">
          <Link to="/model/">How the model works</Link> · Schedules, results and logos via <a href="https://collegefootballdata.com/" target="_blank" rel="noreferrer">CollegeFootballData</a> · Independent; not affiliated with the CFP.
        </p>
      </div>
    </footer>
  </PlayerProvider></TeamsContext.Provider>
}
