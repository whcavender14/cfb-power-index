import { useEffect, useLayoutEffect, useRef, useState, type KeyboardEvent, type PointerEvent } from 'react'
import { fmtSigned } from './components'
import type { HistoryPoint } from './data'

// Line chart of CFPi+ ratings over the season. Values come straight from history.json; a week the site has no
// rating for stays a gap in the line (never interpolated). Reconstructed weeks use hollow markers.
export type ChartSeries = { id: string; name: string; slot: number; power: (number | null)[]; rank: (number | null)[] }

const PAD = { top: 16, right: 112, bottom: 30, left: 44 }
const PAD_NARROW = { top: 16, right: 16, bottom: 30, left: 40 }

function useWidth<T extends HTMLElement>() {
  const ref = useRef<T>(null)
  const [w, setW] = useState(0)
  useLayoutEffect(() => {
    if (!ref.current) return
    const ro = new ResizeObserver(([e]) => setW(Math.round(e.contentRect.width)))
    ro.observe(ref.current)
    return () => ro.disconnect()
  }, [])
  return [ref, w] as const
}

function niceTicks(lo: number, hi: number): number[] {
  const span = Math.max(hi - lo, 1), raw = span / 5
  const step = [1, 2, 2.5, 5, 10].map(m => m * 10 ** Math.floor(Math.log10(raw))).find(s => span / s <= 6) ?? raw
  const out: number[] = []
  for (let v = Math.floor(lo / step) * step; v <= Math.ceil(hi / step) * step + 1e-9; v += step) out.push(Math.round(v * 100) / 100)
  return out
}

