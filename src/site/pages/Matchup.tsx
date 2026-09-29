import '../matchup.css'
import { useState, type ReactNode } from 'react'
import { PlayerLink } from '../player'
import { DataGate, fmt, fmtSigned, Info, Missing, pctText, TeamLink, TeamLogo, useData, useTeams } from '../components'
import type { EfficiencyDoc, Efficiency, Game, GamesDoc, IndexDoc, KeyPlayer, TeamRow, UsageDoc } from '../data'
import { kickoffText, QUALITY_INFO, useLines } from '../games'
import { Link } from '../router'
import { STAT_GROUPS, statRank, statValue, type StatDef } from '../stats'
import NotFound from './NotFound'
import GameRecap from '../GameRecap'
import { teamTheme } from '../teamTheme'

// Matchup breakdown (/games/<game_id>/): the model's forecast, the sportsbook line when one exists (evaluation only),
// and both teams side by side. Every number is precomputed (games.json, index.json, efficiency.json, usage/<slug>.json,
// betting.json); a section whose data is missing for both teams is left out rather than shown empty.

const MODEL_LINE_INFO = 'The model’s implied line: its projected margin written as a point spread (negative = that team favored), from the ratings through the latest week plus home-field advantage. The model predicts margins only; it has no total or score.'
const MARKET_INFO = 'One sportsbook quote (spread and over/under) retrieved from CollegeFootballData before kickoff. Shown for comparison only: it is never an input to CFPi+ and is not used to evaluate or adjust the ratings on this page.'

/** Home-perspective spread in betting convention (negative = home favored) as "Team −X". */
const spreadText = (home: string, away: string, v: number) => Math.abs(v) < 0.05 ? 'Pick’em' : v < 0 ? `${home} −${fmt(-v)}` : `${away} −${fmt(v)}`

function Side({ label, away, home, better }: { label: ReactNode; away: ReactNode; home: ReactNode; better?: 'away' | 'home' | null }) {
  return <div className={`cf-mu-row${better ? ` is-better-${better}` : ''}`}>
    <span className={`cf-mu-a${better === 'away' ? ' is-better' : ''}`}>{away}</span>
    <span className="cf-mu-label">{label}</span>
    <span className={`cf-mu-h${better === 'home' ? ' is-better' : ''}`}>{home}</span>
  </div>
}
const valRank = (v: ReactNode, r: number | null | undefined) => <><span className="cf-mu-val">{v}</span><small className="cf-mu-rank">{r ? `No. ${r}` : ''}</small></>
const betterOf = (ra: number | null | undefined, rh: number | null | undefined) => ra == null || rh == null || ra === rh ? null : ra < rh ? 'away' : 'home'

function StatSides({ d, a, h }: { d: StatDef; a?: Efficiency; h?: Efficiency }) {
  const va = statValue(a, d.key), vh = statValue(h, d.key), ra = statRank(a, d.key), rh = statRank(h, d.key)
  if (va == null && vh == null) return null
  return <Side label={<>{d.label}{d.lower && <span className="cf-lower">↓ better</span>}</>} better={d.neutral ? null : betterOf(ra, rh)}
    away={va == null ? <Missing /> : valRank(d.show(va), ra)} home={vh == null ? <Missing /> : valRank(d.show(vh), rh)} />
}

