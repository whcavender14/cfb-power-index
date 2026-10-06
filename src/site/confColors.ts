// Conference line colours for the comparison chart and its PNG: each conference's own colour from the theme table
// (teamTheme.ts), falling back to its alternate where the primary would be confused with a conference already
// drawn or would barely show on the page. Computed once over every conference, in a fixed order, so a conference
// keeps its colour however the toggles are set.
import { CONF_COLORS } from './teamTheme.ts'

// Power conferences claim their colours first, then the rest in order of how many teams they put on the chart.
const ORDER = ['sec', 'big-ten', 'big-12', 'acc', 'pac-12', 'american-athletic', 'mountain-west', 'sun-belt', 'conference-usa', 'mid-american', 'fbs-independents']
const MIN_DISTINCT = 28   // CIE76 ΔE between any two lines
const MIN_CONTRAST = { light: 1.8, dark: 2.5 }  // against the page background (lines are 2.5px; logos carry the identity too)

const rgb = (hex: string) => [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16) / 255)
const lin = (c: number) => c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4
const luminance = (hex: string) => { const [r, g, b] = rgb(hex).map(lin); return 0.2126 * r + 0.7152 * g + 0.0722 * b }
const contrast = (a: string, b: string) => { const x = luminance(a), y = luminance(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05) }
function lab(hex: string): [number, number, number] {
  const [r, g, b] = rgb(hex).map(lin)
  const x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047, y = 0.2126 * r + 0.7152 * g + 0.0722 * b, z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
  const f = (t: number) => t > 0.008856 ? Math.cbrt(t) : 7.787 * t + 16 / 116
  return [116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))]
}
const distance = (a: string, b: string) => { const p = lab(a), q = lab(b); return Math.hypot(p[0] - q[0], p[1] - q[1], p[2] - q[2]) }

function fromLab([L, A, B]: [number, number, number]): string {
  const fy = (L + 16) / 116, fx = fy + A / 500, fz = fy - B / 200
  const inv = (t: number) => t ** 3 > 0.008856 ? t ** 3 : (t - 16 / 116) / 7.787
  const x = inv(fx) * 0.95047, y = inv(fy), z = inv(fz) * 1.08883
  const lr = [3.2406 * x - 1.5372 * y - 0.4986 * z, -0.9689 * x + 1.8758 * y + 0.0415 * z, 0.0557 * x - 0.204 * y + 1.057 * z]
  const gam = (c: number) => Math.round(255 * Math.min(1, Math.max(0, c <= 0.0031308 ? 12.92 * c : 1.055 * c ** (1 / 2.4) - 0.055)))
  return '#' + lr.map(c => gam(c).toString(16).padStart(2, '0')).join('')
}
/** The nearest shade that clears `ok`: first lighter or darker in the same hue, then with the hue turned slightly. */
function nudge(hex: string, ok: (c: string) => boolean): string | null {
  const [L, A, B] = lab(hex)
  const tries: { cost: number; c: string }[] = []
  for (const turn of [0, 18, -18, 36, -36]) {
    const t = turn * Math.PI / 180, a = A * Math.cos(t) - B * Math.sin(t), b = A * Math.sin(t) + B * Math.cos(t)
    for (let d = 0; d <= 48; d += 4) for (const sign of d ? [1, -1] : [1]) tries.push({ cost: d / 4 + Math.abs(turn) / 6, c: fromLab([Math.min(95, Math.max(8, L + sign * d)), a, b]) })
  }
  return tries.sort((x, y) => x.cost - y.cost).find(t => ok(t.c))?.c ?? null
}

export function conferenceColors(dark: boolean): Record<string, string> {
  const bg = dark ? '#08111f' : '#ffffff'
  const out: Record<string, string> = {}
  const gap = (c: string) => Math.min(...Object.values(out).map(t => distance(c, t)), 999)
  const ok = (c: string) => contrast(c, bg) >= (dark ? MIN_CONTRAST.dark : MIN_CONTRAST.light) && gap(c) >= MIN_DISTINCT
  for (const slug of ORDER) {
    const [primary, alt] = CONF_COLORS[slug] ?? ['#4a5568', '#b8860b']
    // Primary if distinct and visible; else the alternate; else the lighter/darker shade of whichever is closest to working.
    out[slug] = ok(primary) ? primary : ok(alt) ? alt
      : nudge(primary, ok) ?? nudge(alt, ok) ?? [primary, alt].sort((a, b) => gap(b) - gap(a))[0]
  }
  return out
}
