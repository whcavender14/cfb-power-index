import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { X } from 'lucide-react'
import './player.css'
import { DataGate, Info, InfoLabel, Segmented, SortTh, sortRows, TeamLogo, useData, useTeams, type Sort } from './components'
import type { Meta } from './data'
import { teamTheme } from './teamTheme'
import { FLAG_INFO, RATING_INFO, ratingRows, TIER, type RatingsTeam } from './ratings'

// Player detail modal (docs/website/PLAYER_DATA.md). Every number is a CFBD box-score value or a sum of them;
// rates (Y/A, Y/C, ...) are simple divisions done here for display.

type Stats = {
  pass_cmp: number; pass_att: number; pass_yds: number; pass_td: number; pass_int: number
  rush_car: number; rush_yds: number; rush_td: number; rec: number; rec_yds: number; rec_td: number
  tkl: number; tfl: number; sacks: number; int: number; pd: number; qbh: number; fum_lost: number
}
type SeasonRow = Stats & { season: number; team_id: string; team: string; gp: number }
type GameRow = Stats & { season: number; week: number; post: boolean; date: string; team_id: string; opp_id: string; opp: string; loc: 'H' | 'A' | 'N'; pts: number | null; opp_pts: number | null }
type Transfer = { season: number; from: string; from_id: string | null; to: string | null; to_id: string | null; date: string | null }
type Player = {
  athlete_id: string; name: string; team: string; team_id: string | null; jersey: number | null; position: string | null
  class: number | null; height: number | null; weight: number | null; headshot: string | null
  hometown: { city: string | null; state: string | null; country: string | null } | null
  recruiting: { year: number; stars: number | null; rating: number | null; ranking: number | null; school: string | null; city: string | null; state: string | null; committed_to: string | null; committed_id: string | null } | null
  hs_class: number | null; hs_class_estimated: boolean; draft_year: number | null
  transfers: Transfer[]; seasons: SeasonRow[]; game_cols: string[]; games: (string | number | boolean | null)[][]
}
type PlayerDoc = { meta: Meta; source: string; through_week: number | null; player: Player }

type Tab = 'production' | 'career' | 'games'
const TABS: { key: Tab; label: string }[] = [{ key: 'production', label: 'Production' }, { key: 'career', label: 'Career path' }, { key: 'games', label: 'Game log' }]

const heightText = (h: number | null) => h ? `${Math.floor(h / 12)}′${h % 12}″` : null
const CLASS = ['', 'Freshman', 'Sophomore', 'Junior', 'Senior', 'Fifth year', 'Sixth year']
const rate = (a: number, b: number, d = 1) => b > 0 ? (a / b).toFixed(d) : '—'
const int = (v: number) => v.toLocaleString()
const MINUS = (v: number | string) => String(v).replace('-', '−')

