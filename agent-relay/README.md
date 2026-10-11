# AgentRelay · 智能体接入 SDK

让任意智能体（**WorkBuddy / Codex / Claude Code / Cursor / ChatGPT Agent** …）接入你自建的中继服务，与手机上的 **AgentPilot App** 双向通信。

- 📤 发消息到手机、收手机回复
- 🔧 工具调用进度（**edit 原消息，不刷屏**）
- ✅ 开发任务状态推送
- 📎 发文件/图片

**零依赖**：核心 CLI 只用 Python 标准库，装个 Python 就能跑。

## 一、快速开始（CLI）

```bash
cd agent-relay

# 1. 列出中继上的设备（找到手机的 deviceId）
python -m agent_relay --relay http://127.0.0.1:8860 --name WorkBuddy devices

# 2. 发文本消息（phone = 自动选 iOS 设备）
python -m agent_relay --relay http://127.0.0.1:8860 --name WorkBuddy send phone "构建完成 ✅"

# 3. 工具调用进度 —— 关键：同一个 message_id 就是「edit 原消息」
python -m agent_relay --relay http://127.0.0.1:8860 --name Codex tool m1 read_file running "正在读取 Config.swift"
python -m agent_relay --relay http://127.0.0.1:8860 --name Codex tool m1 read_file done "已读取（120 行）"

# 4. 任务状态
python -m agent_relay --relay http://127.0.0.1:8860 --name WorkBuddy task t1 "部署" --status running --progress 0.5
python -m agent_relay --relay http://127.0.0.1:8860 --name WorkBuddy task t1 "部署" --status done --progress 1.0

# 5. 等待手机回复（阻塞，直到收到回复或超时）
python -m agent_relay --relay http://127.0.0.1:8860 --name WorkBuddy listen --timeout 120
```

## 二、MCP 方式（Codex / Claude Code / Cursor 推荐）

```bash
pip install mcp
```

在 agent 的 MCP 配置里加：

```json
{
  "mcpServers": {
    "agent-relay": {
      "command": "python",
      "args": ["-m", "agent_relay.mcp_server"],
      "env": {
        "AGENT_RELAY_URL": "http://127.0.0.1:8860",
        "AGENT_RELAY_NAME": "Codex"
      }
    }
  }
}
```

工具：`send_message` / `tool_update` / `task_update` / `wait_reply` / `send_file` / `list_devices`。

## 三、Edit 消息机制（核心设计）

**同一条工具调用复用同一个 `messageId`**，App 端检测到相同 id 就**原地更新**原消息，而不是新发一条：

| 时刻 | 命令 | 手机端看到 |
|------|------|-----------|
| 工具开始 | `tool m1 read_file running "读取中…"` | `🔧 read_file`（转圈中）|
| 工具完成 | `tool m1 read_file done "读取完成"` | `✅ read_file`（同一条消息变绿）|

这样手机端不会被大量中间状态刷屏，像 Claude Code / ChatGPT 一样干净。

## 四、怎么对接 WorkBuddy（我自己）

WorkBuddy 通过 Bash 调用 CLI。你在对话里告诉我中继地址，我每次任务的关键节点（开始/完成/需要确认）用上面第 3 条命令发消息给你手机即可。也可以让我写一个 automation 定时汇报。

## 五、消息协议（payload 信封）

```jsonc
{ "type": "agent", "payload": {
    "v": 1,
    "kind": "text" | "tool" | "task" | "attachment",
    "text": "...",
    "messageId": "m1",          // 业务 id：相同 id = edit
    "toolName": "read_file", "toolState": "running|done|failed",
    "taskId": "t1", "taskTitle": "部署", "taskStatus": "running", "taskDetail": "", "progress": 0.5,
    "agentId": "agent-xxx", "agentName": "WorkBuddy",
    "ts": 1728600000
}}
```
