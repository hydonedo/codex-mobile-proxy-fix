#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/codex-remote-proxy-restart.sh [--apply] [--proxy-mode socks-only|mixed|http-only]

Dry-run by default. With --apply, restarts the managed Codex app-server daemon
with proxy environment variables and enables remote control.

Environment:
  CODEX_BIN         Codex binary path. Defaults to ~/.local/bin/codex, then codex on PATH.
  PROXY_URL         HTTP/HTTPS proxy URL. Default: http://127.0.0.1:7897
  SOCKS_PROXY_URL   ALL_PROXY URL. Default: socks5://127.0.0.1:7897
  NO_PROXY_VALUE    NO_PROXY value. Default: 127.0.0.1,localhost
  PROXY_MODE        socks-only, mixed, or http-only. Default: socks-only
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

CODEX="$(resolve_codex)"
PROXY_URL="${PROXY_URL:-http://127.0.0.1:7897}"
SOCKS_PROXY_URL="${SOCKS_PROXY_URL:-socks5://127.0.0.1:7897}"
NO_PROXY_VALUE="${NO_PROXY_VALUE:-127.0.0.1,localhost}"
PROXY_MODE="${PROXY_MODE:-socks-only}"

APPLY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      APPLY=1
      shift
      ;;
    --proxy-mode)
      PROXY_MODE="${2:-}"
      shift 2
      ;;
    --proxy-mode=*)
      PROXY_MODE="${1#*=}"
      shift
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
done

apply_proxy_env() {
  case "$PROXY_MODE" in
    socks-only)
      export HTTP_PROXY="$SOCKS_PROXY_URL"
      export HTTPS_PROXY="$SOCKS_PROXY_URL"
      export ALL_PROXY="$SOCKS_PROXY_URL"
      export http_proxy="$SOCKS_PROXY_URL"
      export https_proxy="$SOCKS_PROXY_URL"
      export all_proxy="$SOCKS_PROXY_URL"
      ;;
    mixed)
      export HTTP_PROXY="$PROXY_URL"
      export HTTPS_PROXY="$PROXY_URL"
      export ALL_PROXY="$SOCKS_PROXY_URL"
      export http_proxy="$PROXY_URL"
      export https_proxy="$PROXY_URL"
      export all_proxy="$SOCKS_PROXY_URL"
      ;;
    http-only)
      unset ALL_PROXY all_proxy
      export HTTP_PROXY="$PROXY_URL"
      export HTTPS_PROXY="$PROXY_URL"
      export http_proxy="$PROXY_URL"
      export https_proxy="$PROXY_URL"
      ;;
    *)
      echo "Unsupported PROXY_MODE: $PROXY_MODE" >&2
      usage >&2
      exit 2
      ;;
  esac

  export NO_PROXY="$NO_PROXY_VALUE"
  export no_proxy="$NO_PROXY_VALUE"
}

print_env() {
  echo "# proxy mode: $PROXY_MODE"
  case "$PROXY_MODE" in
    socks-only)
      cat <<EOF
export HTTP_PROXY="$SOCKS_PROXY_URL"
export HTTPS_PROXY="$SOCKS_PROXY_URL"
export ALL_PROXY="$SOCKS_PROXY_URL"
export http_proxy="$SOCKS_PROXY_URL"
export https_proxy="$SOCKS_PROXY_URL"
export all_proxy="$SOCKS_PROXY_URL"
export NO_PROXY="$NO_PROXY_VALUE"
export no_proxy="$NO_PROXY_VALUE"
EOF
      ;;
    mixed)
      cat <<EOF
export HTTP_PROXY="$PROXY_URL"
export HTTPS_PROXY="$PROXY_URL"
export ALL_PROXY="$SOCKS_PROXY_URL"
export http_proxy="$PROXY_URL"
export https_proxy="$PROXY_URL"
export all_proxy="$SOCKS_PROXY_URL"
export NO_PROXY="$NO_PROXY_VALUE"
export no_proxy="$NO_PROXY_VALUE"
EOF
      ;;
    http-only)
      cat <<EOF
unset ALL_PROXY all_proxy
export HTTP_PROXY="$PROXY_URL"
export HTTPS_PROXY="$PROXY_URL"
export http_proxy="$PROXY_URL"
export https_proxy="$PROXY_URL"
export NO_PROXY="$NO_PROXY_VALUE"
export no_proxy="$NO_PROXY_VALUE"
EOF
      ;;
    *)
      echo "Unsupported PROXY_MODE: $PROXY_MODE" >&2
      usage >&2
      exit 2
      ;;
  esac
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

apply_proxy_env

"$CODEX" --version
"$CODEX" app-server daemon stop || true
"$CODEX" app-server daemon start
"$CODEX" app-server daemon enable-remote-control
"$CODEX" app-server daemon version