// Stat groups, shown only when the player has recorded something in them.
type Col = { key: string; label: string; info?: string; value: (s: Stats) => number | null; text: (s: Stats) => string; best?: boolean }
type Group = { key: string; label: string; has: (s: Stats) => boolean; cols: Col[] }
const GROUPS: Group[] = [
  { key: 'pass', label: 'Passing', has: s => s.pass_att > 0, cols: [
    { key: 'ca', label: 'C/A', value: s => s.pass_cmp, text: s => `${s.pass_cmp}/${s.pass_att}` },
    { key: 'pct', label: 'Cmp%', value: s => s.pass_att ? s.pass_cmp / s.pass_att : null, text: s => s.pass_att ? `${(100 * s.pass_cmp / s.pass_att).toFixed(1)}` : '—' },
    { key: 'pyds', label: 'Yds', value: s => s.pass_yds, text: s => MINUS(int(s.pass_yds)), best: true },
    { key: 'ptd', label: 'TD', value: s => s.pass_td, text: s => String(s.pass_td), best: true },
    { key: 'pint', label: 'INT', value: s => s.pass_int, text: s => String(s.pass_int) },
    { key: 'ya', label: 'Y/A', info: 'Passing yards per attempt.', value: s => s.pass_att ? s.pass_yds / s.pass_att : null, text: s => rate(s.pass_yds, s.pass_att), best: true },
  ] },
  { key: 'rush', label: 'Rushing', has: s => s.rush_car > 0, cols: [
    { key: 'car', label: 'Car', value: s => s.rush_car, text: s => String(s.rush_car) },
    { key: 'ryds', label: 'Yds', value: s => s.rush_yds, text: s => MINUS(int(s.rush_yds)), best: true },
    { key: 'rtd', label: 'TD', value: s => s.rush_td, text: s => String(s.rush_td), best: true },
    { key: 'yc', label: 'Y/C', info: 'Rushing yards per carry.', value: s => s.rush_car ? s.rush_yds / s.rush_car : null, text: s => rate(s.rush_yds, s.rush_car), best: true },
  ] },
  { key: 'rec', label: 'Receiving', has: s => s.rec > 0, cols: [
    { key: 'rec', label: 'Rec', value: s => s.rec, text: s => String(s.rec) },
    { key: 'cyds', label: 'Yds', value: s => s.rec_yds, text: s => MINUS(int(s.rec_yds)), best: true },
    { key: 'ctd', label: 'TD', value: s => s.rec_td, text: s => String(s.rec_td), best: true },
    { key: 'yr', label: 'Y/R', info: 'Receiving yards per catch.', value: s => s.rec ? s.rec_yds / s.rec : null, text: s => rate(s.rec_yds, s.rec), best: true },
  ] },
  { key: 'adv', label: 'Per Play', has: s => s.pass_att + s.rush_car + s.rec > 0, cols: [
    { key: 'ypp', label: 'Yds/Play', info: 'Passing + rushing + receiving yards per pass attempt, carry and catch. Air yards (for ADOT) and targets are not in the box scores, so those are not shown.', value: s => { const n = s.pass_att + s.rush_car + s.rec; return n ? (s.pass_yds + s.rush_yds + s.rec_yds) / n : null }, text: s => rate(s.pass_yds + s.rush_yds + s.rec_yds, s.pass_att + s.rush_car + s.rec), best: true },
    { key: 'tds', label: 'Total TD', value: s => s.pass_td + s.rush_td + s.rec_td, text: s => String(s.pass_td + s.rush_td + s.rec_td), best: true },
  ] },
  { key: 'def', label: 'Defense', has: s => s.tkl + s.tfl + s.sacks + s.int + s.pd > 0, cols: [
    { key: 'tkl', label: 'Tkl', value: s => s.tkl, text: s => String(s.tkl), best: true },
    { key: 'tfl', label: 'TFL', value: s => s.tfl, text: s => String(s.tfl), best: true },
    { key: 'sk', label: 'Sk', value: s => s.sacks, text: s => String(s.sacks), best: true },
    { key: 'int', label: 'INT', value: s => s.int, text: s => String(s.int), best: true },
    { key: 'pd', label: 'PD', info: 'Passes defended.', value: s => s.pd, text: s => String(s.pd), best: true },
  ] },
]

const STAT_KEYS: (keyof Stats)[] = ['pass_cmp', 'pass_att', 'pass_yds', 'pass_td', 'pass_int', 'rush_car', 'rush_yds', 'rush_td', 'rec', 'rec_yds', 'rec_td', 'tkl', 'tfl', 'sacks', 'int', 'pd', 'qbh', 'fum_lost']
const sum = (rows: Stats[]): Stats => Object.fromEntries(STAT_KEYS.map(k => [k, rows.reduce((a, r) => a + (r[k] ?? 0), 0)])) as Stats

/** One number per game for highlighting: scrimmage yards, touchdowns, turnovers and defensive plays, weighted like a
 *  standard box-score score. Used only to flag games well above or below the player's own average. */
const gameScore = (s: Stats) => 0.04 * s.pass_yds + 4 * s.pass_td - 2 * s.pass_int + 0.1 * (s.rush_yds + s.rec_yds) + 6 * (s.rush_td + s.rec_td)
  + s.tkl + s.tfl + 2 * s.sacks + 4 * s.int + s.pd - 2 * s.fum_lost

function useGames(p: Player): GameRow[] {
  return useMemo(() => p.games.map(g => Object.fromEntries(p.game_cols.map((c, i) => [c, g[i]])) as unknown as GameRow), [p])
}

