import { lazy, Suspense, useMemo, useState } from 'react'
import { DataGate, PageHead, Segmented, Select, SortTh, sortRows, TeamLogo, useData, useTeams, type Sort } from '../components'
import type { Meta } from '../data'
import { Headshot, PlayerLink, useOpenPlayer } from '../player'
import { useQueryParam } from '../router'
const RatingsView = lazy(() => import('./PlayerRatings').then(m => ({ default: m.RatingsView })))

// Player leaderboards (/players/; docs/website/PLAYER_DATA.md). Every count is a CollegeFootballData value and PPA is
// CFBD's own number; the passer rating comes precomputed from R. Rates (Y/A, Cmp%, success rate, ...) are simple
// divisions done here for display, as in the player modal.

type Cat = 'passing' | 'rushing' | 'receiving' | 'defense' | 'kicking' | 'punting'
type Pull = { available: boolean; reason: string | null; pulled_at?: string | null }
type Board = {
  meta: Meta; category: Cat; through_week: number | null; unavailable?: string; rank_stat: string; columns: string[]
  team_games: Record<string, number>; qualifier: { stat: string; per_team_game: number; text: string } | null; floor: string
  ppa?: Pull | null; usage?: Pull | null; source: string; rows: (string | number | boolean | null)[][]
}
type Row = Record<string, number | null> & { athlete_id: string; player: string; team_id: string; position: string | null; class: number | null; q: boolean | null; rs: number }

const CATS: { value: Cat; label: string }[] = [
  { value: 'passing', label: 'Passing' }, { value: 'rushing', label: 'Rushing' }, { value: 'receiving', label: 'Receiving' },
  { value: 'defense', label: 'Defense' }, { value: 'kicking', label: 'Kicking' }, { value: 'punting', label: 'Punting' },
]
// The Ratings view (CFPi+ Player Ratings beta) sits beside the stat categories; it is a modelled rating, not a stat.
const VIEWS: { value: Cat | 'ratings'; label: string }[] = [...CATS, { value: 'ratings', label: 'Ratings (Beta)' }]
const PPA_INFO = 'Predicted Points Added per play, as CollegeFootballData computes it: the change in expected points on the plays credited to the player (an EPA-style measure, not opponent-adjusted). '
const div = (a: number | null, b: number | null) => a != null && b ? a / b : null
const f1 = (v: number | null) => v == null ? '—' : v.toFixed(1).replace('-', '−')
const pct = (v: number | null) => v == null ? '—' : `${(100 * v).toFixed(1)}`
const n0 = (v: number | null) => v == null ? '—' : v.toLocaleString().replace('-', '−')

// Columns per category: value() sorts, text() shows. rate = only meaningful for qualified players.
type Col = { key: string; label: string; value: (r: Row) => number | null; text?: (r: Row) => string; info?: string; rate?: boolean }
const c = (key: string, label: string, extra: Partial<Col> = {}): Col => ({ key, label, value: r => r[key] ?? null, ...extra })
const sr: Col = { key: 'sr', label: 'SR%', value: r => div(r.sr_successes, r.sr_plays), text: r => pct(div(r.sr_successes, r.sr_plays)), rate: true,
  info: 'Success rate (CollegeFootballData): share of the player’s plays that gained enough yardage for the down and distance.' }
