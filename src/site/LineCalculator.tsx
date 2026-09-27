import { useMemo, useState } from 'react'
import { fmt, Select, TeamLogo, useData, useTeams } from './components'
import type { IndexDoc } from './data'

// Implied line for any two FBS teams, computed in the browser from published numbers only: the same formula the site
// uses for scheduled games (projected margin = home power − away power + home field, zero at a neutral site; win
// probability from a normal with the model's residual sd). Nothing is re-modelled and no market data is involved.

/** Standard normal CDF (Abramowitz & Stegun 7.1.26 error function; absolute error < 1.5e-7). */
function phi(z: number) {
  const x = Math.abs(z) / Math.SQRT2, t = 1 / (1 + 0.3275911 * x)
  const erf = 1 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * Math.exp(-x * x)
  return z >= 0 ? (1 + erf) / 2 : (1 - erf) / 2
}

export default function LineCalculator() {
  const index = useData<IndexDoc>('index.json')
  const dir = useTeams()
  const [away, setAway] = useState('')
  const [home, setHome] = useState('')
  const [neutral, setNeutral] = useState(false)
  const rated = useMemo(() => (index.data?.teams ?? []).filter(t => t.power != null && dir.has(t.team_id)).map(t => ({ ...t, name: dir.get(t.team_id)!.team })).sort((a, b) => a.name.localeCompare(b.name)), [index.data, dir])
  if (!index.data || !rated.length || index.data.meta.hfa == null || index.data.meta.sigma == null) return null
  const { hfa, sigma } = index.data.meta
  const a = rated.find(t => t.team_id === away), h = rated.find(t => t.team_id === home)
  const opts = <><option value="">Choose a team</option>{rated.map(t => <option key={t.team_id} value={t.team_id}>{t.name}</option>)}</>

  let result: { margin: number; pHome: number } | null = null
  if (a && h && a.team_id !== h.team_id) {
    const margin = h.power! - a.power! + (neutral ? 0 : hfa)
    result = { margin, pHome: phi(margin / sigma) }
  }
  const fav = result && (result.margin >= 0 ? h! : a!)
  const pFav = result && Math.max(result.pHome, 1 - result.pHome)
  const size = Math.abs(result?.margin ?? 0)
  const line = !result ? null : size < 0.05 ? 'Pick’em' : `${fav!.name} −${fmt(size)}`

  return <details className="cf-panel cf-calc">
    <summary><span className="cf-calc-title">Line calculator</span><span className="cf-muted cf-small">Pick any two teams for the model’s implied line</span></summary>
    <div className="cf-calc-body">
      <div className="cf-calc-inputs">
        <Select label={neutral ? 'Team A' : 'Away team'} value={away} onChange={setAway}>{opts}</Select>
        <Select label={neutral ? 'Team B' : 'Home team'} value={home} onChange={setHome}>{opts}</Select>
        <Select label="Site" value={neutral ? 'neutral' : 'home'} onChange={v => setNeutral(v === 'neutral')}>
          <option value="home">Home team’s field</option>
          <option value="neutral">Neutral site</option>
        </Select>
      </div>
      {away && home && away === home && <p className="cf-muted cf-small">Pick two different teams.</p>}
      {result && <div className="cf-calc-out" role="status">
        <span className="cf-calc-logos"><TeamLogo id={a!.team_id} name={a!.name} size={32} /><TeamLogo id={h!.team_id} name={h!.name} size={32} /></span>
        <div><span className="cf-mu-tile-k">Model line</span><strong className="cf-mu-tile-v">{line}</strong></div>
        <div><span className="cf-mu-tile-k">Win probability</span><strong className="cf-mu-tile-v">{size < 0.05 ? '50.0%' : `${fav!.name} ${(pFav! * 100).toFixed(1)}%`}</strong></div>
        <div><span className="cf-mu-tile-k">Projected margin</span><strong className="cf-mu-tile-v">{size < 0.05 ? 'Even' : `${fav!.name} by ${fmt(size)}`}</strong><span className="cf-mu-tile-s">{neutral ? 'Neutral site' : `${h!.name} home field: ${fmt(hfa, 1)} pts`}</span></div>
      </div>}
      {!result && <p className="cf-muted cf-small">Uses current CFPi+ ratings and the same formula as the Games table. Negative = that team favored.</p>}
    </div>
  </details>
}
