# OpenCode Mobile — 技术方案设计

> 通过 SSH 协议在手机上使用 opencode AI 编程助手的 Flutter App

---

## 一、产品概述

### 核心价值
用户在自己的服务器上安装好 opencode，通过本 App SSH 连接后，用手机以**原生移动端 UI**（非终端模拟）操控 opencode 进行 AI 辅助编程。

### 工作流程
```
1. 用户在 App 中配置 SSH 服务器（host/port/user/password）
2. App 建立 SSH 连接，远端执行 `opencode serve --port 4096`
3. App 通过 SSH 本地端口转发将远端 4096 映射到本地
4. App 与本地 localhost:4096 通信（REST API + SSE）
5. 原生 UI 展示 AI 对话、Diff 预览、权限审批等交互
```

### 与其他方案的区别
| 方案 | 问题 |
|------|------|
| SSH + 终端模拟 | TUI 在小屏难用，无触屏优化 |
| 直连 HTTP（无 SSH）| 暴露端口，安全风险 |
| **本方案：SSH 隧道 + HTTP API** | ✅ 安全 + 原生体验 |

---

## 二、技术栈

### 客户端（Flutter）

```yaml
dependencies:
  # SSH 客户端 + 端口转发
  dartssh2: ^2.9.0

  # HTTP 客户端
  dio: ^5.4.0

  # SSE 流式响应
  dio_smart_retry: ^6.0.0

  # 安全存储（Keychain/Keystore）
  flutter_secure_storage: ^9.0.0

  # Markdown + 代码高亮
  flutter_markdown: ^0.7.0
  flutter_highlight: ^0.7.0

  # 状态管理
  riverpod: ^2.5.0

  # 路由
  go_router: ^13.0.0

  # Diff 渲染
  diff_match_patch: ^0.4.1
```

### 服务端（用户已有）
- 任意 Linux 服务器
- 已安装 opencode（`opencode serve` 命令可用）
- SSH 服务运行中

---

## 三、模块架构

```
lib/
├── main.dart
│
├── core/
│   ├── ssh/
│   │   ├── ssh_client.dart          # SSH 连接管理、端口转发
│   │   └── ssh_session_manager.dart # 管理多个 SSH 会话
│   │
│   ├── api/
│   │   ├── opencode_client.dart     # HTTP 客户端封装（Dio）
│   │   ├── sse_client.dart          # SSE 事件流客户端
│   │   └── models/                  # API 数据模型
│   │       ├── session.dart
│   │       ├── message.dart
│   │       ├── permission.dart
│   │       └── event.dart
│   │
│   └── storage/
│       └── server_config_store.dart # 服务器配置安全存储
│
├── features/
│   ├── servers/                     # 服务器管理
│   │   ├── server_list_screen.dart
│   │   ├── server_form_screen.dart
│   │   └── server_provider.dart
│   │
│   ├── connection/                  # 连接流程
│   │   ├── connecting_screen.dart   # 连接动画页面
│   │   └── connection_provider.dart
│   │
│   ├── sessions/                    # opencode 会话
│   │   ├── session_list_screen.dart
│   │   └── session_provider.dart
│   │
│   └── chat/                        # 对话界面（核心）
│       ├── chat_screen.dart
│       ├── chat_provider.dart
│       ├── widgets/
│       │   ├── message_bubble.dart
│       │   ├── tool_execution_card.dart
│       │   ├── diff_preview_card.dart
│       │   ├── permission_sheet.dart
│       │   └── chat_input_bar.dart
│       └── markdown/
│           └── code_block_widget.dart
│
└── shared/
    ├── theme.dart
    └── widgets/
        └── app_scaffold.dart
```

---

## 四、核心数据流

### 4.1 连接建立流程

```
ServerConfig（存储层）
    ↓
SSHClient.connect(host, port, user, password)
    ↓
SSH 握手 + 认证
    ↓
exec("opencode serve --port 4096")
    ↓
SSHClient.forwardLocalPort(localPort: 14096, remotePort: 4096)
    ↓
OpencodeClient(baseUrl: "http://localhost:14096")
    ↓
SSEClient.subscribe("/event")  →  持续监听事件
```

> 本地端口使用 14096 避免与用户本机冲突

### 4.2 发送消息流程

