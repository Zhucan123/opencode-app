# OpenCode Mobile

> 📱 在手机上丝滑使用 [opencode](https://opencode.ai) AI 编程助手

OpenCode Mobile 是一个原生的 Flutter 移动端应用，通过 SSH 隧道安全连接到你的私人服务器。它不仅仅是一个终端模拟器，而是专为 OpenCode 打造的原生、沉浸式、高颜值移动端交互界面。在地铁上、咖啡厅里，随时随地 Review 代码、下发指令、审批权限。

---

## ✨ 核心特性

### 🔌 基础连接与安全
- **SSH 隧道透传** — 支持密码与 PEM 私钥认证，利用 `dartssh2` 进行本地端口转发。
- **本地安全存储** — 所有服务器密码和私钥均使用 Android Keystore 原生安全加密，绝不明文存储。
- **零隐私泄露** — AI 对话全流程在你自己的服务器上处理，App 不连接任何第三方云服务。

### 💬 沉浸式 AI 对话体验
- **SSE 流式响应** — 打字机效果实时呈现 AI 思考过程与回复，支持断线自动重连。
- **沉浸式暗黑模式** — 专为极客设计的深色主题，极致的边框与光影细节，高信噪比的信息排版。
- **Markdown & 代码高亮** — 完美支持复杂 Markdown 渲染及多种语言的语法高亮展示。
- **多模型与模式切换** — 支持动态获取服务器可用大模型（Model）列表并无缝切换，支持 `plan`, `build` 等多种工作模式。

### 🛠️ 深度集成的专属交互
- **工具调用卡片 (Tool Execution)** — 当 AI 执行 `bash`, `read_file`, `write_file`, `webfetch` 等工具时，以精致的折叠卡片展示命令与执行结果。
- **原生权限审批盾牌 (Permission Intercept)** — 完美接管官方的安全策略！当 AI 尝试修改外部文件或执行高危命令时，原生底部弹窗拦截，支持 `允许一次`、`始终允许` 或 `拒绝`。
- **智能交互表单 (Question Sheet)** — 原生支持 AI 下发的单选/多选提问，轻松在手机上完成需求决策。
- **Tokens 与成本追踪** — 会话列表实时计算并以等宽极客字体展示 Token 消耗量与预估花费。

---

## 🏗️ 工作原理

```text
📱 手机 App (Flutter 原生 UI)
  │
  ├─ 1. SSH 连接 (22端口)
  ├─ 2. 远端执行: opencode serve --port 4096
  ├─ 3. SSH 本地端口转发 (localhost:14096 -> 远端:4096)
  │
☁️ 远端服务器
  │
  └─ 4. HTTP / SSE 通信 (完全原生的 OpenAPI 接口对接，非终端字符串解析)
```

---

## 🚀 快速开始

### 前置条件
服务器上需要提前安装 opencode 核心：
```bash
curl -fsSL https://opencode.ai/install | sh
```

### 安装 App
- 从 [Releases](https://github.com/Zhucan123/opencode-app/releases) 下载最新 APK 即可直接安装。
- 或者在 Github [Actions](https://github.com/Zhucan123/opencode-app/actions) 中下载最新自动构建产物。

### 使用指南
1. 打开 App，点击首页的 **+** 添加新服务器。
2. 填写主机 IP、SSH 端口、用户名及认证凭据（支持工作目录配置）。
3. 点击卡片连接，等待底层隧道建立及 OpenCode 启动。
4. 开始你优雅的移动端 Coding 之旅。

---

## 💻 开发者指南

**环境要求**：Flutter 3.24+，Android SDK

```bash
# 1. 克隆项目
git clone https://github.com/Zhucan123/opencode-app.git
cd opencode-app

# 2. 安装依赖
flutter pub get

# 3. 运行调试（请连接真机或启动 Android 模拟器）
flutter run

# 4. 构建 Release APK
flutter build apk --release
```

---

## 📄 隐私与协议

本 App 不收集任何个人数据，所有的会话记录与密钥凭证均只存在于你的手机与你配置的目标服务器之间。
详见 [隐私政策](https://zhucan123.github.io/opencode-app/privacy.html)。

开源协议：**MIT License**