@echo off
REM AgentPilot AI bot bridge: phone App <-> relay <-> local AI CLI (like feishu bot)
REM 你的电脑已装 Claude Code，默认用它。改 --ai 那行可换成 Codex：
REM   Claude Code:  --ai "claude -p {message}"
REM   Codex:        --ai "codex exec {message}"   (需先 npm install -g @openai/codex)
cd /d "%~dp0"
set NO_PROXY=192.168.2.250,127.0.0.1,localhost
python ai_bot.py --relay http://192.168.2.250:8861 --name WorkBuddy --ai "claude -p {message}"
pause
