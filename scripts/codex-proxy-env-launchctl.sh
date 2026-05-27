#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/codex-proxy-env-launchctl.sh <status|install|uninstall> [--apply] [--proxy-mode socks-only|mixed|http-only]

Installs or removes a user LaunchAgent that sets Codex proxy environment
variables for future GUI app launches. Dry-run by default for install/uninstall.

Environment:
  PROXY_URL         HTTP/HTTPS proxy URL. Default: http://127.0.0.1:7897
  SOCKS_PROXY_URL   SOCKS proxy URL. Default: socks5://127.0.0.1:7897
  NO_PROXY_VALUE    NO_PROXY value. Default: 127.0.0.1,localhost
  PROXY_MODE        socks-only, mixed, or http-only. Default: socks-only
  LABEL             LaunchAgent label. Default: com.local.codex.proxy-env
EOF
}

ACTION="${1:-status}"
if [[ $# -gt 0 ]]; then
  shift
fi

APPLY=0
PROXY_URL="${PROXY_URL:-http://127.0.0.1:7897}"
SOCKS_PROXY_URL="${SOCKS_PROXY_URL:-socks5://127.0.0.1:7897}"
NO_PROXY_VALUE="${NO_PROXY_VALUE:-127.0.0.1,localhost}"
PROXY_MODE="${PROXY_MODE:-socks-only}"
LABEL="${LABEL:-com.local.codex.proxy-env}"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_PATH="$HOME/Library/Logs/$LABEL.log"
UID_VALUE="$(id -u)"
BOOTSTRAP_TARGET="gui/$UID_VALUE"

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

case "$ACTION" in
  status|install|uninstall)
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

proxy_value_for_key() {
  local key="$1"
  case "$PROXY_MODE" in
    socks-only)
      case "$key" in
        HTTP_PROXY|HTTPS_PROXY|ALL_PROXY|http_proxy|https_proxy|all_proxy)
          printf '%s\n' "$SOCKS_PROXY_URL"
          ;;
        NO_PROXY|no_proxy)
          printf '%s\n' "$NO_PROXY_VALUE"
          ;;
      esac
      ;;
    mixed)
      case "$key" in
        HTTP_PROXY|HTTPS_PROXY|http_proxy|https_proxy)
          printf '%s\n' "$PROXY_URL"
          ;;
        ALL_PROXY|all_proxy)
          printf '%s\n' "$SOCKS_PROXY_URL"
          ;;
        NO_PROXY|no_proxy)
          printf '%s\n' "$NO_PROXY_VALUE"
          ;;
      esac
      ;;
    http-only)
      case "$key" in
        HTTP_PROXY|HTTPS_PROXY|http_proxy|https_proxy)
          printf '%s\n' "$PROXY_URL"
          ;;
        ALL_PROXY|all_proxy)
          printf '\n'
          ;;
        NO_PROXY|no_proxy)
          printf '%s\n' "$NO_PROXY_VALUE"
          ;;
      esac
      ;;
    *)
      echo "Unsupported PROXY_MODE: $PROXY_MODE" >&2
      exit 2
      ;;
  esac
}

shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

xml_escape() {
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

proxy_keys() {
  printf '%s\n' \
    HTTP_PROXY HTTPS_PROXY ALL_PROXY \
    http_proxy https_proxy all_proxy \
    NO_PROXY no_proxy
}

build_launchctl_command() {
  local key value command
  command=""
  while IFS= read -r key; do
    value="$(proxy_value_for_key "$key")"
    if [[ -n "$value" ]]; then
      command="$command/bin/launchctl setenv $key $(shell_quote "$value"); "
    else
      command="$command/bin/launchctl unsetenv $key; "
    fi
  done < <(proxy_keys)
  command="$command/bin/date '+%Y-%m-%dT%H:%M:%S%z codex proxy env loaded' >> $(shell_quote "$LOG_PATH")"
  printf '%s\n' "$command"
}

print_plan() {
  echo "label: $LABEL"
  echo "plist: $PLIST_PATH"
  echo "log: $LOG_PATH"
  echo "bootstrap target: $BOOTSTRAP_TARGET"
  echo "proxy mode: $PROXY_MODE"
  echo
  while IFS= read -r key; do
    value="$(proxy_value_for_key "$key")"
    if [[ -n "$value" ]]; then
      echo "$key=$value"
    else
      echo "$key=<unset>"
    fi
  done < <(proxy_keys)
}

write_plist() {
  local command_xml
  command_xml="$(build_launchctl_command | xml_escape)"
  mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
  /usr/bin/tee "$PLIST_PATH" >/dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/sh</string>
    <string>-c</string>
    <string>$command_xml</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$LOG_PATH</string>
  <key>StandardErrorPath</key>
  <string>$LOG_PATH</string>
</dict>
</plist>
EOF
}

set_current_launchctl_env() {
  local key value
  while IFS= read -r key; do
    value="$(proxy_value_for_key "$key")"
    if [[ -n "$value" ]]; then
      /bin/launchctl setenv "$key" "$value"
    else
      /bin/launchctl unsetenv "$key"
    fi
  done < <(proxy_keys)
}

unset_current_launchctl_env() {
  local key
  while IFS= read -r key; do
    /bin/launchctl unsetenv "$key"
  done < <(proxy_keys)
}

status() {
  local key value
  if [[ -f "$PLIST_PATH" ]]; then
    echo "plist: installed ($PLIST_PATH)"
  else
    echo "plist: not installed ($PLIST_PATH)"
  fi
  echo "launchctl env:"
  while IFS= read -r key; do
    value="$(launchctl getenv "$key" 2>/dev/null || true)"
    if [[ -n "$value" ]]; then
      echo "  $key=$value"
    else
      echo "  $key=<unset>"
    fi
  done < <(proxy_keys)
}

install_agent() {
  if [[ "$APPLY" -ne 1 ]]; then
    echo "dry-run: no changes were made"
    print_plan
    echo
    echo "Run with --apply to install and set current launchctl env."
    return
  fi

  write_plist
  /bin/launchctl bootout "$BOOTSTRAP_TARGET" "$PLIST_PATH" >/dev/null 2>&1 || true
  /bin/launchctl bootstrap "$BOOTSTRAP_TARGET" "$PLIST_PATH"
  set_current_launchctl_env
  echo "installed"
  status
}

uninstall_agent() {
  if [[ "$APPLY" -ne 1 ]]; then
    echo "dry-run: no changes were made"
    echo "Would bootout $PLIST_PATH, unset proxy launchctl env vars, and remove the plist."
    echo
    status
    echo
    echo "Run with --apply to uninstall."
    return
  fi

  /bin/launchctl bootout "$BOOTSTRAP_TARGET" "$PLIST_PATH" >/dev/null 2>&1 || true
  unset_current_launchctl_env
  rm -f "$PLIST_PATH"
  echo "uninstalled"
  status
}

case "$ACTION" in
  status)
    status
    ;;
  install)
    install_agent
    ;;
  uninstall)
    uninstall_agent
    ;;
esac
