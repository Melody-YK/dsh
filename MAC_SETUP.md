# Mac 版 DSH 手机远程访问实现方案

> 目标：让手机在**任意网络**（家里/出门）通过 Tailscale 访问这台 Mac 上的 DSH，
> 与 Windows 主机上已验证的方案对齐（同一套手机 App，同一套架构）。

---

## 一、架构（和 Windows 版一致，核心组件全跨平台）

```
手机 DSH Mobile App
   │  http://<Mac的Tailscale IP>:3081
   ▼
Tailscale 网络（tailnet，端到端加密）
   ▼
Mac 上的 tailscaled ── serve tcp:3081 ──→ 127.0.0.1:3080（本机 DSH 实例）
```

**关键约束**（DSH 的跨平台安全设计）：
1. DSH **禁止 `--host 0.0.0.0`**（防止 RCE 暴露网络），只能绑 `127.0.0.1`
2. 外部流量必须经 Tailscale serve 转发进来（serve 是 tailscaled 的监听，不触发 macOS 应用防火墙，不需要 sudo）
3. `/api` 有**信任围栏**：请求的 Host 头必须是 loopback 或 `--trusted-host` 声明的地址，否则 403

---

## 二、实施步骤

### Step 1：Tailscale 安装与登录（一次性）

```bash
# 官网下载 macOS 版安装（或 App Store 安装）
# 登录（会打印授权链接，浏览器打开用账号登录）
sudo tailscale up
# 确认已登录并拿到 IP
tailscale status
tailscale ip -4      # 记下这个 100.x.y.z，下面要用
```

Mac 的 Tailscale 登录后**开机自启、状态持久**，不需要每次手动连。

### Step 2：启动 DSH（带信任名单）

```bash
# 先把 Tailscale IP 存进变量，避免手敲错
TS_IP=$(tailscale ip -4 | head -1)

# 用你 Mac 上实际可用的 dsh 启动命令（dsh / pnpm start / node bin.js 皆可），
# 核心是加上以下三个参数：
dsh web --host 127.0.0.1 --port 3080 --trusted-host "$TS_IP"
```

说明：
- `--trusted-host 100.x.y.z` 用 **port-less 形式**（匹配任意端口，因为手机访问时 Host 是 `100.x.y.z:3081`）
- 如果还要支持局域网直连，另加 `--trusted-host <局域网IP>`（可选，Tailscale 已覆盖远程场景）

### Step 3：Tailscale serve 转发（幂等，可重复执行）

```bash
tailscale serve --bg --tcp=3081 3080
tailscale serve status   # 确认：tcp://<TS_IP>:3081 -> tcp://127.0.0.1:3080
```

### Step 4：本机验证（模拟手机路径）

```bash
# 1) 握手（应返回 version/cwd，HTTP 200）
curl -s -X POST http://$TS_IP:3081/api/host.describe \
  -H 'Content-Type: application/json' \
  -d '{"type":"client-request","rpcId":"test-0001","method":"host.describe","payload":{}}'

# 2) 会话列表（应返回 items 数组）
curl -s -X POST http://$TS_IP:3081/api/session.list \
  -H 'Content-Type: application/json' \
  -d '{"type":"client-request","rpcId":"test-0002","method":"session.list","payload":{}}'

# 3) 反向验证信任围栏：用未声明的 Host 应被拒（403 正常）
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:3080/api/host.describe \
  -H 'Host: evil.example.com' -H 'Content-Type: application/json' \
  -d '{"type":"client-request","rpcId":"test-0003","method":"host.describe","payload":{}}'
```

### Step 5：一键启动脚本 + 连接页（可选但推荐）

存为 `~/dsh-mobile/start-dsh.command`，`chmod +x` 后 Finder 里**双击即运行**：

