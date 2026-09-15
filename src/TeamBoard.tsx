import { useEffect, useState, type CSSProperties, type ReactNode } from 'react'
import { ArrowDown, ArrowUp, ArrowUpDown, ChevronLeft, ChevronRight, Search, X } from 'lucide-react'
import type { Team } from './data'
import { EmptyState, SelectField, Tip } from './ui'

// rank/team/text sit left; primary is the headline number; stat cells fold into a grid on phones.
export type Column<T> = {
  key: string; label: string; short?: string; tip?: string
  kind: 'rank' | 'team' | 'text' | 'primary' | 'stat'
  hideOnPhone?: boolean
  sortValue?: (row: T) => number | string | null
  render: (row: T) => ReactNode
}
type Props<T extends Team> = {
  caption: string; rows: T[]; columns: Column<T>[]; defaultSort: { key: string; desc: boolean }
  loading: boolean; error: boolean; onRetry: () => void
  actions?: ReactNode; notice?: ReactNode; phoneStatColumns: number
  toggle?: { label: string; test: (row: T) => boolean }
  rowClass?: (row: T) => string
}
const PAGE_SIZE = 25
const textKinds = new Set(['rank', 'team', 'text'])

export default function TeamBoard<T extends Team>({ caption, rows, columns, defaultSort, loading, error, onRetry, actions, notice, phoneStatColumns, toggle, rowClass }: Props<T>) {
  const [query, setQuery] = useState('')
  const [conference, setConference] = useState('')
  const [toggleOn, setToggleOn] = useState(false)
  const [sort, setSort] = useState(defaultSort)
  const [page, setPage] = useState(0)
  useEffect(() => { setPage(0) }, [query, conference, toggleOn, sort])

  const conferences = [...new Set(rows.map(r => r.conference).filter((c): c is string => !!c))].sort()
  const sortable = columns.filter(c => c.sortValue)
  const active = columns.find(c => c.key === sort.key)
  const needle = query.trim().toLocaleLowerCase()
  const filtered = rows
    .filter(row => row.team.toLocaleLowerCase().includes(needle) && (!conference || row.conference === conference) && (!toggle || !toggleOn || toggle.test(row)))
    .sort((a, b) => {
      const av = active?.sortValue?.(a) ?? null
      const bv = active?.sortValue?.(b) ?? null
      if (av === null && bv === null) return a.team.localeCompare(b.team)
      if (av === null) return 1
      if (bv === null) return -1
      const comparison = typeof av === 'number' && typeof bv === 'number' ? av - bv : String(av).localeCompare(String(bv))
      return comparison === 0 ? a.team.localeCompare(b.team) : comparison * (sort.desc ? -1 : 1)
    })
  const maxPage = Math.max(0, Math.ceil(filtered.length / PAGE_SIZE) - 1)
  const safePage = Math.min(page, maxPage)
  const visible = filtered.slice(safePage * PAGE_SIZE, (safePage + 1) * PAGE_SIZE)

  const pick = (key: string) => { const column = columns.find(c => c.key === key); if (column) setSort({ key, desc: !textKinds.has(column.kind) }) }
  const toggleSort = (column: Column<T>) => setSort(old => ({ key: column.key, desc: old.key === column.key ? !old.desc : !textKinds.has(column.kind) }))
  const reset = () => { setQuery(''); setConference(''); setToggleOn(false) }

  return <div className="board">
    <div className="toolbar">
      <div className="toolbar-filters">
        <label className="field search">
          <Search size={16} aria-hidden="true" />
          <span className="visually-hidden">Search teams</span>
          <input type="search" value={query} onChange={e => setQuery(e.target.value)} placeholder="Search teams" />
          {query && <button type="button" className="field-clear" aria-label="Clear search" onClick={() => setQuery('')}><X size={14} /></button>}
        </label>
        <SelectField label="Conference" value={conference} onChange={setConference} className="conference">
          <option value="">All conferences</option>
          {conferences.map(c => <option key={c} value={c}>{c}</option>)}
        </SelectField>
        <div className="phone-sort">
          <SelectField label="Sort by" value={sort.key} onChange={pick}>{sortable.map(c => <option key={c.key} value={c.key}>{c.label}</option>)}</SelectField>
          <button type="button" className="btn btn-icon" aria-label={sort.desc ? 'Sorted descending; switch to ascending' : 'Sorted ascending; switch to descending'} onClick={() => setSort(s => ({ ...s, desc: !s.desc }))}>{sort.desc ? <ArrowDown size={15} /> : <ArrowUp size={15} />}</button>
        </div>
        {toggle && <label className="check"><input type="checkbox" checked={toggleOn} onChange={e => setToggleOn(e.target.checked)} />{toggle.label}</label>}
      </div>
      <div className="toolbar-end">
        <span className="count" aria-live="polite">{filtered.length} teams</span>
        {actions}
      </div>
    </div>
    {notice}
    {loading ? <EmptyState role="status" title="Loading the index">Reading the latest published snapshot…</EmptyState>
      : error ? <EmptyState role="alert" title="Data unavailable" action={<button type="button" className="btn" onClick={onRetry}>Retry loading</button>}>This dataset could not be loaded. Please try again.</EmptyState>
      : <>
        <div className="table-wrap">
          <table className="team-table" style={{ '--stat-cols': phoneStatColumns } as CSSProperties}>
            <caption className="visually-hidden">{caption}</caption>
            <thead><tr>{columns.map((c, i) => <th key={c.key} scope="col" className={`col-${c.kind}`} aria-sort={sort.key === c.key ? sort.desc ? 'descending' : 'ascending' : undefined}>
              <span className="th-inner">
                {c.sortValue
                  ? <button type="button" onClick={() => toggleSort(c)}>{c.label}{sort.key === c.key ? sort.desc ? <ArrowDown size={12} /> : <ArrowUp size={12} /> : <ArrowUpDown size={11} className="sort-idle" />}</button>
                  : <span>{c.label}</span>}
                {c.tip && <Tip text={c.tip} align={i < 2 ? 'start' : i >= columns.length - 2 ? 'end' : 'center'} />}
              </span>
            </th>)}</tr></thead>
            <tbody>{visible.map(row => <tr key={row.team_id} className={rowClass?.(row)}>
              {columns.map(c => <td key={c.key} className={`col-${c.kind}${c.hideOnPhone ? ' hide-phone' : ''}`} data-label={c.short ?? c.label}>{c.render(row)}</td>)}
            </tr>)}</tbody>
          </table>
          {filtered.length === 0 && <EmptyState title="No teams found" action={<button type="button" className="btn" onClick={reset}>Reset filters</button>}>Try another team name or conference.</EmptyState>}
        </div>
        <div className="board-foot">
          <span>Showing <strong>{filtered.length ? safePage * PAGE_SIZE + 1 : 0}–{Math.min((safePage + 1) * PAGE_SIZE, filtered.length)}</strong> of {filtered.length}</span>
          <div className="pager">
            <button type="button" className="btn btn-icon" aria-label="Previous page" disabled={safePage === 0} onClick={() => setPage(safePage - 1)}><ChevronLeft size={16} /></button>
            <span>Page {safePage + 1} of {maxPage + 1}</span>
            <button type="button" className="btn btn-icon" aria-label="Next page" disabled={safePage >= maxPage} onClick={() => setPage(safePage + 1)}><ChevronRight size={16} /></button>
          </div>
        </div>
      </>}
  </div>
}