const COLS: Record<Cat, Col[]> = {
  passing: [
    c('passing_completions', 'Cmp'), c('passing_att', 'Att'),
    { key: 'pct', label: 'Cmp%', value: r => div(r.passing_completions, r.passing_att), text: r => pct(div(r.passing_completions, r.passing_att)), rate: true },
    c('passing_yds', 'Yds', { text: r => n0(r.passing_yds) }),
    { key: 'ya', label: 'Y/A', value: r => div(r.passing_yds, r.passing_att), text: r => f1(div(r.passing_yds, r.passing_att)), rate: true, info: 'Passing yards per attempt.' },
    c('passing_td', 'TD'), c('passing_int', 'INT'),
    c('rating', 'Passer Rating', { text: r => f1(r.rating), rate: true, info: 'Passer rating (NCAA passer efficiency): (8.4 × yards + 330 × TD + 100 × completions − 200 × INT) ÷ attempts.' }),
    c('ppa_avg', 'PPA/Play', { text: r => r.ppa_avg == null ? '—' : r.ppa_avg.toFixed(2).replace('-', '−'), rate: true, info: `${PPA_INFO}Passing plays.` }),
    sr,
  ],
  rushing: [
    c('rushing_car', 'Car'), c('rushing_yds', 'Yds', { text: r => n0(r.rushing_yds) }),
    { key: 'yc', label: 'Y/C', value: r => div(r.rushing_yds, r.rushing_car), text: r => f1(div(r.rushing_yds, r.rushing_car)), rate: true, info: 'Rushing yards per carry.' },
    c('rushing_td', 'TD'), c('rushing_long', 'Long'),
    c('ppa_avg', 'PPA/Play', { text: r => r.ppa_avg == null ? '—' : r.ppa_avg.toFixed(2).replace('-', '−'), rate: true, info: `${PPA_INFO}Rushing plays.` }),
    sr,
    c('usage', 'Rush Share %', { text: r => pct(r.usage), info: 'Player usage (CollegeFootballData): share of the team’s rushing plays on which the player carried the ball.' }),
    c('fumbles_lost', 'Fum Lost'),
  ],
  receiving: [
    c('receiving_rec', 'Rec'), c('receiving_yds', 'Yds', { text: r => n0(r.receiving_yds) }),
    { key: 'yr', label: 'Y/R', value: r => div(r.receiving_yds, r.receiving_rec), text: r => f1(div(r.receiving_yds, r.receiving_rec)), rate: true, info: 'Receiving yards per catch. Targets are not in the data, so there is no catch rate.' },
    c('receiving_td', 'TD'), c('receiving_long', 'Long'),
    c('ppa_avg', 'PPA/Play', { text: r => r.ppa_avg == null ? '—' : r.ppa_avg.toFixed(2).replace('-', '−'), rate: true, info: `${PPA_INFO}Passing plays credited to the receiver.` }),
    c('usage', 'Pass Share %', { text: r => pct(r.usage), info: 'Player usage (CollegeFootballData): share of the team’s passing plays credited to the player.' }),
  ],
  defense: [
    c('defensive_solo', 'Solo', { info: 'Solo tackles.' }), { key: 'ast', label: 'Ast', value: r => r.defensive_tot != null && r.defensive_solo != null ? r.defensive_tot - r.defensive_solo : null, info: 'Assisted tackles: total tackles minus solo tackles.' },
    c('defensive_tot', 'Tot', { info: 'Total tackles.' }), c('defensive_tfl', 'TFL', { info: 'Tackles for loss.' }), c('defensive_sacks', 'Sacks'),
    c('defensive_qb_hur', 'QBH', { info: 'Quarterback hurries.' }), c('defensive_pd', 'PD', { info: 'Passes defended.' }),
    c('interceptions_int', 'INT'), c('interceptions_yds', 'INT Yds', { text: r => n0(r.interceptions_yds), info: 'Interception return yards.' }),
  ],
  kicking: [
    c('kicking_fgm', 'FGM', { info: 'Field goals made.' }), c('kicking_fga', 'FGA', { info: 'Field goals attempted.' }),
    { key: 'fgp', label: 'FG%', value: r => div(r.kicking_fgm, r.kicking_fga), text: r => pct(div(r.kicking_fgm, r.kicking_fga)), rate: true },
    c('kicking_long', 'LNG', { info: 'Longest field goal made.' }),
    c('kicking_xpm', 'XPM', { info: 'Extra points made.' }), c('kicking_xpa', 'XPA', { info: 'Extra points attempted.' }),
    { key: 'xpp', label: 'XP%', value: r => div(r.kicking_xpm, r.kicking_xpa), text: r => pct(div(r.kicking_xpm, r.kicking_xpa)), info: 'Extra-point percentage.' },
  ],
  punting: [
    c('punting_no', 'Punts'), c('punting_yds', 'Yds', { text: r => n0(r.punting_yds) }),
    { key: 'avg', label: 'Avg', value: r => div(r.punting_yds, r.punting_no), text: r => f1(div(r.punting_yds, r.punting_no)), rate: true, info: 'Gross yards per punt.' },
    c('punting_long', 'Long'), c('punting_in_20', 'In 20'), c('punting_tb', 'TB', { info: 'Touchbacks.' }),
  ],
}

