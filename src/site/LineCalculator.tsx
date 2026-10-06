import { useMemo, useState } from 'react'
import { fmt, pctText, Select, TeamLogo, useData, useTeams } from './components'
import type { IndexDoc } from './data'
import { Quality, QUALITY_INFO } from './games'
import { teamTheme } from './teamTheme'

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
  const size = Math.abs(result?.margin ?? 0)
  // Watchability = the site's Matchup Quality (strength from current ranks x closeness of the model win probability).
  const ranked = (index.data.teams ?? []).filter(t => t.rank != null).length
  const strength = (r: number | null) => r != null && ranked > 1 ? 1 - Math.sqrt((r - 1) / (ranked - 1)) : 0
  const watch = result ? Math.round(100 * ((strength(a!.rank) + strength(h!.rank)) / 2) * (1 - (2 * result.pHome - 1) ** 2)) : null
  const ab = (t: { team_id: string; name: string }) => dir.get(t.team_id)?.abbreviation ?? t.name
  const rk = (n: number | null) => n == null ? '—' : `#${n}`
  const share = (r: number | null) => r != null && ranked > 1 ? 1 - (r - 1) / (ranked - 1) : 0
  const cmp = result ? [['Overall', a!.rank, h!.rank], ['Offense', a!.off_rank, h!.off_rank], ['Defense', a!.def_rank, h!.def_rank]].map(([label, x, y]) => ({ label: label as string, a: x as number | null, h: y as number | null, sa: share(x as number | null), sh: share(y as number | null) })) : []
  const theme = (id: string) => teamTheme(dir.get(id)?.color ?? null, dir.get(id)?.alt_color ?? null)
  const rec = (t: { wins: number | null; losses: number | null }) => t.wins == null ? '—' : `${t.wins}–${t.losses}`
  const profile = result ? [
    { k: 'Record', a: rec(a!), h: rec(h!) },
    { k: 'Rating', a: a!.power != null ? fmt(a!.power, 1) : '—', h: h!.power != null ? fmt(h!.power, 1) : '—' },
    { k: 'Strength of schedule', a: rk(a!.sos_rank), h: rk(h!.sos_rank) },
    { k: 'Résumé rank', a: rk(a!.resume_rank), h: rk(h!.resume_rank) },
    { k: 'Playoff odds', a: pctText(a!.p_playoff) ?? '—', h: pctText(h!.p_playoff) ?? '—' },
  ] : []
  const line = !result ? null : size < 0.05 ? 'Pick’em' : `${fav!.name} −${fmt(size)}`

  const side = (t: typeof a, label: string, value: string, set: (v: string) => void) => <div className="cf-calc-side">
    <span className="cf-calc-logo">{t ? <TeamLogo id={t.team_id} name={t.name} size={44} /> : null}</span>
    <Select label={label} value={value} onChange={set}>{opts}</Select>
  </div>
  const site = <Select label="Site" value={neutral ? 'neutral' : 'home'} onChange={v => setNeutral(v === 'neutral')}>
    <option value="home">Home team’s field</option>
    <option value="neutral">Neutral site</option>
  </Select>

  return <details className="cf-calc">
    <summary><span className="cf-calc-title">Compare teams</span><span className="cf-calc-hint">Any two FBS teams · model line, win probability &amp; matchup</span><span className="cf-calc-chev" aria-hidden="true" /></summary>
    <div className="cf-calc-body">
      <div className="cf-calc-match">
        {side(a, neutral ? 'Team A' : 'Away', away, setAway)}
        <span className="cf-calc-at" aria-hidden="true">{neutral ? 'vs' : 'at'}</span>
        {side(h, neutral ? 'Team B' : 'Home', home, setHome)}
        <div className="cf-calc-site">{site}</div>
      </div>
      {away && home && away === home && <p className="cf-muted cf-small">Pick two different teams.</p>}
      {result && <div className="cf-calc-out" role="status" key={`${a!.team_id}-${h!.team_id}-${neutral}`}>
        <div className="cf-calc-teams">
          {[{ t: a!, p: 1 - result.pHome }, { t: h!, p: result.pHome }].map(({ t, p }) => <div key={t.team_id} className={`cf-calc-row${p >= 0.5 && size >= 0.05 ? ' is-fav' : ''}`} style={theme(t.team_id)}>
            <TeamLogo id={t.team_id} name={t.name} size={28} />
            <span className="cf-calc-name">{t.name}</span>
            <span className="cf-calc-bar" aria-hidden="true"><i style={{ width: `${(p * 100).toFixed(1)}%` }} /></span>
            <span className="cf-calc-pct cf-num">{(p * 100).toFixed(1)}%</span>
          </div>)}
          <div className="cf-calc-cmp">
            <div className="cf-calc-cmphead"><span>{ab(a!)}</span><span>{ab(h!)}</span></div>
            {cmp.map(m => <div key={m.label} className="cf-calc-cmprow">
              <span className="cf-calc-k">{m.label}</span>
              <span className="cf-calc-v cf-num">{rk(m.a)}</span>
              <span className="cf-calc-track" aria-hidden="true">
                <span className="l" style={theme(a!.team_id)}><i className={m.sa >= m.sh ? 'lead' : ''} style={{ width: `${(m.sa * 100).toFixed(1)}%` }} /></span>
                <span className="r" style={theme(h!.team_id)}><i className={m.sh >= m.sa ? 'lead' : ''} style={{ width: `${(m.sh * 100).toFixed(1)}%` }} /></span>
              </span>
              <span className="cf-calc-v cf-num">{rk(m.h)}</span>
            </div>)}
          </div>
        </div>
        <dl className="cf-calc-facts">
          <div><dt>Model line</dt><dd className="cf-num">{line}</dd></div>
          <div><dt title={QUALITY_INFO}>Watchability</dt><dd><Quality value={watch} /></dd></div>
          <div className="cf-calc-hd"><span>{ab(a!)}</span><span>Team profile</span><span>{ab(h!)}</span></div>
          {profile.map(r => <div key={r.k} className="cf-calc-pr"><dd className="cf-num">{r.a}</dd><dt>{r.k}</dt><dd className="cf-num">{r.h}</dd></div>)}
        </dl>
      </div>}
      {!result && <p className="cf-muted cf-small">Uses current CFPi+ ratings and the same formula as the Games table. Negative = that team favored.</p>}
    </div>
  </details>
}
