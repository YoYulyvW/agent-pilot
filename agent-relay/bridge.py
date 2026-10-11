"""常驻监听桥接：持续 poll 中继，把手机发来的消息实时落地到 inbox.log。

用法：
  python bridge.py --relay http://192.168.2.250:8861 --name WorkBuddy

收到手机消息后：
  1. ack（确认收到，中继不再重复投递）
  2. 追加写入同目录 inbox.log（供 WorkBuddy 定时/手动处理）
"""
import argparse
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from agent_relay.client import RelayClient  # noqa: E402

INBOX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "inbox.log")


def main():
    p = argparse.ArgumentParser(description="AgentPilot 常驻监听桥接")
    p.add_argument("--relay", default="http://127.0.0.1:8861")
    p.add_argument("--name", default="WorkBuddy")
    args = p.parse_args()

    c = RelayClient(args.relay, device_name=args.name)
    c.register()
    print("监听中继 %s（智能体 %s），手机消息会实时写入 inbox.log" % (args.relay, args.name))
    print("Ctrl+C 停止")

    seen = set()
    while True:
        try:
            msgs = c.poll(timeout=25)
            for m in msgs:
                if m.get("type") != "agent":
                    continue
                mid = m.get("messageId")
                if mid in seen:
                    continue
                seen.add(mid)
                from_id = m.get("from") or ""
                from_name = m.get("fromName") or ""
                text = (m.get("payload") or {}).get("text") or ""
                record = {
                    "time": time.time(),
                    "iso": time.strftime("%Y-%m-%d %H:%M:%S"),
                    "messageId": mid,
                    "from": from_id,
                    "fromName": from_name,
                    "text": text,
                }
                with open(INBOX, "a", encoding="utf-8") as f:
                    f.write(json.dumps(record, ensure_ascii=False) + "\n")
                c.ack([mid])
                print("[%s] 收到 %s: %s" % (record["iso"], from_name, text))
        except KeyboardInterrupt:
            print("已停止")
            break
        except Exception as e:
            print("轮询错误: %s，3 秒后重试" % e)
            time.sleep(3)


if __name__ == "__main__":
    main()
