import { useEffect, useMemo, useRef, useState } from 'react'
import { Pause, Play } from 'lucide-react'
import { useData } from './components'
import { load } from './data'
import { navigate } from './router'
import type { DashboardDoc, HsDoc, Recruit } from './recruiting'
import { rowsOf } from './recruiting'
import { teamTheme } from './teamTheme'
import { US_STATES, US_VIEWBOX } from './usStates'
import './recruiting.css'

// Where a recruiting class comes from: a US map (real state outlines, AK/HI as insets) shaded by count in the team's color,
// beside the top home states, with a scrub bar that steps through classes and animates the year-over-year change. Counts are
// rows of hs_<year>.json that pass `match`. Outlines: scripts/gen_state_paths.R.

const NAMES: Record<string, string> = { AL: 'Alabama', AK: 'Alaska', AZ: 'Arizona', AR: 'Arkansas', CA: 'California', CO: 'Colorado', CT: 'Connecticut', DE: 'Delaware', DC: 'Washington, DC', FL: 'Florida', GA: 'Georgia', HI: 'Hawaii', ID: 'Idaho', IL: 'Illinois', IN: 'Indiana', IA: 'Iowa', KS: 'Kansas', KY: 'Kentucky', LA: 'Louisiana', ME: 'Maine', MD: 'Maryland', MA: 'Massachusetts', MI: 'Michigan', MN: 'Minnesota', MS: 'Mississippi', MO: 'Missouri', MT: 'Montana', NE: 'Nebraska', NV: 'Nevada', NH: 'New Hampshire', NJ: 'New Jersey', NM: 'New Mexico', NY: 'New York', NC: 'North Carolina', ND: 'North Dakota', OH: 'Ohio', OK: 'Oklahoma', OR: 'Oregon', PA: 'Pennsylvania', RI: 'Rhode Island', SC: 'South Carolina', SD: 'South Dakota', TN: 'Tennessee', TX: 'Texas', UT: 'Utah', VT: 'Vermont', VA: 'Virginia', WA: 'Washington', WV: 'West Virginia', WI: 'Wisconsin', WY: 'Wyoming' }
// A count is drawn inside its state when it fits the largest circle that state can hold (r from scripts/gen_state_paths.R); otherwise
// it becomes a callout in the Atlantic joined by a leader line (HI sits far from the rest, so its callout stays beside it).
const fits = (s: string, n: number) => US_STATES[s].r >= 4.5 * String(n).length + 5
// Shade follows log(1 + count), so a state with 5 recruits stays distinct from one with 25 even when another state has 400.
const shade = (n: number, max: number) => n ? Math.log1p(n) / Math.log1p(max) : 0
const fillFor = (t: number): React.CSSProperties | undefined => t ? { fill: `color-mix(in srgb, var(--rc-heat) ${Math.round(14 + 86 * t)}%, var(--cf-surface))` } : undefined
const INK_AT = 0.62   // shade above which the count flips to the light/dark ink
const PLAY_MS = 1300
const plural = (n: number) => `${n} recruit${n === 1 ? '' : 's'}`
const signed = (d: number) => d > 0 ? `+${d}` : d < 0 ? `−${-d}` : '±0'
const hsPath = (y: number) => `recruiting/hs_${y}.json`
const reduced = () => typeof matchMedia !== 'undefined' && matchMedia('(prefers-reduced-motion: reduce)').matches

type Team = { team: string; color: string | null; alt_color: string | null }
type Tally = { counts: Map<string, number>; total: number; abroad: number; unknown: number }

function tally(doc: HsDoc | null, match: (r: Recruit) => boolean): Tally {
  const counts = new Map<string, number>(); let total = 0, abroad = 0, unknown = 0
  if (doc) for (const r of rowsOf<Recruit>(doc)) {
    if (!match(r)) continue
    total++
    if (!r.state) unknown++
    else if (NAMES[r.state]) counts.set(r.state, (counts.get(r.state) ?? 0) + 1)
    else abroad++
  }
  return { counts, total, abroad, unknown }
}

