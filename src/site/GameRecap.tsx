import { useEffect, useMemo, useState } from 'react'
import { fmt, Info, TeamLogo, useData, useTeams } from './components'
import { teamTheme } from './teamTheme'
import { load, type Game, type HistoryDoc } from './data'
import { gradePick, useReview } from './games'
import { PlayerLink } from './player'

// Recap of a finished game: the score against the model's pre-game expectation, team totals and player lines summed from
// the CollegeFootballData box-score rows already published in player/<id>.json. Display only: nothing here feeds the model.

type PlayerIndex = { players: [string, string, string, string | null, number | null][] }   // athlete_id, name, team_id, position, jersey
type PlayerDoc = { player: { athlete_id: string; name: string; position: string | null; jersey: number | null; game_cols: string[]; games: (string | number | boolean | null)[][] } }
type Line = { id: string; name: string; pos: string; s: Record<string, number> }

const NUM = ['pass_cmp', 'pass_att', 'pass_yds', 'pass_td', 'pass_int', 'rush_car', 'rush_yds', 'rush_td', 'rec', 'rec_yds', 'rec_td', 'tkl', 'tfl', 'sacks', 'int', 'pd', 'qbh', 'fum_lost'] as const

/** Every listed player's box-score line for one game (season + week + team), fetched in small batches. */
function useBox(g: Game, season: number) {
  const index = useData<PlayerIndex>('players.json')
  const [state, setState] = useState<{ lines: Map<string, Line[]>; done: boolean; total: number }>({ lines: new Map(), done: false, total: 0 })
  const ids = useMemo(() => (index.data?.players ?? []).filter(p => p[2] === g.home_id || p[2] === g.away_id), [index.data, g.home_id, g.away_id])
  useEffect(() => {
    if (!index.data) return
    let live = true
    const out = new Map<string, Line[]>([[g.home_id, []], [g.away_id, []]])
    setState({ lines: out, done: false, total: ids.length })
    ;(async () => {
      for (let i = 0; i < ids.length; i += 12) {
        const batch = await Promise.all(ids.slice(i, i + 12).map(p => load<PlayerDoc>(`player/${p[0]}.json`).catch(() => null)))
        if (!live) return
        for (const doc of batch) {
          const p = doc?.player; if (!p) continue
          const c = (k: string) => p.game_cols.indexOf(k)
          const row = p.games.find(r => r[c('season')] === season && r[c('week')] === g.week && (r[c('team_id')] === g.home_id || r[c('team_id')] === g.away_id))
          if (!row) continue
          const s: Record<string, number> = {}
          for (const k of NUM) { const v = row[c(k)]; s[k] = typeof v === 'number' ? v : 0 }
          out.get(String(row[c('team_id')]))?.push({ id: p.athlete_id, name: p.name, pos: p.position ?? '', s })
        }
      }
      if (live) setState({ lines: new Map(out), done: true, total: ids.length })
    })()
    return () => { live = false }
  }, [index.data, ids, g.week, g.home_id, g.away_id, season])
  return state
}

const sum = (ls: Line[], k: string) => ls.reduce((a, l) => a + (l.s[k] ?? 0), 0)
const signed = (v: number) => v === 0 ? '0' : v > 0 ? `+${fmt(v)}` : `−${fmt(-v)}`

const hi = (a: number, h: number): 'away' | 'home' | null => a === h ? null : a > h ? 'away' : 'home'
const lo = (a: number, h: number): 'away' | 'home' | null => a === h ? null : a < h ? 'away' : 'home'

