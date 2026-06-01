# OpenCode Mobile — Project Context for AI Agents

> 通过 SSH 协议在手机上使用 opencode AI 编程助手的 Flutter App

---

## 项目定位

这是一个 **Flutter 移动端 App**（iOS + Android），让用户能在手机上连接自己的服务器并使用 opencode AI 编程助手。

**不是**终端模拟器，**不是** SSH 客户端工具箱——它是专门为 opencode 设计的原生移动 UI。

---

## 核心工作原理

```
手机 App
  1. SSH 连接用户服务器（密码认证）
  2. 远端执行：opencode serve --port 4096
  3. SSH 本地端口转发：localhost:14096 → 远端:4096
  4. 通过 HTTP REST API + SSE 与 opencode 通信
  5. 原生 Flutter UI 展示对话、Diff、权限审批
```

opencode 有完整的 HTTP API（OpenAPI 3.1），无需解析终端 escape 序列。

---

## 项目结构

```
lib/
├── main.dart
├── core/
│   ├── ssh/                    # SSH 连接 + 端口转发（dartssh2）
│   ├── api/                    # opencode HTTP 客户端（Dio + SSE）
│   │   └── models/             # API 数据模型
│   └── storage/                # 服务器配置安全存储
├── features/
│   ├── servers/                # 服务器 CRUD 管理
│   ├── connection/             # 连接流程 + 动画
│   ├── sessions/               # opencode 会话列表
│   └── chat/                   # 对话主界面（核心功能）
│       └── widgets/            # message_bubble, diff_card, permission_sheet 等
└── shared/                     # 主题、通用组件
```

完整设计见 `DESIGN.md`，UI 原型见 `prototype.html`。

---

## 关键依赖

| 包 | 用途 |
|----|------|
| `dartssh2` | SSH 连接 + 本地端口转发 |
| `dio` | HTTP 客户端 |
| `flutter_secure_storage` | SSH 密码加密存储（Keychain/Keystore）|
| `riverpod` | 状态管理 |
| `go_router` | 路由导航 |
| `flutter_markdown` | AI 回复 Markdown 渲染 |
| `flutter_highlight` | 代码块语法高亮 |
| `diff_match_patch` | Diff 预览渲染 |

---

## opencode API 速查

服务端地址：`http://localhost:14096`（SSH 端口转发后的本地地址）

```
# 会话
GET    /session                          会话列表
POST   /session                          新建会话 { title? }
DELETE /session/:id                      删除会话

# 消息
GET    /session/:id/message              历史消息列表
POST   /session/:id/prompt_async         发送消息（异步，通过 SSE 接收回复）
POST   /session/:id/abort                中止当前生成
POST   /session/:id/revert               撤销最后一条消息

# 权限审批（AI 执行 bash/写文件前需要用户批准）
POST   /session/:id/permissions/:permId  { decision: "allow"|"deny", permanent: bool }

# 实时事件
GET    /event                            SSE 全局事件流
```

### SSE 事件类型

```
session.updated      AI 回复生成中
session.message      消息完成
tool.execution       工具被调用（bash/read_file/write_file 等）
permission.requested 需要用户审批（触发 PermissionSheet）
session.error        发生错误
```

---

## 数据模型

### ServerConfig（本地）
```dart
class ServerConfig {
  String id;
  String name;
  String host;
  int sshPort;        // 默认 22
  String username;
  String password;    // 存于 Keychain，不明文
  int opencodePort;   // 默认 4096，转发到本地 14096+
  DateTime? lastConnected;
}
```

### 本地端口分配规则
- 第一个服务器用 `14096`，第二个 `14097`，以此类推
- 避免与用户本机 opencode 实例冲突

---

## 状态管理（Riverpod）

```dart
serverListProvider              // List<ServerConfig>
connectionProvider(serverId)    // ConnectionState（连接中/已连接/断开）
sessionListProvider             // opencode 会话列表
chatProvider(sessionId)         // 消息列表 + 发送状态
pendingPermissionProvider       // 待审批权限请求队列
sseEventProvider                // Stream<OpencodeEvent>
```

---

## UI 页面与职责

| 页面 | 文件 | 职责 |
|------|------|------|
| 服务器列表 | `servers/server_list_screen.dart` | 首页，展示已配置服务器 |
| 添加服务器 | `servers/server_form_screen.dart` | 表单 CRUD |
| 连接中 | `connection/connecting_screen.dart` | SSH + 启动动画 |
| 会话列表 | `sessions/session_list_screen.dart` | opencode 会话 |
| 对话界面 | `chat/chat_screen.dart` | **核心页面**，AI 对话 |

### Chat 界面关键 Widget

- `MessageBubble` — 用户/AI 消息气泡，AI 侧支持 Markdown
- `ToolExecutionCard` — 工具调用折叠卡片，可展开查看命令和输出
- `DiffPreviewCard` — 文件变更预览，红绿高亮 + 接受/拒绝按钮
- `PermissionSheet` — 底部抽屉，审批 bash/文件操作权限
- `ChatInputBar` — 输入框 + 附件 + 发送，自适应高度

---

## 编码约定

### 命名
- 文件：`snake_case.dart`
- 类：`PascalCase`
- Provider：以 `Provider` 结尾，如 `chatProvider`
- Widget：以 `Screen`（页面）或 `Widget`/具体名称（组件）结尾

### 错误处理
- SSH 连接失败 → 返回服务器列表，显示 SnackBar 错误
- API 请求失败 → 局部错误状态，不崩溃全局
- SSE 断连 → 自动重试 3 次，失败后提示用户重连

### 安全规则
- 密码**必须**通过 `flutter_secure_storage` 存储，禁止 `SharedPreferences`
- opencode 端口**不得**直接暴露，必须走 SSH 隧道访问
- 日志**不得**打印密码、SSH 私钥等敏感信息

---

## 开发阶段

### Phase 1（MVP）
SSH 连接 → 服务器配置 → 会话列表 → 发送消息 → 流式回复渲染

### Phase 2
权限审批 → Diff 预览 → 工具执行卡片 → 撤销/中止

### Phase 3
断线重连 → 横屏优化 → 多服务器切换 → 字体缩放

---

## 参考资料

- opencode 官方文档：https://opencode.ai/docs/
- opencode Server API：https://opencode.ai/docs/server/
- dartssh2 文档：https://pub.dev/packages/dartssh2
- 设计文档：`DESIGN.md`
- UI 原型：`prototype.html`（浏览器打开）