```bash
#!/bin/bash
set -e

# 1) 拿 Tailscale IP
TS_IP=$(tailscale ip -4 | head -1)
if [ -z "$TS_IP" ]; then
  echo "Tailscale 未登录或未运行，先执行: sudo tailscale up"
  exit 1
fi

# 2) 启动 DSH（已在跑则跳过；注意：绝不要重复起第二个实例！）
if ! lsof -iTCP:3080 -sTCP:LISTEN >/dev/null 2>&1; then
  nohup dsh web --host 127.0.0.1 --port 3080 --trusted-host "$TS_IP" \
    >> ~/dsh-mobile/dsh-3080.log 2>&1 &
  sleep 4
else
  echo "DSH 已在运行，跳过启动"
fi

# 3) Tailscale serve（幂等）
tailscale serve --bg --tcp=3081 3080

# 4) 生成连接页（大字 URL + 二维码），浏览器打开
URL="http://$TS_IP:3081"
HTML=~/dsh-mobile/connect.html
mkdir -p ~/dsh-mobile
cat > "$HTML" <<EOF
<!doctype html>
<html><head><meta charset="utf-8"><title>DSH Mobile 连接</title></head>
<body style="font-family:sans-serif;text-align:center;padding:40px 24px;">
<h1>DSH Mobile 连接</h1>
<p style="color:#666;">手机 DSH Mobile → 服务地址 → 点扫码图标，扫下面的二维码</p>
<p style="font-size:26px;color:#4D6BFE;user-select:all;">$URL</p>
<img src="https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=$URL" width="280" height="280" alt="二维码加载失败请手动输入地址">
<p style="color:#999;">扫完关掉这个页面即可，服务在后台运行。</p>
</body></html>
EOF
open "$HTML"
echo "完成。手机连接地址: $URL"
```

### Step 6：手机端

- **Android**：安装 App（从 Windows 主机桌面拿 `app-release.apk`，或让 Windows 上的 dsh 重新构建一份发你），打开后：
  - 服务地址输入框右侧点**扫码图标** → 扫连接页二维码，或手动填 `http://<Mac的Tailscale IP>:3081`
- **iPhone**：App 是 Flutter 写的，`flutter build ios` 可出 iOS 版（需 Xcode + Apple 账号签名；免费账号侧载 7 天重签一次）。需要的话让 Windows 上的 dsh 提供 iOS 构建配置。

---

## 三、必须避开的坑（Windows 主机已踩过，Mac 同样适用）

1. **禁止 `--host 0.0.0.0`**：DSH 会直接报错拒绝启动（安全设计），不要尝试绕过。
2. **绝不启动第二个 DSH 实例共享同一 profile**：两个实例并发写同一份会话存储会**损坏会话日志**（曾经导致 `session.history` 报 "corrupt session log / seq gap"）。判断"已在跑"用 `lsof -iTCP:3080 -sTCP:LISTEN`，不要靠猜。
3. **trusted-host 不对 → 全部 403**：手机访问的 Host 头是 `<TailscaleIP>:3081`，所以 trusted-host 写 `100.x.y.z`（不带端口）。IP 变了要重启 DSH 更新参数。
4. **配置文件在 `~/.dsh/`**：settings.yaml、.credentials.yaml。想复用 Windows 上的模型配置（比如 tokenrhythm），把 `llm-pi-ai:` 段和凭据文件对应内容拷过来。
5. **Mac 上 DSH 的启动命令**：取决于安装方式（npm 全局 / 源码仓库 `pnpm start` / corepack），用你机器上实际能跑的那个，参数照加即可。

---

## 四、验收清单

- [ ] `tailscale status` 显示 Mac 在线，手机端 Tailscale 也在线（同一账号）
- [ ] `curl http://$TS_IP:3081/api/host.describe` 返回 HTTP 200 + version/cwd
- [ ] 未声明 Host 的请求返回 403（围栏工作正常）
- [ ] 手机 App 连接后能看到会话列表、发消息、收回复
- [ ] 手机关 WiFi 用流量（走 Tailscale）仍能连接
- [ ] 电脑和手机各自新建/归档会话，双方实时同步