function ScoreVsModel({ g, season, hfa }: { g: Game; season: number; hfa: number | null }) {
  const history = useData<HistoryDoc>('history.json')
  const review = useReview([g], history.data, season, hfa).get(g.game_id)
  const model = review?.model ?? null, market = review?.market ?? null
  const actual = (g.home_points ?? 0) - (g.away_points ?? 0)
  const who = (m: number) => m === 0 ? 'Even' : `${m > 0 ? g.home_team : g.away_team} ${m > 0 ? '' : ''}by ${fmt(Math.abs(m))}`
  const grade = gradePick(g, model, market)
  const beat = model == null ? null : actual - model            // home perspective: positive = home did better than the model expected
  const scale = Math.max(14, Math.abs(actual), Math.abs(model ?? 0)) * 1.15
  const pos = (v: number) => 50 + (v / scale) * 50
  return <section className="cf-panel cf-recap-model" aria-labelledby="rc-model">
    <div className="cf-panel-head"><h2 id="rc-model" className="cf-h2">Score vs. Model</h2><span className="cf-small cf-muted">Pre-Game Ratings, Not Stored Forecasts <Info text="The margin the model would have projected from each team’s rating going into the game (the previous week’s ratings) plus home-field advantage unless the game was at a neutral site. Recomputed from the published rating history." label="About the pre-game model" /></span></div>
    <div className="cf-recap-tiles">
      <div><span>Model Expected</span><b>{model == null ? '—' : who(model)}</b></div>
      <div><span>Actual Result</span><b>{actual === 0 ? 'Tie' : who(actual)}</b><small className="cf-num">{g.away_team} {g.away_points}, {g.home_team} {g.home_points}</small></div>
      <div><span>Versus the Model</span><b>{beat == null ? '—' : Math.abs(beat) < 0.05 ? 'Right on it' : `${beat > 0 ? g.home_team : g.away_team} +${fmt(Math.abs(beat))}`}</b><small>{beat == null ? 'No pre-game rating for one side' : `${beat > 0 ? g.home_team : g.away_team} did that much better than expected`}</small></div>
      <div><span>Model Pick</span><b>{grade.su == null ? '—' : grade.su ? 'Correct' : 'Missed'}</b><small>{model == null || model === 0 ? '' : `${model > 0 ? g.home_team : g.away_team} favored`}</small></div>
      {market != null && <div><span>Opening Line</span><b>{Math.abs(market) < 0.05 ? 'Pick’em' : market < 0 ? `${g.home_team} −${fmt(-market)}` : `${g.away_team} −${fmt(market)}`}</b><small>{grade.ats === true ? 'Model’s side covered' : grade.ats === false ? 'Model’s side missed' : grade.ats === 'push' ? 'Push' : 'No model side'}</small></div>}
    </div>
    {model != null && <figure className="cf-recap-axis" aria-label={`Expected margin ${signed(model)}, actual ${signed(actual)}, home perspective`}>
      <div className="cf-recap-labels" aria-hidden="true">
        <span className="cf-recap-lab is-exp" style={{ left: `${Math.min(88, Math.max(12, pos(model)))}%` }}>Model: {who(model)}</span>
      </div>
      <div className="cf-recap-track"><i className="cf-recap-zero" />
        <i className="cf-recap-fill" style={{ left: `${Math.min(pos(model), pos(actual))}%`, width: `${Math.abs(pos(actual) - pos(model))}%` }} />
        <b className="cf-recap-pin is-exp" style={{ left: `${pos(model)}%` }} title="Model expected" /><b className="cf-recap-pin is-act" style={{ left: `${pos(actual)}%` }} title="Actual" />
      </div>
      <div className="cf-recap-labels is-below" aria-hidden="true">
        <span className="cf-recap-lab is-zero" style={{ left: '50%' }}>Even</span>
        <span className="cf-recap-lab is-act" style={{ left: `${Math.min(88, Math.max(12, pos(actual)))}%` }}>Actual: {who(actual)}</span>
      </div>
      <figcaption><span><TeamLogo id={g.away_id} name={g.away_team} size={18} /> {g.away_team} Better</span><span><i className="cf-recap-key is-exp" /> Model Expected <i className="cf-recap-key is-act" /> Actual Result</span><span>{g.home_team} Better <TeamLogo id={g.home_id} name={g.home_team} size={18} /></span></figcaption>
    </figure>}
  </section>
}

