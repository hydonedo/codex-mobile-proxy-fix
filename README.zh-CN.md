# Codex 手机远程连接代理修复

这个仓库记录一个实际修复路径：Mac 上的 Codex 已经扫码绑定 ChatGPT 手机端，但手机里一直显示主机离线。根因不是显示名称，而是本机 `app-server` daemon 没有带代理环境变量启动，导致连接 ChatGPT relay 的 websocket 握手超时。

测试环境：macOS，Codex CLI `0.133.0`。

## 典型现象

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

HTTP_PROXY="$PROXY_URL" \
HTTPS_PROXY="$PROXY_URL" \
ALL_PROXY="$SOCKS_PROXY_URL" \
NO_PROXY="$NO_PROXY_VALUE" \
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
HTTP_PROXY="$PROXY_URL" \
HTTPS_PROXY="$PROXY_URL" \
ALL_PROXY="$SOCKS_PROXY_URL" \
NO_PROXY="$NO_PROXY_VALUE" \
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
bash scripts/codex-remote-proxy-check.sh --with-proxy
```

预览重启命令，不执行：

```bash
bash scripts/codex-remote-proxy-restart.sh
```

真正执行：

```bash
PROXY_URL="http://127.0.0.1:7897" \
SOCKS_PROXY_URL="socks5://127.0.0.1:7897" \
bash scripts/codex-remote-proxy-restart.sh --apply
```

## 注意

- 这通常不是可见主机名的问题。
- 关键是 daemon 启动时要继承代理环境变量。
- 如果手机还显示旧版本或旧节点，重新扫码绑定新的 host。
- 不要把 `codex app-server --listen ws://0.0.0.0:PORT` 暴露到公网。

官方资料：

- [Codex remote connections](https://developers.openai.com/codex/remote-connections)
- [Codex app-server](https://developers.openai.com/codex/app-server)
- [Codex installer](https://chatgpt.com/codex/install.sh)
