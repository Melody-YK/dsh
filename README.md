# DSH Mobile — DeepSeek Harness 手机端

原生 Flutter 客户端，直连 DSH 后端的 `/api` 协议（HTTP 一元 RPC + WebSocket 下行事件流），
无需修改 DSH 服务端任何代码。

## 功能

- 服务地址配置（手动输入 / QR 扫码）
- 会话列表（host 流实时刷新、运行状态指示）
- 工作区管理（新建/重命名/删除工作区、归档/恢复/移动会话）
- 聊天（最新消息在前、上滑加载历史、Markdown 渲染、推理块折叠/展开）
- 模型选择器（按 provider 分组、支持 reasoning effort 选择）
- 工具审批弹窗（允许一次 / 拒绝）
- 模型提问弹窗（选项 / 自定义答案）
- 取消生成、新建会话、自动重连（官方同款指数退避）
- 目录选择器（浏览主机目录 / 调用原生选择器）

## 快速开始

```bash
flutter pub get
flutter run          # 连接你的手机/模拟器
flutter test         # 协议层单元测试（12 个测试）
node tools/smoke-test.mjs   # 对运行中的 DSH 做只读协议冒烟测试
```

App 首次启动会要求输入服务地址（支持扫码）。

## 构建

```bash
# Android APK
flutter build apk --release
# 输出：build/app/outputs/flutter-apk/app-release.apk

# iOS（需 Mac + Xcode）
flutter build ios --release
```

## 服务端准备（一次性）

**Windows**：双击 `start-all.bat`，自动完成全部启动（DSH + 转发器 + Tailscale serve + 连接页）。

**Mac**：参考 `MAC_SETUP.md` 的完整步骤，或手动执行：

```bash
# 1. 启动 DSH（绑 127.0.0.1，加 Tailscale 信任）
TS_IP=$(tailscale ip -4 | head -1)
dsh web --host 127.0.0.1 --port 3080 --trusted-host "$TS_IP"

# 2. Tailscale 端口转发
tailscale serve --bg --tcp=3081 3080

# 3. 手机 App 填 http://<Mac_Tailscale_IP>:3081
```

⚠️ DSH **禁止 `--host 0.0.0.0`**（安全设计，会直接拒绝启动）。
外部流量必须通过 Tailscale serve 转发。`/api` 没有用户认证，不要裸暴露到公网。

## 架构速览

```
lib/
├── core/
│   ├── protocol/
│   │   ├── envelope.dart        # 四象限 RPC 信封
│   │   ├── rpc_client.dart      # POST /api/<method> 一元调用
│   │   ├── downlink_stream.dart # WS 下行流
│   │   ├── connection.dart      # 连接管理 + 重连
│   │   ├── mux_frame.dart       # Mux 帧
│   │   └── host_frame.dart      # Host 帧
│   └── api/sessions_api.dart    # 会话/工作区/模型 API 封装
├── state/
│   ├── app_state.dart           # 全局状态
│   └── chat_controller.dart     # 单会话控制器
├── screens/                     # 配置页 / 会话列表 / 聊天 / 扫码 / 目录选择
├── widgets/respond_handler.dart # 全局审批与提问弹窗
└── main.dart
```

## 协议对照

- 消息模型：`@deepseek-ai/dsh-client-connection` 的四象限模型
- 端点：`POST /api/<method>`、`POST /api/respond`、WS `/api/events.mux`、`/api/events.host`
- 重连：`500ms × 2^(n-1)` 退避，上限 10s，加随机抖动
- 审批应答：`{approvalId, outcome: "allowed-once"|"rejected"}`
- 提问应答：`{answers: [{id, selected: [...], custom?}]}`

## 已知边界（v0.1）

- 图片发送（base64）协议已支持，UI 未接
- Goal / 子代理面板未做 UI（API 已封装）
- 消息编辑 / 重发未实现
- iOS 未构建测试（Flutter 工程已跨平台就绪）
- 自动更新按钮未实现（方案已设计，见 `PROGRESS.md`）

## 相关文档

| 文档 | 内容 |
|---|---|
| `PROGRESS.md` | 项目进度总览（给 Mac 端大模型看的完整说明） |
| `MAC_SETUP.md` | Mac 端 DSH 远程访问实施方案 |
| `PHONE_SETUP.md` | 手机端从零到跑起来的完整流程 |