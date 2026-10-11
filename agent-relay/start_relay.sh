#!/usr/bin/env bash
# AgentPilot 独立中继服务（端口 8861，独立于开饭小助手的 8860）
cd "$(dirname "$0")"
python agent_relay/relay_server.py --port 8861 "$@"