export default function PlayerModal({ id, onClose }: { id: string; onClose: () => void }) {
  const doc = useData<PlayerDoc>(`player/${id}.json`)
  const box = useRef<HTMLDivElement>(null)
  useEffect(() => {
    const prev = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    box.current?.focus()
    const key = (e: KeyboardEvent) => {
      if (e.key === 'Escape') { e.preventDefault(); onClose() }
      if (e.key === 'Tab' && box.current) {   // keep focus inside the dialog
        const f = [...box.current.querySelectorAll<HTMLElement>('button, a[href], input, select, [tabindex="0"]')].filter(el => !el.hasAttribute('disabled'))
        if (!f.length) return
        const first = f[0], last = f[f.length - 1]
        if (e.shiftKey && (document.activeElement === first || document.activeElement === box.current)) { e.preventDefault(); last.focus() }
        else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus() }
      }
    }
    document.addEventListener('keydown', key)
    return () => { document.body.style.overflow = prev; document.removeEventListener('keydown', key) }
  }, [onClose])
  return <div className="cf-pm-backdrop" onMouseDown={e => { if (e.target === e.currentTarget) onClose() }}>
    <div className="cf-pm" role="dialog" aria-modal="true" aria-labelledby="cf-pm-name" tabIndex={-1} ref={box}>
      <button type="button" className="cf-icon-btn cf-pm-close" onClick={onClose} aria-label="Close player details"><X size={18} /></button>
      <DataGate source={doc} label="Player details">{d => <PlayerBody doc={d} />}</DataGate>
    </div>
  </div>
}

