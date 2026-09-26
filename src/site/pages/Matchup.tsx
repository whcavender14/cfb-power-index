import { useState, type ReactNode } from 'react'
import { DataGate, fmt, fmtSigned, Info, Missing, pctText, TeamLink, TeamLogo, useData, useTeams } from '../components'
import type { EfficiencyDoc, Efficiency, Game, GamesDoc, IndexDoc, TeamRow, UsageDoc } from '../data'
import { kickoffText, projection, useLines, WINPROB_INFO } from '../games'
import { Link } from '../router'
import { STAT_GROUPS, statRank, statValue, type StatDef } from '../stats'
import NotFound from './NotFound'

// Matchup breakdown (/games/<game_id>/): the model's forecast, the sportsbook line when one exists (evaluation only),
// and both teams side by side. Every number is precomputed (games.json, index.json, efficiency.json, usage/<slug>.json,
// betting.json); a section whose data is missing for both teams is left out rather than shown empty.

const MODEL_LINE_INFO = 'The model’s implied line: its projected margin written as a point spread (negative = that team favored), from the ratings through the latest week plus home-field advantage. The model predicts margins only; it has no total or score.'
const MARKET_INFO = 'One sportsbook quote (spread and over/under) retrieved from CollegeFootballData before kickoff. Shown for comparison only: it is never an input to CFPi+ and is not used to evaluate or adjust the ratings on this page.'

/** Home-perspective spread in betting convention (negative = home favored) as "Team −X". */
const spreadText = (home: string, away: string, v: number) => Math.abs(v) < 0.05 ? 'Pick’em' : v < 0 ? `${home} −${fmt(-v)}` : `${away} −${fmt(v)}`

function Side({ label, away, home, better }: { label: ReactNode; away: ReactNode; home: ReactNode; better?: 'away' | 'home' | null }) {
  return <div className="cf-mu-row">
    <span className={`cf-mu-a${better === 'away' ? ' is-better' : ''}`}>{away}</span>
    <span className="cf-mu-label">{label}</span>
    <span className={`cf-mu-h${better === 'home' ? ' is-better' : ''}`}>{home}</span>
  </div>
}
const valRank = (v: ReactNode, r: number | null | undefined) => <>{v}{r ? <small className="cf-mu-rank">No. {r}</small> : null}</>
const betterOf = (ra: number | null | undefined, rh: number | null | undefined) => ra == null || rh == null || ra === rh ? null : ra < rh ? 'away' : 'home'

function StatSides({ d, a, h }: { d: StatDef; a?: Efficiency; h?: Efficiency }) {
  const va = statValue(a, d.key), vh = statValue(h, d.key), ra = statRank(a, d.key), rh = statRank(h, d.key)
  if (va == null && vh == null) return null
  return <Side label={<>{d.label}{d.lower && <span className="cf-lower">↓ better</span>}</>} better={d.neutral ? null : betterOf(ra, rh)}
    away={va == null ? <Missing /> : valRank(d.show(va), ra)} home={vh == null ? <Missing /> : valRank(d.show(vh), rh)} />
}

