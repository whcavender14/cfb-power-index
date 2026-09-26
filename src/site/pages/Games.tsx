import ShareButton from '../ShareButton'
import { useEffect, useMemo, useState } from 'react'
import { DataGate, Freshness, Info, Missing, PageHead, pctText, Select, SortTh, sortRows, useData, useTeams, type Sort } from '../components'
import type { GamesDoc, Game } from '../data'
import { GameCard, kickoffText, Matchup, projection, ProjectionText, Quality, QUALITY_INFO, WINPROB_INFO } from '../games'
import { useQueryParam } from '../router'

type Line = { game_id: string; market_spread: number | null; market_provider: string | null; home_team: string; away_team: string }

/** Sportsbook quotes for the upcoming week (public/data/betting.json). Display only; optional. */
function useLines(): Map<string, Line> {
  const [lines, setLines] = useState(new Map<string, Line>())
  useEffect(() => {
    fetch(`${import.meta.env.BASE_URL}data/betting.json`).then(r => r.ok ? r.json() : null).then(body => {
      if (body?.schema_version === 1 && Array.isArray(body.games)) setLines(new Map((body.games as Line[]).filter(g => g.market_spread != null).map(g => [g.game_id, g])))
    }).catch(() => { /* lines are optional */ })
  }, [])
  return lines
}

const lineText = (l: Line) => l.market_spread === 0 ? 'Pick’em' : l.market_spread! < 0
  ? `${l.home_team} ${String(l.market_spread).replace('-', '−')}` : `${l.away_team} −${l.market_spread}`

export default function Games() {
  const doc = useData<GamesDoc>('games.json')
  const teams = useTeams()
  const lines = useLines()
  const [week, setWeek] = useQueryParam('week')
  const [conf, setConf] = useQueryParam('conf')
  const [team, setTeam] = useQueryParam('team')
  const [sortKey, setSortKey] = useQueryParam('sort', 'kickoff')
  const [dir, setDir] = useQueryParam('dir', '')
  const natural = (key: string) => key !== 'kickoff'
  const sort: Sort = { key: sortKey, desc: dir ? dir === 'desc' : natural(sortKey) }
  const onSort = (s: Sort) => { setSortKey(s.key); setDir(s.desc === natural(s.key) ? '' : s.desc ? 'desc' : 'asc') }
  const conferences = useMemo(() => [...new Set([...teams.values()].map(t => t.conference).filter(Boolean) as string[])].sort(), [teams])
  const teamOptions = useMemo(() => [...teams.values()].sort((a, b) => a.team.localeCompare(b.team)), [teams])

  return <>
    <PageHead title="Games" lede="Every game involving an FBS team: results so far and CFPi+ projections for the rest." />
    <DataGate source={doc} label="Games">{({ meta, games }) => {
      const weeks = [...new Set(games.map(g => g.week))].sort((a, b) => a - b)
      const slug = teams.get(team) ? team : [...teams.values()].find(t => t.slug === team)?.team_id ?? ''
      const activeWeek = week === 'all' ? null : week ? Number(week) : slug ? null : meta.current_week
      const rows = games.filter(g => (activeWeek == null || g.week === activeWeek)
        && (!conf || g.home_conference === conf || g.away_conference === conf)
        && (!slug || g.home_id === slug || g.away_id === slug))
      const value: Record<string, (g: Game) => number | null> = {
        kickoff: g => Date.parse(g.kickoff), quality: g => g.quality,
        prob: g => projection(g)?.prob ?? null, week: g => g.week,
      }
      const sorted = sortRows(rows, value[sort.key] ?? value.kickoff, sort.desc)
      const showLines = sorted.some(g => lines.has(g.game_id))
      return <>
        <div className="cf-toolbar">
          <Select label="Week" value={week || (slug ? 'all' : String(meta.current_week ?? 'all'))} onChange={v => setWeek(v === String(meta.current_week) && !slug ? '' : v)}>
            <option value="all">All weeks</option>
            {weeks.map(w => <option key={w} value={String(w)}>Week {w}{w === meta.current_week ? ' (this week)' : ''}</option>)}
          </Select>
          <Select label="Conference" value={conf} onChange={setConf}>
            <option value="">All conferences</option>
            {conferences.map(c => <option key={c} value={c}>{c}</option>)}
          </Select>
          <Select label="Team" value={slug ? teams.get(slug)!.slug : ''} onChange={v => setTeam(v)}>
            <option value="">All teams</option>
            {teamOptions.map(t => <option key={t.team_id} value={t.slug}>{t.team}</option>)}
          </Select>
        </div>
        <div className="cf-subbar">
          <Freshness meta={meta} />
          <p className="cf-muted" role="status">{sorted.length} {sorted.length === 1 ? 'game' : 'games'}{showLines && ' · Lines: one sportsbook quote per game, for reference only'}</p>
          <ShareButton disabled={!sorted.some(g => g.status === 'scheduled')} run={async () => (await import('../graphics')).gamesPng(meta, sorted, teams, activeWeek == null ? 'all weeks' : `Week ${activeWeek}`)} />
        </div>

        {meta.ratings_as_of && <p className="cf-note">Projections use ratings through Week {meta.ratings_week}. Games played since then keep their projection until the next weekly update adds the result.</p>}
        {sorted.length === 0 ? <div className="cf-state"><p className="cf-state-title">No games match these filters</p></div> : <>
          <div className="cf-table-wrap cf-desktop">
            <table className="cf-table">
              <caption className="cf-sr">Games, sortable</caption>
              <thead><tr>
                <SortTh label="Kickoff" sortKey="kickoff" sort={sort} onSort={onSort} align="start" />
                <th scope="col" className="cf-th-start">Matchup</th>
                <th scope="col" className="cf-th-start">Projection / result</th>
                <SortTh label="Win prob." sortKey="prob" sort={sort} onSort={onSort} info={WINPROB_INFO} />
                <SortTh label="Quality" sortKey="quality" sort={sort} onSort={onSort} info={QUALITY_INFO} />
                {showLines && <th scope="col" className="cf-th-end"><span className="cf-th">Line <Info text="A single sportsbook line retrieved from CollegeFootballData for this week's games. It is shown for reference only and is never an input to CFPi+." label="About lines" /></span></th>}
              </tr></thead>
              <tbody>{sorted.map(g => { const p = projection(g); const l = lines.get(g.game_id); return <tr key={g.game_id}>
                <td className="cf-nowrap cf-muted">{activeWeek == null && <span className="cf-small">Wk {g.week} · </span>}{kickoffText(g)}</td>
                <td><Matchup g={g} /></td>
                <td><ProjectionText g={g} /></td>
                <td className="cf-td-end cf-num">{p?.prob != null ? pctText(p.prob) : <Missing why="No projection" />}</td>
                <td className="cf-td-end"><Quality value={g.quality} /></td>
                {showLines && <td className="cf-td-end cf-num">{l ? lineText(l) : <Missing why="No line" />}</td>}
              </tr> })}</tbody>
            </table>
          </div>
          <div className="cf-phone cf-gamelist">{sorted.map(g => <div key={g.game_id}>
            <GameCard g={g} />
            {lines.get(g.game_id) && <p className="cf-small cf-line-note">Line: {lineText(lines.get(g.game_id)!)}</p>}
          </div>)}</div>
        </>}
      </>
    }}</DataGate>
  </>
}
