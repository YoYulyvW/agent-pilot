"""命令行入口：任何智能体通过 Bash/exec 调用本 CLI 与手机 App 通信。

示例：
  agentrelay --relay http://127.0.0.1:8860 --name WorkBuddy devices
  agentrelay --relay http://127.0.0.1:8860 --name WorkBuddy send phone "构建完成"
  agentrelay --relay http://127.0.0.1:8860 --name Codex tool m1 read_file running "读取中"
  agentrelay --relay http://127.0.0.1:8860 --name Codex tool m1 read_file done "读取完成"   # 同 m1 = edit
  agentrelay --relay http://127.0.0.1:8860 --name WorkBuddy task t1 "部署" --status running --progress 0.5
  agentrelay --relay http://127.0.0.1:8860 --name WorkBuddy listen --timeout 120
"""
import argparse
import sys

from .client import RelayClient, RelayError


def _new_client(args):
    return RelayClient(args.relay, device_name=args.name)


def cmd_devices(args):
    c = _new_client(args)
    c.register()
    devs = c.devices()
    if not devs:
        print("(无在线设备)")
        return
    for d in devs:
        print("%s  %s  platform=%s  online=%s" % (
            d.get("deviceId"), d.get("deviceName"),
            d.get("platform"), d.get("online")))


def cmd_send(args):
    c = _new_client(args)
    c.register()
    ok = c.send_text(args.to, args.text, message_id=args.message_id)
    print("OK" if ok else "FAIL")


def cmd_tool(args):
    c = _new_client(args)
    c.register()
    ok = c.send_tool(args.to, args.message_id, args.tool_name, args.state, args.text)
    print("OK" if ok else "FAIL")


def cmd_task(args):
    c = _new_client(args)
    c.register()
    ok = c.send_task(args.to, args.task_id, args.title, args.status, args.progress, args.detail)
    print("OK" if ok else "FAIL")


def cmd_listen(args):
    c = _new_client(args)
    c.register()
    print("监听中（%ds）…" % args.timeout, file=sys.stderr)
    replies = c.wait_reply(timeout=args.timeout)
    for p in replies:
        text = p.get("text") or ""
        sender = p.get("senderName") or "手机"
        print("[%s] %s" % (sender, text))


def cmd_file(args):
    c = _new_client(args)
    c.register()
    ok = c.send_attachment(args.to, args.path)
    print("OK" if ok else "FAIL")


def build_parser():
    p = argparse.ArgumentParser(prog="agentrelay",
                                description="让智能体接入自建中继，与手机 App 通信")
    p.add_argument("--relay", required=True, help="中继地址，如 http://127.0.0.1:8860")
    p.add_argument("--name", default="Agent", help="智能体名称（显示在手机上）")

    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("devices", help="列出中继上的设备")
    s.set_defaults(func=cmd_devices)

    s = sub.add_parser("send", help="发文本消息")
    s.add_argument("to", help="目标 deviceId，或 phone（自动选 iOS 设备）")
    s.add_argument("text", help="消息内容")
    s.add_argument("--message-id", dest="message_id", default=None,
                   help="业务 id，相同 id 会更新原消息")
    s.set_defaults(func=cmd_send)

    s = sub.add_parser("tool", help="工具调用状态（相同 message_id 自动 edit 原消息）")
    s.add_argument("message_id", help="稳定 id，同一工具调用复用")
    s.add_argument("tool_name", help="工具名，如 read_file")
    s.add_argument("state", choices=["running", "done", "failed"], help="状态")
    s.add_argument("text", help="描述/结果")
    s.add_argument("--to", default="phone", help="目标，默认 phone")
    s.set_defaults(func=cmd_tool)

    s = sub.add_parser("task", help="开发任务状态")
    s.add_argument("task_id", help="任务 id")
    s.add_argument("title", help="任务标题")
    s.add_argument("--status", default="pending",
                   choices=["pending", "running", "blocked", "done", "failed"])
    s.add_argument("--progress", type=float, default=0.0)
    s.add_argument("--detail", default="")
    s.add_argument("--to", default="phone")
    s.set_defaults(func=cmd_task)

    s = sub.add_parser("listen", help="长轮询接收手机回复")
    s.add_argument("--timeout", type=int, default=60)
    s.set_defaults(func=cmd_listen)

    s = sub.add_parser("file", help="发文件（内联，≤150KB）")
    s.add_argument("path", help="文件路径")
    s.add_argument("--to", default="phone")
    s.set_defaults(func=cmd_file)

    return p


def main(argv=None):
    args = build_parser().parse_args(argv)
    try:
        args.func(args)
    except RelayError as e:
        print("错误: %s" % e, file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
