export function downloadBlob(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = filename
  document.body.appendChild(link)
  link.click()
  link.remove()
  setTimeout(() => URL.revokeObjectURL(url), 1000)
}

// The byte-order mark lets Excel detect UTF-8 team names.
export const downloadCsv = (csv: string, filename: string) => downloadBlob(new Blob(['﻿', csv], { type: 'text/csv;charset=utf-8' }), filename)
