import { useEffect, useId, useMemo, useRef, useState } from 'react'
import { Search as SearchIcon, X } from 'lucide-react'
import { TeamLogo, useData, useTeams } from './components'
import type { Meta, TeamMeta } from './data'
import { useOpenPlayer } from './player'
import { navigate } from './router'

// Header search: teams (from the team directory already on the page) and players (players.json, loaded on first use).
// A team opens its page; a player opens the player modal.
type PlayersDoc = { meta: Meta; columns: string[]; players: [string, string, string | null, string | null, number | null][] }
type Hit = { key: string; kind: 'team'; team: TeamMeta } | { key: string; kind: 'player'; id: string; name: string; teamId: string | null; pos: string | null; jersey: number | null }

const norm = (s: string) => s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9 ]/g, ' ').replace(/\s+/g, ' ').trim()
/** 0 = no match; higher is better: whole-string prefix, then every query word starting a word, then substring. */
function score(text: string, q: string, words: string[]): number {
  if (text === q) return 5
  if (text.startsWith(q)) return 4
  const tw = text.split(' ')
  if (words.every(w => tw.some(t => t.startsWith(w)))) return 3
  return text.includes(q) ? 1 : 0
}

export default function Search() {
  const [q, setQ] = useState('')
  const [open, setOpen] = useState(false)
  const [active, setActive] = useState(0)
  const [wide, setWide] = useState(false)   // phones: the box opens from an icon
  const [used, setUsed] = useState(false)
  const input = useRef<HTMLInputElement>(null)
  const box = useRef<HTMLDivElement>(null)
  const list = useId()
  const teams = useTeams()
  const players = useData<PlayersDoc>(used ? 'players.json' : null)
  const openPlayer = useOpenPlayer()

  const index = useMemo(() => ({
    teams: [...teams.values()].map(t => ({ t, text: norm(`${t.team} ${t.mascot ?? ''}`), abbr: norm(t.abbreviation ?? '') })),
    players: (players.data?.players ?? []).map(p => ({ p, text: norm(p[1]) })),
  }), [teams, players.data])

  const hits = useMemo<Hit[]>(() => {
    const n = norm(q)
    if (!n) return []
    const words = n.split(' ')
    const t = index.teams.map(x => ({ x, s: x.abbr === n ? 5 : score(x.text, n, words) })).filter(r => r.s > 0)
      .sort((a, b) => b.s - a.s || a.x.t.team.localeCompare(b.x.t.team)).slice(0, 6)
    const p = index.players.map(x => ({ x, s: score(x.text, n, words) })).filter(r => r.s > 0)
      .sort((a, b) => b.s - a.s || a.x.p[1].localeCompare(b.x.p[1])).slice(0, 8)
    return [
      ...t.map(r => ({ key: `t-${r.x.t.team_id}`, kind: 'team' as const, team: r.x.t })),
      ...p.map(r => ({ key: `p-${r.x.p[0]}`, kind: 'player' as const, id: r.x.p[0], name: r.x.p[1], teamId: r.x.p[2], pos: r.x.p[3], jersey: r.x.p[4] })),
    ]
  }, [q, index])

  useEffect(() => { setActive(0) }, [q])
  useEffect(() => {   // "/" focuses the search box, like most sites
    const key = (e: KeyboardEvent) => {
      const el = e.target as HTMLElement
      if (e.key === '/' && !e.metaKey && !e.ctrlKey && !/^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName) && !el.isContentEditable) { e.preventDefault(); setWide(true); setUsed(true); setTimeout(() => input.current?.focus(), 0) }
    }
    document.addEventListener('keydown', key)
    return () => document.removeEventListener('keydown', key)
  }, [])
  useEffect(() => {
    if (!open) return
    const away = (e: Event) => { if (!box.current?.contains(e.target as Node)) { setOpen(false); setWide(false) } }
    document.addEventListener('pointerdown', away)
    return () => document.removeEventListener('pointerdown', away)
  }, [open])

  const pick = (h: Hit) => {
    setOpen(false); setWide(false); setQ('')
    input.current?.blur()
    if (h.kind === 'team') navigate(`/teams/${h.team.slug}/`)
    else openPlayer(h.id)
  }
  const onKey = (e: React.KeyboardEvent) => {
    if (e.key === 'ArrowDown') { e.preventDefault(); setOpen(true); setActive(a => Math.min(hits.length - 1, a + 1)) }
    else if (e.key === 'ArrowUp') { e.preventDefault(); setActive(a => Math.max(0, a - 1)) }
    else if (e.key === 'Enter' && hits[active]) { e.preventDefault(); pick(hits[active]) }
    else if (e.key === 'Escape') { if (q) setQ(''); else { setOpen(false); setWide(false); input.current?.blur() } }
  }
  const showList = open && q.trim().length > 0
  const loading = used && players.loading && !players.data
  const groups: [string, Hit[]][] = [['Teams', hits.filter(h => h.kind === 'team')], ['Players', hits.filter(h => h.kind === 'player')]]

  return <div className={`cf-hs${wide ? ' is-wide' : ''}`} ref={box}>
    <button type="button" className="cf-icon-btn cf-hs-btn" aria-label="Search teams and players" onClick={() => { setWide(true); setUsed(true); setOpen(true); setTimeout(() => input.current?.focus(), 0) }}><SearchIcon size={17} /></button>
    <div className="cf-hs-field">
      <SearchIcon size={15} aria-hidden="true" />
      <input ref={input} type="search" role="combobox" aria-label="Search teams and players" aria-expanded={showList} aria-controls={list} aria-autocomplete="list"
        aria-activedescendant={showList && hits[active] ? `${list}-${active}` : undefined} placeholder="Search teams, players" autoComplete="off" spellCheck={false}
        value={q} onChange={e => { setQ(e.target.value); setOpen(true) }} onFocus={() => { setUsed(true); setOpen(true) }} onKeyDown={onKey} />
      {q ? <button type="button" className="cf-hs-clear" aria-label="Clear search" onMouseDown={e => e.preventDefault()} onClick={() => { setQ(''); input.current?.focus() }}><X size={14} /></button>
        : <kbd className="cf-hs-key" aria-hidden="true">/</kbd>}
    </div>
    {showList && <div className="cf-hs-pop" id={list} role="listbox" aria-label="Search results">
      {hits.length === 0 && <p className="cf-small cf-muted cf-hs-empty" role="status">{loading ? 'Loading players…' : `No teams or players match “${q.trim()}”.`}</p>}
      {groups.map(([title, items]) => items.length > 0 && <div key={title} role="presentation">
        <p className="cf-hs-group" role="presentation">{title}</p>
        {items.map(h => { const i = hits.indexOf(h)
          return <div key={h.key} id={`${list}-${i}`} role="option" aria-selected={i === active} className={`cf-hs-item${i === active ? ' is-active' : ''}`}
            onMouseEnter={() => setActive(i)} onMouseDown={e => e.preventDefault()} onClick={() => pick(h)}>
            {h.kind === 'team'
              ? <><TeamLogo id={h.team.team_id} name={h.team.team} size={24} /><span className="cf-hs-main">{h.team.team}<span className="cf-muted cf-small"> {h.team.mascot}</span></span><span className="cf-muted cf-small">{h.team.conference}</span></>
              : <><TeamLogo id={h.teamId} name={teams.get(h.teamId ?? '')?.team ?? ''} size={24} /><span className="cf-hs-main">{h.name}<span className="cf-muted cf-small"> {[h.pos, h.jersey != null ? `#${h.jersey}` : null].filter(Boolean).join(' · ')}</span></span><span className="cf-muted cf-small">{teams.get(h.teamId ?? '')?.team}</span></>}
          </div> })}
      </div>)}
      {loading && hits.length > 0 && <p className="cf-small cf-muted cf-hs-empty" role="status">Loading players…</p>}
    </div>}
  </div>
}
