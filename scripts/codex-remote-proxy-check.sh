#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/codex-remote-proxy-check.sh [--with-proxy]

Read-only diagnostics for Codex mobile remote-control proxy issues.

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

WITH_PROXY=0
case "${1:-}" in
  "")
    ;;
  --with-proxy)
    WITH_PROXY=1
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

if [[ "$WITH_PROXY" -eq 1 ]]; then
  export HTTP_PROXY="$PROXY_URL"
  export HTTPS_PROXY="$PROXY_URL"
  export ALL_PROXY="$SOCKS_PROXY_URL"
  export NO_PROXY="$NO_PROXY_VALUE"
fi

echo "codex binary: $CODEX"
"$CODEX" --version

echo
echo "daemon version:"
"$CODEX" app-server daemon version || true

echo
echo "doctor summary:"
set +e
"$CODEX" doctor --summary
doctor_status=$?
set -e

echo
echo "doctor exit status: $doctor_status"
if [[ "$doctor_status" -ne 0 ]]; then
  echo "Non-zero can be expected when only the terminal check fails in non-interactive shells."
fi