type Adv = Record<string, number | null>
type AdvDoc = { teams: Record<string, Adv> }
type StatRow = { label: string; a: string; h: string; better: 'away' | 'home' | null; group?: string }
const grp = (group: string): StatRow => ({ group, label: '', a: '', h: '', better: null })
const epa = (v: number | null | undefined) => v == null ? '—' : (v > 0 ? '+' : v < 0 ? '−' : '') + Math.abs(v).toFixed(2)
const pct1 = (v: number | null | undefined) => v == null ? '—' : `${(v * 100).toFixed(1)}%`
/** Advanced rows: `off` are each team's own offense (higher is better); `def` are what the opponent's offense did (lower is better). */
function advRows(adv: AdvDoc, away: string, home: string): StatRow[] {
  const A = adv.teams[away], H = adv.teams[home]
  if (!A || !H) return []
  const row = (label: string, key: string, show: (v: number | null) => string, side: 'off' | 'def'): StatRow => {
    const a = side === 'off' ? A[key] : H[key], h = side === 'off' ? H[key] : A[key]
    return { label, a: show(a ?? null), h: show(h ?? null), better: a == null || h == null || a === h ? null : (side === 'off' ? a > h : a < h) ? 'away' : 'home' }
  }
  return [
    grp('Advanced Offense'),
    row('EPA / Play', 'epa_play', epa, 'off'), row('Rushing EPA / Play', 'rush_epa', epa, 'off'), row('Passing EPA / Play', 'pass_epa', epa, 'off'),
    row('Early-Down EPA / Play', 'early_epa', epa, 'off'), row('Red Zone EPA / Play', 'redzone_epa', epa, 'off'), row('Total EPA', 'total_epa', epa, 'off'),
    row('Success Rate', 'sr', pct1, 'off'), row('Success Rate on Standard Downs', 'sr_standard', pct1, 'off'), row('Success Rate on Passing Downs', 'sr_passing', pct1, 'off'),
    row('Rushing Success Rate', 'sr_rush', pct1, 'off'), row('Passing Success Rate', 'sr_pass', pct1, 'off'),
    row('Explosive Play Rate', 'explosive_rate', pct1, 'off'), row('3rd Down Conversion Rate', 'third_conv', pct1, 'off'),
    grp('Advanced Defense'),
    row('Defensive EPA / Play', 'epa_play', epa, 'def'), row('Rushing EPA / Play Allowed', 'rush_epa', epa, 'def'), row('Passing EPA / Play Allowed', 'pass_epa', epa, 'def'),
    row('Success Rate Allowed', 'sr', pct1, 'def'), row('Explosive Play Rate Allowed', 'explosive_rate', pct1, 'def'), row('3rd Down Conversion Rate Allowed', 'third_conv', pct1, 'def'),
  ]
}
function statRows(A: Line[], H: Line[]): StatRow[] {
  const pct = (l: Line[]) => sum(l, 'pass_att') ? sum(l, 'pass_cmp') / sum(l, 'pass_att') : 0
  const per = (n: number, d: number) => d ? n / d : 0
  const num = (label: string, f: (l: Line[]) => number, show: (v: number) => string, dir: 'hi' | 'lo' | null): StatRow => {
    const a = f(A), h = f(H); return { label, a: show(a), h: show(h), better: dir === 'hi' ? hi(a, h) : dir === 'lo' ? lo(a, h) : null }
  }
  const int = (v: number) => String(v), dec = (v: number) => fmt(v) ?? '—'
  const comp = (l: Line[]) => `${sum(l, 'pass_cmp')}/${sum(l, 'pass_att')} (${fmt(pct(l) * 100)}%)`
  return [
    grp('Box Score'),
    { label: 'Passing (C/A)', a: comp(A), h: comp(H), better: hi(pct(A), pct(H)) },
    num('Rushing (Carries)', l => sum(l, 'rush_car'), int, null),
    num('Total Yards', l => sum(l, 'pass_yds') + sum(l, 'rush_yds'), int, 'hi'),
    num('Passing Yards', l => sum(l, 'pass_yds'), int, 'hi'),
    num('Rushing Yards', l => sum(l, 'rush_yds'), int, 'hi'),
    num('Yards Per Carry', l => per(sum(l, 'rush_yds'), sum(l, 'rush_car')), dec, 'hi'),
    num('Yards Per Pass Attempt', l => per(sum(l, 'pass_yds'), sum(l, 'pass_att')), dec, 'hi'),
    num('Touchdowns (Pass + Rush)', l => sum(l, 'pass_td') + sum(l, 'rush_td'), int, 'hi'),
    num('Interceptions Thrown', l => sum(l, 'pass_int'), int, 'lo'),
    num('Fumbles Lost', l => sum(l, 'fum_lost'), int, 'lo'),
    num('Sacks', l => sum(l, 'sacks'), dec, 'hi'),
    num('Tackles for Loss', l => sum(l, 'tfl'), dec, 'hi'),
    num('Interceptions', l => sum(l, 'int'), int, 'hi'),
  ]
}
/** Two cards on one shared row grid (subgrid), like Player Stats: the same stat sits at the same height in both. */
function TeamStats({ g, A, H, adv }: { g: Game; A: Line[]; H: Line[]; adv: AdvDoc | null }) {
  const dir = useTeams()
  const rows = [...statRows(A, H), ...(adv ? advRows(adv, g.away_id, g.home_id) : [])]
  return <div className="cf-recap-players" style={{ ['--rows' as string]: rows.length + 1 }}>
    {([[g.away_id, g.away_team, 'away'], [g.home_id, g.home_team, 'home']] as const).map(([id, name, side]) => { const t = dir.get(id); return <div key={id} className="cf-panel cf-recap-card">
      <h3 className="cf-recap-teamhead" style={teamTheme(t?.color ?? null, t?.alt_color ?? null)}><span className="cf-recap-logo"><TeamLogo id={id} name={name} size={30} /></span><span>{name}</span></h3>
      {rows.map(r => r.group ? <div key={r.group} className="cf-recap-statgroup">{r.group}</div>
        : <div key={r.label} className={`cf-recap-stat${r.better === side ? ' is-better' : ''}`}><span>{r.label}</span><b className="cf-num">{side === 'away' ? r.a : r.h}</b></div>)}
    </div> })}
  </div>
}

