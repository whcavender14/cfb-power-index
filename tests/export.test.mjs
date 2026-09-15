import test from 'node:test'
import assert from 'node:assert/strict'
import { csvCell, toCsv } from '../src/csv.ts'

test('CSV cells quote delimiters and keep missing values empty', () => {
  assert.equal(csvCell(null), '')
  assert.equal(csvCell(undefined), '')
  assert.equal(csvCell(-3.25), '-3.25')
  assert.equal(csvCell(Number.NaN), '')
  assert.equal(csvCell('Texas A&M'), 'Texas A&M')
  assert.equal(csvCell('Miami (OH), "RedHawks"'), '"Miami (OH), ""RedHawks"""')
  assert.equal(csvCell(false), 'false')
})
test('Text that spreadsheets would execute is neutralized, numbers are not', () => {
  assert.equal(csvCell('=HYPERLINK("x")'), `"'=HYPERLINK(""x"")"`)
  assert.equal(csvCell('-cmd'), "'-cmd")
  assert.equal(csvCell(-1), '-1')
})
test('Rows serialize with CRLF line endings and a header', () => {
  assert.equal(toCsv(['team', 'power'], [['Georgia', 29.5], ['Unrated', null]]), 'team,power\r\nGeorgia,29.5\r\nUnrated,\r\n')
})
