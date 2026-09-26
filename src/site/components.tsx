import { createContext, useCallback, useContext, useEffect, useId, useRef, useState, type ReactNode } from 'react'
import { ArrowDown, ArrowUp, ChevronDown, ChevronUp, Minus } from 'lucide-react'
import { load, type Meta, type TeamMeta } from './data'
import { Link } from './router'
import { isNum } from '../format'

// ---------------------------------------------------------------------------------------------
// Data loading
// ---------------------------------------------------------------------------------------------
export type Loadable<T> = { data: T | null; error: string | null; loading: boolean; retry: () => void }

export function useData<T>(path: string | null): Loadable<T> {
  const [state, setState] = useState<{ data: T | null; error: string | null; loading: boolean }>({ data: null, error: null, loading: !!path })
  const [attempt, setAttempt] = useState(0)
  useEffect(() => {
    if (!path) return
    let live = true
    setState(s => ({ ...s, loading: true, error: null }))
    load<T>(path).then(data => { if (live) setState({ data, error: null, loading: false }) })
      .catch((e: Error) => { if (live) setState({ data: null, error: e.message, loading: false }) })
    return () => { live = false }
  }, [path, attempt])
  const retry = useCallback(() => setAttempt(a => a + 1), [])
  return { ...state, retry }
}

/** Loading / error states around a page body. Errors say what failed and offer a retry. */
export function DataGate<T>({ source, label, children }: { source: Loadable<T>; label: string; children: (data: T) => ReactNode }) {
  if (source.data) return <>{children(source.data)}</>
  if (source.error) return <div className="cf-state" role="alert">
    <p className="cf-state-title">{label} could not be loaded</p>
    <p className="cf-muted">{source.error}. The rest of the site still works.</p>
    <button type="button" className="cf-btn" onClick={source.retry}>Try again</button>
  </div>
  return <div className="cf-state" role="status" aria-live="polite"><span className="cf-spinner" aria-hidden="true" />Loading {label.toLowerCase()}…</div>
}

// ---------------------------------------------------------------------------------------------
// Team directory (teams.json), shared by every page
// ---------------------------------------------------------------------------------------------
export const TeamsContext = createContext<Map<string, TeamMeta>>(new Map())
export const useTeams = () => useContext(TeamsContext)

const initials = (name: string) => name.replace(/[^A-Za-z0-9 &]/g, '').split(/\s+/).filter(Boolean).slice(0, 2).map(w => w[0]).join('').toUpperCase()

/** Black or white text, whichever contrasts more with a team colour (WCAG relative luminance). */
function inkOn(hex: string): string {
  const m = /^#?([0-9a-f]{6})$/i.exec(hex.trim()); if (!m) return '#fff'
  const [r, g, b] = [0, 2, 4].map(i => { const c = parseInt(m[1].slice(i, i + 2), 16) / 255; return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4 })
  const L = 0.2126 * r + 0.7152 * g + 0.0722 * b
  return (L + 0.05) / 0.05 > 1.05 / (L + 0.05) ? '#1d1d1f' : '#fff'
}
/** Small same-origin logo (public/logos/sm, 144 px), then the full mirrored logo, then the CDN, then a monogram. */
export function TeamLogo({ id, name, size = 28 }: { id?: string | null; name: string; size?: number }) {
  const team = useTeams().get(id ?? '')
  const sources = [id && team ? `${import.meta.env.BASE_URL}logos/sm/${id}.png` : null, id && team ? `${import.meta.env.BASE_URL}logos/${id}.png` : null, team?.logo ?? null].filter(Boolean) as string[]
  const [index, setIndex] = useState(0)
  const style = { width: size, height: size }
  if (index >= sources.length) {
    return <span className="cf-logo cf-logo-mono" style={{ ...style, fontSize: Math.max(9, Math.round(size * 0.36)), background: team?.color ?? undefined, color: team?.color ? inkOn(team.color) : undefined }} aria-hidden="true">{initials(name)}</span>
  }
  return <img className="cf-logo" style={style} src={sources[index]} alt="" loading="lazy" decoding="async" onError={() => setIndex(i => i + 1)} />
}