function leaders(ls: Line[], score: (l: Line) => number, n: number) { return ls.filter(l => score(l) > 0).sort((a, b) => score(b) - score(a)).slice(0, n) }
const CATS: [string, (ls: Line[]) => Line[], (l: Line) => string][] = [
  ['Passing', ls => leaders(ls, l => l.s.pass_att, 2), l => `${l.s.pass_cmp}/${l.s.pass_att} · ${l.s.pass_yds} yds${l.s.pass_td ? ` · ${l.s.pass_td} TD` : ''}${l.s.pass_int ? ` · ${l.s.pass_int} INT` : ''}`],
  ['Rushing', ls => leaders(ls, l => l.s.rush_yds + (l.s.rush_car ? 0.001 : 0), 3), l => `${l.s.rush_car} car · ${l.s.rush_yds} yds${l.s.rush_td ? ` · ${l.s.rush_td} TD` : ''}`],
  ['Receiving', ls => leaders(ls, l => l.s.rec_yds + (l.s.rec ? 0.001 : 0), 3), l => `${l.s.rec} rec · ${l.s.rec_yds} yds${l.s.rec_td ? ` · ${l.s.rec_td} TD` : ''}`],
  ['Defense', ls => leaders(ls, l => l.s.tkl + l.s.sacks * 2 + l.s.int * 3 + l.s.tfl, 3), l => `${l.s.tkl} tkl${l.s.tfl ? ` · ${fmt(l.s.tfl)} TFL` : ''}${l.s.sacks ? ` · ${fmt(l.s.sacks)} sk` : ''}${l.s.int ? ` · ${l.s.int} INT` : ''}${l.s.pd ? ` · ${l.s.pd} PD` : ''}`],
]
/** Both teams share one grid per category, so each category starts at the same height on both sides. */
function PlayerStats({ g, A, H }: { g: Game; A: Line[]; H: Line[] }) {
  const dir = useTeams()
  const cats = CATS.map(([title, pick, line]) => ({ title, line, a: pick(A), h: pick(H) })).filter(c => c.a.length + c.h.length > 0)
  const list = (ls: Line[], line: (l: Line) => string) => ls.length === 0 ? <p className="cf-muted cf-small cf-recap-none">—</p>
    : <ul>{ls.map(l => <li key={l.id}><PlayerLink id={l.id}>{l.name}</PlayerLink><span className="cf-muted cf-small">{l.pos}</span><span className="cf-num cf-small">{line(l)}</span></li>)}</ul>
  // Two cards on one shared row grid (subgrid): each category is the same height in both, so they line up across the boxes.
  return <div className="cf-recap-players" style={{ ['--rows' as string]: cats.length + 1 }}>
    {([[g.away_id, g.away_team, 'a'], [g.home_id, g.home_team, 'h']] as const).map(([id, name, side]) => { const t = dir.get(id); return <div key={id} className="cf-panel cf-recap-card">
      <h3 className="cf-recap-teamhead" style={teamTheme(t?.color ?? null, t?.alt_color ?? null)}><span className="cf-recap-logo"><TeamLogo id={id} name={name} size={30} /></span><span>{name}</span></h3>
      {cats.map(c => <div key={c.title} className="cf-recap-cat"><h4>{c.title}</h4>{list(side === 'a' ? c.a : c.h, c.line)}</div>)}
    </div> })}
  </div>
}

