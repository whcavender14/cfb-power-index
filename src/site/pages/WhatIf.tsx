import { useMemo, useState } from 'react'
import { X } from 'lucide-react'
import { DataGate, Freshness, Info, PageHead, pctText, Select, TeamLink, TeamLogo, useData, useTeams } from '../components'
import type { Game, GamesDoc, PlayoffDoc, ScenarioDoc } from '../data'
import { kickoffText } from '../games'
import { Link, useQueryParam } from '../router'
import { aggregate, COUNTS_BELOW, decode, formatPicks, matching, parsePicks, WARN_BELOW, type Pick, type TeamResult } from '../scenario'

const SHOW = 25

/** A share of the matching seasons: a percentage, or "k of n" when there are too few seasons for percentages. */
function Share({ k, n, base }: { k: number; n: number; base?: number | null }) {
  if (n < COUNTS_BELOW) return <span className="cf-num">{k} of {n}</span>
  const p = k / n
  const d = base == null ? null : p - base
  return <span className="cf-num">{pctText(p)}{d != null && Math.abs(d) >= 0.0005 && <span className={`cf-delta ${d > 0 ? 'is-up' : 'is-down'}`}> {d > 0 ? '▲' : '▼'}{Math.abs(d * 100).toFixed(1)}</span>}</span>
}

function GamePicker({ g, pick, onPick }: { g: Game; pick: Pick | undefined; onPick: (side: 'home' | 'away' | null) => void }) {
  const side = (s: 'home' | 'away') => {
    const id = s === 'home' ? g.home_id : g.away_id, name = s === 'home' ? g.home_team : g.away_team
    const p = s === 'home' ? g.win_prob_home : g.win_prob_home == null ? null : 1 - g.win_prob_home
    const on = pick?.side === s
    return <button type="button" className={`cf-pick${on ? ' is-on' : ''}`} aria-pressed={on} onClick={() => onPick(on ? null : s)}>
      <TeamLogo id={id} name={name} size={20} /><span className="cf-pick-name">{name}</span><span className="cf-pick-p cf-num">{pctText(p, 0)}</span>
    </button>
  }
  return <li className="cf-pickrow">
    <span className="cf-pick-when cf-muted cf-small">{kickoffText(g)}</span>
    <span className="cf-pick-pair">{side('away')}<span className="cf-at">{g.neutral ? 'vs' : 'at'}</span>{side('home')}</span>
  </li>
}

