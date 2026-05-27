# Codex WebSocket and Mobile Remote Control Proxy Fix

Fix for Codex reconnect loops such as `Reconnecting... request timed out` before thinking, and for a Mac Codex host that stays **Offline** in ChatGPT mobile after QR setup when the local daemon can reach HTTPS but cannot complete the ChatGPT websocket handshake through the right proxy path.

Tested on macOS with Codex CLI `0.133.0` and `0.134.0`.

- English: this file.
- Chinese: [README.zh-CN.md](README.zh-CN.md).

## Symptom

You already completed the mobile QR setup from the Codex App, but ChatGPT mobile keeps showing the host as offline.

Common signals:

- Codex Desktop or CLI shows repeated reconnect attempts before a response starts.
- The Mac is awake, online, signed in to the same ChatGPT account/workspace, and Codex App is open.
- Changing the visible host name does not help.
- `codex doctor` shows `Responses WebSocket timed out` when no proxy env vars are present.
- Running the same check with `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY` succeeds with `HTTP 101 Switching Protocols`.

This can happen when Codex Desktop or your shell traffic uses a local proxy, but the managed `app-server` daemon was started without inheriting that proxy environment.

## Why This Matters

OpenAI's Codex remote-connection docs say mobile access uses a connected Mac host and a secure relay layer. If the host daemon cannot keep its relay websocket connected, the phone has nothing reachable to control, so it appears offline even though QR pairing completed.

Official references:

- [Codex remote connections](https://developers.openai.com/codex/remote-connections)
- [Codex app-server](https://developers.openai.com/codex/app-server)
- [Codex installer](https://chatgpt.com/codex/install.sh)

## Quick Fix

Replace the proxy port with your local proxy. `7897` is only an example.

```bash
export PROXY_URL="http://127.0.0.1:7897"
export SOCKS_PROXY_URL="socks5://127.0.0.1:7897"
export NO_PROXY_VALUE="127.0.0.1,localhost"
export PROXY_MODE="socks-only"
```

For Codex response reconnects, first validate the no-restart path. This does not stop or restart the app-server daemon, so it does not interrupt an existing iPhone remote-control session.

```bash
HTTP_PROXY="$SOCKS_PROXY_URL" \
HTTPS_PROXY="$SOCKS_PROXY_URL" \
ALL_PROXY="$SOCKS_PROXY_URL" \
http_proxy="$SOCKS_PROXY_URL" \
https_proxy="$SOCKS_PROXY_URL" \
all_proxy="$SOCKS_PROXY_URL" \
NO_PROXY="$NO_PROXY_VALUE" \
no_proxy="$NO_PROXY_VALUE" \
~/.local/bin/codex doctor --summary
```

Expected signal:

```text
websocket    connected (HTTP 101 Switching Protocols)
```

Install or update the standalone Codex CLI if your managed install is missing or old:

```bash
HTTPS_PROXY="$PROXY_URL" HTTP_PROXY="$PROXY_URL" \
  curl -fsSL https://chatgpt.com/codex/install.sh | \
  HTTPS_PROXY="$PROXY_URL" HTTP_PROXY="$PROXY_URL" sh
```

Use the standalone binary when multiple Codex binaries exist:

```bash
~/.local/bin/codex --version
```

Restart the managed daemon with proxy env vars:

```bash
~/.local/bin/codex app-server daemon stop || true

HTTP_PROXY="$SOCKS_PROXY_URL" \
HTTPS_PROXY="$SOCKS_PROXY_URL" \
ALL_PROXY="$SOCKS_PROXY_URL" \
http_proxy="$SOCKS_PROXY_URL" \
https_proxy="$SOCKS_PROXY_URL" \
all_proxy="$SOCKS_PROXY_URL" \
NO_PROXY="$NO_PROXY_VALUE" \
no_proxy="$NO_PROXY_VALUE" \
~/.local/bin/codex app-server daemon start

~/.local/bin/codex app-server daemon enable-remote-control
~/.local/bin/codex app-server daemon version
```

Then open the Codex App connection setup again and scan the QR code from ChatGPT mobile.

## Diagnose Before and After

Without proxy env vars:

```bash
~/.local/bin/codex doctor
```

Expected failing signal:

```text
websocket    Responses WebSocket timed out
network      no proxy env vars
```

With proxy env vars:

```bash
HTTP_PROXY="$SOCKS_PROXY_URL" \
HTTPS_PROXY="$SOCKS_PROXY_URL" \
ALL_PROXY="$SOCKS_PROXY_URL" \
http_proxy="$SOCKS_PROXY_URL" \
https_proxy="$SOCKS_PROXY_URL" \
all_proxy="$SOCKS_PROXY_URL" \
NO_PROXY="$NO_PROXY_VALUE" \
no_proxy="$NO_PROXY_VALUE" \
~/.local/bin/codex doctor
```

Expected success signal:

```text
network      proxy env vars present
websocket    connected (HTTP 101 Switching Protocols)
app-server   running
```

`codex doctor` may still exit non-zero in non-interactive terminals because of `TERM=dumb`; that terminal warning is unrelated to the websocket fix.

## Helper Scripts

Read-only check:

```bash
PROXY_MODE=socks-only bash scripts/codex-remote-proxy-check.sh --with-proxy
```

Persist proxy env for future Codex GUI launches without restarting the current app:

```bash
bash scripts/codex-proxy-env-launchctl.sh install
PROXY_MODE=socks-only bash scripts/codex-proxy-env-launchctl.sh install --apply
bash scripts/codex-proxy-env-launchctl.sh status
```

Dry-run restart preview:

```bash
bash scripts/codex-remote-proxy-restart.sh
```

Apply restart:

```bash
SOCKS_PROXY_URL="socks5://127.0.0.1:7897" \
PROXY_MODE=socks-only \
bash scripts/codex-remote-proxy-restart.sh --apply
```

## Notes

- This is not caused by the visible host name if the underlying remote enrollment points to the same host.
- For response-time reconnects, a SOCKS-only environment means all proxy variables use the `socks5://` proxy URL. On this machine that was more stable than mixing HTTP proxy URLs with `ALL_PROXY=socks5://...`.
- The daemon must be started with proxy env vars for the relay websocket path, not only the interactive shell.
- `scripts/codex-proxy-env-launchctl.sh install --apply` sets user-level launchd env for future GUI app launches. Already-running apps need a quit/reopen to inherit it.
- `scripts/codex-remote-proxy-restart.sh --apply` stops and starts the app-server daemon. Do not run it while preserving an active iPhone remote-control session unless you accept that interruption.
- If the mobile app still shows an old host/version after the daemon reconnects, re-run the mobile setup and scan a fresh QR code.
- Do not expose `codex app-server --listen ws://0.0.0.0:PORT` to the public internet. Use the official relay/mobile setup or SSH workflows described in the OpenAI docs.

## Rollback

Remove the persistent GUI launch environment:

```bash
bash scripts/codex-proxy-env-launchctl.sh uninstall
bash scripts/codex-proxy-env-launchctl.sh uninstall --apply
```

Disable remote control:

```bash
~/.local/bin/codex app-server daemon disable-remote-control
```

Restart without proxy env vars:

```bash
~/.local/bin/codex app-server daemon stop || true
~/.local/bin/codex app-server daemon start
```

## License

MIT