// Column groups, in display order (the header row above the column names, as in a box-score table).
const GROUPS: Record<Cat, { label: string; keys: string[] }[]> = {
  passing: [{ label: 'Passing', keys: ['passing_completions', 'passing_att', 'pct', 'passing_yds', 'ya', 'passing_td', 'passing_int', 'rating'] }, { label: 'Advanced', keys: ['ppa_avg', 'sr'] }],
  rushing: [{ label: 'Rushing', keys: ['rushing_car', 'rushing_yds', 'yc', 'rushing_td', 'rushing_long', 'fumbles_lost'] }, { label: 'Advanced', keys: ['ppa_avg', 'sr', 'usage'] }],
  receiving: [{ label: 'Receiving', keys: ['receiving_rec', 'receiving_yds', 'yr', 'receiving_td', 'receiving_long'] }, { label: 'Advanced', keys: ['ppa_avg', 'usage'] }],
  defense: [{ label: 'Tackles', keys: ['defensive_solo', 'ast', 'defensive_tot', 'defensive_tfl'] }, { label: 'Pass Rush', keys: ['defensive_sacks', 'defensive_qb_hur'] }, { label: 'Pass Defense', keys: ['defensive_pd', 'interceptions_int', 'interceptions_yds'] }],
  kicking: [{ label: 'Field Goals', keys: ['kicking_fgm', 'kicking_fga', 'fgp', 'kicking_long'] }, { label: 'Extra Points', keys: ['kicking_xpm', 'kicking_xpa', 'xpp'] }],
  punting: [{ label: 'Punting', keys: ['punting_no', 'punting_yds', 'avg', 'punting_long', 'punting_in_20', 'punting_tb'] }],
}

// Roster positions vary in detail by team (DL vs DE/DT/EDGE, DB vs CB/S), so the filter works on groups.
const GROUP: Record<string, string> = { FB: 'RB', OT: 'OL', OG: 'OL', G: 'OL', C: 'OL', DE: 'DL', DT: 'DL', NT: 'DL', EDGE: 'DL', ILB: 'LB', OLB: 'LB', MLB: 'LB', CB: 'DB', S: 'DB', SAF: 'DB', FS: 'DB', SS: 'DB', PK: 'K' }
const group = (p: string | null) => p ? GROUP[p] ?? p : ''
const GROUP_ORDER = ['QB', 'RB', 'WR', 'TE', 'OL', 'DL', 'LB', 'DB', 'K', 'P', 'LS', 'ATH']
const CLASS = ['', 'FR', 'SO', 'JR', 'SR', '5th', '6th']
const SHOW = 100
const LINE = '1px solid var(--cf-line)'          // divider before each column group
const SORTED = 'var(--cf-accent-soft)'            // shading for the column the table is sorted by
// Opening sort per category (the files are ordered by volume, which also sets the qualifier).
// The three columns kept on phones; the rest are hidden there (cf-hide-sm).
const PHONE: Record<Cat, string[]> = { passing: ['passing_yds', 'passing_td', 'ppa_avg'], rushing: ['rushing_yds', 'yc', 'rushing_td'], receiving: ['receiving_rec', 'receiving_yds', 'receiving_td'],
  defense: ['defensive_tot', 'defensive_tfl', 'defensive_sacks'], kicking: ['kicking_fgm', 'fgp', 'kicking_long'], punting: ['punting_no', 'avg', 'punting_in_20'] }
const DEFAULT_SORT: Record<Cat, string> = { passing: 'rating', rushing: 'rushing_yds', receiving: 'receiving_yds', defense: 'defensive_tot', kicking: 'kicking_fgm', punting: 'avg' }