function PlayerBody({ doc }: { doc: PlayerDoc }) {
  const p = doc.player
  const [tab, setTab] = useState<Tab>('production')
  const games = useGames(p)
  const teams = useTeams()
  const team = teams.get(p.team_id ?? '')
  const [broken, setBroken] = useState(false)
  const initials = p.name.split(/\s+/).map(w => w[0]).slice(0, 2).join('')
  return <div className="cf-themed cf-pm-themed" style={teamTheme(team?.color ?? null, team?.alt_color ?? null)}>
    <header className="cf-pm-head">
      <span className="cf-pm-face">{p.headshot && !broken ? <img src={p.headshot} alt="" onError={() => setBroken(true)} /> : <span aria-hidden="true">{initials}</span>}</span>
      <div className="cf-pm-id">
        <h2 id="cf-pm-name" className="cf-pm-name">{p.name}</h2>
        <p className="cf-pm-team">
          <TeamLogo id={p.team_id} name={p.team} size={20} /><span>{p.team}</span>
          {p.jersey != null && <span className="cf-pm-chip cf-num">#{p.jersey}</span>}
          {p.position && <span className="cf-pm-chip">{p.position}</span>}
        </p>
      </div>
      {p.team_id && <RatingBadge id={p.athlete_id} teamId={p.team_id} />}
    </header>
    <Bio p={p} season={doc.meta.season} />
    <div className="cf-pm-tabs" role="tablist" aria-label="Player details">
      {TABS.map(t => <button key={t.key} type="button" role="tab" id={`pm-tab-${t.key}`} aria-selected={tab === t.key} aria-controls={`pm-panel-${t.key}`}
        className={tab === t.key ? 'is-on' : ''} onClick={() => setTab(t.key)}>{t.label}</button>)}
    </div>
    <div className="cf-pm-panel" role="tabpanel" id={`pm-panel-${tab}`} aria-labelledby={`pm-tab-${tab}`} key={tab}>
      {tab === 'production' && <Production p={p} games={games} />}
      {tab === 'career' && <CareerPath p={p} season={doc.meta.season} />}
      {tab === 'games' && <GameLog games={games} season={doc.meta.season} />}
    </div>
    <p className="cf-small cf-muted cf-pm-foot">Box scores through Week {doc.through_week ?? '—'} of {doc.meta.season}, from 2021. Source: CollegeFootballData (box scores, roster, recruiting, transfer portal).</p>
  </div>
}

/** CFPi+ Player Rating (beta): the player's row in players/ratings/team/<team_id>.json, if rated. */
function RatingBadge({ id, teamId }: { id: string; teamId: string }) {
  const doc = useData<RatingsTeam>(`players/ratings/team/${teamId}.json`)
  const r = doc.data ? ratingRows(doc.data).find(x => x.athlete_id === id) : null
  if (!r || !doc.data) return null
  const te = r.group === 'TE' ? ' Tight-end ratings validated weakly (their gain over recruiting alone was not significant), so treat them with extra caution.' : ''
  return <div className="cf-pm-ovr">
    <span className="cf-pm-ovr-k">CFPi+ Rating <span className="cf-pm-chip">Beta</span></span>
    <span className="cf-pm-ovr-v"><b className="cf-num">{r.ovr}</b><span className="cf-num"> ± {r.band}</span>
      <Info text={`${RATING_INFO} Built from games through the ${doc.data.rated_through} season. ${TIER(r.ovr)} (CFPi+ interpretation).${te}`} label="About the CFPi+ rating" /></span>
    {(r.provisional || r.estimated) && <span className="cf-pm-ovr-k">{[r.provisional && 'Provisional', r.estimated && 'Estimated'].filter(Boolean).join(' · ')}
      <Info text={[r.provisional && FLAG_INFO.provisional, r.estimated && FLAG_INFO.estimated].filter(Boolean).join(' ')} label="About these flags" /></span>}
  </div>
}

function Bio({ p, season }: { p: Player; season: number }) {
  const h = p.hometown
  const home = h ? [h.city, h.state ?? (h.country !== 'USA' ? h.country : null)].filter(Boolean).join(', ') : null
  const r = p.recruiting
  const stars = r?.stars ? `${r.stars}-star` : null
  const recruit = r ? [stars && r.ranking ? `${stars} No. ${r.ranking} national` : stars ?? 'Unranked', `${r.year} class`].join(' · ') : null
  const body = [heightText(p.height), p.weight ? `${p.weight} lb` : null].filter(Boolean).join(' · ')
  const redshirt = !!(p.class && p.class >= 1 && p.class <= 4 && r && r.year <= season && season - r.year > p.class - 1)
  const next = season + 1
  const draft = p.draft_year == null ? null : p.draft_year <= next ? `Eligible for ${next} draft` : `Eligible in ${p.draft_year}`
  const items: [string, string | null, string?][] = [
    ['Hometown', home],
    ['Recruiting', recruit],
    ['Size', body || null],
    ['Class', p.class ? `${redshirt ? 'Redshirt ' : ''}${redshirt ? (CLASS[p.class] ?? '').toLowerCase() : CLASS[p.class] ?? `Year ${p.class}`}` : null, redshirt ? 'Redshirt is inferred: CollegeFootballData has no redshirt flag. It is tagged when more seasons have passed since the recruiting class than the class year accounts for.' : undefined],
    ['Draft', draft, p.hs_class_estimated ? 'Estimated from class year: no recruiting record. NFL rule: three seasons after high school.' : 'NFL rule: eligible three seasons after high school graduation.'],
  ]
  return <dl className="cf-pm-bio">
    {items.filter(i => i[1]).map(([k, v, info]) => <div key={k}><dt>{k}{info && <Info text={info} label={`About ${k.toLowerCase()}`} />}</dt><dd>{v}</dd></div>)}
  </dl>
}

// ---------------------------------------------------------------------------------------------
// Production
// ---------------------------------------------------------------------------------------------
function Production({ p, games }: { p: Player; games: GameRow[] }) {
  const [view, setView] = useState<'season' | 'games'>('season')
  const total = sum(p.seasons)
  const groups = GROUPS.filter(g => g.has(total))
  if (!p.seasons.length) return <p className="cf-muted cf-pm-empty">No box-score stats since 2021.</p>
  const rows: { key: string; label: ReactNode; gp?: number; s: Stats }[] = view === 'season'
    ? p.seasons.map(s => ({ key: `${s.season}-${s.team_id}`, label: <span className="cf-pm-yr"><TeamLogo id={s.team_id} name={s.team} size={16} /><span className="cf-num">{s.season}</span></span>, gp: s.gp, s }))
    : [...games].reverse().map(g => ({ key: `${g.season}-${g.post}-${g.week}-${g.opp_id}`, label: <span className="cf-pm-yr"><TeamLogo id={g.opp_id} name={g.opp} size={16} /><span><span className="cf-num">{g.season} {g.post ? 'Post' : `Wk ${g.week}`}</span> <span className="cf-muted">{g.loc === 'A' ? '@' : g.loc === 'N' ? 'vs' : ''} {g.opp}</span></span></span>, s: g }))
  // Season view: the best season in each counting or rate column is emphasised.
  const best = new Map<string, number>()
  if (view === 'season' && rows.length > 1) for (const g of groups) for (const c of g.cols) if (c.best) {
    const vals = rows.map(r => c.value(r.s)).filter((v): v is number => v != null && v > 0)
    if (vals.length) best.set(c.key, Math.max(...vals))
  }
  return <>
    <div className="cf-pm-bar">
      <Segmented label="Production view" value={view} onChange={setView} options={[{ value: 'season', label: 'Season' }, { value: 'games', label: 'Games' }]} />
      {view === 'season' && rows.length > 1 && <span className="cf-small cf-muted"><span className="cf-pm-best-key" aria-hidden="true" /> Career best</span>}
    </div>
    <div className="cf-pm-scroll"><table className="cf-table cf-pm-table">
      <thead>
        <tr className="cf-pm-grouprow"><th colSpan={view === 'season' ? 2 : 1} />{groups.map(g => <th key={g.key} colSpan={g.cols.length} className="cf-pm-gh">{g.label}</th>)}</tr>
        <tr><th scope="col" className="cf-th-start">{view === 'season' ? 'Season' : 'Game'}</th>{view === 'season' && <th scope="col" className="cf-th-end">GP</th>}
          {groups.map(g => g.cols.map((c, i) => <th key={c.key} scope="col" className={`cf-th-end${i === 0 ? ' cf-pm-gs' : ''}`}>{c.info ? <InfoLabel focusable text={c.info}>{c.label}</InfoLabel> : c.label}</th>))}</tr>
      </thead>
      <tbody>{rows.map(r => <tr key={r.key}>
        <td>{r.label}</td>{view === 'season' && <td className="cf-num cf-td-end">{r.gp}</td>}
        {groups.map(g => g.cols.map((c, i) => { const v = c.value(r.s); const isBest = best.has(c.key) && v != null && v === best.get(c.key)
          return <td key={c.key} className={`cf-num cf-td-end${i === 0 ? ' cf-pm-gs' : ''}${isBest ? ' is-best' : ''}`}>{c.text(r.s)}{isBest && <span className="cf-sr"> (career best)</span>}</td> }))}
      </tr>)}</tbody>
      {view === 'season' && p.seasons.length > 1 && <tfoot><tr>
        <th scope="row" className="cf-th-start">Career</th><td className="cf-num cf-td-end">{p.seasons.reduce((a, s) => a + s.gp, 0)}</td>
        {groups.map(g => g.cols.map((c, i) => <td key={c.key} className={`cf-num cf-td-end${i === 0 ? ' cf-pm-gs' : ''}`}>{c.text(total)}</td>))}
      </tr></tfoot>}
    </table></div>
  </>
}

// ---------------------------------------------------------------------------------------------
// Career path
// ---------------------------------------------------------------------------------------------
type Stint = { team: string; team_id: string | null; from: number; to: number; gp: number; transfer?: Transfer }
function stints(p: Player, season: number): Stint[] {
  const out: Stint[] = []
  for (const s of p.seasons) {
    const last = out[out.length - 1]
    if (last && last.team_id === s.team_id) { last.to = s.season; last.gp += s.gp }
    else out.push({ team: s.team, team_id: s.team_id, from: s.season, to: s.season, gp: s.gp })
  }
  const r = p.recruiting
  // Enrolled before first recorded game (redshirt years): start the first stint at the recruiting class year.
  if (out.length && r?.committed_id && r.committed_id === out[0].team_id && r.year < out[0].from) out[0].from = r.year
  // On this year's roster somewhere new, with no games there yet.
  if (p.team_id && out[out.length - 1]?.team_id !== p.team_id) out.push({ team: p.team, team_id: p.team_id, from: season, to: season, gp: 0 })
  if (!out.length && r?.committed_to) out.push({ team: r.committed_to, team_id: r.committed_id, from: r.year, to: season, gp: 0 })
  for (let i = 1; i < out.length; i++) {
    out[i].transfer = p.transfers.find(t => t.from_id === out[i - 1].team_id || t.from === out[i - 1].team)
    if (out[i].from > out[i - 1].to + 1) out[i].from = out[i - 1].to + 1   // a year between stints is time spent at the new school
  }
  return out
}

const monthYear = (d: string | null) => d ? new Date(`${d}T12:00:00Z`).toLocaleDateString(undefined, { month: 'short', year: 'numeric' }) : null

function CareerPath({ p, season }: { p: Player; season: number }) {
  const list = stints(p, season)
  const r = p.recruiting
  const current = (s: Stint, i: number) => i === list.length - 1 && s.team_id === p.team_id
  return <ol className="cf-pm-path">
    <li className="cf-pm-node is-hs">
      <span className="cf-pm-dot" aria-hidden="true">HS</span>
      <div>
        <p className="cf-pm-node-title">{r?.school ?? 'High school'}</p>
        <p className="cf-small cf-muted">{[r ? [r.city, r.state].filter(Boolean).join(', ') : [p.hometown?.city, p.hometown?.state].filter(Boolean).join(', '), p.hs_class ? `Class of ${p.hs_class}${p.hs_class_estimated ? ' (est.)' : ''}` : null].filter(Boolean).join(' · ') || 'No recruiting record'}</p>
        {r?.stars ? <p className="cf-pm-stars" aria-label={`${r.stars} stars`}>{'★'.repeat(r.stars)}<span className="cf-faint">{'★'.repeat(Math.max(0, 5 - r.stars))}</span>{r.ranking ? <span className="cf-small cf-muted"> No. {r.ranking} national</span> : null}</p> : null}
      </div>
    </li>
    {list.map((s, i) => <li key={`${s.team_id}-${s.from}`} className={`cf-pm-node${current(s, i) ? ' is-current' : ''}`}>
      <span className="cf-pm-dot is-logo" aria-hidden="true"><TeamLogo id={s.team_id} name={s.team} size={26} /></span>
      <div>
        {s.transfer && <p className="cf-pm-transfer cf-small">Transfer portal{monthYear(s.transfer.date) ? ` · ${monthYear(s.transfer.date)}` : ''}</p>}
        {i > 0 && !s.transfer && <p className="cf-pm-transfer cf-small">Transferred</p>}
        <p className="cf-pm-node-title">{s.team}</p>
        <p className="cf-small cf-muted cf-num">{s.from}{current(s, i) ? ' – Present' : s.to > s.from ? `–${s.to}` : ''} · {s.gp} game{s.gp === 1 ? '' : 's'}</p>
      </div>
    </li>)}
  </ol>
}

// ---------------------------------------------------------------------------------------------
// Game log
// ---------------------------------------------------------------------------------------------
function GameLog({ games, season }: { games: GameRow[]; season: number }) {
  const seasons = [...new Set(games.map(g => g.season))].sort((a, b) => b - a)
  const [year, setYear] = useState<string>(String(seasons.includes(season) ? season : seasons[0] ?? season))
  const [q, setQ] = useState('')
  const [sort, setSort] = useState<Sort>({ key: 'week', desc: false })
  const scored = useMemo(() => {
    const scores = games.map(g => gameScore(g))
    const mean = scores.reduce((a, b) => a + b, 0) / (scores.length || 1)
    const sd = Math.sqrt(scores.reduce((a, b) => a + (b - mean) ** 2, 0) / (scores.length || 1))
    return games.map((g, i) => ({ g, score: scores[i], z: sd > 0 && games.length >= 4 ? (scores[i] - mean) / sd : 0 }))
  }, [games])
  if (!games.length) return <p className="cf-muted cf-pm-empty">No games since 2021.</p>
  const total = sum(games)
  const groups = GROUPS.filter(g => g.key !== 'adv' && g.has(total))
  const cols = groups.flatMap(g => g.cols.filter(c => !['pct', 'ya', 'yc', 'yr'].includes(c.key)).map(c => ({ ...c, group: g.label })))
  const order = (g: GameRow) => g.season * 100 + (g.post ? 50 : g.week)
  let rows = scored.filter(r => (year === 'all' || String(r.g.season) === year) && (!q || r.g.opp.toLowerCase().includes(q.toLowerCase())))
  const col = cols.find(c => c.key === sort.key)
  rows = sortRows(rows, r => sort.key === 'week' ? order(r.g) : sort.key === 'opp' ? r.g.opp : sort.key === 'res' ? (r.g.pts ?? 0) - (r.g.opp_pts ?? 0) : sort.key === 'perf' ? r.z : col ? col.value(r.g) : null, sort.desc)
  return <>
    <div className="cf-pm-bar">
      <label className="cf-pm-filter"><span className="cf-sr">Season</span>
        <select value={year} onChange={e => setYear(e.target.value)}>{seasons.map(s => <option key={s} value={s}>{s}</option>)}<option value="all">All seasons</option></select>
      </label>
      <label className="cf-pm-filter"><span className="cf-sr">Filter by opponent</span><input type="search" placeholder="Opponent" value={q} onChange={e => setQ(e.target.value)} /></label>
      <span className="cf-small cf-muted cf-pm-legend"><span className="cf-pm-flag is-good">▲</span> big game <span className="cf-pm-flag is-bad">▼</span> quiet game
        <Info text="Compared with this player's own average game since 2021, using a box-score score (yards, touchdowns and turnovers; tackles, sacks, interceptions and passes defended on defense). Flagged when a game is one standard deviation or more from the player's average." label="About game flags" /></span>
    </div>
    <div className="cf-pm-scroll"><table className="cf-table cf-pm-table">
      <thead><tr>
        <SortTh label="Wk" sortKey="week" sort={sort} onSort={setSort} align="start" />
        <SortTh label="Opponent" sortKey="opp" sort={sort} onSort={setSort} align="start" />
        <SortTh label="Result" sortKey="res" sort={sort} onSort={setSort} align="start" />
        {cols.map(c => <SortTh key={c.key} label={c.label} sortKey={c.key} sort={sort} onSort={setSort} className={c === cols.find(x => x.group === c.group) ? 'cf-pm-gs' : ''} info={c === cols.find(x => x.group === c.group) ? c.group : undefined} />)}
        <SortTh label="" sortKey="perf" sort={sort} onSort={setSort} />
      </tr></thead>
      <tbody>{rows.map(({ g, z }) => {
        const flag = z >= 1 ? 'good' : z <= -1 ? 'bad' : null
        const won = g.pts != null && g.opp_pts != null ? g.pts > g.opp_pts : null
        return <tr key={`${g.season}-${g.post}-${g.week}-${g.opp_id}`} className={flag ? `is-${flag}` : ''}>
          <td className="cf-num"><span className="cf-pm-wk">{year === 'all' && <span className="cf-muted">{g.season} </span>}{g.post ? 'Post' : g.week}</span><span className="cf-pm-date cf-muted">{g.date?.slice(5).replace('-', '/')}</span></td>
          <td><span className="cf-pm-opp"><span className="cf-muted cf-pm-loc">{g.loc === 'A' ? '@' : g.loc === 'N' ? 'vs' : ''}</span><TeamLogo id={g.opp_id} name={g.opp} size={16} /><span>{g.opp}</span></span></td>
          <td className="cf-num">{won == null ? '—' : <><span className={won ? 'cf-pm-w' : 'cf-pm-l'}>{won ? 'W' : 'L'}</span> {g.pts}–{g.opp_pts}</>}</td>
          {cols.map(c => <td key={c.key} className={`cf-num cf-td-end${c === cols.find(x => x.group === c.group) ? ' cf-pm-gs' : ''}`}>{c.text(g)}</td>)}
          <td className="cf-td-end">{flag && <span className={`cf-pm-flag is-${flag}`} title={flag === 'good' ? "Well above the player's average game" : "Well below the player's average game"}>{flag === 'good' ? '▲' : '▼'}<span className="cf-sr">{flag === 'good' ? 'Big game' : 'Quiet game'}</span></span>}</td>
        </tr>
      })}</tbody>
    </table></div>
    {!rows.length && <p className="cf-muted cf-pm-empty">No games match.</p>}
  </>
}
