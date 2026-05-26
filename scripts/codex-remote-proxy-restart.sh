#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/codex-remote-proxy-restart.sh [--apply]

Dry-run by default. With --apply, restarts the managed Codex app-server daemon
with proxy environment variables and enables remote control.

Environment:
  CODEX_BIN         Codex binary path. Defaults to ~/.local/bin/codex, then codex on PATH.
  PROXY_URL         HTTP/HTTPS proxy URL. Default: http://127.0.0.1:7897
  SOCKS_PROXY_URL   ALL_PROXY URL. Default: socks5://127.0.0.1:7897
  NO_PROXY_VALUE    NO_PROXY value. Default: 127.0.0.1,localhost
EOF
}

resolve_codex() {
  if [[ -n "${CODEX_BIN:-}" ]]; then
    printf '%s\n' "$CODEX_BIN"
    return
  fi

  if [[ -x "$HOME/.local/bin/codex" ]]; then
    printf '%s\n' "$HOME/.local/bin/codex"
    return
  fi

  command -v codex
}

APPLY=0
case "${1:-}" in
  "")
    ;;
  --apply)
    APPLY=1
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

CODEX="$(resolve_codex)"
PROXY_URL="${PROXY_URL:-http://127.0.0.1:7897}"
SOCKS_PROXY_URL="${SOCKS_PROXY_URL:-socks5://127.0.0.1:7897}"
NO_PROXY_VALUE="${NO_PROXY_VALUE:-127.0.0.1,localhost}"

print_env() {
  cat <<EOF
export HTTP_PROXY="$PROXY_URL"
export HTTPS_PROXY="$PROXY_URL"
export ALL_PROXY="$SOCKS_PROXY_URL"
export NO_PROXY="$NO_PROXY_VALUE"
EOF
}

print_commands() {
  print_env
  cat <<EOF
"$CODEX" app-server daemon stop || true
"$CODEX" app-server daemon start
"$CODEX" app-server daemon enable-remote-control
"$CODEX" app-server daemon version
EOF
}

if [[ "$APPLY" -ne 1 ]]; then
  echo "dry-run: no changes were made"
  echo
  print_commands
  echo
  echo "Run with --apply to execute."
  exit 0
fi

export HTTP_PROXY="$PROXY_URL"
export HTTPS_PROXY="$PROXY_URL"
export ALL_PROXY="$SOCKS_PROXY_URL"
export NO_PROXY="$NO_PROXY_VALUE"

"$CODEX" --version
"$CODEX" app-server daemon stop || true
"$CODEX" app-server daemon start
"$CODEX" app-server daemon enable-remote-control
"$CODEX" app-server daemon version
