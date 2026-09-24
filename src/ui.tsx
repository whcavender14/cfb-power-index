import { useState, type ReactNode } from 'react'
import { ChevronDown, CircleHelp, Info } from 'lucide-react'
import { isNum, pct, signed } from './format'

export const initials = (name: string) => name.split(/\s+/).filter(Boolean).slice(0, 2).map(word => word[0]).join('').toUpperCase()

export function TeamLogo({ name, src, size = 36 }: { name: string; src?: string | null; size?: number }) {
  const [failed, setFailed] = useState(false)
  return <span className="logo" style={{ width: size, height: size }} aria-hidden="true">
    {src && !failed
      ? <img src={src} alt="" loading="lazy" decoding="async" onError={() => setFailed(true)} />
      : <span className="logo-mono" style={{ fontSize: Math.max(9, Math.round(size * 0.32)) }}>{initials(name)}</span>}
  </span>
}

export function Tip({ text, align = 'center' }: { text: string; align?: 'start' | 'center' | 'end' }) {
  return <span className={`tip tip-${align}`}>
    <button type="button" className="tip-btn" aria-label={text}><CircleHelp size={13} /></button>
    <span role="tooltip" className="tip-body">{text}</span>
  </span>
}

export const Missing = () => <span className="missing" title="Data unavailable" aria-label="Data unavailable">—</span>

export function Delta({ value }: { value: number | null }) {
  if (!isNum(value)) return <Missing />
  const rounded = Math.round(value * 10) / 10
  const tone = rounded > 0 ? 'pos' : rounded < 0 ? 'neg' : 'zero'
  return <span className={`delta ${tone}`}>{tone !== 'zero' && <i className="tri" aria-hidden="true" />}{signed(value)}</span>
}

/** Signed rating with a diverging bar centred on the FBS average. */
export function PowerValue({ value, scale }: { value: number | null; scale: number }) {
  if (!isNum(value)) return <Missing />
  const width = Math.min(50, (Math.abs(value) / scale) * 50)
  return <span className="power">
    <span className="dbar" aria-hidden="true"><i className={value >= 0 ? 'up' : 'down'} style={{ width: `${width}%` }} /></span>
    <span className="num num-strong">{signed(value)}</span>
  </span>
}

export function Probability({ value }: { value: number | null }) {
  if (!isNum(value)) return <Missing />
  return <span className="prob">
    <span className="num">{pct(value)}</span>
    <span className="prob-bar" aria-hidden="true"><i style={{ width: `${value * 100}%` }} /></span>
  </span>
}

export function SelectField({ label, value, onChange, children, className = '', hideLabel = true, ariaLabel }: {
  label: string; value: string; onChange: (value: string) => void; children: ReactNode; className?: string; hideLabel?: boolean; ariaLabel?: string
}) {
  const control = <span className="field select">
    <select aria-label={ariaLabel ?? label} value={value} onChange={event => onChange(event.target.value)}>{children}</select>
    <ChevronDown size={15} className="chev" aria-hidden="true" />
  </span>
  return hideLabel ? <label className={className}>{control}</label>
    : <label className={`stack ${className}`}><span className="micro-label">{label}</span>{control}</label>
}

/** Numbered kicker ("01 — Power ratings") that marks each section of the platform. */
export function Kicker({ index, children }: { index?: string; children: ReactNode }) {
  return <div className="kicker">{index && <span className="kicker-num">{index}</span>}<span className="kicker-text">{children}</span></div>
}

export function SectionHead({ index, eyebrow, title, id, children }: { index: string; eyebrow: string; title: ReactNode; id?: string; children?: ReactNode }) {
  return <header className="section-head">
    <div><Kicker index={index}>{eyebrow}</Kicker><h2 id={id}>{title}</h2></div>
    {children && <div className="section-aside">{children}</div>}
  </header>
}

export function Notice({ children, role }: { children: ReactNode; role?: 'status' | 'alert' }) {
  return <div className="notice" role={role}><Info size={16} aria-hidden="true" /><div>{children}</div></div>
}

export function EmptyState({ title, children, action, role }: { title: string; children?: ReactNode; action?: ReactNode; role?: 'status' | 'alert' }) {
  return <div className="empty" role={role}><h3>{title}</h3>{children && <p>{children}</p>}{action}</div>
}

export function StatCell({ label, children }: { label: string; children: ReactNode }) {
  return <div className="stat"><span className="tag">{label}</span><div className="stat-body">{children}</div></div>
}

export function TeamName({ name, logo, sub }: { name: string; logo: string | null; sub?: string | null }) {
  return <span className="team-cell"><TeamLogo name={name} src={logo} /><span><span className="team-name">{name}</span>{sub && <span className="team-sub">{sub}</span>}</span></span>
}

export function Sources({ children, extra }: { children: ReactNode; extra?: ReactNode }) {
  return <div className="sources">
    <span>Sources: supplied R model outputs · Team metadata &amp; logos via <a href="https://collegefootballdata.com/" target="_blank" rel="noreferrer">CollegeFootballData</a>{extra && <> · {extra}</>}</span>
    <span>{children}</span>
  </div>
}