/** A team name that links to its team page when it is an FBS team. */
export function TeamLink({ id, name, logo = true, size = 24, sub }: { id: string; name?: string; logo?: boolean; size?: number; sub?: ReactNode }) {
  const team = useTeams().get(id)
  const label = team?.team ?? name ?? '—'
  const body = <>{logo && <TeamLogo id={id} name={label} size={size} />}<span className="cf-team-text"><span className="cf-team-name">{label}</span>{sub && <span className="cf-team-sub">{sub}</span>}</span></>
  return team ? <Link className="cf-team" to={`/teams/${team.slug}/`}>{body}</Link> : <span className="cf-team">{body}</span>
}

// ---------------------------------------------------------------------------------------------
// Numbers
// ---------------------------------------------------------------------------------------------
export const Missing = ({ why = 'Not available' }: { why?: string }) => <span className="cf-missing" title={why}><span aria-hidden="true">—</span><span className="cf-sr">{why}</span></span>

const MINUS = '−'
export const fmt = (v: number | null | undefined, digits = 1) => isNum(v) ? (Object.is(Number(v.toFixed(digits)), -0) ? 0 : Number(v.toFixed(digits))).toFixed(digits).replace('-', MINUS) : null
export const fmtSigned = (v: number | null | undefined, digits = 1) => { const s = fmt(v, digits); return s === null ? null : (Number(v!.toFixed(digits)) > 0 ? `+${s}` : s) }

/** Probabilities from 1,000 simulations: exact zeros and ones show as "<0.1%" / ">99.9%", never a hard 0 or 100. */
export function pctText(p: number | null | undefined, digits = 1): string | null {
  if (!isNum(p)) return null
  if (p <= 0) return '<0.1%'
  if (p >= 1) return '>99.9%'
  const v = p * 100
  if (v < 0.1) return '<0.1%'
  if (v > 99.9) return '>99.9%'
  return `${v.toFixed(digits)}%`
}

export function Num({ value, digits = 1, signed = false, why }: { value: number | null | undefined; digits?: number; signed?: boolean; why?: string }) {
  const text = signed ? fmtSigned(value, digits) : fmt(value, digits)
  return text === null ? <Missing why={why} /> : <span className="cf-num">{text}</span>
}

export function Pct({ value, bar = false, why }: { value: number | null | undefined; bar?: boolean; why?: string }) {
  const text = pctText(value)
  if (text === null) return <Missing why={why} />
  return <span className="cf-pct"><span className="cf-num">{text}</span>{bar && <span className="cf-bar" aria-hidden="true"><i style={{ width: `${Math.min(100, value! * 100)}%` }} /></span>}</span>
}

/** Rank movement: arrow + number, never color alone. Positive = moved up. */
export function Movement({ change, compared }: { change: number | null | undefined; compared?: number | null }) {
  if (!isNum(change)) return <Missing why={compared == null ? 'No comparable previous week' : 'Not ranked last week'} />
  if (change === 0) return <span className="cf-move cf-move-flat" title="No change"><Minus size={12} aria-hidden="true" /><span className="cf-sr">No change</span><span aria-hidden="true">0</span></span>
  const up = change > 0
  return <span className={`cf-move ${up ? 'cf-move-up' : 'cf-move-down'}`}>
    {up ? <ArrowUp size={12} aria-hidden="true" /> : <ArrowDown size={12} aria-hidden="true" />}
    <span className="cf-sr">{up ? 'Up' : 'Down'} </span>{Math.abs(change)}
  </span>
}

// ---------------------------------------------------------------------------------------------
// Tooltip: a focusable button that reveals a short definition (hover, focus or tap)
// ---------------------------------------------------------------------------------------------
export function Info({ text, label = 'What is this?' }: { text: string; label?: string }) {
  const id = useId()
  const [open, setOpen] = useState(false)
  const ref = useRef<HTMLSpanElement>(null)
  useEffect(() => {
    if (!open) return
    const close = (e: Event) => { if (!ref.current?.contains(e.target as Node)) setOpen(false) }
    const esc = (e: KeyboardEvent) => { if (e.key === 'Escape') setOpen(false) }
    document.addEventListener('pointerdown', close); document.addEventListener('keydown', esc)
    return () => { document.removeEventListener('pointerdown', close); document.removeEventListener('keydown', esc) }
  }, [open])
  return <span className="cf-info" ref={ref} onMouseEnter={() => setOpen(true)} onMouseLeave={() => setOpen(false)}>
    <button type="button" className="cf-info-btn" aria-label={label} aria-describedby={open ? id : undefined} aria-expanded={open}
      onClick={e => { e.stopPropagation(); setOpen(o => !o) }} onFocus={() => setOpen(true)} onBlur={() => setOpen(false)}>?</button>
    <span role="tooltip" id={id} className={`cf-info-body${open ? ' is-open' : ''}`}>{text}</span>
  </span>
}

