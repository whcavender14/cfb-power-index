import { useEffect, useState, useSyncExternalStore, type AnchorHTMLAttributes, type MouseEvent } from 'react'

// Path routing under the Pages base path (/cfb-power-index/). Every route also exists as a prerendered
// index.html (scripts/prerender_routes.mjs), so direct loads and refreshes of nested URLs work on
// static hosting. Page state (filters, sort) lives in query parameters.

const BASE = import.meta.env.BASE_URL.replace(/\/$/, '')

/** Route path without the base, always with a trailing slash: "/", "/teams/alabama/". */
export function currentPath(): string {
  let path = location.pathname
  if (BASE && path.startsWith(BASE)) path = path.slice(BASE.length)
  if (!path.startsWith('/')) path = `/${path}`
  path = path.replace(/index\.html$/, '')
  return path.endsWith('/') ? path : `${path}/`
}

export const href = (path: string) => `${BASE}${path}`

let listeners: (() => void)[] = []
const notify = () => listeners.forEach(fn => fn())
const subscribe = (fn: () => void) => {
  listeners.push(fn)
  window.addEventListener('popstate', fn)
  return () => { listeners = listeners.filter(l => l !== fn); window.removeEventListener('popstate', fn) }
}
const snapshot = () => location.pathname + location.search

export function navigate(to: string, { replace = false, keepScroll = false } = {}) {
  const url = to.startsWith(BASE) ? to : href(to)
  if (url === snapshot()) return
  history[replace ? 'replaceState' : 'pushState'](null, '', url)
  if (!keepScroll) window.scrollTo({ top: 0 })
  notify()
}

export function useLocation() {
  useSyncExternalStore(subscribe, snapshot)
  return { path: currentPath(), query: new URLSearchParams(location.search) }
}

/** One query parameter as state; writing it replaces the history entry (filters are not navigation). */
export function useQueryParam(key: string, fallback = ''): [string, (value: string) => void] {
  const { query } = useLocation()
  const value = query.get(key) ?? fallback
  const set = (next: string) => {
    const params = new URLSearchParams(location.search)
    if (next && next !== fallback) params.set(key, next); else params.delete(key)
    const search = params.toString().replace(/%2C/gi, ",")
    navigate(`${location.pathname}${search ? `?${search}` : ''}`, { replace: true, keepScroll: true })
  }
  return [value, set]
}

/** Old single-page URLs (#ratings, #simulations, #betting) keep working. */
export function useLegacyHashRedirect() {
  const [done, setDone] = useState(false)
  useEffect(() => {
    const map: Record<string, string> = { '#ratings': '/rankings/', '#simulations': '/simulations/', '#betting': '/betting/', '#methodology': '/model/' }
    const target = map[location.hash]
    if (target && currentPath() === '/') navigate(target, { replace: true })
    setDone(true)
  }, [])
  return done
}

export function Link({ to, onClick, ...rest }: AnchorHTMLAttributes<HTMLAnchorElement> & { to: string }) {
  const handle = (event: MouseEvent<HTMLAnchorElement>) => {
    onClick?.(event)
    if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    event.preventDefault()
    navigate(to)
  }
  return <a href={href(to)} onClick={handle} {...rest} />
}
