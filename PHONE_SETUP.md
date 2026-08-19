# DSH Mobile 手机使用指南

本文档说明从零到在手机上跑起来的完整流程（Windows 和 Mac 环境）。

## ✅ 本机状态

### Windows 主机（2026-08-15）
- **Flutter SDK 3.47.0 已安装**：`D:\dev\flutter\flutter`（PATH 已配置）
- **APK 已构建**：`app-release.apk`（49.6 MB，已签名）
- **DSH 服务端**：已配置 Tailscale + 端口转发

### Mac 主机（2026-08-19）
- **Flutter SDK 3.47.0 已安装**：`~/flutter/bin/flutter`
- **DSH 服务端**：已配置 Tailscale + 端口转发（`dsh-mobile` 插件）
- **Tailscale IP**：`100.122.227.32`
- **一键启动**：双击 `~/Desktop/dsh-mobile/start-dsh.command`
- **一键停止**：双击 `~/Desktop/dsh-mobile/stop-dsh.command`
- **DSH 内命令**：`/dsh-mobile status` / `/dsh-mobile start` / `/dsh-mobile open`

## 一、传到手机（现在就能做）

从 Windows 主机：
- 方式 A（USB）：`adb install -r build\app\outputs\flutter-apk\app-release.apk`
- 方式 B（无线）：把 `app-release.apk` 通过微信/QQ/网盘发到手机

从 Mac 主机（构建 APK 后）：
- 方式 A（USB）：`adb install -r build/app/outputs/flutter-apk/app-release.apk`
- 方式 B（Taildrop）：在 Windows 主机执行 `tailscale file cp app-release.apk melodymacbook-air:` 传文件到 Mac
- 方式 C（无线）：把 APK 通过微信/QQ/网盘发到手机

## 二、服务端：让 DSH 能被手机访问

> ⚠️ 本版 DSH 出于安全**禁止 `--host 0.0.0.0`**（防止 RCE 暴露到网络），
> 所以正确姿势是：实例绑 127.0.0.1 + `--trusted-host` 声明手机访问的地址 +
> 一个用户级端口转发器。

### 一键启动（推荐）

**Windows**：双击 `start-all.bat`，自动完成全部三件事（DSH + 转发器 + Tailscale serve + 连接页）。

**Mac**：双击 `~/Desktop/dsh-mobile/start-dsh.command`，或在 DSH 聊天框输入 `/dsh-mobile open`。
启动后会自动：检测 Tailscale IP → 写入信任名单 → 配置 serve 转发 → 生成二维码连接页。

### 手动启动（等价命令）

**Windows**：
```powershell
# 1. 启动 DSH
D:\Users\Melody\Desktop\日常不用\deepseek-harness-app\node_modules\.bin\dsh.CMD web --host 127.0.0.1 --port 3080 --trusted-host 192.168.1.4

# 2. 端口转发
node tools\port-forward.mjs 3081 3080
```

**Mac**：
```bash
# 已通过 dsh-mobile 插件自动管理，无需手动执行
# 如需手动：
TS_IP=$(tailscale ip -4 | head -1)
dsh web --host 127.0.0.1 --port 3080 --trusted-host "$TS_IP"
tailscale serve --bg --tcp=3081 3080
```

### 远程（出门在外，Tailscale）

**Windows 主机**：Tailscale IP `100.106.157.69`（desktop-fu8glfm），已配置 serve。

**Mac 主机**：Tailscale IP `100.122.227.32`（melodymacbook-air），已配置 serve + dsh-mobile 插件。

**手机端**（同 tailnet 账号 `1340135887@`）：
1. 手机装 Tailscale App，登录同一账号并保持连接
2. DSH Mobile 里填：
   - 连 Windows：`http://100.106.157.69:3081`
   - 连 Mac：`http://100.122.227.32:3081`
3. 或扫码连接页上的二维码

常用命令：
```powershell
tailscale status                        # 查看状态/IP
tailscale serve status                  # 查看转发配置
tailscale serve --tcp=3081 off          # 关闭转发
tailscale serve --bg --tcp=3081 3081    # 重新开启转发
```

⚠️ `/api` 没有用户认证（信任围栏只防 DNS rebinding / 跨站；未声明的 Host 一律 403）。
Tailscale 之外的公网暴露必须套 TLS + 鉴权，否则等于把你的 agent 交给陌生人。

## 三、手机上：配置与使用

1. 打开 DSH Mobile，输入服务地址：
   - 局域网：`http://192.168.x.x:3080`（电脑 IP，`ipconfig` 可查）
   - 远程：`http://100.x.y.z:3080`（电脑的 Tailscale IP）
2. 点"连接"→ 握手成功自动进入会话列表
3. 点右下角 + 新建会话，或点已有会话进入聊天
4. 输入消息发送；Agent 请求执行工具时会弹出"允许一次 / 拒绝"卡片
5. Agent 向你提问时弹出问题卡片，可选选项或填自定义答案

## 四、开发模式（USB 调试，边改边看）

手机开启"开发者选项 → USB 调试"，连上电脑后：

```powershell
adb devices              # 应看到设备
cd D:\workspace\clawbox-main\dsh-mobile-client
flutter run              # 热重载到手机
```

无线调试（Android 11+，免 USB）：
1. 手机"开发者选项 → 无线调试"开启，记录 IP:端口
2. `adb pair <IP>:<配对端口>` 输配对码
3. `adb connect <IP>:<调试端口>`
4. `flutter run`

## 常见问题

| 现象 | 处理 |
|---|---|
| 连接失败/超时 | 检查电脑防火墙是否放行 3080；手机与电脑是否同网段 |
| `flutter doctor` 提示 Android licenses | 运行 `flutter doctor --android-licenses` 全选接受 |
| 首次构建很慢 | 正常，Gradle 依赖下载；后续构建变快 |
| 安装 APK 提示解析失败 | 确保 Android 7.0+；debug APK 未签名限制可改用 `flutter build apk --release` |
| 手机连不上电脑 IP | 电脑开防火墙入站规则：放行 TCP 3080（仅限专用网络） |
