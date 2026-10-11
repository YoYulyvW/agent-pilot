"""AI 机器人桥接服务：手机 App ↔ 中继 ↔ 本地 AI CLI

对齐 cc-feishu-connector 的架构，但 IM 通道换成自建中继 + AgentPilot App。

用法：
  python ai_bot.py --relay http://192.168.2.250:8861 --name WorkBuddy \
      --ai "codex exec {message}"        # 或 "claude -p {message}"

AI 命令模板用 {message} 占位符，例如：
  --ai "claude -p {message}"             # Claude Code 非交互模式
  --ai "codex exec {message}"            # OpenAI Codex CLI
  --ai "cuckoo {message}"                # 任意支持命令行调用的 AI

循环逻辑：
  1. 长轮询中继，接收手机发来的消息
  2. 用 tool 消息把「AI 思考中」推给手机（running → done，edit 不刷屏）
  3. 调用本地 AI CLI 处理（维护每个会话的上下文）
  4. 把 AI 回复发回手机
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from agent_relay.client import RelayClient  # noqa: E402


class AiBot:
    def __init__(self, relay, name, ai_cmd, timeout=300):
        self.client = RelayClient(relay, device_name=name)
        self.ai_cmd = ai_cmd
        self.timeout = timeout
        # 每个会话（手机 deviceId）维护上下文（最近的对话记录）
        self.contexts = {}  # phone_id -> list of {"role": "user"/"assistant", "text": str}
        self.ack_ids = set()

    def run(self):
        self.client.register()
        print("AI 机器人已启动：中继 %s，AI 命令: %s" % (self.client.base_url, self.ai_cmd))
        print("Ctrl+C 停止")
        while True:
            try:
                msgs = self.client.poll(timeout=25)
                for m in msgs:
                    self.handle(m)
            except KeyboardInterrupt:
                print("已停止")
                break
            except Exception as e:
                print("轮询错误: %s，3 秒后重试" % e)
                time.sleep(3)

    def handle(self, m):
        if m.get("type") != "agent":
            self.client.ack([m.get("messageId")])
            return
        phone_id = m.get("from") or ""
        text = (m.get("payload") or {}).get("text") or ""
        mid = m.get("messageId")
        if not text.strip():
            self.client.ack([mid])
            return

        # 推送「思考中」状态（tool running）
        self.client.send_tool(phone_id, mid, "AI 处理", "running", "正在思考…")
        self.client.ack([mid])

        # 调本地 AI
        reply = self.call_ai(phone_id, text)

        # 回复（tool done edit + 文本回复）
        self.client.send_tool(phone_id, mid, "AI 处理", "done", "已回复")
        if reply:
            self.client.send_text(phone_id, reply)
        print("[%s] 回复 %s: %s" % (time.strftime("%H:%M:%S"), m.get("fromName"), reply[:60]))

    def call_ai(self, phone_id, text):
        """调用本地 AI CLI。维护简单上下文（拼成多轮 prompt）。"""
        hist = self.contexts.setdefault(phone_id, [])
        # 构造 prompt：带上最近几轮上下文
        if hist:
            ctx = "\n".join("%s: %s" % (h["role"], h["text"]) for h in hist[-6:])
            prompt = "对话历史：\n%s\n\n用户最新消息：%s\n请回复。" % (ctx, text)
        else:
            prompt = text
        cmd = self.ai_cmd.replace("{message}", prompt)
        try:
            r = subprocess.run(
                cmd, shell=True, capture_output=True, text=True,
                timeout=self.timeout, encoding="utf-8", errors="replace",
            )
            reply = (r.stdout or "").strip() or (r.stderr or "").strip()
        except subprocess.TimeoutExpired:
            reply = "（AI 处理超时 %ds）" % self.timeout
        except Exception as e:
            reply = "（调用 AI 失败：%s）" % e
        # 记录上下文
        hist.append({"role": "user", "text": text})
        hist.append({"role": "assistant", "text": reply})
        if len(hist) > 20:
            hist[:] = hist[-20:]
        return reply


def main():
    p = argparse.ArgumentParser(description="AgentPilot AI 机器人桥接")
    p.add_argument("--relay", default="http://127.0.0.1:8861")
    p.add_argument("--name", default="WorkBuddy")
    p.add_argument("--ai", required=True, help="AI 命令模板，用 {message} 占位，如 'claude -p {message}'")
    p.add_argument("--timeout", type=int, default=300)
    args = p.parse_args()
    AiBot(args.relay, args.name, args.ai, args.timeout).run()


if __name__ == "__main__":
    main()