// ---------------------------------------------------------------------------------------------
// Sortable table header
// ---------------------------------------------------------------------------------------------
export type Sort = { key: string; desc: boolean }
export function SortTh({ label, sortKey, sort, onSort, info, align = 'end', className = '' }: {
  label: string; sortKey: string; sort: Sort; onSort: (s: Sort) => void; info?: string; align?: 'start' | 'end'; className?: string
}) {
  const active = sort.key === sortKey
  return <th scope="col" className={`cf-th-${align} ${className}`} aria-sort={active ? (sort.desc ? 'descending' : 'ascending') : 'none'}>
    <span className="cf-th">
      <button type="button" className={`cf-sort${active ? ' is-active' : ''}`} onClick={() => onSort({ key: sortKey, desc: active ? !sort.desc : true })}>
        {label}
        <span className="cf-sort-icon" aria-hidden="true">{active ? (sort.desc ? <ChevronDown size={12} /> : <ChevronUp size={12} />) : null}</span>
      </button>
      {info && <Info text={info} label={`About ${label}`} />}
    </span>
  </th>
}

/** Sort that always puts missing values last, whatever the direction. */
export function sortRows<T>(rows: T[], value: (row: T) => number | string | null | undefined, desc: boolean): T[] {
  return [...rows].sort((a, b) => {
    const x = value(a), y = value(b)
    const xm = x === null || x === undefined || (typeof x === 'number' && !Number.isFinite(x))
    const ym = y === null || y === undefined || (typeof y === 'number' && !Number.isFinite(y))
    if (xm || ym) return xm && ym ? 0 : xm ? 1 : -1
    const c = typeof x === 'string' ? x.localeCompare(y as string) : (x as number) - (y as number)
    return desc ? -c : c
  })
}

// ---------------------------------------------------------------------------------------------
// Page furniture
// ---------------------------------------------------------------------------------------------
const dateFmt = (iso: string | null | undefined) => iso ? new Date(iso).toLocaleString(undefined, { month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit', timeZoneName: 'short' }) : null

export function Freshness({ meta, sims = false }: { meta: Meta; sims?: boolean }) {
  const through = meta.ratings_week == null ? null : meta.ratings_week === 0 ? 'Preseason ratings' : `Ratings through Week ${meta.ratings_week}`
  const updated = dateFmt(sims ? meta.sim_updated_at : meta.ratings_updated_at)
  return <p className="cf-fresh">
    {through && <span>{through}</span>}
    {updated && <span>Last updated {updated}</span>}
    {sims && meta.sim_count != null && <span>{meta.sim_count.toLocaleString()} simulated seasons</span>}
  </p>
}

export function PageHead({ title, lede, children }: { title: string; lede?: ReactNode; children?: ReactNode }) {
  return <header className="cf-pagehead">
    <h1>{title}</h1>
    {lede && <p className="cf-lede">{lede}</p>}
    {children}
  </header>
}

export function Segmented<T extends string>({ value, options, onChange, label }: { value: T; options: { value: T; label: string }[]; onChange: (v: T) => void; label: string }) {
  return <div className="cf-seg" role="radiogroup" aria-label={label}>
    {options.map(o => <button key={o.value} type="button" role="radio" aria-checked={value === o.value} className={value === o.value ? 'is-on' : ''} onClick={() => onChange(o.value)}>{o.label}</button>)}
  </div>
}

export function Select({ label, value, onChange, children }: { label: string; value: string; onChange: (v: string) => void; children: ReactNode }) {
  return <label className="cf-field">
    <span className="cf-field-label">{label}</span>
    <span className="cf-select"><select value={value} onChange={e => onChange(e.target.value)}>{children}</select><ChevronDown size={14} aria-hidden="true" /></span>
  </label>
}