type Star = { key: string; name: string; pos: string; line: string; headshot?: string | null; jersey?: number | null }
/** Key players from the team's usage file: starters from the depth chart where it fits, else by usage and production. */
function stars(u: UsageDoc | null): Star[] {
  if (!u) return []
  const depth = u.depth ?? []
  const face = (name: string) => depth.flatMap(r => r.players).find(p => p.name === name)
  const out: Star[] = []
  const add = (s: Star | null) => { if (s && !out.some(o => o.name === s.name)) out.push(s) }
  const qbStarter = depth.find(r => r.group === 'QB')?.players[0]
  const qbUse = u.offense?.QB?.[0]
  const qbName = qbStarter?.name ?? qbUse?.name
  if (qbName) add({ key: 'qb', name: qbName, pos: 'QB', line: [qbStarter?.snaps != null ? `${qbStarter.snaps}% snaps` : null, qbUse && qbUse.name === qbName ? `${Math.round(qbUse.usg_overall * 100)}% of plays` : null].filter(Boolean).join(' · ') || 'Starter', headshot: face(qbName)?.headshot, jersey: face(qbName)?.jersey })
  for (const [g, pos, n] of [['RB', 'RB', 1], ['WR', 'WR', 2], ['TE', 'TE', 1]] as const) for (const p of (u.offense?.[g] ?? []).slice(0, n))
    add({ key: `${g}-${p.athlete_id}`, name: p.name, pos, line: `${Math.round(p.usg_overall * 100)}% of plays`, headshot: p.headshot ?? face(p.name)?.headshot, jersey: p.jersey })
  const defs = [...(u.defense?.DL ?? []), ...(u.defense?.LB ?? []), ...(u.defense?.DB ?? [])]
  const topTackle = [...defs].sort((x, y) => y.tackles - x.tackles).slice(0, 2)
  const topSack = [...defs].sort((x, y) => y.sacks - x.sacks || y.tfl - x.tfl)[0]
  for (const p of [...topTackle, ...(topSack && topSack.sacks > 0 ? [topSack] : [])])
    add({ key: `d-${p.athlete_id}`, name: p.name, pos: p.roster_pos ?? p.position ?? 'DEF', line: `${p.tackles} tkl · ${p.tfl} TFL · ${p.sacks} sk${p.int ? ` · ${p.int} INT` : ''}`, headshot: p.headshot ?? face(p.name)?.headshot, jersey: p.jersey })
  return out
}
function StarCard({ s }: { s: Star }) {
  const [broken, setBroken] = useState(false)
  return <li className="cf-mu-star">
    <span className="cf-dc-face">{s.headshot && !broken ? <img src={s.headshot} alt="" loading="lazy" onError={() => setBroken(true)} /> : <span aria-hidden="true">{s.name.split(/\s+/).map(w => w[0]).slice(0, 2).join('')}</span>}</span>
    <span className="cf-mu-star-text"><strong>{s.name}</strong><span className="cf-muted cf-small">{s.pos}{s.jersey != null ? ` · #${s.jersey}` : ''}</span><span className="cf-small cf-num">{s.line}</span></span>
  </li>
}

function TeamHead({ id, name, row, side, g }: { id: string; name: string; row?: TeamRow; side: 'home' | 'away'; g: Game }) {
  const flag = g.neutral ? 'Neutral' : side === 'home' ? 'Home' : 'Away'
  const pts = g.status === 'final' ? (side === 'home' ? g.home_points : g.away_points) : null
  return <div className={`cf-mu-team is-${side}`}>
    <TeamLogo id={id} name={name} size={64} />
    <div className="cf-mu-team-text">
      <span className="cf-mu-flag">{flag}</span>
      <strong className="cf-mu-name"><TeamLink id={id} name={name} logo={false} /></strong>
      <span className="cf-muted cf-small">{row ? [row.rank ? `No. ${row.rank} CFPi+` : null, row.wins != null ? `${row.wins}–${row.losses}` : null].filter(Boolean).join(' · ') : 'Not rated (non-FBS)'}</span>
    </div>
    {pts != null && <span className="cf-mu-score cf-num">{pts}</span>}
  </div>
}

