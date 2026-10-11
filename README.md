# AgentPilot · 智能体控制台（iOS）

为各种智能体（WorkBuddy、CodeAgent、Claude 等）构建的**远程消息控制台**：

- 📡 **远程接收消息**：通过自建中继（`relay_server.py`）长轮询接收智能体推送
- 💬 **回复消息**：会话窗口直接回复，消息原路送回智能体
- 🖼 **收发图片 / 文件**：相册选图发送、文件选取发送；接收到的图片可保存相册、文件可预览/分享
- ✅ **盯紧开发任务**：智能体推送任务状态（进行中/受阻/完成），侧栏查看总体进度
- 🗂 **侧栏会话窗口**：`NavigationSplitView` 侧栏选择会话，未读角标 + 在线状态
- 📱 iOS 16.4+ · **免签名** · **TrollStore 安装** · GitHub Actions 云端构建

## 消息协议（复用 relay_server.py）

手机注册为中继设备（`platform: ios`），智能体（电脑端）同样注册为设备。消息信封：

```jsonc
// POST /relay/send
{
  "to": "<手机deviceId>",
  "type": "agent",
  "payload": {
    "v": 1,
    "kind": "text",              // text | attachment | task | taskList | status
    "text": "构建完成",
    "agentId": "<智能体deviceId>",
    "agentName": "WorkBuddy",
    "ts": 1728600000,
    // 附件（可选）：
    "attachments": [
      {
        "id": "a1", "kind": "image",           // image | file
        "name": "screen.jpg", "mime": "image/jpeg", "size": 12345,
        "data": "<base64>"                      // 小文件内联；大文件用 "url" 替代
      }
    ],
    // 任务（kind=task 时）：
    "taskId": "t-1", "taskTitle": "iOS 客户端接入",
    "taskStatus": "running",                    // pending|running|blocked|done|failed
    "progress": 0.8
  }
}
```

### 附件与体积

- **小文件（≤ 150 KB）**：`data` 字段 base64 内联，直接走中继转发（中继单条上限 256 KB）。
- **大文件**：先在「设置」里配置**文件服务器地址**（multipart `POST` 上传，返回 `{"ok":true,"url":"..."}`），App 上传后改用 `url` 字段发送。
- **图片发送**：App 自动压缩（最长边 ≤ 1600、渐进降质量）到内联上限以内。
- 手机回复同样以 `type: "agent"` 发回智能体的 deviceId。

## 对接智能体（WorkBuddy / Codex / Claude Code / Cursor）

见 [`agent-relay/`](agent-relay/)——零依赖 Python SDK（CLI + 可选 MCP server）。智能体注册为中继上的 `platform:agent` 设备，即可收发消息、推任务、发文件。

```bash
# 列设备 / 发消息 / 工具进度 / 任务状态 / 等回复
python -m agent_relay --relay http://127.0.0.1:8860 --name WorkBuddy devices
python -m agent_relay --relay http://127.0.0.1:8860 --name Codex tool m1 xcodebuild running "构建中…"
python -m agent_relay --relay http://127.0.0.1:8860 --name Codex tool m1 xcodebuild done "构建完成"
```

### Edit 消息（工具进度不刷屏）

同一条工具调用**复用同一个 `messageId`**，App 端检测到相同 id 就**原地更新**原消息（running 转圈 → done ✓ / failed ✗），而不是新发一条。`kind: "tool"` + `toolName` + `toolState` 字段：

```jsonc
{ "type": "agent", "payload": {
    "v": 1, "kind": "tool",
    "messageId": "m1", "toolName": "read_file", "toolState": "done", "text": "已读取（120 行）",
    "agentId": "agent-xxx", "agentName": "Codex", "ts": 1728600000
}}
```

## 构建（GitHub Actions · 单公开库）

1. 推送到 GitHub 公开仓库（见 `tools/push.py`）
2. Actions 自动构建（push 到 main 触发，也可手动运行 **Build AgentPilot**）
3. 构建完成后 IPA 自动提交回本仓库 `dist/`，生成直链：
   `https://raw.githubusercontent.com/YoYulyvW/agent-pilot/main/dist/AgentPilot.ipa`
4. iPhone 用 Safari 打开该直链下载，**TrollStore 直接安装**（免签名）
   （备用：Actions 的 Artifacts 里也能下载 `AgentPilot.ipa`）

## 本地构建

```bash
brew install xcodegen
xcodegen generate
open AgentPilot.xcodeproj
```

## 中继服务

复用 `kai-fan-le-helper` 内置的 `relay_server.py`（端口 8860），配合 frp / CF Tunnel 暴露公网。
App「设置」里填中继地址即可连接；未配置时展示演示数据。

## 目录结构

```
AgentPilot/
  App.swift                     入口
  Models/Models.swift           会话 / 消息 / 附件 / 任务模型
  Services/RelayTransport.swift 中继协议客户端（register/send/poll/ack）
  Services/Store.swift          全局状态 + 持久化
  Services/AttachmentHelper.swift 图片压缩 / MIME 工具
  Views/RootView.swift          NavigationSplitView 骨架
  Views/SidebarView.swift       侧栏会话列表
  Views/ChatView.swift          聊天 + 附件收发
  Views/TaskListView.swift      开发任务监控
  Views/SettingsView.swift      中继 / 文件服务器配置
```
