import { useState } from 'react'
import { FileDown, ImageDown } from 'lucide-react'
import type { Dataset, Rating } from './data'
import TeamBoard, { type Column } from './TeamBoard'
import { Delta, Kicker, Missing, Notice, PowerValue, SectionHead, Sources, TeamLogo, TeamName } from './ui'
import { signed, weekLabel, weekSlug } from './format'
import { toCsv } from './csv'
import { downloadCsv } from './download'
import { exportRankingsPng } from './exportImage'

type Props = { ratings: Dataset<Rating> | null; ranked: Rating[]; ranks: Map<string, number>; loading: boolean; error: boolean; onRetry: () => void }

export default function PowerRatings({ ratings, ranked, ranks, loading, error, onRetry }: Props) {
  const [exporting, setExporting] = useState(false)
  const [exportFailed, setExportFailed] = useState(false)
  const [missingLogos, setMissingLogos] = useState(0)
  const rows = ratings?.teams ?? []
  const scale = Math.max(1, ...ranked.map(r => Math.abs(r.power_rating!)))

  const columns: Column<Rating>[] = [
    { key: 'rank', label: 'Rk', kind: 'rank', tip: 'Rank among teams with available power ratings; this is not a complete national ranking when coverage is partial.',
      render: r => { const rank = ranks.get(r.team_id); return <span className={rank && rank <= 3 ? 'rank top' : 'rank'}>{rank ? String(rank).padStart(2, '0') : '—'}</span> } },
    { key: 'team', label: 'Team', kind: 'team', tip: 'FBS membership and team identity from the supplied team metadata.', sortValue: r => r.team,
      render: r => <TeamName name={r.team} logo={r.logo_url} sub={r.power_rating === null ? 'Data unavailable' : r.conference} /> },
    { key: 'conference', label: 'Conference', kind: 'text', tip: 'Conference affiliation in the season’s source metadata.', sortValue: r => r.conference, render: r => r.conference ?? <Missing /> },
    { key: 'power_rating', label: 'Power', kind: 'primary', tip: 'Opponent-adjusted team strength in points relative to the model’s average FBS team. Offense minus defense; higher power is better.', sortValue: r => r.power_rating,
      render: r => <PowerValue value={r.power_rating} scale={scale} /> },
    { key: 'offensive_rating', label: 'Offense', short: 'Off', kind: 'stat', tip: 'Opponent-adjusted offensive strength in points above the model’s FBS average. Higher is better.', sortValue: r => r.offensive_rating,
      render: r => r.offensive_rating === null ? <Missing /> : <span className="num">{signed(r.offensive_rating)}</span> },
    { key: 'defensive_rating', label: 'Defense', short: 'Def', kind: 'stat', tip: 'Production-model defensive rating in points. Lower (more negative) is better; power equals offense minus defense.', sortValue: r => r.defensive_rating,
      render: r => r.defensive_rating === null ? <Missing /> : <span className="num">{signed(r.defensive_rating)}</span> },
    { key: 'weekly_change', label: 'Δ Last week', short: 'Δ Week', kind: 'stat', tip: 'Power rating minus the prior numbered week’s rating. Unavailable when either snapshot or team rating is missing.', sortValue: r => r.weekly_change,
      render: r => <Delta value={r.weekly_change} /> },
    { key: 'preseason_change', label: 'Δ Preseason', short: 'Δ Pre', kind: 'stat', tip: 'Current power rating minus the same production model’s pre_power baseline. These are rating-point changes, not rank changes.', sortValue: r => r.preseason_change,
      render: r => <Delta value={r.preseason_change} /> },
  ]

  const season = ratings?.season ?? new Date().getFullYear()
  const exportCsv = () => {
    const sorted = [...rows].sort((a, b) => (ranks.get(a.team_id) ?? Infinity) - (ranks.get(b.team_id) ?? Infinity) || a.team.localeCompare(b.team))
    downloadCsv(toCsv(
      ['rank', 'team', 'conference', 'power_rating', 'offensive_rating', 'defensive_rating', 'change_vs_last_week', 'change_vs_preseason', 'season', 'week', 'updated_at'],
      sorted.map(r => [ranks.get(r.team_id) ?? null, r.team, r.conference, r.power_rating, r.offensive_rating, r.defensive_rating, r.weekly_change, r.preseason_change, r.season, r.week, r.updated_at]),
    ), `cfb-power-ratings-${season}-${weekSlug(ratings?.week)}.csv`)
  }
  const exportPng = async () => {
    setExporting(true); setExportFailed(false); setMissingLogos(0)
    try {
      const result = await exportRankingsPng({ teams: ranked, season, week: ratings?.week ?? null, updatedAt: ratings?.updated_at ?? null })
      setMissingLogos(result.total - result.logos)
    }
    catch { setExportFailed(true) }
    finally { setExporting(false) }
  }
  const partial = !loading && !error && ranked.length < rows.length

  return <section className="view" aria-labelledby="ratings-title">
    <SectionHead index="01" eyebrow={`Power ratings · ${weekLabel(ratings?.week)}`} title="The Index" id="ratings-title">
      <p>Every FBS team, measured in points against an average opponent on a neutral field. Power and offense: higher is better. Defense: lower is better.</p>
    </SectionHead>

    {ranked.length > 0 && <div className="podium" aria-label="Top three teams">
      {ranked.slice(0, 3).map((team, i) => <article key={team.team_id} className={`podium-card card${i === 0 ? ' is-first' : ''}`}>
        <div className="podium-top"><span className="rank-badge" aria-label={`Rank ${i + 1}`}>{String(i + 1).padStart(2, '0')}</span><span className="tag">{team.conference ?? '—'}</span></div>
        <div className="podium-id"><TeamLogo name={team.team} src={team.logo_url} size={52} /><h3>{team.team}</h3></div>
        <div className="podium-figs">
          <div><div className="micro-label">Power rating</div><div className="podium-power">{signed(team.power_rating)}</div></div>
          <dl className="chips">
            <div><dt>Off</dt><dd>{signed(team.offensive_rating)}</dd></div>
            <div><dt>Def</dt><dd>{signed(team.defensive_rating)}</dd></div>
            <div><dt>Δ Pre</dt><dd><Delta value={team.preseason_change} /></dd></div>
          </dl>
        </div>
      </article>)}
    </div>}

    <TeamBoard
      caption="FBS power ratings; ranks apply only to teams with ratings. A dash means data unavailable."
      rows={rows} columns={columns} defaultSort={{ key: 'power_rating', desc: true }} phoneStatColumns={4}
      loading={loading} error={error} onRetry={onRetry}
      toggle={{ label: 'Rated only', test: r => r.power_rating !== null }}
      rowClass={r => r.power_rating === null ? 'is-unrated' : ''}
      notice={<>
        {partial && <Notice><strong>Partial coverage.</strong> The supplied snapshot has ratings for {ranked.length} of {rows.length} FBS teams. Unrated teams and missing comparisons display — (data unavailable).</Notice>}
        {exportFailed && <Notice role="alert">The ranking image could not be generated in this browser. The CSV export still includes every team.</Notice>}
        {missingLogos > 0 && <Notice role="status">Image exported. {missingLogos} team {missingLogos === 1 ? 'logo was' : 'logos were'} unavailable and shown as initials — run <code>pnpm logos</code> before building to mirror them.</Notice>}
      </>}
      actions={ratings && <div className="actions">
        <button type="button" className="btn" onClick={exportCsv}><FileDown size={15} aria-hidden="true" /><span>CSV</span></button>
        <button type="button" className="btn btn-primary" onClick={exportPng} disabled={exporting || ranked.length === 0}><ImageDown size={15} aria-hidden="true" /><span>{exporting ? 'Rendering…' : 'Export PNG'}</span></button>
      </div>}
    />

    <section id="methodology" className="method" aria-labelledby="method-title">
      <div className="method-intro"><Kicker index="—">Methodology</Kicker><h2 id="method-title">How to read the index</h2></div>
      <div className="method-cols">
        <article><h3>The ratings</h3><p>Ratings come from the production model, Current C2: each week, one opponent-adjusted fit of final scores and play-by-play success rates for every FBS, FCS and lower-division team, anchored to a preseason prior. Only games final before the Monday cutoff count. Power equals offense minus defense. Higher power and offense are better; lower, more negative defensive ratings indicate a better defense.</p></article>
        <article><h3>Movement &amp; coverage</h3><p>Movement is a change in rating points. Weekly changes require the previous numbered week; preseason changes use the same model’s pre_power baseline. Missing teams are never assigned a zero rating. Leaders reflect available ratings only.</p></article>
      </div>
      <Sources extra={<a href={`${import.meta.env.BASE_URL}data/ratings.json`} download>Raw ratings.json</a>}>Refreshed weekly during the season</Sources>
    </section>
  </section>
}

