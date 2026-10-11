# Cuckoo-Code → 手机（AgentPilot）中继补丁

把 Cuckoo-Code 的「飞书推送」改造成「推送到你的手机 App」。原理：用一个中继版客户端替换掉 Cuckoo-Code 里的飞书客户端（`out/src/feishu/client.js`），接口不变，底层从飞书 API 换成中继 API。

## 效果

Cuckoo-Code 里的一切实时推送到手机 AgentPilot：
- 👤 用户消息
- 🤖 AI 回复
- 🔧 工具调用（running → done/failed，手机端同一条卡片更新，不刷屏）
- 📎 文件（AI 用 sendToFeishu 工具发的文件 → 发到手机）

手机发消息 → Cuckoo-Code 的 AI 收到并回复（双向）。

## 三步接入

### 1. 改配置 `~/.cuckoo/feishu.json`

在原有基础上加两个字段：

```json
{
  "appId": "cli_aa4a023b8b38dd25",
  "appSecret": "x4bNIcM18GMlCIH0nH7ysbO13uLLnTAw",
  "enabled": true,
  "targetOpenId": "C2CF6B60-F981-483D-9960-DD2D6A5ABB10",
  "relayUrl": "http://192.168.2.250:8861",
  "agentName": "Cuckoo-Code",
  "pushUserMessage": true,
  "pushAiReply": true,
  "pushToolStatus": true,
  "pushToolName": true
}
```

- `relayUrl`：你的中继地址（端口 8861）
- `targetOpenId`：复用为手机 deviceId（就是 `C2CF6B60-F981-483D-9960-DD2D6A5ABB10`）

### 2. 打补丁（先退出 Cuckoo-Code）

```powershell
powershell -ExecutionPolicy Bypass -File "D:\编程\agent-pilot\agent-relay\relay-cuckoo-patch\apply-relay.ps1"
```

### 3. 重启 Cuckoo-Code + 确保中继在跑

```bash
# 中继（没在跑的话）
python D:\编程\agent-pilot\agent-relay\agent_relay\relay_server.py --port 8861
```

## 回滚

打补丁时已备份：
- `out/src/feishu/client.js.feishu.bak`（原飞书客户端）
- `app.asar.bak`（原 asar）

恢复：删掉当前 `app.asar`，把 `app.asar.bak` 改回 `app.asar`。

## 和 Codex / WorkBuddy 共存

- **Cuckoo-Code**：本补丁（自动推送对话流 + 双向）
- **Codex**：`ai_bot.py --ai "codex exec {message}"`（手机发消息自动回复）
- **WorkBuddy（我）**：干活时用 agent-relay CLI 推送到手机

三个智能体用不同的 `agentName`，手机 App 侧栏就是三个会话。
