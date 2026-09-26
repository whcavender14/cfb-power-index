import { lazy, Suspense, useEffect, useRef, useState, type ReactElement } from 'react'
import { Menu, Moon, Sun, X } from 'lucide-react'
import { TeamsContext, useData } from './components'
import type { TeamsDoc } from './data'
import { Link, useLegacyHashRedirect, useLocation } from './router'
import Home from './pages/Home'
const Rankings = lazy(() => import('./pages/Rankings'))
const Games = lazy(() => import('./pages/Games'))
const Playoff = lazy(() => import('./pages/Playoff'))
const Teams = lazy(() => import('./pages/Teams'))
const Team = lazy(() => import('./pages/Team'))
const ConferenceList = lazy(() => import('./pages/Conferences').then(m => ({ default: m.ConferenceList })))
const ConferenceDetail = lazy(() => import('./pages/Conferences').then(m => ({ default: m.ConferenceDetail })))
const Compare = lazy(() => import('./pages/Compare'))
const Changes = lazy(() => import('./pages/Changes'))
const Resume = lazy(() => import('./pages/Resume'))
const WhatIf = lazy(() => import('./pages/WhatIf'))
const Model = lazy(() => import('./pages/Model'))
const LegacySimulations = lazy(() => import('./pages/Legacy').then(m => ({ default: m.LegacySimulations })))
const LegacyBetting = lazy(() => import('./pages/Legacy').then(m => ({ default: m.LegacyBetting })))
import NotFound from './pages/NotFound'

const NAV = [
  { to: '/', label: 'Home' },
  { to: '/rankings/', label: 'Rankings' },
  { to: '/changes/', label: 'What changed' },
  { to: '/compare/', label: 'History' },
  { to: '/games/', label: 'Games' },
  { to: '/playoff/', label: 'Playoff' },
  { to: '/teams/', label: 'Teams' },
  { to: '/conferences/', label: 'Conferences' },
  { to: '/model/', label: 'Model' },
]

function route(path: string) {
  const team = path.match(/^\/teams\/([a-z0-9-]+)\/$/)
  if (team) return { page: <Team slug={team[1]} />, section: '/teams/', title: null }
  const conf = path.match(/^\/conferences\/([a-z0-9-]+)\/$/)
  if (conf) return { page: <ConferenceDetail slug={conf[1]} />, section: '/conferences/', title: null }
  const pages: Record<string, [ReactElement, string]> = {
    '/': [<Home />, 'College Football Power Ratings'],
    '/rankings/': [<Rankings />, 'Rankings'],
    '/games/': [<Games />, 'Games'],
    '/playoff/': [<Playoff />, 'Playoff'],
    '/teams/': [<Teams />, 'Teams'],
    '/conferences/': [<ConferenceList />, 'Conferences'],
    '/compare/': [<Compare />, 'Rating history'],
    '/changes/': [<Changes />, 'What changed'],
    '/rankings/resume/': [<Resume />, 'Résumé ranking'],
    '/whatif/': [<WhatIf />, 'What if?'],
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
    document.querySelector('meta[name="theme-color"]')?.setAttribute('content', theme === 'dark' ? '#000000' : '#ffffff')
    try { localStorage.setItem('cfb-theme', theme) } catch { /* storage unavailable */ }
  }, [theme])
  return [theme, () => setTheme(t => (t === 'dark' ? 'light' : 'dark'))]
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
  const links = (cls: string) => NAV.map(n => <Link key={n.to} to={n.to} className={cls} aria-current={isActive(n.to) ? 'page' : undefined}>{n.label}</Link>)

  return <TeamsContext.Provider value={directory}>
    <a href="#cf-main" className="cf-skip">Skip to content</a>
    <header className="cf-header">
      <div className="cf-wrap cf-header-row">
        <Link to="/" className="cf-brand" aria-label="CFPi+ home">CFPi<span className="cf-brand-plus">+</span></Link>
        <nav className="cf-nav" aria-label="Primary">{links('cf-nav-link')}</nav>
        <div className="cf-header-actions">
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

    <main id="cf-main" className="cf-wrap cf-main" tabIndex={-1}>{ready ? <Suspense fallback={<div className="cf-state" role="status"><p className="cf-muted">Loading…</p></div>}>{page}</Suspense> : null}</main>

    <footer className="cf-footer">
      <div className="cf-wrap cf-footer-row">
        <p><strong>CFPi+</strong> is the production model of the Cavender Football Power Index: opponent-adjusted power ratings and season simulations for every FBS team.</p>
        <p className="cf-muted">
          <Link to="/model/">How the model works</Link> · Schedules, results and logos via <a href="https://collegefootballdata.com/" target="_blank" rel="noreferrer">CollegeFootballData</a> · Independent; not affiliated with the CFP.
        </p>
      </div>
    </footer>
  </TeamsContext.Provider>
}
