import { useMemo, useState } from 'react'
import { FileDown, ChartScatter, Trophy } from 'lucide-react'
import type { Dataset, Rating, Simulation } from './data'
import TeamBoard, { type Column } from './TeamBoard'
import { Kicker, Missing, Notice, Probability, SectionHead, Sources, TeamLogo, TeamName } from './ui'
import { formatUpdated, num, pct, weekLabel, weekSlug } from './format'
import { toCsv } from './csv'
import { downloadCsv } from './download'
import { exportBracketPng, exportPlayoffHuntPng } from './exportPlayoff'
import { DEFAULT_MODEL, joinTeams } from './playoff'

type Props = { simulations: Dataset<Simulation> | null; ratings: Dataset<Rating> | null; loading: boolean; error: boolean; onRetry: () => void }
const wins = (value: number | null) => value === null ? <Missing /> : <span className="num">{num(value)}</span>

type ImageKind = 'hunt' | 'bracket'

export default function SeasonSimulations({ simulations, ratings, loading, error, onRetry }: Props) {
  const [exporting, setExporting] = useState<ImageKind | null>(null)
  const [exportFailed, setExportFailed] = useState<ImageKind | null>(null)
  const [missingLogos, setMissingLogos] = useState(0)
  const rows = simulations?.teams ?? []
  const hasPreseason = rows.some(r => r.projected_wins_preseason !== null)
  const hasVegas = rows.some(r => r.vegas_win_total_preseason !== null)
  const available = simulations?.status === 'available'
  const contenders = rows.filter(r => (r.national_title_probability ?? 0) > 0)
    .sort((a, b) => b.national_title_probability! - a.national_title_probability! || (b.playoff_probability ?? 0) - (a.playoff_probability ?? 0))
    .slice(0, 4)

  const columns: Column<Simulation>[] = [
    { key: 'team', label: 'Team', kind: 'team', tip: 'FBS membership and team identity from the supplied team metadata.', sortValue: r => r.team,
      render: r => <TeamName name={r.team} logo={r.logo_url} sub={r.conference} /> },
    { key: 'conference', label: 'Conference', kind: 'text', tip: 'Conference affiliation in the season’s source metadata.', sortValue: r => r.conference, render: r => r.conference ?? <Missing /> },
    { key: 'projected_wins_current', label: 'Proj. wins', kind: 'primary', tip: 'Mean overall wins from the current simulation. Includes conference championship games according to cfbseedR’s standings rules.', sortValue: r => r.projected_wins_current,
      render: r => r.projected_wins_current === null ? <Missing /> : <span className="num num-strong">{num(r.projected_wins_current)}</span> },
    { key: 'projected_wins_preseason', label: 'Preseason', short: 'Pre wins', kind: 'stat', hideOnPhone: !hasPreseason, tip: 'Mean wins from a saved preseason simulation with the same win-count definition. Never reconstructed using current ratings.', sortValue: r => r.projected_wins_preseason, render: r => wins(r.projected_wins_preseason) },
    { key: 'vegas_win_total_preseason', label: 'Vegas', short: 'Vegas', kind: 'stat', hideOnPhone: !hasVegas, tip: 'Separately supplied preseason sportsbook win total. No market data has been inferred.', sortValue: r => r.vegas_win_total_preseason, render: r => wins(r.vegas_win_total_preseason) },
    { key: 'playoff_probability', label: 'Playoff', short: 'Playoff', kind: 'stat', tip: 'Fraction of simulated seasons in which the team receives a College Football Playoff seed.', sortValue: r => r.playoff_probability, render: r => <Probability value={r.playoff_probability} /> },
    { key: 'conference_title_probability', label: 'Conf. title', short: 'Conf.', kind: 'stat', tip: 'Fraction of simulated seasons in which cfbseedR identifies the team as conference champion.', sortValue: r => r.conference_title_probability, render: r => <Probability value={r.conference_title_probability} /> },
    { key: 'national_title_probability', label: 'Natl. title', short: 'Title', kind: 'stat', tip: 'Fraction of simulated seasons in which the team wins the generated playoff bracket.', sortValue: r => r.national_title_probability, render: r => <Probability value={r.national_title_probability} /> },
  ]
  const phoneStats = 3 + Number(hasPreseason) + Number(hasVegas)

  // The share graphics need both odds and power ratings for the same teams.
  const playoffTeams = useMemo(() => available && ratings?.status === 'available' ? joinTeams(rows, ratings.teams) : [], [available, rows, ratings])
  const canRender = !loading && playoffTeams.length >= 12
  const exportImage = async (kind: ImageKind) => {
    if (!simulations) return
    setExporting(kind); setExportFailed(null); setMissingLogos(0)
    const a = simulations.assumptions
    const common = { teams: playoffTeams, season: simulations.season, week: simulations.week, updatedAt: simulations.updated_at, asOf: simulations.as_of ?? null, simulations: simulations.simulation_count ?? null }
    try {
      const result = kind === 'hunt' ? await exportPlayoffHuntPng(common)
        : await exportBracketPng({ ...common, model: { hfa: a?.hfa ?? DEFAULT_MODEL.hfa, sigma: a?.resid_sd ?? DEFAULT_MODEL.sigma }, ineligible: a?.cfp_ineligible_teams ?? [] })
      setMissingLogos(result.total - result.logos)
    }
    catch { setExportFailed(kind) }
    finally { setExporting(null) }
  }

  const exportCsv = () => {
    const sorted = [...rows].sort((a, b) => (b.projected_wins_current ?? -Infinity) - (a.projected_wins_current ?? -Infinity) || a.team.localeCompare(b.team))
    downloadCsv(toCsv(
      ['team', 'conference', 'projected_wins_current', 'projected_wins_preseason', 'vegas_win_total_preseason', 'playoff_probability', 'conference_title_probability', 'national_title_probability', 'season', 'week', 'updated_at'],
      sorted.map(r => [r.team, r.conference, r.projected_wins_current, r.projected_wins_preseason, r.vegas_win_total_preseason, r.playoff_probability, r.conference_title_probability, r.national_title_probability, r.season, r.week, r.updated_at]),
    ), `cfb-season-simulations-${simulations?.season ?? ''}-${weekSlug(simulations?.week)}.csv`)
  }

  return <section className="view" aria-labelledby="sims-title">
    <SectionHead index="02" eyebrow={`Season simulations · ${weekLabel(simulations?.week)}`} title="Where could your team finish?" id="sims-title">
      <p>Expected wins and postseason odds from the supplied simulation model. Probabilities are model-based expectations, not guarantees.</p>
      <div className="aside-figure"><strong>{simulations?.simulation_count?.toLocaleString() ?? '—'}</strong><span>simulated seasons</span></div>
    </SectionHead>

    {available && contenders.length > 0 && <>
      <h3 className="subhead">Title contenders</h3>
      <div className="contenders">
        {contenders.map(team => <article key={team.team_id} className="contender card">
          <div className="contender-id"><TeamLogo name={team.team} src={team.logo_url} size={40} /><div><div className="team-name">{team.team}</div><div className="team-sub">{team.conference ?? '—'}</div></div></div>
          <div className="contender-fig"><span className="tag tag-gold">Natl. title</span><strong>{pct(team.national_title_probability)}</strong></div>
          <dl className="contender-meta">
            <div><dt>Playoff</dt><dd>{pct(team.playoff_probability)}</dd></div>
            <div><dt>Conf.</dt><dd>{pct(team.conference_title_probability)}</dd></div>
            <div><dt>Wins</dt><dd>{num(team.projected_wins_current)}</dd></div>
          </dl>
        </article>)}
      </div>
    </>}

    <TeamBoard
      caption="FBS simulation results. A dash means data unavailable."
      rows={rows} columns={columns} defaultSort={{ key: 'projected_wins_current', desc: true }} phoneStatColumns={Math.min(3, phoneStats)}
      loading={loading} error={error} onRetry={onRetry}
      notice={!loading && !error && simulations?.status === 'unavailable'
        ? <Notice><strong>Data unavailable.</strong> No completed simulation output was supplied. Projections and odds will appear after a successful simulation run.</Notice> : <>
          {exportFailed && <Notice role="alert">The {exportFailed === 'hunt' ? 'Playoff Hunt' : 'projected playoff'} image could not be generated in this browser. The CSV export still includes every team.</Notice>}
          {missingLogos > 0 && <Notice role="status">Image exported. {missingLogos} team {missingLogos === 1 ? 'logo was' : 'logos were'} unavailable and shown as initials — run <code>pnpm logos</code> before building to mirror them.</Notice>}
        </>}
      actions={simulations && <div className="actions">
        <button type="button" className="btn" onClick={exportCsv}><FileDown size={15} aria-hidden="true" /><span>CSV</span></button>
        <button type="button" className="btn" onClick={() => exportImage('hunt')} disabled={!canRender || exporting !== null} title={canRender ? 'Download the Playoff Hunt graphic' : 'Needs simulation odds and power ratings'}><ChartScatter size={15} aria-hidden="true" /><span>{exporting === 'hunt' ? 'Rendering…' : 'Playoff Hunt'}</span></button>
        <button type="button" className="btn btn-primary" onClick={() => exportImage('bracket')} disabled={!canRender || exporting !== null} title={canRender ? 'Download the projected playoff bracket' : 'Needs simulation odds and power ratings'}><Trophy size={15} aria-hidden="true" /><span>{exporting === 'bracket' ? 'Rendering…' : 'Projected Playoff'}</span></button>
      </div>}
    />

    <section id="methodology" className="method" aria-labelledby="method-title">
      <div className="method-intro"><Kicker index="—">Methodology</Kicker><h2 id="method-title">Simulation assumptions</h2></div>
      <div className="method-cols">
        <article><h3>The run</h3><p>{available
          ? `${simulations.simulation_count?.toLocaleString() ?? 'Unknown count'} simulations. ${simulations.playoff_format ?? 'Playoff format unavailable'}. ${simulations.wins_scope ?? 'Win-count definition unavailable'}.`
          : 'The supplied script configures 1,000 simulations and a 12-team playoff using 2026 automatic-bid rules and static power rankings. No completed run is available, so these are configured assumptions, not published results.'}</p></article>
        <article><h3>Model &amp; update policy</h3><p>Simulations use vCurrent / EB_features; the ratings tab uses the frozen candidate selected by run_2026_rankings.R. The script assumes normal game margins, 3.0685 points of home advantage, 15.7875 residual SD, and −25 FCS power. Completed results are held fixed. Missing preseason projections and Vegas totals remain unavailable.</p></article>
      </div>
      <Sources extra={<a href={`${import.meta.env.BASE_URL}data/simulations.json`} download>Raw simulations.json</a>}>Simulation updated: {formatUpdated(simulations?.updated_at)}</Sources>
    </section>
  </section>
}