```
用户输入
    ↓
ChatProvider.sendMessage(text)
    ↓
POST /session/:id/prompt_async
    ↓
SSE 流推送事件：
  - session.updated（AI 正在思考）
  - tool.execution（工具调用）
  - permission.requested → 触发 PermissionSheet
  - session.message（消息完成）
    ↓
UI 实时更新（Riverpod StreamProvider）
```

### 4.3 权限审批流程

```
SSE: permission.requested { id, command, description }
    ↓
PermissionSheet 弹出（底部抽屉）
    ↓
用户选择：拒绝 / 允许一次 / 始终允许
    ↓
POST /session/:id/permissions/:permissionId
    { decision: "allow" | "deny", permanent: bool }
    ↓
opencode 继续执行
```

---

## 五、API 集成

### 使用的 opencode HTTP API

```
# 会话
GET    /session                  → 会话列表
POST   /session                  → 新建会话
DELETE /session/:id              → 删除会话

# 消息
GET    /session/:id/message      → 历史消息
POST   /session/:id/prompt_async → 发送消息（异步）
POST   /session/:id/abort        → 中止生成
POST   /session/:id/revert       → 撤销最后一条

# 权限
POST   /session/:id/permissions/:permId → 审批权限请求

# 实时事件
GET    /event                    → SSE 全局事件流
```

### SSE 事件类型处理

```dart
enum OpencodeEvent {
  sessionUpdated,    // AI 回复中
  sessionMessage,    // 消息完成
  toolExecution,     // 工具执行
  permissionRequested, // 需要权限审批
  sessionError,      // 错误
}
```

---

## 六、数据模型

### ServerConfig（本地存储）
```dart
class ServerConfig {
  String id;
  String name;           // 显示名称
  String host;
  int sshPort;           // 默认 22
  String username;
  String password;       // 加密存储于 Keychain
  int opencodePort;      // 默认 4096
  DateTime? lastConnected;
}
```

### ChatMessage（UI 层）
```dart
class ChatMessage {
  String id;
  MessageRole role;      // user | assistant
  List<MessagePart> parts;
  List<ToolExecution> toolExecutions;
  List<FileDiff> diffs;
  DateTime createdAt;
}
```

---

## 七、安全设计

| 项目 | 方案 |
|------|------|
| SSH 密码存储 | iOS Keychain / Android Keystore（flutter_secure_storage） |
| 网络传输 | 全程走 SSH 隧道，不暴露 opencode 端口 |
| opencode 认证 | 可选：`OPENCODE_SERVER_PASSWORD` Basic Auth |
| 多服务器隔离 | 每个连接使用不同本地端口（14096, 14097...）|

---

## 八、状态管理设计（Riverpod）

```
serverListProvider          → 服务器配置列表
connectionProvider(serverId) → SSH + API 连接状态
sessionListProvider          → opencode 会话列表
chatProvider(sessionId)      → 消息流 + 发送状态
pendingPermissionProvider    → 待审批的权限请求
sseEventProvider             → SSE 事件流（StreamProvider）
```

---

## 九、屏幕流程图

```
App 启动
    └─→ 服务器列表
           ├─→ [+] 添加服务器 → 保存 → 返回列表
           └─→ 点击服务器 → 连接中（动画）
                               └─→ 会话列表
                                      ├─→ [+] 新建会话 → 进入对话
                                      └─→ 点击会话 → 对话界面
                                                        ├─→ 权限审批（底部抽屉）
                                                        ├─→ Diff 预览（内联卡片）
                                                        └─→ 工具执行（折叠卡片）
```

---

## 十、MVP 开发阶段

### Phase 1 — 核心可用
- [ ] SSH 连接 + 端口转发
- [ ] 服务器配置 CRUD + 安全存储
- [ ] 会话列表 + 新建会话
- [ ] 发送消息 + SSE 流式接收
- [ ] 基础 AI 回复渲染（文字 + 代码块）

### Phase 2 — 体验完善
- [ ] 权限审批 UI
- [ ] Diff 预览卡片（接受/拒绝）
- [ ] 工具执行折叠卡片
- [ ] 消息撤销 / 中止生成

### Phase 3 — 打磨
- [ ] 断线自动重连
- [ ] 多服务器快速切换
- [ ] 横屏优化
- [ ] 字体大小调节
