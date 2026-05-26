#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

bash -n scripts/codex-remote-proxy-check.sh
bash -n scripts/codex-remote-proxy-restart.sh

public_files=(
  README.md
  README.zh-CN.md
  CHANGELOG.md
  LICENSE
  configs/proxy.env.example
  data/sample/redacted-doctor-before.txt
  data/sample/redacted-doctor-after.txt
  scripts/codex-remote-proxy-check.sh
  scripts/codex-remote-proxy-restart.sh
)

private_patterns=(
  'srv_e_'
  'env_e_'
  '/Users/huangyi'
  '453840@qq\.com'
  'hyMac'
  'hydeMac'
  'state_5\.sqlite'
  'auth\.json'
  'app-server-control\.sock'
)

for pattern in "${private_patterns[@]}"; do
  if grep -RInE "$pattern" "${public_files[@]}"; then
    echo "private marker found: $pattern" >&2
    exit 1
  fi
done

grep -q -- '--apply' scripts/codex-remote-proxy-restart.sh
grep -q 'dry-run: no changes were made' scripts/codex-remote-proxy-restart.sh
grep -q 'HTTP 101 Switching Protocols' README.md
grep -q 'Codex remote connections' README.md

echo "publication safety checks passed"