export default function WhatIf() {
  const scen = useData<ScenarioDoc>('scenario.json')
  const gamesDoc = useData<GamesDoc>('games.json')
  const playoff = useData<PlayoffDoc>('playoff.json')
  const directory = useTeams()
  const [param, setParam] = useQueryParam('pick')
  const [weekParam, setWeek] = useQueryParam('week')
  const [all, setAll] = useState(false)
  const [focus, setFocus] = useState('')
  const decoded = useMemo(() => scen.data ? decode(scen.data) : null, [scen.data])
  const picks = parsePicks(param)
  const setPicks = (p: Pick[]) => setParam(formatPicks(p))

  return <>
    <PageHead title="What if?" lede={<>Pick winners of upcoming games. The page keeps only the simulated seasons in which those results happened and recomputes the odds from them. Nothing is re-simulated, and a pick does not change any team’s rating. For the unconditional odds, see <Link to="/playoff/">Playoff</Link>.</>} />
    <DataGate source={scen} label="Scenario data">{() => <DataGate source={gamesDoc} label="Games">{({ meta, games }) => <DataGate source={playoff} label="Playoff odds">{po => {
      const d = decoded!
      const future = games.filter(g => g.status === 'scheduled' && d.games.has(g.game_id))
      const byId = new Map(games.map(g => [g.game_id, g]))
      const valid = picks.filter(p => d.games.has(p.gameId))
      const ignored = picks.length - valid.length
      const sims = matching(d, valid)
      const n = sims.length
      const res = aggregate(d, sims)
      const base = new Map(po.teams.map(t => [t.team_id, t]))
      const weeks = [...new Set(future.map(g => g.week))].sort((a, b) => a - b)
      const week = weekParam ? Number(weekParam) : weeks[0]
      const shown = future.filter(g => g.week === week && (g.home_fbs && g.away_fbs))
      const pickOf = (id: string) => valid.find(p => p.gameId === id)
      const setPick = (g: Game, side: 'home' | 'away' | null) => setPicks([...valid.filter(p => p.gameId !== g.game_id), ...(side ? [{ gameId: g.game_id, side }] : [])])
      const involved = new Set(valid.flatMap(p => { const g = byId.get(p.gameId); return g ? [g.home_id, g.away_id] : [] }))
      const rows = [...res.values()].sort((a, b) => b.playoff - a.playoff || b.conf - a.conf || (base.get(b.team_id)?.p_playoff ?? 0) - (base.get(a.team_id)?.p_playoff ?? 0))
      const list = all ? rows : rows.filter((r, i) => i < SHOW || involved.has(r.team_id))
      const f: TeamResult | undefined = res.get(focus) ?? rows[0]
      return <>
        <Freshness meta={meta} sims />
        <div className="cf-whatif-layout">
        <section className="cf-panel cf-whatif-picks" aria-labelledby="wi-pick">
          <div className="cf-panel-head">
            <h2 id="wi-pick" className="cf-h2">Pick winners</h2>
            <Select label="Week" value={String(week)} onChange={setWeek}>{weeks.map(w => <option key={w} value={w}>Week {w}</option>)}</Select>
          </div>
          <p className="cf-small cf-muted">FBS-vs-FBS games. Percentages are the model’s win probabilities. Click a team to pick it; click again to clear.</p>
          <ul className="cf-picklist">{shown.map(g => <GamePicker key={g.game_id} g={g} pick={pickOf(g.game_id)} onPick={s => setPick(g, s)} />)}</ul>
        </section>
        {valid.length > 0 && <a href="#wi-status" className="cf-whatif-jump" onClick={e => { e.preventDefault(); document.getElementById('wi-status')?.scrollIntoView() }}>
          <span><strong className="cf-num">{n.toLocaleString()}</strong> of {d.n.toLocaleString()} seasons match</span><span>See odds ↓</span></a>}
        <div className="cf-whatif-side" id="wi-status">
        <div className={`cf-whatif-status${n < WARN_BELOW ? ' is-warn' : ''}`} role="status">
          <div className="cf-chips">{valid.map(p => { const g = byId.get(p.gameId)!; const w = p.side === 'home' ? g.home_team : g.away_team; const l = p.side === 'home' ? g.away_team : g.home_team
            return <span key={p.gameId} className="cf-chip">{w} over {l} <span className="cf-muted">(Wk {g.week})</span><button type="button" aria-label={`Remove pick: ${w} over ${l}`} onClick={() => setPicks(valid.filter(x => x.gameId !== p.gameId))}><X size={13} /></button></span> })}
            {valid.length > 0 && <button type="button" className="cf-btn" onClick={() => setPicks([])}>Clear all</button>}</div>
          <p><strong className="cf-num">{n.toLocaleString()}</strong> of {d.n.toLocaleString()} simulated seasons match{valid.length === 0 ? ' (no picks: these are the published odds)' : ''}.
            {n === 0 ? ' This combination never happened in the simulations, so there is nothing to show. Remove a pick.'
              : n < COUNTS_BELOW ? ` Too few seasons for percentages (fewer than ${COUNTS_BELOW}); counts are shown instead. Treat them as anecdotes.`
              : n < WARN_BELOW ? ` Fewer than ${WARN_BELOW} seasons: a 50% figure could be off by about 10 points either way. Read changes loosely.` : ''}
            {ignored > 0 && ` ${ignored} pick${ignored === 1 ? ' is' : 's are'} for games already played or not in this week's simulation and ${ignored === 1 ? 'was' : 'were'} ignored.`}
            <Info text={`Each pick keeps only the simulated seasons in which that team won. With ${d.n.toLocaleString()} seasons, each coin-flip pick roughly halves the pool, so a handful of picks leaves few seasons. Below ${WARN_BELOW} a warning appears; below ${COUNTS_BELOW} only counts are shown.`} label="About matching seasons" /></p>
        </div>

        {n > 0 && <div className="cf-whatif-grid">
          <section className="cf-panel" aria-labelledby="wi-res">
            <div className="cf-panel-head"><h2 id="wi-res" className="cf-h2">Odds in these seasons</h2>
              <label className="cf-check"><input type="checkbox" checked={all} onChange={e => setAll(e.target.checked)} /> All teams</label></div>
            <div className="cf-table-wrap"><table className="cf-table cf-table-compact">
              <thead><tr><th scope="col" className="cf-th-start">Team</th><th scope="col" className="cf-th-end">Playoff</th><th scope="col" className="cf-th-end cf-hide-sm">Bye</th>
                <th scope="col" className="cf-th-end">Conf. title</th><th scope="col" className="cf-th-end cf-hide-sm">Title</th><th scope="col" className="cf-th-end">Exp. record</th></tr></thead>
              <tbody>{list.map(r => { const b = base.get(r.team_id); const t = directory.get(r.team_id)
                return <tr key={r.team_id} className={involved.has(r.team_id) ? 'is-picked' : ''} onClick={() => setFocus(r.team_id)}>
                  <td><TeamLink id={r.team_id} size={20} /></td>
                  <td className="cf-td-end"><Share k={r.playoff} n={n} base={valid.length ? b?.p_playoff : null} /></td>
                  <td className="cf-td-end cf-hide-sm"><Share k={r.bye} n={n} base={valid.length ? b?.p_bye : null} /></td>
                  <td className="cf-td-end">{t?.conference === 'FBS Independents' ? '—' : <Share k={r.conf} n={n} base={valid.length ? b?.p_conf : null} />}</td>
                  <td className="cf-td-end cf-hide-sm"><Share k={r.champ} n={n} base={valid.length ? b?.p_champ : null} /></td>
                  <td className="cf-td-end cf-num">{(r.wins / n).toFixed(1)}–{((d.teamGames.get(r.team_id) ?? 0) - r.wins / n).toFixed(1)}</td>
                </tr> })}</tbody>
            </table></div>
            <p className="cf-small cf-muted">{valid.length ? '▲▼ = change in percentage points from the published odds. ' : ''}Expected record is the mean over the matching seasons (regular season; conference title games are not simulated). Tap a row for seed odds.</p>
          </section>
          {f && <section className="cf-panel" aria-labelledby="wi-seed">
            <div className="cf-panel-head"><h2 id="wi-seed" className="cf-h2">Seed odds</h2>
              <Select label="Team" value={f.team_id} onChange={setFocus}>{[...res.values()].sort((a, b) => (directory.get(a.team_id)?.team ?? '').localeCompare(directory.get(b.team_id)?.team ?? '')).map(r => <option key={r.team_id} value={r.team_id}>{directory.get(r.team_id)?.team}</option>)}</Select></div>
            <p><TeamLink id={f.team_id} size={24} /> makes the field in <Share k={f.playoff} n={n} /> of these seasons.</p>
            <div className="cf-seedbars" role="img" aria-label={f.seeds.map((c, i) => `Seed ${i + 1}: ${c} seasons`).join(', ')}>
              {f.seeds.map((c, i) => <span key={i} className="cf-seedbar"><span className="cf-dist-val">{c ? (n < COUNTS_BELOW ? c : pctText(c / n, 0)) : ''}</span><i style={{ height: `${Math.max(...f.seeds) ? (c / Math.max(...f.seeds)) * 100 : 0}%` }} /><b>{i + 1}</b></span>)}
            </div>
            <p className="cf-small cf-muted">Share of matching seasons with each seed{n < COUNTS_BELOW ? ' (counts)' : ''}. Seeds 1–4 get byes.</p>
          </section>}
        </div>}
        </div>
        </div>
      </>
    }}</DataGate>}</DataGate>}</DataGate>
  </>
}