type Star = { id: string; key: string; name: string; pos: string; line: string; headshot?: string | null; jersey?: number | null }
const yd = (n: number) => `${n.toLocaleString()} yds`
/** Season stat line for a key player (CFBD season stats through the ratings week), by the role they were picked for. */
function statLine(p: KeyPlayer): string {
  const td = (n: number) => n ? ` · ${n} TD` : ''
  switch (p.role) {
    case 'passing': return `${p.pass_cmp}/${p.pass_att} · ${yd(p.pass_yds)}${td(p.pass_td)} · ${p.pass_int} INT${p.rush_yds ? ` · ${p.rush_yds} rush yds` : ''}`
    case 'rushing': return `${p.rush_car} car · ${yd(p.rush_yds)}${td(p.rush_td)}${p.rec ? ` · ${p.rec} rec, ${p.rec_yds} yds` : ''}`
    case 'receiving': return `${p.rec} rec · ${yd(p.rec_yds)}${td(p.rec_td)}`
    default: return `${p.tackles} tkl · ${p.tfl} TFL · ${p.sacks} sk${p.int ? ` · ${p.int} INT` : ''}`
  }
}
function stars(u: UsageDoc | null): Star[] {
  return (u?.key_players ?? []).map(p => ({ key: `${p.role}-${p.athlete_id}`, id: p.athlete_id, name: p.name, pos: p.position ?? '', line: statLine(p), headshot: p.headshot, jersey: p.jersey }))
}
function StarCard({ s }: { s: Star }) {
  const [broken, setBroken] = useState(false)
  return <li className="cf-mu-star">
    <span className="cf-dc-face">{s.headshot && !broken ? <img src={s.headshot} alt="" loading="lazy" onError={() => setBroken(true)} /> : <span aria-hidden="true">{s.name.split(/\s+/).map(w => w[0]).slice(0, 2).join('')}</span>}</span>
    <span className="cf-mu-star-text"><strong><PlayerLink id={s.id}>{s.name}</PlayerLink></strong><span className="cf-muted cf-small">{s.pos}{s.jersey != null ? ` · #${s.jersey}` : ''}</span><span className="cf-small cf-num">{s.line}</span></span>
  </li>
}

