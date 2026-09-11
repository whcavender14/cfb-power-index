import { readFileSync } from 'node:fs'
import assert from 'node:assert/strict'
const pkg = JSON.parse(readFileSync('package.json','utf8'))
const policy = readFileSync('pnpm-workspace.yaml','utf8')
assert.equal(pkg.packageManager, 'pnpm@11.19.0', 'Use the project’s pinned pnpm version')
assert.equal(pkg.pnpm, undefined, 'pnpm 11 ignores package.json pnpm configuration; use pnpm-workspace.yaml')
assert.match(policy, /^allowBuilds:\r?\n(?:[ \t]+#[^\n]*\r?\n)*[ \t]+esbuild: true\s*$/m, 'Commit the root workspace policy explicitly permitting esbuild')
assert.doesNotMatch(policy, /dangerouslyAllowAllBuilds:\s*true/, 'Keep dependency build approvals scoped')
console.log('pnpm 11 workspace policy: esbuild explicitly allowed; no legacy package.json configuration.')