/** A count that eases from its last value to the new one when the class changes. */
function Num({ value }: { value: number }) {
  const [shown, setShown] = useState(value)
  const from = useRef(value)
  useEffect(() => {
    const start = from.current
    if (start === value || reduced()) { from.current = value; setShown(value); return }
    let raf = 0; const t0 = performance.now()
    const step = (t: number) => {
      const k = Math.min(1, (t - t0) / 600), e = 1 - (1 - k) ** 3
      const v = Math.round(start + (value - start) * e); from.current = v; setShown(v)
      if (k < 1) raf = requestAnimationFrame(step)
    }
    raf = requestAnimationFrame(step)
    return () => cancelAnimationFrame(raf)
  }, [value])
  return <>{shown}</>
}

export function RecruitMap({ year, years, onYear, match, matchKey, team, selected, onSelect, hint, subject = 'class', openClass }: {
  year: number; years: number[]; onYear: (y: number) => void; match: (r: Recruit) => boolean; matchKey: string
  team: Team; selected: string; onSelect: (state: string) => void; hint: string; subject?: string; openClass?: number
}) {
  const [hover, setHover] = useState('')
  const [playing, setPlaying] = useState(false)
  const [engaged, setEngaged] = useState(false)   // the prior class (for deltas) loads only once someone scrubs or plays
  const doc = useData<HsDoc>(hsPath(year))
  const shownYear = doc.data?.year ?? year         // the old class stays on screen until the new one arrives, then animates
  const prevYear = years.includes(shownYear - 1) ? shownYear - 1 : null
  const prevDoc = useData<HsDoc>(engaged && prevYear ? hsPath(prevYear) : null)
  const cur = useMemo(() => tally(doc.data, match), [doc.data, matchKey])
  const prev = useMemo(() => prevDoc.data?.year === prevYear ? tally(prevDoc.data, match) : null, [prevDoc.data, prevYear, matchKey])
  const sorted = useMemo(() => [...years].sort((a, b) => a - b), [years])
  const pending = doc.data?.year !== year
  const onYearRef = useRef(onYear); onYearRef.current = onYear

  // Play: step one class at a time, waiting for each class to load before holding it on screen.
  useEffect(() => {
    if (!playing || pending) return
    const i = sorted.indexOf(year)
    if (i < 0 || i >= sorted.length - 1) { setPlaying(false); return }
    const t = setTimeout(() => onYearRef.current(sorted[i + 1]), PLAY_MS)
    return () => clearTimeout(t)
  }, [playing, pending, year, sorted])
  const play = () => {
    setEngaged(true)
    if (playing) { setPlaying(false); return }
    for (const y of sorted) load(hsPath(y)).catch(() => {})
    if (year === sorted[sorted.length - 1]) onYear(sorted[0])
    setPlaying(true)
  }

  const { counts, total, abroad, unknown } = cur
  const max = Math.max(1, ...counts.values())
  const ranked = [...counts].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
  const t = (n: number) => shade(n, max)
  const delta = (s: string) => prev ? (counts.get(s) ?? 0) - (prev.counts.get(s) ?? 0) : null
  const act = (s: string) => ({
    role: 'button' as const, tabIndex: 0, 'aria-pressed': selected === s, 'aria-label': `${NAMES[s]}: ${plural(counts.get(s) ?? 0)}. ${hint}`,
    onClick: () => onSelect(selected === s ? '' : s),
    onKeyDown: (e: React.KeyboardEvent) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onSelect(selected === s ? '' : s) } },
    onFocus: () => setHover(s), onBlur: () => setHover(''),
  })
  const shown = hover || selected
  const callouts = [...counts].filter(([s, n]) => !fits(s, n)).map(([s]) => s).sort((a, b) => US_STATES[a].y - US_STATES[b].y)
  const [, , vw] = US_VIEWBOX.split(' ').map(Number)
  const d = shown ? delta(shown) : null
  const tone = (v: number | null) => v == null ? '' : v > 0 ? ' is-up' : v < 0 ? ' is-down' : ''
  const who = subject === 'class' ? `${team.team} class` : team.team === 'All FBS' ? `All FBS ${subject}` : subject
  const totalDelta = prev ? total - prev.total : null
  const lead = ranked[0]?.[1] ?? 1
  return <figure className="rc-map" style={teamTheme(team.color, team.alt_color)} aria-labelledby="rc-map-year">
    <div className="rc-map-body">
      <div className="rc-map-main">
        <p className="rc-map-read" aria-live="polite">{shown
          ? <><b>{NAMES[shown]}</b> {plural(counts.get(shown) ?? 0)}{d != null && <span className={`rc-d${tone(d)}`}>{signed(d)} vs {prevYear}</span>}</>
          : <span className="cf-muted">Hover a state for its count. Select one to {hint.startsWith('Opens') ? 'see those commitments' : 'filter the list'}.</span>}</p>
        <svg className="rc-map-svg" viewBox={US_VIEWBOX} role="group" aria-label={`${who}, ${shownYear}: recruits by home state`}>
          {Object.entries(US_STATES).map(([s, g]) => {
            const n = counts.get(s) ?? 0
            return <path key={s} d={g.d} className={`rc-st${n ? ' is-hit' : ''}${selected === s ? ' is-on' : ''}`} style={fillFor(t(n))} {...(n ? act(s) : {})}
              onMouseEnter={() => setHover(s)} onMouseLeave={() => setHover('')}><title>{NAMES[s]}: {plural(n)}</title></path>
          })}
          {Object.entries(US_STATES).map(([s, g]) => { const n = counts.get(s) ?? 0
            return n && fits(s, n) ? <text key={s} className={`rc-st-n${t(n) > INK_AT ? ' rc-tinv' : ''}`} x={g.x} y={g.y} textAnchor="middle" dominantBaseline="central"><Num value={n} /></text> : null })}
          {callouts.map((s, i) => { const g = US_STATES[s], n = counts.get(s) ?? 0, near = s === 'HI', cx = near ? g.x + 40 : vw - 46, cy = near ? g.y : 330 + i * 30
            return <g key={s} className={`rc-co${selected === s ? ' is-on' : ''}`} {...act(s)} onMouseEnter={() => setHover(s)} onMouseLeave={() => setHover('')}>
              {!near && <line x1={g.x} y1={g.y} x2={cx - 24} y2={cy} />}<rect x={cx - 24} y={cy - 12} width={48} height={24} rx={6} style={fillFor(t(n))} /><text className={t(n) > INK_AT ? 'rc-tinv' : undefined} x={cx} y={cy} textAnchor="middle" dominantBaseline="central">{s} <Num value={n} /></text>
            </g> })}
        </svg>
        <div className="rc-map-key" aria-hidden="true">
          <span>1</span><i className="rc-ramp" /><span>{max}</span>
          {(abroad > 0 || unknown > 0) && <span className="rc-map-x">{[abroad && `${abroad} from outside the US`, unknown && `${unknown} with no home state`].filter(Boolean).join(' · ')}</span>}
        </div>
      </div>

      <aside className="rc-side" aria-label="Class and top home states">
        <header className="rc-side-h">
          <div>
            <h3 id="rc-map-year" className={`rc-side-y${pending ? ' is-pending' : ''}`}>{year}</h3>
            <p className="rc-side-sub">{who}{shownYear === openClass && <span className="rc-tag">In progress</span>}</p>
          </div>
          <div className="rc-side-total">
            <b><Num value={total} /></b><span>recruits</span>
            {totalDelta != null && <span className={`rc-d${tone(totalDelta)}`}>{signed(totalDelta)} vs {prevYear}</span>}
          </div>
        </header>
        {sorted.length > 1 && <div className="rc-scrub">
          <button type="button" className="rc-scrub-play" onClick={play} aria-label={playing ? 'Pause' : `Play ${sorted[0]} to ${sorted[sorted.length - 1]}`} title={playing ? 'Pause' : 'Play every class'}>
            {playing ? <Pause size={13} strokeWidth={2.5} aria-hidden="true" /> : <Play size={13} strokeWidth={2.5} aria-hidden="true" />}
          </button>
          <Timeline years={sorted} year={year} onYear={y => { setEngaged(true); setPlaying(false); onYear(y) }} />
        </div>}
        <h4 className="rc-side-k">Top home states</h4>
        {ranked.length > 0 ? <ol className="rc-top">
          {ranked.slice(0, 8).map(([s, n], i) => { const dd = delta(s)
            return <li key={s}><button type="button" className={selected === s ? 'is-on' : ''} aria-pressed={selected === s} onClick={() => onSelect(selected === s ? '' : s)} onMouseEnter={() => setHover(s)} onMouseLeave={() => setHover('')}>
              <span className="rc-top-r">{i + 1}</span>
              <span className="rc-top-s">{NAMES[s]}</span>
              <span className="rc-top-m">{dd != null && <span className={`rc-d${tone(dd)}`} title={`Change vs ${prevYear}`}>{signed(dd)}</span>}<span>{Math.round(100 * n / total)}%</span></span>
              <span className="rc-top-n"><Num value={n} /></span>
              <span className="rc-top-b" aria-hidden="true"><i style={{ transform: `scaleX(${n / lead})` }} /></span>
            </button></li> })}
        </ol> : <p className="cf-small cf-muted">{pending ? 'Loading…' : `No ${shownYear} recruits match.`}</p>}
      </aside>
    </div>
  </figure>
}