export default function Players() {
  const [cat, setCat] = useQueryParam('cat', 'passing')
  const ratings = cat === 'ratings'
  const category = (CATS.some(x => x.value === cat) ? cat : 'passing') as Cat
  const board = useData<Board>(ratings ? null : `players/leaders/${category}.json`)
  return <>
    <PageHead title="Players" />
    <div style={{ overflowX: 'auto', maxWidth: '100%', margin: '20px 0 20px' }}><Segmented label="Category" value={ratings ? 'ratings' : category} options={VIEWS} onChange={v => setCat(v)} /></div>
    {ratings ? <Suspense fallback={null}><RatingsView /></Suspense>
      : <DataGate source={board} label="Leaderboard">{d => d.category === category ? <Leaderboard board={d} /> : null}</DataGate>}
  </>
}

function Leaderboard({ board }: { board: Board }) {
  const teams = useTeams()
  const open = useOpenPlayer()
  const [conf, setConf] = useQueryParam('conf')
  const [team, setTeam] = useQueryParam('team')
  const [pos, setPos] = useQueryParam('pos')
  const [cls, setCls] = useQueryParam('class')
  const [all, setAll] = useQueryParam('all')
  const [sortKey, setSortKey] = useQueryParam('sort')
  const [dir, setDir] = useQueryParam('dir')
  const [more, setMore] = useState(false)
  const colGroups = GROUPS[board.category]
  const cols = colGroups.flatMap(g => g.keys.map(k => COLS[board.category].find(x => x.key === k)!))
  const firstOfGroup = new Set(colGroups.map(g => g.keys[0]))
  const rows = useMemo(() => board.rows.map(r => Object.fromEntries(board.columns.map((k, i) => [k, r[i]])) as unknown as Row), [board])
  if (board.through_week == null) return <div className="cf-state"><p className="cf-state-title">Leaderboards are not available this week</p><p className="cf-muted">{board.unavailable}</p></div>

  const col = cols.find(x => x.key === sortKey) ?? cols.find(x => x.key === DEFAULT_SORT[board.category]) ?? cols[0]
  const sort: Sort = { key: col.key, desc: dir !== 'asc' }
  const onSort = (s: Sort) => { setSortKey(s.key); setDir(s.desc ? '' : 'asc') }
  const qualOnly = board.qualifier != null && all !== '1'
  const confs = [...new Set(rows.map(r => teams.get(r.team_id)?.conference).filter(Boolean) as string[])].sort()
  const teamOpts = [...new Set(rows.map(r => r.team_id))].filter(id => !conf || teams.get(id)?.conference === conf)
    .sort((a, b) => (teams.get(a)?.team ?? '').localeCompare(teams.get(b)?.team ?? ''))
  const groups = GROUP_ORDER.filter(g => rows.some(r => group(r.position) === g))
  const shown = sortRows(rows.filter(r => (!qualOnly || r.q) && (!conf || teams.get(r.team_id)?.conference === conf) && (!team || r.team_id === team)
    && (!pos || group(r.position) === pos) && (!cls || String(r.class) === cls)), col.value, sort.desc)
  const list = more ? shown : shown.slice(0, SHOW)
  const q = board.qualifier
  const pulledOut = [board.ppa, board.usage].find(p => p && !p.available)

  return <>
    <div className="cf-toolbar" style={{ alignItems: 'end', gap: '12px 16px', marginBottom: 12 }}>
      <Select label="Conference" value={conf} onChange={v => { setConf(v); setTeam('') }}><option value="">All</option>{confs.map(x => <option key={x} value={x}>{x}</option>)}</Select>
      <Select label="Team" value={team} onChange={setTeam}><option value="">All</option>{teamOpts.map(id => <option key={id} value={id}>{teams.get(id)?.team ?? id}</option>)}</Select>
      <Select label="Position" value={pos} onChange={setPos}><option value="">All</option>{groups.map(g => <option key={g} value={g}>{g}</option>)}</Select>
      <Select label="Class" value={cls} onChange={setCls}><option value="">All</option>{[1, 2, 3, 4].map(k => <option key={k} value={String(k)}>{CLASS[k]}</option>)}</Select>
      {q && <label className="cf-check" style={{ height: 40, alignItems: 'center' }}><input type="checkbox" checked={qualOnly} onChange={e => setAll(e.target.checked ? '' : '1')} /> Qualified only</label>}
    </div>
    <p className="cf-muted cf-small" style={{ margin: '0 0 12px' }} role="status">{shown.length} players · Season stats through Week {board.through_week} · Regular season · FBS</p>
    {shown.length === 0 ? <div className="cf-state"><p className="cf-state-title">No players match</p></div> :
    <div className="cf-table-wrap"><table className="cf-table cf-players-table">
      <colgroup><col /></colgroup>
      <thead>
        <tr className="cf-hide-sm">{/* group labels; hidden on phones, where only three columns show */}
          <th aria-hidden="true" style={{ position: 'static' }} />
          {colGroups.map(g => <th key={g.label} colSpan={g.keys.length} scope="colgroup" style={{ position: 'static', textAlign: 'center', textTransform: 'uppercase', letterSpacing: '.04em', fontSize: '.6875rem', borderLeft: LINE }}>{g.label}</th>)}
        </tr>
        <tr>
          <th scope="col" className="cf-th-start">Player</th>
          {cols.map(x => <SortTh key={x.key} label={x.label} sortKey={x.key} sort={sort} onSort={onSort} info={x.info} align="start"
            style={{ textAlign: 'center', borderLeft: firstOfGroup.has(x.key) ? LINE : undefined, background: x.key === col.key ? SORTED : undefined, whiteSpace: x.label.length > 8 ? 'normal' : undefined, lineHeight: 1.2 }} className={PHONE[board.category].includes(x.key) ? '' : 'cf-hide-sm'} />)}
        </tr>
      </thead>
      <tbody>{list.map(r => {
        const t = teams.get(r.team_id)
        return <tr key={r.athlete_id} className="cf-row-link" onClick={() => open(r.athlete_id)}>
          <td><span className="cf-team"><Headshot id={r.athlete_id} teamId={r.team_id} name={t?.team ?? ''} />
            <span className="cf-team-text"><PlayerLink id={r.athlete_id} className="" style={{ textDecoration: 'none' }}>{r.player}</PlayerLink>
              <span className="cf-team-sub" style={{ display: 'inline-flex', alignItems: 'center', gap: 5 }}><TeamLogo id={r.team_id} name={t?.team ?? ''} size={14} /><span aria-hidden="true">·</span>{[r.position, r.class ? `${r.rs ? 'RS ' : ''}${CLASS[r.class]}` : null].filter(Boolean).join(' · ')}{qualOnly || r.q || !q ? '' : ' · not qualified'}</span></span></span></td>
          {cols.map(x => <td key={x.key} className={`cf-num${PHONE[board.category].includes(x.key) ? '' : ' cf-hide-sm'}`} style={{ textAlign: 'center', borderLeft: firstOfGroup.has(x.key) ? LINE : undefined, background: x.key === col.key ? SORTED : undefined, whiteSpace: x.label.length > 8 ? 'normal' : undefined, lineHeight: 1.2 }}>{x.text ? x.text(r) : n0(x.value(r))}</td>)}
        </tr>
      })}</tbody>
    </table></div>}
    {shown.length > SHOW && <p><button type="button" className="cf-btn" onClick={() => setMore(m => !m)}>{more ? `Show top ${SHOW}` : `Show all ${shown.length}`}</button></p>}
    <p className="cf-small cf-muted">
      {q ? `Qualified: ${q.text} ` : ''}Listed: {board.floor} Team games are the team’s regular-season games through Week {board.through_week}.
      {pulledOut ? ` PPA or usage is omitted this week: the CollegeFootballData pull ${pulledOut.reason}.` : ''}
      {' '}CollegeFootballData has no snap counts or targets, so there are no per-snap or per-target rates. Source: CollegeFootballData (season player stats, player PPA, player success, player usage, roster).
    </p>
  </>
}