function TeamHead({ id, name, row, side, g }: { id: string; name: string; row?: TeamRow; side: 'home' | 'away'; g: Game }) {
  const flag = g.neutral ? 'Neutral' : side === 'home' ? 'Home' : 'Away'
  const pts = g.status === 'final' ? (side === 'home' ? g.home_points : g.away_points) : null
  const t = useTeams().get(id)
  return <div className={`cf-mu-team is-${side}`} style={teamTheme(t?.color ?? null, t?.alt_color ?? null)}>
    <span className="cf-mu-logotile"><TeamLogo id={id} name={name} size={64} /></span>
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
    const probHome = g.win_prob_home, probAway = probHome == null ? null : 1 - probHome
    const modelLine = g.spread_home == null ? null : -g.spread_home                 // betting convention, home perspective
    const line = lines.get(g.game_id)
    const diff = modelLine != null && line?.market_spread != null ? modelLine - line.market_spread : null
    // Value side: the team the model likes more than the market does, at the market's number (home-perspective spread m,
    // negative = home favored). Model less bullish on the home team than Vegas (diff > 0) -> away team at -m; else home at m.
    const signedLine = (v: number) => v === 0 ? 'Pick’em' : v > 0 ? `+${fmt(v)}` : `−${fmt(-v)}`
    const valueSide = diff == null || line?.market_spread == null ? null : diff > 0
      ? `${g.away_team} ${signedLine(-line.market_spread)}` : `${g.home_team} ${signedLine(line.market_spread)}`
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
          {g.venue && <span className="cf-small cf-muted">{g.venue}{g.neutral ? ' (Neutral Site)' : ''}</span>}
          {g.conference_game && <span className="cf-small cf-muted">Conference Game</span>}
        </div>
        <TeamHead id={g.home_id} name={g.home_team} row={rh} side="home" g={g} />
      </header>
      <h1 className="cf-sr">{g.away_team} {sep} {g.home_team}, Week {g.week}</h1>

      {g.status === 'final' && <GameRecap g={g} season={games.data!.meta.season} hfa={games.data!.meta.hfa} />}

      {g.status !== 'final' && <section className="cf-panel cf-mu-fc" aria-labelledby="mu-fc">
        <h2 id="mu-fc" className="cf-h2">Forecast and line {line && <span className="cf-tag">Vegas figures: evaluation only</span>}</h2>
        {<div className="cf-mu-tiles">
          <div className="cf-mu-tile is-model">
            <span className="cf-mu-tile-k">Model line <Info text={MODEL_LINE_INFO} label="About the model line" /></span>
            <strong className="cf-mu-tile-v">{modelLine != null ? spreadText(g.home_team, g.away_team, modelLine) : <Missing why="No projection" />}</strong>
            {probHome != null && <span className="cf-mu-tile-s">Win: {g.away_team} <span className="cf-num">{pctText(probAway)}</span> · {g.home_team} <span className="cf-num">{pctText(probHome)}</span></span>}
          </div>
          {line && <div className="cf-mu-tile">
            <span className="cf-mu-tile-k">Vegas line <Info text={MARKET_INFO} label="About the Vegas line" /></span>
            <strong className="cf-mu-tile-v">{spreadText(g.home_team, g.away_team, line.market_spread!)}</strong>
            {line.market_provider && <span className="cf-mu-tile-s">{line.market_provider}</span>}
          </div>}
          {line && diff != null && <div className="cf-mu-tile">
            <span className="cf-mu-tile-k">Model implied value <Info text="The side the model likes better than the market does, at the Vegas number. If Vegas has the home team −10.5 and the model only −4.1, the value is the away team +10.5. A comparison only, not a pick or advice; the market is never a model input." label="About model implied value" /></span>
            <strong className="cf-mu-tile-v">{Math.abs(diff) < 0.05 ? 'None' : valueSide}</strong>
            <span className="cf-mu-tile-s">{Math.abs(diff) < 0.05 ? 'Model and Vegas agree' : `Model line is ${fmt(Math.abs(diff))} pts from Vegas`}</span>
          </div>}
          {line?.market_total != null && <div className="cf-mu-tile">
            <span className="cf-mu-tile-k">Vegas points total</span>
            <strong className="cf-mu-tile-v cf-num">{fmt(line.market_total)}</strong>
            <span className="cf-mu-tile-s">O/U</span>
          </div>}
          {g.quality != null && <div className="cf-mu-tile">
            <span className="cf-mu-tile-k">Watchability <Info text={QUALITY_INFO} label="About watchability" /></span>
            <strong className="cf-mu-tile-v"><span className="cf-num">{g.quality}</span><small> / 100</small></strong>
            <span className="cf-mu-meter" aria-hidden="true"><i style={{ width: `${g.quality}%` }} /></span>
          </div>}
        </div>}
        {!line && <p className="cf-small cf-muted cf-mu-fc-note">No Vegas line available: lines are pulled only for games that have not kicked off when the data updates.</p>}
      </section>}

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
        <p className="cf-small cf-muted">Ranks among {total || 'FBS'} FBS teams, No. 1 = best; the better side of each row is shaded green. Stats are per game over each team’s regular-season games in the ratings; none are opponent-adjusted except the CFPi+ ratings.{(!ra || !rh) ? ' Non-FBS teams have no CFPi+ stats.' : ''}</p>
      </section>}

      {(sa.length > 0 || sh.length > 0) && <section className="cf-panel" aria-labelledby="mu-stars">
        <h2 id="mu-stars" className="cf-h2">Key players</h2>
        <div className="cf-mu-stars">
          {[[g.away_id, g.away_team, sa], [g.home_id, g.home_team, sh]].map(([tid, name, list], i) => <div key={tid as string} className={i ? 'is-home' : undefined}>
            <h3 className="cf-h3"><TeamLogo id={tid as string} name={name as string} size={20} /> {name as string}</h3>
            {(list as Star[]).length ? <ul className="cf-mu-star-list">{(list as Star[]).map(s => <StarCard key={s.key} s={s} />)}</ul> : <p className="cf-muted cf-small">No player data (non-FBS team).</p>}
          </div>)}
        </div>
        <p className="cf-small cf-muted">Season stats through Week {games.data!.meta.ratings_week} (CollegeFootballData): the depth-chart starting quarterback (TWO·DEEP, with permission), the leading rusher, the top two receivers, the top two tacklers and the sack leader.</p>
      </section>}
    </>
  }}</DataGate>
}
