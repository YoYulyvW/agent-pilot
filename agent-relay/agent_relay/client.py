"""中继客户端（纯标准库，零依赖）。

与 `relay_server.py`（kai-fan-le-helper 内置）协议完全兼容：

  POST /relay/register   -> relayToken
  POST /relay/send       -> 发送
  GET  /relay/poll       -> 长轮询
  POST /relay/ack        -> 确认
  GET  /relay/devices    -> 在线设备
  POST /relay/unregister -> 注销

消息信封（type = "agent"）：
  payload = {
    "v": 1,
    "kind": "text" | "tool" | "task" | "attachment",
    "text": "...",
    "messageId": "...",   # 业务 id：相同 id = 更新原消息（edit），不刷屏
    "toolName": "...", "toolState": "running|done|failed",
    "taskId": "...", "taskTitle": "...", "taskStatus": "...", "taskDetail": "...",
    "progress": 0.5,
    "agentId": "...", "agentName": "...",
    "ts": 1728600000
  }
"""
import base64
import json
import os
import time
import uuid
import urllib.request

DEFAULT_TTL_HOURS = 24
MAX_INLINE_BYTES = 150_000


class RelayError(Exception):
    pass


class RelayClient:
    def __init__(self, base_url, device_id=None, device_name="Agent",
                 platform="agent", bark_key="", config_path=None):
        self.base_url = base_url.rstrip("/")
        self.device_name = device_name
        self.platform = platform
        self.bark_key = bark_key
        self.config_path = config_path or os.path.expanduser("~/.agentrelay.json")
        self.device_id = device_id or self._load_device_id()
        self.token = ""

    # ---------- 配置持久化 ----------
    def _load_device_id(self):
        try:
            with open(self.config_path, encoding="utf-8") as f:
                data = json.load(f)
            if data.get("deviceId"):
                return data["deviceId"]
        except (OSError, ValueError):
            pass
        did = "agent-" + uuid.uuid4().hex[:16]
        try:
            with open(self.config_path, "w", encoding="utf-8") as f:
                json.dump({"deviceId": did}, f)
        except OSError:
            pass
        return did

    # ---------- HTTP 基础 ----------
    def _api(self, path, method="GET", body=None, auth=True, timeout=60):
        url = self.base_url + path
        data = json.dumps(body).encode("utf-8") if body is not None else None
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("Content-Type", "application/json; charset=utf-8")
        req.add_header("Accept", "application/json")
        req.add_header("User-Agent", "AgentRelay/1.0")
        if auth and self.token:
            req.add_header("Authorization", "Bearer " + self.token)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                raw = r.read().decode("utf-8").strip()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            body_text = ""
            try:
                body_text = e.read().decode("utf-8", "ignore")[:200]
            except Exception:
                pass
            raise RelayError("HTTP %s %s: %s" % (method, path, body_text or e.reason))
        except Exception as e:
            raise RelayError("%s %s: %s" % (method, path, e))

    # ---------- 协议方法 ----------
    def register(self):
        resp = self._api("/relay/register", "POST", {
            "deviceId": self.device_id,
            "deviceName": self.device_name,
            "platform": self.platform,
            "pushMode": "poll",
            "version": "1.0.0",
        }, auth=False)
        if not resp.get("ok") or not resp.get("relayToken"):
            raise RelayError("注册失败: %s" % resp)
        self.token = resp["relayToken"]
        return self.token

    def send(self, to, payload, type_="agent", ttl_hours=DEFAULT_TTL_HOURS):
        resp = self._api("/relay/send", "POST", {
            "to": to, "type": type_, "ttlHours": ttl_hours, "payload": payload,
        })
        return resp.get("ok") is True

    def poll(self, timeout=25):
        resp = self._api("/relay/poll?timeout=%d" % max(1, min(timeout, 30)))
        return resp.get("messages", []) if resp.get("ok") else []

    def ack(self, message_ids):
        if not message_ids:
            return
        self._api("/relay/ack", "POST", {"messageIds": list(message_ids)})

    def devices(self):
        resp = self._api("/relay/devices")
        return resp.get("devices", []) if resp.get("ok") else []

    def unregister(self):
        try:
            self._api("/relay/unregister", "POST", {})
        except RelayError:
            pass

    # ---------- 高层封装 ----------
    def _base_payload(self, **extra):
        p = {
            "v": 1,
            "agentId": self.device_id,
            "agentName": self.device_name,
            "senderId": self.device_id,
            "senderName": self.device_name,
            "ts": time.time(),
        }
        p.update(extra)
        return p

    def resolve_target(self, to):
        """'phone'/'ios' 自动解析为第一个 iOS 设备；否则当作 deviceId。"""
        if to in ("phone", "ios", "auto"):
            for d in self.devices():
                if d.get("platform") == "ios":
                    return d["deviceId"]
            raise RelayError("未找到 iOS 设备（手机 App 未连接中继？）")
        return to

    def send_text(self, to, text, message_id=None):
        payload = self._base_payload(kind="text", text=text)
        if message_id:
            payload["messageId"] = message_id
        return self.send(self.resolve_target(to), payload)

    def send_tool(self, to, message_id, tool_name, state, text):
        """工具调用状态。相同 message_id 会更新（edit）原消息。"""
        payload = self._base_payload(
            kind="tool", messageId=message_id, toolName=tool_name,
            toolState=state, text=text,
        )
        return self.send(self.resolve_target(to), payload)

    def send_task(self, to, task_id, title, status="pending", progress=0.0, detail=""):
        payload = self._base_payload(
            kind="task", taskId=task_id, taskTitle=title,
            taskStatus=status, progress=progress, taskDetail=detail,
            text=title,
        )
        return self.send(self.resolve_target(to), payload)

    def send_attachment(self, to, path, kind="file", mime=None, name=None):
        with open(path, "rb") as f:
            data = f.read()
        name = name or os.path.basename(path)
        mime = mime or _guess_mime(name)
        att = {"id": uuid.uuid4().hex, "kind": kind, "name": name,
               "mime": mime, "size": len(data)}
        if len(data) <= MAX_INLINE_BYTES:
            att["data"] = base64.b64encode(data).decode()
        else:
            raise RelayError("文件 %d 字节超过内联上限 %d，需配置文件服务器" % (len(data), MAX_INLINE_BYTES))
        payload = self._base_payload(kind="attachment", text="", attachments=[att])
        return self.send(self.resolve_target(to), payload)

    def wait_reply(self, timeout=60, ack=True):
        """长轮询等待手机回复，返回 payload 列表（仅 type=agent 且来自他人）。"""
        deadline = time.time() + timeout
        replies = []
        while time.time() < deadline:
            msgs = self.poll(timeout=25)
            ack_ids = []
            for m in msgs:
                if m.get("type") != "agent":
                    continue
                if m.get("from") == self.device_id:
                    ack_ids.append(m.get("messageId"))
                    continue
                replies.append(m.get("payload") or {})
                ack_ids.append(m.get("messageId"))
            if ack and ack_ids:
                self.ack(ack_ids)
            if replies:
                return replies
            time.sleep(0.5)
        return replies


def _guess_mime(name):
    ext = os.path.splitext(name)[1].lower()
    return {
        ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png",
        ".gif": "image/gif", ".pdf": "application/pdf", ".txt": "text/plain",
        ".md": "text/markdown", ".json": "application/json", ".zip": "application/zip",
    }.get(ext, "application/octet-stream")
