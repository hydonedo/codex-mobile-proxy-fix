# 解决 Codex Reconnection 问题

这个仓库记录一个实际修复路径：Codex 在 thinking 前反复出现 `Reconnecting... request timed out`，或 Mac 上的 Codex 已经扫码绑定 ChatGPT 手机端但手机里一直显示主机离线。根因通常不是显示名称，而是 Codex 进程或本机 `app-server` daemon 没有走到稳定的 websocket 代理路径。

测试环境：macOS，Codex CLI `0.133.0` 和 `0.134.0`。

- 中文：当前文件。
- English: [README.md](README.md)。

## 典型现象

- Codex Desktop 或 CLI 在回答开始前反复重连。
- Mac 已唤醒、在线，Codex App 已打开，账号和 workspace 也一致。
- 改可见主机名没有用。
- 不带代理运行 `codex doctor` 时出现 `Responses WebSocket timed out`。
- 带 `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY` 后，websocket 变成 `HTTP 101 Switching Protocols`。

这说明普通 HTTPS 可能能通，但 Codex remote control 需要的 websocket relay 没有走到本地代理。

## 修复命令

把 `7897` 换成你自己的本地代理端口。

```bash
export PROXY_URL="http://127.0.0.1:7897"
export SOCKS_PROXY_URL="socks5://127.0.0.1:7897"
export NO_PROXY_VALUE="127.0.0.1,localhost"
export PROXY_MODE="socks-only"
```

如果只是修 Codex thinking 前反复重连，先跑这个不重启路径。它不会 stop/start `app-server` daemon，所以不会打断当前 iPhone 远程连接。

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

期望看到：

```text
websocket    connected (HTTP 101 Switching Protocols)
```

如果本机缺少 standalone Codex，先安装或更新：

```bash
HTTPS_PROXY="$PROXY_URL" HTTP_PROXY="$PROXY_URL" \
  curl -fsSL https://chatgpt.com/codex/install.sh | \
  HTTPS_PROXY="$PROXY_URL" HTTP_PROXY="$PROXY_URL" sh
```

然后用带代理的环境重启 daemon：

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

最后重新在 Codex App 里打开手机连接/扫码流程，用 ChatGPT 手机端重新扫二维码。

## 验证

不带代理：

```bash
~/.local/bin/codex doctor
```

常见失败信号：

```text
websocket    Responses WebSocket timed out
network      no proxy env vars
```

带代理：

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

期望看到：

```text
network      proxy env vars present
websocket    connected (HTTP 101 Switching Protocols)
app-server   running
```

如果 `codex doctor` 因为 `TERM=dumb` 退出非零，那是非交互终端告警，和 websocket 修复无关。

## Helper 脚本

只读检查：

```bash
PROXY_MODE=socks-only bash scripts/codex-remote-proxy-check.sh --with-proxy
```

固定未来 Codex GUI 启动环境，但不重启当前 App：

```bash
bash scripts/codex-proxy-env-launchctl.sh install
PROXY_MODE=socks-only bash scripts/codex-proxy-env-launchctl.sh install --apply
bash scripts/codex-proxy-env-launchctl.sh status
```

预览重启命令，不执行：

```bash
bash scripts/codex-remote-proxy-restart.sh
```

真正执行：

```bash
SOCKS_PROXY_URL="socks5://127.0.0.1:7897" \
PROXY_MODE=socks-only \
bash scripts/codex-remote-proxy-restart.sh --apply
```

## 注意

- 这通常不是可见主机名的问题。
- 对 thinking 前反复重连的问题，SOCKS-only 是指所有 proxy 变量都使用 `socks5://` 代理地址。本机验证结果显示，这比 `HTTP_PROXY/HTTPS_PROXY` 使用 HTTP 地址、`ALL_PROXY` 使用 SOCKS 地址的混合模式更稳。
- 关键是 daemon 启动时要继承代理环境变量。
- `scripts/codex-proxy-env-launchctl.sh install --apply` 会设置用户级 launchd 环境，未来从 GUI 启动的 Codex 会继承；已经运行的 App 需要退出再打开才会继承。
- `scripts/codex-remote-proxy-restart.sh --apply` 会 stop/start app-server daemon。如果要保留当前 iPhone 远程连接，不要跑 apply。
- 如果手机还显示旧版本或旧节点，重新扫码绑定新的 host。
- 不要把 `codex app-server --listen ws://0.0.0.0:PORT` 暴露到公网。

## 回滚

移除固定的 GUI 启动环境：

```bash
bash scripts/codex-proxy-env-launchctl.sh uninstall
bash scripts/codex-proxy-env-launchctl.sh uninstall --apply
```

官方资料：

- [Codex remote connections](https://developers.openai.com/codex/remote-connections)
- [Codex app-server](https://developers.openai.com/codex/app-server)
- [Codex installer](https://chatgpt.com/codex/install.sh)