export default function GameRecap({ g, season, hfa }: { g: Game; season: number; hfa: number | null }) {
  const box = useBox(g, season)
  const adv = useData<AdvDoc>(`game_adv/${g.game_id}.json`)
  const A = box.lines.get(g.away_id) ?? [], H = box.lines.get(g.home_id) ?? []
  const have = A.length + H.length > 0
  return <>
    <ScoreVsModel g={g} season={season} hfa={hfa} />
    <section className="cf-recap-playerwrap" aria-labelledby="rc-team">
      <h2 id="rc-team" className="cf-h2">Team Stats</h2>
      {!box.done && !have ? <p className="cf-muted">Loading box score…</p> : !have ? <p className="cf-muted">No box-score data is published for this game.</p> : <TeamStats g={g} A={A} H={H} adv={adv.data} />}
      <p className="cf-small cf-muted cf-recap-note">Totals are summed from the published player box-score lines for this game (CollegeFootballData), so a player without a published profile is not counted. Better side shaded green. {adv.data ? 'EPA and success rates come from play-by-play (raw, not opponent-adjusted; kneels, spikes and penalties excluded). Success: 50% of the distance on 1st down, 70% on 2nd, 100% on 3rd and 4th. Passing downs are 2nd and 8+ or 3rd and 4th and 5+; standard downs are all others. Explosive plays are runs of 10+ and passes of 15+ yards. Defensive rows use the opponent’s offense, so lower is better.' : 'Advanced play-by-play stats are not published for this game yet.'}</p>
    </section>
    {have && <section className="cf-recap-playerwrap" aria-labelledby="rc-players">
      <h2 id="rc-players" className="cf-h2">Player Stats</h2>
      <PlayerStats g={g} A={A} H={H} />
    </section>}
  </>
}
