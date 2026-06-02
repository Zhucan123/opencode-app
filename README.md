# OpenCode Mobile

> 在手机上使用 [opencode](https://opencode.ai) AI 编程助手

通过 SSH 隧道连接你的服务器，在手机上原生体验 opencode——查看会话历史、发送指令、实时接收 AI 回复。

---

## 功能

- 🔐 **SSH 连接** — 支持密码和 PEM 私钥认证
- 💬 **实时对话** — SSE 流式接收 AI 回复，断线自动重连
- 🗂 **会话管理** — 查看历史会话，新建/删除会话
- ⚙️ **模式切换** — 支持 build / plan 及自定义模式
- 📁 **工作目录** — 每台服务器可配置独立工作目录
- 🔒 **安全存储** — 密码和私钥使用 Android Keystore 加密

## 工作原理

```
手机 App
  ↓ SSH 连接
远端服务器（运行 opencode serve）
  ↓ SSH 本地端口转发
http://localhost:14096
  ↓ HTTP / SSE
opencode API
```

AI 对话完全在你自己的服务器上处理，App 不连接任何第三方服务。

---

## 快速开始

### 前置条件

服务器上需要安装 opencode：

```bash
curl -fsSL https://opencode.ai/install | sh
```

### 安装 App

从 [Releases](https://github.com/Zhucan123/opencode-app/releases) 下载最新 APK 安装。

或从 [Actions](https://github.com/Zhucan123/opencode-app/actions) 下载最新构建产物。

### 使用

1. 打开 App，点击 **+** 新建服务器配置
2. 填写主机地址、SSH 端口、用户名和认证方式
3. （可选）设置工作目录
4. 点击连接，等待 opencode 启动
5. 开始对话

---

## 开发

```bash
# 克隆
git clone https://github.com/Zhucan123/opencode-app.git
cd opencode-app

# 安装依赖
flutter pub get

# 运行（需要连接的 Android 设备或模拟器）
flutter run

# 构建 APK
flutter build apk --debug
```

**要求**：Flutter 3.24+，Android SDK

---

## 隐私

本 App 不收集任何个人数据，所有配置仅存储在本地设备。

详见 [隐私政策](https://zhucan123.github.io/opencode-app/privacy.html)

---

## License

MIT
