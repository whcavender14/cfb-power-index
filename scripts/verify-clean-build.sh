#!/usr/bin/env bash
set -euo pipefail
# Run from the repository root. Isolate both node_modules and the package store
# to prove that esbuild's postinstall is allowed without cached build outputs.
build_check_dir=$(mktemp -d "${TMPDIR:-/tmp}/cfb-clean-build.XXXXXX")
cp package.json pnpm-lock.yaml pnpm-workspace.yaml tsconfig.json vite.config.ts index.html "$build_check_dir/"
cp -R src public tests scripts "$build_check_dir/"
cd "$build_check_dir"
node scripts/check-pnpm-config.mjs
CI=true pnpm install --frozen-lockfile --store-dir "$build_check_dir/pnpm-store"
pnpm --config.store-dir="$build_check_dir/pnpm-store" test
pnpm --config.store-dir="$build_check_dir/pnpm-store" build
printf 'Clean install and production build passed in %s\n' "$build_check_dir"
