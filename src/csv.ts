// Pure CSV serialization (RFC 4180 quoting). Kept DOM-free so node tests can import it.
export type Cell = string | number | boolean | null | undefined

export function csvCell(value: Cell): string {
  if (value === null || value === undefined) return ''
  if (typeof value === 'number') return Number.isFinite(value) ? String(value) : ''
  let text = String(value)
  // Spreadsheet apps execute text cells that begin with a formula character.
  if (/^[=+\-@\t\r]/.test(text)) text = `'${text}`
  return /[",\r\n]/.test(text) || text !== text.trim() ? `"${text.replace(/"/g, '""')}"` : text
}

export function toCsv(header: string[], rows: Cell[][]): string {
  return [header, ...rows].map(row => row.map(csvCell).join(',')).join('\r\n') + '\r\n'
}