export default function Matchup({ id }: { id: string }) {
  const games = useData<GamesDoc>('games.json')
  const index = useData<IndexDoc>('index.json')
  const eff = useData<EfficiencyDoc>('efficiency.json')
  const dir = useTeams()
  const g0 = games.data?.games.find(x => x.game_id === id)
  const slugA = g0 ? dir.get(g0.away_id)?.slug : undefined, slugH = g0 ? dir.get(g0.home_id)?.slug : undefined
  const ua = useData<UsageDoc>(slugA ? `usage/${slugA}.json` : null), uh = useData<UsageDoc>(slugH ? `usage/${slugH}.json` : null)
  const lines = useLines()
  if (games.data && !g0) return <NotFound />
  return <DataGate source={games} label="Game">{() => {
    const g = g0!
    const rows = new Map((index.data?.teams ?? []).map(t => [t.team_id, t]))
    const ra = rows.get(g.away_id), rh = rows.get(g.home_id)
    const effs = new Map((eff.data?.teams ?? []).map(t => [t.team_id, t]))
    const ea = effs.get(g.away_id), eh = effs.get(g.home_id)
    const total = (eff.data?.teams ?? []).filter(t => t.plays != null || t.games != null).length
    const p = projection(g)
    const probHome = g.win_prob_home, probAway = probHome == null ? null : 1 - probHome
    const modelLine = g.spread_home == null ? null : -g.spread_home                 // betting convention, home perspective
    const line = lines.get(g.game_id)
    const diff = modelLine != null && line?.market_spread != null ? modelLine - line.market_spread : null
    const sa = stars(ua.data), sh = stars(uh.data)
    const groups = STAT_GROUPS.map(gr => ({ ...gr, defs: gr.defs.filter(d => statValue(ea, d.key) != null || statValue(eh, d.key) != null) })).filter(gr => gr.defs.length)
    const sep = g.neutral ? 'vs' : 'at'
    const oneSided: 'home' | 'away' | null = ra && !rh && !eh ? 'away' : rh && !ra && !ea ? 'home' : null   // one side not rated (non-FBS)
    return <>
      <nav className="cf-crumbs" aria-label="Breadcrumb"><Link to={`/games/?week=${g.week}`}>← Games</Link><span aria-hidden="true"> / </span><span aria-current="page">Week {g.week}</span></nav>
      <header className="cf-panel cf-mu-head">
        <TeamHead id={g.away_id} name={g.away_team} row={ra} side="away" g={g} />
        <div className="cf-mu-mid">
          <span className="cf-mu-vs">{g.status === 'final' ? 'Final' : sep}</span>
          <span className="cf-small">{kickoffText(g)}</span>
          {g.venue && <span className="cf-small cf-muted">{g.venue}{g.neutral ? ' (neutral site)' : ''}</span>}
          {g.conference_game && <span className="cf-small cf-muted">Conference game</span>}
        </div>
        <TeamHead id={g.home_id} name={g.home_team} row={rh} side="home" g={g} />
      </header>
      <h1 className="cf-sr">{g.away_team} {sep} {g.home_team}, Week {g.week}</h1>

      <div className="cf-mu-grid">
        <section className="cf-panel" aria-labelledby="mu-fc">
          <h2 id="mu-fc" className="cf-h2">Model forecast</h2>
          {p && probHome != null ? <dl className="cf-kv cf-kv-2">
            <div><dt>Model line <Info text={MODEL_LINE_INFO} label="About the model line" /></dt><dd>{spreadText(g.home_team, g.away_team, modelLine!)}</dd></div>
            <div><dt>Projected margin</dt><dd>{p.margin < 0.05 ? 'Even' : <>{p.favorite} by <span className="cf-num">{fmt(p.margin)}</span></>}</dd></div>
            <div><dt>{g.away_team} win <Info text={WINPROB_INFO} label="About win probability" /></dt><dd className="cf-num">{pctText(probAway)}</dd></div>
            <div><dt>{g.home_team} win</dt><dd className="cf-num">{pctText(probHome)}</dd></div>
          </dl> : <p className="cf-muted">{g.status === 'final' ? 'Final. The site shows forecasts for upcoming games only; the pre-game projection is not stored.' : 'No projection for this game.'}</p>}
          <p className="cf-small cf-muted">The model predicts the margin, not points, so it has no implied score or total of its own.</p>
        </section>

        {line && <section className="cf-panel" aria-labelledby="mu-mk">
          <h2 id="mu-mk" className="cf-h2">Sportsbook line <span className="cf-tag">Evaluation only</span> <Info text={MARKET_INFO} label="About the sportsbook line" /></h2>
          <dl className="cf-kv cf-kv-2">
            <div><dt>Market line{line.market_provider ? ` (${line.market_provider})` : ''}</dt><dd>{spreadText(g.home_team, g.away_team, line.market_spread!)}</dd></div>
            <div><dt>Model line</dt><dd>{modelLine != null ? spreadText(g.home_team, g.away_team, modelLine) : <Missing />}</dd></div>
            {line.market_total != null && <div><dt>Market total (over/under)</dt><dd className="cf-num">{fmt(line.market_total)}</dd></div>}
            {diff != null && <div><dt>Model vs market</dt><dd>{Math.abs(diff) < 0.05 ? 'Same line' : <><span className="cf-num">{fmt(Math.abs(diff))}</span> pts more on {diff < 0 ? g.home_team : g.away_team}</>}</dd></div>}
          </dl>
          <p className="cf-small cf-muted">Not a CFPi+ input. The total is the market’s; CFPi+ does not forecast totals.</p>
        </section>}
      </div>

      {(ra || rh || groups.length > 0) && <section className={`cf-panel cf-mu-compare${oneSided ? ` is-one-${oneSided}` : ''}`} aria-labelledby="mu-cmp">
        <div className="cf-mu-cmp-head">
          <span className="cf-mu-cmp-a"><TeamLogo id={g.away_id} name={g.away_team} size={24} /> {g.away_team}</span>
          <h2 id="mu-cmp" className="cf-h2">{oneSided ? (oneSided === 'home' ? g.home_team : g.away_team) : 'Head to head'}</h2>
          <span className="cf-mu-cmp-h">{g.home_team} <TeamLogo id={g.home_id} name={g.home_team} size={24} /></span>
        </div>
        {oneSided && <p className="cf-small cf-muted cf-mu-one-note">{oneSided === 'home' ? g.away_team : g.home_team} is not an FBS team, so it has no CFPi+ rating or stats to compare; {oneSided === 'home' ? g.home_team : g.away_team}’s are shown alone.</p>}
        {(ra || rh) && <div className="cf-mu-group"><h3 className="cf-h3">Ratings <span className="cf-eff-note">· CFPi+ points vs an average FBS team</span></h3>
          <Side label="Power" better={betterOf(ra?.rank, rh?.rank)} away={ra ? valRank(fmtSigned(ra.power), ra.rank) : <Missing why="Not rated" />} home={rh ? valRank(fmtSigned(rh.power), rh.rank) : <Missing why="Not rated" />} />
          <Side label="Offense" better={betterOf(ra?.off_rank, rh?.off_rank)} away={ra ? valRank(fmtSigned(ra.off), ra.off_rank) : <Missing />} home={rh ? valRank(fmtSigned(rh.off), rh.off_rank) : <Missing />} />
          <Side label={<>Defense<span className="cf-lower">↓ better</span></>} better={betterOf(ra?.def_rank, rh?.def_rank)} away={ra ? valRank(fmtSigned(ra.def), ra.def_rank) : <Missing />} home={rh ? valRank(fmtSigned(rh.def), rh.def_rank) : <Missing />} />
        </div>}
        {groups.map(gr => <div key={gr.id} className="cf-mu-group">
          <h3 className="cf-h3">{gr.title}{gr.note && <span className="cf-eff-note"> · {gr.note}</span>}{gr.raw && <span className="cf-tag">Raw, not opponent-adjusted</span>}</h3>
          {gr.defs.map(d => <StatSides key={d.key} d={d} a={ea} h={eh} />)}
        </div>)}
        <p className="cf-small cf-muted">Ranks among {total || 'FBS'} FBS teams, No. 1 = best; the better rank in each row is highlighted. Stats are per game over each team’s regular-season games in the ratings; none are opponent-adjusted except the CFPi+ ratings.{(!ra || !rh) ? ' Non-FBS teams have no CFPi+ stats.' : ''}</p>
      </section>}

      {(sa.length > 0 || sh.length > 0) && <section className="cf-panel" aria-labelledby="mu-stars">
        <h2 id="mu-stars" className="cf-h2">Key players</h2>
        <div className="cf-mu-stars">
          {[[g.away_id, g.away_team, sa], [g.home_id, g.home_team, sh]].map(([tid, name, list]) => <div key={tid as string}>
            <h3 className="cf-h3"><TeamLogo id={tid as string} name={name as string} size={20} /> {name as string}</h3>
            {(list as Star[]).length ? <ul className="cf-mu-star-list">{(list as Star[]).map(s => <StarCard key={s.key} s={s} />)}</ul> : <p className="cf-muted cf-small">No player data (non-FBS team).</p>}
          </div>)}
        </div>
        <p className="cf-small cf-muted">Quarterback from the depth chart (TWO·DEEP, with permission); other players by share of team plays (CollegeFootballData usage, season to date) and defensive production through the ratings week. Injury status is not shown.</p>
      </section>}
    </>
  }}</DataGate>
}
