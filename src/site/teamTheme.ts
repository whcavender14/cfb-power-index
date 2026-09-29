import type { CSSProperties } from 'react'

// Team palette -> CSS vars. Prefers the primary color unless it is near-black/near-white, then tries the alternate.
export function teamTheme(c: string | null, alt: string | null): CSSProperties {
  const rgb = (h: string | null) => { const m = h && /^#?([0-9a-f]{6})$/i.exec(h); return m ? [0, 2, 4].map(i => parseInt(m[1].slice(i, i + 2), 16)) : null }
  const lum = (v: number[]) => (0.2126 * v[0] + 0.7152 * v[1] + 0.0722 * v[2]) / 255
  const ok = (v: number[] | null): v is number[] => !!v && lum(v) > 0.08 && lum(v) < 0.85
  const p = rgb(c), a = rgb(alt)
  const pick = ok(p) ? p : ok(a) ? a : p ?? [29, 111, 192]
  return { ['--team' as string]: c ?? `rgb(${pick.join(' ')})`, ['--team-a' as string]: `rgb(${pick.join(' ')})`, ['--team-rgb' as string]: pick.join(' '),
    ['--team-ink' as string]: lum(p ?? pick) > 0.55 ? '#0b1b33' : '#fff', ['--team-2' as string]: alt ?? (lum(p ?? pick) > 0.55 ? '#0b1b33' : '#fff') }
}

/** Conference brand colors [primary, alternate], keyed by conference slug (matched to the logos in public/logos/conf). */
export const CONF_COLORS: Record<string, [string, string]> = {
  'sec': ['#0b1f4d', '#d8e64a'], 'big-ten': ['#0088ce', '#0b2a4a'], 'big-12': ['#c8102e', '#1c2e5c'],
  'acc': ['#013ca6', '#7fa6e6'], 'pac-12': ['#0b3d91', '#d2232a'], 'american-athletic': ['#c8202f', '#1c3f7a'],
  'conference-usa': ['#0a2d6e', '#d2232a'], 'mid-american': ['#00693c', '#f2c94c'], 'mountain-west': ['#3a2a7a', '#e0301e'],
  'sun-belt': ['#f5a000', '#1c3f7a'], 'fbs-independents': ['#4a5568', '#b8860b'],
}
