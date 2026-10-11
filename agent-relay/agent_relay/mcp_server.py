"""MCP server：让支持 MCP 的智能体（Codex / Claude Code / Cursor 等）直接通过工具调用对接手机 App。

依赖：pip install mcp

配置（环境变量）：
  AGENT_RELAY_URL   中继地址，如 http://127.0.0.1:8860
  AGENT_RELAY_NAME  智能体名称

在 agent 的 MCP 配置里加：
  {
    "mcpServers": {
      "agent-relay": {
        "command": "python", "args": ["-m", "agent_relay.mcp_server"],
        "env": {"AGENT_RELAY_URL": "http://127.0.0.1:8860", "AGENT_RELAY_NAME": "Codex"}
      }
    }
  }
"""
import os

from mcp.server.fastmcp import FastMCP

from .client import RelayClient, RelayError

mcp = FastMCP("agent-relay")

_client = None


def _get_client():
    global _client
    if _client is None:
        url = os.environ.get("AGENT_RELAY_URL", "")
        name = os.environ.get("AGENT_RELAY_NAME", "Agent")
        if not url:
            raise RelayError("未设置 AGENT_RELAY_URL")
        _client = RelayClient(url, device_name=name)
    if not _client.token:
        _client.register()
    return _client


def _reconnect():
    global _client
    _client = None
    return _get_client()


@mcp.tool()
def list_devices() -> str:
    """列出中继上的设备（含手机），返回 deviceId / 名称 / 平台 / 在线状态。"""
    c = _get_client()
    devs = c.devices()
    if not devs:
        return "(无在线设备)"
    lines = []
    for d in devs:
        lines.append("%s | %s | %s | online=%s" % (
            d.get("deviceId"), d.get("deviceName"),
            d.get("platform"), d.get("online")))
    return "\n".join(lines)


@mcp.tool()
def send_message(to: str, text: str) -> str:
    """发送一条文本消息到手机。to 传 deviceId，或传 'phone' 自动选中 iOS 设备。"""
    c = _get_client()
    try:
        ok = c.send_text(to, text)
        return "OK" if ok else "FAIL"
    except RelayError as e:
        _reconnect()
        ok = c.send_text(to, text)
        return ("OK" if ok else "FAIL") + (" (重连后)" if ok else "")


@mcp.tool()
def tool_update(message_id: str, tool_name: str, state: str, text: str) -> str:
    """工具调用进度。state 为 running/done/failed。同一个 message_id 会原地更新（edit）同一条消息，不要每次新发。"""
    c = _get_client()
    ok = c.send_tool("phone", message_id, tool_name, state, text)
    return "OK" if ok else "FAIL"


@mcp.tool()
def task_update(task_id: str, title: str, status: str, progress: float, detail: str = "") -> str:
    """开发任务状态。status: pending/running/blocked/done/failed，progress 0~1。"""
    c = _get_client()
    ok = c.send_task("phone", task_id, title, status, progress, detail)
    return "OK" if ok else "FAIL"


@mcp.tool()
def wait_reply(timeout: int = 60) -> str:
    """长轮询等待手机回复，返回回复内容（多条用换行分隔），超时返回空。"""
    c = _get_client()
    replies = c.wait_reply(timeout=timeout)
    if not replies:
        return ""
    return "\n".join(p.get("text") or "" for p in replies)


@mcp.tool()
def send_file(path: str) -> str:
    """发送本地文件到手机（内联，≤150KB）。"""
    c = _get_client()
    ok = c.send_attachment("phone", path)
    return "OK" if ok else "FAIL"


def main():
    mcp.run()


if __name__ == "__main__":
    main()