/** Segmented class timeline (iOS segmented-control idiom): the thumb answers on press, follows the pointer 1:1 while dragging,
 *  and settles on the nearest class on release. A slider to assistive tech; arrows, Home and End step through classes. */
function Timeline({ years, year, onYear }: { years: number[]; year: number; onYear: (y: number) => void }) {
  const track = useRef<HTMLDivElement>(null)
  const [drag, setDrag] = useState<number | null>(null)   // thumb centre as a fraction of the track while dragging
  const n = years.length, idx = Math.max(0, years.indexOf(year))
  const at = (clientX: number) => { const r = track.current!.getBoundingClientRect(); return Math.min(1, Math.max(0, (clientX - r.left) / r.width)) }
  const pick = (f: number) => { const y = years[Math.min(n - 1, Math.floor(f * n))]; if (y !== year) onYear(y) }
  const centre = drag ?? (idx + 0.5) / n
  return <div ref={track} className={`rc-tl${drag != null ? ' is-drag' : ''}`} role="slider" tabIndex={0} aria-label="Recruiting class"
    aria-valuemin={years[0]} aria-valuemax={years[n - 1]} aria-valuenow={year} aria-valuetext={`${year} class`}
    onPointerDown={e => { e.currentTarget.setPointerCapture(e.pointerId); const f = at(e.clientX); setDrag(f); pick(f) }}
    onPointerMove={e => { if (drag == null) return; const f = at(e.clientX); setDrag(f); pick(f) }}
    onPointerUp={() => setDrag(null)} onPointerCancel={() => setDrag(null)}
    onKeyDown={e => {
      const k = e.key === 'ArrowRight' || e.key === 'ArrowUp' ? idx + 1 : e.key === 'ArrowLeft' || e.key === 'ArrowDown' ? idx - 1 : e.key === 'Home' ? 0 : e.key === 'End' ? n - 1 : null
      if (k == null) return; e.preventDefault(); onYear(years[Math.min(n - 1, Math.max(0, k))])
    }}>
    <span className="rc-tl-thumb" style={{ width: `${100 / n}%`, transform: `translateX(${(centre * n - 0.5) * 100}%)` }} aria-hidden="true" />
    {years.map(y => <span key={y} className={`rc-tl-y${y === year ? ' is-on' : ''}`} aria-hidden="true">’{String(y).slice(2)}</span>)}
  </div>
}

/** Team-page version: scrub through classes; selecting a state opens that team's commitments filtered to the state. */
export function TeamRecruitMap({ id, team }: { id: string; team: Team }) {
  const dash = useData<DashboardDoc>('recruiting/dashboard.json')
  const [pick, setPick] = useState(0)
  if (!dash.data) return null
  const d = dash.data
  const year = pick || d.latest_ranked_class || d.open_class
  return <div className="rc-map-team">
    <RecruitMap year={year} years={d.classes} onYear={setPick} openClass={d.open_class} match={r => r.team_id === id} matchKey={id} team={team}
      selected="" hint="Opens this class’s commitments from that state." onSelect={s => s && navigate(`/recruiting/high-school/?year=${year}&tab=commits&team=${id}&state=${s}`)} />
  </div>
}