export default function HistoryChart({ points, series, height = 300, label }: { points: HistoryPoint[]; series: ChartSeries[]; height?: number; label: string }) {
  const [wrap, width] = useWidth<HTMLDivElement>()
  const [hover, setHover] = useState<number | null>(null)
  const narrow = width < 560
  const pad = narrow ? PAD_NARROW : PAD

  const weeks = points.filter(p => p.week !== null).map(p => p.week as number)
  // The axis always starts at Week 1 (or Week 0 if rated), so weeks without a rating show as gaps, never as a straight line.
  const first = weeks.length ? Math.min(1, ...weeks) : 0, last = weeks.length ? Math.max(...weeks) : 0
  const slots: { label: string; short: string; point: number | null }[] = []
  const pre = points.findIndex(p => p.source === 'preseason')
  if (pre >= 0) slots.push({ label: 'Preseason', short: 'Pre', point: pre })
  for (let w = first; w <= last && weeks.length; w++) {
    const i = points.findIndex(p => p.week === w)
    slots.push({ label: `Week ${w}`, short: `W${w}`, point: i >= 0 ? i : null })
  }

  const vals = series.flatMap(s => s.power).filter((v): v is number => v !== null)
  const lo = Math.min(0, ...vals), hi = Math.max(0, ...vals)
  const ticks = niceTicks(lo, hi)
  const yMin = ticks[0], yMax = ticks[ticks.length - 1]
  const iw = Math.max(width - pad.left - pad.right, 10), ih = height - pad.top - pad.bottom
  const x = (k: number) => pad.left + (slots.length <= 1 ? iw / 2 : (k / (slots.length - 1)) * iw)
  const y = (v: number) => pad.top + (1 - (v - yMin) / (yMax - yMin || 1)) * ih

  // Direct labels at each line's last value, nudged apart vertically (desktop only).
  const ends = series.map(s => {
    let k = slots.length - 1
    while (k >= 0 && (slots[k].point === null || s.power[slots[k].point!] === null)) k--
    return { s, k, y: k >= 0 ? y(s.power[slots[k].point!]!) : NaN }
  }).filter(e => e.k >= 0).sort((a, b) => a.y - b.y)
  for (let i = 1; i < ends.length; i++) if (ends[i].y - ends[i - 1].y < 15) ends[i].y = ends[i - 1].y + 15

  const move = (e: PointerEvent<SVGRectElement>) => {
    const r = e.currentTarget.getBoundingClientRect()
    const px = e.clientX - r.left
    const k = Math.round(((px) / (r.width || 1)) * (slots.length - 1))
    setHover(Math.max(0, Math.min(slots.length - 1, k)))
  }
  const key = (e: KeyboardEvent<SVGSVGElement>) => {
    if (e.key === 'ArrowRight' || e.key === 'ArrowLeft') {
      e.preventDefault()
      setHover(h => Math.max(0, Math.min(slots.length - 1, (h ?? slots.length - 1) + (e.key === 'ArrowRight' ? 1 : -1))))
    } else if (e.key === 'Escape') setHover(null)
  }
  useEffect(() => { if (hover !== null && hover >= slots.length) setHover(null) }, [hover, slots.length])

  const hv = hover !== null ? slots[hover] : null
  const tipLeft = hover !== null ? x(hover) : 0
  return <div className="cf-hist" ref={wrap}>
    {width > 0 && <svg width={width} height={height} role="img" aria-label={label} tabIndex={0} onKeyDown={key} onBlur={() => setHover(null)} className="cf-hist-svg">
      {ticks.map(t => <g key={t}>
        <line x1={pad.left} x2={pad.left + iw} y1={y(t)} y2={y(t)} className={t === 0 ? 'cf-hist-zero' : 'cf-hist-grid'} />
        <text x={pad.left - 8} y={y(t)} dy="0.32em" textAnchor="end" className="cf-hist-tick">{t > 0 ? `+${t}` : t < 0 ? `−${Math.abs(t)}` : '0'}</text>
      </g>)}
      {slots.map((sl, k) => <text key={k} x={x(k)} y={height - 8} textAnchor="middle" className="cf-hist-tick">{narrow ? sl.short : sl.label.replace('Preseason', 'Pre')}</text>)}
      {hv && <line x1={x(hover!)} x2={x(hover!)} y1={pad.top} y2={pad.top + ih} className="cf-hist-cross" />}
      {series.map(s => {
        const segs: string[] = []; let cur = ''
        slots.forEach((sl, k) => {
          const v = sl.point === null ? null : s.power[sl.point]
          if (v === null) { if (cur) segs.push(cur); cur = ''; return }
          cur += `${cur ? 'L' : 'M'}${x(k).toFixed(1)},${y(v).toFixed(1)}`
        })
        if (cur) segs.push(cur)
        return <g key={s.id} className={`cf-series-${s.slot}`}>
          {segs.map((d, i) => <path key={i} d={d} className="cf-hist-line" />)}
          {slots.map((sl, k) => {
            const v = sl.point === null ? null : s.power[sl.point]
            if (v === null) return null
            const hollow = points[sl.point!].source !== 'published'
            return <circle key={k} cx={x(k)} cy={y(v)} r={hover === k ? 5.5 : 4} className={hollow ? 'cf-hist-dot is-hollow' : 'cf-hist-dot'} />
          })}
        </g>
      })}
      {!narrow && ends.map(e => <text key={e.s.id} x={pad.left + iw + 10} y={e.y} dy="0.32em" className="cf-hist-end">
        <tspan className={`cf-series-${e.s.slot} cf-hist-key`}>●</tspan> {e.s.name}</text>)}
      <rect x={pad.left - 12} y={pad.top} width={iw + 24} height={ih} fill="transparent" onPointerMove={move} onPointerDown={move} onPointerLeave={() => setHover(null)} />
    </svg>}
    {hv && <div className={`cf-hist-tip${tipLeft > width * 0.6 ? ' is-left' : ''}`} style={{ left: tipLeft }} role="status">
      <p className="cf-hist-tip-head">{hv.label}{hv.point !== null && points[hv.point].source === 'reconstructed' ? ' · reconstructed' : ''}</p>
      {hv.point === null ? <p className="cf-muted">No rating published for this week</p> :
        [...series].sort((a, b) => (b.power[hv.point!] ?? -1e9) - (a.power[hv.point!] ?? -1e9)).map(s => <p key={s.id} className="cf-hist-tip-row">
          <span className={`cf-series-${s.slot} cf-hist-key`} aria-hidden="true">●</span>
          <span className="cf-hist-tip-name">{s.name}</span>
          <span className="cf-num">{fmtSigned(s.power[hv.point!]) ?? '—'}</span>
          <span className="cf-num cf-muted">{s.rank[hv.point!] != null ? `No. ${s.rank[hv.point!]}` : ''}</span>
        </p>)}
    </div>}
  </div>
}

/** Accessible table of the same values (week × team: rating and rank). */
export function HistoryTable({ points, series }: { points: HistoryPoint[]; series: ChartSeries[] }) {
  return <div className="cf-table-wrap"><table className="cf-table cf-table-compact">
    <thead><tr><th scope="col" className="cf-th-start">Week</th>{series.map(s => <th key={s.id} scope="col" className="cf-th-end">{s.name}</th>)}</tr></thead>
    <tbody>{points.map((p, i) => <tr key={i}>
      <th scope="row" className="cf-th-start">{p.label}{p.source === 'reconstructed' ? <span className="cf-muted"> (reconstructed)</span> : null}</th>
      {series.map(s => <td key={s.id} className="cf-td-end cf-num">{s.power[i] == null ? '—' : <>{fmtSigned(s.power[i])} <span className="cf-small">No. {s.rank[i]}</span></>}</td>)}
    </tr>)}</tbody>
  </table></div>
}
