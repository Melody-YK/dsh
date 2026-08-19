# DSH Mobile — 项目进度总览

> 📌 **本文档写给接手本项目的 Mac 端大模型（AI agent）阅读。**
> 读完本文档后，你应该清楚：项目是什么、做完了什么、还没做什么、以及下一步该做什么。

---

## 一、项目是什么

**DSH Mobile** 是一个原生 Flutter 手机客户端，直连 DeepSeek Harness（DSH）后端的 `/api` 协议（HTTP 一元 RPC + WebSocket 下行事件流），无需修改 DSH 服务端任何代码。

- **目标平台**：Android（已构建 APK）+ iOS（Flutter 工程已就绪，缺 Xcode 构建）
- **连接方式**：局域网直连 + Tailscale 远程（已验证）
- **服务端**：DSH 运行在 Windows/Mac 上，手机 App 通过网络直连
- **协议**：完全复用 DSH 的 `/api` 协议，不引入中间层

---

## 二、已完成功能 ✅

### 核心协议层（`lib/core/protocol/`）
| 文件 | 功能 | 状态 |
|---|---|---|
| `envelope.dart` | 四象限 RPC 信封（client-request / server-response / server-request / client-response），UUID 生成 | ✅ |
| `rpc_client.dart` | `POST /api/<method>` 一元调用 + `POST /api/respond`，超时 90s | ✅ |
| `downlink_stream.dart` | WebSocket 下行流（`/api/events.mux`、`/api/events.host`） | ✅ |
| `connection.dart` | 连接管理：握手 + 双流 + 指数退避重连（500ms → 10s cap） | ✅ |
| `mux_frame.dart` | Mux 帧模型：session/event、approval/*、question/* 等 | ✅ |
| `host_frame.dart` | Host 帧模型：session-added/removed/status 等 | ✅ |

### API 层（`lib/core/api/sessions_api.dart`）
| 功能 | 状态 |
|---|---|
| 会话 CRUD（list/create/history/prompt/cancel） | ✅ |
| 工作区管理（list/create/rename/delete/archiveSession/insertSessionBefore） | ✅ |
| 模型选择（models + selectModel，含 reasoning effort 支持） | ✅ |
| 目录浏览（host.listDirectory + host.pickDirectory） | ✅ |

### 状态管理（`lib/state/`）
| 功能 | 状态 |
|---|---|
| 全局连接生命周期 + 会话列表实时刷新（`app_state.dart`） | ✅ |
| 单会话事件缓冲 + surfaceOp 折叠 + 断线补拉（`chat_controller.dart`） | ✅ |
| 乐观用户消息回显（消息发出即显示，不等服务器回包） | ✅ |
| 本地 SharedPreferences 缓存最近消息（断线恢复快） | ✅ |
| 初始历史限制 12 条 + 上滑自动加载更多 | ✅ |

### UI 界面（`lib/screens/`）
| 界面 | 功能 | 状态 |
|---|---|---|
| 服务地址配置 | 手动输入 + QR 扫码填入 | ✅ |
| 会话列表 | 工作区树/分组、未分组会话、已归档会话 | ✅ |
| 工作区管理 | 新建/重命名/删除工作区、归档/恢复/移动会话 | ✅ |
| 聊天界面 | 倒序显示（最新在前）、上滑加载历史 | ✅ |
| 消息渲染 | Markdown 渲染（`flutter_markdown`） | ✅ |
| 推理块 | 折叠/展开 reasoning（默认折叠，预览 160 字符） | ✅ |
| 工具消息 | 过滤不显示（与 Web DSH 行为一致） | ✅ |
| 模型选择器 | AppBar 下拉，按 provider 分组，支持 reasoning effort | ✅ |
| 目录选择器 | 浏览主机目录 / 调用原生选择器 | ✅ |
| 审批弹窗 | 工具审批（允许一次/拒绝）、提问弹窗 | ✅ |
| QR 扫码 | `mobile_scanner` 扫描服务地址二维码 | ✅ |

### 辅助脚本（`tools/`）
| 脚本 | 用途 |
|---|---|
| `port-forward.mjs` | Node.js TCP 端口转发器（`0.0.0.0:3081 → 127.0.0.1:3080`） |
| `smoke-test.mjs` | 对运行中的 DSH 做只读协议冒烟测试 |

### 启动脚本（项目根目录）
| 脚本 | 用途 |
|---|---|
| `start-all.ps1` / `start-all.bat` | Windows 一键启动 DSH + 转发器 + Tailscale serve + 连接页 |
| `stop-all.ps1` / `stop-all.bat` | Windows 一键停止所有服务 |
| `start-dsh-3080.bat` / `start-mobile.bat` | 开发用独立启动脚本 |

### 文档
| 文档 | 内容 |
|---|---|
| `PHONE_SETUP.md` | 手机端从零到跑起来的完整流程（Windows 环境） |
| `MAC_SETUP.md` | Mac 端 DSH 远程访问实施方案（Tailscale + 端口转发） |
| `PROGRESS.md` | 本文档，项目进度总览 |

---

## 三、尚未完成 ❌

### 高优先级（建议先做）
1. **iOS 构建与测试**
   - Flutter 工程已跨平台，但从未在 iOS 上构建/运行过
   - 需要：Xcode + Apple Developer 账号（免费账号可侧载，7 天重签一次）
   - 命令：`flutter build ios`（在 Mac 上执行）

2. **Mac 版一键启动脚本**
   - `MAC_SETUP.md` 里有 bash 脚本草稿，但未独立成 `.command` 文件
   - 需要：创建 `start-dsh.command`，双击即可启动 DSH + Tailscale serve + 打开连接页
   - 对应停止脚本：`stop-dsh.command`

3. **GitHub 自动更新（App 内"检查更新"按钮）**
   - 当前状态：用户请求添加自动更新按钮，尚未实现
   - 推荐方案：
     - GitHub Actions CI 构建签名 APK + IPA
     - 发布页托管版本清单（JSON）
     - App 内"检查更新"按钮读取清单，比对版本号
     - 有更新时打开浏览器跳转到 GitHub Releases 下载页
   - **不要**让 App 直接 `git pull` 或下载未签名 APK

### 中优先级
4. **图片发送 UI**
   - 协议层已支持 `content: [{type:"image",...}]` base64 图片
   - 聊天界面未接入图片选择/拍照按钮

5. **Goal / 子代理面板**
   - 协议层已封装相关 API
   - UI 未实现

6. **消息编辑 / 重发**
   - 当前不支持编辑已发送消息

### 低优先级
7. **深色模式完善**
   - Flutter Material 3 已自动适配基础深色模式
   - 部分自定义组件可能未覆盖

8. **多语言 / 国际化**
   - 当前仅中文硬编码

---

## 四、架构速览

```
lib/
├── main.dart                      # 入口：恢复配置 → 路由
├── navigation.dart                # 全局 NavigatorKey
├── core/
│   ├── protocol/
│   │   ├── envelope.dart          # 四象限 RPC 信封
│   │   ├── rpc_client.dart        # HTTP 一元 RPC
│   │   ├── downlink_stream.dart   # WebSocket 下行流
│   │   ├── connection.dart        # 连接管理 + 重连
│   │   ├── mux_frame.dart         # Mux 事件帧
│   │   └── host_frame.dart        # Host 事件帧
│   └── api/
│       └── sessions_api.dart      # 会话/工作区/模型 API 封装
├── state/
│   ├── app_state.dart             # 全局状态
│   └── chat_controller.dart       # 单会话控制器
├── screens/
│   ├── server_config_screen.dart  # 服务地址配置
│   ├── session_list_screen.dart   # 会话列表 + 工作区
│   ├── chat_screen.dart           # 聊天界面
│   ├── scanner_screen.dart        # QR 扫码
│   └── directory_picker_screen.dart # 目录选择
├── widgets/
│   └── respond_handler.dart       # 全局审批/提问弹窗
└── main.dart
```

---

## 五、如何在 Mac 上构建

### 前置条件
```bash
# 1. 安装 Flutter SDK（3.3.0+，推荐 3.47.0）
# https://docs.flutter.dev/get-started/install/macos

# 2. 安装 Xcode（App Store）
# 打开一次 Xcode 接受协议，确保命令行工具已安装

# 3. 克隆仓库
git clone https://github.com/Melody-YK/dsh.git
cd dsh

# 4. 安装依赖
flutter pub get

# 5. 运行分析（验证无编译错误）
flutter analyze

# 6. 运行测试
flutter test
```

### 构建 Android APK
```bash
flutter build apk --release
# 输出：build/app/outputs/flutter-apk/app-release.apk
```

### 构建 iOS（需 Xcode）
```bash
flutter build ios --release
# 然后在 Xcode 中打开 ios/Runner.xcworkspace 进行签名和归档
```

---

## 六、Mac 端 DSH 服务端部署

参考 `MAC_SETUP.md` 的完整步骤。核心流程：

1. 安装 Tailscale 并登录（`sudo tailscale up`）
2. 启动 DSH：`dsh web --host 127.0.0.1 --port 3080 --trusted-host <Tailscale_IP>`
3. 配置 Tailscale Serve：`tailscale serve --bg --tcp=3081 3080`
4. 手机 App 填 `http://<Mac_Tailscale_IP>:3081`

**关键约束**（和 Windows 版一致）：
- DSH **禁止 `--host 0.0.0.0`**（安全设计，会直接拒绝启动）
- 绝不启动两个 DSH 实例共享同一 profile（会损坏会话日志）
- 单实例检测用 `lsof -iTCP:3080 -sTCP:LISTEN`
- 配置文件在 `~/.dsh/`（settings.yaml、.credentials.yaml）

---

## 七、代码同步策略（Mac ↔ Windows）

### 推荐方案：GitHub 作为单一事实来源
1. **本仓库**（`https://github.com/Melody-YK/dsh`）是代码的唯一事实来源
2. Windows 和 Mac 都从此仓库 clone/pull
3. 修改代码后 push 到 GitHub，另一边 pull 更新
4. **绝不**提交以下内容：
   - `build/`、`.dart_tool/`、`logs/`（已在 .gitignore）
   - `.credentials.yaml`、API 密钥（安全风险）
   - 个人配置文件（`~/.dsh/settings.yaml`）
   - 构建产物（APK、IPA、zip）

### 工作流
```bash
# Windows 上修改代码后
git add -A
git commit -m "描述改动"
git push

# Mac 上同步
git pull
flutter pub get
flutter analyze
```

### 注意
- DSH 服务端配置（`~/.dsh/settings.yaml`）是**机器相关**的，不同步
- API 密钥（`.credentials.yaml`）**绝不提交到 Git**，用环境变量或手动拷
- 模型配置、provider 配置是机器相关的，Mac 需要独立配置

---

## 八、自动更新方案（待实现）

用户要求添加 App 内"检查更新"按钮。推荐方案：

### 服务端（GitHub Actions CI）
1. 推送 tag（如 `v0.2.0`）触发 GitHub Actions
2. CI 自动构建 Android APK（签名）和 iOS IPA
3. 发布到 GitHub Releases，附带版本清单 JSON

### 客户端（Flutter App）
1. App 内添加"检查更新"按钮（设置页或关于页）
2. 请求 `https://api.github.com/repos/Melody-YK/dsh/releases/latest`
3. 比对本机版本号（`pubspec.yaml` 的 `version`）
4. 有新版本 → 打开浏览器跳转到 GitHub Releases 下载页
5. **不要**在 App 内直接下载/安装 APK（Android 需要用户授权"安装未知来源"）

### 文件结构建议
```
dsh-mobile-client/
├── .github/
│   └── workflows/
│       └── build.yml          # CI：flutter analyze + test + build apk
├── lib/
│   └── screens/
│       └── about_screen.dart  # 关于页 + 检查更新按钮（待创建）
```

---

## 九、测试状态

- `flutter analyze`：✅ 无问题
- `flutter test`：✅ 12 个测试全部通过
- `node tools/smoke-test.mjs`：✅ 对运行中的 DSH 冒烟测试通过

---

## 十、给 Mac 端大模型的任务清单

如果你是一个在 Mac 上接手本项目的 AI agent，以下是你应该做的事情（按优先级排列）：

### 第一优先级：让 Mac 能跑起来
- [ ] `git clone` 本仓库
- [ ] `flutter pub get && flutter analyze && flutter test`
- [ ] 阅读 `MAC_SETUP.md`，在 Mac 上部署 DSH 服务端 + Tailscale
- [ ] 创建 `start-dsh.command`（Mac 版一键启动脚本，双击运行）
- [ ] 创建 `stop-dsh.command`（Mac 版停止脚本）
- [ ] 验证手机 App 能连上 Mac 的 DSH

### 第二优先级：补齐功能
- [ ] 尝试 `flutter build ios`（需 Xcode）
- [ ] 实现"检查更新"按钮（按第八章的方案）
- [ ] 创建 `.github/workflows/build.yml`（CI 自动构建）

### 第三优先级：优化体验
- [ ] 图片发送 UI
- [ ] 完善深色模式
- [ ] 更新 `PHONE_SETUP.md`（加入 Mac 相关内容）

### 永远不要做的事情
- ❌ 提交 `.credentials.yaml`、API 密钥、证书
- ❌ 提交 `build/`、`.dart_tool/`、`logs/`
- ❌ 在 Mac 上启动两个 DSH 实例共享同一 profile
- ❌ 在 App 里实现 `git pull` 自动更新代码（应该用版本清单 + 跳转浏览器下载 APK）
- ❌ 修改 `pubspec.lock` 后不测试

---

## 十一、环境信息（Windows 主机当前状态）

| 项目 | 值 |
|---|---|
| Flutter SDK | 3.47.0 @ `D:\dev\flutter\flutter` |
| DSH 版本 | DeepSeek Harness（`@deepseek-ai/dsh`） |
| Android SDK | 已配置，NDK 28.2.13676358 |
| 最新 APK | `app-release.apk`（约 67 MB，已签名） |
| Windows DSH 路径 | `D:\Users\Melody\Desktop\日常不用\deepseek-harness-app` |
| DSH 配置路径 | `C:\Users\Melody\.dsh\` |
| Tailscale IP | 动态（`tailscale ip -4` 获取） |

---

*最后更新：2026-08-15*